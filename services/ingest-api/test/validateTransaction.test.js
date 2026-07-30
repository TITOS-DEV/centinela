const { test } = require("node:test");
const assert = require("node:assert/strict");
const { validateTransaction } = require("../src/validateTransaction");

const validPayload = {
  accountId: "acc_00381",
  amount: 4200000,
  currency: "COP",
  type: "purchase",
  channel: "pos",
  location: { lat: 6.2442, lon: -75.5812 },
  originTimestamp: "2026-07-17T21:04:00.000Z",
};

test("acepta un payload valido", () => {
  const result = validateTransaction(validPayload);
  assert.equal(result.valid, true);
});

test("rechaza un payload sin accountId", () => {
  const { accountId, ...rest } = validPayload;
  const result = validateTransaction(rest);
  assert.equal(result.valid, false);
  assert.ok(result.errors.some((e) => e.includes("accountId")));
});

test("rechaza amount negativo o cero", () => {
  const result = validateTransaction({ ...validPayload, amount: 0 });
  assert.equal(result.valid, false);
});

test("rechaza type fuera de la lista permitida", () => {
  const result = validateTransaction({ ...validPayload, type: "bizarre" });
  assert.equal(result.valid, false);
});

test("rechaza location sin lat/lon numericos", () => {
  const result = validateTransaction({ ...validPayload, location: { lat: "no-numero" } });
  assert.equal(result.valid, false);
});

test("rechaza body vacio sin lanzar excepcion", () => {
  const result = validateTransaction(null);
  assert.equal(result.valid, false);
});
