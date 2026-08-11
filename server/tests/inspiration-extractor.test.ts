import { describe, expect, it, vi } from "vitest";

import {
  PublicPostExtractor,
  parseInstagramPost,
} from "../src/inspiration-extractor.js";

describe("Instagram inspiration extraction", () => {
  it("extracts the creator, caption, thumbnail, video, and duration from public post pages", () => {
    const postHtml = `
      <meta property="og:title" content="Mari Movie (@mariimovie) on Instagram" />
      <meta property="og:description" content="9,190 likes - mariimovie: &quot;Fallback caption&quot;" />
      <meta property="og:image" content="https://scontent.cdninstagram.com/fallback.jpg?x=1&amp;y=2" />
    `;
    const embedHtml = String.raw`
      <span class="UsernameText">mariimovie</span>
      {\"video_url\":\"https:\\\/\\\/scontent-atl3-3.cdninstagram.com\\\/clip.mp4?x=1\\u0026y=2\",\"video_duration\":37.2,\"edge_media_to_caption\":{\"edges\":[{\"node\":{\"text\":\"The real caption\\nwith a useful point.\"}}]},\"thumbnail_src\":\"https:\\\/\\\/scontent-atl3-3.cdninstagram.com\\\/cover.jpg\"}
    `;

    const result = parseInstagramPost(
      "https://www.instagram.com/reel/DbQtVSaMVlB/",
      postHtml,
      embedHtml,
    );

    expect(result).toMatchObject({
      platform: "instagram",
      mediaKind: "video",
      creatorName: "Mari Movie",
      creatorHandle: "mariimovie",
      caption: "The real caption\nwith a useful point.",
      durationSeconds: 37.2,
    });
    expect(result.thumbnailUrl).toContain("cover.jpg");
    expect(result.mediaUrls).toHaveLength(1);
    expect(result.mediaUrls[0]).toContain("clip.mp4?x=1&y=2");
    expect(result.evidence).toEqual([
      "postMetadata",
      "caption",
      "creator",
      "video",
    ]);
  });

  it("never returns media hosted outside Instagram's CDN", () => {
    const result = parseInstagramPost(
      "https://www.instagram.com/p/SAFE123/",
      '<meta property="og:title" content="Creator on Instagram" />',
      String.raw`<span class="UsernameText">creator</span>{\"text\":\"A useful caption\",\"video_url\":\"https:\\\/\\\/example.com\\\/private.mp4\"}`,
    );

    expect(result.mediaUrls).toEqual([]);
    expect(result.mediaKind).toBe("unknown");
  });

  it("uses oEmbed caption metadata when Instagram blocks both HTML pages", async () => {
    const fetcher = vi.fn<typeof fetch>(async (input) => {
      const url = String(input);
      if (url.includes("/api/v1/oembed/")) {
        return new Response(JSON.stringify({
          author_name: "juliabroome",
          title: "Build a recognizable signature series instead of relying on random one-off posts.",
          thumbnail_url: "https://scontent-atl3-2.cdninstagram.com/series-cover.jpg",
        }), {
          status: 200,
          headers: { "content-type": "application/json" },
        });
      }
      return new Response("rate limited", {
        status: 429,
        headers: { "content-type": "text/html" },
      });
    });
    const extractor = new PublicPostExtractor(fetcher);

    const result = await extractor.extract(
      "https://www.instagram.com/reel/Da3BGW2RoLD/",
    );

    expect(result).toMatchObject({
      platform: "instagram",
      creatorHandle: "juliabroome",
      caption: "Build a recognizable signature series instead of relying on random one-off posts.",
      mediaKind: "image",
    });
    expect(result.thumbnailUrl).toContain("series-cover.jpg");
    expect(result.evidence).toEqual(["postMetadata", "caption", "creator"]);
    expect(fetcher).toHaveBeenCalledTimes(3);
  });

  it("rejects non-post URLs before making a network request", async () => {
    const fetcher = vi.fn<typeof fetch>();
    const extractor = new PublicPostExtractor(fetcher);

    await expect(
      extractor.extract("https://example.com/reel/DbQtVSaMVlB/"),
    ).rejects.toMatchObject({ code: "invalid_input" });
    expect(fetcher).not.toHaveBeenCalled();
  });
});
