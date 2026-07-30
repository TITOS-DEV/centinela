#!/usr/bin/env bash
# stop.sh — Apaga el cómputo de Centinela al cierre de la jornada sin
# destruir nada. Escala ambos Container Apps a 0 réplicas (0 costo de
# cómputo mientras no hay tráfico) dejando Cosmos, Storage, Service Bus,
# Event Grid, ACR y Document Intelligence intactos — todos facturan por uso
# o tienen un costo fijo mínimo, no por "estar prendidos" (ver
# docs/architecture-decisions.md, sección "Consumo de crédito").
#
# Uso: ./stop.sh
# Para volver a levantar: ./start.sh

set -euo pipefail

RESOURCE_GROUP="rg-riwi-staging-v4"
SUFFIX="cel01a2b3"
INGEST_APP="ca-ingest-${SUFFIX}"
SCORING_APP="ca-scoring-${SUFFIX}"

if ! az account show > /dev/null 2>&1; then
  echo ">> sin sesion activa, abriendo az login..."
  az login -o none
fi

echo ">> Escalando ca-ingest a 0 réplicas..."
az containerapp update \
  --resource-group "$RESOURCE_GROUP" \
  --name "$INGEST_APP" \
  --min-replicas 0 \
  --max-replicas 0 \
  -o none

echo ">> Escalando ca-scoring a 0 réplicas..."
az containerapp update \
  --resource-group "$RESOURCE_GROUP" \
  --name "$SCORING_APP" \
  --min-replicas 0 \
  --max-replicas 0 \
  -o none

echo ">> Listo. Cómputo en cero. Para retomar: ./start.sh"
