# Stay – Dog Separation Coach

A home-alone coach for dogs with separation anxiety. A spare iPhone or iPad becomes the **dog camera** (Camera mode); your own phone is **Owner mode**. Stay runs the graduated-absence protocol used by separation anxiety trainers: a short baseline, then daily missions that grow 10–20 % after calm sessions and step back after owner-confirmed distress, with departure-cue practice and rest days.

SwiftUI · iOS 17+ · Swift 6 · no third-party dependencies · no backend · no account.

---

## Run it

1. Open `Stay.xcodeproj` in Xcode 26 or later (built and tested with Xcode 27).
2. Select the **Stay** scheme and an iPhone simulator, then Run. The scheme uses `Stay.storekit`, so purchases work locally without App Store Connect.
3. Tests: **Product › Test** (or `xcodebuild -project Stay.xcodeproj -scheme Stay -destination 'platform=iOS Simulator,name=iPhone 17' test`).

To try the full two-device flow, run on two real devices signed into iCloud (one picks “This is my phone”, the other “This is the dog camera”, then pair with the QR code from Settings › Dog camera). The simulator has no camera, so Camera mode there only runs sound detection.

App icon source: `swift scripts/make_icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png 1024`.

### Before you ship: one place to change

`Config/Shared.xcconfig`

| Setting | Example | Derives |
|---|---|---|
| `STAY_BUNDLE_PREFIX` | `com.acme` | app `com.acme.stay`, widget `com.acme.stay.widgets`, App Group `group.com.acme.stay`, iCloud container `iCloud.com.acme.stay` |
| `STAY_TEAM_ID` | `ABCDE12345` | signing team for all targets |

`App/Core/AppConfig.swift` — `supportEmail` and `websiteURL` (privacy/terms/support links). Also replace `support@example.com` in `website/*.html`.

> The StoreKit product IDs (`com.stay.pro.monthly`, `com.stay.pro.yearly`, `com.stay.pro.lifetime`) are fixed strings in `PurchaseManager.ProductID` and `Stay.storekit`. Product IDs must be unique across the App Store; if `com.stay.*` is taken, change them in both places (e.g. `com.acme.stay.pro.monthly`).

---

## Architecture

```
App/
  StayApp.swift            App entry, AppDelegate (remote notifications for CloudKit pushes)
  Core/                    AppModel (root @Observable state), RootView, MissionCopy, AppConfig
  Models/                  Dog, Session, Severity questionnaire, Journal, Preferences/StayDatabase
  Engine/                  MissionEngine (pure, unit-tested), ProgressStats, FreeTier
  Detection/               DistressAggregator, PacingAnalyzer, LevelTimeline (pure, unit-tested)
  Camera/                  DetectionPipeline (AVCapture + AVAudioEngine + SoundAnalysis + Vision), CameraController
  Link/                    NearbyLink (MultipeerConnectivity), CloudRelay (CloudKit), LinkMessages, PairingPayload
  Services/                PurchaseManager (StoreKit 2), NotificationScheduler, LiveActivityController, Coach
  Persistence/             DataStore (JSON document + media files in Application Support)
  DesignSystem/            Typography scale, cards, buttons, haptics, rings, sparkline
  Features/                Onboarding, Today, Mission (brief/run/review/result), CameraMode, Pairing,
                           Progress, Share (cards + video), Report (PDF), Coach, Settings, Paywall, Dogs
Shared/                    Compiled into app + widget: palette, StayMark, DurationText, WidgetSnapshot, Live Activity attributes
Widgets/                   Home/Lock Screen widget, Live Activity + Dynamic Island
Tests/                     Engine, detection, progress, pairing, persistence, end-to-end review flow, coach
website/                   Static marketing site + privacy, terms, support (GitHub Pages ready)
```

### Data flow

