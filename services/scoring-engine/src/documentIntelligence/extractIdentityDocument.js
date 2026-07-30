const DocumentIntelligence = require("@azure-rest/ai-document-intelligence").default;
const { getLongRunningPoller, isUnexpected } = require("@azure-rest/ai-document-intelligence");
const { DefaultAzureCredential } = require("@azure/identity");

// managedIdentityClientId selecciona la identidad user-assigned de este
// Container App especificamente (ver services/*/src/cosmosClient.js).
// scope explicito: disableLocalAuth=true en el recurso (documentintelligence.bicep)
// fuerza autenticacion Entra ID, sin clave de API en ningun lado.
const credential = new DefaultAzureCredential({
  managedIdentityClientId: process.env.MANAGED_IDENTITY_CLIENT_ID,
});
const client = DocumentIntelligence(process.env.DOCUMENT_INTELLIGENCE_ENDPOINT, credential, {
  credentials: { scopes: ["https://cognitiveservices.azure.com/.default"] },
});

const MODEL_ID = "prebuilt-idDocument";

/**
 * Extrae nombre, numero de identificacion y fechas de un documento de
 * identidad usando el tier gratuito (F0) de Azure AI Document Intelligence.
 *
 * NUNCA lanza para casos de negocio esperados (documento ilegible, formato
 * no soportado, sin campos reconocibles) — devuelve
 * { status: "failed", reason } en esos casos, para que el caso quede en un
 * estado consultable y el analista reciba notificacion, en vez de que el
 * flujo se interrumpa o el mensaje se pierda.
 */
async function extractIdentityDocument(documentUrl) {
  let initialResponse;
  try {
    initialResponse = await client
      .path("/documentModels/{modelId}:analyze", MODEL_ID)
      .post({
        contentType: "application/json",
        body: { urlSource: documentUrl },
      });
  } catch (err) {
    return { status: "failed", reason: `error de red o autenticacion al llamar Document Intelligence: ${err.message}` };
  }

  if (isUnexpected(initialResponse)) {
    // Formato no soportado, documento corrupto, o cuota F0 agotada llegan
    // aca como respuesta HTTP de error, no como excepcion.
    const errorMessage = initialResponse.body?.error?.message || `HTTP ${initialResponse.status}`;
    return { status: "failed", reason: `Document Intelligence rechazo el documento: ${errorMessage}` };
  }

  let result;
  try {
    const poller = getLongRunningPoller(client, initialResponse);
    const finalResponse = await poller.pollUntilDone();
    if (isUnexpected(finalResponse)) {
      const errorMessage = finalResponse.body?.error?.message || `HTTP ${finalResponse.status}`;
      return { status: "failed", reason: `analisis fallido: ${errorMessage}` };
    }
    result = finalResponse.body.analyzeResult;
  } catch (err) {
    return { status: "failed", reason: `timeout o error durante el analisis: ${err.message}` };
  }

  const document = result?.documents?.[0];
  if (!document || !document.fields) {
    return { status: "failed", reason: "el documento no contiene campos reconocibles (ilegible o incompleto)" };
  }

  const fields = document.fields;
  const extracted = {
    fullName: fields.FirstName?.valueString && fields.LastName?.valueString
      ? `${fields.FirstName.valueString} ${fields.LastName.valueString}`
      : fields.FullName?.valueString || null,
    documentNumber: fields.DocumentNumber?.valueString || null,
    dateOfBirth: fields.DateOfBirth?.valueDate || null,
    dateOfExpiration: fields.DateOfExpiration?.valueDate || null,
  };

  const hasAnyField = Object.values(extracted).some((v) => v !== null);
  if (!hasAnyField) {
    return { status: "failed", reason: "no se pudo extraer ningun campo estructurado del documento" };
  }

  return { status: "verified", extracted, confidence: document.confidence ?? null };
}

module.exports = { extractIdentityDocument };
