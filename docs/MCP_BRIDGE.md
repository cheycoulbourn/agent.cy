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

The installer and every successful `bridge_status` call write a content-free `bridge-status.json` heartbeat. It contains only the detected client names, verification time, and connection message. Onboarding and Settings use this file to show whether Claude Code or Codex was actually detected. It contains no creator content or credentials.

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

The same setup is available during onboarding under **Your AI**. Every terminal command is displayed in a copyable code block, and setup can be deferred without losing onboarding progress.

Restart Claude Code or Codex after initial setup. Ask it to call `bridge_status` to verify the connection.

Start content work in Plan mode. Use the client's native question tool to learn the creator's goals, audience, account, pillars, capacity, and constraints before proposing a plan. Do not call an MCP write tool until the creator explicitly approves the plan. The customizable starter prompt in **Settings > AI > Claude & Codex** encodes this workflow for both Claude Code and Codex.

Before every planning or editing operation, ask the creator whether the same content plan lives outside agent.cy. This question is mandatory even when a prior operation used Notion or another system. If the answer is yes:

1. Use the external platform's official MCP server or CLI read-only first.
2. Verify the signed-in workspace, exact database or project, field mapping, source of truth, and sync direction.
3. Preview the agent.cy changes and external changes separately and obtain explicit approval for each system.
4. Pass the verified `externalPlan` context to every agent.cy write tool. The bridge rejects a current write call that omits this preflight.
5. After agent.cy approval, apply only the separately approved external writes, re-read both systems, and compare account, IDs, titles, series or episode, work date, scheduled date, status, and tasks. A partial write is divergence, not a successful sync.

When the creator confirms there is no external plan for the operation, pass `externalPlan: { "status": "none", "creatorConfirmed": true }`. For a linked system, record its system, workspace, destination, source of truth, sync direction, and the required external approval. Never put credentials or access tokens in this context.

When the approved plan includes a date for a new post, call `create_post_draft` once with `targetDate` and `includesTargetTime`. The creator then reviews creation and scheduling together in Cy. Omit `targetDate` only when the creator explicitly wants an unscheduled draft. Never place the posting date only in `notes`, and do not follow a dated `create_post_draft` with a second `schedule_post` request.

## Cy review

Claude and Codex proposals always pass through one creator-controlled review in Cy. The review uses the same post hierarchy and pillar color as the calendar, shows the complete post and posting details, and supports Edit, Approve, and Deny. A dated new-post proposal uses **Approve & schedule** to create the post and place it on the calendar atomically. It never asks for a second scheduling approval. An undated proposal uses **Approve draft** and remains resumable in the post editor.

### Review delivery

- Cy refreshes the iCloud Drive request queue while the app is active. The phone inbox also supports pull-to-refresh; the desktop inbox has an explicit Refresh control and a two-pane queue/detail layout at wide window sizes.
- After notification permission is granted, the app registers its APNs device token with the authenticated server. The server returns a private, revocable notification capability that the app writes into `snapshot.json` for the local bridge.
- When the bridge queues a proposal, it calls that capability with the request ID, type, workspace, review count, and relevant title. It never sends the proposal body, notes, script, caption, or credentials through APNs.
- Tapping the alert routes directly to the Cy review inbox. If agent.cy is active, the app refreshes the queue and opens Cy when the new request appears.
- The bridge writes its last delivery result to `push-status.json`. A notification failure does not bypass or remove the pending review; foreground and manual refresh remain available.

Production review alerts require `PUBLIC_BASE_URL`, `BRIDGE_NOTIFICATION_HASH_SECRET`, and the complete APNs configuration (`APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY`, `APNS_TOPIC`, and `APNS_ENVIRONMENT`) in the server deployment. The Apple App ID and signing profiles must also include the Push Notifications entitlement. Never commit the APNs `.p8` key.

Posts created or edited directly inside agent.cy do not enter the Cy review queue. `schedule_post` remains a separate review only when Claude or Codex is changing the date of a post that already exists.

Use exact built-in format values: `Reel`, `Carousel`, `Feed post`, `Story`, `Short video`, `Long video`, `Short`, or `Video`. Production context belongs in `notes`; captions and calls to action belong in their structured fields.

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
- `external_plan_preflight`
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

Every approval-queued write tool requires an `externalPlan` preflight. This records the creator's answer and verified destination with the proposal; it does not grant permission to write to the external system. External writes require their own explicit approval in the connected MCP server or CLI.

`schedule_post` remains available for moving or scheduling a post that already exists in agent.cy. It is not needed when a new `create_post_draft` request already contains `targetDate`.

Delete, archive, publish, erase, attachment access, and raw database access are deliberately not exposed.
