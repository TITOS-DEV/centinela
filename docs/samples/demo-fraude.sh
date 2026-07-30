#!/usr/bin/env bash
# demo-fraude.sh — Escenario de fraude para la sustentación en vivo.
#
# Envia 3 transacciones "normales" de la misma cuenta (establecen el
# comportamiento histórico: montos ~45-55k, siempre en Medellín) y luego UNA
# transacción que dispara 3 de las 4 reglas simultaneamente:
#   - velocity: 4 transacciones en pocos segundos (máximo esperado: 3)
#   - amount_anomaly: $4.200.000 vs. un histórico de ~$50.000
#   - geo_impossible: Medellín -> Madrid en segundos
#   - risky_merchant: categoría "crypto_exchange" (marcada por defecto, ver
#     containerapp-scoring.bicep)
# Score esperado muy por encima del umbral (70) incluso si solo 2 de las 4
# reglas activan — margen amplio a propósito para que la demo no dependa de
# timing exacto.
#
# Uso: ./demo-fraude.sh https://<fqdn-de-ingest-api>

set -euo pipefail

BASE_URL="${1:?Uso: ./demo-fraude.sh https://<fqdn>}"
ACCOUNT_ID="acc_demo_fraude_$(date +%s)" # cuenta nueva cada corrida, para no arrastrar historico de corridas previas

send() {
  local amount="$1" city="$2" lat="$3" lon="$4" category="$5"
  curl -s -X POST "${BASE_URL}/api/transactions" \
    -H "Content-Type: application/json" \
    -d "{
      \"accountId\": \"${ACCOUNT_ID}\",
      \"amount\": ${amount},
      \"currency\": \"COP\",
      \"type\": \"purchase\",
      \"channel\": \"online\",
      \"merchant\": { \"id\": \"mer_demo\", \"name\": \"Comercio Demo\", \"category\": \"${category}\" },
      \"location\": { \"lat\": ${lat}, \"lon\": ${lon}, \"city\": \"${city}\", \"country\": \"CO\" },
      \"originTimestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\"
    }" | python3 -m json.tool
  echo ""
}

echo ">> Cuenta de la demo: ${ACCOUNT_ID}"
echo ">> Enviando 3 transacciones normales (establecen el histórico)..."
send 48000 Medellin 6.2442 -75.5812 groceries
sleep 2
send 52000 Medellin 6.2442 -75.5812 groceries
sleep 2
send 45000 Medellin 6.2442 -75.5812 groceries
sleep 2

echo ""
echo ">> Enviando la transacción fraudulenta (monto atípico + geo imposible + velocidad + comercio de riesgo)..."
send 4200000 Madrid 40.4168 -3.7038 crypto_exchange

echo ""
echo ">> Revisar en Cosmos (contenedor 'cases') o en Application Insights el caso abierto para ${ACCOUNT_ID}."
echo ">> La explicación llega unos segundos después (generación asíncrona, ver explainerWorker)."
