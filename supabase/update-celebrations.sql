-- =====================================================================
--  Add birthdays and work anniversaries.
--  Only needed if you ran setup.sql BEFORE November 16, 2026 at 3 PM.
--  (Running the whole current setup.sql again does the same thing.)
-- =====================================================================
alter table public.profiles add column if not exists birth_month int check (birth_month between 1 and 12);
alter table public.profiles add column if not exists birth_day   int check (birth_day between 1 and 31);
alter table public.profiles add column if not exists hire_date   date;

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
revoke execute on function public.admin_set_dates(uuid, int, int, date) from public, anon;
grant execute on function public.admin_set_dates(uuid, int, int, date) to authenticated;
