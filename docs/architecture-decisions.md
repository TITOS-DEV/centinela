# Centinela — Documento de decisiones de arquitectura

Cierra las tres semanas del proyecto. No es un registro cronológico de cambios — es la
justificación de las decisiones que definen el sistema tal como queda desplegado.

## 1. CI/CD: GitHub Actions

**Decisión:** GitHub Actions, con autenticación OIDC federada (sin secretos de larga
duración) contra un App Registration de Entra ID con permisos acotados al resource
group del proyecto.

**Qué se obtiene:**
- El pipeline vive en el mismo repositorio que el código — cero fricción para que
  cualquier integrante lo modifique sin salir de GitHub.
- OIDC federado elimina el riesgo de rotar/filtrar un client secret: GitHub emite un
  token de corta duración por cada corrida, que Entra ID valida contra una federated
  credential ya configurada. No hay ninguna contraseña en `Settings > Secrets`.
- Minutos de Actions gratuitos son generosos para un repo público/educativo (2000
  min/mes en repos privados de una cuenta gratuita, ilimitado en repos públicos).

**Qué se sacrifica:**
- Azure DevOps Pipelines tiene integración más profunda con Azure (service
  connections nativas, mejor soporte de *approval gates* multi-stage con revisores
  humanos por ambiente). GitHub Actions puede replicar esto con `environments` y
  reglas de protección, pero es más manual de configurar.
- Si el equipo ya usara Azure Boards/Repos para el resto del ciclo de vida, tener el
  pipeline en una plataforma distinta rompe la cohesión de herramientas.

**En qué contexto la decisión sería la contraria:** un equipo dentro de una empresa
que ya estandarizó en Azure DevOps (Boards, Repos, Artifacts) para todo su portafolio,
con necesidad real de *approval gates* formales entre ambientes (dev → staging →
prod) y un área de gobierno que audita despliegues — ahí Azure DevOps justifica la
fricción adicional de mantener una plataforma separada del código fuente.

## 2. Migración de Azure Functions a contenedores (Azure Container Apps)

Semana 1 y 2 corrieron sobre Azure Functions en plan Consumption. Semana 3 exige
empaquetar la API de ingesta y el motor de scoring como imágenes de contenedor en una
plataforma de contenedores gestionada, con reglas de escalado configurables y
demostrables — eso es difícil de controlar y demostrar con el autoescalado implícito
de Functions. Se migró todo el código de `api/` (Functions) a `services/ingest-api` y
`services/scoring-engine` (procesos Node planos, sin el runtime de Functions),
desplegados en Azure Container Apps.

**Por qué Container Apps y no AKS:** el alcance de la semana excluye explícitamente
"orquestación de contenedores con clusters gestionados". Container Apps administra el
plano de control (nodos, actualizaciones, red) por nosotros — es la opción "serverless"
de contenedores de Azure, con autoescalado nativo vía KEDA y un tier de consumo que
cobra por vCPU-s/GiB-s reales, no por nodos reservados.

**Por qué ya no hay Key Vault:** en la arquitectura final, cada componente se
autentica por Entra ID / Managed Identity contra todo lo que toca (Cosmos, Event
Grid, Service Bus, ACR, Document Intelligence, Storage). No queda ningún secreto —
ni connection string, ni API key — que gestionar. Mantener Key Vault desplegado sin
un solo secreto real adentro era carga sin función.

## 3. Reglas de escalado

### `ca-ingest` (API de ingesta): peticiones concurrentes por réplica

**Métrica elegida:** `concurrentRequests` (scale rule HTTP nativo de Container Apps),
umbral 10. **Por qué no CPU:** el trabajo de este servicio es esperar I/O de red
(escritura en Cosmos + publicación en Event Grid) — bajo carga, la CPU de una réplica
se mantiene baja mientras las requests se acumulan esperando esas dos llamadas. Un
scale rule de CPU habría reaccionado tarde o no habría reaccionado, porque la
sobrecarga real es de conexiones en vuelo, no de cómputo. **Comportamiento
esperado ante un pico:** cada réplica acepta hasta 10 requests concurrentes antes de
que KEDA solicite una réplica adicional; con tráfico sostenido por encima del
umbral, el número de réplicas sube en pasos hasta `maxReplicas` (10); al caer el
tráfico, las réplicas ociosas se retiran gradualmente (cooldown por defecto de
Container Apps, ~5 min) hasta `minReplicas` (1, para evitar cold-start en la demo).

### `ca-scoring` (motor de scoring + casos + explicador + documentos): profundidad de `scoring-queue`

**Métrica elegida:** `messageCount` (scaler KEDA `azure-servicebus`), umbral 5
mensajes por réplica. **Por qué no CPU ni RPS:** este servicio no tiene tráfico HTTP
entrante propio — su carga es el backlog de eventos que produce ingest-api de forma
indirecta (vía Event Grid → Service Bus). La única métrica que refleja "cuánto
trabajo pendiente hay" es la profundidad de la cola; CPU se mantendría bajo mientras
los mensajes se acumulan esperando ser leídos. **Comportamiento esperado ante un
pico:** si `scoring-queue` acumula más de 5 mensajes por réplica activa, KEDA agrega
réplicas (hasta `maxReplicas`=10); con `minReplicas`=0, el servicio escala a cero
cuando no hay backlog, sin costo de cómputo ocioso.

