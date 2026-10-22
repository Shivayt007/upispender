# UPI Spend Tracker

An offline-first Android spending tracker built with Flutter. **Your transaction data remains on your Android device in SQLite.** No cloud login, advertising SDK, backend, or server is needed.

## Implemented in v1

- Dashboard progress ring with green/amber/red target status, today's total, budget remaining and safe hourly allowance
- Quick-add keypad with amount, category and Save. Optional payee, note, Needed/Impulse tag and time
- Add, edit, delete and undo local payments
- Default budget and alternate weekday/weekend daily limits
- Budget threshold alerts (50%, 80%, 100%) when adding expenses
- Daily local report notification (9 PM by default, adjustable in Settings)
- Daily report: total, transaction count, target comparison, top category and payee, Needed/Impulse spending and rule-based insight
- History search by payee/note, filter by category and Needed/Impulse
- Category auto-suggestion based on previously saved payees, custom category colors
- Under-budget streak and monthly target savings, 7-day milestone and no-spend challenge
- "Can I afford this?" preview
- Light/dark mode, hidden amounts, notification preferences, local data deletion

## How to get the Android APK

1. Open [GitHub Actions](https://github.com/Shivayt007/upispender/actions/workflows/android.yml).
2. Select a successful **Build Android APK** run.
3. Download artifact **UPI-Spend-Tracker-APK**, extract the ZIP, and install \`app-release.apk\` on Android.

The Actions workflow automatically sets up Flutter, generates the standard Android project, patches the notification Gradle configuration, runs static analysis and tests, builds the APK and uploads the build artifact. You **do not** need a VPS or EasyPanel deployment.

Local development:
\`\`\`sh
flutter create --platforms=android --org com.upispender --project-name upispender .
python3 tool/configure_android.py
flutter pub get
flutter test
flutter run
\`\`\`

Android application ID: \`com.upispender.upispender\`.

### Signing/distribution

The sample Flutter Android build setup signs a sideload APK using the default **debug keystore** in release mode for testing. This is **not a Play Store-ready, production-signed release**. To publish to Google Play, create a private signing key and configure a secure upload-key-based app bundle release; never commit private keys to the repo.

## Permissions and privacy

v1 requests Android notification permission to show budget and daily-report reminders. **No SMS, accessibility, payment-app, storage, network or banking permissions are requested.** Transactions are stored locally and never transmitted to a backend. Uninstalling clears app-private data unless restored from an Android system backup.

Scheduled reports use inexact alarms, so system battery policies may delay them. Daily reports are calculated in-app when opened; a notification reminds you to open them. Optional evening check-in is a fixed reminder, not a background check that nothing was logged.

## Staged roadmap (not implemented yet)

- **v2:** opt-in SMS debit parsing, duplicate-safe CSV/PDF statement import, weekly/monthly reporting, category limits, CSV/PDF/image export, Android home widget
- **v3:** rollover, weekly bonus allocation, salary-cycle mode, 30-day suggested limit, unusual-spend alerts, recurring rent/EMI/subscription due-date tracking
- **Future privacy:** PIN/biometric lock, Hindi localization, local file backup and restore, customizable quiet hours

The v2+ items above are roadmap only. GPay, PhonePe and Paytm do not provide a general transaction sync API; future import and SMS capture must not claim official integrations or read OTPs.
