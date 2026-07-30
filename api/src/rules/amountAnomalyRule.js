const RULE_ID = "amount_anomaly";
const POINTS = Number(process.env.RULE_AMOUNT_POINTS || 25);
const ZSCORE_THRESHOLD = Number(process.env.RULE_AMOUNT_ZSCORE_THRESHOLD || 2.5);
const MIN_HISTORY_FOR_STATS = 3; // con menos de esto, el promedio no es confiable

function mean(values) {
  return values.reduce((sum, v) => sum + v, 0) / values.length;
}

function stdDev(values, avg) {
  const variance = values.reduce((sum, v) => sum + (v - avg) ** 2, 0) / values.length;
  return Math.sqrt(variance);
}

/**
 * Compara el monto actual contra la media y desviacion estandar del
 * historico de la cuenta. Si no hay suficiente historico, la regla no se
 * activa (evita falsos positivos en cuentas nuevas por falta de datos, no
 * por comportamiento real).
 */
function evaluateAmountAnomaly(currentTx, history) {
  if (history.length < MIN_HISTORY_FOR_STATS) {
    return {
      triggered: false,
      ruleId: RULE_ID,
      points: 0,
      observed: { reason: "historico insuficiente", historyCount: history.length },
    };
  }

  const amounts = history.map((tx) => tx.amount);
  const avg = mean(amounts);
  const sd = stdDev(amounts, avg);

  // Si sd es 0 (todas las transacciones previas fueron el mismo monto exacto)
  // evitamos dividir por cero; cualquier desviacion ya es atipica en ese caso.
  const zScore = sd === 0 ? (currentTx.amount === avg ? 0 : Infinity) : (currentTx.amount - avg) / sd;

  const triggered = zScore > ZSCORE_THRESHOLD;

  return {
    triggered,
    ruleId: RULE_ID,
    points: triggered ? POINTS : 0,
    observed: {
      currentAmount: currentTx.amount,
      historicalAverage: Number(avg.toFixed(2)),
      historicalStdDev: Number(sd.toFixed(2)),
      zScore: Number.isFinite(zScore) ? Number(zScore.toFixed(2)) : "infinito",
      zScoreThreshold: ZSCORE_THRESHOLD,
    },
  };
}

module.exports = { evaluateAmountAnomaly };
