from django.conf import settings
from django.db import models
from django.utils import timezone

# Ownership: PGProperty and Tenant carry a direct owner FK (Tenant keeps it after a
# berth is vacated). Floor/Room/Berth/Payment expose an `owner` property that walks
# the chain, so every view can check `obj.owner == request.user` uniformly.


class PGProperty(models.Model):
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="pgs")
    name = models.CharField(max_length=120)
    address = models.TextField(blank=True)

    class Meta:
        verbose_name = "PG property"
        verbose_name_plural = "PG properties"

    def __str__(self):
        return self.name


class Floor(models.Model):
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="floors", null=True, blank=True)
    pg = models.ForeignKey(PGProperty, on_delete=models.CASCADE, related_name="floors")
    name = models.CharField(max_length=50)  # "Ground", "1", "G1" — matches how owner names them

    def save(self, *args, **kwargs):
        if self.pg_id and self.owner_id is None:
            self.owner_id = self.pg.owner_id
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.pg.name} / {self.name}"


class Room(models.Model):
    # denormalised parent chain: every table carries owner_id (+ pg_id here)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="rooms", null=True, blank=True)
    pg = models.ForeignKey(PGProperty, on_delete=models.CASCADE, related_name="rooms", null=True, blank=True)
    floor = models.ForeignKey(Floor, on_delete=models.CASCADE, related_name="rooms")
    number = models.CharField(max_length=30)
    rent_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    room_type = models.CharField(max_length=30, blank=True)  # single/double/triple...

    def save(self, *args, **kwargs):
        # keep pg + owner in sync with the floor automatically
        if self.floor_id:
            if self.pg_id is None:
                self.pg_id = self.floor.pg_id
            if self.owner_id is None:
                self.owner_id = self.floor.pg.owner_id
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.floor} / {self.number}"


class Berth(models.Model):
    VACANT, OCCUPIED = "vacant", "occupied"
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="berths", null=True, blank=True)
    room = models.ForeignKey(Room, on_delete=models.CASCADE, related_name="berths")
    label = models.CharField(max_length=10)  # "A", "B", "1"...
    status = models.CharField(
        max_length=10, choices=[(VACANT, VACANT), (OCCUPIED, OCCUPIED)], default=VACANT
    )
    # per-berth rent override; null = fall back to the room's rent
    rent_amount = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)

    def save(self, *args, **kwargs):
        if self.room_id and self.owner_id is None:
            self.owner_id = self.room.floor.pg.owner_id
        super().save(*args, **kwargs)

    @property
    def effective_rent(self):
        return self.rent_amount if self.rent_amount is not None else self.room.rent_amount

    def __str__(self):
        return f"{self.room} / {self.label}"


class Tenant(models.Model):
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="tenants")
    # nullable: a vacated tenant keeps history but holds no berth.
    berth = models.OneToOneField(
        Berth, on_delete=models.SET_NULL, null=True, blank=True, related_name="tenant"
    )
    name = models.CharField(max_length=120)
    phone = models.CharField(max_length=20)
    id_proof = models.FileField(upload_to="id_proofs/", null=True, blank=True)
    whatsapp = models.CharField(max_length=20, blank=True)  # for WhatsApp reminders
    join_date = models.DateField()
    deposit_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    vacate_date = models.DateField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, null=True)  # when the tenant was added

    @property
    def current_rent(self):
        return self.berth.effective_rent if self.berth else None

    @property
    def is_active(self):
        return self.berth_id is not None and self.vacate_date is None

    def __str__(self):
        return self.name


class Payment(models.Model):
    PAID, PARTIAL, UNPAID = "paid", "partial", "unpaid"
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="payments", null=True, blank=True)
    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE, related_name="payments")
    month = models.PositiveSmallIntegerField()  # 1-12
    year = models.PositiveSmallIntegerField()
    amount_due = models.DecimalField(max_digits=10, decimal_places=2)
    amount_paid = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    status = models.CharField(max_length=10, default=UNPAID)
    payment_date = models.DateTimeField(null=True, blank=True)
    collected_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="collected_payments",
    )

    class Meta:
        unique_together = ("tenant", "month", "year")
        ordering = ["-year", "-month"]

    @property
    def balance(self):
        return self.amount_due - self.amount_paid

    def save(self, *args, **kwargs):
        if self.tenant_id and self.owner_id is None:
            self.owner_id = self.tenant.owner_id
        # status is derived, never trusted from input.
        if self.amount_paid <= 0:
            self.status = self.UNPAID
        elif self.amount_paid < self.amount_due:
            self.status = self.PARTIAL
        else:
            self.status = self.PAID
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.tenant} {self.month}/{self.year} {self.status}"


class Expense(models.Model):
    """A bill/expense the owner records (electricity, maintenance, groceries…).
    Optionally scoped to a PG; feeds the dashboard's "spent this month"."""
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="expenses")
    pg = models.ForeignKey(PGProperty, on_delete=models.CASCADE, related_name="expenses", null=True, blank=True)
    title = models.CharField(max_length=120)
    category = models.CharField(max_length=40, blank=True)  # e.g. utilities, maintenance
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    spent_on = models.DateField(default=timezone.localdate)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-spent_on", "-created_at"]

    def __str__(self):
        return f"{self.title} ₹{self.amount}"


class ReminderLog(models.Model):
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="reminder_logs", null=True, blank=True)
    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE, related_name="reminders")
    sent_date = models.DateField()
    channel = models.CharField(max_length=20)  # whatsapp / sms
    status = models.CharField(max_length=20)  # sent / failed / no_provider

    class Meta:
        ordering = ["-sent_date"]

    def save(self, *args, **kwargs):
        if self.tenant_id and self.owner_id is None:
            self.owner_id = self.tenant.owner_id
        super().save(*args, **kwargs)
