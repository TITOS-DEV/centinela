require("./tracing"); // debe cargarse antes que cualquier cliente de Azure

const express = require("express");
const { v4: uuidv4 } = require("uuid");
const { transactionsContainer } = require("./cosmosClient");
const { eventGridClient } = require("./eventGridClient");
const { validateTransaction } = require("./validateTransaction");
const { trackStage, trackFailure } = require("./tracing");

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 8080;

// Container Apps usa esto como liveness/readiness probe. No toca Cosmos ni
// Event Grid — si la app responde 200 aca, el proceso esta vivo; la salud de
// las dependencias se ve en Application Insights, no en el probe.
app.get("/healthz", (_req, res) => res.status(200).json({ status: "ok" }));

/**
 * POST /api/transactions
 *
 * Recibe, valida, persiste, publica el evento y responde. No calcula score,
 * no abre casos — eso lo hace scoring-engine, un contenedor separado que
 * reacciona al evento publicado aca. El cliente nunca espera al analisis
 * (restriccion central del proyecto: responder antes de terminar de analizar).
 */
app.post("/api/transactions", async (req, res) => {
  const requestStart = Date.now();
  const body = req.body;

  const validation = validateTransaction(body);
  if (!validation.valid) {
    return res.status(400).json({ error: "validacion fallida", details: validation.errors });
  }

  const transactionId = `txn_${uuidv4()}`;
  const receivedAt = new Date().toISOString();

  const document = {
    id: transactionId,
    accountId: body.accountId,
    amount: body.amount,
    currency: body.currency,
    type: body.type,
    channel: body.channel || "unknown",
    merchant: body.merchant || null,
    location: body.location,
    cardLast4: body.cardLast4 || null,
    originTimestamp: body.originTimestamp,
    receivedAt,
    status: "received",
    score: null,
    ruleTriggers: [],
  };

  // 1. Persistir. Escritura de una sola particion (accountId) — rapida, y es
  //    parte del acuse que le debemos al cliente, no el analisis lento.
  const persistStart = Date.now();
  try {
    await transactionsContainer.items.create(document);
  } catch (err) {
    trackFailure("ingest.persist", { transactionId, accountId: body.accountId, error: err });
    return res.status(500).json({ error: "no se pudo persistir la transaccion" });
  }
  trackStage("ingest.persist", {
    transactionId,
    accountId: body.accountId,
    durationMs: Date.now() - persistStart,
  });

  // 2. Publicar el evento liviano (solo IDs). El consumidor de scoring
  //    relee el documento completo desde Cosmos (docs/event-contract.md, s.3).
  const publishStart = Date.now();
  try {
    await eventGridClient.send([
      {
        eventType: "Centinela.Transaction.Created",
        subject: `transactions/${body.accountId}`,
        dataVersion: "1.0",
        data: { transactionId, accountId: body.accountId },
      },
    ]);
    trackStage("ingest.publish_event", {
      transactionId,
      accountId: body.accountId,
      durationMs: Date.now() - publishStart,
    });
  } catch (err) {
    // La transaccion YA esta persistida. Si falla la publicacion, no le
    // fallamos al cliente por eso, pero queda trazado: esa transaccion
    // quedaria sin analizar (mismo punto de fallo que documenta Semana 1).
    trackFailure("ingest.publish_event", { transactionId, accountId: body.accountId, error: err });
  }

  trackStage("ingest.request_total", {
    transactionId,
    accountId: body.accountId,
    durationMs: Date.now() - requestStart,
  });

  // 3. Responder de inmediato. El analisis corre aparte, de forma asincrona.
  return res.status(202).json({ transactionId, status: "received", receivedAt });
});

app.listen(PORT, () => {
  console.log(`ingest-api escuchando en el puerto ${PORT}`);
});
