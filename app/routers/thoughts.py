"""
Thoughts router — "Share a Thought".

A student posts a short reflection that is broadcast to every student in the
SAME CLASS (any section). Posts can be anonymous (no name shown) or named.

  POST /api/thoughts   — student shares a thought
  GET  /api/thoughts   — class feed (newest first); author hidden for anonymous

Anonymity: the author's display name is captured at post time and stored as
NULL for anonymous posts, and the API never returns author_id — so a classmate
can't tell who wrote an anonymous thought.
"""
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends

from ..deps import CurrentUser, get_current_user, require_role
from ..schemas import ThoughtCreate

router = APIRouter(prefix="/api/thoughts", tags=["thoughts"])


def _my_class(db, user_id: str):
    row = db.table("students").select("class_name").eq("user_id", user_id).maybe_single().execute()
    return (row.data or {}).get("class_name") if row else None


@router.post("", status_code=201)
def create_thought(body: ThoughtCreate, current: CurrentUser = Depends(require_role("student"))):
    """Share a thought with the rest of the student's class."""
    db = current.client
    class_name = _my_class(db, current.id)

    author_name = None
    if not body.is_anonymous:
        u = db.table("users").select("full_name, email").eq("id", current.id).maybe_single().execute()
        ud = u.data or {}
        author_name = ud.get("full_name") or (ud.get("email") or "").split("@")[0] or "Classmate"

    created = db.table("thoughts").insert({
        "author_id": current.id,
        "author_name": author_name,
        "class_name": class_name,
        "content": body.content.strip(),
        "is_anonymous": body.is_anonymous,
    }).execute()

    return {"id": created.data[0]["id"], "class_name": class_name, "is_anonymous": body.is_anonymous}


@router.get("")
def list_thoughts(current: CurrentUser = Depends(get_current_user)):
    """Class feed of shared thoughts (newest first).

    Students see their own class; teachers see all. Author identity is hidden
    for anonymous posts and author_id is never returned.
    """
    db = current.client
    # Thoughts auto-expire after 24h — never show older ones, even if the
    # hourly cleanup job hasn't run yet.
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=24)).isoformat()
    query = (
        db.table("thoughts")
        .select("id, content, is_anonymous, author_name, class_name, created_at")
        .gte("created_at", cutoff)
        .order("created_at", desc=True)
        .limit(50)
    )
    if current.role != "teacher":
        class_name = _my_class(db, current.id)
        if not class_name:
            return []
        query = query.eq("class_name", class_name)

    res = query.execute()
    return [{
        "id": t["id"],
        "content": t["content"],
        "is_anonymous": t["is_anonymous"],
        "author_name": None if t["is_anonymous"] else t.get("author_name"),
        "class_name": t.get("class_name"),
        "created_at": t["created_at"],
    } for t in (res.data or [])]
