"""
InMind App — Pydantic schemas for request/response validation.

Covers:
  • Auth (signup for student/parent/teacher, login, tokens)
  • Flow Ingest (static + dynamic flow sessions, steps, behavioral signals)
  • Quizzes (teacher creation, student submission)
  • Journal (daily entries with mood tags)
"""
from datetime import date, datetime
from typing import Any, Literal, Optional

from pydantic import BaseModel, EmailStr, Field

# ═══════════════════════════════════════════════════════════════
#  AUTH
# ═══════════════════════════════════════════════════════════════

Role = Literal["student", "parent", "teacher"]


class StudentSignup(BaseModel):
    role: Literal["student"] = "student"
    email: EmailStr
    password: str = Field(min_length=6)
    full_name: Optional[str] = None
    phone_number: Optional[str] = None
    # student detail
    roll_number: str
    school_email: Optional[EmailStr] = None
    school_name: Optional[str] = None
    board: Optional[str] = None
    class_name: Optional[str] = None
    section: Optional[str] = None
    date_of_birth: Optional[date] = None
    blood_group: Optional[str] = None
    height: Optional[str] = None
    weight: Optional[str] = None
    parents_name: Optional[str] = None
    parents_phone: Optional[str] = None
    profile_photo_url: Optional[str] = None
    student_id_photo_url: Optional[str] = None


class ParentSignup(BaseModel):
    role: Literal["parent"] = "parent"
    email: EmailStr
    password: str = Field(min_length=6)
    full_name: Optional[str] = None
    phone_number: Optional[str] = None
    # parent detail
    child_name: Optional[str] = None
    child_class: Optional[str] = None
    child_section: Optional[str] = None


class TeacherSignup(BaseModel):
    role: Literal["teacher"] = "teacher"
    email: EmailStr
    password: str = Field(min_length=6)
    full_name: Optional[str] = None
    phone_number: Optional[str] = None
    # teacher detail
    date_of_birth: Optional[date] = None
    teacher_id_photo_url: Optional[str] = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class ThoughtCreate(BaseModel):
    content: str = Field(min_length=1, max_length=2000)
    is_anonymous: bool = False


class ProfileUpdate(BaseModel):
    """Edit the signed-in user's own profile. `detail` holds role-specific
    fields (student/teacher/parent) and is whitelisted server-side."""
    full_name: Optional[str] = None
    phone_number: Optional[str] = None
    detail: Optional[dict] = None


class AuthTokens(BaseModel):
    access_token: str
    refresh_token: Optional[str] = None
    token_type: str = "bearer"
    user_id: str
    role: Optional[str] = None
    email: Optional[str] = None


# ═══════════════════════════════════════════════════════════════
#  FLOW INGEST (static + dynamic check-in sessions)
# ═══════════════════════════════════════════════════════════════

class FlowSessionIn(BaseModel):
    session_id: str
    flow_type: Literal["static", "dynamic"]
    started_at: datetime
    completed_at: Optional[datetime] = None
    total_duration_ms: Optional[int] = None
    total_steps: Optional[int] = None
    steps_completed: Optional[int] = None
    engagement_score: Optional[int] = None
    engagement_label: Optional[str] = None
    is_genuine: Optional[bool] = True
    flags: list[str] = []
    local_date: Optional[date] = None  # student's local calendar date (one static check-in/day)


class FlowStepIn(BaseModel):
    step_number: int
    screen_type: Optional[str] = None
    screen_name: Optional[str] = None
    # ── static answer fields ──
    selected_context: Optional[str] = None
    energy_value: Optional[int] = None
    primary_emotion: Optional[str] = None
    sub_emotion: Optional[str] = None
    body_zone: Optional[str] = None
    sensation_type: Optional[str] = None
    sensation_intensity: Optional[int] = None
    # ── dynamic answer fields ──
    selection: Optional[str] = None
    narrow_selection: Optional[str] = None
    narrow_title: Optional[str] = None
    replay_data: Optional[Any] = None
    story_start_option: Optional[str] = None
    consequence_data: Optional[Any] = None
    prediction: Optional[str] = None
    seen_before: Optional[str] = None
    reflection_text: Optional[str] = None
    insight_data: Optional[Any] = None
    challenge_accepted: Optional[bool] = None
    challenge_data: Optional[Any] = None
    completed: Optional[bool] = None
    # ── behavioral metrics ──
    response_time_ms: Optional[int] = None
    hesitation_time_ms: Optional[int] = None
    option_change_count: Optional[int] = 0
    rapid_tap_count: Optional[int] = 0
    idle_duration_ms: Optional[int] = 0
    completion_duration_ms: Optional[int] = None
    interaction_depth_score: Optional[int] = None
    has_text_input: Optional[bool] = False
    text_length: Optional[int] = 0
    total_taps: Optional[int] = 0
    # ── timestamps ──
    screen_rendered_at: Optional[datetime] = None
    first_interaction_at: Optional[datetime] = None
    response_submitted_at: Optional[datetime] = None


class SignalItem(BaseModel):
    type: str
    value: Optional[int] = None
    severity: Literal["low", "medium", "high"]


class SignalGroupIn(BaseModel):
    step_number: int
    screen_name: str
    signals: list[SignalItem] = []


class FlowPayload(BaseModel):
    session: FlowSessionIn
    steps: list[FlowStepIn] = []
    behavioral_signals: list[SignalGroupIn] = []


# ═══════════════════════════════════════════════════════════════
#  QUIZZES
# ═══════════════════════════════════════════════════════════════

class QuizQuestionIn(BaseModel):
    question_number: int
    category: Optional[str] = None
    question_text: str
    option_a: str
    option_b: str
    option_c: str
    option_d: str
    correct_option: int = Field(ge=0, le=3)


class QuizCreate(BaseModel):
    title: str
    subject: Optional[str] = None
    target_class: Optional[str] = None
    target_section: Optional[str] = None
    duration_seconds: int = 210
    status: Literal["draft", "scheduled", "live", "completed"] = "draft"
    go_live_immediately: bool = False
    scheduled_at: Optional[datetime] = None
    questions: list[QuizQuestionIn] = []


class QuizUpdate(BaseModel):
    """Partial update for an existing quiz. Any field left as None is untouched.
    If `questions` is provided, the entire question set is replaced."""
    title: Optional[str] = None
    subject: Optional[str] = None
    target_class: Optional[str] = None
    target_section: Optional[str] = None
    duration_seconds: Optional[int] = None
    status: Optional[Literal["draft", "scheduled", "live", "completed"]] = None
    go_live_immediately: Optional[bool] = None
    scheduled_at: Optional[datetime] = None
    questions: Optional[list[QuizQuestionIn]] = None


class QuizAnswerIn(BaseModel):
    question_id: int
    selected_option: Optional[int] = Field(default=None, ge=0, le=3)
    response_time_ms: Optional[int] = None


class QuizSubmit(BaseModel):
    started_at: datetime
    time_remaining_seconds: Optional[int] = None
    answers: list[QuizAnswerIn] = []


# ═══════════════════════════════════════════════════════════════
#  JOURNAL
# ═══════════════════════════════════════════════════════════════

class JournalCreate(BaseModel):
    entry_type: str
    prompt_text: Optional[str] = None
    content: str
    entry_date: Optional[date] = None
    time_of_day: Optional[Literal["morning", "evening", "anytime"]] = None
    tags: list[str] = []
