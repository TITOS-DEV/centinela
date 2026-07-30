/**
 * Explicador de casos — genera texto legible a partir del detalle de reglas
 * activadas, persistido por el motor de scoring. Puramente determinista
 * (plantillas + interpolacion de los valores en `observed`), sin modelo de
 * lenguaje. Cada oracion se arma UNICAMENTE con campos que la regla
 * correspondiente ya guardo — si un campo no esta, no se inventa: se omite
 * o se usa una frase generica que no afirma nada que el motor no respalde.
 */

function formatCurrency(amount) {
  if (typeof amount !== "number") return "monto desconocido";
  return `$${Math.round(amount).toLocaleString("es-CO")}`;
}

const SENTENCE_BUILDERS = {
  velocity: ({ observed, points }) => {
    const { transactionCountInWindow, windowMinutes, maxAllowed } = observed;
    return (
      `Se detectaron ${transactionCountInWindow} transacciones de esta cuenta en los ` +
      `últimos ${windowMinutes} minutos, cuando el máximo esperado es de ${maxAllowed} (+${points} puntos).`
    );
  },

  amount_anomaly: ({ observed, points }) => {
    const { currentAmount, historicalAverage, zScore, zScoreThreshold } = observed;
    if (typeof historicalAverage === "number" && historicalAverage > 0) {
      const multiplier = (currentAmount / historicalAverage).toFixed(1);
      return (
        `El monto de ${formatCurrency(currentAmount)} supera en ${multiplier}× el promedio ` +
        `histórico de la cuenta (${formatCurrency(historicalAverage)}) (+${points} puntos).`
      );
    }
    return (
      `El monto de ${formatCurrency(currentAmount)} se desvía del comportamiento histórico de la ` +
      `cuenta con un z-score de ${zScore} (umbral: ${zScoreThreshold}) (+${points} puntos).`
    );
  },

  geo_impossible: ({ observed, points }) => {
    const { previousCity, currentCity, minutesElapsed, distanceKm, previousTransactionId } = observed;
    const origin = previousCity ? `en ${previousCity}` : `(transacción ${previousTransactionId})`;
    const destination = currentCity ? `en ${currentCity}` : "en otra ubicación";
    return (
      `La transacción anterior de esta cuenta se originó ${origin} hace ${minutesElapsed} minutos; ` +
      `esta se origina ${destination}, a ${distanceKm} km de distancia (+${points} puntos).`
    );
  },

  risky_merchant: ({ observed, points }) => {
    const { merchantId, merchantCategory, matchedBy } = observed;
    const descriptor =
      matchedBy === "merchant_id"
        ? `el comercio ${merchantId}`
        : `la categoría de comercio "${merchantCategory}"`;
    return `La transacción se dirige a ${descriptor}, marcado previamente como de riesgo (+${points} puntos).`;
  },
};

/**
 * @param {object} caseDoc - documento de caso con score, threshold, triggeredRules
 * @returns {string} explicacion multilinea lista para mostrar al analista
 */
function generateExplanation(caseDoc) {
  const { score, threshold, triggeredRules } = caseDoc;

  if (!Array.isArray(triggeredRules) || triggeredRules.length === 0) {
    // El motor marco el caso pero no dejo detalle de reglas activadas — esto
    // es un problema del registro del motor, no del explicador (Centinela.md,
    // seccion "El explicador de casos"). Se deja constancia explicita, en vez
    // de fabricar una explicacion sin respaldo.
    return (
      `Transacción marcada con score ${score} (umbral: ${threshold}).\n\n` +
      `El motor de scoring no registró el detalle de las reglas que activaron este caso. ` +
      `No es posible generar una explicación sin esa información — la corrección corresponde ` +
      `al motor, no al explicador.`
    );
  }

  const lines = [`Transacción marcada con score ${score} (umbral: ${threshold}).`, ""];

  for (const rule of triggeredRules) {
    const builder = SENTENCE_BUILDERS[rule.ruleId];
    if (builder) {
      lines.push(builder(rule));
    } else {
      // Regla desconocida (agregada despues sin actualizar el explicador):
      // frase generica que solo usa points, nunca inventa un "porque".
      lines.push(`Se activó la regla "${rule.ruleId}" (+${rule.points} puntos).`);
    }
    lines.push("");
  }

  return lines.join("\n").trim();
}

module.exports = { generateExplanation };
