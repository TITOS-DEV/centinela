const { getAccountHistory, getTransactionById, patchTransactionScore } = require("../queries/transactionHistory");
const { evaluateAllRules } = require("../rules");
const { createSender } = require("../serviceBusClient");
const { trackStage, trackFailure } = require("../tracing");

const SCORE_THRESHOLD = Number(process.env.SCORE_THRESHOLD || 70);
const casesSender = createSender("cases");

/**
 * Se dispara por mensajes en `scoring-queue`, que recibe el evento liviano
 * "Centinela.Transaction.Created" reenviado por la suscripcion de Event Grid
 * (destino: Service Bus). Cosmos es la fuente de verdad — relee el documento
 * completo antes de evaluar las reglas, en vez de confiar en el payload del
 * evento (que solo trae IDs, ver docs/event-contract.md).
 *
 * Restriccion central del proyecto: este worker corre desacoplado de
 * ingest-api. ingest-api nunca lo invoca directamente ni espera su resultado.
 */
async function handleScoringMessage(message) {
  const stageStart = Date.now();
  const event = Array.isArray(message.body) ? message.body[0] : message.body;
  const { transactionId, accountId } = event?.data || {};

  if (!transactionId || !accountId) {
    // Mensaje mal formado no es un fallo transitorio -- reintentarlo no lo
    // arregla. Se completa (se descarta) en vez de dejarlo rebotar hasta dead-letter.
    trackFailure("score.malformed_message", { error: new Error("mensaje sin transactionId/accountId") });
    return { outcome: "discarded" };
  }

  try {
    const currentTx = await getTransactionById(transactionId, accountId);
    if (!currentTx) {
      // Lag de consistencia eventual: se descarta en vez de reintentar indefinidamente.
      trackFailure("score.transaction_not_found", { transactionId, accountId, error: new Error("no encontrada en Cosmos") });
      return { outcome: "discarded" };
    }

    const { history, requestCharge } = await getAccountHistory(accountId, { limit: 20 });
    const historyWithoutCurrent = history.filter((tx) => tx.id !== transactionId);

    const { score, ruleResults, triggeredRules } = evaluateAllRules(currentTx, historyWithoutCurrent);
    const caseOpened = score > SCORE_THRESHOLD;
    const newStatus = caseOpened ? "case_opened" : "scored";

    await patchTransactionScore(transactionId, accountId, { score, ruleResults, status: newStatus });

    if (caseOpened) {
      await casesSender.sendMessages({
        body: {
          transactionId,
          accountId,
          score,
          threshold: SCORE_THRESHOLD,
          triggeredRules: triggeredRules.map((r) => ({ ruleId: r.ruleId, points: r.points, observed: r.observed })),
          transactionSnapshot: {
            amount: currentTx.amount,
            currency: currentTx.currency,
            merchant: currentTx.merchant || null,
            receivedAt: currentTx.receivedAt,
          },
          openedAt: new Date().toISOString(),
        },
        contentType: "application/json",
        messageId: transactionId,
      });
    }

    trackStage("score.completed", {
      transactionId,
      accountId,
      durationMs: Date.now() - stageStart,
      extra: { score: String(score), caseOpened: String(caseOpened), cosmosRequestCharge: String(requestCharge) },
    });

    return { outcome: "scored", score, caseOpened };
  } catch (err) {
    trackFailure("score.processing_error", { transactionId, accountId, error: err });
    throw err; // deja que el receiver haga abandon() -> reintento, hasta maxDeliveryCount
  }
}

module.exports = { handleScoringMessage };
