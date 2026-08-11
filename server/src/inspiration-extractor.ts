import type {
  InspirationExtractResult,
} from "@agent-cy/contracts";

import { AppError } from "./errors.js";

const INSTAGRAM_HOSTS = new Set([
  "instagram.com",
  "www.instagram.com",
  "m.instagram.com",
]);
const MAXIMUM_PAGE_BYTES = 2 * 1_024 * 1_024;
const MAXIMUM_OEMBED_BYTES = 256 * 1_024;
const DEFAULT_TIMEOUT_MS = 10_000;
const MOBILE_SAFARI_USER_AGENT =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) " +
  "AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1";

export interface InspirationExtracting {
  extract(canonicalUrl: string): Promise<InspirationExtractResult>;
}

export interface InstagramOEmbedPayload {
  readonly author_name?: string;
  readonly title?: string;
  readonly thumbnail_url?: string;
}

export class PublicPostExtractor implements InspirationExtracting {
  constructor(
    private readonly fetcher: typeof fetch = fetch,
    private readonly timeoutMs = DEFAULT_TIMEOUT_MS,
  ) {}

  async extract(rawUrl: string): Promise<InspirationExtractResult> {
    const canonicalUrl = canonicalInstagramUrl(rawUrl);
    const embedUrl = new URL(canonicalUrl);
    embedUrl.pathname = `${embedUrl.pathname.replace(/\/$/, "")}/embed/captioned/`;
    const oEmbedUrl = new URL("https://www.instagram.com/api/v1/oembed/");
    oEmbedUrl.searchParams.set("url", canonicalUrl);

    // Instagram changes and independently rate-limits these surfaces. A public
    // caption from oEmbed should still be usable when either HTML page is
    // blocked, and direct media from the embed should enrich oEmbed when both
    // are available.
    const [postPage, embedPage, oEmbedResponse] = await Promise.allSettled([
      this.fetchHtml(canonicalUrl),
      this.fetchHtml(embedUrl.toString()),
      this.fetchOEmbed(oEmbedUrl.toString()),
    ]);
    return parseInstagramPost(
      canonicalUrl,
      fulfilledValue(postPage) ?? "",
      fulfilledValue(embedPage) ?? "",
      fulfilledValue(oEmbedResponse),
    );
  }

  private async fetchHtml(url: string): Promise<string> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await this.fetcher(url, {
        headers: {
          accept: "text/html,application/xhtml+xml",
          "accept-language": "en-US,en;q=0.9",
          "user-agent": MOBILE_SAFARI_USER_AGENT,
        },
        redirect: "follow",
        signal: controller.signal,
      });
      if (!response.ok) {
        throw new AppError(
          "upstream_unavailable",
          "Instagram did not make this public post available.",
          { retryable: response.status >= 500 },
        );
      }
      const finalUrl = new URL(response.url || url);
      if (!INSTAGRAM_HOSTS.has(finalUrl.hostname.toLowerCase())) {
        throw new AppError("invalid_input", "Instagram redirected to an unsafe page.");
      }
      const contentType = response.headers.get("content-type")?.toLowerCase();
      if (contentType && !contentType.includes("text/html")) {
        throw new AppError("invalid_input", "The shared post did not return a web page.");
      }
      return await readBoundedText(response, MAXIMUM_PAGE_BYTES);
    } catch (error) {
      if (error instanceof AppError) throw error;
      if (error instanceof Error && error.name === "AbortError") {
        throw new AppError("timeout", "Instagram took too long to return this post.", {
          retryable: true,
          cause: error,
        });
      }
      throw new AppError(
        "upstream_unavailable",
        "Instagram did not make this public post available.",
        { retryable: true, cause: error },
      );
    } finally {
      clearTimeout(timeout);
    }
  }

  private async fetchOEmbed(url: string): Promise<InstagramOEmbedPayload> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await this.fetcher(url, {
        headers: {
          accept: "application/json",
          "accept-language": "en-US,en;q=0.9",
          "user-agent": MOBILE_SAFARI_USER_AGENT,
        },
        redirect: "follow",
        signal: controller.signal,
      });
      if (!response.ok) {
        throw new AppError(
          "upstream_unavailable",
          "Instagram did not make this public post metadata available.",
          { retryable: response.status >= 500 || response.status === 429 },
        );
      }
      const finalUrl = new URL(response.url || url);
      if (!INSTAGRAM_HOSTS.has(finalUrl.hostname.toLowerCase())) {
        throw new AppError("invalid_input", "Instagram redirected to an unsafe page.");
      }
      const contentType = response.headers.get("content-type")?.toLowerCase();
      if (contentType && !contentType.includes("application/json")) {
        throw new AppError("upstream_unavailable", "Instagram returned invalid post metadata.");
      }
      const rawPayload: unknown = JSON.parse(
        await readBoundedText(response, MAXIMUM_OEMBED_BYTES),
      );
      if (!isRecord(rawPayload)) {
        throw new AppError("upstream_unavailable", "Instagram returned invalid post metadata.");
      }
      return {
        ...(typeof rawPayload.author_name === "string"
          ? { author_name: rawPayload.author_name }
          : {}),
        ...(typeof rawPayload.title === "string" ? { title: rawPayload.title } : {}),
        ...(typeof rawPayload.thumbnail_url === "string"
          ? { thumbnail_url: rawPayload.thumbnail_url }
          : {}),
      };
    } catch (error) {
      if (error instanceof AppError) throw error;
      if (error instanceof Error && error.name === "AbortError") {
        throw new AppError("timeout", "Instagram took too long to return this post.", {
          retryable: true,
          cause: error,
        });
      }
      throw new AppError(
        "upstream_unavailable",
        "Instagram did not make this public post metadata available.",
        { retryable: true, cause: error },
      );
    } finally {
      clearTimeout(timeout);
    }
  }
}

