"""
Static Flow Signal Scoring Engine
=================================

Implements the "STATIC FLOW SIGNAL SCORING FRAMEWORK":

  raw responses + behavioral metrics
      → per-signal scores (0-100)
      → interaction signals (system generated)
      → traits
      → dashboard metrics (with a "caution" band for each)

All functions are pure: they take plain dicts (rows read from the DB) and
return plain dicts, so they're trivially unit-testable and have no DB/HTTP
dependencies.

Score bands (energy / intensity):
    1-20 → 20, 21-40 → 40, 41-60 → 60, 61-80 → 80, 81-100 → 100
A 1-5 slider (used by the sensation intensity control) is scaled ×20.

Interaction-signal thresholds mirror the frontend behavioral constants.
"""
from __future__ import annotations

from typing import Any, Optional

# ── Thresholds (kept in sync with src/lib/behavioral/constants.js) ──
HESITATION_HIGH_MS = 5000      # > 5s  → High Hesitation
RAPID_RESPONSE_MS = 2000       # < 2s  → Rapid Selection
FREQUENT_CHANGES = 5           # >= 5  → Frequent Changes
LOW_ENERGY_SCORE = 20          # < 20  → Low Energy Reported

SOMATIC_ZONES = {"head", "chest"}
SOMATIC_SENSATION = "pain"


# ════════════════════════════════════════════════════════════════
#  1. Helpers
# ════════════════════════════════════════════════════════════════

def band_score(value: Optional[float]) -> int:
    """Band a 0-100 value (or a 1-5 slider) into 20/40/60/80/100."""
    if value is None:
        return 0
    try:
        v = float(value)
    except (TypeError, ValueError):
        return 0
    if v <= 0:
        return 0
    if v <= 5:          # 1-5 slider → scale up
        return int(max(0, min(100, round(v * 20))))
    if v <= 20:
        return 20
    if v <= 40:
        return 40
    if v <= 60:
        return 60
    if v <= 80:
        return 80
    return 100


def readiness_band(score: int) -> str:
    if score <= 25:
        return "Very Low Readiness"
    if score <= 50:
        return "Low Readiness"
    if score <= 75:
        return "Moderate Readiness"
    return "High Readiness"


def caution_for(score: float, *, invert: bool = False) -> str:
    """Map a 0-100 score to a caution band.

    Normal metrics: low score = needs attention.
    invert=True (e.g. emotional intensity): high score = needs attention.
    """
    s = 100 - score if invert else score
    if s < 40:
        return "attention"
    if s < 70:
        return "monitor"
    return "healthy"


# ════════════════════════════════════════════════════════════════
#  2. Per-response signal scores
# ════════════════════════════════════════════════════════════════

def response_scores(answers: dict[str, Any]) -> dict[str, int]:
    """Score the seven static-flow signals from a merged answers dict.

    `answers` is the union of the static_flow_responses rows for one session
    (one field per screen): selected_context, energy_value, primary_emotion,
    sub_emotion, body_zone, sensation_type, sensation_intensity.
    """
    energy = band_score(answers.get("energy_value"))
    sub = answers.get("sub_emotion")
    trigger = 25 if (not sub or str(sub).strip().lower() == "unknown") else 100

    return {
        "readiness": energy,                                                  # Readiness Score
        "emotion_recognition": 100 if answers.get("primary_emotion") else 0,  # Emotion selected?
        "trigger_awareness": trigger,                                          # cause identified?
        "body_awareness": 100 if answers.get("body_zone") else 0,
        "sensation_awareness": 100 if answers.get("sensation_type") else 0,
        "emotion_intensity": band_score(answers.get("sensation_intensity")),
    }


# ════════════════════════════════════════════════════════════════
#  3. Interaction signals (system generated)
# ════════════════════════════════════════════════════════════════

