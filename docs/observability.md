# Observabilidad

Todo el sistema escribe en un único Application Insights (`appi-centinela-<suffix>`,
workspace-based sobre `log-centinela-<suffix>`). Cada evento de negocio incluye
`transactionId` (y `accountId` cuando aplica) como customDimension — esto es lo que
permite reconstruir el recorrido de una transacción sin depender de que la
correlación automática de Application Insights sobreviva un salto asíncrono por
Event Grid o Service Bus (ver `services/*/src/tracing.js`).

## Trazabilidad de una transacción puntual

En Application Insights → Logs (o el mismo workspace de Log Analytics). `Properties`
en las tablas basadas en workspace (`AppEvents`, `AppExceptions`, ...) llega como
texto JSON, no como columna dinámica navegable con `.` directamente — hay que
parsearla con `parse_json()`. Todas las queries de esta sección están verificadas
contra el ambiente real desplegado, con `<TXN_ID>` reemplazado por el id real
(ej. `txn_080da369-5baf-4432-a59d-d3cf2b35e209`):

```kusto
union AppRequests, AppDependencies, AppEvents, AppExceptions, AppTraces
| where TimeGenerated > ago(1h)
| where tostring(parse_json(Properties).transactionId) == "<TXN_ID>"
| project TimeGenerated, ItemType=Type, Name, DurationMs=Duration, Properties
| order by TimeGenerated asc
```

(Para una búsqueda rápida sin parsear, `Properties has "<TXN_ID>"` también funciona
como filtro de texto — más simple, ligeramente menos preciso si dos ids compartieran
substring, lo cual no ocurre con los UUID que usa este proyecto.)

Esto muestra, en orden: `ingest.persist` → `ingest.publish_event` →
`ingest.request_total` (todo en `ca-ingest`) → `score.completed` → (si abrió caso)
`case.opened` → `explainer.generated` → (si hay documento) `document.verified` /
`document.failed` (todo en `ca-scoring`), cada uno con su `durationMs`.

## Preguntas del requerimiento 2.5, resueltas con KQL

**Latencia de scoring (promedio y percentil superior):**
```kusto
AppEvents
| where Name == "score.completed"
| where TimeGenerated > ago(1h)
| extend durationMs = todouble(parse_json(Properties).durationMs)
| summarize avg(durationMs), percentile(durationMs, 95)
```

**Tasa de transacciones procesadas por unidad de tiempo:**
```kusto
AppEvents
| where Name == "ingest.request_total"
| summarize count() by bin(TimeGenerated, 1m)
| render timechart
```

**Proporción de transacciones marcadas sobre el total:**
```kusto
AppEvents
| where Name == "score.completed"
| extend caseOpened = tostring(parse_json(Properties).caseOpened)
| summarize total = count(), marcadas = countif(caseOpened == "true")
| extend proporcion = todouble(marcadas) / total
```

**Punto exacto de fallo de una transacción que no generó caso:**
```kusto
union AppEvents, AppExceptions
| where tostring(parse_json(Properties).transactionId) == "<TXN_ID>"
| order by TimeGenerated asc
```
La última fila antes de que la secuencia se corte (o la excepción con `stage` en
`Properties`) marca el punto exacto de fallo.

**Componente de mayor latencia del pipeline:**
```kusto
AppEvents
| where Name in ("ingest.persist", "ingest.publish_event", "score.completed", "case.opened", "explainer.generated", "document.verified", "document.failed")
| extend durationMs = todouble(parse_json(Properties).durationMs)
| summarize avg(durationMs) by Name
| order by avg_durationMs desc
```

## Alerta configurada

Ver `infra/modules/alerts.bicep`: dispara cuando se registran más de 3
`AppExceptions` en una ventana de 5 minutos, en cualquiera de los servicios.
Justificación completa en `docs/architecture-decisions.md`. Para provocarla en la
demo: detener `explainer-queue`'s consumidor (parar la réplica de `ca-scoring`, ver
"Comportamiento con el explicador detenido" más abajo) y enviar varios documentos
corruptos seguidos, o forzar un error de configuración (ej. apuntar
`COSMOS_ENDPOINT` a un valor inválido temporalmente).

## Comportamiento con el explicador detenido

Escalar `ca-scoring` a 0 réplicas (`az containerapp update --min-replicas 0
--max-replicas 0 --name ca-scoring-<suffix>`) detiene los 4 workers (score, case,
explainer, document) a la vez, porque viven en el mismo contenedor. Los mensajes que
lleguen a `cases-queue`/`explainer-queue` mientras tanto quedan retenidos en Service
Bus (no se pierden). Al reactivar la réplica, el backlog se procesa y las
explicaciones pendientes se generan — la latencia de ingesta nunca se vio afectada,
porque `ca-ingest` es un servicio completamente independiente.

## Nivel gratuito de ingesta de telemetría

Azure Monitor / Log Analytics incluye 5 GB/mes de ingesta gratuita **por workspace**,
de forma permanente (no es un trial). Estimación de consumo del proyecto: cada
evento custom (`AppEvents`) pesa ~1-2 KB serializado; con un volumen de prueba de
~5.000 transacciones/día durante las 3 semanas del proyecto (holgado para pruebas de
carga + demo), y ~6 eventos/transacción (ingest x2, score, case, explainer, y
ocasionalmente document), el consumo estimado es:

```
5.000 tx/día × 6 eventos × 1.5 KB ≈ 45 MB/día ≈ 1.35 GB/mes
```

Muy por debajo del límite gratuito de 5 GB/mes. El `SamplingSettings` en `host.json`
de la arquitectura anterior (Functions) ya no aplica — en Container Apps el SDK
`applicationinsights` v2 tiene su propio sampling adaptativo, deshabilitado
explícitamente aquí (`setSendLiveMetrics(false)`) porque el volumen del proyecto no
lo necesita.
