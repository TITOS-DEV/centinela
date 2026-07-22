const VALID_TYPES = ["purchase", "transfer", "withdrawal"];
const VALID_CHANNELS = ["pos", "online", "atm", "app"];

/**
 * Valida el payload de entrada contra el contrato definido en docs/event-contract.md.
 * Devuelve { valid: true } o { valid: false, errors: [...] }.
 * No lanza excepciones — el caller decide qué código HTTP responder.
 */
function validateTransaction(body) {
  const errors = [];

  if (!body || typeof body !== "object") {
    return { valid: false, errors: ["body vacio o no es JSON"] };
  }

  if (!body.accountId || typeof body.accountId !== "string") {
    errors.push("accountId es obligatorio y debe ser string");
  }

  if (typeof body.amount !== "number" || body.amount <= 0) {
    errors.push("amount es obligatorio y debe ser un numero positivo");
  }

  if (!body.currency || typeof body.currency !== "string") {
    errors.push("currency es obligatorio");
  }

  if (!VALID_TYPES.includes(body.type)) {
    errors.push(`type debe ser uno de: ${VALID_TYPES.join(", ")}`);
  }

  if (body.channel && !VALID_CHANNELS.includes(body.channel)) {
    errors.push(`channel debe ser uno de: ${VALID_CHANNELS.join(", ")}`);
  }

  if (
    !body.location ||
    typeof body.location.lat !== "number" ||
    typeof body.location.lon !== "number"
  ) {
    errors.push("location.lat y location.lon son obligatorios y deben ser numeros");
  }

  if (!body.originTimestamp || isNaN(Date.parse(body.originTimestamp))) {
    errors.push("originTimestamp es obligatorio y debe ser una fecha ISO8601 valida");
  }

  return errors.length === 0 ? { valid: true } : { valid: false, errors };
}

module.exports = { validateTransaction };
