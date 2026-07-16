from supabase import Client, create_client

from .config import get_settings

_settings = get_settings()


def _anon_key() -> str:
    return _settings.supabase_publishable_key or _settings.supabase_anon_key


def get_supabase() -> Client:
    """Anon/publishable client — respects RLS. Used for auth (signup/login)."""
    return create_client(_settings.supabase_url, _anon_key())


def get_user_client(access_token: str) -> Client:
    """Client that runs DB queries AS the signed-in user (RLS enforced via their JWT)."""
    client = create_client(_settings.supabase_url, _anon_key())
    # Route PostgREST/Storage calls with the user's bearer token
    client.postgrest.auth(access_token)
    return client


def get_supabase_admin() -> Client:
    """Service-role client — bypasses RLS. Server-side only."""
    if not _settings.supabase_service_role_key:
        raise RuntimeError(
            "SUPABASE_SERVICE_ROLE_KEY is not set. Add it to .env "
            "(Dashboard -> Project Settings -> API -> service_role)."
        )
    return create_client(_settings.supabase_url, _settings.supabase_service_role_key)
