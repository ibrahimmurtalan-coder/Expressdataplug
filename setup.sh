#!/usr/bin/env bash
# Run once in the project folder BEFORE building (build services: add as a script step).
set -e

# Phone-friendly upload: files uploaded flat at the repo root get moved into place.
if [ -f main.dart ]; then mkdir -p lib && mv -f main.dart lib/main.dart; fi
if [ -f icon.png ]; then mkdir -p assets/icon && mv -f icon.png assets/icon/icon.png; fi
if [ -f icon_fg.png ]; then mkdir -p assets/icon && mv -f icon_fg.png assets/icon/icon_fg.png; fi
# Bundle ID / package name = com.expressdataplug.app
flutter create --org com.expressdataplug --project-name app --platforms=ios,android .
flutter pub get
dart run flutter_launcher_icons

APP_NAME="ExpressDataPlug"
if [ -f ios/Runner/Info.plist ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" ios/Runner/Info.plist 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" ios/Runner/Info.plist || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" ios/Runner/Info.plist || true
fi
sed -i.bak "s/android:label=\"[^\"]*\"/android:label=\"$APP_NAME\"/" android/app/src/main/AndroidManifest.xml

# iOS: Face ID permission text
if [ -f ios/Runner/Info.plist ]; then
  /usr/libexec/PlistBuddy -c "Add :NSFaceIDUsageDescription string 'Unlock your account'" ios/Runner/Info.plist 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :NSFaceIDUsageDescription 'Unlock your account'" ios/Runner/Info.plist || true
fi

# Android: biometric permission + FragmentActivity (required by local_auth)
M=android/app/src/main/AndroidManifest.xml
grep -q USE_BIOMETRIC "$M" || sed -i.bak 's#<application#<uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n    <uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$M"
KT=$(find android/app/src/main -name MainActivity.kt | head -1)
[ -n "$KT" ] && sed -i.bak 's/FlutterActivity/FlutterFragmentActivity/g' "$KT" && \
  sed -i.bak 's#io.flutter.embedding.android.FlutterFragmentActivity#io.flutter.embedding.android.FlutterFragmentActivity#' "$KT"
# Android: AppCompat theme needed by local_auth (fingerprint prompt)
for f in android/app/src/main/res/values/styles.xml android/app/src/main/res/values-night/styles.xml; do
  [ -f "$f" ] && { sed -i.bak 's#parent="@android:style/Theme\.[A-Za-z.]*NoTitleBar"#parent="Theme.AppCompat.DayNight.NoActionBar"#g' "$f"; rm -f "$f.bak"; }
done
echo "Setup done."
