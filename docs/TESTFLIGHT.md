# TestFlight release

Use this checklist for every beta build. The repository can verify and archive the app, but signing into Apple, accepting agreements, managing CloudKit Production, and inviting testers remain owner-controlled actions.

## One-time Apple setup

1. In Xcode, open **Settings > Accounts**, add the Apple Account that owns team `2S27MSM8G8`, and download signing assets.
2. In App Store Connect, create the agent.cy app record for bundle ID `com.agentcy.app` if it does not exist.
3. Confirm the app and widget identifiers, `iCloud.com.agentcy.app`, and `group.com.agentcy.app` belong to the same team.
4. Add beta contact information, a beta description, a feedback email, and testing notes.
5. Promote the exercised CloudKit development schema to Production before giving the build to external testers.
6. Complete App Privacy answers from `docs/PRIVACY.md` and confirm the privacy manifests match the archived binary.

## Build and signing verification

Increment `CURRENT_PROJECT_VERSION` in `ios/project.yml`, then run:

```bash
BUILD_NUMBER=136 EXPORT=1 ./scripts/archive_testflight.sh
```

The script runs the complete monorepo and iOS verification suite by default, regenerates the Xcode project, creates a Release archive, and verifies App Store Connect distribution signing. Set `VERIFY=0` only when the same commit has already passed the complete suite.

Each archive must contain:

- `com.agentcy.app` and the agent.cy widget extension.
- CloudKit container `iCloud.com.agentcy.app`.
- App group `group.com.agentcy.app`.
- `ITSAppUsesNonExemptEncryption` set to `false` when the shipped binary continues to use only exempt standard encryption such as HTTPS.
- A build number that has not already been uploaded for version `0.1.0`.

## Upload and beta setup

1. Open the archive in Xcode Organizer and choose **Distribute App > App Store Connect > Upload**.
2. Wait for App Store Connect processing to complete and review every warning.
3. Add the processed build to an internal testing group first.
4. Verify onboarding, CloudKit sync, notifications, widgets, export, reset, MCP review, dated post creation, and offline editing on a clean device and an upgraded device.
5. Add the build to the external five-creator group, enter **What to Test**, and submit the first external build for TestFlight review.

## Pilot boundaries

- The first external cohort uses the server-controlled promotional entitlement. TestFlight purchases are not treated as real revenue.
- The current iOS app does not contain the production RevenueCat SDK purchase and restore flow. Do not begin a paid App Store pilot until that client integration is complete.
- App Attest remains required before the paid production pilot, not before the small promotional TestFlight cohort.
- Verify Railway production secrets, the persistent `/data` volume, Anthropic spending controls, and privacy-safe logging before inviting external testers.
