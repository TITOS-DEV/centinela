#!/usr/bin/env bash
# deploy.sh — Reconstruye toda la infraestructura de Centinela desde cero.
# Requisitos: az cli autenticado (az login) contra la suscripción free trial del proyecto.

set -euo pipefail

# ---- Config: ajusten estos 3 valores por célula ----
RESOURCE_GROUP="rg-riwi-staging-v4"
LOCATION="centralus"           # verifiquen cuota de free tier Cosmos y Document Intelligence en esta región antes de fijarla
SUFFIX="cel01a2b3"           # único global: usen algo tipo iniciales+4 dígitos random, minúsculas/números, <=10 chars
# -----------------------------------------------------

echo ">> Verificando suscripción activa..."
az account show --query "{subscription:name, id:id}" -o table

echo ">> Creando resource group (si no existe)..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" -o table

echo ">> Validando el template antes de desplegar..."
az deployment group validate \
  --resource-group "$RESOURCE_GROUP" \
  --template-file main.bicep \
  --parameters suffix="$SUFFIX" location="$LOCATION"

echo ">> Desplegando infraestructura (main.bicep)..."
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file main.bicep \
  --parameters suffix="$SUFFIX" location="$LOCATION" \
  --name "centinela-week1-$(date +%Y%m%d%H%M%S)" \
  -o table

echo ">> Listo. Outputs:"
az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$(az deployment group list -g "$RESOURCE_GROUP" --query '[0].name' -o tsv)" \
  --query properties.outputs -o json

echo ""
echo ">> Siguiente paso: publicar el código de la Function"
echo "   cd ../api && func azure functionapp publish func-centinela-${SUFFIX}"
