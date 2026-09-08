from __future__ import annotations

import datetime as dt
import decimal
import uuid

from sqlalchemy import Boolean, Integer, Numeric, Text, text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, created_at_col, uuid_pk


class Shop(Base):
    __tablename__ = "shops"

    id: Mapped[uuid.UUID] = uuid_pk()
    name: Mapped[str] = mapped_column(Text, nullable=False)
    # Multi-shop business owners are linked via the shop_owners join table (a shop
    # may have several owners, or none). See app.models.shop_owner.ShopOwner.
    owner_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    owner_phone: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    
    business_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    business_address: Mapped[str | None] = mapped_column(Text, nullable=True)
    business_phone: Mapped[str | None] = mapped_column(Text, nullable=True)
    business_email: Mapped[str | None] = mapped_column(Text, nullable=True)
    business_upi: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Offset for the running (cumulative) cash-in-hand display. Running total =
    # base + all cash flows (cash sales − cash expenses) through the day. See the
    # a8b2c3d4e5f6 migration.
    cash_in_hand_base: Mapped[decimal.Decimal] = mapped_column(
        Numeric(12, 2), nullable=False, server_default=text("0")
    )

    # Per-shop counter for human-facing bill numbers. Allocated atomically at
    # checkout (UPDATE … RETURNING) so concurrent bills never share a number.
    next_bill_seq: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default=text("1")
    )

    # Shop logo for printed bills. Relative path under MEDIA_ROOT (e.g.
    # "logos/<uuid>.png"), never a URL — same convention as products.photo_path.
    # Admin-only: shop staff can see it but not change it.
    logo_path: Mapped[str | None] = mapped_column(Text, nullable=True)

    # --- Self-signup trial -------------------------------------------------
    # NULL means "not a trial shop" — every admin-provisioned shop, which is
    # all of them before self-signup existed. A NULL can never be locked, so
    # existing shops are unaffected by the trial write-block.
    trial_ends_at: Mapped[dt.datetime | None] = mapped_column(nullable=True)
    is_subscribed: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false")
    )
    # True only for a shop created through the app's own signup. Gates in-app
    # deletion: an admin-provisioned shop must not be self-deletable.
    is_self_signup: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false")
    )

    @property
    def is_trial_locked(self) -> bool:
        """Read-only mode: the trial ran out and nobody has paid yet."""
        if self.trial_ends_at is None or self.is_subscribed:
            return False
        return self.trial_ends_at < dt.datetime.now(dt.timezone.utc)

    @property
    def trial_days_left(self) -> int | None:
        """Whole days remaining, floored at 0. None when there's no trial."""
        if self.trial_ends_at is None or self.is_subscribed:
            return None
        delta = self.trial_ends_at - dt.datetime.now(dt.timezone.utc)
        return max(0, delta.days + (1 if delta.seconds > 0 else 0))

    settings: Mapped[dict] = mapped_column(JSONB, nullable=False, server_default=text("'{}'::jsonb"))
    created_at: Mapped[dt.datetime] = created_at_col()

    @property
    def logo_url(self) -> str | None:
        """The logo's public URL, derived from the stored relative path.

        A property rather than a column so the path stays the single source of
        truth — moving MEDIA_ROOT or changing the public prefix must not require
        rewriting rows. Schemas with from_attributes pick this up automatically.
        """
        from app.media import build_media_url  # local: app.media reads settings

        return build_media_url(self.logo_path)

    @property
    def logo_enabled(self) -> bool:
        """Whether an uploaded logo actually prints. Separate from logo_path so
        turning it off doesn't discard the file the admin uploaded.

        `settings` is only non-null once the row has been through the DB (the
        default is a server_default), so a freshly constructed Shop still has
        None here — and this is read on every bill, where an AttributeError
        would take down the receipt.
        """
        return (self.settings or {}).get("logo_enabled", True)

    @logo_enabled.setter
    def logo_enabled(self, value: bool) -> None:
        if self.settings is None:
            self.settings = {}
        new_settings = dict(self.settings)
        new_settings["logo_enabled"] = value
        self.settings = new_settings

    @property
    def whatsapp_auto_send(self) -> bool:
        return self.settings.get("whatsapp_auto_send", False)

    @whatsapp_auto_send.setter
    def whatsapp_auto_send(self, value: bool) -> None:
        if self.settings is None:
            self.settings = {}
        new_settings = dict(self.settings)
        new_settings["whatsapp_auto_send"] = value
        self.settings = new_settings

    @property
    def whatsapp_message_template(self) -> str | None:
        return self.settings.get("whatsapp_message_template", None)

    @whatsapp_message_template.setter
    def whatsapp_message_template(self, value: str | None) -> None:
        if self.settings is None:
            self.settings = {}
        new_settings = dict(self.settings)
        if value is None:
            new_settings.pop("whatsapp_message_template", None)
        else:
            new_settings["whatsapp_message_template"] = value.strip()
        self.settings = new_settings

    @property
    def whatsapp_enable_pdf(self) -> bool:
        return self.settings.get("whatsapp_enable_pdf", True)

    @whatsapp_enable_pdf.setter
    def whatsapp_enable_pdf(self, value: bool) -> None:
        if self.settings is None:
            self.settings = {}
        new_settings = dict(self.settings)
        new_settings["whatsapp_enable_pdf"] = value
        self.settings = new_settings

    @property
    def whatsapp_footer_message(self) -> str | None:
        return self.settings.get("whatsapp_footer_message", None)

    @whatsapp_footer_message.setter
    def whatsapp_footer_message(self, value: str | None) -> None:
        if self.settings is None:
            self.settings = {}
        new_settings = dict(self.settings)
        if value is None:
            new_settings.pop("whatsapp_footer_message", None)
        else:
            new_settings["whatsapp_footer_message"] = value.strip()
        self.settings = new_settings

    @property
    def whatsapp_language(self) -> str:
        return self.settings.get("whatsapp_language", "en")

    @whatsapp_language.setter
    def whatsapp_language(self, value: str | None) -> None:
        if self.settings is None:
            self.settings = {}
        new_settings = dict(self.settings)
        if value is None:
            new_settings.pop("whatsapp_language", None)
        else:
            new_settings["whatsapp_language"] = value.strip()
        self.settings = new_settings