- **Single source of truth:** `AppModel.db` (`StayDatabase`, Codable) saved as `Application Support/Stay/stay.json`. Photos and snapshots are JPEGs in `Media/`. The widget only reads a small `WidgetSnapshot` written to the App Group.
- **Mission engine:** `MissionEngine` is a deterministic value type. `AppModel.finishReview` turns a reviewed session into a `SessionOutcome` (calm / distress at first confirmed sign / incomplete) and applies it. Unchecked detections are treated as dismissed, so the plan only moves on confirmed data.
- **Detection (camera device):** `SNClassifySoundRequest(.version1)` scores `dog_bark`, `dog_bow_wow`, `dog_howl`, `dog_whimper`, `dog_growl` and `dog`; `DistressAggregator` ignores single woofs and emits one event per sustained episode, with a cooldown. `VNDetectAnimalBodyPoseRequest` (falling back to `VNRecognizeAnimalsRequest`) gives the dog's position twice a second; `PacingAnalyzer` looks for back-and-forth travel. Sensitivity presets live in `DetectionParameters`.
- **Owner ⇄ camera link:**
  - *Same Wi-Fi:* MultipeerConnectivity (encrypted), matched by an 8-character link code. Carries start/stop, status, events and ~4 fps JPEG frames (real live view).
  - *Away from home (Pro):* CloudKit, no server of ours. The owner creates zone `StayLink-<code>` in their **private database** plus a zone-wide `CKShare`. The QR code contains the link code and share URL. If the camera uses the **same Apple Account**, it writes straight to the private zone; otherwise it accepts the share and writes via the **shared database**. Records: `LinkControl/control` (owner commands, polled by the camera every 3 s), `LinkStatus/status` (heartbeat every 10 s), `LinkSnapshot/snapshot` (every 5 s), `DistressEvent/<uuid>`. A `CKQuerySubscription` on `DistressEvent` creation pushes an alert to the owner even when Stay is closed; the owner then pulls zone changes and deletes processed events.
- **Coach:** `CoachService` uses Apple Foundation Models (`SystemLanguageModel`, iOS 26+, when Apple Intelligence is available) with guard-railed instructions (no cure claims, no medication, suggest a vet). `RulesCoach` is the deterministic fallback and also feeds the model its facts.
- **Sharing:** share cards are SwiftUI views rendered with `ImageRenderer` at 1080×1350. The “Day 1 vs Day N” video is rendered frame by frame (`ProgressVideoFrame`) into H.264 via `AVAssetWriter`, 1080×1920, 9 s. The last camera frame of every monitored session is saved for these.
- **Trainer report:** multi-page US Letter PDF rendered from SwiftUI pages (`TrainerReport`), previewed with PDFKit.

### Free vs Pro

Free: baseline, 3 monitored missions, live view on Wi-Fi, cue practice, progress charts, share cards and video, daily coach tip.
Pro: unlimited missions, iCloud alerts + near-live view away from home, weekly insights, trainer/vet PDF, multiple dogs. Rules in `FreeTier` (unit-tested).

---

## App Store Connect checklist

### Identifiers & capabilities (developer.apple.com › Identifiers)
- [ ] App ID `<prefix>.stay` with: **iCloud** (CloudKit, container `iCloud.<prefix>.stay`), **Push Notifications**, **App Groups** (`group.<prefix>.stay`).
- [ ] App ID `<prefix>.stay.widgets` with **App Groups** (`group.<prefix>.stay`).
- [ ] Create the iCloud container and the App Group.
- [ ] In Xcode, check Signing & Capabilities for both targets shows those capabilities; Background Modes › **Remote notifications** is already set in `Support/Stay-Info.plist`.
- [ ] Change `aps-environment` in `Support/Stay.entitlements` to `production` for release builds (Xcode does this automatically when archiving with automatic signing).

### CloudKit (CloudKit Console)
- [ ] Run the app once in Development on a device signed into iCloud (pair a camera and run one mission) so the schema is created: record types `LinkControl`, `LinkStatus`, `LinkSnapshot`, `DistressEvent`.
- [ ] **Deploy Schema Changes to Production** before submitting. No custom indexes are required (Stay uses zone changes and record IDs, not queries).

### Products (App Store Connect › Monetization)
- [ ] Subscription group **Stay Pro**:
  - `com.stay.pro.yearly` — 1 year, $59.99, introductory offer: free trial 1 week (new subscribers). Level 1.
  - `com.stay.pro.monthly` — 1 month, $9.99. Level 2.
- [ ] Non-consumable `com.stay.pro.lifetime` — $129.99.
- [ ] Turn on Family Sharing for all three (matches the .storekit file), add display names/descriptions and a review screenshot of the paywall.
- [ ] Paste the Terms of Use (or the standard EULA link) and Privacy Policy URL in App Information.

