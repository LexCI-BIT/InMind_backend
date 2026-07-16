from functools import lru_cache
from typing import Optional

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Project
    supabase_url: str
    supabase_project_ref: Optional[str] = None

    # Client-safe keys
    supabase_publishable_key: Optional[str] = None
    supabase_anon_key: str

    # Server-only secret (bypasses RLS)
    supabase_service_role_key: Optional[str] = None

    # Direct Postgres connection (optional)
    database_url: Optional[str] = None

    app_env: str = "development"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
