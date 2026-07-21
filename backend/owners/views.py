import json
from datetime import timedelta

import razorpay
from django.conf import settings
from django.utils import timezone
from django.utils.decorators import method_decorator
from django.views.decorators.csrf import csrf_exempt
from rest_framework import generics
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Owner, SubscriptionPlan
from .permissions import IsActiveOwner
from .serializers import OwnerSerializer, PlanSerializer, RegisterSerializer


def _rzp():
    return razorpay.Client(auth=(settings.RAZORPAY_KEY_ID, settings.RAZORPAY_KEY_SECRET))


def _activate(owner, plan):
    """Grant access: active subscription + auto-approval."""
    owner.subscription_plan = plan
    owner.subscription_status = "active"
    owner.subscription_expiry = timezone.now() + timedelta(days=plan.duration_days)
    owner.is_approved = True
    owner.save(update_fields=[
        "subscription_plan", "subscription_status", "subscription_expiry", "is_approved",
    ])


class RegisterView(generics.CreateAPIView):
    permission_classes = [AllowAny]
    serializer_class = RegisterSerializer


class PlanListView(generics.ListAPIView):
    permission_classes = [AllowAny]
    serializer_class = PlanSerializer
    queryset = SubscriptionPlan.objects.filter(is_active=True)


class MeView(generics.RetrieveUpdateAPIView):
    # Any logged-in owner can read their own status (incl. before paying) — the
    # client uses has_access to route to the payment screen vs the dashboard.
    # PATCH lets the owner set editable profile fields (e.g. whatsapp_source).
    permission_classes = [IsAuthenticated]
    serializer_class = OwnerSerializer

    def get_object(self):
        return self.request.user


class ActivateTestView(APIView):
    """DEV-ONLY: activate without a real Razorpay payment, so the flow is testable.
    Disabled when DEBUG is False — production uses VerifyView below."""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        if not settings.DEBUG:
            return Response({"detail": "Test activation is disabled in production."}, status=403)
        try:
            plan = SubscriptionPlan.objects.get(id=request.data.get("plan_id"), is_active=True)
        except SubscriptionPlan.DoesNotExist:
            return Response({"detail": "Invalid plan"}, status=400)
        _activate(request.user, plan)
        return Response({"detail": "activated"})


class VerifyPaymentView(APIView):
    """PRODUCTION: verify Razorpay's client-return signature, then activate."""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        d = request.data
        try:
            _rzp().utility.verify_payment_signature({
                "razorpay_order_id": d["razorpay_order_id"],
                "razorpay_payment_id": d["razorpay_payment_id"],
                "razorpay_signature": d["razorpay_signature"],
            })
        except Exception:
            return Response({"detail": "Payment verification failed."}, status=400)
        plan = request.user.subscription_plan
        if plan is None:
            return Response({"detail": "No plan associated with this order."}, status=400)
        _activate(request.user, plan)
        return Response({"detail": "activated"})


class CreateOrderView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        try:
            plan = SubscriptionPlan.objects.get(id=request.data.get("plan_id"), is_active=True)
        except SubscriptionPlan.DoesNotExist:
            return Response({"detail": "Invalid plan"}, status=400)

        order = _rzp().order.create({
            "amount": int(plan.price * 100),  # paise
            "currency": "INR",
            # notes ride along to the order.paid webhook — how we find the owner.
            "notes": {"owner_id": str(request.user.id), "plan_id": str(plan.id)},
        })
        request.user.subscription_plan = plan
        request.user.save(update_fields=["subscription_plan"])
        return Response({
            "order_id": order["id"],
            "amount": order["amount"],
            "currency": order["currency"],
            "key": settings.RAZORPAY_KEY_ID,
        })


@method_decorator(csrf_exempt, name="dispatch")
class WebhookView(APIView):
    """Authoritative activation. Signature IS the auth — no user session."""

    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        body = request.body  # raw bytes; parse ourselves to avoid DRF stream reuse
        signature = request.headers.get("X-Razorpay-Signature", "")
        try:
            _rzp().utility.verify_webhook_signature(
                body.decode(), signature, settings.RAZORPAY_WEBHOOK_SECRET
            )
        except Exception:
            return Response({"detail": "bad signature"}, status=400)

        data = json.loads(body)
        if data.get("event") == "order.paid":
            notes = data["payload"]["order"]["entity"].get("notes", {})
            try:
                owner = Owner.objects.get(id=notes.get("owner_id"))
                plan = SubscriptionPlan.objects.get(id=notes.get("plan_id"))
            except (Owner.DoesNotExist, SubscriptionPlan.DoesNotExist):
                return Response(status=200)  # ack; nothing to do
            _activate(owner, plan)
        return Response(status=200)