export function parseInstagramPost(
  canonicalUrl: string,
  postHtml: string,
  embedHtml: string,
  oEmbed?: InstagramOEmbedPayload,
): InspirationExtractResult {
  const rawSourceTitle = cleanText(readMetaContent(postHtml, "og:title"));
  const metaDescription = cleanText(readMetaContent(postHtml, "og:description"));
  const creatorHandle = boundedText(
    cleanText(
      firstMatch(embedHtml, /<span[^>]*class=["'][^"']*UsernameText[^"']*["'][^>]*>([^<]+)<\/span>/i),
    ) ?? cleanText(oEmbed?.author_name),
    160,
  );
  const creatorName = creatorNameFromTitle(rawSourceTitle, creatorHandle);
  const sourceTitle = creatorName
    ? `${creatorName} on Instagram`
    : rawSourceTitle
      ? String(rawSourceTitle.slice(0, 160))
      : undefined;
  const embeddedCaption = cleanText(firstEscapedValue(embedHtml, "text"));
  const caption = boundedText(
    embeddedCaption ?? cleanText(oEmbed?.title) ?? captionFromDescription(metaDescription, creatorHandle),
    20_000,
  );
  const videoUrls = safeMediaUrls(allEscapedValues(embedHtml, "video_url"));
  const displayUrls = safeMediaUrls(allEscapedValues(embedHtml, "display_url"));
  const thumbnailUrl = firstSafeMediaUrl([
    ...allEscapedValues(embedHtml, "thumbnail_src"),
    oEmbed?.thumbnail_url,
    readMetaContent(postHtml, "og:image"),
  ]);
  const mediaUrls = videoUrls.length > 0 ? videoUrls : displayUrls;
  const durationSeconds = firstEscapedNumber(embedHtml, "video_duration");
  const mediaKind = videoUrls.length > 0
    ? "video"
    : displayUrls.length > 1
      ? "carousel"
      : displayUrls.length === 1 || thumbnailUrl
        ? "image"
        : "unknown";
  const evidence: InspirationExtractResult["evidence"] = ["postMetadata"];
  if (caption) evidence.push("caption");
  if (creatorHandle || creatorName) evidence.push("creator");
  if (videoUrls.length > 0) evidence.push("video");
  if (displayUrls.length > 1) evidence.push("carousel");

  if (!caption && mediaUrls.length === 0 && !thumbnailUrl) {
    throw new AppError(
      "upstream_unavailable",
      "Cy could not access enough of this public Instagram post yet.",
      { retryable: true },
    );
  }

  return {
    canonicalUrl,
    platform: "instagram",
    mediaKind,
    ...(sourceTitle ? { sourceTitle } : {}),
    ...(creatorName ? { creatorName } : {}),
    ...(creatorHandle ? { creatorHandle } : {}),
    ...(caption ? { caption } : {}),
    ...(thumbnailUrl ? { thumbnailUrl } : {}),
    mediaUrls,
    ...(durationSeconds === undefined ? {} : { durationSeconds }),
    evidence,
  };
}

function canonicalInstagramUrl(rawUrl: string): string {
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new AppError("invalid_input", "Share a valid public Instagram post link.");
  }
  const hostname = parsed.hostname.toLowerCase();
  const pathMatch = parsed.pathname.match(/^\/(?:reel|p|tv)\/([A-Za-z0-9_-]+)\/?$/);
  if (
    parsed.protocol !== "https:" ||
    parsed.username ||
    parsed.password ||
    !INSTAGRAM_HOSTS.has(hostname) ||
    !pathMatch
  ) {
    throw new AppError(
      "invalid_input",
      "This extractor currently supports public Instagram posts and reels.",
    );
  }
  return `https://www.instagram.com${parsed.pathname.replace(/\/$/, "")}/`;
}

async function readBoundedText(response: Response, maximumBytes: number): Promise<string> {
  const declaredLength = Number(response.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new AppError("payload_too_large", "The post page was unexpectedly large.");
  }
  if (!response.body) return "";

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let receivedBytes = 0;
  let result = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    receivedBytes += value.byteLength;
    if (receivedBytes > maximumBytes) {
      await reader.cancel();
      throw new AppError("payload_too_large", "The post page was unexpectedly large.");
    }
    result += decoder.decode(value, { stream: true });
  }
  return result + decoder.decode();
}

