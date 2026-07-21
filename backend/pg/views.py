from datetime import date
from decimal import Decimal

from django.db import transaction
from django.db.models import Q
from django.db.models.functions import Coalesce
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from owners.permissions import IsActiveOwner

from . import services
from .models import Berth, Expense, Floor, PGProperty, Payment, Room, Tenant
from .serializers import (
    BerthSerializer, ExpenseSerializer, FloorSerializer, PaymentSerializer,
    PGPropertySerializer, RoomSerializer, TenantSerializer,
)


class OwnedViewSet(viewsets.ModelViewSet):
    """Scopes every queryset to the requesting owner and rejects writes that
    reference another owner's parent object."""

    permission_classes = [IsActiveOwner]
    owner_lookup = "owner"      # ORM path from this model to the owning user
    parent_field = None         # payload FK whose .owner must match request.user

    def get_queryset(self):
        return self.queryset.filter(**{self.owner_lookup: self.request.user})

    def _check_parent(self, serializer):
        if self.parent_field:
            parent = serializer.validated_data.get(self.parent_field)
            if parent is not None and parent.owner != self.request.user:
                raise PermissionDenied(f"Not your {self.parent_field}")

    def perform_create(self, serializer):
        self._check_parent(serializer)
        serializer.save()

    def perform_update(self, serializer):
        self._check_parent(serializer)
        serializer.save()


class PGPropertyViewSet(OwnedViewSet):
    queryset = PGProperty.objects.all()
    serializer_class = PGPropertySerializer

    def perform_create(self, serializer):
        serializer.save(owner=self.request.user)


class FloorViewSet(OwnedViewSet):
    queryset = Floor.objects.all()
    serializer_class = FloorSerializer
    owner_lookup = "pg__owner"
    parent_field = "pg"

    def get_queryset(self):
        qs = super().get_queryset()
        if self.request.query_params.get("pg"):
            qs = qs.filter(pg_id=self.request.query_params["pg"])
        return qs

    @action(detail=True, methods=["post"])
    def generate_rooms(self, request, pk=None):
        """Bulk-add rooms. Accepts either a single config or a `groups` list so an owner
        can create several sharing types (each with its own rent) in one go, e.g.
        {"groups": [{"count":3,"berths_per_room":2,"rent_amount":5000,"room_type":"AC","prefix":"A"},
                    {"count":2,"berths_per_room":3,"rent_amount":4000}]}
        """
        floor = self.get_object()
        groups = request.data.get("groups")
        if not groups:
            groups = [request.data]  # single-config backward compatibility

        # Continue numbering per prefix across groups AND past existing rooms, so two
        # groups with the same prefix don't collide (e.g. 201,202 then 203..208).
        import re
        next_num = {}

        def seed(prefix):
            mx = 0
            for num in Room.objects.filter(floor=floor).values_list("number", flat=True):
                m = re.match(rf"^{re.escape(prefix)}(\d+)$", num)
                if m:
                    mx = max(mx, int(m.group(1)))
            return mx + 1

        created = []
        try:
            with transaction.atomic():
                for g in groups:
                    count = int(g["count"])
                    per_room = int(g["berths_per_room"])
                    rent = Decimal(str(g["rent_amount"]))
                    prefix = g.get("prefix", "")
                    room_type = g.get("room_type", "")
                    explicit = g.get("start_number")
                    if prefix not in next_num:
                        next_num[prefix] = seed(prefix)
                    start = int(explicit) if explicit not in (None, "", 0, "0") else next_num[prefix]
                    for i in range(count):
                        room = Room.objects.create(
                            floor=floor, number=f"{prefix}{start + i}",
                            rent_amount=rent, room_type=room_type,
                        )
                        Berth.objects.bulk_create(
                            [Berth(room=room, owner=room.owner, label=chr(65 + b)) for b in range(per_room)]
                        )
                        created.append(room.id)
                    next_num[prefix] = start + count
        except (KeyError, ValueError, TypeError):
            raise ValidationError("each group needs count, berths_per_room, rent_amount")
        return Response({"created_room_ids": created}, status=status.HTTP_201_CREATED)


