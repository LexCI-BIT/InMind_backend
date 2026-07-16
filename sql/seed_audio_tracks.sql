-- ============================================================
-- InMind · seed data — audio_tracks
-- Preserved from the original 002_audio_tracks.sql migration.
-- Replace the audio_url values with real Supabase Storage URLs
-- after uploading files to the 'audio-space' bucket.
-- ============================================================

insert into public.audio_tracks (title, description, category, sub_category, audio_url, duration_seconds, author, sort_order)
values
  ('2-Min Calm Breathing',   'A quick guided breathing exercise to reset your mind.',       'clip',      'breathing',   'https://example.com/placeholder.mp3', 120, 'InMind',           1),
  ('Morning Zen',            'Start your day with a 5-minute mindfulness meditation.',      'clip',      'meditation',  'https://example.com/placeholder.mp3', 300, 'InMind',           2),
  ('Ocean Mist',             'Gentle ocean sounds for instant calm.',                       'clip',      'calm',        'https://example.com/placeholder.mp3', 180, 'InMind',           3),
  ('Breath Release',         'Release tension through rhythmic breathing.',                 'clip',      'breathing',   'https://example.com/placeholder.mp3', 120, 'InMind',           4),
  ('Mental Reset',           'A quick 2-minute focus reset exercise.',                      'clip',      'focus',       'https://example.com/placeholder.mp3', 120, 'InMind',           5),
  ('Neural Sync Beats',      'Optimized frequencies for high cognitive output.',            'focus',     'deep work',   'https://example.com/placeholder.mp3', 2700, 'InMind Audio Lab',  6),
  ('Binaural Study Hub',     'Deep work session with binaural beats.',                      'focus',     'deep work',   'https://example.com/placeholder.mp3', 2700, 'InMind Audio Lab',  7),
  ('Lo-Fi Coding Ambience',  'Productivity ambience for long coding sessions.',             'focus',     'productivity','https://example.com/placeholder.mp3', 3600,'InMind Audio Lab',  8),
  ('Atomic Habits',          'Key insights from the bestselling book by James Clear.',      'audiobook', null,          'https://example.com/placeholder.mp3', 600, 'James Clear',       9),
  ('The Power of Now',       'Eckhart Tolle''s guide to spiritual enlightenment.',          'audiobook', null,          'https://example.com/placeholder.mp3', 720, 'Eckhart Tolle',    10),
  ('Ego is the Enemy',       'Ryan Holiday on the dangers of ego in our lives.',            'audiobook', null,          'https://example.com/placeholder.mp3', 600, 'Ryan Holiday',     11)
on conflict do nothing;
