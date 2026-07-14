# agent.cy

agent.cy is an iPhone creative copilot that turns a rough idea into a personalized, ready-to-create content plan, then helps the creator execute it.

The repository is a monorepo:

- `ios/` contains the iOS 26 SwiftUI and SwiftData client.
- `contracts/` contains canonical TypeScript/Zod API contracts.
- `server/` contains the Fastify AI proxy and operational endpoints.
- `docs/` contains the canonical product, architecture, privacy, prompt, and validation documents.

## Product boundary

Version 1 covers ideation, creation, and execution. It does not connect to social platforms, publish content, inspect analytics, search live trends, or send creator-added files, audio, or screenshots to Cy. Social links may be kept locally as creator-supplied references; Cy receives only creator-confirmed text.

## Local development

Requirements:

- Xcode 26.6 or newer stable Xcode 26 release
- XcodeGen 2.45+
- Node.js 24 LTS
- pnpm 11+

The repository pins the verified Node release in `.node-version` and constrains the supported major in `package.json`.

Server and contracts:

```bash
pnpm install
pnpm typecheck
pnpm test
pnpm dev:server
```

Development defaults to the deterministic fixture provider. `pnpm build` also regenerates the canonical JSON Schema and OpenAPI artifacts under `contracts/generated/`.

iOS:

```bash
cd ios
xcodegen generate
xcodebuild -project AgentCy.xcodeproj -scheme AgentCy -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

See [Setup](docs/SETUP.md) for environment variables, Apple capabilities, CloudKit, RevenueCat, Anthropic, Railway, and TestFlight configuration.

The production proxy can be built from the repository root with the included `Dockerfile`. It requires owner-supplied secrets and a persistent `/data` volume before serving a real pilot.

## Source of truth

- [Product requirements](docs/PRD.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Data dictionary](docs/DATA_DICTIONARY.md)
- [Paper implementation guide](docs/PAPER_IMPLEMENTATION.md)
- [Privacy](docs/PRIVACY.md)
- [Prompt and contract rules](docs/PROMPT_CONTRACTS.md)
- [Validation protocol](docs/VALIDATION.md)
- [Architecture decisions](docs/adr/)
