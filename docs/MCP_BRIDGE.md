# Claude & Codex local bridge

The local MCP bridge lets Claude Code or Codex work with a creator's agent.cy workspace without moving the SwiftData database to the Railway proxy. The bridge runs on the creator's computer. A supported mobile app may continue that connected computer session, but the iPhone does not host the MCP server.

## Privacy boundary

- The creator chooses a folder in Files, normally `iCloud Drive/agent.cy MCP`.
- The iPhone app writes a versioned, read-only `snapshot.json` containing posts, Markdown handoffs, tasks, pillars, and schedules.
- The snapshot is limited to the creator account currently selected in agent.cy. New requests carry that workspace identifier so reviews cannot be approved into another account accidentally.
- Attachment names may appear in the handoff. Attachment bytes, the profile photo, credentials, conversations, voice examples, and private CloudKit records are not copied into the MCP snapshot.
- The local MCP server reads that folder. It does not contact Railway or an AI provider.
- MCP write tools create small JSON proposals in `requests/`. Nothing changes in SwiftData until the creator approves the proposal in Cy.
- Approval and rejection receipts are written to `responses/`. Unknown, stale, archived, or invalid records are rejected by the app.

## Guided setup

Download the signed macOS or Windows package from the project release. Keep `agentcy-setup` beside `agentcy-mcp`, open the setup wizard, confirm the detected iCloud Drive folder and clients, then follow the iPhone instruction it shows.

The wizard:

1. Finds or creates the creator's `iCloud Drive/agent.cy MCP` folder.
2. Detects Claude Code and Codex.
3. Registers `agentcy` for the current user.
4. Runs a local bridge check and reports Connected or Repair needed.

Re-run the wizard to repair an installation. Run it with `--uninstall` to remove client registrations while keeping the creator's iCloud Drive workspace.

## Advanced developer setup

Use Node 24 and run from the repository root:

```bash
pnpm install
pnpm mcp:setup
```

The setup command:

1. Builds `@agent-cy/mcp`.
2. Creates `iCloud Drive/agent.cy MCP` on macOS or Windows.
3. Registers the local stdio server in Claude Code and Codex CLI.

Then on iPhone:

1. Open **Settings > AI > Claude & Codex**.
2. Choose **iCloud Drive > agent.cy MCP**.
3. Tap **Sync now**.

Restart Claude Code or Codex after initial setup. Ask it to call `bridge_status` to verify the connection.

Start content work in Plan mode. Use the client's native question tool to learn the creator's goals, audience, account, pillars, capacity, and constraints before proposing a plan. Do not call an MCP write tool until the creator explicitly approves the plan. The customizable starter prompt in **Settings > AI > Claude & Codex** encodes this workflow for both Claude Code and Codex.

To configure one client or a different folder:

```bash
pnpm --filter @agent-cy/mcp run setup -- --client claude
pnpm --filter @agent-cy/mcp run setup -- --client codex
pnpm --filter @agent-cy/mcp run setup -- --workspace "/absolute/path/to/agent.cy MCP"
AGENTCY_NODE_PATH="/absolute/path/to/node" pnpm mcp:setup
```

## MCP tools

Read tools:

- `bridge_status`
- `search_posts`
- `get_post`
- `list_ideas`
- `list_pillars`
- `get_agenda`
- `list_tasks`

Approval-queued write tools:

- `create_idea`
- `create_post_draft`
- `update_post`
- `schedule_post`
- `add_task`
- `complete_task`
- `change_request_status`

Delete, archive, publish, erase, attachment access, and raw database access are deliberately not exposed.
