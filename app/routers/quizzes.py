"""
Quiz router — teacher creates quizzes, students take them.

Endpoints:
  POST   /api/quizzes            — teacher creates a quiz + questions
  GET    /api/quizzes            — list all quizzes (filtered by RLS)
  GET    /api/quizzes/{id}       — get quiz with questions (answers hidden for students)
  PATCH  /api/quizzes/{id}       — teacher edits a quiz (fields, status, questions)
  POST   /api/quizzes/{id}/submit — student submits answers, gets graded
"""
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException

from ..deps import CurrentUser, get_current_user, require_role
from ..schemas import QuizCreate, QuizSubmit, QuizUpdate

router = APIRouter(prefix="/api/quizzes", tags=["quizzes"])


@router.post("", status_code=201)
def create_quiz(body: QuizCreate, current: CurrentUser = Depends(require_role("teacher"))):
    """Teacher creates a quiz with questions."""
    db = current.client
    quiz = {
        "teacher_id": current.id,
        "title": body.title,
        "subject": body.subject,
        "target_class": body.target_class,
        "target_section": body.target_section,
        "duration_seconds": body.duration_seconds,
        "status": body.status,
        "go_live_immediately": body.go_live_immediately,
        "scheduled_at": body.scheduled_at.isoformat() if body.scheduled_at else None,
        # Stamp the live start time so the teacher dashboard can show "Started X ago".
        "started_at": datetime.utcnow().isoformat() if (body.go_live_immediately or body.status == "live") else None,
    }
    quiz = {k: v for k, v in quiz.items() if v is not None}
    created = db.table("quizzes").insert(quiz).execute()
    quiz_id = created.data[0]["id"]

    if body.questions:
        questions = [{
            "quiz_id": quiz_id,
            "question_number": q.question_number,
            "category": q.category,
            "question_text": q.question_text,
            "option_a": q.option_a,
            "option_b": q.option_b,
            "option_c": q.option_c,
            "option_d": q.option_d,
            "correct_option": q.correct_option,
        } for q in body.questions]
        db.table("quiz_questions").insert(questions).execute()

    return {"id": quiz_id, "questions_added": len(body.questions)}


@router.get("")
def list_quizzes(current: CurrentUser = Depends(get_current_user)):
    """List quizzes (newest first) with a question count on each.

    Teachers get all of their own quizzes (any status). Everyone else
    (students) only see quizzes that have been published — i.e. not drafts —
    so a teacher's in-progress draft never shows up on the student side.
    """
    is_teacher = current.role == "teacher"
    # Teachers get a participant count; students get their own attempt (if any).
    select_cols = "*, quiz_questions(count)"
    if is_teacher:
        select_cols += ", quiz_sessions(count)"
    else:
        select_cols += ", quiz_sessions(id, score, total_questions, percentage, tier, completed_at)"

    query = current.client.table("quizzes").select(select_cols).order("created_at", desc=True)
    if is_teacher:
        query = query.eq("teacher_id", current.id)
    else:
        query = query.neq("status", "draft")

    res = query.execute()

    def _count(rel):
        if isinstance(rel, list) and rel:
            return rel[0].get("count", 0) or 0
        if isinstance(rel, dict):
            return rel.get("count", 0) or 0
        return 0

    quizzes = []
    for q in res.data or []:
        # PostgREST returns embedded counts as quiz_questions: [{"count": N}]
        q["question_count"] = _count(q.pop("quiz_questions", None))
        sess_rel = q.pop("quiz_sessions", None)
        if is_teacher:
            q["participant_count"] = _count(sess_rel)
        else:
            # RLS limits this to the student's own session(s); at most one per quiz.
            q["my_attempt"] = sess_rel[0] if isinstance(sess_rel, list) and sess_rel else None
        quizzes.append(q)
    return quizzes


