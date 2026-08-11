import { chmodSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  ChatTurnResultSchema,
  InspirationShapeResultSchema,
  LocalCyResponseSchema,
  LocalCyRuntimeStatusSchema,
  LocalCySchemaVersion,
  SparkTurnResultSchema,
} from "@agent-cy/contracts";
import { afterEach, describe, expect, it } from "vitest";

import {
  LocalCyRuntime,
  parseClaudeStructuredOutput,
  resolveClaudeCodeExecutable,
} from "../src/local-cy-runtime.js";
import { AgentCyWorkspace, writeJsonAtomically } from "../src/workspace.js";

const temporaryDirectories: string[] = [];

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

describe("LocalCyRuntime", () => {
  it("resolves an explicitly configured Claude Code executable", () => {
    const directory = mkdtempSync(join(tmpdir(), "agentcy-claude-bin-"));
    temporaryDirectories.push(directory);
    const executable = join(directory, "claude");
    writeJsonAtomically(executable, {});
    // writeJsonAtomically creates a private regular file, so add execute access
    // to model the installed Claude Code CLI.
    chmodSync(executable, 0o700);

    expect(resolveClaudeCodeExecutable({
      AGENTCY_CLAUDE_EXECUTABLE: executable,
      PATH: "",
    }, directory)).toBe(executable);
  });

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

  it("accepts a usable partial Spark result and restores the request working state", async () => {
    const directory = mkdtempSync(join(tmpdir(), "agentcy-local-cy-"));
    temporaryDirectories.push(directory);
    const workspace = new AgentCyWorkspace(directory);
    workspace.ensureDirectories();
    const id = "b7bd60a9-d19c-49f5-bcb0-11b6f661ca31";
    writeJsonAtomically(join(workspace.localCyRequestsDirectory, `${id}.json`), {
      schemaVersion: LocalCySchemaVersion,
      id,
      operation: "sparkTurn",
      createdAt: new Date().toISOString(),
      workspaceId: null,
      payload: validSparkRequest(id),
    });

    const runtime = new LocalCyRuntime(workspace, async () => ({
      result: {
        message: "What is the one belief this post should change?",
        workingState: { premise: "Explain the rough hit rate clearly." },
      },
      model: "claude-sonnet-test",
    }));

    await expect(runtime.runOnce()).resolves.toBe(1);
    const response = LocalCyResponseSchema.parse(JSON.parse(
      readFileSync(join(workspace.localCyResponsesDirectory, `${id}.json`), "utf8"),
    ));
    expect(response.status).toBe("succeeded");
    if (response.status === "succeeded") {
      const result = SparkTurnResultSchema.parse(response.result);
      expect(result.assistantMessage).toContain("one belief");
      expect(result.workingState.audience).toBe("Data-curious creators");
    }
  });

  it("validates the dedicated inspiration shaping operation", async () => {
    const directory = mkdtempSync(join(tmpdir(), "agentcy-local-cy-"));
    temporaryDirectories.push(directory);
    const workspace = new AgentCyWorkspace(directory);
    workspace.ensureDirectories();
    const id = "a9c49e4c-8630-4ad2-923e-7ec495523934";
    writeJsonAtomically(join(workspace.localCyRequestsDirectory, `${id}.json`), {
      schemaVersion: LocalCySchemaVersion,
      id,
      operation: "shapeInspiration",
      createdAt: new Date().toISOString(),
      workspaceId: null,
      payload: validInspirationShapeRequest(id),
    });

    const runtime = new LocalCyRuntime(workspace, async (_request, resultSchema) => ({
      result: resultSchema.parse(validInspirationShapeResult()),
      model: "claude-sonnet-test",
    }));

    await expect(runtime.runOnce()).resolves.toBe(1);
    const response = LocalCyResponseSchema.parse(JSON.parse(
      readFileSync(join(workspace.localCyResponsesDirectory, `${id}.json`), "utf8"),
    ));
    expect(response.status).toBe("succeeded");
    if (response.status === "succeeded") {
      expect(InspirationShapeResultSchema.parse(response.result).idea.title).toContain("reset");
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

function validSparkRequest(operationId: string) {
  return {
    schemaVersion: "agent-cy.ai.v1",
    promptVersion: "spark-turn.v1",
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
    spark: {
      sparkId: "881ae4bb-090c-4f19-a968-89c2fa57d934",
      source: "text",
      text: "Anatomy of a rough hit rate",
    },
    turnNumber: 1,
    composeNow: false,
    conversation: [],
    workingState: {
      premise: "A rough hit rate can still contain useful evidence.",
      audience: "Data-curious creators",
      creativeGoal: null,
      proofOrStory: null,
      desiredTakeaway: null,
      constraints: [],
    },
  };
}

function validInspirationShapeRequest(operationId: string) {
  return {
    schemaVersion: "inspiration-shape.request.v3",
    promptVersion: "inspiration-shape.v3",
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
    sourcePlatform: "instagram",
    sourceMaterial: {
      title: "A practical filming reset",
      caption: "The hook creates tension before a practical reset.",
      transcript: "I made filming easier by shrinking one setup decision.",
      visualObservations: ["Direct-to-camera opening followed by a demonstration."],
      analyzedInputs: ["caption", "audioTranscript", "videoFrames"],
      durationSeconds: 45,
    },
  };
}

function validInspirationShapeResult() {
  return {
    sourceSummary: "The post demonstrates how one smaller setup decision reduces filming friction.",
    keyPoints: ["Name the tension first.", "Demonstrate one practical reset."],
    interpretedMechanic: {
      hookPattern: "Open with tension",
      structurePattern: "Tension, reset, demonstration",
      payoffPattern: "One smaller next move",
    },
    originalityGuardrails: [
      "Use a firsthand example.",
      "Do not reuse source wording or story details.",
    ],
    idea: {
      title: "The reset that made starting easier",
      premise: "Show one original workflow adjustment that reduced friction.",
      audience: "Solo creators delaying their first take",
      takeaway: "Shrink one setup decision.",
      spokenHook: "The plan was not the problem.",
      firstFrameText: "MAKE THE FIRST TAKE EASIER",
      filmingApproach: "Direct to camera with one firsthand demonstration.",
      recommendedFormat: "45-second vertical video",
      durationSeconds: 45,
    },
    suggestedPillarId: null,
    assumptions: ["The creator has a firsthand example."],
  };
}