## 4. Componente que se satura primero bajo carga

Con los recursos asignados (0.5 vCPU / 1GiB por réplica, hasta 10 réplicas por
servicio), el cuello de botella esperado **no es el cómputo de los contenedores** —
es el **throughput de Cosmos DB** (400 RU/s compartidos a nivel de base de datos,
dentro del free tier de 1000 RU/s). Bajo carga sostenida y con suficientes réplicas
de `ingest-api` escritas en paralelo, Cosmos empieza a responder `429 (Request Rate
Too Large)` antes de que se agoten las réplicas máximas configuradas.

**Mitigación aplicada:** el SDK de Cosmos reintenta automáticamente los 429 con
backoff exponencial (comportamiento por defecto de `@azure/cosmos`), lo cual absorbe
picos cortos a costa de latencia adicional, no de errores al cliente.

**Mitigación NO aplicada (fuera de alcance, para no exceder el crédito):** subir el
throughput provisionado o migrar a modo autoscale de Cosmos — ambos tienen costo por
fuera del free tier. Queda documentado como el primer paso si el proyecto escalara a
producción real.

## 4.1. Identidad administrada: tres bugs reales encontrados al desplegar

El primer despliegue real (no la validación de plantilla, que no los detecta) expuso
tres problemas de ordenamiento entre identidades administradas y RBAC, todos con el
mismo patrón de fondo — **un recurso valida el permiso de forma síncrona al
crearse, no solo al usarlo**:

1. **Container Apps con identidad system-assigned no pueden auto-otorgarse
   `AcrPull`.** El principalId solo existe al crear el Container App, pero esa
   misma creación ya intenta descargar la imagen. Se resolvió con identidades
   **user-assigned** (`managed-identities.bicep`), creadas antes que los Container
   Apps, para que `rbac.bicep` pudiera otorgar `AcrPull` primero.
2. **`DefaultAzureCredential()` sin `managedIdentityClientId` falla con identidades
   user-assigned.** A diferencia de system-assigned (donde no hay ambigüedad), con
   user-assigned el SDK necesita que se le diga explícitamente cuál identidad usar
   — sin eso, falla con "Unable to load the proper Managed Identity" aunque el rol
   esté bien otorgado.
3. **Event Grid no puede entregar a una cola de Service Bus con
   `disableLocalAuth: true` sin su propia identidad + rol `Service Bus Data
   Sender`**, y además **valida ese permiso al crear la `eventSubscription`**, no
   solo al entregar el primer evento — igual que el caso de ACR Pull. Se resolvió
   separando la creación del recurso con identidad (`storage-systemtopic.bicep`)
   de la creación de las suscripciones (`eventgrid-subscriptions.bicep`), con
   `rbac.bicep` en medio.

Ninguno de los tres lo detecta `az deployment group validate` — solo aparecen al
desplegar de verdad, lo que confirma por qué el criterio de aceptación exige probar
el sistema desplegado y no solo la plantilla.

## 5. Qué haríamos distinto si empezáramos de nuevo

- **Instrumentar observabilidad desde el día 1**, no al final de semana 3. Retroactivamente
  agregar `transactionId` como customDimension a cada servicio obligó a tocar los
  cuatro componentes a la vez — si hubiera estado desde semana 1, cada pieza nueva
  solo habría tenido que seguir el patrón ya existente.
- **Separar ingest-api y scoring-engine en repos o al menos carpetas independientes
  desde semana 1**, en vez de migrar de Functions monolítico a contenedores a mitad
  de proyecto. La migración de semana 3 fue directa porque el código ya estaba
  desacoplado por responsabilidad, pero el cambio de *hosting model* completo
  (Functions → contenedores planos) fue trabajo evitable.
  Habríamos elegido Container Apps desde el principio si el alcance completo de las
  3 semanas hubiera sido visible desde el día 1.
- **Definir la convención de partición del contenedor `cases` (`/accountId`) al mismo
  tiempo que `transactions`**, no en semana 3 — evita tener que decidir bajo presión
  de tiempo si convenía particionar por `accountId` o por `caseId`.
- **No mezclar el nombre del repositorio (`centinela` vs. `centinela_project`) con el
  contenido real del proyecto.** Durante la semana 3 se encontraron dos carpetas
  locales con remotos cruzados (una apuntaba a `centinela_project.git` con solo el
  código de semana 1, la otra a `centinela.git` con el motor de scoring de semana 2
  sin commitear). Un único repo, con un único remoto claro desde el día 1, habría
  evitado el riesgo de perder trabajo.

## 6. Consumo de crédito

- `stop.sh` escala ambos Container Apps a 0 réplicas al cierre de cada jornada — el
  único costo que permanece mientras el sistema está "apagado" es el fijo de ACR
  Basic (~$5/mes) y el almacenamiento mínimo de Cosmos/Storage (dentro del free
  tier). Nada de esto se factura por hora de cómputo ocioso.
- Ver `docs/credit-report.md` (entregable #10) para el consumo final medido al
  cierre del proyecto.