function readMetaContent(html: string, property: string): string | undefined {
  const metaTags = html.match(/<meta\b[^>]*>/gi) ?? [];
  for (const tag of metaTags) {
    const attributes = Object.fromEntries(
      [...tag.matchAll(/([\w:-]+)\s*=\s*(["'])([\s\S]*?)\2/g)].map((match) => [
        match[1]?.toLowerCase() ?? "",
        decodeHtmlEntities(match[3] ?? ""),
      ]),
    );
    if (attributes.property === property || attributes.name === property) {
      return attributes.content;
    }
  }
  return undefined;
}

function firstEscapedValue(html: string, key: string): string | undefined {
  return allEscapedValues(html, key)[0];
}

function allEscapedValues(html: string, key: string): string[] {
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(
    `\\\\"${escapedKey}\\\\":\\\\"((?:\\\\\\\\.|[^"\\\\])*)\\\\"`,
    "g",
  );
  const results: string[] = [];
  for (const match of html.matchAll(pattern)) {
    const decoded = decodeEmbeddedJsonString(match[1] ?? "");
    if (decoded && !results.includes(decoded)) results.push(decoded);
  }
  return results;
}

function firstEscapedNumber(html: string, key: string): number | undefined {
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = html.match(new RegExp(`\\\\"${escapedKey}\\\\":(-?\\d+(?:\\.\\d+)?)`));
  if (!match?.[1]) return undefined;
  const value = Number(match[1]);
  return Number.isFinite(value) && value >= 0 ? value : undefined;
}

function decodeEmbeddedJsonString(rawValue: string): string | undefined {
  let value = rawValue;
  try {
    for (let pass = 0; pass < 2; pass += 1) {
      value = JSON.parse(`"${value}"`) as string;
    }
    return decodeHtmlEntities(value);
  } catch {
    return undefined;
  }
}

function safeMediaUrls(values: readonly (string | undefined)[]): string[] {
  const results: string[] = [];
  for (const value of values) {
    const safe = safeMediaUrl(value);
    if (safe && !results.includes(safe)) results.push(safe);
  }
  return results.slice(0, 20);
}

function firstSafeMediaUrl(values: readonly (string | undefined)[]): string | undefined {
  for (const value of values) {
    const safe = safeMediaUrl(value);
    if (safe) return safe;
  }
  return undefined;
}

function safeMediaUrl(rawValue: string | undefined): string | undefined {
  if (!rawValue) return undefined;
  try {
    const parsed = new URL(decodeHtmlEntities(rawValue));
    const host = parsed.hostname.toLowerCase();
    if (
      parsed.protocol !== "https:" ||
      parsed.username ||
      parsed.password ||
      !(host.endsWith(".cdninstagram.com") || host.endsWith(".fbcdn.net"))
    ) {
      return undefined;
    }
    return parsed.toString();
  } catch {
    return undefined;
  }
}

function creatorNameFromTitle(
  sourceTitle: string | undefined,
  creatorHandle: string | undefined,
): string | undefined {
  if (!sourceTitle) return creatorHandle;
  const byHandle = sourceTitle.match(/^(.+?)\s*\(@[^)]+\)/);
  const onInstagram = sourceTitle.match(/^(.+?)\s+on Instagram(?::|$)/i);
  const candidate = cleanText(byHandle?.[1] ?? onInstagram?.[1]);
  return candidate && candidate.toLowerCase() !== "instagram"
    ? candidate
    : creatorHandle;
}

function captionFromDescription(
  description: string | undefined,
  creatorHandle: string | undefined,
): string | undefined {
  if (!description) return undefined;
  const quoted = description.match(/:\s*[“\"]([\s\S]+?)[”\"]\s*\.?$/)?.[1];
  const cleaned = cleanText(quoted);
  if (cleaned) return cleaned;
  if (creatorHandle && description.length <= 20_000) return description;
  return undefined;
}

function firstMatch(value: string, pattern: RegExp): string | undefined {
  return value.match(pattern)?.[1];
}

function cleanText(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const cleaned = decodeHtmlEntities(value)
    .replace(/<br\s*\/?\s*>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  return cleaned || undefined;
}

function boundedText(value: string | undefined, maximumLength: number): string | undefined {
  return value ? String(value.slice(0, maximumLength)) : undefined;
}

function fulfilledValue<T>(result: PromiseSettledResult<T>): T | undefined {
  return result.status === "fulfilled" ? result.value : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function decodeHtmlEntities(value: string): string {
  return value
    .replace(/&#x([0-9a-f]+);/gi, (_match, hexadecimal: string) =>
      String.fromCodePoint(Number.parseInt(hexadecimal, 16)),
    )
    .replace(/&#(\d+);/g, (_match, decimal: string) =>
      String.fromCodePoint(Number.parseInt(decimal, 10)),
    )
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, "\"")
    .replace(/&#(?:39|x27);/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">");
}
