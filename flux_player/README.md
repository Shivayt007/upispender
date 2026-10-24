# Flux Download & Play (Android, Flutter + Kotlin)

This standalone Android app lives in `flux_player/` in the `feature/flux-download-player` branch of the existing `upispender` repository. It does **not** replace the UPI expense tracker.

## Implemented

- Direct HTTP/HTTPS downloads started by pasting a URL.
- Up to 16 parallel HTTP byte-range transfers when the server answers with valid `206 Partial Content` and `Content-Range`; one connection otherwise.
- Native Kotlin foreground service so downloads can run while the Flutter activity is in the background (subject to Android's foreground service policy).
- Pause / resume / retry, saved task progress and per-part checkpoint files; adaptive resume on restart with a matching ETag or length.
- Download progress, per-file actions and completed-file playback from app-specific external storage.
- Stream a URL without downloading, with an embedded MediaKit video player.
- Audio-language and subtitle-track selection when the source provides tracks, external audio/subtitle URI entry, pause/play, 10-second seeking, scrubbing, playback speed, fit/fill, full-screen landscape, double-tap seeking, screen brightness on left-side vertical swipe and Android media volume on right-side vertical swipe.
- Release APK workflow with separate arm64, armeabi-v7a and x86_64 APK artifacts.

## Important limits

- Not MX Player's proprietary implementation. Codec support depends on MediaKit/libmpv and the device.
- The downloader handles *direct files*, not torrent, DRM, YouTube extraction, HLS offline packing or DASH offline packaging. Streaming playback of HLS/DASH may work where supported by libmpv.
- Large downloads temporarily require space for both the range-part files and the merged output.
- Files are placed in the app's external-files directory (`Android/data/dev.flux.flux_player/files/FluxDownloads`), **not** public Downloads. Uninstalling the app can delete these files. Public storage export via SAF/MediaStore is future work.
- Android may restrict background execution/foreground service time, particularly on newer Android releases. Notification permission should be granted.
- Cancel deletes task metadata and temporary parts; completed local files stay in the app folder.
- DRM bypass, track-sync adjustment, PIP, Chromecast, equalizer and folder-library scanning are **not** implemented.
- Release APKs use Flutter's default development signing configuration, **not** a stable Play Store distribution key. Install for testing only.

## Build locally

```bash
cd flux_player
flutter create --platforms android --org dev.flux --project-name flux_player .
flutter pub get
flutter analyze
flutter build apk --release --split-per-abi
```

## CI artifact

Open GitHub Actions → **Flux Android APK** → latest successful run → **Flux-Download-Player-APK**. Extract ZIP and choose `app-arm64-v8a-release.apk` for modern Android/Redmi arm64 phones.

## Dependencies

Uses `media_kit`, `media_kit_video`, `media_kit_libs_video` and Android's built-in HTTP networking, foreground service, native brightness/volume APIs.
