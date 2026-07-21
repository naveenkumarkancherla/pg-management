from rest_framework.permissions import BasePermission


class IsActiveOwner(BasePermission):
    """Single choke point: approved AND paid AND not expired.

    Reuse on every business endpoint added in later phases.
    """

    message = "Owner not approved, or subscription inactive/expired."

    def has_permission(self, request, view):
        u = request.user
        return bool(u and u.is_authenticated and u.is_approved and u.has_active_subscription())
