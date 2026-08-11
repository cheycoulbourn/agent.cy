# External Setup

The repository can build and run with local fixture services. Production behavior additionally requires the following owner-controlled setup.

## Apple

- Apple Developer team and bundle identifier.
- Sign in with Apple capability enabled for `com.agentcy.app` on iOS and Mac Catalyst.
- iCloud and private CloudKit container.
- Background Modes remote-notification capability for CloudKit mirroring.
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
- Separate secrets for invitation hashing, installation credential hashing, and Apple-subject hashing, plus Anthropic, RevenueCat, and webhook verification.
- Request body and authorization logging disabled.

The repository root contains a production `Dockerfile` and `railway.json`. Railway should build from the repository root because the server imports the shared contracts workspace. Attach one volume at `/data`, keep one replica for the JSON repository, set `DATA_FILE=/data/agent-cy-state.json`, and configure the production secrets before the first deployment. The service health check is `/healthz`.

Production starts only when `NODE_ENV=production` and `AI_PROVIDER=anthropic`. Use distinct hash secrets of at least 32 characters. `APPLE_SUBJECT_HASH_SECRET` must differ from the invitation and every installation secret; `APPLE_CLIENT_IDS` must include `com.agentcy.app`. Keep `INVITE_HASH_SECRET` stable after codes have been issued. Rotate `INSTALLATION_HASH_SECRET` by moving its prior value into `PREVIOUS_INSTALLATION_HASH_SECRETS`; every current and previous installation secret must remain unique, and authenticated requests are rehashed with the newest secret after successful verification.

Every production `INVITE_CODES` value must be unique and contain at least 20 characters across at least three character classes. Set `PILOT_COMPED_ACCESS` explicitly for the cohort and set `PILOT_COMPED_DURATION_DAYS` to its intended fixed duration; the current validation default is 28 days.

Railway detects a root Dockerfile and supports shared JavaScript monorepos. See [Railway Dockerfiles](https://docs.railway.com/builds/dockerfiles) and [Railway monorepos](https://docs.railway.com/deployments/monorepo).

## Local environment

Copy `server/.env.example` to `server/.env` and use the fixture AI provider until real credentials are available. Never commit real secrets or local operational databases.

Run the proxy locally from the repository root:

```bash
pnpm install --frozen-lockfile
pnpm dev:server
```

## iOS verification

The generated Debug and Release configurations both target the live Railway proxy. Set the Debug scheme environment variable `AGENTCY_USE_LIVE_AI=0` to use the deterministic in-process preview service. To exercise a local Fastify fixture instead, leave `AGENTCY_USE_LIVE_AI=1` and set `AGENTCY_API_BASE_URL=http://127.0.0.1:3000`. Live mode requires the first device to redeem a one-use invitation before the first AI request; it never inserts or redeems a code automatically. The creator can then link that installation to Apple from Access settings and use Sign in with Apple on another device. Each device receives a separate credential stored in its device-only Keychain.

Release builds use the live service at `https://agentcy-production.up.railway.app`. Before archiving, regenerate the project with `xcodegen generate` and verify `/healthz` plus invitation redemption on a real device.

Install an iOS Simulator runtime matching the Xcode iOS SDK to run the complete test suite and visual checks. Then run `./scripts/verify.sh`.

If Xcode and the installed simulator runtime temporarily differ, source and test-bundle compilation can still be verified without asset thinning or test execution:

```bash
IOS_SOURCE_ONLY=1 ./scripts/verify.sh
```

Every simulator uses the local `AgentCyStore` without CloudKit mirroring. The generated Debug configuration also disables CloudKit on a signed iPhone; the signed Release configuration uses the same schema and store identity with the private CloudKit container.

## Release gates still outside the repository

- The RevenueCat webhook projection exists on the proxy, but the iOS RevenueCat SDK, verified purchase flow, and restore flow are not wired. `UnavailableLiveSubscriptionService` fails closed, so real paid billing is not ready to ship.
- App Attest is represented only as an optional request-contract field. The app does not yet generate assertions and the proxy does not yet verify them.
- Promote the CloudKit development schema and complete signed two-device sync, conflict, and erase testing.
- Enable Sign in with Apple for the App ID and refresh the iOS and Mac Catalyst provisioning profiles before the first signed account test.
- Verify Railway secrets, the persistent `/data` volume, webhook configuration, Anthropic spending controls, and provider retention terms in their owner-controlled dashboards.
- Review the bundled privacy manifests against the final binaries and complete App Store Connect privacy labels for proxy telemetry and AI processing.
