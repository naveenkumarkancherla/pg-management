"""Create this month's rent-due rows for every active tenant (idempotent).

    python manage.py generate_dues

Run on the 1st of each month via host cron. amount_due = current berth's room rent.
"""
from django.core.management.base import BaseCommand
from django.utils import timezone

from pg.models import Payment, Tenant
from pg.services import billing_period


class Command(BaseCommand):
    help = "Auto-generate the current cycle's rent-due row for active tenants (join-anchored)."

    def handle(self, *args, **opts):
        today = timezone.localdate()
        created = 0
        active = Tenant.objects.filter(berth__isnull=False, vacate_date__isnull=True).select_related("berth__room")
        for t in active:
            year, month = billing_period(t.join_date, today)
            _, was_created = Payment.objects.get_or_create(
                tenant=t, month=month, year=year,
                defaults={"amount_due": t.current_rent or 0, "amount_paid": 0},
            )
            created += was_created
        self.stdout.write(self.style.SUCCESS(f"Dues created: {created}"))
