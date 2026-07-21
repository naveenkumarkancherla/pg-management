"""Daily rent-reminder job. Run once a day via host cron (Railway/Render scheduled job):

    python manage.py send_reminders

ponytail: a cron-triggered command, not Celery+Redis. Once a day needs no worker/broker.
"""
from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.utils import timezone

from pg.models import ReminderLog
from pg.notifications import send_reminder
from pg.services import tenants_to_remind

Owner = get_user_model()


class Command(BaseCommand):
    help = "Send rent-due reminders to tenants (WhatsApp/SMS)."

    def handle(self, *args, **opts):
        today = timezone.localdate()
        sent = 0
        for owner in Owner.objects.filter(is_approved=True):
            for tenant, due in tenants_to_remind(owner, today):
                # skip if we already logged a send for this tenant today
                if ReminderLog.objects.filter(tenant=tenant, sent_date=today).exists():
                    continue
                text = (
                    f"Hi {tenant.name}, your rent of ₹{tenant.current_rent} is due on "
                    f"{due:%d %b}. Please pay on time. — {owner.email}"
                )
                channel, status = send_reminder(
                    tenant.whatsapp or tenant.phone, text, owner.whatsapp_source
                )
                ReminderLog.objects.create(
                    tenant=tenant, sent_date=today, channel=channel, status=status
                )
                sent += 1
        self.stdout.write(self.style.SUCCESS(f"Reminders processed: {sent}"))
