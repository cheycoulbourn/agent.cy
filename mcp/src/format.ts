import type {
  McpBridgePost,
  McpBridgeSnapshot,
  McpBridgeTask,
} from "@agent-cy/contracts";

export function workspaceSummary(snapshot: McpBridgeSnapshot): string {
  const activePosts = snapshot.posts.filter((post) => post.status !== "archived");
  const openTasks = snapshot.tasks.filter((task) => !task.completed);
  const ideas = activePosts.filter((post) => post.status === "spark");
  return [
    `agent.cy workspace generated ${formatDate(snapshot.generatedAt)}`,
    `Creator: ${snapshot.profile?.name || "Not set"}`,
    `Pillars: ${snapshot.pillars.length}`,
    `Posts: ${activePosts.length}`,
    `Ideas: ${ideas.length}`,
    `Open tasks: ${openTasks.length}`,
  ].join("\n");
}

export function postSearchResult(posts: McpBridgePost[]): string {
  if (posts.length === 0) return "No matching posts found.";
  return posts
    .map((post) => {
      const targets = post.outputs
        .filter((output) => output.targetDate)
        .map((output) => `${output.destination || output.platform}: ${formatDate(output.targetDate!)}`);
      return [
        `## ${post.title}`,
        `ID: ${post.id}`,
        `Status: ${post.status}`,
        targets.length > 0 ? `Schedule: ${targets.join("; ")}` : "Schedule: none",
        post.premise ? `Premise: ${post.premise}` : "",
      ]
        .filter(Boolean)
        .join("\n");
    })
    .join("\n\n");
}

export function agendaResult(snapshot: McpBridgeSnapshot, startDate: Date, days: number): string {
  const start = startOfDay(startDate);
  const end = new Date(start);
  end.setDate(end.getDate() + days);

  const entries: Array<{ date: Date; text: string }> = [];
  for (const post of snapshot.posts) {
    if (post.status === "archived") continue;
    for (const output of post.outputs) {
      if (!output.targetDate) continue;
      const date = new Date(output.targetDate);
      if (date >= start && date < end) {
        entries.push({
          date,
          text: `POST · ${post.title} · ${output.destination || output.platform} · ${output.status}`,
        });
      }
    }
  }
  for (const task of snapshot.tasks) {
    if (!task.targetDate) continue;
    const date = new Date(task.targetDate);
    if (date >= start && date < end) {
      entries.push({ date, text: `TASK · ${task.title} · ${task.completed ? "complete" : task.priority}` });
    }
  }
  if (entries.length === 0) {
    return `Nothing scheduled from ${dateOnly(start)} through ${dateOnly(new Date(end.getTime() - 1))}.`;
  }
  entries.sort((left, right) => left.date.getTime() - right.date.getTime());
  const grouped = new Map<string, string[]>();
  for (const entry of entries) {
    const key = dateOnly(entry.date);
    const values = grouped.get(key) ?? [];
    values.push(`- ${entry.text}${hasTime(entry.date) ? ` · ${timeOnly(entry.date)}` : ""}`);
    grouped.set(key, values);
  }
  return [...grouped.entries()]
    .map(([date, values]) => `## ${date}\n${values.join("\n")}`)
    .join("\n\n");
}

export function taskResult(tasks: McpBridgeTask[]): string {
  if (tasks.length === 0) return "No matching tasks found.";
  return tasks
    .map((task) => {
      const date = task.targetDate ? formatDate(task.targetDate) : "No date";
      return `- [${task.completed ? "x" : " "}] ${task.title} · ${task.priority} · ${date} · ID ${task.id}`;
    })
    .join("\n");
}

export function formatDate(value: string): string {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString();
}

function dateOnly(value: Date): string {
  const year = value.getFullYear();
  const month = String(value.getMonth() + 1).padStart(2, "0");
  const day = String(value.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function timeOnly(value: Date): string {
  return value.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

function hasTime(value: Date): boolean {
  return value.getHours() !== 0 || value.getMinutes() !== 0;
}

function startOfDay(value: Date): Date {
  const result = new Date(value);
  result.setHours(0, 0, 0, 0);
  return result;
}
