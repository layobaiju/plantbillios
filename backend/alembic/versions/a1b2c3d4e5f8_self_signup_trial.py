"""Self-signup trial: trial_ends_at + is_subscribed on shops

Revision ID: a1b2c3d4e5f8
Revises: e5f7a9b1c3d4
Create Date: 2026-09-07

Deliberately additive and safe for the shops that already exist.

`trial_ends_at` is NULLABLE and every existing row keeps NULL, which means
"not a trial shop". The lock check is:

    trial_ends_at IS NOT NULL AND NOT is_subscribed AND trial_ends_at < now()

so a NULL can never evaluate to locked. Admin-created shops — every shop on
production today, plus the Android and web users on them — are therefore
completely unaffected by this migration and by the write-block that reads
these columns.
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "a1b2c3d4e5f8"
down_revision = "e5f7a9b1c3d4"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "shops",
        sa.Column("trial_ends_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "shops",
        sa.Column(
            "is_subscribed",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )
    # Marks a shop the owner created themselves through the app, as opposed to
    # one the platform admin provisioned. Only a self-signed-up shop may be
    # deleted from inside the app (App Store guideline 5.1.1(v) requires
    # in-app deletion of accounts that were created in-app — and equally, an
    # admin-provisioned shop must NOT be self-deletable).
    op.add_column(
        "shops",
        sa.Column(
            "is_self_signup",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )
    # Trial expiry is read on every write request, so keep the lookup cheap.
    op.create_index(
        "ix_shops_trial_ends_at",
        "shops",
        ["trial_ends_at"],
        postgresql_where=sa.text("trial_ends_at IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("ix_shops_trial_ends_at", table_name="shops")
    op.drop_column("shops", "is_self_signup")
    op.drop_column("shops", "is_subscribed")
    op.drop_column("shops", "trial_ends_at")
