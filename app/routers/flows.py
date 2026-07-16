"""
Flow router — ingest full static/dynamic check-in payloads.

Receives the unified JSON payload from logSessionSummary() and persists:
  1. flow_sessions        — one session row
  2. static/dynamic_flow_responses — one row per step (answers + behavioral metrics)
  3. behavioral_signals   — one row per flagged signal
  4. challenges           — challenge accept/decline (dynamic flow only)
"""
from datetime import date, datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, status

from ..deps import CurrentUser, get_current_user
from ..schemas import FlowPayload

router = APIRouter(prefix="/api/flows", tags=["flows"])


def _json(value: Any) -> Any:
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    return value


def _clean(d: dict) -> dict:
    return {k: _json(v) for k, v in d.items() if v is not None}


# Fields that belong to each flow's response table
_STATIC_FIELDS = {
    "selected_context", "energy_value", "primary_emotion", "sub_emotion",
    "body_zone", "sensation_type", "sensation_intensity",
}
_DYNAMIC_FIELDS = {
    "selection", "narrow_selection", "narrow_title", "replay_data",
    "story_start_option", "consequence_data", "prediction", "seen_before",
    "reflection_text", "insight_data", "challenge_accepted", "challenge_data",
    "completed",
}
_METRIC_FIELDS = {
    "response_time_ms", "hesitation_time_ms", "option_change_count",
    "rapid_tap_count", "idle_duration_ms", "completion_duration_ms",
    "interaction_depth_score", "has_text_input", "text_length", "total_taps",
    "screen_rendered_at", "first_interaction_at", "response_submitted_at",
}


