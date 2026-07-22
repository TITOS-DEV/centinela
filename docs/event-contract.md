# Contrato de eventos — Centinela

Este documento es la fuente de verdad del payload que cruza el pipeline. Si lo cambian,
lo cambian aquí primero y avisan al equipo — el motor de scoring (semana 2) consume
exactamente esta forma.

## 1. Payload de entrada a la API (`POST /api/transactions`)

Lo que manda el cliente origen (core bancario / pasarela de pagos, simulado en el proyecto).

```json
{
  "accountId": "acc_00381",
  "amount": 4200000,
  "currency": "COP",
  "type": "purchase",
  "channel": "pos",
  "merchant": {
    "id": "mer_9911",
    "name": "Electrodomesticos XYZ",
    "category": "electronics"
  },
  "location": {
    "lat": 6.2442,
    "lon": -75.5812,
    "city": "Medellín",
    "country": "CO"
  },
  "cardLast4": "4321",
  "originTimestamp": "2026-07-17T21:04:00.000Z"
}
```

Campos obligatorios: `accountId`, `amount`, `currency`, `type`, `location.lat`, `location.lon`, `originTimestamp`.
Si falta alguno, la API responde `400` — no se persiste nada a medias.

`type` ∈ `purchase | transfer | withdrawal`
`channel` ∈ `pos | online | atm | app`

## 2. Documento persistido en Cosmos DB (contenedor `transactions`, PK `/accountId`)

```json
{
  "id": "txn_5f3a...",
  "accountId": "acc_00381",
  "amount": 4200000,
  "currency": "COP",
  "type": "purchase",
  "channel": "pos",
  "merchant": { "id": "mer_9911", "name": "Electrodomesticos XYZ", "category": "electronics" },
  "location": { "lat": 6.2442, "lon": -75.5812, "city": "Medellín", "country": "CO" },
  "cardLast4": "4321",
  "originTimestamp": "2026-07-17T21:04:00.000Z",
  "receivedAt": "2026-07-17T21:04:00.412Z",
  "status": "received",
  "score": null,
  "ruleTriggers": []
}
```

`status` progresa: `received` → `scored` → `flagged` | `clean`.
`ruleTriggers` lo llena el motor en semana 2 — cada elemento debe tener regla, puntos y el dato
concreto que la disparó (no solo el número). Esto es lo que en semana 3 alimenta al explicador.

## 3. Evento publicado en Event Grid (topic `transaction-events`, evento `Centinela.Transaction.Created`)

```json
{
  "id": "evt_...",
  "eventType": "Centinela.Transaction.Created",
  "subject": "transactions/acc_00381",
  "eventTime": "2026-07-17T21:04:00.412Z",
  "dataVersion": "1.0",
  "data": {
    "transactionId": "txn_5f3a...",
    "accountId": "acc_00381"
  }
}
```

**Deliberadamente el evento va liviano** — solo `transactionId` + `accountId`. El consumidor
(scoring, semana 2) va a leer el documento completo desde Cosmos usando esas dos claves. Esto evita
que el evento cargue el payload completo dos veces y evita inconsistencias si el documento cambia
antes de que el consumidor lo procese.

## 4. Regla de oro

Todo lo que el motor de scoring necesite en semana 2 (histórico de la cuenta, umbral, reglas
disparadas con su dato concreto) tiene que poder derivarse de lo que este documento define. Si en
semana 2 se dan cuenta de que falta un campo, se agrega aquí primero, versionado (`dataVersion`),
no se improvisa en el código.
