const appInsights = require("applicationinsights");

// Se arranca antes que cualquier otro require de negocio: instrumenta
// automaticamente HTTP entrante/saliente y las llamadas a Cosmos/Event Grid
// como "dependencies". APPLICATIONINSIGHTS_CONNECTION_STRING viene del app
// setting inyectado por container-apps.bicep (no es secreto: es un endpoint +
// un instrumentation key de escritura, igual que una URL de API).
if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  appInsights
    .setup()
    .setAutoCollectConsole(true, true)
    .setSendLiveMetrics(false)
    .start();
  appInsights.defaultClient.context.tags[appInsights.defaultClient.context.keys.cloudRole] = "ingest-api";
}

/**
 * Registra una etapa nombrada del pipeline con su duracion, siempre con
 * transactionId como customDimension. Esto es lo que permite reconstruir el
 * recorrido completo de UNA transaccion (KQL: customEvents | where
 * customDimensions.transactionId == "...") sin depender de que el contexto
 * de correlacion de Application Insights sobreviva un salto asincrono por
 * Event Grid / Service Bus.
 */
function trackStage(name, { transactionId, accountId, durationMs, extra = {} }) {
  if (!appInsights.defaultClient) return;
  appInsights.defaultClient.trackEvent({
    name,
    properties: {
      transactionId,
      accountId,
      durationMs: String(durationMs),
      ...extra,
    },
    measurements: { durationMs },
  });
}

function trackFailure(stage, { transactionId, accountId, error }) {
  if (!appInsights.defaultClient) return;
  appInsights.defaultClient.trackException({
    exception: error instanceof Error ? error : new Error(String(error)),
    properties: { stage, transactionId, accountId },
  });
}

module.exports = { appInsights, trackStage, trackFailure };
