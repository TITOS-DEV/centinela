const { test } = require("node:test");
const assert = require("node:assert/strict");
const { evaluateVelocity } = require("../src/rules/velocityRule");
const { evaluateAmountAnomaly } = require("../src/rules/amountAnomalyRule");
const { evaluateGeoImpossible } = require("../src/rules/geoImpossibleRule");
const { evaluateRiskyMerchant } = require("../src/rules/riskyMerchantRule");
const { evaluateAllRules } = require("../src/rules");

test("velocity: activa cuando hay mas transacciones que el maximo en la ventana", () => {
  const now = new Date("2026-07-17T21:04:00.000Z");
  const currentTx = { receivedAt: now.toISOString() };
  const history = [
    { receivedAt: new Date(now - 60_000).toISOString() },
    { receivedAt: new Date(now - 120_000).toISOString() },
    { receivedAt: new Date(now - 180_000).toISOString() },
  ];
  const result = evaluateVelocity(currentTx, history);
  assert.equal(result.triggered, true);
  assert.equal(result.ruleId, "velocity");
});

test("velocity: no activa con historico vacio", () => {
  const result = evaluateVelocity({ receivedAt: new Date().toISOString() }, []);
  assert.equal(result.triggered, false);
});

test("amount_anomaly: no activa con historico insuficiente", () => {
  const result = evaluateAmountAnomaly({ amount: 1000000 }, [{ amount: 1000 }]);
  assert.equal(result.triggered, false);
  assert.equal(result.observed.reason, "historico insuficiente");
});

test("amount_anomaly: activa cuando el monto es muy superior al historico", () => {
  const history = [{ amount: 50000 }, { amount: 48000 }, { amount: 52000 }, { amount: 49000 }];
  const result = evaluateAmountAnomaly({ amount: 4200000 }, history);
  assert.equal(result.triggered, true);
});

test("geo_impossible: no activa sin transaccion previa", () => {
  const result = evaluateGeoImpossible({ location: { lat: 6.24, lon: -75.58 }, receivedAt: new Date().toISOString() }, []);
  assert.equal(result.triggered, false);
});

test("geo_impossible: activa con velocidad implicita imposible", () => {
  const t0 = new Date("2026-07-17T21:00:00.000Z");
  const t1 = new Date("2026-07-17T21:11:00.000Z");
  const previous = { location: { lat: 6.2442, lon: -75.5812, city: "Medellin" }, receivedAt: t0.toISOString(), id: "txn_prev" };
  const current = { location: { lat: 40.4168, lon: -3.7038, city: "Madrid" }, receivedAt: t1.toISOString() };
  const result = evaluateGeoImpossible(current, [previous]);
  assert.equal(result.triggered, true);
  assert.ok(result.observed.distanceKm > 7000);
});

test("risky_merchant: activa por categoria marcada", () => {
  process.env.RISKY_MERCHANT_CATEGORIES = "gambling";
  const result = evaluateRiskyMerchant({ merchant: { id: "mer_1", category: "gambling" } });
  assert.equal(result.triggered, true);
  delete process.env.RISKY_MERCHANT_CATEGORIES;
});

test("evaluateAllRules: suma los puntos de las reglas activadas", () => {
  const { score, triggeredRules } = evaluateAllRules({ amount: 100, receivedAt: new Date().toISOString() }, []);
  assert.equal(typeof score, "number");
  assert.ok(Array.isArray(triggeredRules));
});
