# Page, navigation, and design cohesion review

Reviewed September 5, 2026, following cleanup commit `1adb4f0`. This pass includes the previously uncommitted episode-review, iCloud queue-loading, posted-date, and thumbnail edits. Those edits were preserved and reviewed; the fixes below extend them. No deployment, production approval, or physical-device installation was performed.

## Findings and fixes

| Finding | Result |
| --- | --- |
| Quick Add opened another sheet for idea/post/task capture and live-post capture. | These stages now replace the content of the existing Quick Add sheet. The existing Back to Quick Add action returns to the menu. Voice recording retains its separate recording sheet. |
| Idea detail actions could finish underneath the floating phone navigation. | The page uses the shared bottom-navigation clearance and the standard title font. Both actions were visible above navigation after scrolling into view. |
| Converting an idea stalled while opening the post editor. | Reproduced from Idea Bank; a process sample showed repeated editor rendering. Replaced the separate presentation Boolean and output state with one item-based navigation destination. The same route then opened a stable editor with the original title, notes, and linked task. Returning to an existing draft offers Open post. |
| Closing a proposal discarded local review edits, and the conversation still offered Compose post afterward. | Close persists the pending proposal without accepting it. Continue review reopens those edits. Backgrounding also saves review changes; dirty interactive dismissal is blocked until saved. Missing or replaced proposals cannot be recreated by a late close. Accepting closes both the review and its Build with Cy parent. |
| Cy could report unavailable while Settings said Connected and offered no repair path. | Cy and Settings now share one availability resolver. Unavailable Cy links directly to Cy connection, with routes to hosted access and Claude/Codex bridge setup. Checking, local bridge, hosted access, and unavailable have distinct labels. Hosted access means valid local credentials and access policy, not a successful network probe. |
| Episode edits could be serialized before buffered title/copy/notes/date fields were committed. Some visible controls had no representation in the queued request. | The host Save action first commits the editor, then builds the edited request. The review editor exposes supported fields and explains that scripts, media, and tasks can be added after approval. Save errors remain visible in the editor. Series defaults hydrate the draft, and approving an edited platform/format applies that selection instead of silently restoring the series destination. |
| Raw brand-mark red made text too dim in dark mode; Customize used the control radius instead of the button radius. | Foreground labels use the adaptive accent-text token; brand fills retain their existing color. The dark text token keeps its hue/chroma and raises lightness to clear 4.5:1 against the dark canvas. `design.md` and the contrast regression check agree. Customize now uses the canonical button radius. |

## Runtime coverage

Used an iPhone 17 Pro simulator on iOS 26.5 and an isolated Mac Catalyst preview bundle (`com.agentcy.cohesion-preview`). Runtime records were seeded in memory. Debug-only proposal fixtures exercise review without sending a Cy request or approving an external queue item.

| Page family / route | Evidence |
| --- | --- |
| Home, Plan/Agenda, Tasks, Pillars, Idea Bank, Cy | Phone roots inspected through screenshots and accessibility state. Home, Agenda, Feed, Tasks, and Saved Posts also inspected on desktop. |
| Pillars → pillar detail → idea | Opened the linked idea and inspected its form and actions. |
| Idea Bank → idea → post | Reproduced the rendering stall, applied item-based navigation, and re-ran the conversion into a stable post editor. |
| Quick Add → idea capture → Back | Verified one sheet, the capture form, and return to Quick Add. Post/task modes share this capture container; every capture-mode save combination was not exercised. |
| Agenda → task → linked scheduled post | Followed the desktop links and inspected task fields, subtasks, the linked post, and post detail. A first task navigation attempt required reselecting Tasks; a later task detail/link worked. This intermittent first-entry behavior is not claimed fixed by the idea-route change. |
| Scheduled post → Mark as posted → posted date | Inspected the compact form, expanded calendar, disabled future dates, and Cancel returning to the post. |
| Post editor → Edit media | Verified the phone cover preview, constrained thumbnails, media options, add actions, and Done control. No media was uploaded. |
| Settings → Weekly focus → Monday → recurring tasks → Save | Saved an in-memory focus selection and verified the updated Monday value in the parent list. |
| Cy unavailable → Cy connection → Connect Claude or Codex | Verified matching unavailable status and the correct bridge setup destination. No credentials or live bridge settings were changed. |
| Proposal review → edit → close → Continue review → accept | Verified the edited title reappeared, the working post remained unchanged before acceptance, and acceptance returned to the fixture's parent screen with the accepted title. |
| Pending episode → Edit episode | Verified populated fields on first open, planning dates, supported controls, text entry, and cancellation leaving Original hook intact. The native phone Save toolbar button was visible but unavailable through the automation accessibility tree; save-to-approval data propagation is covered by source review and regression tests, not a claimed complete live Save/Approve run. |
| Feed and Saved Posts | Desktop planned-post grid and empty library inspected, including their add actions. Phone saved-post link capture inspected. Remote link fetching and populated imported-post detail were not exercised. |
| Light / dark appearance | Phone light layouts and desktop dark Agenda, Feed, and Saved Posts inspected. Dark foreground-token changes also have a numeric contrast check. This was not a full accessibility certification across text sizes and assistive technologies. |

## Verification

Final validation after the phone navigation and contrast changes:

