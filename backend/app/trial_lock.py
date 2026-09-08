"""Read-only enforcement for shops whose free trial has run out.

Implemented as middleware rather than a per-route dependency on purpose. The
alternative means editing every write route across a dozen routers, and any
route added later would silently miss the check — the failure mode being "an
expired trial can still write", which is the one thing this must never allow.
One place, no router changes, and new routes are covered automatically.

The rule is deliberately narrow:

    locked  =  trial_ends_at IS NOT NULL
               AND NOT is_subscribed
               AND trial_ends_at < now()

`trial_ends_at` is NULL for every admin-provisioned shop, so nothing that
existed before self-signup can ever be locked by this. Reads are always
allowed — an expired trial keeps full visibility of its own data, it just
can't change anything.
"""
from __future__ import annotations

from fastapi import Request, status
from fastapi.responses import JSONResponse
from jose import JWTError
from sqlalchemy import select
from starlette.middleware.base import BaseHTTPMiddleware

from app.auth.security import decode_access_token
from app.database import privileged_session
from app.models.shop import Shop

#: Methods that change data. GET/HEAD/OPTIONS stay open when locked.
_MUTATING = {"POST", "PUT", "PATCH", "DELETE"}

#: Paths that must keep working even when locked, so the shop can get out of
#: it: signing in, reading identity, and deleting the account.
_ALWAYS_ALLOWED = {"/auth/login", "/auth/signup", "/auth/me"}

LOCKED_DETAIL = (
    "Your 14-day free trial has ended. You can still see all your data, "
    "but adding or changing anything needs an active plan. "
    "Contact us to continue."
)


class TrialLockMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.method not in _MUTATING or request.url.path in _ALWAYS_ALLOWED:
            return await call_next(request)

        auth = request.headers.get("authorization") or ""
        if not auth.lower().startswith("bearer "):
            return await call_next(request)  # unauthenticated: let auth reject it

        try:
            token = decode_access_token(auth.split(" ", 1)[1])
        except (JWTError, ValueError, IndexError):
            return await call_next(request)  # invalid token: let auth reject it

        if token.shop_id is None:
            return await call_next(request)  # admin/owner: no single shop to lock

        with privileged_session() as db:
            shop = db.execute(
                select(Shop).where(Shop.id == token.shop_id)
            ).scalar_one_or_none()
            locked = shop is not None and shop.is_trial_locked

        if locked:
            # 402 Payment Required — the same status Android's older
            # subscription lock used, and unambiguous against 401/403.
            return JSONResponse(
                status_code=status.HTTP_402_PAYMENT_REQUIRED,
                content={"detail": LOCKED_DETAIL},
            )

        return await call_next(request)
