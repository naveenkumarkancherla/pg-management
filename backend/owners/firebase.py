"""Firebase Admin: verify a client's phone-auth ID token → the verified phone number.

The Flutter app does the OTP flow via Firebase (no DLT needed) and sends us the resulting
ID token. We only trust the phone number Firebase signed.

Set FIREBASE_CREDENTIALS to the service-account JSON path. Unset → verification fails
with a clear error (registration is blocked rather than silently insecure).
"""
import firebase_admin
from firebase_admin import auth, credentials
from django.conf import settings

_app = None


def _ensure_app():
    global _app
    if _app is None:
        path = getattr(settings, "FIREBASE_CREDENTIALS", "")
        if not path:
            raise RuntimeError("FIREBASE_CREDENTIALS not configured")
        _app = firebase_admin.initialize_app(credentials.Certificate(path))
    return _app


def verify_phone_token(id_token):
    """Return the E.164 phone number from a valid token, or None if invalid/unverified
    (or if Firebase isn't configured — registration is blocked, never silently trusted)."""
    try:
        _ensure_app()
        claims = auth.verify_id_token(id_token)
    except Exception:
        return None
    return claims.get("phone_number")
