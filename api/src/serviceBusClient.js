const { ServiceBusClient } = require("@azure/service-bus");
const { DefaultAzureCredential } = require("@azure/identity");

// Misma filosofía que cosmosClient.js: Managed Identity en Azure, tu sesion de
// `az login` en local. Nunca una connection string con clave embebida.
const credential = new DefaultAzureCredential();

// SERVICEBUS_NAMESPACE es el FQDN del namespace, ej:
// "sb-centinela-<suffix>.servicebus.windows.net" (sin protocolo, sin queue).
const sbClient = new ServiceBusClient(process.env.SERVICEBUS_NAMESPACE, credential);

const CASES_QUEUE_NAME = process.env.SERVICEBUS_CASES_QUEUE || "cases-queue";
const sender = sbClient.createSender(CASES_QUEUE_NAME);

/**
 * Encola un caso de fraude. A diferencia de Event Grid, este mensaje se
 * retiene en la cola hasta que el consumidor lo procese explicitamente —
 * si el consumidor esta caido, el mensaje espera, no se pierde.
 */
async function enqueueCase(casePayload) {
  await sender.sendMessages({
    body: casePayload,
    contentType: "application/json",
    messageId: casePayload.transactionId, // permite deduplicacion si se habilita
  });
}

module.exports = { enqueueCase };
