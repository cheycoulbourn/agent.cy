# L4 build warning census — captured 2026-09-01

## Commands
```
xcodebuild -project ios/AgentCy.xcodeproj -scheme AgentCy -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath <scratch>/L4/DD build            # BUILD SUCCEEDED
xcodebuild ... build-for-testing                                                                             # TEST BUILD SUCCEEDED
xcodebuild -scheme 'AgentCy Desktop' -destination 'platform=macOS,variant=Mac Catalyst' ... build            # BUILD SUCCEEDED
```

Clean derived data (no prior cache), so every warning below was emitted by a full compile of all sources.

## iOS simulator build (AgentCy + AgentCyWidgets + AgentCyInspirationShare)
```
  11 warning: 'copyCGImage(at:actualTime:)' was deprecated in iOS 18.0: Use generateCGImageAsynchronouslyForTime:completionHandler: instead
   1 warning: Metadata extraction skipped. No AppIntents.framework dependency found.
```
Sites:
```
2026-09-01 16:20:31.278 appintentsmetadataprocessor[16371:491869] warning: Metadata extraction skipped. No AppIntents.framework dependency found.
ios/AgentCy/Services/InspirationContentAnalysisService.swift:362:43: warning: 'copyCGImage(at:actualTime:)' was deprecated in iOS 18.0: Use generateCGImageAsynchronouslyForTime:completionHandler: instead
ios/AgentCyInspirationShare/InspirationShareMediaAnalyzer.swift:147:43: warning: 'copyCGImage(at:actualTime:)' was deprecated in iOS 18.0: Use generateCGImageAsynchronouslyForTime:completionHandler: instead
```

## build-for-testing (adds AgentCyTests)
```
2026-09-01 16:24:58.590 appintentsmetadataprocessor[18057:518484] warning: Metadata extraction skipped. No AppIntents.framework dependency found.
ios/AgentCyTests/ServiceTests.swift:961:22: warning: 'init(frame:)' was deprecated in iOS 26.0: Use init(windowScene:) instead.
```

## Mac Catalyst build (AgentCyMac)
```
  10 warning: 'copyCGImage(at:actualTime:)' was deprecated in Mac Catalyst 18.0: Use generateCGImageAsynchronouslyForTime:completionHandler: instead
   1 warning: result of call to 'withTransaction' is unused
```
Sites:
```
ios/AgentCy/Services/InspirationContentAnalysisService.swift:362:43: warning: 'copyCGImage(at:actualTime:)' was deprecated in Mac Catalyst 18.0: Use generateCGImageAsynchronouslyForTime:completionHandler: instead
ios/AgentCy/Views/Shell/DesktopAppShellView.swift:714:9: warning: result of call to 'withTransaction' is unused
```
