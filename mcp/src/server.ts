import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import {
  McpExternalPlanContextSchema,
} from "@agent-cy/contracts";

import { agendaResult, postSearchResult, taskResult, workspaceSummary } from "./format.js";
import { AgentCyWorkspace, clientSource, type SeriesEpisodeRevisionPatch } from "./workspace.js";

const statusValues = ["spark", "developing", "ready", "scheduled", "posted", "archived"] as const;
const platformValues = ["instagramReels", "tiktok", "youtubeShorts", "youtubeVideo", "substack", "pinterest"] as const;
const formatValues = ["Reel", "Carousel", "Feed post", "Story", "Short video", "Long video", "Short", "Video", "Letter", "Note", "Pin"] as const;
const kindValues = ["planning", "scripting", "filming", "editing", "publishing", "creatorBusiness"] as const;
const priorityValues = ["none", "low", "medium", "high", "urgent"] as const;
const cadenceValues = ["none", "daily", "weekly", "monthly"] as const;
const brandTypeValues = ["brand", "agency", "publicRelations", "creator", "other"] as const;
const brandStageValues = ["wishlist", "reachedOut", "talking", "workingTogether", "pastPartner", "archived"] as const;
const episodeRevisionStatusValues = ["needsRevision", "readyForReview", "approved", "removed"] as const;
const externalPlanInputSchema = McpExternalPlanContextSchema.describe(
  "Required planning preflight. Ask whether this creator plan also lives outside agent.cy. Use status none only after the creator says no. For linked plans, verify the exact external workspace and destination with its official MCP server or CLI, name the source of truth and sync direction, and keep external writes behind a separate approval.",
);

const POST_SLOT_DATE_GUIDANCE =
  "The post slot: when this goes live. This is the only date you should schedule on your own initiative. Before proposing it, ask the creator the scheduling_preflight questions so the date fits their real cadence, filming rhythm, and existing agenda. Never invent a date the creator has not confirmed.";
