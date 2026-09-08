from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1)


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class TokenData(BaseModel):
    """Decoded JWT claims used to build the per-request RLS context."""

    user_id: uuid.UUID
    role: str
    shop_id: uuid.UUID | None = None


class SignupRequest(BaseModel):
    """Public self-signup: creates a shop and its first manager together."""

    shop_name: str = Field(min_length=1, max_length=120)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    owner_name: str | None = Field(default=None, max_length=120)
    owner_phone: str | None = Field(default=None, max_length=20)


class CurrentUser(BaseModel):
    """Public view of the authenticated user (returned by /auth/me).

    The trial fields are additive and optional. Existing clients (Android, the
    web app) ignore unknown keys, and admin-provisioned shops report
    trial_ends_at=None / is_trial_locked=False, which is exactly the behaviour
    they had before trials existed.
    """

    id: uuid.UUID
    email: EmailStr
    role: str
    shop_id: uuid.UUID | None = None
    is_active: bool
    shop_name: str | None = None
    business_name: str | None = None
    business_upi: str | None = None

    trial_ends_at: datetime | None = None
    trial_days_left: int | None = None
    is_trial_locked: bool = False
    is_subscribed: bool = False
    is_self_signup: bool = False

    model_config = {"from_attributes": True}
