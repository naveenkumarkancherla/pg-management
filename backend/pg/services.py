"""Pure-ish domain logic, kept out of views/commands so it can be unit-tested."""
import calendar
from datetime import date
from decimal import Decimal

from django.db.models import Sum
from django.db.models.functions import ExtractMonth, ExtractYear

from .models import Berth, Expense, Payment, Tenant

REMIND_WINDOW_DAYS = 3  # remind on the due day and the next 2 days (e.g. due 21st → 21–23)


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


def current_status(tenant, today=None):
    """Paid/partial/unpaid for the tenant's CURRENT join-anchored cycle — the same
    period the tenant card shows. Uses prefetched payments (no extra query).
    Mirrors TenantSerializer.get_current_payment so list filters and cards agree."""
    today = today or date.today()
    rent = tenant.current_rent or 0
    year, month = billing_period(tenant.join_date, today)
    p = next((x for x in tenant.payments.all() if x.month == month and x.year == year), None)
    if p is None:
        return Payment.PAID if rent <= 0 else Payment.UNPAID  # nothing billed yet
    return p.status


def sync_current_due(tenant, today=None):
    """Keep the current OPEN (unpaid/partial) cycle's amount_due in step with the
    tenant's current rent, so lowering/raising a berth or room rent immediately
    corrects what's owed. Fully-paid cycles are never touched."""
    today = today or date.today()
    if not tenant.is_active:
        return
    rent = tenant.current_rent
    if rent is None:
        return
    year, month = billing_period(tenant.join_date, today)
    p = Payment.objects.filter(tenant=tenant, month=month, year=year).first()
    if p and p.status != Payment.PAID and p.amount_due != rent:
        p.amount_due = rent
        p.save()  # status recomputed in Payment.save()


def tenants_to_remind(owner, today):
    """Active tenants whose rent is unpaid, reminded only on the due day and the next
    REMIND_WINDOW_DAYS-1 days (never before the due date; e.g. due 21st → 21st–23rd)."""
    out = []
    active = Tenant.objects.filter(owner=owner, berth__isnull=False, vacate_date__isnull=True)
    for t in active.select_related("berth__room"):
        due = due_date_for(t.join_date, today)
        days_since_due = (today - due).days
        if not (0 <= days_since_due < REMIND_WINDOW_DAYS):
            continue  # only from the due date, for a 3-day window
        paid = Payment.objects.filter(
            tenant=t, month=today.month, year=today.year, status=Payment.PAID
        ).exists()
        if not paid:
            out.append((t, due))
    return out


def monthly_summary(owner, pg_id=None):
    """Income (rent collected) per month, plus expenses and net, newest first.
    Income is grouped by the payment's billing cycle (month/year); expenses by spent_on."""
    pay = Payment.objects.filter(tenant__owner=owner)
    exp = Expense.objects.filter(owner=owner)
    if pg_id:
        pay = pay.filter(tenant__berth__room__floor__pg_id=pg_id)
        exp = exp.filter(pg_id=pg_id)

    merged = {}  # (year, month) -> {"income", "spent"}
    for r in pay.values("year", "month").annotate(s=Sum("amount_paid")):
        merged[(r["year"], r["month"])] = {"income": r["s"] or Decimal("0"), "spent": Decimal("0")}
    for r in (exp.annotate(y=ExtractYear("spent_on"), m=ExtractMonth("spent_on"))
                 .values("y", "m").annotate(s=Sum("amount"))):
        merged.setdefault((r["y"], r["m"]), {"income": Decimal("0"), "spent": Decimal("0")})["spent"] = r["s"] or Decimal("0")

    out = []
    for (year, month) in sorted(merged, reverse=True):
        income = merged[(year, month)]["income"]
        spent = merged[(year, month)]["spent"]
        out.append({"year": year, "month": month, "income": income, "spent": spent, "net": income - spent})
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
