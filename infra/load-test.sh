#!/usr/bin/env bash
# load-test.sh — Genera carga sobre ingest-api y muestra en vivo el número de
# réplicas de ca-ingest, para demostrar el criterio de aceptación de
# escalado: "la carga genera un aumento observable de instancias, y al
# cesar, el número se reduce".
#
# Uso: ./load-test.sh https://<fqdn-de-ingest-api>
#
# Métrica de escalado configurada: peticiones concurrentes por réplica
# (umbral: 10, ver containerapp-ingest.bicep). Esta carga usa 40 workers
# concurrentes sostenidos durante 2 minutos — muy por encima del umbral,
# para que el scale-out sea visible en la ventana de la sustentación.

set -euo pipefail

BASE_URL="${1:?Uso: ./load-test.sh https://<fqdn>}"
DURATION_SECONDS="${2:-120}"
CONCURRENCY="${3:-40}"
RESOURCE_GROUP="rg-riwi-staging-v4"
SUFFIX="cel01a2b3"
INGEST_APP="ca-ingest-${SUFFIX}"

if ! az account show > /dev/null 2>&1; then
  echo ">> sin sesion activa, abriendo az login..."
  az login -o none
fi

send_one_request() {
  curl -s -o /dev/null -w "%{http_code}\n" -X POST "${BASE_URL}/api/transactions" \
    -H "Content-Type: application/json" \
    -d "{
      \"accountId\": \"acc_loadtest_$((RANDOM % 500))\",
      \"amount\": $((RANDOM % 90000 + 10000)),
      \"currency\": \"COP\",
      \"type\": \"purchase\",
      \"channel\": \"online\",
      \"merchant\": { \"id\": \"mer_loadtest\", \"name\": \"Carga Sintetica\", \"category\": \"retail\" },
      \"location\": { \"lat\": 6.2442, \"lon\": -75.5812, \"city\": \"Medellin\", \"country\": \"CO\" },
      \"originTimestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\"
    }"
}
export -f send_one_request
export BASE_URL

monitor_replicas() {
  while true; do
    COUNT=$(az containerapp replica list --resource-group "$RESOURCE_GROUP" --name "$INGEST_APP" --query "length(@)" -o tsv 2>/dev/null || echo "?")
    echo "[$(date +%H:%M:%S)] réplicas de ${INGEST_APP}: ${COUNT}"
    sleep 10
  done
}

echo ">> Generando carga: ${CONCURRENCY} workers concurrentes durante ${DURATION_SECONDS}s contra ${BASE_URL}"
echo ">> Monitoreando réplicas en paralelo (Ctrl+C detiene todo)..."

monitor_replicas &
MONITOR_PID=$!
trap 'kill $MONITOR_PID 2>/dev/null || true' EXIT

END=$((SECONDS + DURATION_SECONDS))
REQUEST_COUNT=0
while [ $SECONDS -lt $END ]; do
  seq 1 "$CONCURRENCY" | xargs -P "$CONCURRENCY" -I{} bash -c send_one_request > /tmp/loadtest_results.txt
  REQUEST_COUNT=$((REQUEST_COUNT + CONCURRENCY))
done

echo ">> Carga detenida. Total de requests enviados: ${REQUEST_COUNT}"
echo ">> Dejando el monitor de réplicas corriendo 3 minutos más para ver el scale-down..."
sleep 180

kill "$MONITOR_PID" 2>/dev/null || true
echo ">> Fin. Revisar el log de arriba: el conteo de réplicas debió subir durante la carga y bajar después."
