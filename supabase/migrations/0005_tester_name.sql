-- Tester identity. Free-text name typed into the home screen field.
alter table public.liveness_attempts
  add column if not exists tester_name text;

create index if not exists liveness_attempts_tester_idx
  on public.liveness_attempts (tester_name)
  where tester_name is not null;
