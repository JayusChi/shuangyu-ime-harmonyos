ARG NODE_BASE_IMAGE
FROM ${NODE_BASE_IMAGE}

WORKDIR /app
COPY package.json ./
COPY src ./src

ENV NODE_ENV=production
USER 10001:10001
EXPOSE 8080
CMD ["node", "src/server.mjs"]
