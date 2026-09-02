# Gate H1 decisions

On 2026-09-02 Chey answered the decision packet with "accept all recommendations". That resolves every item in `decision-packet.md` as recommended:

| Item | Resolution |
|---|---|
| DEC-01 | Every glass surface moves from `.clear` to `.regular`; `ProfileSettingsButton` takes the toolbar control's geometry and material. Chey re-judges on device at H2. |
| DEC-02 | Primary button metric: 44 pt tall, 15 pt label. design.md updated in the same commit. |
| DEC-03 | `cyReviewModalMetrics = 1180 × 860` becomes a named exception; `creationHubMenuMetrics` moves to 900 × 860. |
| DEC-04 | Onboarding masthead caps at `.agentDisplay` (32 pt). No eighth type level. |
| DEC-05 | Creator Session family is removed from the binary (Task 74), including its Info.plist declarations. |
| DEC-06 | Brand Cabinet stays behind its setting, default off, out of the beta story. |
| DEC-07 | Saved Posts merges into Idea Bank as a filter; desktop drops the sidebar tab. |
| DEC-08 | Desktop Feed tab demoted to a push from Plan. |
| DEC-09 | Home's three week cards trim to one. |
| DEC-10 | Six tabs stay on phone; desktop goes from eight to six. |
| DEC-11 | The plan may correct `docs/PRD.md` vocabulary (Today → Home, Agenda → Plan, Platforms as an editor section). |
| DEC-12 | `PRIVACY.md` changes to describe the Share Extension's two network calls truthfully. |
| DEC-13 | Local Cy ships with Task 87's mitigations and a plain disclosure in Settings > AI. RISK-02 is accepted. |
| DEC-14 | Fastify stays on patch bumps; no major upgrade before beta. |
| DEC-15 | `ios/build` and `ios/build-device` may be deleted (Task 75). Any dSYM found there is copied to the scratchpad first. |
| DEC-16 | `whyItFits` is surfaced in Idea Bank direction rows. |
| DEC-17 | `UIBackgroundModes: audio` is removed; Voice Spark does not record in the background. |
| DEC-18 | Catalyst Release `APS_ENVIRONMENT` set to `development`. |
| DEC-19 | The post editor gets one chrome contract with two named modes. |
| RISK-01, 02, 03, 05 | Accepted. |
| RISK-04 | Not shipped before the probe reads Railway's `X-Forwarded-For` hop count (Task 80 waits on AUTH-02 phase P1). |
| AUTH-01 | Granted: one Instruments session on Chey's iPhone before and after B2. The session itself still needs her phone connected and unlocked; the controller asks at that moment. |
| AUTH-02 | Granted in principle: the 58-request probe. Still needs, at run time, her confirmation of the hostname, a disposable invite code, and a 30-minute window. |
| AUTH-03 | Granted: `brew install peripheryapp/periphery/periphery` before B4 deletions. |
| AUTH-04 | Granted: `corepack enable && corepack prepare pnpm@11.7.0 --activate`. |
| O-1 … O-14 | Owner steps remain Chey's; the beta-readiness report tracks them. |

Tasks 25, 26, 27 and the 36 pt masthead in Task 8 are unblocked.
