from django.contrib.auth.base_user import BaseUserManager


class OwnerManager(BaseUserManager):
    use_in_migrations = True

    def create_user(self, email, password=None, **extra):
        if not email:
            raise ValueError("Email is required")
        owner = self.model(email=self.normalize_email(email), **extra)
        owner.set_password(password)
        owner.save(using=self._db)
        return owner

    def create_superuser(self, email, password=None, **extra):
        extra.setdefault("is_staff", True)
        extra.setdefault("is_superuser", True)
        extra.setdefault("is_approved", True)
        return self.create_user(email, password, **extra)
