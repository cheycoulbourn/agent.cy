import { describe, expect, it, vi } from "vitest";
import { ApnsBridgePushSender } from "../src/bridge-push.js";

describe("APNs bridge push sender", () => {
  it("sends an alert that routes directly to the MCP review inbox", async () => {
    const send = vi.fn(async () => ({ status: 200, body: "" }));
    const sender = new ApnsBridgePushSender(
      {
        teamId: "TEAM123456",
        keyId: "KEY1234567",
        privateKey: "unused-by-test-token-provider",
        topic: "com.agentcy.app",
        environment: "production",
      },
      { send },
      { token: async () => "signed-provider-token" },
    );

    await sender.send({
      deviceToken: "ab".repeat(32),
      platform: "ios",
      title: "Agent.cy needs your review",
      body: "“The hidden bill behind cheap data” has a new posting date and needs your review.",
      category: "agentcy.mcp-review",
      collapseId: "agentcy-mcp-installation-one",
      requestId: "8f7f6883-6a5c-4df4-9c03-356b02a00be1",
    });

    expect(send).toHaveBeenCalledWith({
      origin: "https://api.push.apple.com",
      path: `/3/device/${"ab".repeat(32)}`,
      headers: {
        authorization: "bearer signed-provider-token",
        "apns-topic": "com.agentcy.app",
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-collapse-id": "agentcy-mcp-installation-one",
      },
      body: {
        aps: {
          alert: {
            title: "Agent.cy needs your review",
            body: "“The hidden bill behind cheap data” has a new posting date and needs your review.",
          },
          sound: "default",
          category: "agentcy.mcp-review",
          "thread-id": "agentcy-mcp-review",
          "content-available": 1,
        },
        agentcy_route: "mcpReview",
        agentcy_request_id: "8f7f6883-6a5c-4df4-9c03-356b02a00be1",
      },
    });
  });
});
