import { describe, expect, it } from "vitest";

import { agendaResult, postSearchResult } from "../src/format.js";

const dateOnlyOutput = {
  id: "22222222-2222-4222-8222-222222222222",
  platform: "instagramReels" as const,
  destination: "Instagram",
  format: "Reel",
  socialAccountId: null,
  account: null,
  status: "scheduled" as const,
  targetDate: "2026-07-20T16:00:00.000Z",
  includesTargetTime: false,
  durationSeconds: 60,
  title: "",
  caption: "",
  openingAdjustment: "",
  callToAction: "",
  editNotes: "",
  publishedUrl: "",
};

const post = {
  id: "11111111-1111-4111-8111-111111111111",
  title: "A soft weekend in Charlotte",
  premise: "Let a day unfold.",
  notes: "",
  status: "scheduled" as const,
  pillarId: null,
  includesWorkTime: false,
  durationSeconds: 60,
  hook: "",
  firstFrameText: "",
  script: [],
  ending: "",
  callToAction: "",
  createdAt: "2026-07-18T12:00:00.000Z",
  updatedAt: "2026-07-18T12:00:00.000Z",
  markdown: "# A soft weekend in Charlotte",
  outputs: [dateOnlyOutput],
  tasks: [],
};

describe("MCP date formatting", () => {
  it("does not invent a time for a date-only posting target", () => {
    const result = postSearchResult([post]);
    expect(result).toContain("2026-07-20");
    expect(result).not.toMatch(/12:00|4:00|AM|PM/);
  });

  it("keeps date-only agenda entries free of placeholder times", () => {
    const result = agendaResult({
      schemaVersion: 1,
      generatedAt: "2026-07-18T12:00:00.000Z",
      workspaceId: null,
      workspaceName: null,
      profile: null,
      socialAccounts: [],
      pillars: [],
      series: [],
      episodeSlots: [],
      brandPartners: [],
      posts: [post],
      tasks: [],
    }, new Date("2026-07-20T00:00:00"), 1);

    expect(result).toContain("A soft weekend in Charlotte");
    expect(result).not.toMatch(/12:00|4:00|AM|PM/);
  });
});
