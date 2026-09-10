# Knowledge Management Firebase Setup

## 1. Authentication

1. Open **Firebase Console → Authentication → Sign-in method**.
2. Enable **Google** and configure the project support email.
3. Enable **Email/Password** if email accounts are supported.
4. In **Authentication → Settings → Authorized domains**, add the production web
   domain and the local development domain used by Flutter web.
5. Keep App Check enabled for production and register the web reCAPTCHA Enterprise
   site key used by the app.

## 2. Firebase Storage

The encrypted backup is stored per user. The client must never be able to read
or write another user's backup.

### Storage CORS

Flutter Web loads profile images through browser XHR requests, so the Storage
bucket must allow the local development origin. Apply the included
`storage.cors.json` to the actual bucket:

```powershell
gcloud storage buckets update gs://languagehungry.firebasestorage.app `
  --cors-file=storage.cors.json
```

If `gcloud` is unavailable, install the Google Cloud CLI and run:

```powershell
gcloud auth login
gcloud config set project languagehungry
gcloud storage buckets update gs://languagehungry.firebasestorage.app `
  --cors-file=storage.cors.json
```

For production, add the exact HTTPS origin to `storage.cors.json`, for example:
`https://your-domain.example`, then apply the configuration again. Do not use
`*` for a production bucket containing private user files.

```text
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /users/{userId}/backups/{fileName} {
      allow read, write: if request.auth != null
                         && request.auth.uid == userId
                         && request.resource.size < 50 * 1024 * 1024
                         && request.resource.contentType == 'application/octet-stream';
    }
  }
}
```

Deploy the rule after replacing the default test rule. The app should encrypt
the SQLite export with AES-256 before uploading; Firebase Storage must receive
only ciphertext.

The implemented client service is:

```dart
final backup = EncryptedBackupService(store: knowledgeStore);
await backup.upload(passphrase: userPassphrase);
await backup.restore(
  backupPath: selectedStoragePath,
  passphrase: userPassphrase,
);
```

The backup format contains a version header, random salt, random AES-GCM
nonce, ciphertext, and authentication tag. The password is never uploaded.

## 3. Firestore and App Check

1. Create or keep the `langgry` named Firestore database used by the app.
2. Deploy production Firestore rules for user profiles; do not use an
   expiration-based allow-all rule.
3. In **App Check**, register the web reCAPTCHA Enterprise site key and the
   Android/iOS providers used by release builds.
4. Start with metrics-only enforcement, verify sign-in and backup traffic, then
   enforce App Check for Authentication, Firestore, and Storage.

## 4. Backup key handling

Derive the AES-256 key locally from a user-provided passphrase using a memory
hard KDF such as Argon2id or PBKDF2-HMAC-SHA256 with a random salt. Store the
salt and nonce with the encrypted file, never the passphrase or raw key. A
lost passphrase cannot be recovered by Firebase.
