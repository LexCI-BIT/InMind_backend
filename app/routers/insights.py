"""
Insights router — turns stored static-flow data into dashboard metrics.

  GET /api/insights/me                  — student: own latest check-in insights
  GET /api/insights/students            — teacher: roster + who checked in today
  GET /api/insights/student/{user_id}   — teacher: one student's insights + trend

The heavy lifting (scores → signals → traits → metrics) lives in app.scoring.
"""
from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException

from ..deps import CurrentUser, get_current_user, require_role
from ..scoring import band_score, compute_session_insights, readiness_band

router = APIRouter(prefix="/api/insights", tags=["insights"])


def _latest_static(client, user_id: str):
    """The student's most recent daily static check-in row (self-contained)."""
    res = (
        client.table("static_flow_responses")
        .select("*")
        .eq("user_id", user_id)
        .order("response_date", desc=True)
        .limit(1)
        .execute()
    )
    return res.data[0] if res.data else None


def _readiness_trend(client, user_id: str, limit: int = 7):
    """Readiness over the last few check-ins (oldest→newest). Missed days simply
    have no row, so the trend shows only the days the student actually checked in."""
    rows = (
        client.table("static_flow_responses")
        .select("response_date, energy_value, sensation_intensity")
        .eq("user_id", user_id)
        .order("response_date", desc=True)
        .limit(limit)
        .execute()
    ).data or []
    trend = []
    for r in reversed(rows):
        trend.append({
            "date": r.get("response_date"),
            "readiness": band_score(r.get("energy_value")),
            "intensity": band_score(r.get("sensation_intensity")),
        })
    return trend


def _insights_payload(client, user_id: str, with_trend: bool = True):
    row = _latest_static(client, user_id)
    if not row:
        return {"has_data": False}
    bundle = compute_session_insights(row)
    bundle["has_data"] = True
    if with_trend:
        bundle["trend"] = _readiness_trend(client, user_id)
    return bundle


@router.get("/me")
def my_insights(current: CurrentUser = Depends(get_current_user)):
    """The signed-in student's own latest check-in insights."""
    return _insights_payload(current.client, current.id)


@router.get("/students")
def roster(current: CurrentUser = Depends(require_role("teacher"))):
    """All students with their latest check-in date + today's status."""
    client = current.client
    students = (
        client.table("users")
        .select("id, full_name, email")
        .eq("role", "student")
        .execute()
    ).data or []

    rows = (
        client.table("static_flow_responses")
        .select("user_id, response_date")
        .order("response_date", desc=True)
        .execute()
    ).data or []

    latest: dict[str, str] = {}
    for r in rows:
        uid = r["user_id"]
        if uid not in latest:
            latest[uid] = r.get("response_date")

    today = date.today().isoformat()
    out = []
    for st in students:
        last = latest.get(st["id"])
        out.append({
            "id": st["id"],
            "name": st.get("full_name") or (st.get("email") or "").split("@")[0] or "Student",
            "email": st.get("email"),
            "last_checkin": last,
            "checked_in_today": bool(last and str(last)[:10] == today),
        })
    # Students who checked in today first, then by name.
    out.sort(key=lambda s: (not s["checked_in_today"], s["name"].lower()))
    return out


@router.get("/student/{user_id}")
def student_insights(user_id: str, current: CurrentUser = Depends(require_role("teacher"))):
    """One student's full insights (RLS lets a teacher read student flow data)."""
    profile = current.client.table("users").select("id, full_name, email, role").eq("id", user_id).maybe_single().execute()
    if not profile or not profile.data or profile.data.get("role") != "student":
        raise HTTPException(status_code=404, detail="Student not found.")
    data = _insights_payload(current.client, user_id)
    data["student"] = {
        "id": profile.data["id"],
        "name": profile.data.get("full_name") or (profile.data.get("email") or "").split("@")[0],
        "email": profile.data.get("email"),
    }
    return data
