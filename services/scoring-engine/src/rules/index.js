const { evaluateVelocity } = require("./velocityRule");
const { evaluateAmountAnomaly } = require("./amountAnomalyRule");
const { evaluateGeoImpossible } = require("./geoImpossibleRule");
const { evaluateRiskyMerchant } = require("./riskyMerchantRule");

/**
 * Corre las 4 reglas contra la transaccion actual y su historico, y suma
 * los puntos de las que se activaron. Devuelve el score total y el detalle
 * COMPLETO de cada regla evaluada (activada o no) — el explicador se
 * construye sobre este detalle, por eso se persiste siempre, no solo
 * cuando triggered=true.
 */
function evaluateAllRules(currentTx, history) {
  const results = [
    evaluateVelocity(currentTx, history),
    evaluateAmountAnomaly(currentTx, history),
    evaluateGeoImpossible(currentTx, history),
    evaluateRiskyMerchant(currentTx),
  ];

  const score = results.reduce((sum, r) => sum + r.points, 0);
  const triggeredRules = results.filter((r) => r.triggered);

  return { score, ruleResults: results, triggeredRules };
}

module.exports = { evaluateAllRules };
