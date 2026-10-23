# UPI Spend Tracker — v1.2 (Android / Flutter)

Offline-first personal UPI and cash expense tracking with all amounts in Indian rupees. All spending history, category limits, charts and warning rules are kept **on the device**; no server or bank login is required.

## New in v1.2 — first-time user guide

### 1. Category budgets (Budget tab)
Open **Budget → Category budgets**. Tap *Set limit* beside a category. Example: set **Food ₹300 per day** and **Travel ₹200 per day**. Category spending is calculated from payments saved to that category and the bar shows the amount used today. Orange shows 80% or more; red means the limit is exceeded. Tap the category to change or remove its limit. Each category budget resets with the local calendar day, and does not replace your overall daily target. A category without a set limit has no restriction. These are advisory limits, not bank/card payment blockers.

### 2. Weekly and monthly charts (Reports tab)
Tap **Reports → Weekly** or **Monthly**. The bar chart shows each day's saved expenses, and the category section shows where money went. Swipe the chart horizontally for longer months. Use the left/right arrows to inspect older weeks or months. A week is Monday–Sunday; months use real calendar boundaries. The comparison shows the recorded spending relative to the previous complete week/month; a current in-progress period naturally has fewer elapsed days. No-data days are shown as days with no records, not assumed to be within budget.

### 3. Small-spending tracker (Home or Reports tab)
Tap **Home → Small spends under ₹100** or **Reports → Small-spending tracker**. Choose Today, Week or Month to see how many purchases were *strictly below ₹100*, their combined total, and their share of all spending. A purchase of exactly ₹100 does not count, while ₹99.99 does.

### 4. Spending calendar (Reports tab)
Open **Reports → Spending calendar**. Green dots are days with recorded expenses at or below the daily target; red means a recorded day exceeded the target; grey means no spending was logged. Tap a date to view that day's saved payments. Calendar arrows navigate months; future dates are not selectable. No record does **not** mean no spending.

### 5. Smart spending warnings (Home and local notifications)
The Home dashboard shows warnings when your overall daily target is at least 80% used, a category daily limit is at least 80% used, or small purchases under ₹100 account for at least 20% of your target across at least 3 payments. After saving a current-day payment, the app can send an additional **category budget alert** at 80%/100% or an **unusually large payment alert** if that single expense is at least ₹500 and at least 3 times the average of **5 or more previous payments from the preceding 30 days**. All calculations run locally. Smart notifications respect the current notification toggle and quiet hours. Warnings depend on recorded transactions and are not financial advice.

**SMS records still require approval:** In **Settings → Automatic UPI SMS detection**, grant the permission voluntarily. New incoming UPI debit SMS are placed into a review inbox (not added automatically). Select a category and tap *Save payment* to include them in category limits, reports and warnings.

## Other existing features
Daily budget ring, weekday/weekend targets, manual quick-add, edit/delete/undo, on-device SQLite, daily reports, category suggestions, Needed/Impulse tags, streaks and affordability preview.

## Download and install
1. Open **[GitHub Actions APK builds](https://github.com/Shivayt007/upispender/actions/workflows/android.yml)**.
2. Choose the latest successful **Build Android APK** workflow.
3. Download **UPI-Spend-Tracker-APK**, extract the ZIP, install \`app-release.apk\`.
4. Open the app to set your default daily target, and try logging a payment manually.

> **Important update/signing warning:** The GitHub workflow currently signs test APKs using an ephemeral debug keystore, which might differ between builds. Updating an existing installation may fail with "App not installed" due to a signing mismatch. **Do not uninstall your previous app if it contains important financial records.** There is not yet a backup/export feature. A persistent private signing key and encrypted local backup should be implemented before relying on app upgrades long-term.

The Android app is a local APK; no hosting or VPS is required.

## Privacy and limitations
- All records stay local in app-private SQLite. No internet/account access.
- Incoming SMS detection is opt-in and uses RECEIVE_SMS, not READ_SMS.
- Raw messages and OTPs are not stored. SMS detection is not guaranteed for every bank or UPI payment.
- No direct GPay/PhonePe/Paytm synchronization is claimed.
- These charts visualize recorded payments only, not bank account balances or cash you have not logged.
- SMS permission may require Google Play policy eligibility and permission review for store distribution.
- Daily warning notifications may be delayed or disabled by Android battery/notification settings.

## Still planned
Statement CSV/PDF imports, exports/backups, fingerprint/PIN app lock, permanent signing, home widget, recurring payments, rollover, salary cycles, and Hindi localization.

---
