# Centinela — Semana 1: Fundamentos

Entregable de esta semana: la API recibe transacciones, responde de inmediato y las persiste
particionadas por cuenta. **No hay scoring todavía.** Eso es semana 2.

## Checklist del día 1 (antes de tocar código)

- [ ] Crear la suscripción Azure free trial **hoy**. Si algún miembro de la célula ya tiene una
      cuenta vieja, no sirve — su crédito ya corrió o expiró.
- [ ] `az account show` — confirmar que están en la suscripción correcta antes de desplegar nada.
- [ ] Verificar en el portal (Quotas + Azure AI Foundry / Document Intelligence) que el tier
      gratuito **F0** de Document Intelligence está disponible en la región que van a usar. Esto
      es para semana 3, pero si no está disponible cambia dónde conviene desplegar todo lo demás
      — resuélvanlo ahora, no en la semana 3.
- [ ] Decidir la región (`LOCATION` en `deploy.sh`) confirmando que Cosmos free tier y
      Document Intelligence F0 estén ambos disponibles ahí. No siempre coinciden.

## Estructura del repo

```
centinela/
├── infra/
│   ├── main.bicep              # orquesta todo
│   ├── modules/
│   │   ├── storage.bicep
│   │   ├── cosmos.bicep        # particionado /accountId, free tier
│   │   ├── eventgrid.bicep     # desacople API <-> scoring
│   │   ├── keyvault.bicep
│   │   ├── function.bicep      # Consumption plan + Managed Identity
│   │   └── rbac.bicep          # permisos minimos de la identidad
│   └── deploy.sh
├── api/
│   ├── src/
│   │   ├── functions/ingestTransaction.js
│   │   ├── cosmosClient.js
│   │   ├── eventGridClient.js
│   │   └── validateTransaction.js
│   ├── host.json
│   ├── package.json
│   └── local.settings.json.example
└── docs/
    └── event-contract.md       # la forma de los payloads, no la cambien sin avisar al equipo
```

## Desplegar la infraestructura

```bash
az login
cd infra
# edita RESOURCE_GROUP, LOCATION y SUFFIX en deploy.sh (SUFFIX debe ser unico global)
./deploy.sh
```

Esto crea: resource group, storage account, Cosmos DB (free tier, contenedor `transactions`
particionado por `/accountId`), Event Grid topic, Key Vault, y el Function App con identidad
administrada y los 3 role assignments (Cosmos Data Contributor, Event Grid Data Sender,
Key Vault Secrets User) — nada más, nada de rol Owner/Contributor genérico.

## Publicar el código de la Function

```bash
cd api
npm install
func azure functionapp publish func-centinela-<SUFFIX>
```

## Probar

```bash
curl -X POST "https://func-centinela-<SUFFIX>.azurewebsites.net/api/transactions?code=<FUNCTION_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "accountId": "acc_00381",
    "amount": 4200000,
    "currency": "COP",
    "type": "purchase",
    "channel": "pos",
    "merchant": { "id": "mer_9911", "name": "Electrodomesticos XYZ", "category": "electronics" },
    "location": { "lat": 6.2442, "lon": -75.5812, "city": "Medellin", "country": "CO" },
    "cardLast4": "4321",
    "originTimestamp": "2026-07-17T21:04:00.000Z"
  }'
```

Respuesta esperada (inmediata, `202`):

```json
{ "transactionId": "txn_...", "status": "received", "receivedAt": "2026-07-17T21:04:00.412Z" }
```

Verificar en el portal (o `az cosmosdb sql query`... o el Data Explorer de Cosmos) que el
documento quedó en el contenedor `transactions`, y en el Event Grid topic que salió un evento
`Centinela.Transaction.Created` — hay una métrica de "Published Events" en el portal.

## Local (sin desplegar)

```bash
cd api
cp local.settings.json.example local.settings.json   # completar con endpoints reales
az login   # DefaultAzureCredential usa tu sesion local
npm install
func start
```

## Decisiones ya tomadas (para defender, no repetir)

| Decisión | Por qué |
|---|---|
| Cosmos particionado por `accountId` | Es la consulta que domina el sistema: "transacciones recientes de esta cuenta", en cada análisis de scoring (semana 2). |
| Consistencia `Session` en Cosmos, no `Strong` | No hay multi-región ni doble escritura concurrente sobre el mismo documento; Session ya garantiza que quien escribe ve su propia escritura. Más barato que Strong. |
| Event Grid, no Service Bus | No necesitamos orden estricto ni colas con reintento complejo — el scoring de semana 2 va a ser idempotente por `transactionId`, así que at-least-once alcanza. Event Grid tiene tier gratis más generoso. |
| Function App Consumption, no App Service Plan dedicado | Se paga por ejecución, no por cómputo prendido 24/7. Con el presupuesto de $60 en 21 días, un plan dedicado se come el crédito sin necesidad. |
| Managed Identity para Cosmos y Event Grid, sin claves | Menos secretos que rotar, menos superficie de fuga. Key Vault queda reservado para la clave de Document Intelligence en semana 3. |
| Evento liviano (solo IDs, no el payload completo) | Evita duplicar el estado de la transacción en dos lugares — el consumidor relee de Cosmos, que es la fuente de verdad. |

## Todavía NO existe en este entregable (a propósito)

- Motor de reglas / scoring (semana 2).
- Sistema de gestión de casos (semana 2/3).
- Explicador (semana 3).
- Verificación documental con Document Intelligence (semana 3).
- Pipeline de CI/CD (semana 3) — por ahora el deploy es manual vía `deploy.sh` + `func publish`,
  pero versionado y reproducible, que es lo que pide semana 1.
