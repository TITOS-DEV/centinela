# Verificación documental

## Flujo

1. El analista sube el documento de identidad a
   `identity-documents/{accountId}/{caseId}/{filename}` en la cuenta de storage
   (mismo contenedor de objetos configurado en semana 1, contenedor privado nuevo:
   `identity-documents`).
2. El System Topic de Event Grid de esa cuenta de storage emite
   `Microsoft.Storage.BlobCreated`, filtrado por `subjectBeginsWith:
   /blobServices/default/containers/identity-documents/` (ver
   `infra/modules/eventgrid-subscriptions.bicep`) y reenviado a la cola
   `documents-queue` de Service Bus.
3. `documentWorker` (dentro de `ca-scoring`) consume el mensaje, llama a Azure AI
   Document Intelligence (modelo `prebuilt-idDocument`, tier **F0**) pasando
   solo la URL del blob — Document Intelligence usa su propia identidad
   administrada (rol `Storage Blob Data Reader` sobre la cuenta de storage) para
   leerlo, sin SAS tokens.
4. El resultado (`verified` con los campos extraídos, o `failed` con el motivo) se
   adjunta al documento del caso en Cosmos (`documentVerification`), sin importar
   cuál sea.

## Manejo de fallos

`extractIdentityDocument()` (`services/scoring-engine/src/documentIntelligence/`)
**nunca lanza** para los casos de negocio esperados — documento ilegible, formato no
soportado, corrupto, o sin campos reconocibles — siempre devuelve `{status: "failed",
reason}`. `documentWorker` siempre completa el mensaje de Service Bus después de
escribir el resultado en el caso (éxito o fallo), así que:

- El caso **nunca queda en un estado indeterminado**: `documentVerification.status`
  es `"verified"` o `"failed"`, consultable en cualquier momento.
- El analista se entera del resultado consultando ese campo — no hay canal de
  notificación push adicional en el alcance de esta semana (ver
  `documentWorker.js`, comentario final).
- Solo se reintenta (mensaje abandonado, no completado) cuando el fallo es de
  Cosmos (posible problema transitorio) — nunca cuando el fallo es del propio
  documento, porque reintentar un documento ilegible no lo hace legible.

## Tier gratuito (F0) y volumen esperado

El tier F0 de Azure AI Document Intelligence incluye **500 páginas/mes**, gratis de
forma permanente. Verificado en semana 1 (`SEMANA1.md`, checklist del día 1) que está
disponible en `centralus`. Volumen esperado del proyecto: verificación de identidad
es un flujo de escalamiento manual iniciado por un analista, no automático por cada
transacción — con un volumen de prueba de decenas de documentos durante las 3
semanas del proyecto, el consumo esperado está muy por debajo de las 500
páginas/mes del tier gratuito.

## Plan alternativo (no aplica en este proyecto)

El checklist de semana 1 confirmó que Document Intelligence F0 sí está disponible en
la suscripción y región del proyecto — el plan alternativo (extracción con una
librería de procesamiento documental corriendo dentro del componente serverless) no
fue necesario.
