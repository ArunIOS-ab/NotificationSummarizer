# NotificationSummarizer — iOS 17+

This is a native SwiftUI/SwiftData/App Intents/Core ML project. It is intentionally runnable **without** the Core ML model: until `NotificationClassifier.mlpackage` and its matching `vocab.txt` are added, the app uses the local deterministic fallback classifier/summarizer.

## Open

Open `NotificationSummarizer.xcodeproj` in Xcode 15.4+ (Xcode 16+ recommended), select the `NotificationSummarizer` scheme, choose an iOS 17+ simulator/device, and Run.

## Add the model later

1. Drag `NotificationClassifier.mlpackage` into the `NotificationSummarizer` group.
2. Select **Copy items if needed**.
3. Check **NotificationSummarizer** under Target Membership.
4. Add the exact `vocab.txt` used to train the model under `NotificationSummarizer/Resources/Tokenizer/` and target membership.

The app dynamically loads the compiled Core ML model. No generated model Swift class is required.

## Current behavior

- 100% local processing.
- Six categories: Work, Social, Finance, Security, Promotional, Personal.
- SwiftData persistence.
- App Intent: “Summarize Notifications”.
- 1.5-second classification timeout.
- Rule-based local fallback when the model/tokenizer is unavailable.
- Deterministic 20-word maximum summary fallback.

## Important iOS limitation

A normal third-party app cannot read arbitrary notifications belonging to other apps. To process notifications from your own app, use a Notification Service Extension and an App Group for shared persistence.
