#!/usr/bin/env bash
# start.sh — Levanta Centinela para la sustentación con un solo comando.
#
# No hay una "maquina virtual" que encender: la arquitectura de semana 3 usa
# Azure Container Apps (serverless), asi que "levantar el sistema" significa
# reactivar las réplicas que stop.sh puso en cero (ver stop.sh) y esperar a
# que el endpoint publico responda. No recrea ni redespliega nada — para eso
# esta deploy.sh o un push a main.
#
# Uso: ./start.sh
# Unico requisito real: tener az cli instalado. Si no hay sesion activa, este
# script la dispara solo (az login abre el navegador) -- no hace falta
# correr nada antes.

set -euo pipefail

RESOURCE_GROUP="rg-riwi-staging-v4"
SUFFIX="cel01a2b3"
INGEST_APP="ca-ingest-${SUFFIX}"
SCORING_APP="ca-scoring-${SUFFIX}"

echo ">> Verificando sesion de Azure..."
if ! az account show > /dev/null 2>&1; then
  echo "   sin sesion activa, abriendo az login..."
  az login -o none
fi
az account show --query "{subscription:name, id:id}" -o table

echo ">> Reactivando ca-ingest (min 1 réplica, para evitar cold-start en la demo)..."
az containerapp update \
  --resource-group "$RESOURCE_GROUP" \
  --name "$INGEST_APP" \
  --min-replicas 1 \
  --max-replicas 10 \
  -o none

echo ">> Reactivando ca-scoring (min 0, escala bajo demanda por profundidad de cola)..."
az containerapp update \
  --resource-group "$RESOURCE_GROUP" \
  --name "$SCORING_APP" \
  --min-replicas 0 \
  --max-replicas 10 \
  -o none

echo ">> Esperando a que ingest-api responda en /healthz..."
FQDN=$(az containerapp show --resource-group "$RESOURCE_GROUP" --name "$INGEST_APP" --query properties.configuration.ingress.fqdn -o tsv)

for i in $(seq 1 30); do
  if curl -sf "https://${FQDN}/healthz" > /dev/null; then
    echo ">> Sistema arriba."
    break
  fi
  echo "   aun no responde, reintentando (${i}/30)..."
  sleep 5
done

echo ""
echo "================================================================"
echo " Centinela — listo para la sustentación"
echo "================================================================"
echo " API de ingesta:      https://${FQDN}/api/transactions"
echo " Health check:         https://${FQDN}/healthz"
echo ""
echo " Ejemplo de transacción normal:"
echo "   curl -X POST https://${FQDN}/api/transactions -H 'Content-Type: application/json' -d @../docs/samples/transaccion-normal.json"
echo ""
echo " Escenario de transacción fraudulenta (dispara caso + explicación):"
echo "   ../docs/samples/demo-fraude.sh https://${FQDN}"
echo ""
echo " Carga para demostrar escalado:"
echo "   ./load-test.sh https://${FQDN}"
echo ""
echo " Observabilidad (Application Insights / Log Analytics):"
echo "   Resource Group: ${RESOURCE_GROUP}"
echo "   App Insights:   appi-centinela-${SUFFIX}  (Transaction Search / Logs)"
echo "   Query de trazabilidad por transacción, ver docs/observability.md"
echo "================================================================"
