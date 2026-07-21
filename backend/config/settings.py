from datetime import timedelta
from pathlib import Path

import dj_database_url
import environ

BASE_DIR = Path(__file__).resolve().parent.parent

env = environ.Env(DEBUG=(bool, False))
environ.Env.read_env(BASE_DIR / ".env")

SECRET_KEY = env("SECRET_KEY", default="dev-insecure-change-me")
DEBUG = env("DEBUG")
ALLOWED_HOSTS = ["*"] if DEBUG else env.list("ALLOWED_HOSTS", default=[])
CSRF_TRUSTED_ORIGINS = env.list("CSRF_TRUSTED_ORIGINS", default=[])
# Render injects the external hostname at runtime — auto-trust it so the URL is never hardcoded.
_render_host = env("RENDER_EXTERNAL_HOSTNAME", default="")
if _render_host:
    ALLOWED_HOSTS.append(_render_host)
    CSRF_TRUSTED_ORIGINS.append(f"https://{_render_host}")
# ponytail: wide-open only in DEBUG (web dev). In prod list the web app's origin(s)
# in CORS_ALLOWED_ORIGINS. Native mobile apps don't need CORS (not browsers).
CORS_ALLOW_ALL_ORIGINS = DEBUG
CORS_ALLOWED_ORIGINS = env.list("CORS_ALLOWED_ORIGINS", default=[])

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "corsheaders",
    "owners",
    "pg",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",  # serves admin static in prod
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"

# Supabase Postgres via DATABASE_URL; sqlite fallback for local dev without one.
DATABASE_URL = env("DATABASE_URL", default="")
if DATABASE_URL:
    DATABASES = {"default": dj_database_url.parse(DATABASE_URL, conn_max_age=600, ssl_require=True)}
else:
    # ponytail: sqlite fallback so the app runs before Supabase creds are wired.
    DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": BASE_DIR / "db.sqlite3"}}

AUTH_USER_MODEL = "owners.Owner"

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
]

# bcrypt verifies ~10x faster than PBKDF2 (600k iters) on low-CPU hosts (Render free),
# cutting warm login from ~2s to ~0.3s. PBKDF2 kept below so existing hashes still verify
# (Django auto-rehashes to bcrypt on the user's next successful login).
PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.BCryptSHA256PasswordHasher",
    "django.contrib.auth.hashers.PBKDF2PasswordHasher",
    "django.contrib.auth.hashers.PBKDF2SHA1PasswordHasher",
]

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
    ],
}

# Long session: 1-day access token + 60-day refresh. Client auto-refreshes silently,
# so owners rarely re-login. Refresh rotates and old ones are blacklisted-by-expiry.
SIMPLE_JWT = {
    # Long-lived so the app stays logged in until the user explicitly logs out. Access
    # token rarely needs refreshing; refresh rolls forward on each use (rotation).
    "ACCESS_TOKEN_LIFETIME": timedelta(days=30),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=365),
    "ROTATE_REFRESH_TOKENS": True,
}

RAZORPAY_KEY_ID = env("RAZORPAY_KEY_ID", default="")
RAZORPAY_KEY_SECRET = env("RAZORPAY_KEY_SECRET", default="")
RAZORPAY_WEBHOOK_SECRET = env("RAZORPAY_WEBHOOK_SECRET", default="")

LANGUAGE_CODE = "en-us"
TIME_ZONE = "Asia/Kolkata"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "whitenoise.storage.CompressedStaticFilesStorage"},
}

# Tenant ID proofs. ponytail: local FileField for MVP — swap 'default' storage above for
# django-storages + Supabase/S3 when you outgrow the host disk.
MEDIA_URL = "media/"
MEDIA_ROOT = BASE_DIR / "media"

# Reminder providers (blank = disabled; send_reminders logs 'no_provider').
GUPSHUP_API_KEY = env("GUPSHUP_API_KEY", default="")
GUPSHUP_SOURCE = env("GUPSHUP_SOURCE", default="")
GUPSHUP_APP = env("GUPSHUP_APP", default="")
MSG91_API_KEY = env("MSG91_API_KEY", default="")

# Firebase Admin: service-account JSON path. Used to verify phone-auth ID tokens at
# registration. Blank → registration rejects (no insecure fallback).
FIREBASE_CREDENTIALS = env("FIREBASE_CREDENTIALS", default="")

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
