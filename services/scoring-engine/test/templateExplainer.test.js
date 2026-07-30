const { test } = require("node:test");
const assert = require("node:assert/strict");
const { generateExplanation } = require("../src/explainer/templateExplainer");

test("genera una explicacion con encabezado y una linea por regla activada", () => {
  const caseDoc = {
    score: 82,
    threshold: 60,
    triggeredRules: [
      { ruleId: "velocity", points: 35, observed: { transactionCountInWindow: 3, windowMinutes: 4, maxAllowed: 1 } },
      {
        ruleId: "amount_anomaly",
        points: 30,
        observed: { currentAmount: 4200000, historicalAverage: 50000, zScore: 12, zScoreThreshold: 2.5 },
      },
      {
        ruleId: "geo_impossible",
        points: 17,
        observed: {
          previousCity: "Medellin",
          currentCity: "Madrid",
          minutesElapsed: 11,
          distanceKm: 8000,
          previousTransactionId: "txn_prev",
        },
      },
    ],
  };

  const explanation = generateExplanation(caseDoc);

  assert.match(explanation, /score 82 \(umbral: 60\)/);
  assert.match(explanation, /3 transacciones.*4 minutos/s);
  assert.match(explanation, /84\.0×.*50[.,]000/s);
  assert.match(explanation, /Medellin.*11 minutos.*Madrid.*8000 km/s);
  assert.match(explanation, /\+35 puntos/);
  assert.match(explanation, /\+30 puntos/);
  assert.match(explanation, /\+17 puntos/);
});

test("no inventa una explicacion si el motor no registro reglas activadas", () => {
  const explanation = generateExplanation({ score: 75, threshold: 60, triggeredRules: [] });
  assert.match(explanation, /no registró el detalle/);
  assert.doesNotMatch(explanation, /\+\d+ puntos/);
});

test("regla desconocida produce una frase generica sin inventar causas", () => {
  const explanation = generateExplanation({
    score: 90,
    threshold: 60,
    triggeredRules: [{ ruleId: "regla_nueva_no_mapeada", points: 40, observed: {} }],
  });
  assert.match(explanation, /regla "regla_nueva_no_mapeada"/);
  assert.match(explanation, /\+40 puntos/);
});
