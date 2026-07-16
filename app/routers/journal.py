"""
Journal router — students create and list daily journal entries.

Endpoints:
  POST  /api/journal  — create a journal entry (with optional mood tags)
  GET   /api/journal  — list all entries for the current user (newest first)
"""
from fastapi import APIRouter, Depends

from ..deps import CurrentUser, get_current_user
from ..schemas import JournalCreate

router = APIRouter(prefix="/api/journal", tags=["journal"])


@router.post("", status_code=201)
def create_entry(body: JournalCreate, current: CurrentUser = Depends(get_current_user)):
    """Create a new journal entry with optional mood tags."""
    db = current.client
    entry = {
        "user_id": current.id,
        "entry_type": body.entry_type,
        "prompt_text": body.prompt_text,
        "content": body.content,
        "word_count": len(body.content.split()),
        "time_of_day": body.time_of_day,
    }
    if body.entry_date:
        entry["entry_date"] = body.entry_date.isoformat()
    entry = {k: v for k, v in entry.items() if v is not None}
    created = db.table("journal_entries").insert(entry).execute()
    entry_id = created.data[0]["id"]

    if body.tags:
        tags = [{"entry_id": entry_id, "tag": t} for t in set(body.tags)]
        db.table("journal_tags").upsert(tags, on_conflict="entry_id,tag").execute()

    return {"id": entry_id, "tags_added": len(set(body.tags))}


@router.get("")
def list_entries(current: CurrentUser = Depends(get_current_user)):
    """List all journal entries for the current user, newest first."""
    res = (
        current.client.table("journal_entries")
        .select("*, journal_tags(tag)")
        .eq("user_id", current.id)
        .order("entry_date", desc=True)
        .execute()
    )
    return res.data
