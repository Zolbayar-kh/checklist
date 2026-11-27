-- ============================================================
-- Миний checklist: өгөгдлийн түүх (алдагдлаас хамгаалах)
-- Сервер дээрх хувийн өгөгдөл өөрчлөгдөх бүрт өмнөх хувилбарыг
-- (15 минутад нэгээс ихгүй, сүүлийн 60-ыг) хадгална.
-- Апп-ын Профайл → "Сэргээх" хэсгээс буцааж нэгтгэж болно.
-- Supabase → SQL Editor → New query → хуулж тавиад → Run
-- ============================================================
create table if not exists public.app_state_history (
  id       bigserial primary key,
  user_id  uuid not null references auth.users (id) on delete cascade,
  data     jsonb not null,
  saved_at timestamptz not null default now()
);
create index if not exists app_state_history_user on public.app_state_history (user_id, saved_at desc);

create or replace function public.app_state_keep_history() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.data is distinct from new.data and not exists (
       select 1 from app_state_history
       where user_id = old.user_id and saved_at > now() - interval '15 minutes') then
    insert into app_state_history (user_id, data) values (old.user_id, old.data);
    delete from app_state_history
      where user_id = old.user_id
        and id not in (select id from app_state_history where user_id = old.user_id
                       order by saved_at desc limit 60);
  end if;
  return new;
end $$;
drop trigger if exists app_state_history_trg on public.app_state;
create trigger app_state_history_trg before update on public.app_state
  for each row execute function public.app_state_keep_history();

alter table public.app_state_history enable row level security;
drop policy if exists history_select on public.app_state_history;
create policy history_select on public.app_state_history for select to authenticated
  using (user_id = auth.uid());

grant usage on schema public to authenticated;
grant select on table public.app_state_history to authenticated;
