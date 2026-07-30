const RULE_ID = "velocity";
const POINTS = Number(process.env.RULE_VELOCITY_POINTS || 30);
const WINDOW_MINUTES = Number(process.env.RULE_VELOCITY_WINDOW_MINUTES || 10);
const MAX_COUNT = Number(process.env.RULE_VELOCITY_MAX_COUNT || 3);

/**
 * Cuenta cuantas transacciones de la cuenta cayeron dentro de los ultimos
 * WINDOW_MINUTES, contando la transaccion actual. Si supera MAX_COUNT, activa.
 *
 * history ya viene ordenado por receivedAt DESC (ver transactionHistory.js).
 */
function evaluateVelocity(currentTx, history) {
  const now = new Date(currentTx.receivedAt).getTime();
  const windowMs = WINDOW_MINUTES * 60 * 1000;

  const countInWindow = history.filter((tx) => {
    const txTime = new Date(tx.receivedAt).getTime();
    return now - txTime <= windowMs;
  }).length + 1; // +1 por la transaccion actual, que aun no esta en el historial

  const triggered = countInWindow > MAX_COUNT;

  return {
    triggered,
    ruleId: RULE_ID,
    points: triggered ? POINTS : 0,
    observed: {
      transactionCountInWindow: countInWindow,
      windowMinutes: WINDOW_MINUTES,
      maxAllowed: MAX_COUNT,
    },
  };
}

module.exports = { evaluateVelocity };
