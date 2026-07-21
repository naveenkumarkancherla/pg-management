from datetime import date, timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from .models import Berth, Floor, PGProperty, Payment, Room, Tenant
from .services import analytics, due_date_for, tenants_to_remind

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

    def test_only_unpaid_active_due_soon(self):
        today = date(2026, 7, 5)
        b = _berth(self.owner, status=Berth.OCCUPIED)
        # due on the 7th → within 3 days of the 5th
        due_soon = Tenant.objects.create(owner=self.owner, berth=b, name="Due", phone="1", join_date=date(2026, 1, 7))
        # due on the 25th → too far off
        b2 = Berth.objects.create(room=b.room, label="B", status=Berth.OCCUPIED)
        Tenant.objects.create(owner=self.owner, berth=b2, name="Later", phone="2", join_date=date(2026, 1, 25))

        picked = [t.name for t, _ in tenants_to_remind(self.owner, today)]
        self.assertEqual(picked, ["Due"])

        # once paid this month, drops out
        Payment.objects.create(tenant=due_soon, month=7, year=2026, amount_due=1000, amount_paid=1000)
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