def interaction_signals(row: dict[str, Any]) -> list[dict]:
    """Detect the framework's system-generated signals from the session's
    behavioral aggregates (stored once per session)."""
    hesitation = row.get("max_hesitation_ms") or 0
    fastest = row.get("min_response_time_ms")
    changes = row.get("max_option_changes") or 0
    raw_energy = row.get("energy_value")

    zone = str(row.get("body_zone") or "").strip().lower()
    sensation = str(row.get("sensation_type") or "").strip().lower()

    out = []
    if hesitation > HESITATION_HIGH_MS:
        out.append({"signal": "High Hesitation", "score": 100, "trait": "Decision Confidence",
                    "meaning": "Student needed more time before responding."})
    if fastest is not None and fastest < RAPID_RESPONSE_MS:
        out.append({"signal": "Rapid Selection", "score": 100, "trait": "Engagement",
                    "meaning": "Student responded very quickly."})
    if changes >= FREQUENT_CHANGES:
        out.append({"signal": "Frequent Changes", "score": 100, "trait": "Certainty",
                    "meaning": "Student repeatedly changed responses."})
    if raw_energy is not None and float(raw_energy) < LOW_ENERGY_SCORE:
        out.append({"signal": "Low Energy Reported", "score": 100, "trait": "Readiness",
                    "meaning": "Student reports very low readiness."})
    if zone in SOMATIC_ZONES and sensation == SOMATIC_SENSATION:
        out.append({"signal": "Somatic Complaint", "score": 100, "trait": "Somatic Awareness",
                    "meaning": "Physical discomfort reported."})
    return out


# ════════════════════════════════════════════════════════════════
#  4. Traits
# ════════════════════════════════════════════════════════════════

def traits(rs: dict[str, int], signals: list[dict], engagement_score: Optional[int]) -> dict[str, int]:
    has = {s["signal"] for s in signals}
    hesitation_score = 100 if "High Hesitation" in has else 0
    changes_score = 100 if "Frequent Changes" in has else 0

    emotional_awareness = round(
        rs["emotion_recognition"] * 0.35
        + rs["trigger_awareness"] * 0.35
        + rs["emotion_intensity"] * 0.30
    )
    somatic = round(rs["body_awareness"] * 0.5 + rs["sensation_awareness"] * 0.5)

    return {
        "Emotional Awareness": emotional_awareness,
        "Somatic Awareness": somatic,
        "Readiness": rs["readiness"],
        "Decision Confidence": 100 - hesitation_score,
        "Certainty": 100 - changes_score,
        "Engagement": int(engagement_score) if engagement_score is not None else rs["readiness"],
    }


# ════════════════════════════════════════════════════════════════
#  5. Dashboard metrics
# ════════════════════════════════════════════════════════════════

def _metric(label: str, value: float, *, invert: bool = False, band: Optional[str] = None) -> dict:
    value = round(value)
    return {
        "label": label,
        "value": value,
        "band": band,
        "caution": caution_for(value, invert=invert),
    }


def dashboard_metrics(rs: dict[str, int], tr: dict[str, int], answers: dict[str, Any]) -> list[dict]:
    understanding = round((rs["emotion_recognition"] + rs["trigger_awareness"]) / 2)
    return [
        _metric("Daily Readiness", rs["readiness"], band=readiness_band(rs["readiness"])),
        _metric("Understanding Emotions", understanding),
        _metric("Mind Body Awareness", tr["Somatic Awareness"]),
        _metric("Emotional Intensity Trend", rs["emotion_intensity"], invert=True),
        _metric("Response Confidence", tr["Decision Confidence"]),
        _metric("Participation Quality", tr["Engagement"]),
        {
            "label": "Environment Insights",
            "value": answers.get("selected_context") or "—",
            "band": "Context (metadata only)",
            "caution": "info",
        },
    ]


# ════════════════════════════════════════════════════════════════
#  6. Top-level: compute everything for one session
# ════════════════════════════════════════════════════════════════

def compute_session_insights(row: dict | None) -> dict:
    """Full insight bundle for one daily static check-in.

    `row` is the self-contained static_flow_responses row (answers + behavioral
    aggregates + engagement + flags + date), or None if the day is missing.
    """
    row = row or {}
    rs = response_scores(row)
    sigs = interaction_signals(row)
    tr = traits(rs, sigs, row.get("engagement_score"))
    metrics = dashboard_metrics(rs, tr, row)
    return {
        "session": {
            "session_id": row.get("session_id"),
            "date": row.get("response_date"),
            "started_at": row.get("created_at"),
            "engagement_score": row.get("engagement_score"),
            "engagement_label": row.get("engagement_label"),
            "is_genuine": row.get("is_genuine"),
            "flags": row.get("flags") or [],
        },
        "response_scores": rs,
        "interaction_signals": sigs,
        "traits": tr,
        "metrics": metrics,
    }
