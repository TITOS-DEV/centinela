# Optimización de imágenes de contenedor

## Tamaño final

| Imagen | Tamaño (local, sin comprimir) | Tamaño comprimido (lo que viaja al pull/push) |
|---|---|---|
| `ingest-api` | 370 MB | 64.9 MB |
| `scoring-engine` | 405 MB | 69.1 MB |

## Comparación contra una imagen sin optimizar

Se construyó una versión de referencia de `ingest-api` con las prácticas que este
proyecto evita — `node:20` completo (no `alpine`), sin build multi-stage, con
`npm install` en vez de `npm ci --omit=dev`, y copiando también la carpeta `test/`:

| Versión | Tamaño |
|---|---|
| Sin optimizar (`node:20`, single-stage, con devDependencies) | **1.78 GB** |
| Optimizada (la que se despliega) | **370 MB** |

**Reducción: ~79%** (4.8× más chica).

## Medidas aplicadas

1. **`node:20-alpine` en vez de `node:20`.** La base Debian completa carga
   herramientas de compilación y utilidades que esta API nunca usa; Alpine
   (musl + busybox) es ~170MB más liviana solo en la capa base.
2. **Build multi-stage** (`Dockerfile`, etapa `deps` + etapa `runtime`): la
   etapa `runtime` final no contiene el caché de `npm`, ni el `package-lock.json`
   completo, ni ninguna herramienta de build — solo `node_modules` ya resuelto y
   el código fuente.
3. **`npm ci --omit=dev`** en vez de `npm install`: instala exactamente lo que
   dice el lockfile (reproducible) y excluye devDependencies (no hay test
   runners, linters, ni tipos en la imagen final).
4. **`.dockerignore`** excluye `node_modules` local, `test/`, `.git`, `*.md` y
   cualquier `.env*` — nada de eso llega ni siquiera al build context, mucho
   menos a una capa de la imagen final.
5. **Usuario no-root** (`centinela`): no reduce el tamaño, pero es la otra mitad
   del requerimiento de esta sección — si el contenedor se compromete, no corre
   como root.

## Ningún secreto en ninguna capa

Las imágenes no reciben ninguna credencial durante el build — ni siquiera como
`ARG` o variable de entorno temporal. Todo (Cosmos, Event Grid, Service Bus,
Document Intelligence, ACR) se resuelve en **runtime** vía Managed Identity,
inyectada por Container Apps como variables de entorno con **endpoints**
(URLs), nunca claves. Esto es verificable con:

```bash
docker history --no-trunc acrcentinelacel01a2b3.azurecr.io/ingest-api:latest
```

que muestra únicamente las capas de `COPY`/`RUN npm ci`/`WORKDIR` — ninguna capa
con un `ENV` o `ARG` de secreto, porque nunca se declaró ninguno en el Dockerfile.
