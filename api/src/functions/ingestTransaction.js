const { app } = require("@azure/functions");
const { v4: uuidv4 } = require("uuid");
const { transactionsContainer } = require("../cosmosClient");
const { eventGridClient } = require("../eventGridClient");
const { validateTransaction } = require("../validateTransaction");

/**
 * POST /api/transactions
 *
 * Este endpoint es TODO lo que hace semana 1: recibe, valida, persiste, publica el evento
 * y responde. No calcula score, no abre casos — eso lo hace un consumidor separado en semana 2
 * que reacciona al evento publicado acá. El cliente nunca espera al analisis.
 */
app.http("ingestTransaction", {
  methods: ["POST"],
  authLevel: "function",
  route: "transactions",
  handler: async (request, context) => {
    let body;
    try {
      body = await request.json();
    } catch (err) {
      return { status: 400, jsonBody: { error: "body invalido, se esperaba JSON" } };
    }

    const validation = validateTransaction(body);
    if (!validation.valid) {
      return { status: 400, jsonBody: { error: "validacion fallida", details: validation.errors } };
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

    // 1. Persistir. Esta escritura es rapida (un solo documento, particion por accountId) y es
    //    parte del acuse que le debemos al cliente -- no es el analisis lento que se desacopla.
    try {
      await transactionsContainer.items.create(document);
    } catch (err) {
      context.error("Error al persistir en Cosmos:", err.message);
      return { status: 500, jsonBody: { error: "no se pudo persistir la transaccion" } };
    }

    // 2. Publicar el evento liviano. El consumidor de semana 2 relee el documento completo
    //    desde Cosmos usando transactionId + accountId (ver docs/event-contract.md, seccion 3).
    try {
      await eventGridClient.send([
        {
          eventType: "Centinela.Transaction.Created",
          subject: `transactions/${body.accountId}`,
          dataVersion: "1.0",
          data: {
            transactionId,
            accountId: body.accountId,
          },
        },
      ]);
    } catch (err) {
      // La transaccion YA esta persistida. Si falla la publicacion del evento, no le fallamos
      // al cliente por eso -- pero lo dejamos bien loggeado porque esa transaccion se quedaria
      // sin analizar. En semana 2/3 esto se resuelve con un job de reconciliacion que barre
      // documentos en estado "received" mas viejos que N minutos.
      context.error("Error al publicar evento (transaccion ya persistida):", err.message);
    }

    // 3. Responder de inmediato. El analisis (que todavia no existe en semana 1) corre aparte.
    return {
      status: 202,
      jsonBody: {
        transactionId,
        status: "received",
        receivedAt,
      },
    };
  },
});
