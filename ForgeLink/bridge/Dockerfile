FROM node:24-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates procps && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --chown=node:node package.json config.example.json ./
COPY --chown=node:node src ./src
USER node
ENV FORGELINK_CONFIG=/config/config.json
ENV HOST=0.0.0.0
EXPOSE 8787
CMD ["node", "src/cli.mjs"]
