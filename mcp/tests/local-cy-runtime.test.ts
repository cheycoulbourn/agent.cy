import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  ChatTurnResultSchema,
  LocalCyResponseSchema,
  LocalCyRuntimeStatusSchema,
  LocalCySchemaVersion,
} from "@agent-cy/contracts";
import { afterEach, describe, expect, it } from "vitest";

import { LocalCyRuntime, parseClaudeStructuredOutput } from "../src/local-cy-runtime.js";
import { AgentCyWorkspace, writeJsonAtomically } from "../src/workspace.js";

const temporaryDirectories: string[] = [];

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

describe("LocalCyRuntime", () => {
  it("recovers structured output returned as JSON text by the Agent SDK", () => {
    expect(parseClaudeStructuredOutput('{"ideas":[1,2,3]}')).toEqual({ ideas: [1, 2, 3] });
    expect(parseClaudeStructuredOutput('```json\n{"ideas":[1,2,3]}\n```')).toEqual({ ideas: [1, 2, 3] });
    expect(parseClaudeStructuredOutput('Here is the result:\n```json\n{"ideas":[1,2,3]}\n```\nDone.')).toEqual({ ideas: [1, 2, 3] });
    expect(parseClaudeStructuredOutput('Result: {"ideas":[1,2,3]}')).toEqual({ ideas: [1, 2, 3] });
    expect(parseClaudeStructuredOutput("Not structured JSON")).toBeUndefined();
  });

  it("does not churn the iCloud heartbeat on every queue poll", async () => {
    const directory = mkdtempSync(join(tmpdir(), "agentcy-local-cy-"));
    temporaryDirectories.push(directory);
    const workspace = new AgentCyWorkspace(directory);
    const runtime = new LocalCyRuntime(workspace, async () => {
      throw new Error("No generation expected.");
    });

    await runtime.runOnce();
    const first = LocalCyRuntimeStatusSchema.parse(JSON.parse(
      readFileSync(workspace.localCyStatusPath, "utf8"),
    ));
    await runtime.runOnce();
    const second = LocalCyRuntimeStatusSchema.parse(JSON.parse(
      readFileSync(workspace.localCyStatusPath, "utf8"),
    ));

    expect(second.updatedAt).toBe(first.updatedAt);
  });

  it("validates a queued request and writes a structured response", async () => {
    const directory = mkdtempSync(join(tmpdir(), "agentcy-local-cy-"));
    temporaryDirectories.push(directory);
    const workspace = new AgentCyWorkspace(directory);
    workspace.ensureDirectories();
    const id = "be4d7760-0d3e-4d67-9221-2d5d5162a277";
    writeJsonAtomically(join(workspace.localCyRequestsDirectory, `${id}.json`), {
      schemaVersion: LocalCySchemaVersion,
      id,
      operation: "chatTurn",
      createdAt: new Date().toISOString(),
      workspaceId: null,
      payload: validChatRequest(id),
    });

    const runtime = new LocalCyRuntime(workspace, async (_request, resultSchema) => ({
      result: resultSchema.parse({
        assistantMessage: "Start with the clearest idea you can make today.",
        suggestions: [],
        proposedAction: null,
      }),
      model: "claude-sonnet-test",
    }));

    await expect(runtime.runOnce()).resolves.toBe(1);
    const response = LocalCyResponseSchema.parse(JSON.parse(
      readFileSync(join(workspace.localCyResponsesDirectory, `${id}.json`), "utf8"),
    ));
    expect(response.status).toBe("succeeded");
    if (response.status === "succeeded") {
      expect(ChatTurnResultSchema.parse(response.result).assistantMessage).toContain("clearest idea");
    }
  });

  it("returns a creator-safe failure without leaking the upstream error", async () => {
    const directory = mkdtempSync(join(tmpdir(), "agentcy-local-cy-"));
    temporaryDirectories.push(directory);
    const workspace = new AgentCyWorkspace(directory);
    workspace.ensureDirectories();
    const id = "d74970f6-768e-468d-ab17-2bdd9140ab88";
    writeJsonAtomically(join(workspace.localCyRequestsDirectory, `${id}.json`), {
      schemaVersion: LocalCySchemaVersion,
      id,
      operation: "chatTurn",
      createdAt: new Date().toISOString(),
      workspaceId: null,
      payload: validChatRequest(id),
    });

    const runtime = new LocalCyRuntime(workspace, async () => {
      throw new Error("secret credential was rejected with 401");
    });

    await expect(runtime.runOnce()).resolves.toBe(1);
    const response = LocalCyResponseSchema.parse(JSON.parse(
      readFileSync(join(workspace.localCyResponsesDirectory, `${id}.json`), "utf8"),
    ));
    expect(response.status).toBe("failed");
    if (response.status === "failed") {
      expect(response.error.message).toBe("Claude needs to be signed in on your Mac before Local Cy can respond.");
      expect(response.error.message).not.toContain("secret");
    }
  });
});

function validChatRequest(operationId: string) {
  return {
    schemaVersion: "agent-cy.ai.v1",
    promptVersion: "chat-turn.v1",
    operationId,
    appBuild: "test",
    assistanceMode: "collaborate",
    creatorContext: {
      name: "Chey",
      primaryGoal: "Create useful content",
      selectedPlatforms: ["instagramReels"],
      voiceExamples: [],
      pillars: [],
      librarySummaries: [],
    },
    conversation: [{ messageId: "ffbdf55b-d39e-47ac-aa52-29e7b41e832a", role: "user", content: "What should I make?" }],
    relevantBriefIds: [],
  };
}
