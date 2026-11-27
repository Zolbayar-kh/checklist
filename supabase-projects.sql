-- ============================================================
-- Миний checklist: багийн төслүүд
-- Supabase → SQL Editor → New query → энэ бүгдийг хуулж тавиад → Run
-- (supabase.sql-ийг өмнө нь ажиллуулсан байх ёстой)
-- Дахин ажиллуулахад аюулгүй: байгаа өгөгдлийг устгахгүй.
-- ============================================================

-- 1. Хэрэглэгчийн профайл (гишүүдийн нэр, имэйлийг харуулах, урихад)
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  email        text not null,
  display_name text,
  created_at   timestamptz not null default now()
);
create unique index if not exists profiles_email_lower on public.profiles (lower(email));

insert into public.profiles (id, email)
  select id, email from auth.users where email is not null
  on conflict (id) do nothing;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email) values (new.id, new.email) on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2. Төсөл, гишүүд, урилга, ажлууд
create table if not exists public.projects (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 120),
  description text not null default '',
  color       text not null default '#9b6cf0',
  start_date  date,
  end_date    date,
  budget      numeric(14,0) not null default 0 check (budget >= 0),
  archived    boolean not null default false,
  owner_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.project_members (
  project_id uuid not null references public.projects (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  role       text not null default 'member' check (role in ('owner','member')),
  joined_at  timestamptz not null default now(),
  primary key (project_id, user_id)
);
create index if not exists project_members_user on public.project_members (user_id);

create table if not exists public.project_invites (
  project_id uuid not null references public.projects (id) on delete cascade,
  email      text not null,
  invited_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (project_id, email)
);

create table if not exists public.project_tasks (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects (id) on delete cascade,
  title       text not null check (char_length(title) between 1 and 200),
  description text not null default '',
  status      text not null default 'todo' check (status in ('todo','doing','done')),
  priority    text not null default 'med'  check (priority in ('low','med','high')),
  assignee    uuid references public.profiles (id) on delete set null,
  start_date  date,
  due_date    date,
  planned     numeric(14,0) not null default 0 check (planned >= 0),
  actual      numeric(14,0) not null default 0 check (actual >= 0),
  steps       jsonb not null default '[]'::jsonb,
  created_by  uuid default auth.uid() references auth.users (id) on delete set null,
  done_at     timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists project_tasks_project on public.project_tasks (project_id);

-- 3. Туслах функцууд
create or replace function public.is_project_member(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from project_members where project_id = p and user_id = auth.uid())
$$;
create or replace function public.is_project_owner(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from project_members where project_id = p and user_id = auth.uid() and role = 'owner')
$$;
create or replace function public.shares_project(other uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from project_members a join project_members b on a.project_id = b.project_id
                 where a.user_id = auth.uid() and b.user_id = other)
$$;

-- Төсөл үүсгэсэн хүн автоматаар "эзэн" гишүүн болно
create or replace function public.add_project_owner() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, email) select u.id, u.email from auth.users u where u.id = new.owner_id
    on conflict (id) do nothing;
  insert into project_members (project_id, user_id, role) values (new.id, new.owner_id, 'owner')
    on conflict do nothing;
  return new;
end $$;
drop trigger if exists project_owner_member on public.projects;
create trigger project_owner_member after insert on public.projects
  for each row execute function public.add_project_owner();

create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
drop trigger if exists projects_touch on public.projects;
create trigger projects_touch before update on public.projects
  for each row execute function public.touch_updated_at();
drop trigger if exists project_tasks_touch on public.project_tasks;
create trigger project_tasks_touch before update on public.project_tasks
  for each row execute function public.touch_updated_at();

-- 4. Урих, урилга хүлээн авах
create or replace function public.invite_to_project(p_project uuid, p_email text) returns text
language plpgsql security definer set search_path = public as $$
declare v_user uuid; v_email text := lower(trim(p_email));
begin
  if not is_project_member(p_project) then raise exception 'not a project member'; end if;
  if v_email is null or position('@' in v_email) = 0 then raise exception 'invalid email'; end if;
  select id into v_user from profiles where lower(email) = v_email;
  if v_user is not null then
    if exists (select 1 from project_members where project_id = p_project and user_id = v_user) then
      return 'already';
    end if;
    insert into project_members (project_id, user_id, role) values (p_project, v_user, 'member');
    return 'added';
  end if;
  insert into project_invites (project_id, email) values (p_project, v_email) on conflict do nothing;
  return 'invited';
end $$;

create or replace function public.accept_project_invites() returns integer
language plpgsql security definer set search_path = public as $$
declare v_email text := lower(coalesce(auth.jwt() ->> 'email', '')); n integer := 0;
begin
  if auth.uid() is null or v_email = '' then return 0; end if;
  insert into profiles (id, email) values (auth.uid(), v_email) on conflict (id) do nothing;
  insert into project_members (project_id, user_id, role)
    select project_id, auth.uid(), 'member' from project_invites where lower(email) = v_email
    on conflict do nothing;
  get diagnostics n = row_count;
  delete from project_invites where lower(email) = v_email;
  return n;
end $$;

revoke execute on function public.invite_to_project(uuid, text) from anon;
revoke execute on function public.accept_project_invites() from anon;
grant execute on function public.invite_to_project(uuid, text) to authenticated;
grant execute on function public.accept_project_invites() to authenticated;

-- 5. Хамгаалалтын дүрэм (RLS): зөвхөн төслийн гишүүд хардаг, засдаг
alter table public.profiles        enable row level security;
alter table public.projects        enable row level security;
alter table public.project_members enable row level security;
alter table public.project_invites enable row level security;
alter table public.project_tasks   enable row level security;

drop policy if exists profiles_select on public.profiles;
drop policy if exists profiles_insert on public.profiles;
drop policy if exists profiles_update on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or shares_project(id));
create policy profiles_insert on public.profiles for insert to authenticated
  with check (id = auth.uid());
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists projects_select on public.projects;
drop policy if exists projects_insert on public.projects;
drop policy if exists projects_update on public.projects;
drop policy if exists projects_delete on public.projects;
create policy projects_select on public.projects for select to authenticated
  using (is_project_member(id) or owner_id = auth.uid());
