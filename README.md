# B2B SaaS — Inventory, Orders & Billing (Flutter + Firebase)

A production-oriented B2B inventory / order-management platform. **One Flutter
codebase** serves both:

- **Client app** (Android) — browse catalog, cart, place & track orders.
- **Admin panel** (Flutter Web) — manage catalog, inventory, parties, orders,
  invoices, reports.

Backend is **Firebase** (Auth, Firestore, Storage, Cloud Messaging, Cloud
Functions). Architecture is **feature-first Clean Architecture** with Riverpod +
GoRouter. Every record carries a `companyId`, so the app is **multi-tenant
ready** even though it runs single-tenant today.

> **Status:** this repository is the **foundation build**. Auth, role-based
> routing, the design system, the adaptive admin/client shells, the dashboard,
> and the **Categories** module are implemented end-to-end. Categories is the
> reference pattern — every other admin module is built by copying it. See the
> [Roadmap](#roadmap) for what remains.

---

## 1. Prerequisites (install these first)

This machine currently has **Node + git** but **not** Flutter/Dart/Firebase CLI.
Install:

1. **Flutter SDK** (latest stable) — <https://docs.flutter.dev/get-started/install/windows>
   Then: `flutter doctor` and fix anything red.
2. **Android Studio** (for the Android SDK + an emulator/JDK).
3. **Firebase CLI**:
   ```bash
   npm install -g firebase-tools
   firebase login
   ```
4. **FlutterFire CLI**:
   ```bash
   dart pub global activate flutterfire_cli
   ```

## 2. First-time setup

Firebase project: **nexgrova-fba5d**. `android/app/google-services.json` and the
Android values in `lib/firebase_options.dart` are already filled in. A **Web**
app still needs registering (see step 3).

```bash
# from D:\b2b saas
# Generate the platform folders (android/, web/, etc.). This repo ships only
# lib/ + config; `flutter create .` scaffolds the rest WITHOUT touching lib/.
flutter create . --platforms=android,web --org com.company

# IMPORTANT: the Android app id MUST match google-services.json →
# com.company.nexgrova. In android/app/build.gradle(.kts) set:
#   namespace     "com.company.nexgrova"
#   applicationId "com.company.nexgrova"
#   minSdkVersion 23   // required by firebase_auth

flutter pub get

# EASIEST: let FlutterFire wire everything (Gradle plugins + web app + options):
flutterfire configure --project=nexgrova-fba5d
# (this also fills the Web app id/key and updates firebase_options.dart)

# install Cloud Functions deps
cd functions && npm install && cd ..
```

In the [Firebase console](https://console.firebase.google.com):
- Enable **Authentication → Email/Password**.
- Create **Firestore** (production mode) and **Storage**.
- Enable **Cloud Messaging**.

Deploy backend config:
```bash
firebase deploy --only firestore:rules,firestore:indexes,storage
firebase deploy --only functions
```

## 3. Run

```bash
# Client app (Android)
flutter run

# Admin panel (Flutter Web)
flutter run -d chrome
```

Both entry through the same `main.dart`; the **role on the signed-in user's
`users/{uid}` document** decides whether they land on the admin or client shell.

## 4. Create the first admin (bootstrap)

Rules provision client logins via a Cloud Function, but the very first admin must
be created by hand:

1. Firebase console → Authentication → **Add user** (email + password).
2. Firestore → create collection `users` → document id = that user's **UID**:
   ```json
   {
     "companyId": "default",
     "role": "admin",
     "name": "Owner",
     "email": "you@example.com",
     "status": "active"
   }
   ```
3. Sign in via the **Admin** tab in the app.

Clients are then created from the admin panel (Parties module → calls the
`createClientUser` function), which turns a **Party ID** into a login
(`p00102@party.b2bsaas.app`) — the client only ever types the Party ID.

## 5. Manual Android Firebase wiring (skip if you ran `flutterfire configure`)

If you did **not** run `flutterfire configure`, add the Google Services Gradle
plugin so `google-services.json` is picked up:

- `android/settings.gradle(.kts)` plugins block (or `android/build.gradle`
  classpath): `com.google.gms.google-services` version `4.4.2`, `apply false`.
- `android/app/build.gradle(.kts)`: apply `com.google.gms.google-services`.
- `android/app/src/main/AndroidManifest.xml`: add
  `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>`
  (Android 13+ FCM) and internet permission.

## 6. Build & deploy

```bash
# Android release
flutter build apk --release           # or: flutter build appbundle --release

# Web admin
flutter build web --release
firebase deploy --only hosting        # serves build/web (config in firebase.json)

# Backend
firebase deploy --only firestore:rules,firestore:indexes,storage,functions
```

Run tests / static analysis:
```bash
flutter analyze
flutter test
```

## 7. Performance & offline notes

- **Firestore offline cache** is enabled (`main.dart`) so the app works with
  intermittent connectivity and reads are served locally first.
- Lists use `ListView.separated`/`GridView` with lazy building; images use
  `cached_network_image` and are compressed before upload.
- Dashboard/report metrics aggregate client-side today. As data grows, move hot
  counters to a Cloud Function-maintained `stats/{companyId}` doc and read that
  instead of counting whole collections.
- All list queries are company-scoped and backed by the composite indexes in
  `firestore.indexes.json`.

---

## Project structure

```
lib/
  main.dart                     # Firebase init + ProviderScope
  firebase_options.dart         # PLACEHOLDER — regenerate with flutterfire
  app/                          # app shell: theme, router, MaterialApp
  core/
    constants/                  # collection names, app config
    providers/                  # Firebase SDK providers
    utils/                      # validators, formatters
    widgets/                    # design system: shell, state views, responsive
  features/
    auth/       {data,domain,presentation}   # login, roles, profile
    dashboard/  presentation                 # admin dashboard + charts
    categories/ {data,domain,presentation}   # ✅ reference CRUD module
    products/   domain                       # Product + dynamic attributes, Variant
    parties/    domain                       # Party (customer) model
    orders/     domain                       # Order, OrderItem, status lifecycle
    inventory/  domain                       # transaction-based stock model
functions/                      # Cloud Functions (invoice #, stock, notifications)
firestore.rules                 # role-based, company-scoped security
firestore.indexes.json          # composite indexes
storage.rules
firebase.json
```

### Key architectural decisions
- **Variants, not duplicate products.** A product has many `variants` (20mm,
  25mm…), each with its own rate/pack/stock. Product & variant attributes are
  **dynamic key/value pairs** → the app fits any industry without schema changes.
- **Transaction-based inventory.** Stock is the *sum* of
  `inventory_transactions`; it is never edited directly. Full audit trail.
- **Server-authoritative business logic.** Invoice numbers, stock deduction and
  client provisioning run in **Cloud Functions** so clients can't tamper.
- **Company-scoped everything.** Every doc has `companyId`; rules enforce it.

---

## Roadmap

Each module below follows the **Categories pattern**
(`domain model → repository → StreamProvider → screen with form dialog`):

- [x] Foundation: architecture, theme, routing, auth, shells, dashboard
- [x] Categories CRUD (reference module)
- [x] Subcategories CRUD (reachable from the Categories screen)
- [x] Products + Variants (dynamic attribute editor, opening-stock transaction)
- [x] Parties CRUD + `createClientUser` wiring (generates the client login)
- [x] Product **image upload** (picker → compress → Firebase Storage, multi-image)
- [x] CSV/Excel **Import Engine**: header auto-detect, column mapping, saved
      templates, row-level validation, add-only/add+update/update-only, creates
      categories & products on the fly, opening-stock transactions
- [x] Bulk party import (generic Import Engine, `parties` target + login provisioning)
- [x] ZIP bulk image import (match by SKU/product name)
- [x] Inventory: transaction-based adjustments (purchase/damage/return/correction),
      low-stock filter + banner, per-variant history
- [x] Client app: catalog browse → variant picker → cart → submit → track
- [x] Order workflow: admin approve (server `approveOrder` + stock deduction) /
      reject / advance status (packing→dispatched→delivered→completed)
- [x] PDF invoices (`pdf`/`printing`) — print/preview from the order detail screen
- [x] Notifications UI: FCM token registration on sign-in + in-app history screen
- [x] Discount engine (priority variant → product → category → party → global),
      applied live in the client catalog
- [x] Reports & analytics (revenue, status breakdown, top parties, monthly)
- [x] Settings (company profile, invoice prefix, currency, terms) + theme switch
      (persisted) + light/dark
- [x] Report export to CSV / Excel / PDF (from the Reports screen)
- [x] Admin broadcast notifications (to all clients) + activity logs (audit trail)
- [x] Unit tests for core logic (discounts, column mapping, cart, statuses, CSV)
- [x] Build & deploy config (Android google-services, web hosting, FCM sw)
- [ ] Full device/browser run-through once the Flutter SDK is installed (your side)

---

## Firestore collections

`users`, `parties`, `categories`, `subcategories`, `products`, `variants`,
`inventory_transactions`, `orders`, `order_items`, `discounts`, `notifications`,
`settings`, `logs`, `invoice_counter`, `import_templates`.
