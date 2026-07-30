const { transactionsContainer } = require("../cosmosClient");

/**
 * Trae las ultimas N transacciones de una cuenta, mas recientes primero.
 *
 * Importante: el `partitionKey` se pasa explicitamente en las opciones de la
 * query. Eso es lo que convierte esto en una consulta de una sola particion
 * (la que exige el criterio de aceptacion "consulta el historial de una
 * unica cuenta, demostrable via metrica de RU consumidas"). Sin ese
 * partitionKey, el SDK haria fan-out a todas las particiones aunque el
 * WHERE filtre por accountId.
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

/**
 * Lee una transaccion puntual por id, usando su accountId como partition key.
 * Tambien es lectura de una sola particion — nunca un fan-out.
 */
async function getTransactionById(transactionId, accountId) {
  const { resource } = await transactionsContainer.item(transactionId, accountId).read();
  return resource;
}

/**
 * Actualiza el score y el detalle de reglas de una transaccion ya persistida,
 * sin reescribir el documento completo (patch parcial).
 */
async function patchTransactionScore(transactionId, accountId, { score, ruleResults, status }) {
  await transactionsContainer.item(transactionId, accountId).patch([
    { op: "replace", path: "/score", value: score },
    { op: "replace", path: "/ruleTriggers", value: ruleResults },
    { op: "replace", path: "/status", value: status },
  ]);
}

module.exports = { getAccountHistory, getTransactionById, patchTransactionScore };

