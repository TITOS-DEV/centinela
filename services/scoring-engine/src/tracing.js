const appInsights = require("applicationinsights");

if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  appInsights
    .setup()
    .setAutoCollectConsole(true, true)
    .setSendLiveMetrics(false)
    .start();
  appInsights.defaultClient.context.tags[appInsights.defaultClient.context.keys.cloudRole] = "scoring-engine";
}

/**
 * Registra una etapa nombrada del pipeline con su duracion, siempre con
 * transactionId (y accountId cuando aplica) como customDimension. Esto
 * reconstruye el recorrido de una transaccion via KQL:
 *   customEvents | where customDimensions.transactionId == "txn_..."
 *   | order by timestamp asc
 * sin depender de que el contexto de correlacion sobreviva el salto
 * asincrono Event Grid -> Service Bus -> este proceso.
 */
function trackStage(name, { transactionId, accountId, durationMs, extra = {} }) {
  if (!appInsights.defaultClient) return;
  appInsights.defaultClient.trackEvent({
    name,
    properties: {
      transactionId: transactionId || null,
      accountId: accountId || null,
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
    properties: { stage, transactionId: transactionId || null, accountId: accountId || null },
  });
}

module.exports = { appInsights, trackStage, trackFailure };