create policy projects_insert on public.projects for insert to authenticated
  with check (owner_id = auth.uid());
create policy projects_update on public.projects for update to authenticated
  using (is_project_member(id)) with check (is_project_member(id));
create policy projects_delete on public.projects for delete to authenticated
  using (is_project_owner(id));

drop policy if exists members_select on public.project_members;
drop policy if exists members_delete on public.project_members;
create policy members_select on public.project_members for select to authenticated
  using (is_project_member(project_id));
create policy members_delete on public.project_members for delete to authenticated
  using ((is_project_owner(project_id) and user_id <> auth.uid())
      or (user_id = auth.uid() and role <> 'owner'));

drop policy if exists invites_select on public.project_invites;
drop policy if exists invites_delete on public.project_invites;
create policy invites_select on public.project_invites for select to authenticated
  using (is_project_member(project_id));
create policy invites_delete on public.project_invites for delete to authenticated
  using (is_project_member(project_id));

drop policy if exists tasks_select on public.project_tasks;
drop policy if exists tasks_insert on public.project_tasks;
drop policy if exists tasks_update on public.project_tasks;
drop policy if exists tasks_delete on public.project_tasks;
create policy tasks_select on public.project_tasks for select to authenticated
  using (is_project_member(project_id));
create policy tasks_insert on public.project_tasks for insert to authenticated
  with check (is_project_member(project_id));
create policy tasks_update on public.project_tasks for update to authenticated
  using (is_project_member(project_id)) with check (is_project_member(project_id));
create policy tasks_delete on public.project_tasks for delete to authenticated
  using (is_project_member(project_id));

-- 6. Шууд шинэчлэлт (багийн гишүүний өөрчлөлт шууд харагдана)
do $$
begin
  begin alter publication supabase_realtime add table public.project_tasks;   exception when duplicate_object then null; when undefined_object then null; end;
  begin alter publication supabase_realtime add table public.projects;        exception when duplicate_object then null; when undefined_object then null; end;
  begin alter publication supabase_realtime add table public.project_members; exception when duplicate_object then null; when undefined_object then null; end;
end $$;

-- 7. Нэвтэрсэн хэрэглэгчид хүснэгт, функц ашиглах эрх
--    (Supabase-ийн шинэ төслүүд SQL-ээр үүсгэсэн хүснэгтэд энэ эрхийг автоматаар өгдөггүй)
grant usage on schema public to authenticated;
grant select, insert, update, delete on table
  public.app_state, public.profiles, public.projects,
  public.project_members, public.project_invites, public.project_tasks
to authenticated;
grant execute on function
  public.is_project_member(uuid), public.is_project_owner(uuid), public.shares_project(uuid),
  public.invite_to_project(uuid, text), public.accept_project_invites()
to authenticated;
