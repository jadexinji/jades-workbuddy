create extension if not exists pgcrypto with schema extensions;

create table if not exists public.workbuddy_daily_entries (
  owner_id text,
  entry_date date,
  sync_key_hash text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (owner_id, entry_date)
);

alter table public.workbuddy_daily_entries
  add column if not exists owner_id text;

update public.workbuddy_daily_entries
set owner_id = encode(extensions.digest(sync_key_hash, 'sha256'), 'hex')
where owner_id is null;

alter table public.workbuddy_daily_entries
  alter column owner_id set not null;

alter table public.workbuddy_daily_entries
  drop constraint if exists workbuddy_daily_entries_pkey;

alter table public.workbuddy_daily_entries
  add constraint workbuddy_daily_entries_pkey primary key (owner_id, entry_date);

alter table public.workbuddy_daily_entries enable row level security;

revoke all on public.workbuddy_daily_entries from anon, authenticated;

create or replace function public.workbuddy_owner_id(p_sync_key text)
returns text
language sql
security definer
set search_path = public, extensions
as $$
  select encode(extensions.digest(p_sync_key, 'sha256'), 'hex');
$$;

create or replace function public.workbuddy_get_day(
  p_sync_key text,
  p_entry_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_data jsonb;
  v_owner_id text;
begin
  if length(coalesce(p_sync_key, '')) < 8 then
    raise exception 'sync key is too short';
  end if;

  v_owner_id := public.workbuddy_owner_id(p_sync_key);

  select data into v_data
  from public.workbuddy_daily_entries
  where owner_id = v_owner_id
    and entry_date = p_entry_date
    and sync_key_hash = extensions.crypt(p_sync_key, sync_key_hash);

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
set search_path = public, extensions
as $$
declare
  v_owner_id text;
  v_saved jsonb;
begin
  if length(coalesce(p_sync_key, '')) < 8 then
    raise exception 'sync key is too short';
  end if;

  v_owner_id := public.workbuddy_owner_id(p_sync_key);

  insert into public.workbuddy_daily_entries (owner_id, entry_date, sync_key_hash, data)
  values (
    v_owner_id,
    p_entry_date,
    extensions.crypt(p_sync_key, extensions.gen_salt('bf')),
    p_data
  )
  on conflict (owner_id, entry_date)
  do update set
    data = excluded.data,
    updated_at = now()
  returning data into v_saved;

  return v_saved;
end;
$$;

grant execute on function public.workbuddy_owner_id(text) to anon, authenticated;
grant execute on function public.workbuddy_get_day(text, date) to anon, authenticated;
grant execute on function public.workbuddy_save_day(text, date, jsonb) to anon, authenticated;
