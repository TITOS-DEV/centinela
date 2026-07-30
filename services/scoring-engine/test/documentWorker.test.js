const { test } = require("node:test");
const assert = require("node:assert/strict");
const { parseBlobSubject } = require("../src/workers/documentWorker");

test("parsea una ruta de blob valida", () => {
  const result = parseBlobSubject(
    "/blobServices/default/containers/identity-documents/blobs/acc_00381/case_txn_abc/cedula.pdf"
  );
  assert.deepEqual(result, { accountId: "acc_00381", caseId: "case_txn_abc", filename: "cedula.pdf" });
});

test("devuelve null para una ruta que no sigue la convencion", () => {
  const result = parseBlobSubject("/blobServices/default/containers/otro/blobs/algo.txt");
  assert.equal(result, null);
});
