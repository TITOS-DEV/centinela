const { getCaseById, patchCaseExplanation } = require("../queries/casesQueries");
const { generateExplanation } = require("../explainer/templateExplainer");
const { trackStage, trackFailure } = require("../tracing");

/**
 * Se dispara por mensajes en `explainer-queue`, encolados por caseWorker
 * inmediatamente despues de abrir el caso. Corre DESPUES de que el caso ya
 * existe y es visible para el analista -- la generacion de la explicacion
 * nunca esta en el camino critico de la apertura del caso ni de la
 * respuesta al cliente (esa ya ocurrio en ingest-api, minutos u horas antes).
 *
 * Si este worker esta caido, los mensajes se acumulan en la cola sin
 * perderse; al restablecerse, procesa el backlog y las explicaciones
 * pendientes se generan (requerimiento 2.4).
 */
async function handleExplainerMessage(message) {
  const stageStart = Date.now();
  const { caseId, accountId } = message.body || {};

  if (!caseId || !accountId) {
    trackFailure("explainer.malformed_message", { error: new Error("mensaje sin caseId/accountId") });
    return { outcome: "discarded" };
  }

  try {
    const caseDoc = await getCaseById(caseId, accountId);
    if (!caseDoc) {
      trackFailure("explainer.case_not_found", { accountId, error: new Error(`caso ${caseId} no encontrado`) });
      return { outcome: "discarded" };
    }

    const explanation = generateExplanation(caseDoc);
    await patchCaseExplanation(caseId, accountId, { explanation, explanationStatus: "generated" });

    trackStage("explainer.generated", {
      transactionId: caseDoc.transactionId,
      accountId,
      durationMs: Date.now() - stageStart,
      extra: { caseId },
    });

    return { outcome: "explained", caseId };
  } catch (err) {
    trackFailure("explainer.processing_error", { accountId, error: err });
    throw err; // reintento hasta maxDeliveryCount; el caso ya esta abierto y consultable
  }
}

module.exports = { handleExplainerMessage };
