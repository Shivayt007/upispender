# UPI Spend Tracker — Android (Flutter)

An offline-first personal expense tracker for Indian rupees (₹). Stores expenses in SQLite in app-private storage with no backend, sign-in, analytics or network permission.

## Features in v1.1

- Daily spending ring, green/amber/red progress, budget left, hourly guidance
- Quick manual payment entry, category chips, Needed/Impulse tags, edit/delete/undo
- Daily or weekday/weekend targets, 50/80/100% alerts, daily reports and spending insights
- Custom categories, payee-based category suggestion, streaks, search and budget affordability check
- **Opt-in Android SMS UPI debit detection (new in v1.1):**
  - You explicitly enable it under **Settings → Automatic UPI SMS detection**
  - Prominent explanation followed by Android \`RECEIVE_SMS\` permission
  - Captures new incoming SMS only via Android \`SMS_RECEIVED\`, including while app isn't open, subject to Android restrictions
  - Checks for UPI context, debit words and ₹/Rs/INR amounts; discards OTP, credit, refund and failed-payment messages
  - Saves **only** a candidate amount, possible payee, SMS sender label, timestamp, and SHA-256 deduplication fingerprint to a local review queue
  - Shows a generic notification on detection (notification permission required on Android 13+)
  - **Home → Review detected payments** or **Settings → Automatic UPI SMS detection → Review detected payments**
  - Choose category and **Save payment**, or **Ignore**
  - Reviewed imports are atomic and duplicate-protected by unique SQLite fingerprint; previously entered v1 transactions are preserved by database migration
  - Does not scan existing SMS inbox or read all SMS history; does not claim direct GPay, PhonePe or Paytm API access

**The app never automatically adds an SMS payment to your daily budget.** Review each detection first to avoid categorization errors, unrelated bank alerts and duplicates. Different SMS formats may be missed, and a transaction might not generate an SMS at all. The receiver runs only after opt-in, an Android permission grant and while the OS allows delivery. It cannot receive SMS if Android force-stops the application. Exact UPI fingerprint duplicates are filtered; different alerts for one payment without a shared UPI reference may still require manual deduplication.

## Build and install

1. Go to [GitHub Actions — Build Android APK](https://github.com/Shivayt007/upispender/actions/workflows/android.yml).
2. Open the latest successful workflow.
3. Under **Artifacts**, download \`UPI-Spend-Tracker-APK\`.
4. Unzip, then open \`app-release.apk\` to install on Android.
5. Open **Settings → Automatic UPI SMS detection**, read the disclosure, enable the toggle, grant SMS and notification permission, and make a **real test UPI transaction** that causes a bank SMS.
6. Open **Detected UPI payments**, review and save the transaction. Verify the result against your bank app.

Android application ID: \`com.upispender.upispender\`.

### Installing over previous testing APKs

The GitHub Actions build uses Flutter's ephemeral debug signing key to make an installable test APK. Since the signing key may differ across workflow runners, Android **may reject installing a new build over an old one**. Do not uninstall an earlier copy that contains important spending data without a reliable backup. **v1.1 currently has no export/backup UI.** For reliable future updates, configure a persistent, privately held release keystore using GitHub Actions secrets. The test APK is not production-signed or approved for Google Play.

## Local build

\`\`\`bash
flutter create --platforms=android --org com.upispender --project-name upispender .
python3 tool/configure_android.py
flutter pub get
flutter test
flutter build apk --release
\`\`\`

The Android receiver lives in \`android/app/src/main/kotlin/com/upispender/upispender/\`. Never add READ_SMS permissions unless implementing a separately disclosed historical import capability.

## Privacy and policy

The app requests RECEIVE_SMS for incoming debit alerts only, not READ_SMS. It uses POST_NOTIFICATIONS for alert/reminder notifications. Raw SMS, OTPs, full bank account details and messages rejected by filters are **not persisted, logged, exported or uploaded**. The pending queue and deduplication history are private local app preferences. Confirmed expenses are in SQLite. The manifest disables Android Auto Backup.

SMS and Call Log permissions are restricted on Google Play. A money-management/budgeting app **may apply for a policy exception** but approval is not guaranteed. Before any Play Store release, follow Google Play's permission declaration, privacy policy, prominent disclosure and consent rules. This source build is for direct Android testing. See:
- https://support.google.com/googleplay/android-developer/answer/10208820
- https://developer.android.com/reference/android/provider/Telephony.Sms.Intents

## Roadmap

- Statement CSV/PDF imports, charts, category budgets, widgets, exports and local backup
- Recurring payments, rollover, salary cycle and unusual-spending analysis
- Biometric/PIN app lock, Hindi and customizable notification quiet hours
