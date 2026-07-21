# PG Management

Owner-only PG management app. **This slice = Phase 0 + 1**: owner registration → KYC →
Razorpay subscription → JWT login → access-gated API. Later phases (property/tenant/reminders/
analytics) build on this.

## Backend (Django + DRF)

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env          # fill Supabase DATABASE_URL + Razorpay keys (or leave DB blank → sqlite)
python manage.py migrate
python manage.py createsuperuser
python manage.py runserver --nothreading   # --nothreading reuses one DB connection → ~5x faster in dev
```

> **Dev speed:** the threaded dev server opens a new Supabase connection per request
> (~1.4s each). `--nothreading` keeps one persistent connection (~0.28s). Production uses
> gunicorn (see `Procfile`), which reuses connections per worker automatically.
> For even lower latency, use the Supabase **connection pooler** string and host the project
> in a region close to your users.

Django admin (`/admin/`) is the super-admin panel: create `SubscriptionPlan`s and flip
`is_approved` on owners.

### API
| Endpoint | Auth | Notes |
|---|---|---|
| `POST /api/auth/register/` | none | email, password, phone, kyc_details |
| `POST /api/auth/login/` `POST /api/auth/refresh/` | none | JWT |
| `GET /api/plans/` | none | active plans |
| `POST /api/subscription/create-order/` | JWT | body `{plan_id}` → Razorpay order |
| `POST /api/subscription/webhook/` | signature | `order.paid` → activates subscription |
| `GET /api/me/` | JWT + approved + active | profile; the access gate |

Access model: **payment** sets subscription active; **admin** flips `is_approved` (KYC vetting).
`/api/me/` (and every future endpoint) needs both — via `owners.permissions.IsActiveOwner`.

### Razorpay webhook
Point a Razorpay webhook at `POST /api/subscription/webhook/` for event `order.paid`, using
`RAZORPAY_WEBHOOK_SECRET`. Use ngrok to expose localhost during testing.

## Property, tenants, payments, analytics (Phases 2–6)

All under `/api/`, all require JWT + approved + active (`IsActiveOwner`), all scoped to the
owner. Standard REST CRUD via routers: `pgs/`, `floors/`, `rooms/`, `berths/`, `tenants/`,
`payments/` (read-only). Plus actions:

| Endpoint | Purpose |
|---|---|
| `POST /api/floors/{id}/generate_rooms/` | Bulk-add. Body `{count, berths_per_room, rent_amount, start_number?, prefix?}`. Rooms numbered `prefix+n`, berths labelled A, B, C… |
| `GET /api/berths/?status=vacant&floor=&room=&pg=` | Vacancy filters. |
| `GET /api/tenants/?name=&floor=&pg=&active=true&payment_status=paid\|partial\|unpaid` | Tenant filters (payment_status = current month). |
| `POST /api/tenants/` (with `berth`) | Add tenant; berth auto-marked occupied. |
| `POST /api/tenants/{id}/move/` | Body `{berth_id}`. Frees old berth, occupies new. |
| `POST /api/tenants/{id}/vacate/` | Frees berth, detaches tenant, stamps vacate_date. |
| `POST /api/tenants/{id}/collect/` | Body `{month, year, amount_paid, amount_due?}`. Idempotent per month; status (paid/partial/unpaid) derived server-side. |
| `GET /api/tenants/{id}/payments/` | Per-tenant history. |
| `GET /api/analytics/?pg=` | Occupancy %, vacant/filled, revenue this vs last month, collection breakdown. |

Berth/room/tenant chain is owner-scoped; you cannot reference another owner's parent object.
Multi-PG "switcher" is a client concern — filter every list by `?pg=` and hide the selector
when the owner has one PG.

## Reminders (Phase 5) — cron, no Celery

```bash
python manage.py send_reminders      # daily: WhatsApp (Gupshup) → SMS (MSG91) fallback
python manage.py expire_subscriptions
```
Set these as **daily scheduled jobs** on Railway/Render. Providers are env-gated
(`GUPSHUP_*`, `MSG91_API_KEY`); with none set, sends log `no_provider`. Due date = tenant's
join day-of-month; reminds when due within 3 days (or overdue) and not paid this month.
Every send is recorded in `ReminderLog` (no duplicate sends per day).

## Deploy (Phase 7)

`Procfile` runs `migrate` + `collectstatic` on release, gunicorn for web; whitenoise serves
admin static. In prod set `DEBUG=False`, `ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS`, real
`DATABASE_URL` (Supabase). Subscription-expiry lockout is automatic via `IsActiveOwner`.

## Mobile (Flutter)

Flutter isn't installed on this machine. Once it is, generate the platform folders around the
existing `lib/`:

```bash
cd mobile
flutter create --org com.yourcompany --project-name pg_management .
flutter pub get
flutter run --dart-define=API_BASE=http://10.0.2.2:8000   # 10.0.2.2 = host from Android emulator
```

Full owner app in `lib/` (flat, no state-mgmt lib — `setState` + one `Api` client):
`api.dart`, `main.dart` (auth gate), `auth_screen.dart`, `home_screen.dart` (PG switcher —
auto-hidden for single-PG owners — + bottom nav), `dashboard_tab.dart` (analytics),
`rooms_tab.dart` (floors/rooms/berths, add floor, generate rooms), `tenants_tab.dart`
(list + all/active/unpaid filters, collect/move/vacate/history), `add_tenant_screen.dart`.

**Not compile-checked** — Flutter isn't installed here. After installing the SDK, run
`flutter analyze` and fix anything it flags (report back and I'll fix).

```bash
cd mobile
flutter create --org com.yourcompany --project-name pg_management .   # generate platform folders around lib/
flutter pub get
# start the backend first (cd ../backend && python manage.py runserver), then:
flutter run --dart-define=API_BASE=http://10.0.2.2:8000   # Android emulator; iOS sim/desktop use http://127.0.0.1:8000
```

**Ready-to-use login:** `test@pg.com` / `test12345` (approved + active, with a seeded PG).
New sign-ups via the app land unapproved/unpaid until payment + admin approval.

## Tests
```bash
cd backend && python manage.py test owners
```