class RoomViewSet(OwnedViewSet):
    queryset = Room.objects.all()
    serializer_class = RoomSerializer
    owner_lookup = "floor__pg__owner"
    parent_field = "floor"

    def get_queryset(self):
        qs = super().get_queryset().select_related("floor__pg")
        p = self.request.query_params
        if p.get("floor"):
            qs = qs.filter(floor_id=p["floor"])
        if p.get("pg"):
            qs = qs.filter(floor__pg_id=p["pg"])
        return qs

    def perform_create(self, serializer):
        # single "Add room" also creates its berths (labels A, B, C...)
        self._check_parent(serializer)
        berth_count = serializer.validated_data.pop("berth_count", 1)
        room = serializer.save()
        Berth.objects.bulk_create([Berth(room=room, owner=room.owner, label=chr(65 + i)) for i in range(berth_count)])


class BerthViewSet(OwnedViewSet):
    queryset = Berth.objects.all()
    serializer_class = BerthSerializer
    owner_lookup = "room__floor__pg__owner"
    parent_field = "room"

    def get_queryset(self):
        # select_related collapses room→floor→pg and the reverse tenant into one query
        # (was N+1 per berth → the main source of slowness).
        qs = super().get_queryset().select_related("room__floor__pg", "tenant")
        p = self.request.query_params
        if p.get("status"):
            qs = qs.filter(status=p["status"])
        if p.get("room"):
            qs = qs.filter(room_id=p["room"])
        if p.get("floor"):
            qs = qs.filter(room__floor_id=p["floor"])
        if p.get("pg"):
            qs = qs.filter(room__floor__pg_id=p["pg"])
        return qs.order_by("room__floor__name", "room__number", "label")


