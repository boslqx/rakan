"""Firebase ID-token check for every endpoint (D-15 / P0-1, V-07).

The app sends `Authorization: Bearer <Firebase ID token>`. The uid used for
any Firestore write comes from the verified token, never from the request
body: the Admin SDK bypasses the Firestore rules, so a body uid alone let
anyone write another user's plan (ST-14).
"""
from typing import Optional

from fastapi import Header, HTTPException


def verify_token(token: str) -> dict:
    """Decodes and checks a Firebase ID token. Kept separate so tests can
    replace it without a Firebase project."""
    import firebase_config  # noqa: F401  (initialises the Admin SDK)
    from firebase_admin import auth as firebase_auth

    return firebase_auth.verify_id_token(token)


def current_uid(authorization: Optional[str] = Header(default=None)) -> str:
    """FastAPI dependency: the signed-in user's uid, or 401."""
    scheme, _, token = (authorization or "").partition(" ")
    token = token.strip()
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Missing ID token")
    try:
        decoded = verify_token(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired ID token")
    return decoded["uid"]


def check_body_uid(body_uid: Optional[str], token_uid: str) -> None:
    """403 when an (older) client sends a uid that isn't its own."""
    if body_uid is not None and body_uid != token_uid:
        raise HTTPException(status_code=403, detail="uid does not match the signed-in user")
