# NFC Reader & Writer

A small Flutter app that reads and writes **NFC / NDEF** tags (text or link records) on **iOS** and **Android**.
GitHub Actions builds an **unsigned IPA** (for iPhone, after signing) and an **APK** (for Android) on every push.

## Features

- Plain English UI with a Read tab and a Write tab.
- Reads every NDEF record on a tag: text, link, media, external or raw data.
- Writes a Text record or a URI record to any writable NDEF tag.
- Shows tag details: writable or read-only, capacity in bytes, written message size.
- NFC status card that distinguishes "NFC turned off", "unavailable" and "ready", and still tries a
  session so the exact CoreNFC error is shown.

## Run locally

```bash
flutter pub get
flutter run            # use a real device, the iOS Simulator has no NFC
```

Windows note: keep the project in a path with **ASCII characters only** (no Cyrillic). The Gradle
wrapper and the Dart AOT/Kotlin compilers fail on non-ASCII paths, while GitHub Actions is unaffected.

Build an unsigned iOS app on macOS:

```bash
flutter build ios --release --no-codesign
```

## Download the builds from GitHub Actions

1. Push to `main`, or open **Actions** → **Build apps (unsigned IPA + APK)** → **Run workflow**.
2. When the build finishes (about 5–10 minutes) download the files from either place:
   - **Actions** → latest run → **Artifacts** → `NFC_READ_WRITE-unsigned-ipa` and `NFC_READ_WRITE-apk`
   - or the **Releases** page: `NFC_READ_WRITE-unsigned.ipa` and `NFC_READ_WRITE.apk`
3. iPhone: sign the IPA with **Sideloadly**, **ESign**, **AltStore** or **TrollStore**.
4. Android: copy `NFC_READ_WRITE.apk` to the phone and install it (allow installs from unknown sources).

The IPA is **unsigned**, so it must be signed before iOS will install it. The APK is signed with the
debug key, which is enough for sideloading.

## Installing on iPhone

- **Sideloadly** (Windows/macOS): drop the IPA into the window, enter your Apple ID, press Start.
- **ESign / TrollStore**: open the file and choose Sign / Install.

### Important NFC note for iOS

Reading and writing NFC on iOS needs the `com.apple.developer.nfc.readersession.formats` entitlement,
which is available only to **paid Apple Developer accounts** ($99/year). When the IPA is signed with a free
Apple ID the app installs and runs, but `NFCTagReaderSession.readingAvailable` is `false` and no NFC session
can start — that is an Apple restriction, not an app bug. Sign with a profile that includes the NFC capability
and the entitlement already present in `ios/Runner/Runner.entitlements` takes effect.

## Project layout

```
lib/main.dart            App UI and NFC session handling (nfc_manager / nfc_manager_ndef)
lib/ndef_codec.dart      NDEF text and URI record encoding/decoding
test/ndef_codec_test.dart
ios/Runner/Runner.entitlements            NFC entitlement
ios/Runner/Info.plist                     NFCReaderUsageDescription
.github/workflows/build-apps.yml          Analyze/test, unsigned IPA and APK builds
```

## License

Use it however you like.
