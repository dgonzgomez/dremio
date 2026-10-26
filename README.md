# Dremio

Dremio for Mac, Windows and Fire TV / Android TV, built with Flutter.

## Requirements (all platforms)

- [Flutter](https://docs.flutter.dev/get-started/install) stable, 3.44 or newer (Dart 3.12+). Check with `flutter --version`.
- Run `flutter pub get` once in this folder before your first build.
- `flutter doctor` lists anything missing for the platform you're building.

Each platform has to be built on its own OS: Windows apps on Windows, Mac apps on a Mac. Android builds work from either.

## Mac

Needs a Mac with Apple Silicon, [Xcode](https://apps.apple.com/app/xcode/id497799835) (open it once to accept the license) and CocoaPods (`brew install cocoapods`).

```sh
tool/build_macos.sh
```

This builds a release app, strips the Intel code from the bundled video player to keep it small, signs it ad hoc and zips it:

- App: `build/macos/Build/Products/Release/Dremio.app`
- Zip to share: `build/Dremio-macos.zip`

The app isn't notarized, so on another Mac the first launch needs a right-click on Dremio.app, then **Open**. If macOS says the app is damaged, run `xattr -dr com.apple.quarantine /path/to/Dremio.app`.

For a quick development run: `flutter run -d macos`.

## Windows

Needs Windows 10 or 11 (x64) and [Visual Studio 2022](https://visualstudio.microsoft.com/vs/community/) with the **Desktop development with C++** workload. (This is Visual Studio itself, not VS Code.)

```powershell
flutter build windows --release
```

The app is the whole folder `build\windows\x64\runner\Release\`. Run `Dremio.exe` from it. To share it, zip the entire folder, because the exe needs the DLLs and `data` folder next to it:

```powershell
Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath Dremio-windows-x64.zip
```

Windows SmartScreen will warn on first launch because the app isn't code-signed. Click **More info**, then **Run anyway**.

For a quick development run: `flutter run -d windows`.

### Without a Windows PC

`.github/workflows/release.yml` builds the Windows zip, the Mac zip and the Android APK on GitHub's servers whenever `main` is pushed (or from **Actions → Release → Run workflow**). Download them from the run's **Artifacts** section.

## Releases

Releases publish themselves. When `main` is pushed with a `version` in `pubspec.yaml` that has no release yet, the workflow creates release `v<version>` with all three downloads attached, using that version's section under **What's new** below as the release notes. To ship a release:

1. Bump `version` in `pubspec.yaml` (for example `0.4.0+4` to `0.5.0+5`).
2. Add a `### 0.5.0` section under **What's new**.
3. Push to `main`.

The Android APK is only attached when the repository has an `ANDROID_DEBUG_KEYSTORE` secret (the base64 of `~/.android/debug.keystore` from the computer that built the copy already on the TV). Without the same key, the in-app update can't replace the installed app.

## Android / Fire TV

Needs JDK 17 and the Android SDK. Installing [Android Studio](https://developer.android.com/studio) provides both. Without Android Studio, set `JAVA_HOME` to a JDK 17 and `ANDROID_HOME` to the SDK, and run `flutter config --android-sdk <path>`.

```sh
flutter build apk --release --target-platform android-arm
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.

`android-arm` targets 32-bit ARM, which is what Fire TV Sticks and most TVs run, and keeps the APK smaller. For phones or newer 64-bit devices, drop `--target-platform` to build one APK that runs everywhere.

The app installs as **Dremio** (`dev.dremio.flutter`).

### Installing on a Fire TV

1. On the TV: **Settings → My Fire TV → Developer options**, turn on **ADB debugging** (and **Apps from Unknown Sources**). If Developer options is hidden, open **About** and press Select on the device name seven times.
2. Find the TV's IP address under **Settings → My Fire TV → About → Network**.
3. From the computer, using `adb` (included in the Android SDK's `platform-tools`):

   ```sh
   adb connect <tv-ip>:5555
   adb install -r build/app/outputs/flutter-apk/app-release.apk
   ```

   Approve the debugging prompt on the TV the first time. **Dremio** then appears in Apps.

### Signing

Release APKs are currently signed with the Android debug key. That's fine for sideloading, but an update has to be signed with the same key, so building on a different computer means uninstalling the old copy first. Before publishing to a store, add a real signing config in `android/app/build.gradle.kts`.

## Low disk space

Builds need several GB of temporary space (Gradle and Xcode caches). If a build fails with "Insufficient space" or "No space left on device", `flutter clean` clears this project's build output.

## What's new

### 0.6.2

- Letterboxd: link your account in Settings by username (your diary must be public). Your avatar and name sit under the logo in the sidebar and open your History: what you've played in Dremio, your Letterboxd diary and your favorites.
- Orbit, a new tab under Home: what your friends have been watching, with their ratings on the posters, and a blend with each friend (a match score, films they loved that you haven't seen, and films you both loved), based on each person's last 50 diary entries. Import who you follow on Letterboxd or add friends by username.
- Log on Letterboxd: movie pages have a button for it, and finishing a movie offers to log and rate it. On Mac and Windows it opens in your browser; on Fire TV it shows a QR code to scan with your phone.

### 0.6.1

- Fire TV: the left sidebar replaces the top bar. Press Left from the start of a row to open it; Lookback works with the remote too.
- Player: a "Buffering…" spinner shows while a big file is still loading.
- Data Saver (Settings, under HDR): prefers files under 7 GB so playback starts faster, using bigger ones only when nothing smaller plays.
- Android updates: the download is checked for completeness and the right signing key before installing, with a clear message if something's wrong.
- Windows updates: Dremio only closes once the updater has actually started, so a blocked updater no longer leaves it closed. Unpacking is faster too.

### 0.6.0

- Mac and Windows: a new left sidebar with the logo at the top, the tabs in the middle and Settings at the bottom. It slides out on hover, and hovering an item shines a UFO-style spotlight on it.
- Lookback: pick a decade from the 1940s to the 2010s to get a home page of that decade's popular movies, with banners, the best of the decade, highest rated, top genres and a row for each year. Rows avoid repeating each other, the order reshuffles daily, and decades preload in the background so they open instantly.

### 0.5.6

- Windows: Alt+Enter is handled by the window itself, so it always toggles full screen, never presses the selected button, and doesn't play the error sound.
- Windows updates: Dremio checks it can write to its folder before closing, retries files Windows still has locked, always reopens afterwards, and explains in Settings if an update didn't finish.

### 0.5.5

- Mac and Windows: the window scales to the display, reading the usable screen area with display scaling (e.g. 125%) applied. Screens too small for 1440x900 open maximized; larger ones get about 75% of the screen.
- Windows: Alt+Enter no longer plays the error sound.

### 0.5.4

- Recommendations stay fresh when the app is left open: catalogs are rechecked when Dremio comes back to the foreground and hourly while idle, and Home picks up the daily reshuffle.

### 0.5.3

- Mac and Windows: the window opens sized to fit the screen, including with display scaling, so the title bar and its buttons stay reachable.

### 0.5.2

- Alt+Enter toggles full screen anywhere on Mac and Windows, without also pressing the selected button.
- Fire TV player: Back hides the controls when they're showing and only leaves the video when they're hidden.
- Player controls hide after 10 seconds without input, even when paused.
- Fire TV player: Down on the bottom row of controls stays there, and the volume slider is hidden (the remote has its own volume buttons).

### 0.5.1

- Settings: navigating back up from the bottom of the page reaches the top again.
- Player: only the progress bar's dot highlights when it's selected.

### 0.5.0

- Multiple sources: connect Debridio, Torrentio and Comet in Settings and choose which one is the default. Other connected sources are tried when the default has nothing playable.
- HDR setting under Resolution: turn it off to skip HDR and Dolby Vision streams.

### 0.4.0

- Resolved Fire TV bug fixes: remote navigation back to the top of the screen and through the player controls, plus faster artwork loading with less memory use.
- Implemented an episode view: Continue Watching shows each show's current episode and progress, and opens straight to that episode.

### 0.3.0

- Update button in Settings that checks GitHub releases and installs the new version.
- Volume slider, scroll-wheel volume, online subtitles when a source has none.
