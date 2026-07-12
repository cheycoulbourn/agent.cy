# External Setup

The repository can build and run with local fixture services. Production behavior additionally requires the following owner-controlled setup.

## Apple

- Apple Developer team and bundle identifier.
- iCloud and private CloudKit container.
- Background Modes remote-notification capability for CloudKit mirroring.
- Microphone usage description.
- App Store Connect app record and monthly subscription product.
- Paid Apps Agreement, banking, and tax information before real billing.
- TestFlight groups and external beta review.
- App Attest before the paid production pilot.

## Anthropic

- Commercial API organization and workspace.
- `ANTHROPIC_API_KEY` stored only in Railway secrets or local `.env`.
- Spending ceiling and rate-limit alerts.
- Confirm retention terms before publishing privacy claims.

## RevenueCat

- Project, iOS app, entitlement, offering, and $8.99 monthly product.
- 14-day introductory trial configured in App Store Connect.
- Webhook secret configured in the server and RevenueCat dashboard.
- The same `creator_access` entitlement identifier configured in the app, RevenueCat, and `REVENUECAT_ENTITLEMENT_ID` on the proxy.
- Promotional entitlements for the TestFlight validation cohort.

## Railway

- Server service built with Node 24 LTS.
- Persistent volume for hashed installation records, counters, entitlements, and content-free telemetry.
- Preview and production environments.
- Separate secrets for invitation hashing and installation credential hashing, plus Anthropic, RevenueCat, and webhook verification.
- Request body and authorization logging disabled.

The repository root contains a production `Dockerfile` and `railway.json`. Railway should build from the repository root because the server imports the shared contracts workspace. Attach one volume at `/data`, keep one replica for the JSON repository, set `DATA_FILE=/data/agent-cy-state.json`, and configure the production secrets before the first deployment. The service health check is `/healthz`.

Keep `INVITE_HASH_SECRET` stable after codes have been issued. Rotate `INSTALLATION_HASH_SECRET` by moving its prior value into `PREVIOUS_INSTALLATION_HASH_SECRETS`; authenticated requests are rehashed with the newest secret after successful verification.

Railway detects a root Dockerfile and supports shared JavaScript monorepos. See [Railway Dockerfiles](https://docs.railway.com/builds/dockerfiles) and [Railway monorepos](https://docs.railway.com/deployments/monorepo).

## Local environment

Copy `server/.env.example` to `server/.env` and use the fixture AI provider until real credentials are available. Never commit real secrets or local operational databases.

Run the proxy locally from the repository root:

```bash
pnpm install --frozen-lockfile
pnpm dev:server
```

## iOS verification

Debug builds use the local fixture creative service by default. To exercise the live proxy in a Debug launch, set the scheme environment variable `AGENTCY_USE_LIVE_AI=1`; `AGENTCY_API_BASE_URL` can override the endpoint in the same way. Live mode inserts one-use invitation redemption before the first AI request and stores the returned credential in the device-only Keychain.

Release builds use the live service by default. Before archiving, replace the `https://replace-me.invalid` value in `ios/project.yml` with the deployed Railway HTTPS origin, regenerate the project with `xcodegen generate`, and verify `/healthz` plus invitation redemption on a real device. Do not ship the placeholder endpoint.

Install an iOS Simulator runtime matching the Xcode iOS SDK to run the complete test suite and visual checks. Then run `./scripts/verify.sh`.

If Xcode and the installed simulator runtime temporarily differ, source and test-bundle compilation can still be verified without asset thinning or test execution:

```bash
IOS_SOURCE_ONLY=1 ./scripts/verify.sh
```

The simulator intentionally uses the local `AgentCyStore` without CloudKit mirroring. Signed iPhone builds use the same schema and store identity with the private CloudKit container.
