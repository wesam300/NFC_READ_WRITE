# NFC Reader & Writer

A small Flutter app that reads and writes **NFC / NDEF** tags (text or link records) on **iOS** and **Android**.
GitHub Actions builds an **unsigned IPA** on every push, ready to be signed with any sideloading tool and installed on an iPhone.

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

Build an unsigned iOS app on macOS:

```bash
flutter build ios --release --no-codesign
```

## Download the IPA from GitHub Actions

1. Push to `main`, or open **Actions** → **Build iOS IPA (unsigned)** → **Run workflow**.
2. When the build finishes (about 5–10 minutes) download the file from either place:
   - **Actions** → latest run → **Artifacts** → `NFC_READ_WRITE-unsigned-ipa`
   - or the **Releases** page: `NFC_READ_WRITE-unsigned.ipa`
3. Sign and install it with **Sideloadly**, **ESign**, **AltStore** or **TrollStore**.

The artifact is **unsigned**, so it must be signed before iOS will install it.

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
.github/workflows/ios-unsigned-ipa.yml    Unsigned IPA build
```

## License

Use it however you like.
