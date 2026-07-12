import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";

const config = loadConfig();
const app = await buildApp({ config });

const shutdown = async (signal: string) => {
  try {
    await app.close();
    process.stdout.write(`agent-cy-server stopped after ${signal}\n`);
    process.exitCode = 0;
  } catch {
    process.exitCode = 1;
  }
};

process.once("SIGINT", () => void shutdown("SIGINT"));
process.once("SIGTERM", () => void shutdown("SIGTERM"));

try {
  await app.listen({ host: config.host, port: config.port });
  process.stdout.write(`agent-cy-server listening on ${config.host}:${config.port}\n`);
} catch {
  process.exitCode = 1;
  await app.close();
}
