# Firebase project migration (handover)

Moves **all data** from the old Firebase project (`nexgrova-fba5d`) to a **new**
project owned by the new owner — Firestore documents, Storage images (with the
stored image URLs repointed at the new bucket), and Auth logins.

Run this **once**, after the new Firebase project exists and its Firestore +
Storage are enabled. Everything here runs on your machine with keys you download;
nothing is committed to the repo.

---

## What migrates

| Part | Handled by | Notes |
|------|------------|-------|
| Firestore (products, categories, subcategories, variants, parties, discounts, settings, orders, order_items, inventory, notifications, counters, users, logs) | `migrate.js` | Document ids preserved |
| Storage files (all images + logo) | `migrate.js` | Copied to the new bucket with fresh download tokens |
| Image URLs in Firestore (`products.imageUrls`, `categories.imageUrl`, `subcategories.imageUrl`, `settings.logoUrl`) | `migrate.js` | Rewritten to the new bucket so images don't break |
| **Auth accounts** (admin + dealer logins, passwords) | **Firebase CLI** (Step 4) | Separate — preserves UIDs + password hashes |

> The `users/{uid}` Firestore docs are keyed by Auth UID, so do the Auth import
> (Step 4) with UIDs preserved and the `users` collection copy (Step 3) will line
> up automatically.

---

## Step 1 — Create & enable the new project

In the [Firebase console](https://console.firebase.google.com): create the
project, then enable **Authentication → Email/Password**, **Firestore Database**,
and **Storage**. Upgrade to the **Blaze** plan (needed for Functions + Storage).
Note the **project id** and the **storage bucket** (looks like
`<project-id>.firebasestorage.app`).

## Step 2 — Get two service-account keys

For **each** project: Console → ⚙ Project settings → **Service accounts** →
**Generate new private key**. Save the two JSON files **outside this repo**
(e.g. `C:\keys\old-service-account.json`, `C:\keys\new-service-account.json`).
These are secrets — never commit them.

## Step 3 — Run the data migration

```bash
cd tools/migrate && npm install
```

PowerShell — preview first (no writes):

```powershell
$env:OLD_SA="C:\keys\old-service-account.json"; $env:NEW_SA="C:\keys\new-service-account.json"; $env:OLD_BUCKET="nexgrova-fba5d.firebasestorage.app"; $env:NEW_BUCKET="NEW_PROJECT_ID.firebasestorage.app"; $env:DRY_RUN="1"; node migrate.js
```

If the counts look right, run for real:

```powershell
$env:DRY_RUN="0"; node migrate.js
```

## Step 4 — Migrate Auth logins (Firebase CLI)

This preserves every login's UID and password. Get the **password hash
parameters** from the OLD project: Console → Authentication → ⋮ (top-right) →
**Password hash parameters** (`base64_signer_key`, `base64_salt_separator`,
`rounds`, `mem_cost`).

```bash
npm i -g firebase-tools
firebase auth:export users.json --project OLD_PROJECT_ID
firebase auth:import users.json --project NEW_PROJECT_ID --hash-algo=SCRYPT --hash-key="BASE64_SIGNER_KEY" --salt-separator="BASE64_SALT_SEPARATOR" --rounds=ROUNDS --mem-cost=MEM_COST
```

## Step 5 — Point the app at the new project & rebuild

```bash
flutterfire configure --project=NEW_PROJECT_ID
```

Then deploy backend + rebuild the app:

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage,functions --project NEW_PROJECT_ID
flutter build apk --release
```

## Step 6 — Verify

Open the app against the new project and confirm products, categories, images,
and logins all load. Spot-check an image URL in Firestore — it should contain the
**new** bucket name. Keep the old project around until you've verified, then it
can be retired.

---

### Notes & limits

- Re-runnable: documents are written by id and files re-uploaded to the same path.
- Only URLs in the Firebase Storage format (`.../o/<path>?...`) are rewritten;
  legacy inline `data:` images are left untouched (they need no bucket).
- Very large catalogs: files are copied one-by-one in memory — fine for images,
  but if you have tens of thousands of objects consider `gsutil -m rsync`
  for the bulk copy and run this script only for the URL rewrite.
- The script never writes to the old project.
