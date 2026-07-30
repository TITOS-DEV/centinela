const { app } = require("@azure/functions");
const { getAccountHistory, getTransactionById, patchTransactionScore } = require("../queries/transactionHistory");
const { evaluateAllRules } = require("../rules");
const { enqueueCase } = require("../serviceBusClient");

// Configurable via app setting, sin necesidad de redeploy para cambiarlo.
const SCORE_THRESHOLD = Number(process.env.SCORE_THRESHOLD || 70);

/**
 * Se dispara por el evento "Centinela.Transaction.Created" publicado por
 * ingestTransaction. El evento es liviano (solo IDs) — Cosmos es la fuente
 * de verdad, asi que releemos el documento completo desde ahi antes de
 * evaluar las reglas.
 *
 * Restriccion central de la semana: esta Function corre de forma
 * independiente, disparada por Event Grid. ingestTransaction NUNCA la llama
 * directamente ni espera su resultado — por eso este archivo vive en un
 * trigger separado, no dentro del handler HTTP de ingesta.
 */
app.eventGrid("scoreTransaction", {
  handler: async (event, context) => {
    const { transactionId, accountId } = event.data;

    context.log(`Scoring iniciado para ${transactionId} (cuenta ${accountId})`);

    const currentTx = await getTransactionById(transactionId, accountId);
    if (!currentTx) {
      // Puede pasar por lag de consistencia eventual en casos raros; se loguea
      // y se descarta en vez de reintentar indefinidamente.
      context.warn(`Transaccion ${transactionId} no encontrada en Cosmos, se omite scoring`);
      return;
    }

    // Excluye la propia transaccion actual del historial que consultamos,
    // por si ya alcanzo a persistirse antes de que el scoring la lea.
    const { history, requestCharge } = await getAccountHistory(accountId, { limit: 20 });
    const historyWithoutCurrent = history.filter((tx) => tx.id !== transactionId);

    context.log(`Historial de ${accountId}: ${historyWithoutCurrent.length} tx, ${requestCharge} RUs consumidas`);

    const { score, ruleResults, triggeredRules } = evaluateAllRules(currentTx, historyWithoutCurrent);

    const newStatus = score > SCORE_THRESHOLD ? "case_opened" : "scored";

    await patchTransactionScore(transactionId, accountId, {
      score,
      ruleResults,
      status: newStatus,
    });

    if (score > SCORE_THRESHOLD) {
      context.log(`Umbral superado (${score} > ${SCORE_THRESHOLD}), encolando caso para ${transactionId}`);

      await enqueueCase({
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
      });
    } else {
      context.log(`Score ${score} bajo el umbral (${SCORE_THRESHOLD}), no se abre caso`);
    }
  },
});
