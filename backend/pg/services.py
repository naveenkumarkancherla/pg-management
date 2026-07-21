"""Pure-ish domain logic, kept out of views/commands so it can be unit-tested."""
import calendar
from datetime import date
from decimal import Decimal

from django.db.models import Sum

from .models import Berth, Expense, Payment, Tenant

REMIND_BEFORE_DAYS = 3  # ponytail: constant, not config — change here if it ever varies


def due_date_for(join_date, ref):
    """Rent due on the tenant's join day-of-month, clamped to the month length."""
    last = calendar.monthrange(ref.year, ref.month)[1]
    return date(ref.year, ref.month, min(join_date.day, last))


def billing_period(join_date, today):
    """The current rent cycle for a tenant, anchored to their join day (not the
    calendar month). Returns (year, month) of the period start.
    e.g. joined on the 15th: on Jul 20 → (2026, 7); on Jul 10 → (2026, 6) —
    still inside the Jun-15→Jul-14 cycle until the 15th ticks over."""
    if not join_date:
        return today.year, today.month
    last = calendar.monthrange(today.year, today.month)[1]
    due_day = min(join_date.day, last)
    if today.day >= due_day:
        return today.year, today.month
    return (today.year, today.month - 1) if today.month > 1 else (today.year - 1, 12)


def tenants_to_remind(owner, today):
    """Active tenants whose rent is due within REMIND_BEFORE_DAYS (or overdue) and
    not yet marked paid for the current month."""
    out = []
    active = Tenant.objects.filter(owner=owner, berth__isnull=False, vacate_date__isnull=True)
    for t in active.select_related("berth__room"):
        due = due_date_for(t.join_date, today)
        if (due - today).days > REMIND_BEFORE_DAYS:
            continue  # not due yet
        paid = Payment.objects.filter(
            tenant=t, month=today.month, year=today.year, status=Payment.PAID
        ).exists()
        if not paid:
            out.append((t, due))
    return out


def _revenue(owner, year, month):
    agg = Payment.objects.filter(tenant__owner=owner, year=year, month=month).aggregate(
        s=Sum("amount_paid")
    )
    return agg["s"] or Decimal("0")


def analytics(owner, pg_id=None):
    berths = Berth.objects.filter(room__floor__pg__owner=owner)
    if pg_id:
        berths = berths.filter(room__floor__pg_id=pg_id)
    total = berths.count()
    occupied = berths.filter(status=Berth.OCCUPIED).count()

    today = date.today()
    prev_year, prev_month = (today.year, today.month - 1) if today.month > 1 else (today.year - 1, 12)

    cur = Payment.objects.filter(tenant__owner=owner, year=today.year, month=today.month)
    if pg_id:
        cur = cur.filter(tenant__berth__room__floor__pg_id=pg_id)
    breakdown = {s: {"count": 0, "amount": Decimal("0")} for s in ("paid", "partial", "unpaid")}
    for p in cur:
        b = breakdown[p.status]
        b["count"] += 1
        b["amount"] += p.amount_paid

    # churn = tenants vacated this month (owner-wide; vacated tenants hold no berth to scope by pg)
    churn = Tenant.objects.filter(
        owner=owner, vacate_date__year=today.year, vacate_date__month=today.month
    ).count()
    active = Tenant.objects.filter(owner=owner, berth__isnull=False, vacate_date__isnull=True).count()

    # spent this month (bills/expenses), month-specific like the rest of the dashboard
    exp = Expense.objects.filter(owner=owner, spent_on__year=today.year, spent_on__month=today.month)
    if pg_id:
        exp = exp.filter(pg_id=pg_id)
    spent = exp.aggregate(s=Sum("amount"))["s"] or Decimal("0")

    return {
        "occupancy_pct": round(occupied / total * 100, 1) if total else 0,
        "berths_total": total,
        "berths_occupied": occupied,
        "berths_vacant": total - occupied,
        "inmates": active,
        "revenue_this_month": _revenue(owner, today.year, today.month),
        "revenue_last_month": _revenue(owner, prev_year, prev_month),
        "collection": breakdown,
        "vacated_this_month": churn,
        "expenses_this_month": spent,
    }
