const { extractIdentityDocument } = require("../documentIntelligence/extractIdentityDocument");
const { patchCaseDocumentVerification } = require("../queries/casesQueries");
const { trackStage, trackFailure } = require("../tracing");

// Convencion de ruta del blob subido por el analista:
// identity-documents/{accountId}/{caseId}/{filename}
// El "subject" de Microsoft.Storage.BlobCreated trae el formato completo de
// Azure: /blobServices/default/containers/{container}/blobs/{blobPath} -- el
// segmento "blobs/" es fijo y lo agrega la plataforma, no la convencion propia.
const PATH_PATTERN = /\/containers\/identity-documents\/blobs\/([^/]+)\/([^/]+)\/([^/]+)$/;

function parseBlobSubject(subject) {
  const match = subject.match(PATH_PATTERN);
  if (!match) return null;
  const [, accountId, caseId, filename] = match;
  return { accountId, caseId, filename };
}

/**
 * Se dispara por mensajes en `documents-queue`, alimentada por el evento
 * "Microsoft.Storage.BlobCreated" del contenedor `identity-documents`
 * (System Topic de Storage -> suscripcion con destino Service Bus).
 *
 * Requerimiento central: un documento ilegible, incompleto, corrupto o de
 * formato inesperado NUNCA debe interrumpir el flujo ni dejar el caso en un
 * estado indeterminado. Por eso extractIdentityDocument() no lanza para
 * esos casos -- siempre devuelve un resultado, y este worker SIEMPRE deja
 * el caso en un estado consultable (verified o failed con motivo).
 */
async function handleDocumentMessage(message) {
  const stageStart = Date.now();
  const event = Array.isArray(message.body) ? message.body[0] : message.body;
  const subject = event?.subject;
  const blobUrl = event?.data?.url;

  if (!subject || !blobUrl) {
    trackFailure("document.malformed_message", { error: new Error("evento sin subject/url") });
    return { outcome: "discarded" };
  }

  const parsed = parseBlobSubject(subject);
  if (!parsed) {
    // Ruta que no sigue la convencion esperada -- no es un documento de
    // verificacion valido, se descarta sin reintentar (reintentar no cambia la ruta).
    trackFailure("document.unexpected_path", { error: new Error(`ruta no reconocida: ${subject}`) });
    return { outcome: "discarded" };
  }

  const { accountId, caseId } = parsed;

  const result = await extractIdentityDocument(blobUrl);

  const documentVerification = {
    status: result.status, // "verified" | "failed"
    processedAt: new Date().toISOString(),
    ...(result.status === "verified"
      ? { extracted: result.extracted, confidence: result.confidence }
      : { reason: result.reason }),
  };

  try {
    await patchCaseDocumentVerification(caseId, accountId, documentVerification);
  } catch (err) {
    // Si el caso ya no existe o Cosmos falla, SI reintentamos -- a
    // diferencia de un documento ilegible, esto puede ser transitorio.
    trackFailure("document.patch_case_error", { accountId, error: err });
    throw err;
  }

  trackStage(`document.${result.status}`, {
    accountId,
    durationMs: Date.now() - stageStart,
    extra: { caseId, reason: result.status === "failed" ? result.reason : undefined },
  });

  // El analista se entera por el estado consultable del caso
  // (documentVerification.status) -- no hay canal de notificacion push
  // separado en el alcance de esta semana.
  return { outcome: result.status, caseId };
}

module.exports = { handleDocumentMessage, parseBlobSubject };
