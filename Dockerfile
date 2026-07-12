FROM node:24-bookworm-slim

ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
ENV DATA_FILE=/data/agent-cy-state.json

RUN npm install --global pnpm@11.7.0

WORKDIR /app

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json ./
COPY contracts/package.json contracts/tsconfig.json contracts/tsconfig.build.json ./contracts/
COPY server/package.json server/tsconfig.json server/tsconfig.build.json ./server/

RUN pnpm install --frozen-lockfile

COPY contracts ./contracts
COPY server ./server

RUN pnpm --filter @agent-cy/contracts build && pnpm --filter @agent-cy/server build

ENV NODE_ENV=production

EXPOSE 3000

CMD ["node", "server/dist/index.js"]
