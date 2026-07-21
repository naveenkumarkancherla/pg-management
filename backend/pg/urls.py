from django.urls import include, path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("pgs", views.PGPropertyViewSet)
router.register("floors", views.FloorViewSet)
router.register("rooms", views.RoomViewSet)
router.register("berths", views.BerthViewSet)
router.register("tenants", views.TenantViewSet)
router.register("payments", views.PaymentViewSet)
router.register("expenses", views.ExpenseViewSet)

urlpatterns = [
    path("", include(router.urls)),
    path("analytics/", views.AnalyticsView.as_view()),
]
