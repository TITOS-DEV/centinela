const RULE_ID = "risky_merchant";
const POINTS = Number(process.env.RULE_RISKY_MERCHANT_POINTS || 35);

// Listas separadas por coma en app settings, ej:
// RISKY_MERCHANT_IDS="mer_1234,mer_5678"
// RISKY_MERCHANT_CATEGORIES="crypto_exchange,gambling,cash_advance"
// Se leen en cada invocacion (no al cargar el modulo) para poder actualizarlas
// sin redeploy, solo cambiando el app setting.
function getRiskyIds() {
  return (process.env.RISKY_MERCHANT_IDS || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

function getRiskyCategories() {
  return (process.env.RISKY_MERCHANT_CATEGORIES || "")
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
}

/**
 * Activa si el comercio (por id) o su categoria estan en la lista marcada.
 * No requiere historico de la cuenta, solo el comercio de la transaccion actual.
 */
function evaluateRiskyMerchant(currentTx) {
  const merchant = currentTx.merchant;

  if (!merchant) {
    return {
      triggered: false,
      ruleId: RULE_ID,
      points: 0,
      observed: { reason: "transaccion sin datos de comercio" },
    };
  }

  const riskyIds = getRiskyIds();
  const riskyCategories = getRiskyCategories();

  const idMatch = merchant.id && riskyIds.includes(merchant.id);
  const categoryMatch = merchant.category && riskyCategories.includes(merchant.category.toLowerCase());
  const triggered = Boolean(idMatch || categoryMatch);

  return {
    triggered,
    ruleId: RULE_ID,
    points: triggered ? POINTS : 0,
    observed: {
      merchantId: merchant.id || null,
      merchantCategory: merchant.category || null,
      matchedBy: idMatch ? "merchant_id" : categoryMatch ? "categoria" : null,
    },
  };
}

module.exports = { evaluateRiskyMerchant };
