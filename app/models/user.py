"""User model — one row per Firebase identity.

Keyed by firebase_uid (the Firebase UID string), not an integer PK, so the
app can look up users from the session cookie without needing a separate
database column as the join key.
"""

from __future__ import annotations

from datetime import datetime

from sqlmodel import Field, SQLModel


class User(SQLModel, table=True):
    firebase_uid: str = Field(primary_key=True, max_length=128)
    email: str = Field(index=True, max_length=320)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    last_login_at: datetime = Field(default_factory=datetime.utcnow)
