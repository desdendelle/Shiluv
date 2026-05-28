# Shiluv Frontend

Flutter Web draft for the Hebrew-only Shiluv UI.

## Run

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

## Build

```bash
flutter build web --release --dart-define=API_BASE_URL=https://api.example.invalid
```

The generated static site is written to `build/web`.
