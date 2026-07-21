from django.contrib import admin

from .models import Owner, SubscriptionPlan


@admin.register(SubscriptionPlan)
class SubscriptionPlanAdmin(admin.ModelAdmin):
    list_display = ["name", "price", "duration_days", "is_active"]
    list_editable = ["price", "duration_days", "is_active"]


@admin.register(Owner)
class OwnerAdmin(admin.ModelAdmin):
    list_display = [
        "email", "phone", "whatsapp_source", "pg_count",
        "subscription_status", "subscription_expiry", "is_approved",
    ]

    @admin.display(description="PGs")
    def pg_count(self, obj):
        return obj.pgs.count()
    list_editable = ["is_approved"]  # one-click manual approval
    list_filter = ["subscription_status", "is_approved"]
    search_fields = ["email", "phone"]
    readonly_fields = ["last_login", "date_joined"]
