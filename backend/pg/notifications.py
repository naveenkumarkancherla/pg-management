"""Thin reminder + OTP sender. WhatsApp via Gupshup, SMS via MSG91 — both gated by env.

ponytail: stdlib urllib, no requests dep, no provider SDK. The real integration is a
handful of lines; if a provider's API grows hairy, swap this one function for its SDK.
Returns (channel, status) for ReminderLog.
"""
import urllib.parse
import urllib.request

from django.conf import settings


def _post(url, data, headers):
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=10) as r:
        return 200 <= r.status < 300


def send_reminder(phone, text, source=""):
    key = getattr(settings, "GUPSHUP_API_KEY", "")
    src = source or getattr(settings, "GUPSHUP_SOURCE", "")
    if key and src:
        try:
            ok = _post(
                "https://api.gupshup.io/wa/api/v1/msg",
                {"channel": "whatsapp", "source": src, "destination": phone,
                 "message": text, "src.name": getattr(settings, "GUPSHUP_APP", "")},
                {"apikey": key, "Content-Type": "application/x-www-form-urlencoded"},
            )
            return "whatsapp", "sent" if ok else "failed"
        except Exception:
            pass  # fall through to SMS

    sms_key = getattr(settings, "MSG91_API_KEY", "")
    if sms_key:
        try:
            ok = _post(
                "https://api.msg91.com/api/v5/flow/",
                {"mobiles": phone, "message": text},
                {"authkey": sms_key, "Content-Type": "application/x-www-form-urlencoded"},
            )
            return "sms", "sent" if ok else "failed"
        except Exception:
            return "sms", "failed"

    return "none", "no_provider"
