# InMind — Database Schema

Complete PostgreSQL/Supabase schema for the InMind student wellbeing platform.
This reflects the live production schema on project `rvphxztkiucxvihduqcm` as of 2026-07-16.

## Structure

```
inmind-database/
├── schema.sql                  ← everything in ONE file, ready to run on a fresh project
├── 00_setup/
│   └── 00_types_and_functions.sql   (user_role enum, current_role, handle_new_user, set_updated_at, auth trigger, grants)
├── 01_identity/
│   ├── 01_users.sql            (central identity, extends auth.users)
│   ├── 02_students.sql
│   ├── 03_parents.sql
│   └── 04_teachers.sql
├── 02_checkin_flows/
│   ├── 01_flow_sessions.sql    (parent record for every check-in)
│   ├── 02_static_flow_responses.sql
│   ├── 03_dynamic_flow_responses.sql
│   ├── 04_behavioral_signals.sql
│   └── 05_challenges.sql
├── 03_quizzes/
│   ├── 01_quizzes.sql
│   ├── 02_quiz_questions.sql
│   ├── 03_quiz_sessions.sql
│   └── 04_quiz_answers.sql
├── 04_journal/
│   ├── 01_journal_entries.sql
│   └── 02_journal_tags.sql
├── 05_social/
│   └── 01_thoughts.sql
└── 06_audio/
    ├── 01_audio_tracks.sql
    └── 02_audio_playback_progress.sql
```

Every table file is self-contained: CREATE TABLE + constraints + indexes +
updated_at trigger (where applicable) + RLS enable + all policies for that table.

## Run order (fresh database)

Folder numbering IS the dependency order:

1. `00_setup` — types and functions (everything depends on these)
2. `01_identity` — users first, then students/parents/teachers
3. `02_checkin_flows` — flow_sessions first, then its children
4. `03_quizzes` — quizzes → questions → sessions → answers
5. `04_journal` — entries → tags
6. `05_social`, `06_audio` — independent

Or just run `schema.sql`, which contains all of the above in the correct order.

## Security model

- Every table has RLS enabled.
- `current_role()` (SECURITY DEFINER) returns the caller's role and powers all
  role-based policies. General pattern: users can read/write their own rows;
  teachers and admins get elevated read access; quizzes are teacher-owned;
  audio_tracks are read-only for users and writable by admins only.
- `handle_new_user()` auto-creates a `public.users` row on signup from
  auth metadata (`role`, `full_name`, `phone_number`).
- Trigger/helper functions are not callable via the public API (grants revoked).

## Notes

- `users.role` is varchar constrained to student/parent/teacher; the
  `user_role` enum (which also includes admin) exists for policy expressions.
- `static_flow_responses` allows exactly one row per session AND one per
  user per day (`uq_static_flow_user_date`).
- All FKs cascade on delete, so removing a user cleanly removes their data.
