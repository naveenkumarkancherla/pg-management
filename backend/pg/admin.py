from django.contrib import admin

from .models import Berth, Floor, PGProperty, Payment, ReminderLog, Room, Tenant

admin.site.register([PGProperty, Floor, Room, Berth, ReminderLog])


@admin.register(Tenant)
class TenantAdmin(admin.ModelAdmin):
    list_display = ["name", "phone", "berth", "join_date", "vacate_date"]
    list_filter = ["owner", "vacate_date"]
    search_fields = ["name", "phone"]


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = ["tenant", "month", "year", "amount_due", "amount_paid", "status"]
    list_filter = ["status", "year", "month"]