const WORK_DATE_GUIDANCE =
  "The creator's own working or filming date. It belongs to the creator, not to you. Do not set it unless the creator explicitly asked you to. Ask first: do you want me to schedule the work date too, or will you set that yourself? Otherwise leave it empty and schedule only the post slot.";

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
        const revisionCount = workspace.listEpisodeRevisions("needsRevision").length;
        return textResult(`${workspaceSummary(snapshot)}\nPending app approvals: ${workspace.listPendingRequestIds().length}\nEpisodes needing revision: ${revisionCount}`);
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  server.registerTool(
    "external_plan_preflight",
    {
      title: "Check the external content plan rule",
      description: "Return the mandatory preflight for Notion or any other external content-plan system before planning or queueing changes in agent.cy.",
      inputSchema: {},
    },
    async () => {
      try {
        const snapshot = workspace.readSnapshot();
        return textResult([
          `Active agent.cy account: ${snapshot.workspaceName ?? snapshot.profile?.name ?? "Unnamed workspace"}`,
          "Before every content planning or editing operation, ask: Does this content plan also live somewhere outside agent.cy?",
          "If no: pass externalPlan { status: \"none\", creatorConfirmed: true } to every write tool.",
          "If yes: verify the official MCP or CLI connection, signed-in workspace, exact database/project, field mapping, source of truth, and sync direction. Never infer these from a similar name.",
          "Preview agent.cy changes and external changes separately. Obtain explicit approval for each system before writing.",
          "After agent.cy approval, apply only the approved external writes, re-read both systems, compare IDs, titles, dates, status, account, series, and tasks, and report any divergence instead of calling it synced.",
        ].join("\n"));
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  server.registerTool(
    "scheduling_preflight",
    {
      title: "Check the scheduling rule",
      description: "Return the mandatory questions to ask the creator before scheduling any post or series episode. Call this before proposing dates.",
      inputSchema: {},
    },
    async () => {
      try {
        const snapshot = workspace.readSnapshot();
        return textResult([
          `Active agent.cy account: ${snapshot.workspaceName ?? snapshot.profile?.name ?? "Unnamed workspace"}`,
          "Schedule the post slot only. The work date belongs to the creator.",
          "Never set a work date unless the creator explicitly asked for it. Ask first: do you want me to schedule the work date too, or will you set that yourself?",
          "Before proposing any posting date, ask the creator whichever of these they have not already answered:",
          "1. What day and time should this go out, and does that match the cadence you already publish on?",
          "2. Is anything already on that week that this would crowd?",
          "3. Do you need filming or editing time before that date, and is the gap realistic?",
          "4. For a series: should this follow the series cadence, or is this episode an exception?",
          "Read get_agenda and list_episode_slots before proposing, and name any collision instead of scheduling over it.",
          "Propose dates and let the creator confirm. Never invent a date the creator has not agreed to.",
        ].join("\n"));
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
    "list_social_accounts",
    {
      title: "List connected social accounts",
      description: "List the exact agent.cy social accounts available in the active workspace. When a destination has multiple accounts, use one returned account ID in every post or series proposal instead of guessing.",
      inputSchema: {
        destination: z.string().trim().max(160).optional(),
      },
    },
    async ({ destination }) => {
      try {
        const needle = destination?.toLocaleLowerCase();
        const accounts = workspace
          .readSnapshot()
          .socialAccounts
          .filter((account) => !needle || account.destination.toLocaleLowerCase() === needle)
          .sort((left, right) => left.destination.localeCompare(right.destination)
            || Number(right.isPrimary) - Number(left.isPrimary)
            || left.label.localeCompare(right.label));
        if (accounts.length === 0) return textResult("No matching social accounts are configured in agent.cy.");
        return textResult(accounts.map((account) => [
          account.label,
          account.destination,
          account.isPrimary ? "Primary" : null,
          `Account ID: ${account.id}`,
        ].filter(Boolean).join(" · ")).join("\n"));
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
    "list_episode_revisions",
    {
      title: "List series episodes in revision",
      description: "List denied series episodes that remain attached to their original series and slot, plus revisions already pushed back for review.",
      inputSchema: {
        status: z.enum(episodeRevisionStatusValues).optional(),
        seriesId: z.string().uuid().optional(),
        limit: z.number().int().min(1).max(200).default(50),
      },
    },
    async ({ status, seriesId, limit }) => {
      try {
        const revisions = workspace.listEpisodeRevisions(status)
          .filter((revision) => !seriesId || revision.seriesId === seriesId)
          .slice(0, limit);
        if (revisions.length === 0) return textResult("No series episodes match this revision filter.");
        return textResult(revisions.map((revision) => [
          `- ${revision.request.payload.title} — ${revision.status}`,
          `  Episode review ID: ${revision.episodeReviewId}`,
          `  Series ID: ${revision.seriesId}`,
          revision.episodeSlotId ? `  Episode slot ID: ${revision.episodeSlotId}` : undefined,
          `  Revision: ${revision.revisionNumber}`,
          revision.decisionNote ? `  Review note: ${revision.decisionNote}` : undefined,
        ].filter(Boolean).join("\n")).join("\n"));
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  server.registerTool(
    "get_episode_revision",
    {
      title: "Get one series episode revision",
      description: "Read the full retained proposal, review note, stable series/slot context, and revision lineage for one denied episode.",
      inputSchema: { episodeReviewId: z.string().uuid() },
    },
    async ({ episodeReviewId }) => {
      try {
        const revision = workspace.readEpisodeRevision(episodeReviewId);
        return textResult(JSON.stringify(revision, null, 2));
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  server.registerTool(
    "list_brand_partners",
    {
      title: "List brand partners",
      description: "List the creator's brand, agency, PR, creator, and other partnership records, including stage and follow-up date.",
      inputSchema: {
        stage: z.enum(brandStageValues).optional(),
        limit: z.number().int().min(1).max(200).default(50),
      },
    },
    async ({ stage, limit }) => {
      try {
        const partners = workspace.readSnapshot().brandPartners
          .filter((partner) => !stage || partner.stage === stage)
          .slice(0, limit);
        const text = partners.length === 0
          ? "No brand partners match this filter."
          : partners.map((partner) => [
              `- ${partner.name} (${partner.stage})`,
              `  ID: ${partner.id}`,
              `  Type: ${partner.type}`,
              partner.socialHandle ? `  Social: ${partner.socialHandle}` : undefined,
              partner.nextFollowUpAt ? `  Follow up: ${partner.nextFollowUpAt}` : undefined,
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
        externalPlan: externalPlanInputSchema,
        title: z.string().trim().min(1).max(500),
        notes: z.string().max(20_000).optional(),
        pillarId: z.string().uuid().nullable().optional(),
      },
    },
    async ({ externalPlan, ...payload }) => queuedResult(workspace, { type: "createIdea", externalPlan, payload }),
  );

  server.registerTool(
    "create_post_draft",
    {
      title: "Queue a post draft or scheduled post",
      description: "Queue one reviewable post proposal in agent.cy. Include targetDate to create and schedule it atomically after one approval; omit targetDate for a resumable draft. Use list_social_accounts and include socialAccountId whenever the destination has multiple accounts. Put the social caption in caption, never in notes. Notes are only for production context and must not be used as the only place for a posting date.",
      inputSchema: {
        externalPlan: externalPlanInputSchema,
        title: z.string().trim().min(1).max(500),
        premise: z.string().max(20_000).optional(),
        notes: z.string().max(20_000).optional(),
        pillarId: z.string().uuid().nullable().optional(),
        platform: z.enum(platformValues).optional(),
        format: z.enum(formatValues).optional(),
        socialAccountId: z.string().uuid().optional(),
        hook: z.string().max(10_000).optional(),
        caption: z.string().max(20_000).optional(),
        callToAction: z.string().max(5_000).optional(),
        targetDate: z.string().datetime({ offset: true }).describe(POST_SLOT_DATE_GUIDANCE).optional(),
        includesTargetTime: z.boolean().default(false),
      },
    },
    async ({ externalPlan, ...payload }) => queuedResult(workspace, { type: "createPostDraft", externalPlan, payload }),
  );

  server.registerTool(
    "update_post",
    {
      title: "Queue post changes",
      description: "Queue edits to an existing post. Every field is shown for approval in the app. Put the social caption in caption, never in notes. Notes are only for production context.",
      inputSchema: {
        externalPlan: externalPlanInputSchema,
        postId: z.string().uuid(),
        outputId: z.string().uuid().optional(),
        socialAccountId: z.string().uuid().optional(),
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
    async ({ externalPlan, ...payload }) => queuedResult(workspace, { type: "updatePost", externalPlan, payload }),
  );

  server.registerTool(
    "set_post_work_date",
    {
      title: "Queue a post work date",
      description: "Set, move, or clear when the creator wants to work on a post. This does not change the posting date. The work date belongs to the creator: only call this when the creator has explicitly asked you to set it. If they have not asked, ask first and otherwise schedule only the post slot.",
      inputSchema: {
        externalPlan: externalPlanInputSchema,
        postId: z.string().uuid(),
        workDate: z.string().datetime({ offset: true }).describe(WORK_DATE_GUIDANCE).optional(),
        includesWorkTime: z.boolean().default(false),
        clearWorkDate: z.boolean().default(false),
      },
    },
    async ({ externalPlan, ...payload }) => queuedResult(workspace, { type: "updatePost", externalPlan, payload }),
  );

  server.registerTool(
    "schedule_post",
    {
      title: "Queue a posting date",
      description: "Queue a schedule change for an existing ready post. Call scheduling_preflight and ask the creator its questions before proposing a date; never invent a date the creator has not confirmed. Choose outputId when the post has multiple outputs and socialAccountId when its destination has multiple accounts. Approval is required in agent.cy.",
      inputSchema: {
        externalPlan: externalPlanInputSchema,
        postId: z.string().uuid(),
        outputId: z.string().uuid().optional(),
        socialAccountId: z.string().uuid().optional(),
        targetDate: z.string().datetime({ offset: true }).describe(POST_SLOT_DATE_GUIDANCE),
        includesTargetTime: z.boolean().default(true),
      },
    },
    async ({ externalPlan, ...payload }) => queuedResult(workspace, { type: "schedulePost", externalPlan, payload }),
  );

  server.registerTool(
    "reschedule_post",
    {
      title: "Queue a new date for a late post",
      description: "Move an overdue or otherwise scheduled post to a new posting date. Call scheduling_preflight and ask the creator its questions before proposing the new date. Choose outputId when the post has multiple outputs and socialAccountId when its destination has multiple accounts. Approval is required in agent.cy.",
      inputSchema: {
        externalPlan: externalPlanInputSchema,
        postId: z.string().uuid(),
        outputId: z.string().uuid().optional(),
        socialAccountId: z.string().uuid().optional(),
        targetDate: z.string().datetime({ offset: true }).describe(POST_SLOT_DATE_GUIDANCE),
        includesTargetTime: z.boolean().default(true),
      },
    },
    async ({ externalPlan, ...payload }) => queuedResult(workspace, { type: "reschedulePost", externalPlan, payload }),
  );

  server.registerTool(
    "mark_posted",
    {
      title: "Queue a post as posted",
      description: "Record when an existing platform post actually went live. Future timestamps are rejected by the app.",
      inputSchema: {
        externalPlan: externalPlanInputSchema,
        postId: z.string().uuid(),
        outputId: z.string().uuid().optional(),
        postedAt: z.string().datetime({ offset: true }),
      },
    },
    async ({ externalPlan, ...payload }) => queuedResult(workspace, { type: "markPostPosted", externalPlan, payload }),
  );

  server.registerTool(
    "create_series",
    {
      title: "Queue a content series",
      description: "Create a reusable content series under a required active pillar, with a default platform, social account, and planning cadence. Use list_pillars to choose pillarId. Use list_social_accounts and include socialAccountId when the platform has multiple accounts.",
      inputSchema: {
        externalPlan: externalPlanInputSchema,
        name: z.string().trim().min(1).max(500),
        pillarId: z.string().uuid(),
        platform: z.enum(platformValues).optional(),
        socialAccountId: z.string().uuid().optional(),
        cadence: z.enum(cadenceValues).default("none"),
        cadenceStartDate: z.string().datetime({ offset: true }).optional(),
        cadenceWeekdays: z.array(z.number().int().min(1).max(7)).max(7).default([]),
        cadenceMonthDay: z.number().int().min(1).max(31).optional(),
        cadenceEndDate: z.string().datetime({ offset: true }).optional(),
        includesTargetTime: z.boolean().default(false),
      },
    },
    async ({ externalPlan, ...payload }) => queuedResult(workspace, { type: "createSeries", externalPlan, payload }),
  );

  server.registerTool(
    "create_series_episode",
    {
      title: "Queue a series episode",
      description: "Turn an open episode slot into a post, or create an episode on a post slot. Anchor the episode with an episodeSlotId or a targetDate; targetDate is the post slot and is the date you should set. Do not set workDate unless the creator explicitly asked you to schedule their working time. Call scheduling_preflight and ask the creator its questions before proposing dates. When the creator asks to schedule or publish the episode on a date, targetDate is required so approval places it on the Agenda; never substitute workDate or a date in notes. Use the series account or include socialAccountId explicitly when the destination has multiple accounts.",
      inputSchema: {
        externalPlan: externalPlanInputSchema,
        seriesId: z.string().uuid(),
        episodeSlotId: z.string().uuid().optional(),
        title: z.string().trim().min(1).max(500),
        premise: z.string().max(20_000).optional(),
        notes: z.string().max(20_000).optional(),
        episodeNumber: z.number().int().positive().optional(),
        episodeLabel: z.string().max(160).optional(),
        platform: z.enum(platformValues).optional(),
        format: z.enum(formatValues).optional(),
        socialAccountId: z.string().uuid().optional(),
        hook: z.string().max(10_000).optional(),
        caption: z.string().max(20_000).optional(),
        callToAction: z.string().max(5_000).optional(),
        workDate: z.string().datetime({ offset: true }).describe(WORK_DATE_GUIDANCE).optional(),
        includesWorkTime: z.boolean().default(false),
        targetDate: z.string().datetime({ offset: true }).describe(POST_SLOT_DATE_GUIDANCE).optional(),
        includesTargetTime: z.boolean().default(false),
      },
    },
    async ({ externalPlan, ...payload }) => queuedResult(workspace, { type: "createSeriesEpisode", externalPlan, payload }),
  );

  server.registerTool(
    "resubmit_series_episode",
    {
      title: "Revise and requeue a denied series episode",
      description: "Update a retained episode revision and push its next version back into agent.cy review without losing the original series, slot, schedule, request history, or episode position.",
      inputSchema: {
        externalPlan: externalPlanInputSchema,
        episodeReviewId: z.string().uuid(),
        title: z.string().trim().min(1).max(500).optional(),
        premise: z.string().max(20_000).optional(),
        notes: z.string().max(20_000).optional(),
        episodeNumber: z.number().int().positive().optional(),
        episodeLabel: z.string().max(160).optional(),
        platform: z.enum(platformValues).optional(),
        format: z.enum(formatValues).optional(),
        socialAccountId: z.string().uuid().optional(),
        hook: z.string().max(10_000).optional(),
        caption: z.string().max(20_000).optional(),
        callToAction: z.string().max(5_000).optional(),
        workDate: z.string().datetime({ offset: true }).optional(),
        includesWorkTime: z.boolean().optional(),
        targetDate: z.string().datetime({ offset: true }).optional(),
        includesTargetTime: z.boolean().optional(),
      },
    },
    async ({ episodeReviewId, externalPlan, ...patch }) => {
      try {
        const definedPatch = Object.fromEntries(
          Object.entries(patch).filter(([, value]) => value !== undefined),
        ) as SeriesEpisodeRevisionPatch;
        const queued = workspace.resubmitSeriesEpisode(
          episodeReviewId,
          definedPatch,
          clientSource(),
          externalPlan,
        );
        await workspace.notifyQueuedRequest(queued);
        return textResult([
          "Revision pushed to agent.cy for review.",
          `Request ID: ${queued.id}`,
          `Episode review ID: ${queued.payload.episodeReviewId}`,
          `Revision: ${queued.payload.revisionNumber}`,
          "The episode will return to its original series pipeline when this version is approved.",
        ].join("\n"));
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  server.registerTool(
    "add_task",
    {
      title: "Queue a task",
      description: "Queue a creator or post task for approval in agent.cy.",
      inputSchema: {
        externalPlan: externalPlanInputSchema,
        title: z.string().trim().min(1).max(500),
        notes: z.string().max(10_000).optional(),
        postId: z.string().uuid().optional(),
        outputId: z.string().uuid().optional(),
        pillarId: z.string().uuid().optional(),
        kind: z.enum(kindValues).default("planning"),
        lane: z.enum(["pillar", "production"]).default("production"),
        priority: z.enum(priorityValues).default("none"),
        targetDate: z.string().datetime({ offset: true }).describe(POST_SLOT_DATE_GUIDANCE).optional(),
        includesTargetTime: z.boolean().default(false),
      },
    },
    async ({ externalPlan, ...payload }) => queuedResult(workspace, { type: "addTask", externalPlan, payload }),
  );

  server.registerTool(
    "add_post_task",
    {
      title: "Queue a task for a post",
      description: "Create a production task that stays linked to a specific post and follows that post when its work date moves.",
      inputSchema: {
        externalPlan: externalPlanInputSchema,
        postId: z.string().uuid(),
        outputId: z.string().uuid().optional(),
        title: z.string().trim().min(1).max(500),
        notes: z.string().max(10_000).optional(),
        kind: z.enum(kindValues).default("planning"),
        priority: z.enum(priorityValues).default("none"),
        targetDate: z.string().datetime({ offset: true }).describe(POST_SLOT_DATE_GUIDANCE).optional(),
        includesTargetTime: z.boolean().default(false),
      },
    },
    async ({ externalPlan, ...payload }) => queuedResult(workspace, {
      type: "addTask",
      externalPlan,
      payload: { ...payload, lane: "production" },
    }),
  );

  server.registerTool(
    "create_brand_partner",
    {
      title: "Queue a brand partner",
      description: "Create a partnership record with stage, notes, social details, and an optional follow-up date.",
      inputSchema: {
        externalPlan: externalPlanInputSchema,
        name: z.string().trim().min(1).max(500),
        brandType: z.enum(brandTypeValues).default("brand"),
        brandStage: z.enum(brandStageValues).default("wishlist"),
        website: z.string().max(4_096).optional(),
        socialHandle: z.string().max(500).optional(),
        notes: z.string().max(20_000).optional(),
        nextFollowUpAt: z.string().datetime({ offset: true }).optional(),
      },
    },
    async ({ externalPlan, ...payload }) => queuedResult(workspace, { type: "createBrandPartner", externalPlan, payload }),
  );

  server.registerTool(
    "update_brand_partner",
    {
      title: "Queue brand partner changes",
      description: "Update a partnership record, including its pipeline stage and next follow-up.",
      inputSchema: {
        externalPlan: externalPlanInputSchema,
        brandPartnerId: z.string().uuid(),
        name: z.string().trim().min(1).max(500).optional(),
        brandType: z.enum(brandTypeValues).optional(),
        brandStage: z.enum(brandStageValues).optional(),
        website: z.string().max(4_096).optional(),
        socialHandle: z.string().max(500).optional(),
        notes: z.string().max(20_000).optional(),
        nextFollowUpAt: z.string().datetime({ offset: true }).optional(),
        clearNextFollowUp: z.boolean().optional(),
      },
    },
    async ({ externalPlan, ...payload }) => queuedResult(workspace, { type: "updateBrandPartner", externalPlan, payload }),
  );

  server.registerTool(
    "make_anchor_pillar",
    {
      title: "Queue a new anchor pillar",
      description: "Promote a secondary pillar to anchor without moving or deleting its posts, ideas, or history.",
      inputSchema: {
        externalPlan: externalPlanInputSchema,
        pillarId: z.string().uuid(),
      },
    },
    async ({ externalPlan, ...payload }) => queuedResult(workspace, { type: "makeAnchorPillar", externalPlan, payload }),
  );

  server.registerTool(
    "complete_task",
    {
      title: "Queue task completion",
      description: "Queue completion of one task for approval in agent.cy.",
      inputSchema: {
        externalPlan: externalPlanInputSchema,
        taskId: z.string().uuid(),
      },
    },
    async ({ externalPlan, ...payload }) => queuedResult(workspace, { type: "completeTask", externalPlan, payload }),
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
        if (receipt) {
          return textResult([
            `${receipt.status}: ${receipt.message}`,
            receipt.seriesId ? `Series ID: ${receipt.seriesId}` : undefined,
            receipt.episodeReviewId ? `Episode review ID: ${receipt.episodeReviewId}` : undefined,
            receipt.episodeSlotId ? `Episode slot ID: ${receipt.episodeSlotId}` : undefined,
            receipt.revisionNumber ? `Revision: ${receipt.revisionNumber}` : undefined,
            receipt.decisionNote ? `Review note: ${receipt.decisionNote}` : undefined,
            receipt.resultPostId ? `Created post ID: ${receipt.resultPostId}` : undefined,
            receipt.nextAction === "reviseSeriesEpisode"
              ? "Next action: revise this episode with resubmit_series_episode."
              : undefined,
          ].filter(Boolean).join("\n"));
        }
        const waiting = workspace.listPendingRequestIds().includes(requestId);
        return textResult(waiting ? "Waiting for approval in agent.cy." : "No queued request or receipt was found.");
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  return server;
}

async function queuedResult(
  workspace: AgentCyWorkspace,
  request: Parameters<AgentCyWorkspace["queueRequest"]>[0],
) {
  try {
    const queued = workspace.queueRequest(request);
    await workspace.notifyQueuedRequest(queued);
    const context = queued.type === "createSeries"
      ? `\nProposed series ID: ${queued.payload.seriesId}`
      : queued.type === "createSeriesEpisode"
        ? `\nEpisode review ID: ${queued.payload.episodeReviewId}`
        : "";
    const externalContext = queued.externalPlan?.status === "linked"
      ? `\nExternal plan recorded: ${queued.externalPlan.system} · ${queued.externalPlan.workspace} · ${queued.externalPlan.destination}. Its write still requires separate approval and verification.`
      : "\nCreator confirmed that this operation has no external content-plan destination.";
    return textResult(
      `Queued for approval in agent.cy. Request ID: ${queued.id}${context}${externalContext}\nOpen Cy on the iPhone to review it, or use Settings > AI > Claude & Codex to check the connection.`,
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
