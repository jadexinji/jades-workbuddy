create extension if not exists pgcrypto;

create table if not exists public.workbuddy_daily_entries (
  entry_date date primary key,
  sync_key_hash text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.workbuddy_daily_entries enable row level security;

revoke all on public.workbuddy_daily_entries from anon, authenticated;

create or replace function public.workbuddy_get_day(
  p_sync_key text,
  p_entry_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_data jsonb;
begin
  if length(coalesce(p_sync_key, '')) < 8 then
    raise exception 'sync key is too short';
  end if;

  select data into v_data
  from public.workbuddy_daily_entries
  where entry_date = p_entry_date
    and sync_key_hash = crypt(p_sync_key, sync_key_hash);

  return coalesce(v_data, '{}'::jsonb);
end;
$$;

create or replace function public.workbuddy_save_day(
  p_sync_key text,
  p_entry_date date,
  p_data jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
  v_saved jsonb;
begin
  if length(coalesce(p_sync_key, '')) < 8 then
    raise exception 'sync key is too short';
  end if;

  select exists (
    select 1
    from public.workbuddy_daily_entries
    where entry_date = p_entry_date
  ) into v_exists;

  if v_exists then
    update public.workbuddy_daily_entries
    set data = p_data,
        updated_at = now()
    where entry_date = p_entry_date
      and sync_key_hash = crypt(p_sync_key, sync_key_hash)
    returning data into v_saved;

    if v_saved is null then
      raise exception 'invalid sync key for this day';
    end if;

    return v_saved;
  end if;

  insert into public.workbuddy_daily_entries (entry_date, sync_key_hash, data)
  values (p_entry_date, crypt(p_sync_key, gen_salt('bf')), p_data)
  returning data into v_saved;

  return v_saved;
end;
$$;

grant execute on function public.workbuddy_get_day(text, date) to anon, authenticated;
grant execute on function public.workbuddy_save_day(text, date, jsonb) to anon, authenticated;
