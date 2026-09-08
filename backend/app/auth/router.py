"""Authentication routes: /auth/signup, /auth/login, /auth/me."""
from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth.dependencies import get_current_user, get_db
from app.auth.security import create_access_token, hash_password, verify_password
from app.database import privileged_session
from app.models.shop import Shop
from app.models.user import ROLE_MANAGER, ROLE_SALESPERSON, User
from app.schemas.auth import CurrentUser, LoginRequest, SignupRequest, Token

#: Length of the free trial for a self-signed-up shop.
TRIAL_DAYS = 14

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=Token)
def login(payload: LoginRequest) -> Token:
    """Verify credentials and issue a JWT.

    Uses a privileged (admin-context) session because there is no JWT yet and we
    must look up the user by email across the whole users table.
    """
    invalid = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid email or password",
    )

    with privileged_session() as db:
        user = db.execute(
            select(User).where(User.email == str(payload.email))
        ).scalar_one_or_none()

        if user is None or not verify_password(payload.password, user.password_hash):
            raise invalid
        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, detail="User account is inactive"
            )

        if user.role in (ROLE_MANAGER, ROLE_SALESPERSON):
            shop = db.execute(select(Shop).where(Shop.id == user.shop_id)).scalar_one_or_none()
            if shop is None or not shop.is_active:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN, detail="Shop is inactive"
                )

        token = create_access_token(user_id=user.id, role=user.role, shop_id=user.shop_id)

    return Token(access_token=token)


@router.post("/signup", response_model=Token, status_code=status.HTTP_201_CREATED)
def signup(payload: SignupRequest) -> Token:
    """Public self-signup — one shop, one manager, one 14-day trial.

    Deliberately creates a MANAGER, not an owner: the manager role already has
    every shop feature (billing, products, sales, dues, staff, labour, reports,
    settings), so a trial user gets the whole product in a single workspace
    without the multi-shop owner shell, which would be empty and confusing for
    one shop.

    Runs in a privileged session because there is no JWT yet, same as /login.
    """
    with privileged_session() as db:
        existing = db.execute(
            select(User).where(User.email == str(payload.email))
        ).scalar_one_or_none()
        if existing is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="An account with this email already exists. Try signing in.",
            )

        shop = Shop(
            name=payload.shop_name,
            owner_name=payload.owner_name,
            owner_phone=payload.owner_phone,
            business_name=payload.shop_name,
            trial_ends_at=dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=TRIAL_DAYS),
            is_self_signup=True,
        )
        db.add(shop)
        db.flush()  # assign shop.id before creating the manager

        manager = User(
            shop_id=shop.id,
            email=str(payload.email),
            password_hash=hash_password(payload.password),
            role=ROLE_MANAGER,
        )
        db.add(manager)

        try:
            db.flush()
        except IntegrityError:
            db.rollback()
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="An account with this email already exists. Try signing in.",
            )

        token = create_access_token(
            user_id=manager.id, role=manager.role, shop_id=manager.shop_id
        )

    return Token(access_token=token)


@router.get("/me", response_model=CurrentUser)
def me(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> CurrentUser:
    shop_name = None
    business_name = None
    business_upi = None
    trial_ends_at = None
    trial_days_left = None
    is_trial_locked = False
    is_subscribed = False
    is_self_signup = False
    if user.shop_id is not None:
        shop = db.execute(select(Shop).where(Shop.id == user.shop_id)).scalar_one_or_none()
        if shop:
            shop_name = shop.name
            business_name = shop.business_name
            business_upi = shop.business_upi
            trial_ends_at = shop.trial_ends_at
            trial_days_left = shop.trial_days_left
            is_trial_locked = shop.is_trial_locked
            is_subscribed = shop.is_subscribed
            is_self_signup = shop.is_self_signup

    return CurrentUser(
        id=user.id,
        email=user.email,
        role=user.role,
        shop_id=user.shop_id,
        is_active=user.is_active,
        shop_name=shop_name,
        business_name=business_name,
        business_upi=business_upi,
        trial_ends_at=trial_ends_at,
        trial_days_left=trial_days_left,
        is_trial_locked=is_trial_locked,
        is_subscribed=is_subscribed,
        is_self_signup=is_self_signup,
    )


@router.delete(
    "/me",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
)
def delete_my_account(user: User = Depends(get_current_user)) -> Response:
    """In-app account deletion, required by App Store guideline 5.1.1(v).

    Scoped to shops created through signup: deleting the account deletes the
    whole trial workspace and everything in it. An admin-provisioned shop is
    NOT self-deletable — that account belongs to a paying business and is the
    platform admin's to remove, so the same button would be a footgun.
    """
    with privileged_session() as db:
        shop = db.execute(select(Shop).where(Shop.id == user.shop_id)).scalar_one_or_none()
        if shop is None or not shop.is_self_signup:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=(
                    "This account was set up for you by Plantbill. "
                    "Contact us and we'll close it for you."
                ),
            )
        # Everything under a shop cascades from the shop row (see the initial
        # migration's FKs), so removing it removes the whole workspace.
        db.delete(shop)

    return Response(status_code=status.HTTP_204_NO_CONTENT)
