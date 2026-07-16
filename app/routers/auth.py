"""
Auth router — signup (student/parent/teacher), login, me, logout.

Uses Supabase Auth for identity. On signup a Postgres trigger auto-creates
the `public.users` row; we then insert the role-specific detail row (students,
parents, or teachers).
"""
from fastapi import APIRouter, Depends, HTTPException, status

from ..deps import CurrentUser, get_current_user
from ..schemas import (
    AuthTokens,
    LoginRequest,
    ParentSignup,
    ProfileUpdate,
    RefreshRequest,
    StudentSignup,
    TeacherSignup,
)
from ..supabase_client import get_supabase, get_supabase_admin, get_user_client

router = APIRouter(prefix="/auth", tags=["auth"])


# ─── Helpers ──────────────────────────────────────────────────

def _sign_up_and_session(email: str, password: str, metadata: dict):
    """Create the auth user via the admin API (no email verification, no rate limits),
    then sign in to get a session token for the frontend.
    """
    admin = get_supabase_admin()
    sb = get_supabase()

    # 1) Create user via admin API — auto-confirmed, no email sent
    try:
        res = admin.auth.admin.create_user({
            "email": email,
            "password": password,
            "email_confirm": True,       # mark email as verified immediately
            "user_metadata": metadata,
        })
    except Exception as e:
        detail = str(e)
        # If user already exists, let them know
        if "already" in detail.lower() or "duplicate" in detail.lower():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="An account with this email already exists. Try logging in.",
            )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=detail)

    user = res.user
    if not user:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Sign up failed.")

    # 2) Sign in to get a session (access_token + refresh_token)
    try:
        login_res = sb.auth.sign_in_with_password({"email": email, "password": password})
        session = login_res.session
    except Exception:
        session = None

    return user, session


def _insert_detail(access_token: str | None, user_id: str, table: str, row: dict):
    """Insert the role-specific detail row.

    Prefer the user's RLS-scoped client; fall back to the service-role admin
    client so the row is always saved even if the session wasn't returned.
    """
    payload = {"user_id": user_id, **{k: v for k, v in row.items() if v is not None}}
    try:
        if access_token:
            client = get_user_client(access_token)
            client.table(table).upsert(payload, on_conflict="user_id").execute()
            return
    except Exception:
        pass
    # Fallback: service-role (bypasses RLS) — server-side only.
    get_supabase_admin().table(table).upsert(payload, on_conflict="user_id").execute()


def _tokens(user, session, role) -> AuthTokens:
    return AuthTokens(
        access_token=session.access_token if session else "",
        refresh_token=session.refresh_token if session else None,
        user_id=user.id,
        role=role,
        email=user.email,
    )


# ─── Signup Endpoints ────────────────────────────────────────

@router.post("/signup/student", response_model=AuthTokens)
def signup_student(body: StudentSignup):
    meta = {"role": "student", "full_name": body.full_name, "phone_number": body.phone_number}
    user, session = _sign_up_and_session(body.email, body.password, meta)
    detail = body.model_dump(
        exclude={"role", "email", "password", "full_name", "phone_number"}
    )
    if body.date_of_birth:
        detail["date_of_birth"] = body.date_of_birth.isoformat()
    _insert_detail(session.access_token if session else None, user.id, "students", detail)
    return _tokens(user, session, "student")


@router.post("/signup/parent", response_model=AuthTokens)
def signup_parent(body: ParentSignup):
    meta = {"role": "parent", "full_name": body.full_name, "phone_number": body.phone_number}
    user, session = _sign_up_and_session(body.email, body.password, meta)
    detail = body.model_dump(exclude={"role", "email", "password", "full_name", "phone_number"})
    _insert_detail(session.access_token if session else None, user.id, "parents", detail)
    return _tokens(user, session, "parent")


@router.post("/signup/teacher", response_model=AuthTokens)
def signup_teacher(body: TeacherSignup):
    meta = {"role": "teacher", "full_name": body.full_name, "phone_number": body.phone_number}
    user, session = _sign_up_and_session(body.email, body.password, meta)
    detail = body.model_dump(exclude={"role", "email", "password", "full_name", "phone_number"})
    if body.date_of_birth:
        detail["date_of_birth"] = body.date_of_birth.isoformat()
    _insert_detail(session.access_token if session else None, user.id, "teachers", detail)
    return _tokens(user, session, "teacher")


# ─── Login / Me / Logout ─────────────────────────────────────

@router.post("/login", response_model=AuthTokens)
def login(body: LoginRequest):
    sb = get_supabase()
    try:
        res = sb.auth.sign_in_with_password({"email": body.email, "password": body.password})
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e))
    if not res.session:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials.")
    # Resolve role from the users table (authoritative), falling back to metadata.
    role = (res.user.user_metadata or {}).get("role")
    try:
        row = (
            get_user_client(res.session.access_token)
            .table("users").select("role").eq("id", res.user.id).single().execute()
        )
        if row.data and row.data.get("role"):
            role = row.data["role"]
    except Exception:
        pass
    return _tokens(res.user, res.session, role)


@router.post("/refresh", response_model=AuthTokens)
def refresh(body: RefreshRequest):
    """Exchange a refresh token for a fresh access token (access tokens expire
    ~hourly). The frontend calls this automatically on a 401."""
    sb = get_supabase()
    try:
        res = sb.auth.refresh_session(body.refresh_token)
    except Exception:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session expired. Please log in again.")
    if not res or not res.session:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session expired. Please log in again.")
    role = (res.user.user_metadata or {}).get("role") if res.user else None
    return _tokens(res.user, res.session, role)


@router.get("/me")
def me(current: CurrentUser = Depends(get_current_user)):
    profile = current.client.table("users").select("*").eq("id", current.id).single().execute()
    detail = None
    table = {"student": "students", "parent": "parents", "teacher": "teachers"}.get(current.role or "")
    if table:
        d = current.client.table(table).select("*").eq("user_id", current.id).maybe_single().execute()
        detail = d.data if d else None
    return {"user": profile.data, "role": current.role, "detail": detail}


_ALLOWED_DETAIL = {
    "student": {
        "roll_number", "school_email", "school_name", "board", "class_name", "section",
        "date_of_birth", "blood_group", "height", "weight", "parents_name", "parents_phone",
        "profile_photo_url", "student_id_photo_url",
    },
    "teacher": {"date_of_birth", "teacher_id_photo_url"},
    "parent": {"child_name", "child_class", "child_section"},
}


@router.patch("/me")
def update_me(body: ProfileUpdate, current: CurrentUser = Depends(get_current_user)):
    """Update the signed-in user's own profile (users row + role detail row)."""
    db = current.client

    user_updates = {}
    if body.full_name is not None:
        user_updates["full_name"] = body.full_name
    if body.phone_number is not None:
        user_updates["phone_number"] = body.phone_number
    if user_updates:
        db.table("users").update(user_updates).eq("id", current.id).execute()

    if body.detail:
        table = {"student": "students", "parent": "parents", "teacher": "teachers"}.get(current.role or "")
        allowed = _ALLOWED_DETAIL.get(current.role or "", set())
        clean = {k: v for k, v in body.detail.items() if k in allowed}
        if table and clean:
            db.table(table).upsert({"user_id": current.id, **clean}, on_conflict="user_id").execute()

    # Return the refreshed profile.
    return me(current)


@router.post("/logout")
def logout(current: CurrentUser = Depends(get_current_user)):
    try:
        current.client.auth.sign_out()
    except Exception:
        pass
    return {"ok": True}