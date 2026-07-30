const { createCase } = require("../queries/casesQueries");
const { createSender } = require("../serviceBusClient");
const { trackStage, trackFailure } = require("../tracing");

const explainerSender = createSender("explainer");

/**
 * Se dispara por mensajes en `cases-queue`, encolados directamente por
 * scoreWorker (sin pasar por Event Grid) cuando el score supera el umbral.
 * A diferencia de Event Grid, esta cola garantiza entrega: si este worker
 * esta caido, el mensaje espera en la cola en vez de perderse -- perder un
 * caso de fraude tiene costo real, a diferencia de perder una notificacion
 * de "transaccion creada".
 *
 * Abre el caso de inmediato y encola la generacion de la explicacion por
 * separado (explainer-queue). Que el explicador este caido NUNCA bloquea
 * la apertura del caso (requerimiento 2.4).
 */
async function handleCaseMessage(message) {
  const stageStart = Date.now();
  const payload = message.body;
  const { transactionId, accountId } = payload || {};

  if (!transactionId || !accountId) {
    trackFailure("case.malformed_message", { error: new Error("mensaje de caso sin transactionId/accountId") });
    return { outcome: "discarded" };
  }

  try {
    const caseDoc = await createCase(payload);

    await explainerSender.sendMessages({
      body: { caseId: caseDoc.id, accountId },
      contentType: "application/json",
      messageId: caseDoc.id,
    });

    trackStage("case.opened", {
      transactionId,
      accountId,
      durationMs: Date.now() - stageStart,
      extra: { caseId: caseDoc.id, score: String(caseDoc.score) },
    });

    return { outcome: "case_opened", caseId: caseDoc.id };
  } catch (err) {
    trackFailure("case.processing_error", { transactionId, accountId, error: err });
    throw err;
  }
}

module.exports = { handleCaseMessage };
