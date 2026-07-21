# Firebase Phone Auth — setup

Registration verifies a Firebase phone-auth **ID token**. The app runs the OTP flow
(Firebase sends the SMS, no DLT needed); the backend trusts the phone number Firebase signed.

## What's already done (in code)
- Backend verifies the token via `firebase-admin` (`owners/firebase.py`); reads `FIREBASE_CREDENTIALS`.
- App runs `verifyPhoneNumber` → code → `signInWithCredential` → sends the ID token to `/api/auth/register/`.
- `flutterfire_cli` installed; Android debug SHA fingerprints generated (below).

## What you do (needs your Google account)

### 1. Create the Firebase project
Firebase console → **Add project** → **Authentication → Sign-in method → enable Phone**.
Upgrade to the **Blaze** plan (phone auth requires it). Turn on **SMS region policy** and
**toll-fraud protection** (Authentication → Settings) so a bot can't burn your SMS quota.

### 2. Log in the CLI (interactive)
In a terminal, run:
```
firebase login
```
Then, from `mobile/`, run `flutterfire configure` (or non-interactively) to
generate `mobile/lib/firebase_options.dart` and place the platform config
(`google-services.json`, `GoogleService-Info.plist`).

### 3. Android SHA fingerprints (debug)
Firebase console → Project settings → your Android app → **Add fingerprint**:
- SHA-1:   `4A:91:3B:01:9E:D2:9A:13:6F:FE:7E:41:CF:D1:63:F5:92:77:93:7E`
- SHA-256: `E4:F7:44:EB:AB:55:D2:2C:36:31:8B:86:FD:D1:61:59:07:80:B3:4F:4C:6F:3D:63:6F:18:0E:62:53:68:2C:2B`
(Add your **release** keystore SHA before shipping to Play.)

### 4. Web authorized domains
Authentication → Settings → **Authorized domains** → add `127.0.0.1` (dev) and your prod domain.

### 5. Backend service account
Firebase console → Project settings → **Service accounts → Generate new private key** →
save the JSON, then in `backend/.env`:
```
FIREBASE_CREDENTIALS=/absolute/path/to/serviceAccount.json
```
Keep this file out of git (it's a secret).

## App identifiers (registered by flutterfire configure)
- Android: `com.yourcompany.pg_management`
- iOS:     `com.yourcompany.pgManagement`

Change these to your real reverse-domain ID before store release (separate task).

## Caveats
- **Web** phone auth shows a reCAPTCHA — expected, web only.
- Firebase validates phone auth server-side; a misconfigured project fails the token verify,
  and registration returns "Phone verification failed" (never silently trusts client input).
