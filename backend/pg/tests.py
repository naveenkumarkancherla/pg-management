from datetime import date, timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from .models import Berth, Floor, PGProperty, Payment, Room, Tenant
from .services import analytics, billing_period, due_date_for, sync_current_due, tenants_to_remind

Owner = get_user_model()


def _make_owner(email="o@x.com"):
    from django.utils import timezone
    return Owner.objects.create_user(
        email=email, password="pass12345", is_approved=True, subscription_status="active",
        subscription_expiry=timezone.now() + timedelta(days=30),
    )


def _berth(owner, rent=1000, status=Berth.VACANT):
    pg = PGProperty.objects.create(owner=owner, name="PG")
    floor = Floor.objects.create(pg=pg, name="1")
    room = Room.objects.create(floor=floor, number="101", rent_amount=rent)
    return Berth.objects.create(room=room, label="A", status=status)


class PaymentStatusTest(TestCase):
    def setUp(self):
        self.owner = _make_owner()
        self.tenant = Tenant.objects.create(owner=self.owner, name="T", phone="9", join_date=date(2026, 1, 5))

    def _pay(self, paid):
        return Payment.objects.create(
            tenant=self.tenant, month=7, year=2026, amount_due=Decimal("1000"),
            amount_paid=Decimal(paid),
        )

    def test_status_derivation(self):
        self.assertEqual(self._pay("0").status, Payment.UNPAID)
        self.tenant.payments.all().delete()
        self.assertEqual(self._pay("400").status, Payment.PARTIAL)
        self.tenant.payments.all().delete()
        self.assertEqual(self._pay("1000").status, Payment.PAID)
        self.tenant.payments.all().delete()
        self.assertEqual(self._pay("1200").status, Payment.PAID)  # overpay still paid

    def test_balance(self):
        self.assertEqual(self._pay("400").balance, Decimal("600"))


class CurrentStatusTest(TestCase):
    """The 'unpaid/partial' list must judge each tenant by their join-anchored cycle,
    not the calendar month — else a tenant fully paid in the previous (still-current)
    cycle is wrongly shown as unpaid while their card says 'paid'."""

    def setUp(self):
        from .services import current_status
        self.current_status = current_status
        self.owner = _make_owner()
        # today = 22nd; a tenant joined on the 23rd is still inside the PREVIOUS cycle
        self.today = date(2026, 7, 22)

    def _tenant(self, join, rent=5000):
        berth = _berth(self.owner, rent=rent, status=Berth.OCCUPIED)
        return Tenant.objects.create(owner=self.owner, name="T", phone="9", join_date=join, berth=berth)

    def test_prev_month_paid_reads_paid(self):
        t = self._tenant(date(2026, 3, 23))  # due day 23 > today 22 → cycle = June
        Payment.objects.create(tenant=t, month=6, year=2026, amount_due=Decimal("5000"), amount_paid=Decimal("5000"))
        self.assertEqual(self.current_status(t, self.today), Payment.PAID)

    def test_current_month_partial_reads_partial(self):
        t = self._tenant(date(2026, 3, 10))  # due day 10 <= today 22 → cycle = July
        Payment.objects.create(tenant=t, month=7, year=2026, amount_due=Decimal("5000"), amount_paid=Decimal("2500"))
        self.assertEqual(self.current_status(t, self.today), Payment.PARTIAL)

    def test_no_row_owes_rent_is_unpaid(self):
        t = self._tenant(date(2026, 3, 10))
        self.assertEqual(self.current_status(t, self.today), Payment.UNPAID)

    def test_rent_free_is_paid(self):
        t = self._tenant(date(2026, 3, 10), rent=0)
        self.assertEqual(self.current_status(t, self.today), Payment.PAID)


class SyncCurrentDueTest(TestCase):
    """Changing rent must re-open/close the current cycle's dues (the 'fully paid but
    shown partial' bug: paid == new rent but due frozen at the old higher rent)."""

    def setUp(self):
        self.owner = _make_owner()
        self.today = date(2026, 7, 22)
        self.berth = _berth(self.owner, rent=8000, status=Berth.OCCUPIED)
        self.tenant = Tenant.objects.create(
            owner=self.owner, name="Rajesh", phone="9", join_date=date(2026, 7, 20), berth=self.berth,
        )
        y, m = billing_period(self.tenant.join_date, self.today)
        self.payment = Payment.objects.create(
            tenant=self.tenant, month=m, year=y, amount_due=Decimal("8000"), amount_paid=Decimal("6000"),
        )

    def test_lowering_rent_marks_fully_paid(self):
        self.assertEqual(self.payment.status, Payment.PARTIAL)
        self.berth.room.rent_amount = Decimal("6000")  # rent dropped to what was paid
        self.berth.room.save()
        sync_current_due(self.tenant, today=self.today)
        self.payment.refresh_from_db()
        self.assertEqual(self.payment.amount_due, Decimal("6000"))
        self.assertEqual(self.payment.status, Payment.PAID)

    def test_genuine_underpayment_stays_partial(self):
        self.berth.room.rent_amount = Decimal("7000")  # still above the 6000 paid
        self.berth.room.save()
        sync_current_due(self.tenant, today=self.today)
        self.payment.refresh_from_db()
        self.assertEqual(self.payment.amount_due, Decimal("7000"))
        self.assertEqual(self.payment.status, Payment.PARTIAL)

    def test_paid_cycle_untouched(self):
        self.payment.amount_paid = Decimal("8000")  # fully paid at old rent
        self.payment.save()
        self.assertEqual(self.payment.status, Payment.PAID)
        self.berth.room.rent_amount = Decimal("6000")
        self.berth.room.save()
        sync_current_due(self.tenant, today=self.today)
        self.payment.refresh_from_db()
        self.assertEqual(self.payment.amount_due, Decimal("8000"))  # frozen; paid cycles never touched


