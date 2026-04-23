-- Tester-supplied label identifying which test case this attempt was for.
alter table public.liveness_attempts
  add column if not exists test_case text;
