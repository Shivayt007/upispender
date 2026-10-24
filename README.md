# Jarvis Voice Assistant (Android)

**Separate experimental Kotlin Android app**; package `com.shivay.jarvisvoice`. This project is independent of the UPI Spend Tracker source code. It uses a persistent, user-started microphone foreground service for an *experimental* screen-off command mode; it is **not a guaranteed hardware wake-word assistant**.

## Features included
- Reads notification previews from selected WhatsApp, Telegram, Instagram, and SMS apps with English TTS; user grants Notification Access in Android Settings.
- Opt-in **Start hands-free** mode with an ongoing microphone disclosure notification. Say **"Hey Jarvis, wake up"**, then **"Call Rahul"** or **"Call that person"** (refers to the last readable message sender).
- Matches saved contacts, asks **"Call Rahul? Say yes or no"**, and calls via Android `TelecomManager.placeCall` using `CALL_PHONE` permission.
- Toggle individual source apps. No server or message uploads. No conversation history saved; only last sender may be remembered locally for the command.
- Stop listening from the app or the ongoing notification. English TTS and English speech recognition.

## How to use
1. Install debug APK; open it **once** to set permissions.
2. Grant **Notification Access**, **Microphone**, **Contacts**, **Phone** and (Android 13+) **Notifications**.
3. In the app, enable the desired messenger sources and tap **Start hands-free** while app is open.
4. Say **Hey Jarvis, wake up**, then **Call Rahul**. Reply **yes** or **no** when asked.
5. A normal SIM call uses the phone's default calling account. On some dual-SIM devices the system asks which SIM to use.
6. Tap **Stop hands-free** or use the notification's **Stop** action to turn the microphone off.

## What it cannot guarantee
- Android's `SpeechRecognizer` is **not designed for perpetual hotword recognition**. This implementation restarts finite recognition sessions and may stop on screen-off, network loss, battery management, other audio use, or vendor restrictions. It may consume significant battery. For a true production lock-screen assistant, replace it with a validated on-device wake-word engine or supported default-assistant implementation, subject to OEM support.
- Phone calls initiated while locked are device/policy dependent. Confirm with real hardware before relying on hands-free calling.
- Contact names in chat notifications may differ from names in Contacts; ambiguous matches do not call.
- If the messenger hides notification previews, Jarvis cannot read or recover the hidden message. Calls from unknown numbers or via WhatsApp are **not supported**.
- Voice confirmation alone does **not authenticate a speaker**; other people nearby might issue the command. Only enable hands-free mode when safe.
- Speech recognition may use the phone's installed recognition provider and the internet. `EXTRA_PREFER_OFFLINE` is a hint, not a guarantee of offline transcription.

## Build debug APK
CI workflow `.github/workflows/android-apk.yml` builds on commits to `jarvis-voice-assistant` and uploads `jarvis-debug-apk` as an Actions artifact. The repo's **Actions** tab provides the APK ZIP if GitHub Actions is enabled.

Locally, install JDK 17, Android SDK platform 35 and build-tools 35.0.0, and Gradle 8.11.1, then run:

```sh
gradle :app:assembleDebug
```

APK: `app/build/outputs/apk/debug/app-debug.apk`.

## Privacy
Notification content is processed in-memory for voice playback; no online backend or advertising SDK is included. Users can disable notifications per app and stop microphone listening any time. Check local laws and obtain consent before voice/phone automation.
