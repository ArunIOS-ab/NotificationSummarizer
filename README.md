# NotificationSummarizer — iOS 17+

This is a native SwiftUI/SwiftData/App Intents/Core ML project. It is intentionally runnable **without** the Core ML model: until `NotificationClassifier.mlpackage` and its matching `vocab.txt` are added, the app uses the local deterministic fallback classifier/summarizer.

## Screenshots

Every notification is classified into one of six categories, summarized on-device, and shown in an adaptive dashboard that re-flows from a single-column phone list to an iPad sidebar/grid/detail layout.

### iPhone

<table>
  <tr>
    <td width="33%"><img src="docs/screenshots/iphone-compact.png" alt="Compact width phone dashboard" /></td>
    <td width="33%"><img src="docs/screenshots/iphone-medium.png" alt="Medium width phone dashboard" /></td>
    <td width="33%"><img src="docs/screenshots/local-engine-panel.png" alt="On-device engine test panel" /></td>
  </tr>
  <tr>
    <td align="center"><sub>Compact &mdash; single column, scrollable category chips</sub></td>
    <td align="center"><sub>Medium &mdash; stats header, category filters, cards</sub></td>
    <td align="center"><sub>On-device engine &mdash; summary + category output</sub></td>
  </tr>
</table>

### iPad

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/ipad-expanded.png" alt="Expanded iPad sidebar, grid, and detail layout" /></td>
    <td width="50%"><img src="docs/screenshots/ipad-expanded-dark.png" alt="Expanded iPad layout in dark mode" /></td>
  </tr>
  <tr>
    <td align="center"><sub>Expanded &mdash; category sidebar, card grid, detail pane</sub></td>
    <td align="center"><sub>Expanded &mdash; dark mode</sub></td>
  </tr>
</table>

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/ipad-split-view.png" alt="Compact split-view iPad layout" width="420" /></td>
  </tr>
  <tr>
    <td align="center"><sub>Compact split view &mdash; narrower iPad window with the on-device engine panel</sub></td>
  </tr>
</table>

> Screenshots are generated from the snapshot-test reference renders in
> `NotificationSummarizerTests/__Snapshots__/SnapshotTests/`, so they always match the
> committed UI baseline.

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

## watchOS

There is a native watchOS app in the same project (`NotificationSummarizerWatch`, watchOS
10+) running the same on-device engine: a feed with category filters, a capture screen
that dictates or types a notification and summarises it on the wrist, and an overview with
per-category counts.

Select the `NotificationSummarizerWatch` scheme to run it. See [docs/watchos.md](docs/watchos.md)
for the target layout, shared code, installing on hardware, and what is not in there yet.

## Important iOS limitation

A normal third-party app cannot read arbitrary notifications belonging to other apps. To process notifications from your own app, use a Notification Service Extension and an App Group for shared persistence.
