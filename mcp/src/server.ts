import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { agendaResult, postSearchResult, taskResult, workspaceSummary } from "./format.js";
import { AgentCyWorkspace, clientSource } from "./workspace.js";

const statusValues = ["spark", "developing", "ready", "scheduled", "posted", "archived"] as const;
const platformValues = ["instagramReels", "tiktok", "youtubeShorts", "youtubeVideo"] as const;
const formatValues = ["Reel", "Carousel", "Feed post", "Story", "Short video", "Long video", "Short", "Video"] as const;
const kindValues = ["planning", "scripting", "filming", "editing", "publishing", "creatorBusiness"] as const;
const priorityValues = ["none", "low", "medium", "high", "urgent"] as const;

export function createAgentCyMcpServer(workspace = new AgentCyWorkspace()): McpServer {
  const server = new McpServer({ name: "agent.cy", version: "0.1.0" });

  server.registerTool(
    "bridge_status",
    {
      title: "Check agent.cy bridge",
      description: "Check whether the iPhone app has synced its local workspace and summarize what is available.",
      inputSchema: {},
    },
    async () => {
      try {
        const source = clientSource();
        workspace.recordBridgeConnection(
          source === "mcp-client" ? [] : [source],
          "bridge_status was verified from Claude or Codex.",
        );
        const snapshot = workspace.readSnapshot();
        return textResult(`${workspaceSummary(snapshot)}\nPending app approvals: ${workspace.listPendingRequestIds().length}`);
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  server.registerTool(
    "search_posts",
    {
      title: "Search agent.cy posts",
      description: "Search ideas, drafts, scheduled posts, and posted work stored in agent.cy.",
      inputSchema: {
        query: z.string().trim().max(500).optional(),
        status: z.enum(statusValues).optional(),
        pillarId: z.string().uuid().optional(),
        limit: z.number().int().min(1).max(50).default(20),
      },
    },
    async ({ query, status, pillarId, limit }) => {
      try {
        const snapshot = workspace.readSnapshot();
        const needle = query?.toLocaleLowerCase();
        const posts = snapshot.posts
          .filter((post) => !status || post.status === status)
          .filter((post) => !pillarId || post.pillarId === pillarId)
          .filter((post) => {
            if (!needle) return true;
            return [post.title, post.premise, post.notes, post.hook, ...post.script]
              .join("\n")
              .toLocaleLowerCase()
              .includes(needle);
          })
          .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt))
          .slice(0, limit);
        return textResult(postSearchResult(posts));
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  server.registerTool(
    "get_post",
    {
      title: "Get a complete post handoff",
      description: "Return the clean Notion-ready Markdown handoff for one agent.cy post.",
      inputSchema: { postId: z.string().uuid() },
    },
    async ({ postId }) => {
      try {
        const post = workspace.readSnapshot().posts.find((candidate) => candidate.id === postId);
        return post ? textResult(post.markdown) : textResult(`No post exists with ID ${postId}.`, true);
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  server.registerTool(
    "list_ideas",
    {
      title: "List the Idea Bank",
      description: "List unscheduled ideas from the agent.cy Idea Bank.",
      inputSchema: {
        pillarId: z.string().uuid().optional(),
        limit: z.number().int().min(1).max(100).default(30),
      },
    },
    async ({ pillarId, limit }) => {
      try {
        const ideas = workspace
          .readSnapshot()
          .posts.filter((post) => post.status === "spark" && !post.outputs.some((output) => output.targetDate))
          .filter((post) => !pillarId || post.pillarId === pillarId)
          .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt))
          .slice(0, limit);
        return textResult(postSearchResult(ideas));
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  server.registerTool(
    "list_pillars",
    {
      title: "List content pillars",
      description: "List active agent.cy pillars, colors, roles, and assigned weekdays.",
      inputSchema: {},
    },
    async () => {
      try {
        const pillars = workspace.readSnapshot().pillars;
        const text = pillars.length === 0
          ? "No pillars are configured."
          : pillars.map((pillar) => [
              `- ${pillar.name} (${pillar.role})`,
              `  ID: ${pillar.id}`,
              `  Color: #${pillar.colorHex}`,
              `  Weekdays: ${pillar.assignedWeekdays.join(", ") || "none"}`,
            ].join("\n")).join("\n");
        return textResult(text);
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  server.registerTool(
    "list_series",
    {
      title: "List content series",
      description: "List agent.cy series with cadence, state, episode counts, and open planning slots.",
      inputSchema: {
        state: z.enum(["active", "paused", "archived"]).optional(),
      },
    },
    async ({ state }) => {
      try {
        const snapshot = workspace.readSnapshot();
        const items = snapshot.series.filter((series) => !state || series.state === state);
        const text = items.length === 0
          ? "No series match this filter."
          : items.map((series) => {
              const episodeCount = snapshot.posts.filter((post) => post.seriesId === series.id).length;
              const openSlotCount = snapshot.episodeSlots.filter(
                (slot) => slot.seriesId === series.id && slot.status === "open",
              ).length;
              return [
                `- ${series.name} (${series.state})`,
                `  ID: ${series.id}`,
                `  Cadence: ${series.cadence}`,
                `  Episodes: ${episodeCount}`,
                `  Open slots: ${openSlotCount}`,
              ].join("\n");
            }).join("\n");
        return textResult(text);
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  server.registerTool(
    "list_episode_slots",
    {
      title: "List planned episode slots",
      description: "List empty, converted, or skipped series planning slots. Slots are planning objects, not scheduled posts.",
      inputSchema: {
        seriesId: z.string().uuid().optional(),
        status: z.enum(["open", "converted", "skipped"]).optional(),
        limit: z.number().int().min(1).max(200).default(50),
      },
    },
    async ({ seriesId, status, limit }) => {
      try {
        const snapshot = workspace.readSnapshot();
        const seriesById = new Map(snapshot.series.map((series) => [series.id, series.name]));
        const slots = snapshot.episodeSlots
          .filter((slot) => !seriesId || slot.seriesId === seriesId)
          .filter((slot) => !status || slot.status === status)
          .sort((left, right) => left.plannedDate.localeCompare(right.plannedDate))
          .slice(0, limit);
        const text = slots.length === 0
          ? "No episode slots match this filter."
          : slots.map((slot) => [
              `- ${seriesById.get(slot.seriesId) ?? "Unknown series"} — ${slot.status}`,
              `  Slot ID: ${slot.id}`,
              `  Planned: ${slot.plannedDate}`,
              slot.convertedPostId ? `  Converted post: ${slot.convertedPostId}` : undefined,
            ].filter(Boolean).join("\n")).join("\n");
        return textResult(text);
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  server.registerTool(
    "get_agenda",
    {
      title: "Read the agenda",
      description: "Read scheduled posts and tasks for a day or date range.",
      inputSchema: {
        startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
        days: z.number().int().min(1).max(31).default(7),
      },
    },
    async ({ startDate, days }) => {
      try {
        const date = startDate ? new Date(`${startDate}T00:00:00`) : new Date();
        if (Number.isNaN(date.getTime())) return textResult("The start date is invalid.", true);
        return textResult(agendaResult(workspace.readSnapshot(), date, days));
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  server.registerTool(
    "list_tasks",
    {
      title: "List creator tasks",
      description: "List agent.cy tasks, optionally filtered to a post or open tasks.",
      inputSchema: {
        postId: z.string().uuid().optional(),
        completed: z.boolean().optional(),
        limit: z.number().int().min(1).max(100).default(50),
      },
    },
    async ({ postId, completed, limit }) => {
      try {
        const tasks = workspace
          .readSnapshot()
          .tasks.filter((task) => !postId || task.briefId === postId)
          .filter((task) => completed === undefined || task.completed === completed)
          .sort((left, right) => (left.targetDate ?? "9999").localeCompare(right.targetDate ?? "9999"))
          .slice(0, limit);
        return textResult(taskResult(tasks));
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  server.registerTool(
    "create_idea",
    {
      title: "Queue a new idea",
      description: "Queue an Idea Bank entry for approval in agent.cy. The app does not change until the creator approves it.",
      inputSchema: {
        title: z.string().trim().min(1).max(500),
        notes: z.string().max(20_000).optional(),
        pillarId: z.string().uuid().nullable().optional(),
      },
    },
    async (payload) => queuedResult(workspace, { type: "createIdea", payload }),
  );

  server.registerTool(
    "create_post_draft",
    {
      title: "Queue a post draft or scheduled post",
      description: "Queue one reviewable post proposal in agent.cy. Include targetDate to create and schedule it atomically after one approval; omit targetDate for a resumable draft. Put the social caption in caption, never in notes. Notes are only for production context and must not be used as the only place for a posting date.",
      inputSchema: {
        title: z.string().trim().min(1).max(500),
        premise: z.string().max(20_000).optional(),
        notes: z.string().max(20_000).optional(),
        pillarId: z.string().uuid().nullable().optional(),
        platform: z.enum(platformValues).optional(),
        format: z.enum(formatValues).optional(),
        hook: z.string().max(10_000).optional(),
        caption: z.string().max(20_000).optional(),
        callToAction: z.string().max(5_000).optional(),
        targetDate: z.string().datetime({ offset: true }).optional(),
        includesTargetTime: z.boolean().default(false),
      },
    },
    async (payload) => queuedResult(workspace, { type: "createPostDraft", payload }),
  );

  server.registerTool(
    "update_post",
    {
      title: "Queue post changes",
      description: "Queue edits to an existing post. Every field is shown for approval in the app. Put the social caption in caption, never in notes. Notes are only for production context.",
      inputSchema: {
        postId: z.string().uuid(),
        title: z.string().trim().min(1).max(500).optional(),
        premise: z.string().max(20_000).optional(),
        notes: z.string().max(20_000).optional(),
        pillarId: z.string().uuid().nullable().optional(),
        hook: z.string().max(10_000).optional(),
        caption: z.string().max(20_000).optional(),
        format: z.enum(formatValues).optional(),
        callToAction: z.string().max(5_000).optional(),
      },
    },
    async (payload) => queuedResult(workspace, { type: "updatePost", payload }),
  );

  server.registerTool(
    "schedule_post",
    {
      title: "Queue a posting date",
      description: "Queue a schedule change for an existing ready post. Approval is required in agent.cy.",
      inputSchema: {
        postId: z.string().uuid(),
        outputId: z.string().uuid().optional(),
        targetDate: z.string().datetime({ offset: true }),
        includesTargetTime: z.boolean().default(true),
      },
    },
    async (payload) => queuedResult(workspace, { type: "schedulePost", payload }),
  );

  server.registerTool(
    "add_task",
    {
      title: "Queue a task",
      description: "Queue a creator or post task for approval in agent.cy.",
      inputSchema: {
        title: z.string().trim().min(1).max(500),
        notes: z.string().max(10_000).optional(),
        postId: z.string().uuid().optional(),
        outputId: z.string().uuid().optional(),
        pillarId: z.string().uuid().optional(),
        kind: z.enum(kindValues).default("planning"),
        lane: z.enum(["pillar", "production"]).default("production"),
        priority: z.enum(priorityValues).default("none"),
        targetDate: z.string().datetime({ offset: true }).optional(),
        includesTargetTime: z.boolean().default(false),
      },
    },
    async (payload) => queuedResult(workspace, { type: "addTask", payload }),
  );

  server.registerTool(
    "complete_task",
    {
      title: "Queue task completion",
      description: "Queue completion of one task for approval in agent.cy.",
      inputSchema: { taskId: z.string().uuid() },
    },
    async (payload) => queuedResult(workspace, { type: "completeTask", payload }),
  );

  server.registerTool(
    "change_request_status",
    {
      title: "Check a queued change",
      description: "Check whether a proposed change was approved, rejected, or is still waiting in the app.",
      inputSchema: { requestId: z.string().uuid() },
    },
    async ({ requestId }) => {
      try {
        const receipt = workspace.readReceipt(requestId);
        if (receipt) return textResult(`${receipt.status}: ${receipt.message}`);
        const waiting = workspace.listPendingRequestIds().includes(requestId);
        return textResult(waiting ? "Waiting for approval in agent.cy." : "No queued request or receipt was found.");
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  return server;
}

function queuedResult(
  workspace: AgentCyWorkspace,
  request: Parameters<AgentCyWorkspace["queueRequest"]>[0],
) {
  try {
    const queued = workspace.queueRequest(request);
    return textResult(
      `Queued for approval in agent.cy. Request ID: ${queued.id}\nOpen Cy on the iPhone to review it, or use Settings > AI > Claude & Codex to check the connection.`,
    );
  } catch (error) {
    return errorResult(error);
  }
}

function textResult(text: string, isError = false) {
  return { content: [{ type: "text" as const, text }], isError };
}

function errorResult(error: unknown) {
  const message = error instanceof Error ? error.message : "The agent.cy bridge could not complete the request.";
  return textResult(message, true);
}
