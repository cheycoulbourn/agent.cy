import type { FastifyReply } from "fastify";

export type SseEventName = "meta" | "phase" | "result" | "error" | "done";

export class SseWriter {
  private ended = false;

  constructor(private readonly reply: FastifyReply) {
    reply.hijack();
    reply.raw.writeHead(200, {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-cache, no-store, must-revalidate",
      connection: "keep-alive",
      "x-accel-buffering": "no",
    });
    reply.raw.flushHeaders();
  }

  send(event: SseEventName, data: unknown): void {
    if (this.ended || this.reply.raw.destroyed) return;
    this.reply.raw.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  }

  close(): void {
    if (this.ended) return;
    this.ended = true;
    this.reply.raw.end();
  }
}

export interface ParsedSseEvent {
  readonly event: string;
  readonly data: unknown;
}

export function parseSseForTests(payload: string): ParsedSseEvent[] {
  return payload
    .split("\n\n")
    .filter((block) => block.trim().length > 0)
    .map((block) => {
      const lines = block.split("\n");
      const event = lines.find((line) => line.startsWith("event: "))?.slice(7);
      const data = lines.find((line) => line.startsWith("data: "))?.slice(6);
      if (!event || data === undefined) {
        throw new Error(`Invalid SSE block: ${block}`);
      }
      return { event, data: JSON.parse(data) as unknown };
    });
}