@router.post("/session", status_code=status.HTTP_201_CREATED)
def ingest_session(payload: FlowPayload, current: CurrentUser = Depends(get_current_user)):
    """Persist a full check-in payload: session + step responses + signals (+ challenge)."""
    db = current.client
    s = payload.session
    flow = s.flow_type

    # 1) Session
    session_row = _clean({
        "session_id": s.session_id,
        "user_id": current.id,
        "flow_type": flow,
        "started_at": s.started_at,
        "completed_at": s.completed_at,
        "total_duration_ms": s.total_duration_ms,
        "total_steps": s.total_steps,
        "steps_completed": s.steps_completed,
        "engagement_score": s.engagement_score,
        "engagement_label": s.engagement_label,
        "is_genuine": s.is_genuine,
        "flags": s.flags,
    })
    try:
        db.table("flow_sessions").upsert(session_row, on_conflict="session_id").execute()
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"session insert failed: {e}")

    # 2) Responses
    challenge_rows = []
    steps_saved = 0

    if flow == "static":
        # ── One consolidated row per session ──
        # The static flow yields a single fixed set of answers, so we merge all
        # step answers and collapse the per-step behavioral metrics into the
        # session-level aggregates the scoring engine needs (no NULL-heavy rows).
        answers: dict = {}
        resp_times, hesitations, changes, idles, taps, depths, rapid = [], [], [], [], [], [], []
        for step in payload.steps:
            data = step.model_dump()
            for f in _STATIC_FIELDS:
                if data.get(f) is not None:
                    answers[f] = data[f]
            if data.get("response_time_ms") is not None: resp_times.append(data["response_time_ms"])
            if data.get("hesitation_time_ms") is not None: hesitations.append(data["hesitation_time_ms"])
            if data.get("option_change_count") is not None: changes.append(data["option_change_count"])
            if data.get("idle_duration_ms") is not None: idles.append(data["idle_duration_ms"])
            if data.get("rapid_tap_count") is not None: rapid.append(data["rapid_tap_count"])
            if data.get("total_taps") is not None: taps.append(data["total_taps"])
            if data.get("interaction_depth_score") is not None: depths.append(data["interaction_depth_score"])

        response_date = (s.local_date or date.today()).isoformat()
        static_row = _clean({
            "session_id": s.session_id,
            "user_id": current.id,
            "response_date": response_date,
            **answers,
            "total_response_time_ms": sum(resp_times) if resp_times else None,
            "min_response_time_ms": min(resp_times) if resp_times else None,
            "max_hesitation_ms": max(hesitations) if hesitations else None,
            "max_option_changes": max(changes) if changes else None,
            "rapid_tap_count": sum(rapid) if rapid else 0,
            "max_idle_ms": max(idles) if idles else 0,
            "avg_depth_score": round(sum(depths) / len(depths), 1) if depths else None,
            "engagement_score": s.engagement_score,
            "engagement_label": s.engagement_label,
            "is_genuine": s.is_genuine,
            "flags": s.flags,
        })
        try:
            # One row per student per day — redoing the flow updates the day's row.
            db.table("static_flow_responses").upsert(static_row, on_conflict="user_id,response_date").execute()
            steps_saved = 1
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"static response insert failed: {e}")
    else:
        # ── Dynamic flow stays one row per step (each screen differs) ──
        step_rows = []
        for step in payload.steps:
            data = step.model_dump()
            row = {
                "session_id": s.session_id,
                "user_id": current.id,
                "step_number": step.step_number,
                "screen_type": (step.screen_type or step.screen_name or f"step_{step.step_number}")[:30],
            }
            for f in _DYNAMIC_FIELDS | _METRIC_FIELDS:
                if data.get(f) is not None:
                    row[f] = _json(data[f])
            step_rows.append(_clean(row))
            if data.get("challenge_accepted") is not None:
                challenge_rows.append(_clean({
                    "session_id": s.session_id,
                    "user_id": current.id,
                    "accepted": data.get("challenge_accepted"),
                    "completed": bool(data.get("completed")),
                }))
        if step_rows:
            try:
                db.table("dynamic_flow_responses").upsert(step_rows, on_conflict="session_id,step_number").execute()
                steps_saved = len(step_rows)
            except Exception:
                try:
                    db.table("dynamic_flow_responses").insert(step_rows).execute()
                    steps_saved = len(step_rows)
                except Exception as e2:
                    raise HTTPException(status_code=400, detail=f"steps insert failed: {e2}")

    # 3) Behavioral signals (flattened: one row per signal)
    signal_rows = []
    for group in payload.behavioral_signals:
        for sig in group.signals:
            signal_rows.append(_clean({
                "session_id": s.session_id,
                "user_id": current.id,
                "step_number": group.step_number,
                "screen_name": group.screen_name,
                "signal_type": sig.type,
                "signal_value": sig.value,
                "severity": sig.severity,
            }))
    if signal_rows:
        try:
            db.table("behavioral_signals").insert(signal_rows).execute()
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"signals insert failed: {e}")

    # 4) Challenge (if any)
    if challenge_rows:
        try:
            db.table("challenges").insert(challenge_rows).execute()
        except Exception:
            pass

    return {
        "ok": True,
        "session_id": s.session_id,
        "flow_type": flow,
        "steps_saved": steps_saved,
        "signals_saved": len(signal_rows),
    }


@router.get("/today")
def static_today(date_param: str | None = Query(default=None, alias="date"), current: CurrentUser = Depends(get_current_user)):
    """Has the student already completed the static check-in for `date`?

    The frontend passes its LOCAL date (?date=YYYY-MM-DD) so the gate resets at
    the student's local midnight. One row exists per student per day.
    """
    day = date_param or date.today().isoformat()
    res = (
        current.client.table("static_flow_responses")
        .select("session_id, response_date")
        .eq("user_id", current.id)
        .eq("response_date", day)
        .limit(1)
        .execute()
    )
    row = res.data[0] if res.data else None
    return {
        "date": day,
        "completed_today": bool(row),
        "session_id": row["session_id"] if row else None,
    }


@router.get("/sessions")
def my_sessions(current: CurrentUser = Depends(get_current_user)):
    """List all flow sessions for the current user, newest first."""
    res = (
        current.client.table("flow_sessions")
        .select("*")
        .eq("user_id", current.id)
        .order("started_at", desc=True)
        .execute()
    )
    return res.data