class BerthConsistencyTest(TestCase):
    """move/vacate must keep berth.status in sync — the flow's whole point."""

    def setUp(self):
        self.owner = _make_owner()
        self.b1 = _berth(self.owner)
        # second berth in same room
        self.b2 = Berth.objects.create(room=self.b1.room, label="B")

    def test_occupy_move_vacate(self):
        from rest_framework.test import APIRequestFactory, force_authenticate
        from .views import TenantViewSet

        factory = APIRequestFactory()

        def call(action_name, data, pk=None, detail=True):
            view = TenantViewSet.as_view({"post": action_name} if detail else {"post": "create"})
            req = factory.post("/", data, format="json")
            force_authenticate(req, user=self.owner)
            return view(req, pk=pk) if pk else view(req)

        # create tenant on b1 → b1 occupied
        create = TenantViewSet.as_view({"post": "create"})
        req = APIRequestFactory().post("/", {
            "name": "T", "phone": "9", "join_date": "2026-01-05", "berth": self.b1.id,
        }, format="json")
        force_authenticate(req, user=self.owner)
        resp = create(req)
        self.assertEqual(resp.status_code, 201, resp.data)
        tid = resp.data["id"]
        self.b1.refresh_from_db()
        self.assertEqual(self.b1.status, Berth.OCCUPIED)

        # move to b2 → b1 vacant, b2 occupied
        call("move", {"berth_id": self.b2.id}, pk=tid)
        self.b1.refresh_from_db(); self.b2.refresh_from_db()
        self.assertEqual(self.b1.status, Berth.VACANT)
        self.assertEqual(self.b2.status, Berth.OCCUPIED)

        # vacate → b2 vacant, tenant detached + dated
        call("vacate", {}, pk=tid)
        self.b2.refresh_from_db()
        t = Tenant.objects.get(id=tid)
        self.assertEqual(self.b2.status, Berth.VACANT)
        self.assertIsNone(t.berth)
        self.assertEqual(t.vacate_date, date.today())


class ReminderSelectionTest(TestCase):
    def setUp(self):
        self.owner = _make_owner()

    def test_due_date_clamped(self):
        # join on the 31st, February → clamp to 28/29
        self.assertEqual(due_date_for(date(2026, 1, 31), date(2026, 2, 10)), date(2026, 2, 28))

    def test_reminds_from_due_date_within_window(self):
        today = date(2026, 7, 22)  # inside the window for a 21st due date (21–23)
        b = _berth(self.owner, status=Berth.OCCUPIED)
        # due on the 21st → 1 day into the 3-day window → reminded
        in_window = Tenant.objects.create(owner=self.owner, berth=b, name="Due", phone="1", join_date=date(2026, 1, 21))
        # due on the 25th → still in the future → NOT reminded (never before the due date)
        b2 = Berth.objects.create(room=b.room, label="B", status=Berth.OCCUPIED)
        Tenant.objects.create(owner=self.owner, berth=b2, name="Future", phone="2", join_date=date(2026, 1, 25))
        # due on the 15th → 7 days past due, window closed → NOT reminded
        b3 = Berth.objects.create(room=b.room, label="C", status=Berth.OCCUPIED)
        Tenant.objects.create(owner=self.owner, berth=b3, name="Old", phone="3", join_date=date(2026, 1, 15))

        picked = [t.name for t, _ in tenants_to_remind(self.owner, today)]
        self.assertEqual(picked, ["Due"])

        # once paid this month, drops out
        Payment.objects.create(tenant=in_window, month=7, year=2026, amount_due=1000, amount_paid=1000)
        self.assertEqual(tenants_to_remind(self.owner, today), [])


class AnalyticsTest(TestCase):
    def test_occupancy_and_revenue(self):
        owner = _make_owner()
        b = _berth(owner, status=Berth.OCCUPIED)
        Berth.objects.create(room=b.room, label="B", status=Berth.VACANT)
        t = Tenant.objects.create(owner=owner, berth=b, name="T", phone="9", join_date=date(2026, 1, 1))
        today = date.today()
        Payment.objects.create(tenant=t, month=today.month, year=today.year, amount_due=1000, amount_paid=1000)

        a = analytics(owner)
        self.assertEqual(a["berths_total"], 2)
        self.assertEqual(a["berths_occupied"], 1)
        self.assertEqual(a["occupancy_pct"], 50.0)
        self.assertEqual(a["revenue_this_month"], Decimal("1000"))
        self.assertEqual(a["collection"]["paid"]["count"], 1)
