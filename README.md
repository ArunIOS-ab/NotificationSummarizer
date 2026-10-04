# NotificationSummarizer — iOS 17+ / watchOS 10+

This is a native SwiftUI/SwiftData/App Intents/Core ML project. It is intentionally runnable **without** the Core ML model: until `NotificationClassifier.mlpackage` and its matching `vocab.txt` are added, the app uses the local deterministic fallback classifier/summarizer.

Ships two apps in one project, sharing the same on-device engine: an iOS app and a
watchOS app.

## Screenshots

Every notification is classified into one of six categories and summarised on-device. On
iOS that lands in an adaptive dashboard that re-flows from a single-column phone list to an
iPad sidebar/grid/detail layout; on Apple Watch it becomes a glanceable feed, a dictate-to-
summarise capture screen, and a per-category overview.

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

<table>
  <tr>
    <td width="33%"><img src="docs/screenshots-watch/feed.png" alt="Watch feed with category filter and notification rows" /></td>
    <td width="33%"><img src="docs/screenshots-watch/capture.png" alt="Watch capture screen with text field and summarise button" /></td>
    <td width="33%"><img src="docs/screenshots-watch/overview.png" alt="Watch overview with totals and category breakdown" /></td>
  </tr>
  <tr>
    <td align="center"><sub>Feed &mdash; filter, swipe to mark read or delete</sub></td>
    <td align="center"><sub>Capture &mdash; dictate or type, summarised on device</sub></td>
    <td align="center"><sub>Overview &mdash; totals and per-category counts</sub></td>
  </tr>
</table>

Captured on an Apple Watch Series 11 (46mm) simulator, watchOS 26.5.

Select the `NotificationSummarizerWatch` scheme to run it. See [docs/watchos.md](docs/watchos.md)
for the target layout, shared code, installing on hardware, and what is not in there yet.

## Important iOS limitation

A normal third-party app cannot read arbitrary notifications belonging to other apps. To process notifications from your own app, use a Notification Service Extension and an App Group for shared persistence.
