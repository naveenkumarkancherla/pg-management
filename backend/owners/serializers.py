from django.contrib.auth import get_user_model
from rest_framework import serializers

import re

from .models import SubscriptionPlan

Owner = get_user_model()

# Indian mobile: 10 digits starting 6-9, optional +91 / 91 / 0 prefix.
_PHONE_RE = re.compile(r"^(?:\+?91|0)?[6-9]\d{9}$")


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)
    phone = serializers.CharField()

    class Meta:
        model = Owner
        fields = ["id", "email", "password", "phone", "whatsapp_source", "kyc_details"]

    def validate_phone(self, value):
        digits = re.sub(r"[\s-]", "", value)
        if not _PHONE_RE.match(digits):
            raise serializers.ValidationError("Enter a valid 10-digit mobile number.")
        return digits[-10:]  # store the bare 10-digit number

    def create(self, validated_data):
        return Owner.objects.create_user(**validated_data)


class PlanSerializer(serializers.ModelSerializer):
    class Meta:
        model = SubscriptionPlan
        fields = ["id", "name", "price", "duration_days", "features"]


class OwnerSerializer(serializers.ModelSerializer):
    has_access = serializers.SerializerMethodField()

    class Meta:
        model = Owner
        fields = [
            "id", "email", "phone", "whatsapp_source", "kyc_details", "subscription_plan",
            "subscription_status", "subscription_expiry", "is_approved", "has_access",
        ]
        # Everything read-only except the fields the owner may edit on their profile.
        read_only_fields = [f for f in fields if f not in ("phone", "whatsapp_source")]

    def get_has_access(self, obj):
        return obj.is_approved and obj.has_active_subscription()
