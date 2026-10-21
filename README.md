# Account App (Flutter WebView + Face ID)

1. Site address is set in `kSiteUrl` in `lib/main.dart` (https://expressdataplug.com/account/).
2. Run `./setup.sh` (generates ios/ and android/ folders and adds Face ID permissions).
3. Build:
   - iOS:     `flutter build ipa`      (needs a Mac + Apple Developer account)
   - Android: `flutter build apk --release`

On Codemagic / similar: upload this folder, add `./setup.sh` as the first build script.
App name: ExpressDataPlug. Bundle ID / package: com.expressdataplug.app (set in setup.sh).

## Android build without a computer SDK (GitHub Actions)
Push this folder to a GitHub repo -> Actions tab -> "Build Android APK" -> Run workflow.
Download `ExpressDataPlug-apk` from the run's Artifacts and install the .apk on your phone.
