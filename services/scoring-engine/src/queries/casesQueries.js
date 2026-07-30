const { casesContainer } = require("../cosmosClient");

/**
 * El contenedor `cases` esta particionado por /accountId, igual que
 * `transactions` — misma cuenta, misma particion, y la mayoria de consultas
 * de un analista ("casos abiertos de esta cuenta") caen en una sola particion.
 */
async function createCase(casePayload) {
  const caseId = `case_${casePayload.transactionId}`;
  const document = {
    id: caseId,
    transactionId: casePayload.transactionId,
    accountId: casePayload.accountId,
    score: casePayload.score,
    threshold: casePayload.threshold,
    triggeredRules: casePayload.triggeredRules,
    transactionSnapshot: casePayload.transactionSnapshot,
    status: "open",
    openedAt: casePayload.openedAt,
    explanation: null,
    explanationStatus: "pending",
    identityDocument: null,
    documentVerification: null,
  };

  // upsert: si Service Bus reintrega el mismo mensaje (at-least-once), esto
  // es idempotente por id en vez de fallar con un conflicto 409.
  await casesContainer.items.upsert(document);
  return document;
}

async function getCaseById(caseId, accountId) {
  const { resource } = await casesContainer.item(caseId, accountId).read();
  return resource;
}

async function patchCaseExplanation(caseId, accountId, { explanation, explanationStatus }) {
  await casesContainer.item(caseId, accountId).patch([
    { op: "replace", path: "/explanation", value: explanation },
    { op: "replace", path: "/explanationStatus", value: explanationStatus },
  ]);
}

async function patchCaseDocumentVerification(caseId, accountId, documentVerification) {
  await casesContainer.item(caseId, accountId).patch([
    { op: "replace", path: "/documentVerification", value: documentVerification },
  ]);
}

module.exports = {
  createCase,
  getCaseById,
  patchCaseExplanation,
  patchCaseDocumentVerification,
};
