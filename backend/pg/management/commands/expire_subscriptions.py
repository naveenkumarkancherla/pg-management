"""Flip past-expiry owners to 'expired' so admin/analytics reflect reality.

Access is already blocked live by IsActiveOwner (it checks the expiry date), so this is
just for accurate status reporting. Run daily alongside send_reminders.
"""
from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.utils import timezone

Owner = get_user_model()


class Command(BaseCommand):
    help = "Mark owners whose subscription_expiry has passed as expired."

    def handle(self, *args, **opts):
        n = Owner.objects.filter(
            subscription_status="active", subscription_expiry__lt=timezone.now()
        ).update(subscription_status="expired")
        self.stdout.write(self.style.SUCCESS(f"Expired: {n}"))
