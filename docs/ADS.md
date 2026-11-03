# Advertising (Google AdMob)

LocalDrop shows ads with [`google_mobile_ads`](https://pub.dev/packages/google_mobile_ads).

## Where ads appear
| Placement | Format |
|---|---|
| Home screen | Anchored adaptive banner (bottom) |
| Gallery, Uploads, Dashboard tabs | Anchored adaptive banner above the tab bar |
| After a session ends ("Back to home") or a participant leaves | Interstitial, at most once every 3 minutes |

Never shown: media viewer, join flow, QR/PIN screen, host controls, or during transfers.
The browser client served to participants contains **no ads**.

## Offline behaviour
Ads need internet. On a hotspot without mobile data nothing loads, banners take **zero space**, and the
app works exactly as before. The SDK starts after the first frame, never blocks the UI, and retries when
the app returns to the foreground (e.g. after mobile data is turned on).

## Consent
Uses Google's User Messaging Platform: the consent form appears where required (EEA/UK/Switzerland,
US state laws) once you configure "Privacy & messaging" in AdMob. Ads are only requested when
`canRequestAds()` is true. An "Ad privacy settings" link appears on Home when required.
`NSUserTrackingUsageDescription` is present for the iOS ATT prompt if you enable an IDFA message.

## Going live — replace the test IDs
Until you do, **Google test ads are shown and earn nothing.**

1. Create Android and iOS apps in AdMob; create a *Banner (adaptive)* and an *Interstitial* unit for each.
2. App IDs (format `ca-app-pub-XXXX~YYYY`):
   * Android: `flutter build apk -PadmobAppId=ca-app-pub-XXXX~YYYY` (or `admobAppId=` in `android/gradle.properties`)
   * iOS: set `GAD_APPLICATION_IDENTIFIER` in `ios/Flutter/Release.xcconfig` (and Debug if wanted)
3. Ad unit IDs (format `ca-app-pub-XXXX/ZZZZ`) via `--dart-define`:
   ```bash
   flutter build apk --release -PadmobAppId=ca-app-pub-XXXX~YYYY \
     --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-XXXX/AAAA \
     --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-XXXX/BBBB
   ```
   iOS: `ADMOB_BANNER_IOS`, `ADMOB_INTERSTITIAL_IOS`.
4. Add the full SKAdNetwork list from Google to `ios/Runner/Info.plist` (only Google's own ID is included).
5. Publish `app-ads.txt` on your developer website.
6. Store declarations: Play Console "Contains ads" = yes, Data safety (device/advertising ID, diagnostics
   collected by the ads SDK); App Store privacy labels likewise.

Turn ads off entirely with `--dart-define=ADS_ENABLED=false`.

Never click your own live ads; use test IDs or register test devices while developing.
