-- =====================================================================
--  Revive Rewards — database setup
--  Run this ONCE in Supabase:  SQL Editor  →  New query  →  paste  →  Run
--  Then run first-admin.sql to create your own login.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- tables ----------------------------------------------------

create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  username    text not null unique check (username ~ '^[a-z0-9._-]{2,40}$'),
  full_name   text not null check (char_length(full_name) between 1 and 80),
  title       text not null default '',
  facility    text not null default '',
  role        text not null default 'staff' check (role in ('staff','admin')),
  active      boolean not null default true,
  must_change_password boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.settings (
  id                int primary key default 1 check (id = 1),
  program_name      text not null default 'Revive Rewards',
  point_value_cents numeric not null default 10 check (point_value_cents > 0),
  core_values       text[] not null default array[
    'Respectful to All',
    'Doing the Right Thing, the Right Way, at the Right Time',
    'Accommodating for Family Needs and Support',
    'Educationally Supportive',
    'Environmentally Friendly',
    'Strategically Innovative'],
  facilities        text[] not null default array['Alpine Skilled Nursing'],
  timezone          text not null default 'America/Los_Angeles'
);
insert into public.settings (id) values (1) on conflict do nothing;

create table if not exists public.posts (
  id          uuid primary key default gen_random_uuid(),
  author      uuid not null references public.profiles(id) on delete cascade,
  recipients  uuid[] not null check (cardinality(recipients) between 1 and 50),
  body        text not null check (char_length(body) between 1 and 1000),
  core_value  text,
  image_path  text,
  created_at  timestamptz not null default now()
);
create index if not exists posts_created_idx on public.posts (created_at desc);
create index if not exists posts_recipients_idx on public.posts using gin (recipients);

-- points are added to posts by admins only (one row per time an admin adds points)
create table if not exists public.post_points (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references public.posts(id) on delete cascade,
  given_by    uuid references public.profiles(id) on delete set null,
  recipients  uuid[] not null check (cardinality(recipients) between 1 and 50),
  points_each int  not null check (points_each between 1 and 100000),
  created_at  timestamptz not null default now()
);
create index if not exists post_points_post_idx on public.post_points (post_id);
create index if not exists post_points_recipients_idx on public.post_points using gin (recipients);

-- birthdays (month + day only, no year, so no ages are stored) and hire dates for work anniversaries
alter table public.profiles add column if not exists birth_month int check (birth_month between 1 and 12);
alter table public.profiles add column if not exists birth_day   int check (birth_day between 1 and 31);
alter table public.profiles add column if not exists hire_date   date;

-- upgrading from the first version (peer points + monthly allowance): remove the old pieces
drop policy if exists posts_delete on public.posts;
drop function if exists public.give_award(uuid[], text, text, int, text);
drop function if exists public.points_left();
drop function if exists public.month_start();
alter table public.posts drop column if exists points_each;
alter table public.posts drop column if exists kind;
alter table public.settings drop column if exists allowance;

create table if not exists public.likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table if not exists public.comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.posts(id) on delete cascade,
  author     uuid not null references public.profiles(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
create index if not exists comments_post_idx on public.comments (post_id);

create table if not exists public.rewards (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 80),
  description text not null default '',
  emoji       text not null default '🎁',
  cost        int  not null check (cost > 0),
  active      boolean not null default true,
  sort        int  not null default 0
);

create table if not exists public.redemptions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  reward_id   uuid references public.rewards(id) on delete set null,
  reward_name text not null,
  cost        int  not null check (cost > 0),
  status      text not null default 'pending' check (status in ('pending','sent','declined')),
  note        text not null default '',
  created_at  timestamptz not null default now(),
  handled_by  uuid references public.profiles(id) on delete set null,
  handled_at  timestamptz
);

-- ---------- helpers ---------------------------------------------------

create or replace function public.is_active() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active);
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active and role = 'admin');
$$;

-- ---------- row level security (who can see / change what) ------------