@router.patch("/{quiz_id}")
def update_quiz(quiz_id: int, body: QuizUpdate, current: CurrentUser = Depends(require_role("teacher"))):
    """Teacher edits a quiz. Any provided field is updated; if `questions` is
    provided the whole question set is replaced. RLS ensures a teacher can only
    touch their own quizzes."""
    db = current.client

    # Make sure the quiz exists and belongs to this teacher.
    owner = db.table("quizzes").select("id, teacher_id").eq("id", quiz_id).maybe_single().execute()
    if not owner or not owner.data or owner.data.get("teacher_id") != current.id:
        raise HTTPException(status_code=404, detail="Quiz not found.")

    updates = {}
    for field in ("title", "subject", "target_class", "target_section", "duration_seconds", "status", "go_live_immediately"):
        val = getattr(body, field, None)
        if val is not None:
            updates[field] = val
    if body.scheduled_at is not None:
        updates["scheduled_at"] = body.scheduled_at.isoformat()
    # When moving to live, stamp the start time.
    if updates.get("status") == "live" or body.go_live_immediately:
        updates["started_at"] = datetime.utcnow().isoformat()

    if updates:
        db.table("quizzes").update(updates).eq("id", quiz_id).execute()

    questions_count = None
    if body.questions is not None:
        # Replace the full question set.
        db.table("quiz_questions").delete().eq("quiz_id", quiz_id).execute()
        if body.questions:
            rows = [{
                "quiz_id": quiz_id,
                "question_number": q.question_number,
                "category": q.category,
                "question_text": q.question_text,
                "option_a": q.option_a,
                "option_b": q.option_b,
                "option_c": q.option_c,
                "option_d": q.option_d,
                "correct_option": q.correct_option,
            } for q in body.questions]
            db.table("quiz_questions").insert(rows).execute()
        questions_count = len(body.questions)

    return {"id": quiz_id, "updated": True, "questions_count": questions_count}


@router.get("/{quiz_id}")
def get_quiz(quiz_id: int, current: CurrentUser = Depends(get_current_user)):
    """Get a quiz with its questions. correct_option is hidden for students."""
    quiz = current.client.table("quizzes").select("*").eq("id", quiz_id).single().execute()

    # Students see questions without the correct answer
    select_cols = "id, question_number, category, question_text, option_a, option_b, option_c, option_d"
    if current.role == "teacher":
        select_cols += ", correct_option"

    questions = (
        current.client.table("quiz_questions")
        .select(select_cols)
        .eq("quiz_id", quiz_id)
        .order("question_number")
        .execute()
    )
    return {"quiz": quiz.data, "questions": questions.data}


@router.get("/{quiz_id}/results")
def quiz_results(quiz_id: int, current: CurrentUser = Depends(require_role("teacher"))):
    """Analytics for a quiz: per-student attempts, aggregate stats, and a
    per-question accuracy breakdown. Teacher-only, own quiz only."""
    db = current.client

    quiz = db.table("quizzes").select("*").eq("id", quiz_id).maybe_single().execute()
    if not quiz or not quiz.data or quiz.data.get("teacher_id") != current.id:
        raise HTTPException(status_code=404, detail="Quiz not found.")

    # Per-student attempts (joins users for the student's name/email).
    sess = (
        db.table("quiz_sessions")
        .select("*, users(full_name, email)")
        .eq("quiz_id", quiz_id)
        .order("percentage", desc=True)
        .execute()
    )
    results = []
    for s in sess.data or []:
        u = s.pop("users", None) or {}
        s["student_name"] = u.get("full_name")
        s["student_email"] = u.get("email")
        results.append(s)

    attempts = len(results)
    pcts = [float(r.get("percentage") or 0) for r in results]
    stats = {
        "attempts": attempts,
        "average_percentage": round(sum(pcts) / attempts, 1) if attempts else 0,
        "highest_percentage": max(pcts) if pcts else 0,
        "lowest_percentage": min(pcts) if pcts else 0,
        "pass_rate": round(sum(1 for p in pcts if p >= 50) / attempts * 100, 1) if attempts else 0,
    }

    # Per-question accuracy.
    qrows = (
        db.table("quiz_questions")
        .select("id, question_number, question_text")
        .eq("quiz_id", quiz_id)
        .order("question_number")
        .execute()
    )
    questions = qrows.data or []
    qids = [q["id"] for q in questions]
    answers = []
    if qids:
        ans = db.table("quiz_answers").select("question_id, is_correct").in_("question_id", qids).execute()
        answers = ans.data or []

    tally = {qid: {"correct": 0, "total": 0} for qid in qids}
    for a in answers:
        t = tally.get(a["question_id"])
        if t is not None:
            t["total"] += 1
            if a.get("is_correct"):
                t["correct"] += 1

    per_question = []
    for q in questions:
        t = tally[q["id"]]
        accuracy = round(t["correct"] / t["total"] * 100, 1) if t["total"] else 0
        per_question.append({
            "question_number": q["question_number"],
            "question_text": q["question_text"],
            "correct_count": t["correct"],
            "total_answers": t["total"],
            "accuracy": accuracy,
        })

    return {
        "quiz": {
            "id": quiz.data["id"],
            "title": quiz.data["title"],
            "subject": quiz.data.get("subject"),
            "target_class": quiz.data.get("target_class"),
            "status": quiz.data.get("status"),
            "question_count": len(questions),
        },
        "stats": stats,
        "results": results,
        "per_question": per_question,
    }


