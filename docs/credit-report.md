# Reporte de crédito consumido

Completar al cierre del proyecto (entregable #10), antes de la sustentación.

## Cómo medir

```bash
# Resumen por servicio, mes en curso
az consumption usage list \
  --start-date "$(date -d '21 days ago' +%Y-%m-%d)" \
  --end-date "$(date +%Y-%m-%d)" \
  --query "[].{producto:product, costo:pretaxCost, moneda:currency}" \
  -o table
```

O directamente en el portal: **Cost Management + Billing → Cost analysis**, filtrado
por el resource group `rg-riwi-staging-v4`, rango de fechas = duración del proyecto.

**Nota:** en esta suscripción (`az consumption usage list`) el campo `costo` devuelve
`None` para todos los registros — es una limitación conocida de las suscripciones
tipo trial/sponsorship, que no exponen costo acumulado vía esa API. El portal
(Cost Management + Billing) sí lo muestra siempre; es la fuente confiable para este
reporte, no la CLI.

## Recursos con costo real (fuera del free tier)

| Recurso | Costo esperado | Por qué no es gratis |
|---|---|---|
| Azure Container Registry (Basic) | ~$5/mes fijo | No hay tier F0 para ACR; Basic es el más barato con soporte de identidad administrada. |
| Container Apps (cómputo) | Variable, ~$0 en reposo | Se factura por vCPU-s/GiB-s reales. `stop.sh` lo lleva a 0 al cerrar cada jornada. |
| Log Analytics / App Insights | $0 hasta 5GB/mes | Ver `docs/observability.md` para el estimado de consumo del proyecto. |
| Service Bus (Basic) | Centavos, por operación | Sin cargo fijo relevante en el tier Basic. |

## Recursos 100% gratuitos en este proyecto

- Cosmos DB (free tier, 1000 RU/s + 25GB permanente).
- Event Grid (tier gratuito, ~100k operaciones/mes).
- Azure AI Document Intelligence (F0, 500 páginas/mes).
- Azure Functions (ya no aplica — migrado a Container Apps en semana 3).

## Resultado final

_(completar antes de la sustentación)_

- **Costo total acumulado:** $ ___ USD
- **Recurso de mayor costo:** ___
- **¿Se mantuvo bajo los $60 USD del criterio de aceptación?** Sí / No
