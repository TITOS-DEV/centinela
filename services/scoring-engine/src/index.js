require("./tracing"); // debe cargarse antes que cualquier cliente de Azure

const http = require("http");
const { createReceiver } = require("./serviceBusClient");
const { handleScoringMessage } = require("./workers/scoreWorker");
const { handleCaseMessage } = require("./workers/caseWorker");
const { handleExplainerMessage } = require("./workers/explainerWorker");
const { handleDocumentMessage } = require("./workers/documentWorker");

const PORT = process.env.PORT || 8080;

/**
 * Suscribe un receiver de Service Bus a un handler. peekLock: el mensaje se
 * completa explicitamente solo si el handler no lanza. Si lanza, se
 * abandona -- Service Bus lo reintenta hasta maxDeliveryCount (10, ver
 * servicebus.bicep) y despues lo manda a dead-letter en vez de perderlo.
 */
function subscribe(queueKey, handler, label) {
  const receiver = createReceiver(queueKey);

  receiver.subscribe({
    processMessage: async (message) => {
      try {
        await handler(message);
        await receiver.completeMessage(message);
      } catch (err) {
        console.error(`[${label}] error procesando mensaje, se abandona para reintento:`, err.message);
        await receiver.abandonMessage(message);
      }
    },
    processError: async (args) => {
      console.error(`[${label}] error del receiver:`, args.error.message);
    },
  });

  console.log(`[${label}] escuchando cola`);
  return receiver;
}

const receivers = [
  subscribe("scoring", handleScoringMessage, "score-worker"),
  subscribe("cases", handleCaseMessage, "case-worker"),
  subscribe("explainer", handleExplainerMessage, "explainer-worker"),
  subscribe("documents", handleDocumentMessage, "document-worker"),
];

// Container Apps no tiene bindings nativos para Service Bus en un contenedor
// plano -- este proceso vive corriendo y consumiendo las 4 colas. El scale
// rule de KEDA (azure-servicebus, ver container-apps.bicep) escala replicas
// segun la profundidad de `scoring-queue`; cada replica nueva arranca este
// mismo proceso y se suma a los 4 consumers activos.
http
  .createServer((req, res) => {
    if (req.url === "/healthz") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "ok" }));
      return;
    }
    res.writeHead(404);
    res.end();
  })
  .listen(PORT, () => console.log(`scoring-engine healthz en el puerto ${PORT}`));

async function shutdown() {
  console.log("apagando receivers...");
  await Promise.all(receivers.map((r) => r.close()));
  process.exit(0);
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
