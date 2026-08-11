import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { z } from "zod";

import {
  AiEndpointRegistry,
  ContractSchemaRegistry,
  type ContractSchemaName,
} from "./registry.js";

function withoutDialect(schema: unknown): Record<string, unknown> {
  const value = schema as Record<string, unknown>;
  const { $schema: _dialect, ...rest } = value;
  return rest;
}

const definitions = Object.fromEntries(
  Object.entries(ContractSchemaRegistry).map(([name, schema]) => [
    name,
    withoutDialect(z.toJSONSchema(schema, { unrepresentable: "any" })),
  ]),
);

const jsonSchemaBundle = {
  $schema: "https://json-schema.org/draft/2020-12/schema",
  title: "agent.cy canonical contracts",
  $defs: definitions,
};

function schemaReference(name: ContractSchemaName) {
  return { $ref: `#/components/schemas/${name}` };
}

const aiPaths = Object.fromEntries(
  Object.entries(AiEndpointRegistry).map(([operationId, endpoint]) => [
    endpoint.path,
    {
      post: {
        operationId,
        security: [{ installationCredential: [] }],
        requestBody: {
          required: true,
          content: {
            "application/json": {
              schema: schemaReference(endpoint.requestSchema),
            },
          },
        },
        responses: {
          "200": {
            description: `SSE stream containing a validated ${endpoint.resultSchema}`,
            content: {
              "text/event-stream": {
                schema: { type: "string" },
              },
            },
            "x-agent-cy-result-schema": schemaReference(endpoint.resultSchema),
          },
        },
      },
    },
  ]),
);

function jsonPost(
  operationId: string,
  requestSchema: ContractSchemaName,
  resultSchema: ContractSchemaName,
  statusCode: string,
  security: "installation" | "revenueCat" | "none",
) {
  const securityRequirement =
    security === "installation"
      ? [{ installationCredential: [] }]
      : security === "revenueCat"
        ? [{ revenueCatWebhookSecret: [] }]
        : [];
  return {
    post: {
      operationId,
      security: securityRequirement,
      requestBody: {
        required: true,
        content: {
          "application/json": { schema: schemaReference(requestSchema) },
        },
      },
      responses: {
        [statusCode]: {
          description: "Successful response",
          content: {
            "application/json": { schema: schemaReference(resultSchema) },
          },
        },
      },
    },
  };
}

const openApi = {
  openapi: "3.1.0",
  jsonSchemaDialect: "https://json-schema.org/draft/2020-12/schema",
  info: {
    title: "agent.cy API",
    version: "0.1.0",
    description: "Thin, privacy-scoped AI proxy for the agent.cy iPhone app.",
  },
  paths: {
    ...aiPaths,
    "/v1/installations/redeem": jsonPost(
      "redeemInstallation",
      "InstallationRedeemRequest",
      "InstallationRedeemResult",
      "201",
      "none",
    ),
    "/v1/accounts/apple/link": jsonPost(
      "linkAppleAccount",
      "AppleAccountAuthorizationRequest",
      "AppleAccountAuthorizationResult",
      "200",
      "installation",
    ),
    "/v1/accounts/apple/sign-in": jsonPost(
      "signInWithApple",
      "AppleAccountAuthorizationRequest",
      "AppleAccountAuthorizationResult",
      "201",
      "none",
    ),
    "/v1/inspiration/extract": jsonPost(
      "extractInspiration",
      "InspirationExtractRequest",
      "InspirationExtractResult",
      "200",
      "installation",
    ),
    "/v1/telemetry/events": jsonPost(
      "recordTelemetryEvents",
      "TelemetryEventsRequest",
      "TelemetryEventsResult",
      "202",
      "installation",
    ),
    "/v1/privacy/delete": jsonPost(
      "deletePrivacyMetadata",
      "PrivacyDeleteRequest",
      "PrivacyDeleteResult",
      "200",
      "installation",
    ),
    "/v1/webhooks/revenuecat": jsonPost(
      "receiveRevenueCatWebhook",
      "RevenueCatWebhookRequest",
      "RevenueCatWebhookResult",
      "200",
      "revenueCat",
    ),
    "/healthz": {
      get: {
        operationId: "healthCheck",
        security: [],
        responses: {
          "200": {
            description: "Service is healthy",
            content: {
              "application/json": { schema: schemaReference("HealthResult") },
            },
          },
        },
      },
    },
  },
  components: {
    schemas: definitions,
    securitySchemes: {
      installationCredential: {
        type: "http",
        scheme: "bearer",
      },
      revenueCatWebhookSecret: {
        type: "apiKey",
        in: "header",
        name: "Authorization",
      },
    },
  },
};

const packageRoot = resolve(
  dirname(fileURLToPath(import.meta.url)),
  import.meta.url.includes("/dist/") ? ".." : "../..",
);
const generatedDirectory = resolve(packageRoot, "generated");
mkdirSync(generatedDirectory, { recursive: true });
writeFileSync(
  resolve(generatedDirectory, "contracts.schema.json"),
  `${JSON.stringify(jsonSchemaBundle, null, 2)}\n`,
);
writeFileSync(
  resolve(generatedDirectory, "openapi.json"),
  `${JSON.stringify(openApi, null, 2)}\n`,
);