- **763 iOS tests passed**, including five new review/availability/episode regression tests and expanded light/dark accent-text contrast assertions. Existing posted-date and iCloud candidate/retry tests remain in place.
- **iOS Release and Mac Catalyst Release builds passed**, with signing disabled for local compilation. Debug simulator and isolated Catalyst preview builds also passed.
- **Inter typography, the design ratchet, and `git diff --check` passed.** The ratchet permits existing baseline violations and is not a zero-design-debt certification.
- No TypeScript changed in this pass. The preceding cleanup's 140 passing TypeScript tests, typecheck, and build were not rerun for Swift-only edits.

Build/test logs are under `/tmp/agentcy-cohesion-*`. The main final logs are `full-tests.log`, `ios-release.log`, `mac-release.log`, `typography.log`, and `design.log` with that prefix.

## Remaining limits

- Actual cross-device iCloud placeholder download, live hosted AI, bridge round trips, remote saved-post fetching, account recovery, payments, notification delivery, and calendar synchronization require their respective live environments. This review does not certify those flows from fixture evidence.
- The unsigned desktop preview produced CloudKit initialization crash reports during the review. Subsequent launches with explicit in-memory fixture arguments supported the desktop checks. These reports do not establish a shipped media-editor crash.
- The native phone and desktop episode Save → Approve checks subsequently ran successfully in the September 6 foreground follow-up below. A single phone punctuation discrepancy remains unexplained and did not recur in the repeat check.
- Desktop Agenda → first task → linked scheduled post subsequently passed in the September 6 foreground follow-up. Two earlier navigation-timing experiments did not establish a fix and were removed; existing desktop navigation is preserved.
- Historical refinement findings are not automatically closed by this pass. Coverage here is the principal page families and the listed links, rather than every possible page, data state, device size, or deep link.

This report accompanies the cohesion updates. The earlier cleanup remains separately committed as `1adb4f0`.

## September 6 computer testing follow-up

The installed Mac app is build 229; the reviewed source is build 232. The installed app was inspected without changing its open draft. Interactive mutations used the isolated Catalyst preview and an in-memory iPhone 17 Pro simulator fixture.

- Fresh validation passed: **763 iOS tests, zero failures**, Debug Catalyst build, Catalyst Release build, and a final Debug simulator build after correcting the fixture's workspace assignment. Logs: `/tmp/agentcy-computer-test-ios.log`, `/tmp/agentcy-computer-test-desktop.log`, `/tmp/agentcy-computer-test-release.log`, and `/tmp/agentcy-computer-test-fixture-build.log`.
- The debug episode fixture now presents the actual desktop review surface on Catalyst. Its injected approval action uses real request application against the in-memory store, then opens the resulting post. Production approval retains its existing default implementation. This fixture does not acknowledge a live bridge request or export widget data.
- Phone **Approve episode → resulting post → Go to series → scheduled episode detail** passed through accessibility-button interaction and screenshot inspection. The series displayed one scheduled episode with the expected title, date, platform, and original copy. Initial fixture series records lacked the active workspace assignment and incorrectly showed zero episodes; correcting the fixture resolved that result.
- Phone **Edit episode** opens populated controls. The native Save button is visible in screenshots but absent from the exposed accessibility tree. Coordinate clicks fail with `noWindowsAvailable`; the keyboard shortcut did not complete Save. An accessibility value assignment changed the displayed hook, but a separate post-save check retained the original hook, so that assignment is not accepted as evidence of a completed user edit or successful persistence. Full edit → Save → Approve remains unverified.
- Desktop task navigation and episode selection still produce inconsistent detail redraw during automation. Mouse clicks fail with `noWindowsAvailable`; requesting Finder also fails with `cgWindowNotFound`. A user foreground check was requested to distinguish computer-control failure from app behavior. No speculative navigation fix was added.

No live account, bridge approval, physical-device installation, production app replacement, commit, or push occurred during this follow-up.

### Foreground follow-up after user confirmation

The user brought the desktop test window forward and confirmed that episode details opened. Subsequent accessibility state and screenshots showed the populated detail pane. Coordinate interaction then also worked in Simulator. The earlier control failures are not evidence of a product navigation defect.

- **Desktop episode edit → Save → reopen → Back → Approve passed.** Typed hook text appeared in the review, survived reopening, and appeared in the resulting post after fixture approval.
- **Desktop Agenda → first task → linked scheduled post passed on the first attempt after relaunch.** The task showed its title, due date, subtasks, and linked post; the linked scheduled post showed its expected title, cover, platform, date, and task links. No navigation code change was needed.
- **Phone episode edit → native Save → review → Approve passed in a repeat check.** Coordinate clicking reached the native Save control. The exact hook `Check: Phone reviewOriginal hook` and caption `Verified caption. Original caption` were visible in both the review and resulting post. Caption editing was ended with Done; the repeated hook check saved directly while editing remained active.
- **One text discrepancy remains unexplained.** An earlier phone hook entry displayed `Phone review: Original hook`, then saved as `Phone reviewOriginal hook`. A repeated active-field Save preserved `Check: ` exactly, and the caption preserved its period and space. This was not reproduced or attributed conclusively to the app versus simulator text injection; no speculative text-handling change was made.

These checks used the same tested binaries and in-memory request application described above. They do not establish persistence across process relaunch or a live bridge acknowledgment. This foreground follow-up changes the verification record, not production code.
