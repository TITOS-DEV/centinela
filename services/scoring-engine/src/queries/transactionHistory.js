const { transactionsContainer } = require("../cosmosClient");

/**
 * Trae las ultimas N transacciones de una cuenta, mas recientes primero.
 * El partitionKey se pasa explicitamente para forzar una consulta de una
 * sola particion (sin ese partitionKey el SDK haria fan-out a todas).
 */
async function getAccountHistory(accountId, { limit = 20 } = {}) {
  const querySpec = {
    query: `
      SELECT TOP @limit *
      FROM c
      WHERE c.accountId = @accountId
      ORDER BY c.receivedAt DESC
    `,
    parameters: [
      { name: "@accountId", value: accountId },
      { name: "@limit", value: limit },
    ],
  };

  const { resources, requestCharge } = await transactionsContainer.items
    .query(querySpec, { partitionKey: accountId })
    .fetchAll();

  return { history: resources, requestCharge };
}

/** Lee una transaccion puntual por id, usando su accountId como partition key. */
async function getTransactionById(transactionId, accountId) {
  const { resource } = await transactionsContainer.item(transactionId, accountId).read();
  return resource;
}

/** Actualiza el score y el detalle de reglas de una transaccion ya persistida. */
async function patchTransactionScore(transactionId, accountId, { score, ruleResults, status }) {
  await transactionsContainer.item(transactionId, accountId).patch([
    { op: "replace", path: "/score", value: score },
    { op: "replace", path: "/ruleTriggers", value: ruleResults },
    { op: "replace", path: "/status", value: status },
  ]);
}

module.exports = { getAccountHistory, getTransactionById, patchTransactionScore };
