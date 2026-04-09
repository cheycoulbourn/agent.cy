import { Router, Request, Response } from "express";
import Anthropic from "@anthropic-ai/sdk";

const router = Router();

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,
});

// POST /api/ai/expand-idea
// Takes a raw idea + creator context, returns a full content brief
router.post("/expand-idea", async (req: Request, res: Response) => {
  try {
    const { idea, context } = req.body;

    const systemPrompt = buildSystemPrompt(context);

    const message = await anthropic.messages.create({
      model: "claude-sonnet-4-20250514",
      max_tokens: 1024,
      system: systemPrompt,
      messages: [
        {
          role: "user",
          content: `Expand this content idea into a full brief. Return JSON with: title, suggestedPillar, platforms (array), format, caption (in the creator's voice), hooks (3 variations), hashtags (10-15).

Idea: ${idea}`,
        },
      ],
    });

    const text =
      message.content[0].type === "text" ? message.content[0].text : "";

    res.json({ result: text });
  } catch (error) {
    console.error("expand-idea error:", error);
    res.status(500).json({ error: "Failed to expand idea" });
  }
});

// POST /api/ai/generate-caption
// Generates platform-specific captions
router.post("/generate-caption", async (req: Request, res: Response) => {
  try {
    const { topic, platform, format, pillar, context } = req.body;

    const systemPrompt = buildSystemPrompt(context);

    const message = await anthropic.messages.create({
      model: "claude-sonnet-4-20250514",
      max_tokens: 1024,
      system: systemPrompt,
      messages: [
        {
          role: "user",
          content: `Write 3 caption variations for ${platform}. Format: ${format}. Topic: ${topic}. Pillar: ${pillar || "general"}. Return JSON with: variations (array of 3 strings), hashtags (array of strings). Write in my brand voice.`,
        },
      ],
    });

    const text =
      message.content[0].type === "text" ? message.content[0].text : "";

    res.json({ result: text });
  } catch (error) {
    console.error("generate-caption error:", error);
    res.status(500).json({ error: "Failed to generate caption" });
  }
});

// POST /api/ai/chat
// Conversational AI with full creator context
router.post("/chat", async (req: Request, res: Response) => {
  try {
    const { messages, context } = req.body;

    const systemPrompt = buildSystemPrompt(context);

    const message = await anthropic.messages.create({
      model: "claude-sonnet-4-20250514",
      max_tokens: 2048,
      system: systemPrompt,
      messages: messages.map((m: { role: string; content: string }) => ({
        role: m.role as "user" | "assistant",
        content: m.content,
      })),
    });

    const text =
      message.content[0].type === "text" ? message.content[0].text : "";

    res.json({ role: "assistant", content: text });
  } catch (error) {
    console.error("chat error:", error);
    res.status(500).json({ error: "Failed to process chat" });
  }
});

// POST /api/ai/adapt-caption
// Adapts a caption for a different platform
router.post("/adapt-caption", async (req: Request, res: Response) => {
  try {
    const { caption, targetPlatform, context } = req.body;

    const systemPrompt = buildSystemPrompt(context);

    const platformRules: Record<string, string> = {
      instagram:
        "Max 2200 chars, use emojis moderately, include line breaks for readability, 20-30 hashtags at the end",
      tiktok:
        "Max 150 chars, very casual, 3-5 hashtags, reference trending sounds if relevant",
      x: "Max 280 chars, punchy, 1-3 hashtags max, no emojis unless on-brand",
      youtube:
        "For community posts or video descriptions. Can be longer. Include timestamps if video.",
      linkedin:
        "Professional but personable, use line breaks, no hashtags in body (3-5 at end), longer form OK",
      pinterest: "Keyword-rich for SEO, 2-3 sentences, include relevant hashtags",
      facebook: "Conversational, can include links, moderate length, minimal hashtags",
    };

    const rules = platformRules[targetPlatform] || "General social media post";

    const message = await anthropic.messages.create({
      model: "claude-sonnet-4-20250514",
      max_tokens: 512,
      system: systemPrompt,
      messages: [
        {
          role: "user",
          content: `Adapt this caption for ${targetPlatform}. Rules: ${rules}. Keep my brand voice. Return only the adapted caption.\n\nOriginal: ${caption}`,
        },
      ],
    });

    const text =
      message.content[0].type === "text" ? message.content[0].text : "";

    res.json({ caption: text });
  } catch (error) {
    console.error("adapt-caption error:", error);
    res.status(500).json({ error: "Failed to adapt caption" });
  }
});

// POST /api/ai/analyze-inspiration
// Analyzes saved inspiration for content angles
router.post(
  "/analyze-inspiration",
  async (req: Request, res: Response) => {
    try {
      const { text, sourceURL } = req.body;

      const content = text || `Content from: ${sourceURL}`;

      const message = await anthropic.messages.create({
        model: "claude-sonnet-4-20250514",
        max_tokens: 1024,
        messages: [
          {
            role: "user",
            content: `Analyze this piece of content/inspiration for a content creator. Return JSON with: summary (1-2 sentences), themes (array of keywords), contentAngles (3 ways they could create their own content inspired by this), suggestedPillar (best-fit content pillar name or null).\n\nContent: ${content}`,
          },
        ],
      });

      const responseText =
        message.content[0].type === "text" ? message.content[0].text : "";

      res.json({ result: responseText });
    } catch (error) {
      console.error("analyze-inspiration error:", error);
      res.status(500).json({ error: "Failed to analyze inspiration" });
    }
  }
);

function buildSystemPrompt(context?: {
  displayName?: string;
  niche?: string;
  voiceAdjectives?: string[];
  voiceDescription?: string;
  pillarNames?: string[];
  recentContentTitles?: string[];
  platforms?: string[];
  goals?: string;
}): string {
  if (!context) {
    return "You are Agent Cy, an AI content creation assistant. Help the creator plan, write, and strategize their content.";
  }

  return `You are Agent Cy, a creative content assistant for ${context.displayName || "a creator"}.

BRAND VOICE:
${context.voiceDescription || `Tone: ${(context.voiceAdjectives || []).join(", ") || "friendly, authentic"}`}

NICHE: ${context.niche || "general"}

CONTENT PILLARS:
${(context.pillarNames || []).map((p) => `- ${p}`).join("\n") || "Not yet defined"}

PLATFORMS: ${(context.platforms || []).join(", ") || "general"}

GOALS: ${context.goals || "grow and engage"}

RECENT CONTENT (avoid repetition):
${(context.recentContentTitles || []).map((t) => `- ${t}`).join("\n") || "None yet"}

RULES:
- Always write in the creator's brand voice
- Suggest content aligned with their pillars
- Be specific and actionable, not generic
- When suggesting ideas, include the hook, angle, and format
- Keep responses concise unless asked for detail`;
}

export { router as aiRouter };