class TenantViewSet(OwnedViewSet):
    queryset = Tenant.objects.all()
    serializer_class = TenantSerializer

    def get_queryset(self):
        qs = super().get_queryset().select_related("berth__room__floor__pg").prefetch_related("payments")
        p = self.request.query_params
        if p.get("name"):
            qs = qs.filter(name__icontains=p["name"])
        if p.get("q"):  # combined search: name or phone
            qs = qs.filter(Q(name__icontains=p["q"]) | Q(phone__icontains=p["q"]))
        if p.get("floor"):
            qs = qs.filter(berth__room__floor_id=p["floor"])
        if p.get("pg"):
            qs = qs.filter(berth__room__floor__pg_id=p["pg"])
        if p.get("active") == "true":
            qs = qs.filter(berth__isnull=False, vacate_date__isnull=True)
        elif p.get("active") == "false":  # vacated tenants (kept for history), recent first
            qs = qs.filter(vacate_date__isnull=False).order_by("-vacate_date")
        # payment_status filters against the current month
        ps = p.get("payment_status")
        if ps in (Payment.PAID, Payment.PARTIAL):
            today = date.today()
            qs = qs.filter(payments__month=today.month, payments__year=today.year, payments__status=ps)
        elif ps == Payment.UNPAID:
            # "unpaid" includes partial — everyone NOT fully paid this month, excluding
            # rent-free beds (e.g. staff) which owe nothing.
            today = date.today()
            fully_paid_ids = Payment.objects.filter(
                month=today.month, year=today.year, status=Payment.PAID
            ).values_list("tenant_id", flat=True)
            eff_rent = Coalesce("berth__rent_amount", "berth__room__rent_amount")
            qs = (qs.filter(berth__isnull=False, vacate_date__isnull=True)
                    .annotate(_eff_rent=eff_rent).filter(_eff_rent__gt=0)
                    .exclude(id__in=fully_paid_ids))
        return qs.distinct()

    def perform_create(self, serializer):
        berth = serializer.validated_data.get("berth")
        self._validate_berth(berth)
        tenant = serializer.save(owner=self.request.user)
        if tenant.berth:
            tenant.berth.status = Berth.OCCUPIED
            tenant.berth.save(update_fields=["status"])

    def perform_update(self, serializer):
        # Editing profile fields is fine; berth changes must use the move endpoint
        # so berth.status stays consistent.
        if "berth" in serializer.validated_data and \
                serializer.validated_data["berth"] != serializer.instance.berth:
            raise ValidationError("Use the move endpoint to change berth")
        serializer.save()

    def _validate_berth(self, berth):
        if berth is None:
            return
        if berth.owner != self.request.user:
            raise PermissionDenied("Not your berth")
        if berth.status == Berth.OCCUPIED:
            raise ValidationError("Berth already occupied")

    @action(detail=True, methods=["post"])
    def move(self, request, pk=None):
        tenant = self.get_object()
        try:
            new_berth = Berth.objects.get(id=request.data["berth_id"])
        except (KeyError, Berth.DoesNotExist):
            raise ValidationError("valid berth_id required")
        self._validate_berth(new_berth)
        with transaction.atomic():
            if tenant.berth:
                tenant.berth.status = Berth.VACANT
                tenant.berth.save(update_fields=["status"])
            tenant.berth = new_berth
            tenant.vacate_date = None
            tenant.save(update_fields=["berth", "vacate_date"])
            new_berth.status = Berth.OCCUPIED
            new_berth.save(update_fields=["status"])
        return Response(self.get_serializer(tenant).data)

    @action(detail=True, methods=["post"])
    def vacate(self, request, pk=None):
        tenant = self.get_object()
        with transaction.atomic():
            if tenant.berth:
                tenant.berth.status = Berth.VACANT
                tenant.berth.save(update_fields=["status"])
            tenant.berth = None
            tenant.vacate_date = date.today()
            tenant.save(update_fields=["berth", "vacate_date"])
        return Response(self.get_serializer(tenant).data)

    @action(detail=True, methods=["post"])
    def collect(self, request, pk=None):
        """Record a manual collection for one month. ADDITIVE — the received amount is
        added to whatever was already paid, so partial payments accumulate toward the due."""
        tenant = self.get_object()
        from django.utils import timezone
        try:
            month = int(request.data["month"])
            year = int(request.data["year"])
            received = Decimal(str(request.data["amount_paid"]))
        except (KeyError, ValueError):
            raise ValidationError("month, year, amount_paid required")
        due_in = request.data.get("amount_due")
        default_due = Decimal(str(due_in)) if due_in is not None else (tenant.current_rent or Decimal("0"))

        payment, _ = Payment.objects.get_or_create(
            tenant=tenant, month=month, year=year,
            defaults={"amount_due": default_due, "amount_paid": Decimal("0")},
        )
        payment.amount_paid = (payment.amount_paid or Decimal("0")) + received
        payment.payment_date = timezone.now()
        payment.collected_by = request.user
        payment.save()  # status recomputed in Payment.save()
        return Response(PaymentSerializer(payment).data, status=status.HTTP_200_OK)

    @action(detail=True, methods=["get"])
    def payments(self, request, pk=None):
        tenant = self.get_object()
        return Response(PaymentSerializer(tenant.payments.all(), many=True).data)


class ExpenseViewSet(OwnedViewSet):
    """Owner's bills/expenses. Optional ?pg=, ?month=&year= filters."""
    queryset = Expense.objects.all()
    serializer_class = ExpenseSerializer
    parent_field = "pg"  # if a pg is given, it must belong to the owner

    def get_queryset(self):
        qs = super().get_queryset()
        p = self.request.query_params
        if p.get("pg"):
            qs = qs.filter(pg_id=p["pg"])
        if p.get("month") and p.get("year"):
            qs = qs.filter(spent_on__month=p["month"], spent_on__year=p["year"])
        return qs

    def perform_create(self, serializer):
        self._check_parent(serializer)
        serializer.save(owner=self.request.user)


class PaymentViewSet(viewsets.ReadOnlyModelViewSet):
    """Read + filter only. Writes go through Tenant.collect (single audited path)."""

    permission_classes = [IsActiveOwner]
    serializer_class = PaymentSerializer
    queryset = Payment.objects.all()

    def get_queryset(self):
        qs = self.queryset.filter(tenant__owner=self.request.user).select_related("tenant")
        p = self.request.query_params
        for key, field in (("tenant", "tenant_id"), ("status", "status"),
                           ("month", "month"), ("year", "year")):
            if p.get(key):
                qs = qs.filter(**{field: p[key]})
        return qs


class AnalyticsView(APIView):
    permission_classes = [IsActiveOwner]

    def get(self, request):
        return Response(services.analytics(request.user, request.query_params.get("pg")))