### App information
- **Name:** Stay: Dog Separation Coach
- **Subtitle:** Calm home-alone training
- **Category:** Lifestyle (secondary: Health & Fitness is *not* recommended — keep it Lifestyle to avoid medical framing)
- **Age rating:** 4+ (no objectionable content; answer “None” throughout. No unrestricted web access, no user-generated content shared publicly).
- **Keywords (100 chars):** `separation anxiety,dog,puppy,home alone,training,pet camera,barking,crate,trainer,calm,leave,alone`
- **Promotional text:** Help your dog feel safe home alone with calm daily missions, on-device bark detection and gentle alerts.
- **Description:**

  > Stay is a gentle, step-by-step coach for dogs who struggle to be home alone.
  >
  > Based on the graduated-absence method used by separation anxiety trainers, Stay starts with a short baseline and builds daily missions at your dog's pace — a little longer after every calm session, a small step back after a hard one. Quick departure-cue practice (keys, shoes, the door) and built-in rest days help progress stick.
  >
  > TURN A SPARE iPHONE INTO A DOG CAMERA
  > • Listens for barking, howling and whining with Apple's on-device sound analysis
  > • Notices pacing with on-device vision
  > • Live view on your home Wi-Fi; alerts and a near-live view while you're out, through your own iCloud
  > • Nothing is recorded continuously and no audio is uploaded
  >
  > YOU STAY IN CHARGE
  > Confirm or dismiss every detected moment. The plan only changes on what you confirm.
  >
  > SEE AND SHARE PROGRESS
  > • Charts of time alone, streaks and milestones
  > • A Live Activity with your mission timer, plus Home and Lock Screen widgets
  > • Beautiful progress cards and an automatic "Day 1 vs today" video
  > • A PDF report for your trainer or vet
  > • Daily tips and weekly insights, written on your iPhone with Apple Intelligence where available
  >
  > No account. No ads. No tracking.
  >
  > Free: baseline test, 3 monitored missions and live view on Wi-Fi. Stay Pro unlocks unlimited missions, alerts away from home, weekly insights, reports and multiple dogs. Monthly $9.99, yearly $59.99 with a 7-day free trial, or lifetime $129.99. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period.
  >
  > Stay is training support, not veterinary care. If your dog is very distressed or has hurt themselves, please talk to your vet.
  >
  > Terms: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

- **Support URL:** `<your site>/support.html` · **Marketing URL:** `<your site>/` · **Privacy Policy URL:** `<your site>/privacy.html`

### App Privacy (nutrition label)
- **Data collection:** “**No, we do not collect data from this app.**” Rationale: all data stays on device or in the user's own iCloud private/shared database, which Apple does not treat as developer collection; there are no analytics, ads or third-party SDKs; the on-device model sends nothing off device.
- **Tracking:** No. `PrivacyInfo.xcprivacy` declares no tracking, no collected data, and required-reason APIs (UserDefaults CA92.1, file timestamps C617.1).
- **Export compliance:** `ITSAppUsesNonExemptEncryption = NO` (only Apple-provided encryption).

### App Review notes (paste into “Notes”)
> Stay works fully without an account. To review the camera features you need two devices: on device A choose “This is my phone”, finish onboarding, then open Settings › Dog camera to show a QR code. On device B choose “This is the dog camera”, scan the code, tap “Arm camera”. Start a mission on device A; device B begins monitoring. Barking near device B triggers an alert on A. With a single device, choose “This is my phone” and start a mission without a camera; you can mark signs manually and review the session. The camera only runs while Camera mode is on screen (no background camera use). Purchases can be tested in the sandbox; Restore is in Settings and on the paywall.

### Screenshot shot list (6.9" and 13" iPad)
1. **Today** — hero mission card “Leave for 3 min 20 s” with dog photo, streak and coach tip. Caption: *Small calm steps, every day.*
2. **Mission running** — progress ring, live view of a sleeping dog, “All calm so far”. Caption: *See your dog while you're out.*
3. **Alert + review** — detected “Barking” moment with snapshot, Stress / Not stress toggles. Caption: *You confirm what really happened.*
4. **Progress** — trend chart, longest calm, milestones shelf. Caption: *Watch calm grow.*
5. **Share card** — “Day 1 vs Day 24”. Caption: *Celebrate every milestone.*
6. **Camera mode** — dimmed monitoring screen with breathing mark. Caption: *Turn a spare iPhone into a dog camera.*
7. **Lock Screen** — Live Activity with timer + Dynamic Island. Caption: *Your mission timer, always in view.*
8. **Coach** — weekly insight. Caption: *Personal coaching, private on your iPhone.*

### Final checks
- [ ] Replace `support@example.com` (AppConfig + website) and deploy `website/` (GitHub Pages: Settings › Pages › deploy from branch, folder `/website`, or copy it to a `gh-pages` branch). Update `AppConfig.websiteURL`.
- [ ] Archive with Release configuration, upload, and test with TestFlight on two devices (Wi-Fi and cellular away-from-home alert).
- [ ] Verify the yearly trial shows in the sandbox paywall and that Restore works.

---

## Known limitations

- iOS doesn't allow camera capture in the background, so the camera device must stay on screen (Stay suggests Guided Access).
- CloudKit push delivery is best-effort; Stay also polls every 4 s while a mission screen is open.
- The built-in sound classifier is general-purpose; sensitivity presets and owner review compensate for false alarms.
