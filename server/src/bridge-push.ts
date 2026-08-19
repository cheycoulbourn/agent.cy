export interface BridgePushMessage {
  readonly deviceToken: string;
  readonly platform: "ios" | "macCatalyst";
  readonly title: string;
  readonly body: string;
  readonly category: "agentcy.mcp-review";
  readonly collapseId: string;
  readonly requestId: string;
}

export interface BridgePushSending {
  send(message: BridgePushMessage): Promise<void>;
}

export interface ApnsBridgePushConfig {
  readonly teamId: string;
  readonly keyId: string;
  readonly privateKey: string;
  readonly topic: string;
  readonly environment: "development" | "production";
}

interface ApnsTransportRequest {
  readonly origin: string;
  readonly path: string;
  readonly headers: Readonly<Record<string, string>>;
  readonly body: Readonly<Record<string, unknown>>;
}

interface ApnsTransportResponse {
  readonly status: number;
  readonly body: string;
}

interface ApnsTransport {
  send(request: ApnsTransportRequest): Promise<ApnsTransportResponse>;
}

interface ApnsTokenProviding {
  token(): Promise<string>;
}

export class ApnsBridgePushSender implements BridgePushSending {
  private readonly transport: ApnsTransport;
  private readonly tokenProvider: ApnsTokenProviding;

  constructor(
    private readonly config: ApnsBridgePushConfig,
    transport: ApnsTransport = new Http2ApnsTransport(),
    tokenProvider: ApnsTokenProviding = new ApnsProviderToken(config),
  ) {
    this.transport = transport;
    this.tokenProvider = tokenProvider;
  }

  async send(message: BridgePushMessage): Promise<void> {
    const response = await this.transport.send({
      origin: this.config.environment === "production"
        ? "https://api.push.apple.com"
        : "https://api.sandbox.push.apple.com",
      path: `/3/device/${message.deviceToken}`,
      headers: {
        authorization: `bearer ${await this.tokenProvider.token()}`,
        "apns-topic": this.config.topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-collapse-id": message.collapseId,
      },
      body: {
        aps: {
          alert: { title: message.title, body: message.body },
          sound: "default",
          category: message.category,
          "thread-id": "agentcy-mcp-review",
          "content-available": 1,
        },
        agentcy_route: "mcpReview",
        agentcy_request_id: message.requestId,
      },
    });
    if (response.status !== 200) {
      throw new Error(`APNs returned ${response.status}${response.body ? `: ${response.body}` : "."}`);
    }
  }
}

class ApnsProviderToken implements ApnsTokenProviding {
  private cached: { value: string; expiresAt: number } | null = null;

  constructor(private readonly config: ApnsBridgePushConfig) {}

  async token(): Promise<string> {
    const nowSeconds = Math.floor(Date.now() / 1_000);
    if (this.cached && this.cached.expiresAt > nowSeconds) return this.cached.value;
    const key = await importPKCS8(this.config.privateKey.replace(/\\n/g, "\n"), "ES256");
    const value = await new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: this.config.keyId })
      .setIssuer(this.config.teamId)
      .setIssuedAt(nowSeconds)
      .sign(key);
    this.cached = { value, expiresAt: nowSeconds + 50 * 60 };
    return value;
  }
}

class Http2ApnsTransport implements ApnsTransport {
  send(request: ApnsTransportRequest): Promise<ApnsTransportResponse> {
    return new Promise((resolve, reject) => {
      const client = connect(request.origin);
      const stream = client.request({
        ":method": "POST",
        ":path": request.path,
        "content-type": "application/json",
        ...request.headers,
      });
      let status = 0;
      let responseBody = "";
      stream.setEncoding("utf8");
      stream.on("response", (headers) => {
        status = Number(headers[":status"] ?? 0);
      });
      stream.on("data", (chunk: string) => { responseBody += chunk; });
      stream.on("end", () => {
        client.close();
        resolve({ status, body: responseBody });
      });
      stream.on("error", (error) => {
        client.close();
        reject(error);
      });
      client.on("error", reject);
      stream.end(JSON.stringify(request.body));
    });
  }
}

export class UnavailableBridgePushSender implements BridgePushSending {
  async send(): Promise<void> {
    throw new Error("APNs is not configured for this server.");
  }
}
import { connect } from "node:http2";
import { importPKCS8, SignJWT } from "jose";
