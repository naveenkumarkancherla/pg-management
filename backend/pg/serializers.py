from rest_framework import serializers

from .models import Berth, Expense, Floor, PGProperty, Payment, Room, Tenant


class PGPropertySerializer(serializers.ModelSerializer):
    class Meta:
        model = PGProperty
        fields = ["id", "name", "address"]


class FloorSerializer(serializers.ModelSerializer):
    class Meta:
        model = Floor
        fields = ["id", "pg", "name"]


class RoomSerializer(serializers.ModelSerializer):
    berth_count = serializers.IntegerField(write_only=True, required=False, min_value=1, default=1)

    class Meta:
        model = Room
        fields = ["id", "floor", "pg", "number", "rent_amount", "room_type", "berth_count"]
        extra_kwargs = {"pg": {"read_only": True}}  # derived from floor automatically


class BerthSerializer(serializers.ModelSerializer):
    room_number = serializers.CharField(source="room.number", read_only=True)
    floor_name = serializers.CharField(source="room.floor.name", read_only=True)
    pg_name = serializers.CharField(source="room.floor.pg.name", read_only=True)
    rent = serializers.SerializerMethodField()  # effective per-berth rent (override or room rent)
    tenant_name = serializers.SerializerMethodField()

    class Meta:
        model = Berth
        # rent_amount = optional per-berth override (writable); rent = effective value (read)
        fields = ["id", "room", "label", "status", "rent_amount", "room_number", "floor_name", "pg_name", "rent", "tenant_name"]

    def get_rent(self, obj):
        return obj.effective_rent

    def get_tenant_name(self, obj):
        return obj.tenant.name if hasattr(obj, "tenant") else None


class TenantSerializer(serializers.ModelSerializer):
    location = serializers.SerializerMethodField()
    current_rent = serializers.DecimalField(max_digits=10, decimal_places=2, read_only=True)
    is_active = serializers.BooleanField(read_only=True)
    current_payment = serializers.SerializerMethodField()

    class Meta:
        model = Tenant
        fields = [
            "id", "berth", "name", "phone", "id_proof", "whatsapp",
            "join_date", "deposit_amount", "vacate_date", "created_at",
            "location", "current_rent", "is_active", "current_payment",
        ]
        read_only_fields = ["vacate_date", "created_at"]  # set by the system, not free-form

    def get_location(self, obj):
        if not obj.berth:
            return None
        b = obj.berth
        return f"{b.room.floor.pg.name} / {b.room.floor.name} / {b.room.number} / {b.label}"

    def get_current_payment(self, obj):
        # current join-anchored cycle: due / paid / pending / status + the period (month, year)
        from datetime import date

        from .services import billing_period
        today = date.today()
        rent = obj.current_rent or 0
        due_day = obj.join_date.day if obj.join_date else 1
        year, month = billing_period(obj.join_date, today)
        # use the prefetched payments (no extra query per tenant)
        p = next((x for x in obj.payments.all() if x.month == month and x.year == year), None)
        base = {"due_day": due_day, "period_month": month, "period_year": year}
        if p is None:
            # no rent (e.g. a staff bed) → nothing owed → treat as paid
            status = "paid" if rent <= 0 else "unpaid"
            return {**base, "due": float(rent), "paid": 0.0, "pending": float(rent), "status": status}
        return {
            **base,
            "due": float(p.amount_due),
            "paid": float(p.amount_paid),
            "pending": float(p.amount_due - p.amount_paid),
            "status": p.status,
        }


class ExpenseSerializer(serializers.ModelSerializer):
    class Meta:
        model = Expense
        fields = ["id", "pg", "title", "category", "amount", "spent_on", "created_at"]
        read_only_fields = ["created_at"]


class PaymentSerializer(serializers.ModelSerializer):
    balance = serializers.DecimalField(max_digits=10, decimal_places=2, read_only=True)
    tenant_name = serializers.CharField(source="tenant.name", read_only=True)

    class Meta:
        model = Payment
        fields = [
            "id", "tenant", "tenant_name", "month", "year",
            "amount_due", "amount_paid", "status", "payment_date", "balance",
        ]
        read_only_fields = fields
