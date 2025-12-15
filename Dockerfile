# ---------- BUILD STAGE ----------
FROM node:20-slim AS builder

WORKDIR /app

COPY package*.json ./

# Install pg + pg-hstore (Strapi Postgres drivers)
RUN npm install pg pg-hstore

RUN npm ci --production=false

COPY . .
RUN npm run build

# ---------- RUN STAGE ----------
FROM node:20-slim

WORKDIR /app

COPY --from=builder /app /app

EXPOSE 1337
CMD ["npm", "run", "start"]