from django.urls import path
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from . import views

urlpatterns = [
    path("auth/register/", views.RegisterView.as_view()),
    path("auth/login/", TokenObtainPairView.as_view()),
    path("auth/refresh/", TokenRefreshView.as_view()),
    path("plans/", views.PlanListView.as_view()),
    path("subscription/create-order/", views.CreateOrderView.as_view()),
    path("subscription/activate-test/", views.ActivateTestView.as_view()),
    path("subscription/verify/", views.VerifyPaymentView.as_view()),
    path("subscription/webhook/", views.WebhookView.as_view()),
    path("me/", views.MeView.as_view()),
]
