import hashlib
import hmac
import json

from django.test import TestCase, override_settings

from .models import Owner, SubscriptionPlan

SECRET = "whsecret"


@override_settings(RAZORPAY_WEBHOOK_SECRET=SECRET)
class WebhookSignatureTest(TestCase):
    def setUp(self):
        self.plan = SubscriptionPlan.objects.create(name="Monthly", price=499, duration_days=30)
        self.owner = Owner.objects.create_user(email="a@b.com", password="pass12345")
        self.body = json.dumps({
            "event": "order.paid",
            "payload": {"order": {"entity": {"notes": {
                "owner_id": str(self.owner.id), "plan_id": str(self.plan.id),
            }}}},
        })
        self.sig = hmac.new(SECRET.encode(), self.body.encode(), hashlib.sha256).hexdigest()

    def _post(self, signature):
        return self.client.post(
            "/api/subscription/webhook/",
            data=self.body,
            content_type="application/json",
            HTTP_X_RAZORPAY_SIGNATURE=signature,
        )

    def test_valid_signature_activates(self):
        resp = self._post(self.sig)
        self.assertEqual(resp.status_code, 200)
        self.owner.refresh_from_db()
        self.assertEqual(self.owner.subscription_status, "active")
        self.assertIsNotNone(self.owner.subscription_expiry)

    def test_bad_signature_rejected(self):
        resp = self._post("deadbeef")
        self.assertEqual(resp.status_code, 400)
        self.owner.refresh_from_db()
        self.assertEqual(self.owner.subscription_status, "pending")
        self.assertIsNone(self.owner.subscription_expiry)
