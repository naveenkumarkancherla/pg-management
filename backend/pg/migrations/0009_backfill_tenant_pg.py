from django.db import migrations


def backfill_pg(apps, schema_editor):
    Tenant = apps.get_model("pg", "Tenant")
    # Active tenants still hold a berth → derive their PG from the berth chain.
    # Already-vacated tenants have no berth, so their PG is unknowable here and
    # stays null (they simply won't appear under a per-PG vacated filter).
    for t in Tenant.objects.filter(berth__isnull=False, pg__isnull=True).select_related(
        "berth__room__floor"
    ):
        t.pg_id = t.berth.room.floor.pg_id
        t.save(update_fields=["pg"])


class Migration(migrations.Migration):
    dependencies = [("pg", "0008_tenant_pg")]
    operations = [migrations.RunPython(backfill_pg, migrations.RunPython.noop)]
