"""Upload tenant photos to Supabase Storage and return their public URL.

The client sends a `data:<mime>;base64,<data>` string; we push the raw bytes to the
bucket via Supabase's Storage REST API (stdlib urllib — no extra dependency) and store
only the returned public URL on the tenant. Assumes a PUBLIC bucket with unguessable
(uuid) object names. ponytail: switch to a private bucket + signed URLs if the photos
need real access control.
"""
import base64
import json
import uuid
import urllib.error
import urllib.request

from django.conf import settings


def upload_data_url(data_url, folder="tenants"):
    base = settings.SUPABASE_URL.rstrip("/")
    key = settings.SUPABASE_SERVICE_KEY
    bucket = settings.SUPABASE_BUCKET
    if not (base and key and bucket):
        raise RuntimeError("SUPABASE_URL, SUPABASE_SERVICE_KEY and SUPABASE_BUCKET must be set")

    header, _, b64 = data_url.partition(",")
    if not b64 or "base64" not in header:
        raise ValueError("expected a base64 data URL")
    content_type = header[5:].split(";")[0] or "image/jpeg"  # strip "data:"
    ext = content_type.split("/")[-1] or "jpg"
    raw = base64.b64decode(b64)

    path = f"{folder}/{uuid.uuid4().hex}.{ext}"
    req = urllib.request.Request(
        url=f"{base}/storage/v1/object/{bucket}/{path}",
        data=raw,
        method="POST",
        headers={
            "Authorization": f"Bearer {key}",
            "apikey": key,
            "Content-Type": content_type,
            "x-upsert": "true",
        },
    )
    try:
        urllib.request.urlopen(req, timeout=30)
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        try:
            detail = json.loads(detail).get("message", detail)
        except ValueError:
            pass
        raise RuntimeError(f"Supabase upload failed ({e.code}): {detail}") from e

    return f"{base}/storage/v1/object/public/{bucket}/{path}"


def delete_url(url):
    """Best-effort delete of an object we previously stored (given its public URL).
    Silently ignores anything that isn't one of our bucket URLs, or an already-gone
    object — a failed cleanup must never block the tenant save."""
    base = settings.SUPABASE_URL.rstrip("/")
    bucket = settings.SUPABASE_BUCKET
    if not (url and base and bucket and url.startswith("http")):
        return
    marker = f"/object/public/{bucket}/"
    i = url.find(marker)
    if i == -1:
        return  # not an object in our bucket — leave it alone
    path = url[i + len(marker):]
    key = settings.SUPABASE_SERVICE_KEY
    req = urllib.request.Request(
        url=f"{base}/storage/v1/object/{bucket}/{path}",
        method="DELETE",
        headers={"Authorization": f"Bearer {key}", "apikey": key},
    )
    try:
        urllib.request.urlopen(req, timeout=15)
    except (urllib.error.HTTPError, urllib.error.URLError):
        pass
