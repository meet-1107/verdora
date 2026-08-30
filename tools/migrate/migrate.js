#!/usr/bin/env node
/**
 * One-off data migration between two Firebase projects for the Asian Plast
 * (B2B ERP) app.
 *
 * It copies, from the OLD project to the NEW project:
 *   1. Storage objects (product/category/subcategory images, company logo, …)
 *   2. All Firestore collections (documents keep their ids)
 *   3. Then rewrites the stored image download URLs
 *      (products.imageUrls, categories.imageUrl, subcategories.imageUrl,
 *       settings.logoUrl) so they point at the NEW bucket.
 *
 * The OLD project is only ever READ. Re-running is safe (documents are written
 * by id; files are re-uploaded to the same path).
 *
 * NOTE: Firebase Authentication accounts (admin + dealer logins) are NOT handled
 * here — migrate them with the Firebase CLI so UIDs and passwords are preserved.
 * See README.md ("Step 4 — Auth").
 *
 * Usage (PowerShell):
 *   cd tools/migrate
 *   npm install
 *   $env:OLD_SA   = "C:\keys\old-service-account.json"
 *   $env:NEW_SA   = "C:\keys\new-service-account.json"
 *   $env:OLD_BUCKET = "nexgrova-fba5d.firebasestorage.app"
 *   $env:NEW_BUCKET = "<new-project-id>.firebasestorage.app"
 *   $env:DRY_RUN  = "1"    # preview counts without writing; remove to run for real
 *   node migrate.js
 */
'use strict';

const fs = require('fs');
const crypto = require('crypto');
const admin = require('firebase-admin');

function req(name) {
  const v = process.env[name];
  if (!v) {
    console.error(`ERROR: missing required env var ${name}`);
    process.exit(1);
  }
  return v;
}

const OLD_SA = req('OLD_SA');
const NEW_SA = req('NEW_SA');
const OLD_BUCKET = req('OLD_BUCKET');
const NEW_BUCKET = req('NEW_BUCKET');
const DRY = process.env.DRY_RUN === '1';

const loadSA = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));

const oldApp = admin.initializeApp(
  { credential: admin.credential.cert(loadSA(OLD_SA)), storageBucket: OLD_BUCKET },
  'old',
);
const newApp = admin.initializeApp(
  { credential: admin.credential.cert(loadSA(NEW_SA)), storageBucket: NEW_BUCKET },
  'new',
);

const oldDb = oldApp.firestore();
const newDb = newApp.firestore();
const oldBucket = oldApp.storage().bucket();
const newBucket = newApp.storage().bucket();

// Every top-level collection the app uses (see lib/core/constants/collections.dart).
const COLLECTIONS = [
  'users', 'roles', 'companies', 'parties', 'categories', 'subcategories',
  'products', 'variants', 'inventory_transactions', 'orders', 'order_items',
  'discounts', 'notifications', 'settings', 'logs', 'invoice_counter',
  'order_counters', 'import_templates',
];

// Fields that store Storage download URLs, by collection.
const IMAGE_FIELDS = {
  products: { list: ['imageUrls'] },
  categories: { single: ['imageUrl'] },
  subcategories: { single: ['imageUrl'] },
  settings: { single: ['logoUrl'] },
};

// Storage object path -> new download URL (built while copying files).
const pathToNewUrl = new Map();

async function copyStorage() {
  const [files] = await oldBucket.getFiles();
  const real = files.filter((f) => !f.name.endsWith('/'));
  console.log(`Storage: ${real.length} objects`);
  let i = 0;
  for (const f of real) {
    const path = f.name;
    const token = crypto.randomUUID();
    pathToNewUrl.set(
      path,
      `https://firebasestorage.googleapis.com/v0/b/${NEW_BUCKET}/o/` +
        `${encodeURIComponent(path)}?alt=media&token=${token}`,
    );
    if (!DRY) {
      const [buf] = await f.download();
      const [meta] = await f.getMetadata();
      await newBucket.file(path).save(buf, {
        resumable: false,
        metadata: {
          contentType: meta.contentType || 'application/octet-stream',
          metadata: { firebaseStorageDownloadTokens: token },
        },
      });
    }
    if (++i % 25 === 0) console.log(`  …${i}/${real.length}`);
  }
}

async function copyFirestore() {
  for (const col of COLLECTIONS) {
    const snap = await oldDb.collection(col).get();
    console.log(`Firestore ${col}: ${snap.size} docs`);
    if (DRY || snap.empty) continue;
    let batch = newDb.batch();
    let n = 0;
    for (const doc of snap.docs) {
      batch.set(newDb.collection(col).doc(doc.id), doc.data());
      if (++n % 400 === 0) {
        await batch.commit();
        batch = newDb.batch();
      }
    }
    if (n % 400 !== 0) await batch.commit();
  }
}

// Pull the object path out of a Firebase download URL (…/o/<ENCODED_PATH>?…).
function pathFromUrl(url) {
  const m = /\/o\/([^?]+)/.exec(url || '');
  return m ? decodeURIComponent(m[1]) : null;
}

function rewriteUrl(url) {
  if (typeof url !== 'string' || !url) return url;
  if (url.startsWith('data:')) return url; // legacy inline image — leave alone
  const path = pathFromUrl(url);
  if (!path) return url; // not a Firebase Storage URL
  return pathToNewUrl.get(path) || url; // leave as-is if the file wasn't found
}

async function rewriteImageUrls() {
  for (const [col, spec] of Object.entries(IMAGE_FIELDS)) {
    const snap = await newDb.collection(col).get();
    let batch = newDb.batch();
    let n = 0;
    let changed = 0;
    for (const doc of snap.docs) {
      const data = doc.data();
      const update = {};
      for (const field of spec.single || []) {
        if (data[field]) {
          const nu = rewriteUrl(data[field]);
          if (nu !== data[field]) update[field] = nu;
        }
      }
      for (const field of spec.list || []) {
        if (Array.isArray(data[field])) {
          const arr = data[field].map(rewriteUrl);
          if (JSON.stringify(arr) !== JSON.stringify(data[field])) update[field] = arr;
        }
      }
      if (Object.keys(update).length) {
        changed++;
        if (!DRY) {
          batch.update(doc.ref, update);
          if (++n % 400 === 0) {
            await batch.commit();
            batch = newDb.batch();
          }
        }
      }
    }
    if (!DRY && n % 400 !== 0) await batch.commit();
    console.log(`URL rewrite ${col}: ${changed} doc(s) ${DRY ? '(dry run)' : 'updated'}`);
  }
}

(async () => {
  console.log(
    `Migrating OLD(${OLD_BUCKET}) -> NEW(${NEW_BUCKET})${DRY ? '   [DRY RUN — no writes]' : ''}`,
  );
  await copyStorage(); // copy files + build path -> new URL map
  await copyFirestore(); // copy all documents (image fields still hold old URLs)
  await rewriteImageUrls(); // repoint image fields at the new bucket
  console.log('Done.');
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
