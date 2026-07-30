#!/usr/bin/env bash
# deploy.sh — Aprovisiona TODO Centinela desde cero: infraestructura,
# imagenes de contenedor y despliegue de los Container Apps. Es el unico
# punto de entrada manual del proyecto — todo lo posterior (cada push a
# main) lo hace .github/workflows/deploy.yml sin intervencion humana.
#
# Requisitos: az cli autenticado (az login), docker corriendo localmente.
#
# Por que build+push ANTES del `deployment group create` final: los
# Container Apps (containerapp-ingest.bicep / containerapp-scoring.bicep)
# referencian una imagen por tag, y Azure valida que pueda resolverla al
# crear la revision. En un ambiente nuevo el ACR todavia no tiene ninguna
# imagen — por eso este script crea el registro primero, empuja las
# imagenes, y RECIEN DESPUES corre el despliegue completo (mismo orden que
# el pipeline de CI/CD).

set -euo pipefail

# ---- Config: ajusten estos valores por célula ----
RESOURCE_GROUP="rg-riwi-staging-v4"
LOCATION="centralus"          # verificado en semana 1: Cosmos free tier y Document Intelligence F0 disponibles aca
SUFFIX="cel01a2b3"             # único global, <=10 chars — el mismo de semana 1/2, para reusar Cosmos free tier
ALERT_EMAIL="${ALERT_EMAIL:-}" # email que recibe la alerta de Azure Monitor (requerido)
IMAGE_TAG="local-$(date +%Y%m%d%H%M%S)"
ACR_NAME="acrcentinela${SUFFIX}"
# -----------------------------------------------------

if [ -z "$ALERT_EMAIL" ]; then
  echo "ERROR: definan ALERT_EMAIL (ej: ALERT_EMAIL=analista@equipo.com ./deploy.sh)"
  exit 1
fi

if ! az account show > /dev/null 2>&1; then
  echo ">> sin sesion activa, abriendo az login..."
  az login -o none
fi

echo ">> Verificando suscripción activa..."
az account show --query "{subscription:name, id:id}" -o table

echo ">> Creando resource group (si no existe)..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" -o table

echo ">> Creando/verificando el registro de contenedores (bootstrap, antes del template completo)..."
az acr create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ACR_NAME" \
  --sku Basic \
  --admin-enabled false \
  -o table

echo ">> Login en el registro (via tu identidad de az login, no admin user/password)..."
az acr login --name "$ACR_NAME"

echo ">> Build y push de ingest-api..."
docker build -t "${ACR_NAME}.azurecr.io/ingest-api:${IMAGE_TAG}" -t "${ACR_NAME}.azurecr.io/ingest-api:latest" ../services/ingest-api
docker push "${ACR_NAME}.azurecr.io/ingest-api:${IMAGE_TAG}"
docker push "${ACR_NAME}.azurecr.io/ingest-api:latest"

echo ">> Build y push de scoring-engine..."
docker build -t "${ACR_NAME}.azurecr.io/scoring-engine:${IMAGE_TAG}" -t "${ACR_NAME}.azurecr.io/scoring-engine:latest" ../services/scoring-engine
docker push "${ACR_NAME}.azurecr.io/scoring-engine:${IMAGE_TAG}"
docker push "${ACR_NAME}.azurecr.io/scoring-engine:latest"

echo ">> Validando el template antes de desplegar..."
az deployment group validate \
  --resource-group "$RESOURCE_GROUP" \
  --template-file main.bicep \
  --parameters suffix="$SUFFIX" location="$LOCATION" imageTag="$IMAGE_TAG" alertEmailAddress="$ALERT_EMAIL"

echo ">> Desplegando infraestructura completa (main.bicep)..."
DEPLOYMENT_NAME="centinela-week3-$(date +%Y%m%d%H%M%S)"
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file main.bicep \
  --parameters suffix="$SUFFIX" location="$LOCATION" imageTag="$IMAGE_TAG" alertEmailAddress="$ALERT_EMAIL" \
  --name "$DEPLOYMENT_NAME" \
  -o table

echo ""
echo ">> Listo. Outputs:"
az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" \
  --query properties.outputs -o json

echo ""
echo ">> Siguiente paso: configurar el pipeline de CI/CD (ver docs/architecture-decisions.md,"
echo "   seccion 'Configurar GitHub Actions') para que los proximos despliegues sean automaticos."
echo ">> Para las jornadas de trabajo: ./start.sh al empezar, ./stop.sh al terminar."