@router.post("/{quiz_id}/submit")
def submit_quiz(quiz_id: int, body: QuizSubmit, current: CurrentUser = Depends(require_role("student"))):
    """Student submits answers for a quiz. Auto-grades and returns score."""
    db = current.client

    # Load correct answers
    qs = db.table("quiz_questions").select("id, correct_option").eq("quiz_id", quiz_id).execute()
    correct = {q["id"]: q["correct_option"] for q in qs.data}
    total = len(correct)
    if total == 0:
        raise HTTPException(status_code=400, detail="Quiz has no questions.")

    score = 0
    graded = []
    for a in body.answers:
        is_correct = a.selected_option is not None and correct.get(a.question_id) == a.selected_option
        score += 1 if is_correct else 0
        graded.append((a, is_correct))

    pct = round(score / total * 100, 2)
    tier = ("PERFECT" if pct == 100 else "EXCELLENT" if pct >= 80
            else "GOOD" if pct >= 50 else "KEEP GOING")

    sess = db.table("quiz_sessions").upsert({
        "quiz_id": quiz_id,
        "student_id": current.id,
        "score": score,
        "total_questions": total,
        "percentage": pct,
        "tier": tier,
        "time_remaining_seconds": body.time_remaining_seconds,
        "started_at": body.started_at.isoformat(),
        "completed_at": datetime.utcnow().isoformat(),
    }, on_conflict="quiz_id,student_id").execute()
    session_id = sess.data[0]["id"]

    # Clear any prior answers for this session (in case of a re-attempt) then save.
    db.table("quiz_answers").delete().eq("quiz_session_id", session_id).execute()
    answer_rows = [{
        "quiz_session_id": session_id,
        "question_id": a.question_id,
        "selected_option": a.selected_option,
        "is_correct": is_correct,
        "response_time_ms": a.response_time_ms,
    } for a, is_correct in graded]
    if answer_rows:
        db.table("quiz_answers").insert(answer_rows).execute()

    return {"score": score, "total": total, "percentage": pct, "tier": tier, "quiz_session_id": session_id}


@router.get("/{quiz_id}/my-result")
def my_result(quiz_id: int, current: CurrentUser = Depends(require_role("student"))):
    """A student's own graded attempt: their score plus every question with the
    correct option, the option they picked, and whether they got it right."""
    db = current.client

    sess = (
        db.table("quiz_sessions")
        .select("*")
        .eq("quiz_id", quiz_id)
        .eq("student_id", current.id)
        .maybe_single()
        .execute()
    )
    if not sess or not sess.data:
        raise HTTPException(status_code=404, detail="You haven't attempted this quiz yet.")
    session = sess.data

    quiz = db.table("quizzes").select("id, title, subject, target_class").eq("id", quiz_id).maybe_single().execute()
    questions = (
        db.table("quiz_questions")
        .select("id, question_number, category, question_text, option_a, option_b, option_c, option_d, correct_option")
        .eq("quiz_id", quiz_id)
        .order("question_number")
        .execute()
    )
    answers = (
        db.table("quiz_answers")
        .select("question_id, selected_option, is_correct")
        .eq("quiz_session_id", session["id"])
        .execute()
    )
    amap = {a["question_id"]: a for a in (answers.data or [])}

    qlist = []
    for q in questions.data or []:
        a = amap.get(q["id"]) or {}
        q["selected_option"] = a.get("selected_option")
        q["is_correct"] = bool(a.get("is_correct"))
        qlist.append(q)

    return {"quiz": quiz.data if quiz else None, "session": session, "questions": qlist}
