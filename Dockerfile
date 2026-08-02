FROM node:22-bookworm-slim AS base
RUN corepack enable && corepack prepare yarn@1.22.22 --activate \
  && apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app

FROM base AS deps
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile --non-interactive

FROM base AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN yarn build

FROM node:22-bookworm-slim AS app
ENV NODE_ENV=production PORT=3000 HOSTNAME=0.0.0.0
WORKDIR /app
RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=deps /app/node_modules/ws ./node_modules/ws
COPY docker/entrypoint-app.sh /usr/local/bin/entrypoint-app
RUN chmod 755 /usr/local/bin/entrypoint-app
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=8s --start-period=20s --retries=3 CMD curl -fsS http://127.0.0.1:3000/api/health >/dev/null || exit 1
ENTRYPOINT ["entrypoint-app"]
CMD ["node", "server.js"]
