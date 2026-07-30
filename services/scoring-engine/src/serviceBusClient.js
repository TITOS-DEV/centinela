const { ServiceBusClient } = require("@azure/service-bus");
const { DefaultAzureCredential } = require("@azure/identity");

// Misma filosofia: Managed Identity en Azure, `az login` en local. Nunca una
// connection string con clave embebida. managedIdentityClientId selecciona
// la identidad user-assigned de este Container App especificamente.
const credential = new DefaultAzureCredential({
  managedIdentityClientId: process.env.MANAGED_IDENTITY_CLIENT_ID,
});

// SERVICEBUS_NAMESPACE es el FQDN del namespace (sin protocolo, sin queue).
const sbClient = new ServiceBusClient(process.env.SERVICEBUS_NAMESPACE, credential);

const QUEUES = {
  scoring: process.env.SERVICEBUS_SCORING_QUEUE || "scoring-queue",
  cases: process.env.SERVICEBUS_CASES_QUEUE || "cases-queue",
  explainer: process.env.SERVICEBUS_EXPLAINER_QUEUE || "explainer-queue",
  documents: process.env.SERVICEBUS_DOCUMENTS_QUEUE || "documents-queue",
};

function createSender(queueKey) {
  return sbClient.createSender(QUEUES[queueKey]);
}

function createReceiver(queueKey) {
  // maxAutoLockRenewalDurationInMs=0 desactiva el auto-renew: si un mensaje
  // tarda mas de lockDuration (1 min, ver servicebus.bicep) el lock expira y
  // el mensaje reaparece para reintento, en vez de quedar "colgado" a mitad
  // de un procesamiento que nunca termina.
  return sbClient.createReceiver(QUEUES[queueKey], { receiveMode: "peekLock" });
}

module.exports = { sbClient, createSender, createReceiver, QUEUES };
