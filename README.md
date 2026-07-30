# Centinela — Semana 3: despliegue, explicabilidad y observabilidad

Motor de detección de fraude transaccional. Este README lleva a un tercero sin
contexto previo desde un clon vacío del repositorio hasta el sistema corriendo en
Azure. Para el detalle de negocio ver `Centinela.md`; para las decisiones de
arquitectura y sus justificaciones, `docs/architecture-decisions.md`.

## Arquitectura (resumen)

```
ingest-api (Container App, HTTP público)
   │  persiste en Cosmos, publica "Centinela.Transaction.Created" en Event Grid
   ▼
Event Grid ──▶ Service Bus (scoring-queue)
   ▼
scoring-engine (Container App, sin ingress — 4 workers en un mismo proceso)
   │
   ├─ scoreWorker      : evalúa las 4 reglas, decide caso sí/no
   ├─ caseWorker        (cases-queue)      : abre el caso en Cosmos
   ├─ explainerWorker    (explainer-queue) : genera la explicación (async)
   └─ documentWorker      (documents-queue): verificación documental (Document Intelligence)
```

Todo se autentica por Managed Identity / Entra ID — no hay una sola clave o
connection string en el repo, en la configuración del pipeline, ni en las imágenes.

## Requisitos previos

- `az` CLI ≥ 2.60, autenticado con una suscripción de Azure con crédito disponible.
- Docker (para construir las imágenes).
- Node.js ≥ 20 (para correr las pruebas localmente si se desea).
- Una cuenta de GitHub con permisos sobre el repo, para configurar el pipeline.

## 1. Aprovisionar todo desde cero

```bash
az login
cd infra
ALERT_EMAIL="tu-correo@equipo.com" ./deploy.sh
```

`deploy.sh` crea el resource group, construye y publica las dos imágenes en un
registro de contenedores nuevo, y despliega el resto de la infraestructura
(Cosmos, Event Grid, Service Bus, Container Apps Environment, los dos Container
Apps, Log Analytics + Application Insights, Document Intelligence, y la alerta de
Azure Monitor). Al final imprime los outputs, incluyendo la URL pública de
`ingest-api`.

Ajustar `RESOURCE_GROUP`, `LOCATION` y `SUFFIX` al inicio del script si se quiere un
ambiente distinto al de la célula (`SUFFIX` debe ser único global y ≤10 caracteres).

## 2. Configurar los secretos del pipeline de CI/CD

El pipeline (`.github/workflows/deploy.yml`) se autentica contra Azure vía OIDC
federado — nunca con un client secret. Pasos (una sola vez):

```bash
# 1. Crear el App Registration + Service Principal del pipeline
az ad app create --display-name "centinela-github-actions" --query appId -o tsv
# guardar el appId devuelto como <APP_ID>
az ad sp create --id <APP_ID>

# 2. Federar con el repo de GitHub (branch main)
az ad app federated-credential create --id <APP_ID> --parameters '{
  "name": "centinela-main-branch",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:TITOS-DEV/centinela:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
# Si el repo fue renombrado o transferido alguna vez, GitHub puede emitir el
# subject con IDs numéricos en vez del nombre (ej.
# "repo:TITOS-DEV@181672590/centinela@1308792352:ref:refs/heads/main") — si el
# primer push falla con AADSTS700213 "No matching federated identity record",
# revisar el subject exacto en el log del job "Azure login" y actualizar la
# federated credential (az ad app federated-credential update) para que coincida.

# 3. Dar permisos sobre el resource group. Contributor no alcanza: main.bicep
#    despliega roleAssignments (rbac.bicep), y crear/modificar RBAC requiere
#    ademas "User Access Administrator" (o Owner) sobre el mismo scope --
#    Contributor solo no tiene el permiso Microsoft.Authorization/roleAssignments/write.
az role assignment create \
  --assignee <APP_ID> \
  --role Contributor \
  --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-riwi-staging-v4
az role assignment create \
  --assignee <APP_ID> \
  --role "User Access Administrator" \
  --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-riwi-staging-v4

# 4. Cargar los secrets/vars en GitHub (con gh cli, desde la raíz del repo)
gh secret set AZURE_CLIENT_ID --body "<APP_ID>"
gh secret set AZURE_TENANT_ID --body "$(az account show --query tenantId -o tsv)"
gh secret set AZURE_SUBSCRIPTION_ID --body "$(az account show --query id -o tsv)"
gh secret set ALERT_EMAIL_ADDRESS --body "tu-correo@equipo.com"

gh variable set AZURE_RESOURCE_GROUP --body "rg-riwi-staging-v4"
gh variable set ACR_NAME --body "acrcentinela<SUFFIX>"
gh variable set CENTINELA_SUFFIX --body "<SUFFIX>"
gh variable set AZURE_LOCATION --body "centralus"
```

