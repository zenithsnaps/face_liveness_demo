-- Face liveness: attempt log + photo storage
-- Run in Supabase SQL Editor or via supabase db push.

create extension if not exists "pgcrypto";

create type liveness_failure_reason as enum (
  'noFace',
  'multipleFaces',
  'faceTooSmall',
  'faceTooLarge',
  'faceOffCenter',
  'headPoseOff',
  'eyesClosed',
  'smileNotDetected',
  'blinkNotDetected',
  'objectOccluding',
  'handOccluding',
  'cameraError',
  'analyzerError',
  'timeout'
);

create table public.liveness_attempts (
  id                    uuid primary key default gen_random_uuid(),
  created_at            timestamptz not null default now(),

  -- outcome
  passed                boolean not null,
  failure_reason        liveness_failure_reason,
  failure_message       text,

  -- scores (values shown on summary screen)
  face_score            real,
  face_score_percent    real generated always as (face_score * 100) stored,
  face_score_threshold  real,

  -- timing
  started_at            timestamptz not null,
  completed_at          timestamptz not null,
  duration_ms           integer generated always as
                          ((extract(epoch from (completed_at - started_at)) * 1000)::int) stored,

  -- storage ref: snapshot of the summary screen (PNG)
  summary_bucket        text,
  summary_path          text,
  summary_bytes         integer,
  summary_width         integer,
  summary_height        integer,

  -- post-capture occlusion check detail (null for gate-level failures)
  occlusion_check       jsonb,

  -- device
  platform              text,
  app_version           text,
  device_model          text,
  camera_resolution     text,

  constraint passed_has_no_failure check (
    (passed = true  and failure_reason is null) or
    (passed = false and failure_reason is not null)
  )
);

create index liveness_attempts_created_idx
  on public.liveness_attempts (created_at desc);

create index liveness_attempts_passed_idx
  on public.liveness_attempts (passed, created_at desc);

create index liveness_attempts_reason_idx
  on public.liveness_attempts (failure_reason)
  where failure_reason is not null;

-- Storage bucket: summary PNG screenshots (public for demo simplicity)
insert into storage.buckets (id, name, public)
values ('liveness-summaries', 'liveness-summaries', true)
on conflict (id) do nothing;

-- RLS: permissive for demo (anon can insert/select)
alter table public.liveness_attempts enable row level security;

create policy "attempts_insert_anon"
  on public.liveness_attempts for insert to anon, authenticated
  with check (true);

create policy "attempts_select_anon"
  on public.liveness_attempts for select to anon, authenticated
  using (true);

create policy "storage_anon_rw"
  on storage.objects for all to anon, authenticated
  using (bucket_id = 'liveness-summaries')
  with check (bucket_id = 'liveness-summaries');
