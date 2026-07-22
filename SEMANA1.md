# Centinela — Weekly Semana 1

**Fecha:** 17 de julio, 2026
**Sprint:** Semana 1 — Fundamentos e ingesta de transacciones
**Integrantes:** Nicolas-Jhonatan-Santiago V- Juan Esteban

## Objetivo de la semana

Levantar la infraestructura base en Azure y exponer una API que reciba transacciones, las valide, las persista y publique un evento — todo desacoplado del análisis de fraude (que llega en Semana 2).

## Qué se logró

- **Infraestructura como código (Bicep):** desplegado `main.bicep` completo, sin ningún recurso creado manualmente desde el portal. El template orquesta Storage Account, Cosmos DB (modo serverless), Event Grid Topic, Key Vault, Function App y las asignaciones RBAC necesarias, todo parametrizado por un `suffix` único.
- **API de ingesta funcionando:** endpoint `POST /api/transactions` desplegado en Azure Functions (Node.js, modelo de programación v4), corriendo en `func-centinela-cel01a2b3`.
- **Validación de payload:** reglas de negocio activas (canal debe ser `pos`/`online`/`atm`/`app`, `location` requiere `lat`/`lon` numéricos, entre otras). Probado con casos inválidos (rechazo 400) y válidos (200).
- **Persistencia confirmada:** las transacciones válidas se guardan en Cosmos DB, contenedor `transactions` particionado por `accountId`. Verificado directamente en Data Explorer.
- **Autenticación sin secretos embebidos:** el Function App usa Managed Identity con rol de datos sobre Cosmos (`Cosmos DB Built-in Data Contributor`), en vez de connection strings o claves en el código.
- **Evento publicado:** al persistir, se emite el evento a Event Grid para que el consumidor de scoring (Semana 2) lo procese de forma asíncrona.

## Problemas resueltos en el camino

- Instalación de Azure Functions Core Tools en Ubuntu 24.04.
- Registro de los resource providers necesarios en la suscripción (`Microsoft.Web`, `Microsoft.DocumentDB`, `Microsoft.EventGrid`), que no estaban habilitados por defecto.
- Confirmación de que el proyecto ya incluía `infra/deploy.sh` como único punto de entrada para reconstruir todo el entorno — evita repetir creación manual de recursos.

## Pendiente / próximos pasos

- Rotar la Cosmos Account Key expuesta durante el debugging (ya no se usa en runtime, pero sigue activa).
- Documentar el contrato de eventos publicado en Event Grid (`docs/event-contract.md`) si aún no refleja el payload real emitido.
- Semana 2: construir el consumidor serverless que procese el evento, calcule el score con las reglas heurísticas y abra el caso cuando se supere el umbral.

## Endpoint de referencia

```
POST https://func-centinela-cel01a2b3.azurewebsites.net/api/transactions
```