Desde ese momento, cada push a `main` construye, prueba, empaqueta y despliega solo.
Un `pull_request` corre build+test pero nunca despliega (`if: github.ref ==
'refs/heads/main'` en el job de deploy).

## 3. Operación diaria (sustentación incluida)

```bash
cd infra
./start.sh        # reactiva los Container Apps, espera el healthcheck, imprime los endpoints
./load-test.sh <fqdn-impreso-por-start.sh>   # genera carga y muestra el escalado en vivo
../docs/samples/demo-fraude.sh <fqdn>        # escenario de transacción fraudulenta con explicación
./stop.sh         # al cerrar la jornada: escala todo a 0 réplicas, sin destruir infraestructura
```

No hay una "máquina virtual" que prender/apagar en esta arquitectura — el
equivalente es escalar los Container Apps (ver comentarios dentro de `start.sh` /
`stop.sh`).

## Estructura del repo

```
centinela/
├── .github/workflows/deploy.yml   # CI/CD: build -> test -> imagen -> push -> deploy
├── infra/
│   ├── main.bicep                 # orquesta todo
│   ├── modules/                   # storage, cosmos, eventgrid, servicebus, acr,
│   │                              # loganalytics, appinsights, documentintelligence,
│   │                              # containerappsenv, containerapp-ingest/scoring, rbac, alerts
│   ├── deploy.sh                  # aprovisionamiento desde cero
│   ├── start.sh / stop.sh         # operación diaria / sustentación
│   └── load-test.sh               # demuestra el escalado bajo carga
├── services/
│   ├── ingest-api/                # Container App con ingress HTTP público
│   └── scoring-engine/            # Container App sin ingress, 4 workers de Service Bus
└── docs/
    ├── architecture-decisions.md  # ADR cerrado, 3 semanas
    ├── observability.md           # KQL, límites del free tier, alerta
    ├── document-verification.md   # flujo y manejo de fallos
    ├── image-optimization.md      # tamaño de imágenes y medidas aplicadas
    ├── credit-report.md           # consumo de crédito al cierre
    ├── event-contract.md
    └── samples/                   # payloads y script de demo de fraude
```

## Pruebas

```bash
cd services/ingest-api && npm ci && npm test
cd services/scoring-engine && npm ci && npm test
```

## Decisiones clave (resumen — detalle completo en `docs/architecture-decisions.md`)

| Decisión | Por qué |
|---|---|
| Container Apps, no AKS | El alcance excluye clusters gestionados; Container Apps administra el plano de control por nosotros. |
| GitHub Actions + OIDC federado | Sin secretos de larga duración; vive junto al código. |
| `ingest-api` escala por peticiones concurrentes | Su cuello de botella es I/O (Cosmos + Event Grid), no CPU. |
| `scoring-engine` escala por profundidad de `scoring-queue` | No tiene tráfico entrante propio; la cola es la única señal de trabajo pendiente. |
| Sin Key Vault | Todo el sistema usa Managed Identity — no queda ningún secreto que gestionar. |
| Explicador async, desacoplado por `explainer-queue` | El caso se abre sin esperar la explicación; si el explicador cae, el backlog se procesa al volver. |
