# citiride

A Flutter rider app scaffold for citiride, wired to Firebase project
`citiride-d7743` and ready for the screen mockups, fonts, and color scheme.

## What is set up

- Flutter Android and iOS project files
- Firebase packages for Auth, Firestore, Storage, Messaging, Functions, and Core
- `go_router` for screen navigation
- App-level theme placeholders in `lib/app/theme`
- Firebase startup in `lib/core/firebase`
- Generated Firebase options in `lib/firebase_options.dart`
- Android Firebase config in `android/app/google-services.json`
- Asset folders for `fonts`, `icons`, and `images`

## Run the app

```bash
flutter pub get
flutter run
```

## Email OTP (sign-up / login)

The rider app calls the hosted OTP API at `https://otp-api-production-db79.up.railway.app` by default — **no extra config needed** for release APKs.

**Important:** `CITIRIDE_OTP_API_URL` on **Railway** only affects the server repo env file; it does **not** configure the Flutter app on your phone. To point the app at a different API URL, rebuild with:

```bash
flutter build apk --release --dart-define=CITIRIDE_OTP_API_URL=https://otp-api-production-db79.up.railway.app
```

After changing OTP API code, deploy the **otp-api** service on Railway (see `services/otp-api/README.md`), then reinstall the APK if needed.

## Google Maps

Enable these APIs in Google Cloud for your key: Maps SDK for Android, Maps SDK for iOS, Maps JavaScript API, Places API, Geocoding API, and Routes API.

Run web/Chrome with:

```bash
flutter run -d chrome --dart-define=GOOGLE_MAPS_API_KEY=YOUR_GOOGLE_MAPS_API_KEY
```

Run Android with:

```bash
flutter run -d <android_device_id> --dart-define=GOOGLE_MAPS_API_KEY=YOUR_GOOGLE_MAPS_API_KEY
```

For iOS, copy `ios/Flutter/GoogleMapsSecrets.example.xcconfig` to `ios/Flutter/GoogleMapsSecrets.xcconfig`, set `GOOGLE_MAPS_API_KEY=YOUR_GOOGLE_MAPS_API_KEY`, then also run with the same `--dart-define` so Places autocomplete works in Dart.

Without the dart define, the app keeps using the SVG mock map fallback and offline Nigerian place suggestions.

## Firebase

This project is configured for:

- Firebase project ID: `citiride-d7743`
- Android package: `com.citiride.citiride`
- iOS bundle ID: `com.citiride.citiride`

The startup code in `lib/main.dart` initializes Firebase with
`DefaultFirebaseOptions.currentPlatform`.

## Next inputs needed

- Screen mockups
- Final color palette
- Font files or font family names
- Enabled Firebase products and auth methods