alter table public.profiles    enable row level security;
alter table public.settings    enable row level security;
alter table public.posts       enable row level security;
alter table public.post_points enable row level security;
alter table public.likes       enable row level security;
alter table public.comments    enable row level security;
alter table public.rewards     enable row level security;
alter table public.redemptions enable row level security;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated
  using (public.is_active() or id = auth.uid());

drop policy if exists settings_read on public.settings;
create policy settings_read on public.settings for select to authenticated using (public.is_active());
drop policy if exists settings_admin on public.settings;
create policy settings_admin on public.settings for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists posts_read on public.posts;
create policy posts_read on public.posts for select to authenticated using (public.is_active());
drop policy if exists posts_delete on public.posts;
create policy posts_delete on public.posts for delete to authenticated
  using (public.is_admin() or (author = auth.uid() and public.is_active()
         and not exists (select 1 from public.post_points pp where pp.post_id = posts.id)));
-- (once an admin has added points, only an admin can remove the post)
-- posts are only created through give_shoutout() below

drop policy if exists post_points_read on public.post_points;
create policy post_points_read on public.post_points for select to authenticated using (public.is_active());
-- points are only added/removed through add_points() / remove_points() below

drop policy if exists likes_read on public.likes;
create policy likes_read on public.likes for select to authenticated using (public.is_active());
drop policy if exists likes_add on public.likes;
create policy likes_add on public.likes for insert to authenticated
  with check (user_id = auth.uid() and public.is_active());
drop policy if exists likes_remove on public.likes;
create policy likes_remove on public.likes for delete to authenticated using (user_id = auth.uid());

drop policy if exists comments_read on public.comments;
create policy comments_read on public.comments for select to authenticated using (public.is_active());
drop policy if exists comments_add on public.comments;
create policy comments_add on public.comments for insert to authenticated
  with check (author = auth.uid() and public.is_active());
drop policy if exists comments_remove on public.comments;
create policy comments_remove on public.comments for delete to authenticated
  using (author = auth.uid() or public.is_admin());

drop policy if exists rewards_read on public.rewards;
create policy rewards_read on public.rewards for select to authenticated using (public.is_active());
drop policy if exists rewards_admin on public.rewards;
create policy rewards_admin on public.rewards for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists redemptions_read on public.redemptions;
create policy redemptions_read on public.redemptions for select to authenticated
  using ((user_id = auth.uid() and public.is_active()) or public.is_admin());
-- redemptions are only created/changed through redeem() / set_redemption_status()

-- ---------- points ----------------------------------------------------

-- balances: everyone sees their own; admins see everyone
create or replace function public.points_summary(p_user uuid default null)
returns table (user_id uuid, received bigint, redeemed bigint, balance bigint)
language sql stable security definer set search_path = public as $$
  with r as (select unnest(recipients) as uid, points_each as pts from public.post_points),
       rec as (select uid, sum(pts) as s from r group by uid),
       red as (select user_id as uid, sum(cost) as s from public.redemptions where status <> 'declined' group by user_id)
  select p.id, coalesce(rec.s, 0), coalesce(red.s, 0), coalesce(rec.s, 0) - coalesce(red.s, 0)
  from public.profiles p
  left join rec on rec.uid = p.id
  left join red on red.uid = p.id
  where public.is_active()
    and (public.is_admin() or p.id = auth.uid())
    and (p_user is null or p.id = p_user);
$$;

