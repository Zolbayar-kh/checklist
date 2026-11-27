-- Миний checklist: хэрэглэгч бүрийн өгөгдлийг хадгалах хүснэгт
-- Supabase → SQL Editor → New query → энэ бүгдийг хуулж тавиад → Run

create table if not exists public.app_state (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.app_state enable row level security;

-- Хэрэглэгч зөвхөн өөрийнхөө мөрийг унших, бичих, устгах эрхтэй
drop policy if exists "own_select" on public.app_state;
drop policy if exists "own_insert" on public.app_state;
drop policy if exists "own_update" on public.app_state;
drop policy if exists "own_delete" on public.app_state;

create policy "own_select" on public.app_state
  for select to authenticated using (auth.uid() = user_id);
create policy "own_insert" on public.app_state
  for insert to authenticated with check (auth.uid() = user_id);
create policy "own_update" on public.app_state
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own_delete" on public.app_state
  for delete to authenticated using (auth.uid() = user_id);

-- Нэвтэрсэн хэрэглэгчид хүснэгт ашиглах эрх (шинэ Supabase төслүүдэд заавал хэрэгтэй)
grant usage on schema public to authenticated;
grant select, insert, update, delete on table public.app_state to authenticated;
