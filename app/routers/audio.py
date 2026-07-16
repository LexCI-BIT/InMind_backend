"""
Audio router — list tracks, get/save playback progress.
"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel

from ..deps import CurrentUser, get_current_user


router = APIRouter(prefix="/api/audio", tags=["audio"])


# ─── Response schemas ────────────────────────────────────────


class TrackOut(BaseModel):
    id: str
    title: str
    description: Optional[str] = None
    category: str
    sub_category: Optional[str] = None
    cover_url: Optional[str] = None
    audio_url: str
    duration_seconds: int
    author: Optional[str] = None
    sort_order: int


class ProgressOut(BaseModel):
    track_id: str
    position_seconds: int
    completed: bool
    last_played_at: str


class ProgressIn(BaseModel):
    track_id: str
    position_seconds: int
    completed: bool = False


# ─── Endpoints ───────────────────────────────────────────────


@router.get("/tracks", response_model=list[TrackOut])
def list_tracks(
    category: Optional[str] = Query(None, description="Filter by category: audiobook, clip, focus"),
    current: CurrentUser = Depends(get_current_user),
):
    """List all published audio tracks, optionally filtered by category."""
    query = (
        current.client.table("audio_tracks")
        .select("id, title, description, category, sub_category, cover_url, audio_url, duration_seconds, author, sort_order")
        .eq("is_published", True)
        .order("sort_order")
    )
    if category:
        query = query.eq("category", category)

    resp = query.execute()
    return resp.data or []


@router.get("/tracks/{track_id}", response_model=TrackOut)
def get_track(
    track_id: str,
    current: CurrentUser = Depends(get_current_user),
):
    """Get a single audio track by ID."""
    resp = (
        current.client.table("audio_tracks")
        .select("id, title, description, category, sub_category, cover_url, audio_url, duration_seconds, author, sort_order")
        .eq("id", track_id)
        .eq("is_published", True)
        .single()
        .execute()
    )
    if not resp.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Track not found.")
    return resp.data


@router.get("/progress", response_model=list[ProgressOut])
def list_progress(
    current: CurrentUser = Depends(get_current_user),
):
    """Get the current user's playback progress for all tracks."""
    resp = (
        current.client.table("audio_playback_progress")
        .select("track_id, position_seconds, completed, last_played_at")
        .eq("user_id", current.id)
        .order("last_played_at", desc=True)
        .execute()
    )
    return resp.data or []


@router.post("/progress", response_model=ProgressOut, status_code=status.HTTP_200_OK)
def save_progress(
    body: ProgressIn,
    current: CurrentUser = Depends(get_current_user),
):
    """Save/update playback position for a track (upsert by user_id + track_id)."""
    resp = (
        current.client.table("audio_playback_progress")
        .upsert(
            {
                "user_id": current.id,
                "track_id": body.track_id,
                "position_seconds": body.position_seconds,
                "completed": body.completed,
                "last_played_at": "now()",
            },
            on_conflict="user_id,track_id",
        )
        .execute()
    )
    if not resp.data:
        raise HTTPException(status_code=500, detail="Failed to save progress.")
    row = resp.data[0]
    return ProgressOut(
        track_id=row["track_id"],
        position_seconds=row["position_seconds"],
        completed=row["completed"],
        last_played_at=row.get("last_played_at", row.get("updated_at", "")),
    )
