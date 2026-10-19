# build stage
FROM node:lts-alpine AS build-stage
# Set environment variables for non-interactive npm installs
ENV NPM_CONFIG_LOGLEVEL warn
ENV CI true
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN npm install -g pnpm@9.11.0 && pnpm i --frozen-lockfile
COPY . .
RUN pnpm build

# production stage
FROM dhi.io/nginx:1 AS production-stage
COPY --from=build-stage /app/dist /usr/share/nginx/html
