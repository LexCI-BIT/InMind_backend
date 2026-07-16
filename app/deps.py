"""
FastAPI dependencies — auth, role-guard, current-user injection.
"""
from dataclasses import dataclass

from fastapi import Depends, Header, HTTPException, status
from supabase import Client

from .supabase_client import get_supabase, get_user_client


@dataclass
class CurrentUser:
    id: str
    email: str | None
    role: str | None
    access_token: str
    client: Client  # RLS-scoped client for this user's DB queries


def _extract_token(authorization: str | None) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Authorization header (expected 'Bearer <token>').",
        )
    return authorization.split(" ", 1)[1].strip()


def get_current_user(authorization: str | None = Header(default=None)) -> CurrentUser:
    """Validate the Supabase access token and load the user's role."""
    token = _extract_token(authorization)

    # Validate the JWT against Supabase Auth. An expired/invalid token makes the
    # gotrue client raise AuthApiError (HTTP 403); turn that into a clean 401 so
    # the frontend can refresh the session instead of seeing a 500.
    try:
        auth_resp = get_supabase().auth.get_user(token)
    except Exception:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token.")
    if not auth_resp or not auth_resp.user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token.")

    user = auth_resp.user
    client = get_user_client(token)

    # Try to read role from the users table; fall back to user metadata
    role = None
    try:
        row = client.table("users").select("role").eq("id", user.id).single().execute()
        if row.data:
            role = row.data.get("role")
    except Exception:
        role = (user.user_metadata or {}).get("role")

    return CurrentUser(id=user.id, email=user.email, role=role, access_token=token, client=client)


def require_role(*allowed: str):
    """Dependency factory: restrict an endpoint to specific roles."""

    def _checker(current: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        if current.role not in allowed:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Requires role in {allowed}; you are '{current.role}'.",
            )
        return current

    return _checker
