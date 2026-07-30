# --- Etapa 1: instala dependencias con el lockfile, incluye devDependencies si las hubiera ---
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev --no-audit --no-fund

# --- Etapa 2: imagen final, solo runtime ---
# distroless-style: alpine + usuario no-root, sin npm/build tools en la imagen final.
# Ninguna capa de esta etapa toca secretos: las credenciales llegan por Managed
# Identity en runtime (env vars con endpoints, nunca claves) via Container Apps.
FROM node:20-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

# Usuario no-root: si el contenedor se ve comprometido, no corre como root.
RUN addgroup -S centinela && adduser -S centinela -G centinela

COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

USER centinela
EXPOSE 8080
ENV PORT=8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD node -e "require('http').get('http://127.0.0.1:8080/healthz', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

CMD ["node", "src/server.js"]
