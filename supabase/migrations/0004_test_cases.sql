-- Tester-curated list of test case labels.
-- Seeded with the 7 demo cases; tester can add more from the home screen.

create table public.test_cases (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  position    integer not null,
  created_at  timestamptz not null default now()
);

create index test_cases_position_idx on public.test_cases (position);

alter table public.test_cases enable row level security;

create policy "test_cases_select_anon"
  on public.test_cases for select to anon, authenticated
  using (true);

create policy "test_cases_insert_anon"
  on public.test_cases for insert to anon, authenticated
  with check (true);

create policy "test_cases_delete_anon"
  on public.test_cases for delete to anon, authenticated
  using (true);

insert into public.test_cases (name, position) values
  ('หน้าปกติ',          1),
  ('ปิดปาก',            2),
  ('ปิดปากปิดจมูก',     3),
  ('ปิดครึ่งหน้า',       4),
  ('ปิดมากกว่า 50%',    5),
  ('หลับตา 2 ข้าง',     6),
  ('ภาพมืด',            7)
on conflict (name) do nothing;