-- admins add points to any post, for some or all of the people it recognizes (never themselves)
create or replace function public.add_points(p_post uuid, p_recipients uuid[], p_points int)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_post public.posts; v_rec uuid[]; v_n int; v_id uuid;
begin
  if not public.is_admin() then raise exception 'Only admins can give points.'; end if;
  select * into v_post from public.posts where id = p_post;
  if not found then raise exception 'That post no longer exists.'; end if;
  if coalesce(p_points, 0) < 1 or p_points > 100000 then raise exception 'Enter a number of points from 1 to 100,000.'; end if;
  select array_agg(distinct x) into v_rec from unnest(coalesce(p_recipients, v_post.recipients)) x
   where x = any(v_post.recipients) and x <> auth.uid();
  v_n := coalesce(cardinality(v_rec), 0);
  if v_n = 0 then raise exception 'Pick at least one person on this post (you can''t give points to yourself).'; end if;
  if (select count(*) from public.profiles where id = any(v_rec) and active) <> v_n then
    raise exception 'Someone you picked is no longer an active employee.'; end if;
  insert into public.post_points (post_id, given_by, recipients, points_each)
  values (p_post, auth.uid(), v_rec, p_points) returning id into v_id;
  return v_id;
end $$;

create or replace function public.remove_points(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Only admins can remove points.'; end if;
  delete from public.post_points where id = p_id;
end $$;

-- everyone can post shout-outs; only admins can attach points while posting
create or replace function public.give_shoutout(
  p_recipients uuid[], p_body text, p_value text, p_points int, p_image text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_rec uuid[]; v_n int; v_id uuid;
begin
  if not public.is_active() then raise exception 'Your account is not active.'; end if;
  select array_agg(distinct x) into v_rec from unnest(p_recipients) x where x is not null and x <> auth.uid();
  v_n := coalesce(cardinality(v_rec), 0);
  if v_n = 0 then raise exception 'Pick at least one coworker to recognize.'; end if;
  if v_n > 50 then raise exception 'You can recognize up to 50 people in one post.'; end if;
  if (select count(*) from public.profiles where id = any(v_rec) and active) <> v_n then
    raise exception 'Someone you picked is no longer an active employee.'; end if;
  p_body := btrim(coalesce(p_body, ''));
  if char_length(p_body) = 0 or char_length(p_body) > 1000 then raise exception 'Your message must be 1 to 1000 characters.'; end if;
  if coalesce(p_points, 0) < 0 then raise exception 'Points cannot be negative.'; end if;
  if coalesce(p_points, 0) > 0 and not public.is_admin() then raise exception 'Only admins can give points.'; end if;
  if coalesce(p_image, '') <> '' and split_part(p_image, '/', 1) <> auth.uid()::text then raise exception 'Invalid photo.'; end if;
  insert into public.posts (author, recipients, body, core_value, image_path)
  values (auth.uid(), v_rec, p_body, nullif(left(btrim(coalesce(p_value, '')), 80), ''), nullif(p_image, ''))
  returning id into v_id;
  if coalesce(p_points, 0) > 0 then perform public.add_points(v_id, v_rec, p_points); end if;
  return v_id;
end $$;

create or replace function public.redeem(p_reward uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare r public.rewards; v_bal bigint; v_id uuid;
begin
  if not public.is_active() then raise exception 'Your account is not active.'; end if;
  select * into r from public.rewards where id = p_reward and active;
  if not found then raise exception 'That reward is no longer available.'; end if;
  perform pg_advisory_xact_lock(hashtext('bal:' || auth.uid()::text));
  select balance into v_bal from public.points_summary(auth.uid());
  if coalesce(v_bal, 0) < r.cost then raise exception 'You don''t have enough points for that reward.'; end if;
  insert into public.redemptions (user_id, reward_id, reward_name, cost)
  values (auth.uid(), r.id, r.name, r.cost) returning id into v_id;
  return v_id;
end $$;

create or replace function public.set_redemption_status(p_id uuid, p_status text, p_note text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Only admins can do that.'; end if;
  if p_status not in ('pending','sent','declined') then raise exception 'Unknown status.'; end if;
  update public.redemptions
     set status = p_status, note = left(coalesce(p_note, ''), 300),
         handled_by = case when p_status = 'pending' then null else auth.uid() end,
         handled_at = case when p_status = 'pending' then null else now() end
   where id = p_id;
end $$;

-- ---------- accounts --------------------------------------------------
-- Staff log in with a username. Behind the scenes each account gets an
-- internal address  <username>@staff.reviverewards.internal  that never
-- receives mail. Public sign-up is turned off in the dashboard, so the
-- only way to get an account is for an admin to create one.

create or replace function public._create_user(
  p_username text, p_full_name text, p_title text, p_facility text, p_password text, p_admin boolean)
returns uuid language plpgsql security definer set search_path = public, extensions, auth as $$
declare v_id uuid := gen_random_uuid(); v_email text;
begin
  p_username := lower(btrim(coalesce(p_username, '')));
  if p_username !~ '^[a-z0-9._-]{2,40}$' then
    raise exception 'Usernames can use lowercase letters, numbers, dots, dashes and underscores (2 to 40 characters).'; end if;
  if exists (select 1 from public.profiles where username = p_username) then raise exception 'That username is already taken.'; end if;
  if char_length(coalesce(p_password, '')) < 6 then raise exception 'Passwords must be at least 6 characters.'; end if;
  if char_length(btrim(coalesce(p_full_name, ''))) = 0 then raise exception 'Enter the employee''s name.'; end if;
  v_email := p_username || '@staff.reviverewards.internal';
  if exists (select 1 from auth.users where email = v_email) then raise exception 'That username is already taken.'; end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, recovery_token, email_change, email_change_token_new,
                          email_change_token_current, phone_change, phone_change_token, reauthentication_token)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
          crypt(p_password, gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(),
          '', '', '', '', '', '', '', '');

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_id, v_id::text,
          jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
          'email', now(), now(), now());

  insert into public.profiles (id, username, full_name, title, facility, role, must_change_password)
  values (v_id, p_username, left(btrim(p_full_name), 80), left(btrim(coalesce(p_title, '')), 80),
          left(btrim(coalesce(p_facility, '')), 80), case when p_admin then 'admin' else 'staff' end, true);
  return v_id;
end $$;
revoke all on function public._create_user(text, text, text, text, text, boolean) from public, anon, authenticated;

create or replace function public.admin_create_user(
  p_username text, p_full_name text, p_title text, p_facility text, p_password text, p_admin boolean)
returns uuid language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Only admins can add employees.'; end if;
  return public._create_user(p_username, p_full_name, p_title, p_facility, p_password, p_admin);
end $$;

create or replace function public.admin_reset_password(p_user uuid, p_password text)
returns void language plpgsql security definer set search_path = public, extensions, auth as $$
begin
  if not public.is_admin() then raise exception 'Only admins can reset passwords.'; end if;
  if char_length(coalesce(p_password, '')) < 6 then raise exception 'Passwords must be at least 6 characters.'; end if;
  update auth.users set encrypted_password = crypt(p_password, gen_salt('bf')), updated_at = now() where id = p_user;
  update public.profiles set must_change_password = true where id = p_user;
end $$;

create or replace function public.admin_update_user(
  p_user uuid, p_full_name text, p_title text, p_facility text, p_admin boolean, p_active boolean)
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.is_admin() then raise exception 'Only admins can edit employees.'; end if;
  if p_user = auth.uid() and (not p_active or not p_admin) then
    raise exception 'You can''t remove your own admin access or deactivate yourself. Ask another admin.'; end if;
  if char_length(btrim(coalesce(p_full_name, ''))) = 0 then raise exception 'Enter the employee''s name.'; end if;
  update public.profiles
     set full_name = left(btrim(p_full_name), 80), title = left(btrim(coalesce(p_title, '')), 80),
         facility = left(btrim(coalesce(p_facility, '')), 80),
         role = case when p_admin then 'admin' else 'staff' end, active = p_active
   where id = p_user;
  -- a deactivated person can't sign in at all
  update auth.users set banned_until = case when p_active then null else 'infinity'::timestamptz end where id = p_user;
end $$;

create or replace function public.admin_set_dates(p_user uuid, p_birth_month int, p_birth_day int, p_hire_date date)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Only admins can edit employees.'; end if;
  if (p_birth_month is null) <> (p_birth_day is null) then raise exception 'Enter both the birthday month and day, or leave both blank.'; end if;
  if p_birth_month is not null and (p_birth_month not between 1 and 12 or p_birth_day not between 1 and
       case when p_birth_month = 2 then 29 when p_birth_month in (4,6,9,11) then 30 else 31 end) then
    raise exception 'That birthday isn''t a real date.'; end if;
  if p_hire_date > current_date + 365 then raise exception 'Check the hire date.'; end if;
  update public.profiles set birth_month = p_birth_month, birth_day = p_birth_day, hire_date = p_hire_date where id = p_user;
end $$;

-- called by the app after someone sets their own new password
create or replace function public.password_changed() returns void
language sql security definer set search_path = public as $$
  update public.profiles set must_change_password = false where id = auth.uid();
$$;

-- nobody signed out can call any of these
revoke execute on function public.points_summary(uuid), public.add_points(uuid, uuid[], int), public.remove_points(uuid),
  public.give_shoutout(uuid[], text, text, int, text),
  public.redeem(uuid), public.set_redemption_status(uuid, text, text),
  public.admin_create_user(text, text, text, text, text, boolean), public.admin_reset_password(uuid, text),
  public.admin_update_user(uuid, text, text, text, boolean, boolean), public.password_changed(),
  public.admin_set_dates(uuid, int, int, date)
  from public, anon;
grant execute on function public.points_summary(uuid), public.add_points(uuid, uuid[], int), public.remove_points(uuid),
  public.give_shoutout(uuid[], text, text, int, text),
  public.redeem(uuid), public.set_redemption_status(uuid, text, text),
  public.admin_create_user(text, text, text, text, text, boolean), public.admin_reset_password(uuid, text),
  public.admin_update_user(uuid, text, text, text, boolean, boolean), public.password_changed(),
  public.admin_set_dates(uuid, int, int, date)
  to authenticated;

-- table access for signed-in users (row level security above decides which rows)
revoke all on public.profiles, public.settings, public.posts, public.post_points, public.likes, public.comments,
               public.rewards, public.redemptions from anon;
grant select on public.profiles, public.settings, public.posts, public.post_points, public.likes, public.comments,
                public.rewards, public.redemptions to authenticated;
grant update on public.settings to authenticated;
grant insert, delete on public.likes, public.comments to authenticated;
grant delete on public.posts to authenticated;
grant insert, update, delete on public.rewards to authenticated;

-- ---------- photo storage (private: only signed-in staff can view) ----

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 5242880, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do nothing;

drop policy if exists "photos read" on storage.objects;
create policy "photos read" on storage.objects for select to authenticated
  using (bucket_id = 'photos' and public.is_active());
drop policy if exists "photos upload" on storage.objects;
create policy "photos upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and public.is_active() and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "photos delete" on storage.objects;
create policy "photos delete" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

-- ---------- starter rewards catalog ------------------------------------

insert into public.rewards (name, description, emoji, cost, sort)
select * from (values
  ('Amazon $10 gift card', 'Emailed e-gift card', '📦', 100, 1),
  ('Amazon $25 gift card', 'Emailed e-gift card', '📦', 250, 2),
  ('Starbucks $10 gift card', 'Coffee''s on us', '☕', 100, 3),
  ('Target $25 gift card', 'Emailed e-gift card', '🎯', 250, 4),
  ('DoorDash $15 credit', 'Dinner after a long shift', '🍔', 150, 5),
  ('Visa $50 prepaid card', 'Spend it anywhere', '💳', 500, 6),
  ('Reserved parking spot (1 month)', 'Front-row spot by the main entrance', '🚗', 150, 7)
) v(name, description, emoji, cost, sort)
where not exists (select 1 from public.rewards);
