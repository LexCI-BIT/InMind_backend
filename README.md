# 🧠 InMind Backend API

Backend service for the **InMind** student/teacher/parent mental-wellness ecosystem.  
Built with **FastAPI** and **Supabase** (Auth + Postgres + Storage).

---

## 📦 Tech Stack

| Layer          | Technology                        |
| -------------- | --------------------------------- |
| Framework      | FastAPI                           |
| Runtime        | Python 3.10+                      |
| Database       | PostgreSQL (via Supabase)         |
| Auth           | Supabase Auth (JWT)               |
| ORM / Client   | Supabase Python SDK               |
| Validation     | Pydantic v2 + Pydantic Settings   |
| Server         | Uvicorn (ASGI)                    |

---

## 🗂️ Project Structure

```
backend/
├── app/
│   ├── main.py              # FastAPI entrypoint, CORS & router mounting
│   ├── config.py            # Pydantic Settings (env vars)
│   ├── deps.py              # Dependency injection (auth, current user)
│   ├── schemas.py           # Request/response Pydantic models
│   ├── scoring.py           # Quiz scoring logic
│   ├── supabase_client.py   # Supabase client helpers
│   └── routers/
│       ├── auth.py          # Signup, login, profile, logout
│       ├── audio.py         # Audio tracks & playback progress
│       ├── flows.py         # Dynamic activity flows
│       ├── insights.py      # Student behavioral insights
│       ├── journal.py       # Student journaling
│       ├── quizzes.py       # Quiz CRUD, submission & grading
│       └── thoughts.py      # Share-a-thought feature
├── sql/
│   ├── 001_full_schema.sql  # Full database schema
│   ├── 002_audio_tracks.sql # Audio tracks table & seed data
│   └── 003_schema_patch.sql # Schema migrations / patches
├── .env.example             # Environment variable template
├── requirements.txt         # Python dependencies
└── README.md
```

---

## 🚀 Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/LexCI-BIT/InMind_backend.git
cd InMind_backend
```

### 2. Create a virtual environment

```bash
python -m venv venv

# Windows
venv\Scripts\activate

# macOS / Linux
source venv/bin/activate
```

### 3. Install dependencies

```bash
pip install -r requirements.txt
```

### 4. Configure environment variables

```bash
cp .env.example .env
```

Open `.env` and fill in values from your **Supabase Dashboard → Project Settings → API**:

| Variable                     | Description                                      |
| ---------------------------- | ------------------------------------------------ |
| `SUPABASE_URL`               | Your Supabase project URL                        |
| `SUPABASE_PROJECT_REF`       | Project reference ID                             |
| `SUPABASE_ANON_KEY`          | Public anon key (client-safe)                    |
| `SUPABASE_PUBLISHABLE_KEY`   | Publishable key (optional)                       |
| `SUPABASE_SERVICE_ROLE_KEY`  | Service role key (server-only, bypasses RLS)     |
| `DATABASE_URL`               | Direct Postgres connection string (optional)     |
| `APP_ENV`                    | `development` or `production`                    |

### 5. Set up the database

Run the SQL migration files in order against your Supabase project:

```
sql/001_full_schema.sql
sql/002_audio_tracks.sql
sql/003_schema_patch.sql
```

You can execute these via the **Supabase SQL Editor** or any Postgres client.

### 6. Run the server

```bash
uvicorn app.main:app --reload
```

The API will be available at **http://localhost:8000**

---

## 📡 API Endpoints

### Health Check

| Method | Endpoint   | Description          |
| ------ | ---------- | -------------------- |
| GET    | `/health`  | Server health status |

### Auth (`/auth`)

| Method | Endpoint              | Description                |
| ------ | --------------------- | -------------------------- |
| POST   | `/auth/signup/student` | Student registration       |
| POST   | `/auth/signup/parent`  | Parent registration        |
| POST   | `/auth/signup/teacher` | Teacher registration       |
| POST   | `/auth/login`          | Login (returns JWT tokens) |
| GET    | `/auth/me`             | Get current user profile   |
| PATCH  | `/auth/me`             | Update profile             |
| POST   | `/auth/logout`         | Logout                     |
| POST   | `/auth/refresh`        | Refresh access token       |

### Quizzes (`/api/quizzes`)

| Method | Endpoint                   | Description                            |
| ------ | -------------------------- | -------------------------------------- |
| POST   | `/api/quizzes`             | Teacher creates a quiz + questions     |
| GET    | `/api/quizzes`             | List all quizzes (filtered by RLS)     |
| GET    | `/api/quizzes/{id}`        | Get quiz with questions                |
| PATCH  | `/api/quizzes/{id}`        | Teacher edits a quiz                   |
| POST   | `/api/quizzes/{id}/submit` | Student submits answers & gets graded  |

### Audio (`/api/audio`)

| Method | Endpoint                        | Description                  |
| ------ | ------------------------------- | ---------------------------- |
| GET    | `/api/audio/tracks`             | List audio tracks            |
| GET    | `/api/audio/progress`           | Get playback progress        |
| POST   | `/api/audio/progress`           | Save playback progress       |

### Flows (`/api/flows`)

| Method | Endpoint           | Description                |
| ------ | ------------------ | -------------------------- |
| GET    | `/api/flows`       | List dynamic activity flows|
| POST   | `/api/flows`       | Create / save flow data    |

### Journal (`/api/journal`)

| Method | Endpoint           | Description             |
| ------ | ------------------ | ----------------------- |
| GET    | `/api/journal`     | Get journal entries     |
| POST   | `/api/journal`     | Create journal entry    |

### Insights (`/api/insights`)

| Method | Endpoint           | Description                  |
| ------ | ------------------ | ---------------------------- |
| GET    | `/api/insights`    | Get student behavioral data  |

### Thoughts (`/api/thoughts`)

| Method | Endpoint           | Description            |
| ------ | ------------------ | ---------------------- |
| GET    | `/api/thoughts`    | List shared thoughts   |
| POST   | `/api/thoughts`    | Share a new thought    |

> 📝 Full interactive API docs available at **http://localhost:8000/docs** (Swagger UI)

---

## 🔒 Authentication

The API uses **Supabase Auth** with JWT tokens:

1. Sign up or log in via `/auth/signup/*` or `/auth/login`
2. Receive `access_token` and `refresh_token`
3. Include the access token in subsequent requests:
   ```
   Authorization: Bearer <access_token>
   ```
4. Role-based access control enforces permissions for **student**, **parent**, and **teacher** roles

---

## 🧪 API Documentation

Once the server is running, visit:

- **Swagger UI**: [http://localhost:8000/docs](http://localhost:8000/docs)
- **ReDoc**: [http://localhost:8000/redoc](http://localhost:8000/redoc)

---

## 🤝 Related

- **Frontend (PWA)**: [InMind_PWA](https://github.com/LexCI-BIT/InMind_PWA)

---

## 📄 License

This project is part of the InMind ecosystem developed by **LexCI-BIT**.
