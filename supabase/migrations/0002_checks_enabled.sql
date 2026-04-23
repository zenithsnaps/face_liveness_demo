-- Record which post-capture MediaPipe checks were enabled for the attempt.
alter table public.liveness_attempts
  add column if not exists face_check_enabled boolean,
  add column if not exists hand_check_enabled boolean;
