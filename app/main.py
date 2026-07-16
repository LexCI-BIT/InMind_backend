"""
InMind App — FastAPI entrypoint.

Mounts all routers and configures CORS.
Run with:  uvicorn app.main:app --reload
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import get_settings
from .routers import auth, audio, flows, insights, journal, quizzes, thoughts

settings = get_settings()

app = FastAPI(
    title="InMind App API",
    version="1.0.0",
    description="Backend for the InMind student/teacher/parent ecosystem.",
)

# CORS — open in dev; tighten allow_origins for production
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "http://localhost:3000",
        "http://127.0.0.1:5173",
        "http://127.0.0.1:3000",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(audio.router)
app.include_router(flows.router)
app.include_router(quizzes.router)
app.include_router(journal.router)
app.include_router(insights.router)
app.include_router(thoughts.router)


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "env": settings.app_env,
        "supabase_url": settings.supabase_url,
        "service_role_configured": bool(settings.supabase_service_role_key),
    }
