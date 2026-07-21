from django.contrib.auth.models import AbstractUser
from django.db import models
from django.utils import timezone

from .managers import OwnerManager


class SubscriptionPlan(models.Model):
    name = models.CharField(max_length=100)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    duration_days = models.PositiveIntegerField()
    features = models.JSONField(default=dict, blank=True)
    is_active = models.BooleanField(default=True)

    def __str__(self):
        return f"{self.name} (₹{self.price}/{self.duration_days}d)"


class Owner(AbstractUser):
    username = None
    email = models.EmailField(unique=True)
    phone = models.CharField(max_length=20, blank=True)
    # WhatsApp sender (Gupshup source), per owner. Blank = fall back to GUPSHUP_SOURCE env.
    whatsapp_source = models.CharField(max_length=20, blank=True)
    kyc_details = models.JSONField(default=dict, blank=True)

    subscription_plan = models.ForeignKey(
        SubscriptionPlan, null=True, blank=True, on_delete=models.SET_NULL
    )
    STATUS_CHOICES = [("pending", "pending"), ("active", "active"), ("expired", "expired")]
    subscription_status = models.CharField(max_length=10, choices=STATUS_CHOICES, default="pending")
    subscription_expiry = models.DateTimeField(null=True, blank=True)
    is_approved = models.BooleanField(default=False)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = []

    objects = OwnerManager()

    def has_active_subscription(self):
        return (
            self.subscription_status == "active"
            and self.subscription_expiry is not None
            and self.subscription_expiry > timezone.now()
        )

    def __str__(self):
        return self.email
