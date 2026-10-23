-- Additive Phase 2 tables/functions for the YBA parent contract site.
-- Existing CRM and YBA objects are not altered by this migration.

create schema if not exists yba_contract_private;
revoke all on schema yba_contract_private from public;
grant usage on schema yba_contract_private to anon, authenticated;

create table if not exists public.yba_contract_admins (
  user_id uuid primary key references auth.users(id) on delete restrict,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.yba_contract_admins enable row level security;
revoke all on table public.yba_contract_admins from public, anon, authenticated;

create table if not exists yba_contract_private.daily_number_counters (
  contract_day date primary key,
  last_number integer not null check (last_number between 1 and 9999)
);
revoke all on table yba_contract_private.daily_number_counters from public, anon, authenticated;

create table if not exists public.yba_contract_documents (
  id uuid primary key default gen_random_uuid(),
  monthly_price integer not null check (monthly_price between 1 and 1000000000),
  status text not null default 'pending' check (status in ('pending','signed')),
  contract_number text not null unique,
  parent_name text,
  parent_passport text,
  parent_phone text,
  child_name text,
  child_birth_date date,
  consents jsonb,
  pdf_sha256 text,
  contract_version text not null default 'v1',
  user_agent text,
  signed_at timestamptz,
  pdf_path text,
  created_at timestamptz not null default now(),
  constraint yba_contract_signed_fields check (
    (status = 'pending' and signed_at is null and pdf_path is null)
    or
    (status = 'signed' and signed_at is not null and pdf_path is not null and pdf_sha256 is not null)
  )
);
create index if not exists yba_contract_documents_status_created_idx
  on public.yba_contract_documents (status, created_at desc);
alter table public.yba_contract_documents enable row level security;
revoke all on table public.yba_contract_documents from public, anon, authenticated;

create or replace function yba_contract_private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.yba_contract_admins a
    where a.user_id = (select auth.uid()) and a.active
  );
$$;
revoke all on function yba_contract_private.is_admin() from public;
grant execute on function yba_contract_private.is_admin() to authenticated;

create policy yba_contract_admins_select_self
  on public.yba_contract_admins for select to authenticated
  using (user_id = (select auth.uid()) and active and yba_contract_private.is_admin());

create or replace function yba_contract_private.next_contract_number()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_day date := (now() at time zone 'Asia/Tashkent')::date;
  v_number integer;
begin
  insert into yba_contract_private.daily_number_counters(contract_day, last_number)
  values (v_day, 1)
  on conflict (contract_day) do update
    set last_number = yba_contract_private.daily_number_counters.last_number + 1
  returning last_number into v_number;
  if v_number > 9999 then
    raise exception 'Kunlik shartnoma raqamlari tugadi';
  end if;
  return 'YBA-' || to_char(v_day, 'YYMMDD') || '-' || lpad(v_number::text, 4, '0');
end;
$$;
revoke all on function yba_contract_private.next_contract_number() from public;

create or replace function yba_contract_private.pending_pdf_upload_allowed(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if p_name !~* '^[0-9a-f-]{36}\.pdf$' then return false; end if;
  v_id := substring(p_name from 1 for 36)::uuid;
  return exists (
    select 1 from public.yba_contract_documents d
    where d.id = v_id and d.status = 'pending' and d.pdf_path is null
  );
exception when others then
  return false;
end;
$$;
revoke all on function yba_contract_private.pending_pdf_upload_allowed(text) from public;
grant execute on function yba_contract_private.pending_pdf_upload_allowed(text) to anon, authenticated;

create or replace function public.get_contract(p_contract_id uuid)
returns table (monthly_price integer, status text)
language sql
stable
security definer
set search_path = ''
as $$
  select d.monthly_price, d.status
  from public.yba_contract_documents d
  where d.id = p_contract_id;
$$;
revoke all on function public.get_contract(uuid) from public;
grant execute on function public.get_contract(uuid) to anon, authenticated;

-- The parent link is a bearer token. This second, narrow RPC returns only
-- the already-assigned contract number needed to render the PDF.
create or replace function public.get_contract_number(p_contract_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select d.contract_number
  from public.yba_contract_documents d
  where d.id = p_contract_id and d.status = 'pending';
$$;
revoke all on function public.get_contract_number(uuid) from public;
grant execute on function public.get_contract_number(uuid) to anon, authenticated;

create or replace function public.submit_contract(
  p_contract_id uuid,
  p_parent_name text,
  p_parent_passport text,
  p_parent_phone text,
  p_child_name text,
  p_child_birth_date date,
  p_consents jsonb,
  p_pdf_sha256 text,
  p_contract_version text,
  p_user_agent text
)
returns table (contract_number text, signed_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_number text;
  v_signed_at timestamptz := now();
  v_age integer;
  v_path text;
begin
  if p_parent_name is null or length(btrim(p_parent_name)) < 3 or length(p_parent_name) > 120
     or array_length(regexp_split_to_array(btrim(p_parent_name), '\s+'), 1) < 2 then
    raise exception 'Ota-ona F.I.Sh. notoʻgʻri';
  end if;
  if p_parent_passport is null or p_parent_passport !~ '^[A-Z]{2}[0-9]{7}$' then raise exception 'Pasport formati notoʻgʻri'; end if;
  if p_parent_phone is null or p_parent_phone !~ '^\+998 [0-9]{2} [0-9]{3} [0-9]{2} [0-9]{2}$' then raise exception 'Telefon formati notoʻgʻri'; end if;
  if p_child_name is null or length(btrim(p_child_name)) < 3 or length(p_child_name) > 120
     or array_length(regexp_split_to_array(btrim(p_child_name), '\s+'), 1) < 2 then
    raise exception 'Bola F.I.Sh. notoʻgʻri';
  end if;
  if p_child_birth_date is null then raise exception 'Bola tugʻilgan sanasi kiritilmagan'; end if;
  v_age := extract(year from age((now() at time zone 'Asia/Tashkent')::date, p_child_birth_date))::integer;
  if v_age < 7 or v_age > 14 then raise exception 'Kurs 7–14 yoshdagi bolalar uchun'; end if;
  if p_consents is null or jsonb_typeof(p_consents) <> 'object'
     or jsonb_object_length(p_consents) <> 4
     or not (p_consents ?& array['social','promotion','broadcasts','portfolio'])
     or jsonb_typeof(p_consents->'social') <> 'boolean'
     or jsonb_typeof(p_consents->'promotion') <> 'boolean'
     or jsonb_typeof(p_consents->'broadcasts') <> 'boolean'
     or jsonb_typeof(p_consents->'portfolio') <> 'boolean' then
    raise exception 'Roziliklar formati notoʻgʻri';
  end if;
  if p_pdf_sha256 is null or p_pdf_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'PDF xeshi notoʻgʻri'; end if;
  if p_contract_version is distinct from 'v1' then raise exception 'Shartnoma versiyasi notoʻgʻri'; end if;
  if p_user_agent is not null and length(p_user_agent) > 512 then raise exception 'Brauzer maʼlumoti juda uzun'; end if;
  v_path := p_contract_id::text || '.pdf';
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'shartnomalar' and o.name = v_path
  ) then
    raise exception 'PDF yuklanmagan';
  end if;
  update public.yba_contract_documents d
     set status = 'signed',
         parent_name = btrim(p_parent_name),
         parent_passport = p_parent_passport,
         parent_phone = p_parent_phone,
         child_name = btrim(p_child_name),
         child_birth_date = p_child_birth_date,
         consents = p_consents,
         pdf_sha256 = p_pdf_sha256,
         contract_version = p_contract_version,
         user_agent = p_user_agent,
         signed_at = v_signed_at,
         pdf_path = v_path
   where d.id = p_contract_id and d.status = 'pending'
   returning d.contract_number into v_number;
  if v_number is null then raise exception 'Shartnoma allaqachon imzolangan yoki topilmadi'; end if;
  return query select v_number, v_signed_at;
end;
$$;
revoke all on function public.submit_contract(uuid,text,text,text,text,date,jsonb,text,text,text) from public;
grant execute on function public.submit_contract(uuid,text,text,text,text,date,jsonb,text,text,text) to anon, authenticated;

create or replace function public.admin_create_contract(p_monthly_price integer)
returns table (contract_id uuid, contract_number text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
  v_number text;
begin
  if not yba_contract_private.is_admin() then raise exception 'Ruxsat yoʻq'; end if;
  if p_monthly_price is null or p_monthly_price < 1 or p_monthly_price > 1000000000 then
    raise exception 'Oylik narx notoʻgʻri';
  end if;
  v_number := yba_contract_private.next_contract_number();
  insert into public.yba_contract_documents(id, monthly_price, contract_number)
  values (v_id, p_monthly_price, v_number);
  return query select v_id, v_number;
end;
$$;
revoke all on function public.admin_create_contract(integer) from public;
grant execute on function public.admin_create_contract(integer) to authenticated;

create or replace function public.admin_list_contracts()
returns table (
  contract_id uuid,
  contract_number text,
  status text,
  parent_name text,
  parent_phone text,
  created_at timestamptz,
  signed_at timestamptz,
  pdf_path text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not yba_contract_private.is_admin() then raise exception 'Ruxsat yoʻq'; end if;
  return query
    select d.id, d.contract_number, d.status, d.parent_name, d.parent_phone,
           d.created_at, d.signed_at, d.pdf_path
    from public.yba_contract_documents d
    order by d.created_at desc
    limit 500;
end;
$$;
revoke all on function public.admin_list_contracts() from public;
grant execute on function public.admin_list_contracts() to authenticated;

-- Private bucket creation is performed through the Storage API/dashboard, not SQL.
drop policy if exists yba_contract_pending_pdf_insert on storage.objects;
create policy yba_contract_pending_pdf_insert
  on storage.objects for insert to anon, authenticated
  with check (
    bucket_id = 'shartnomalar'
    and lower(storage.extension(name)) = 'pdf'
    and (metadata->>'mimetype') = 'application/pdf'
    and coalesce((metadata->>'size')::bigint, 0) between 1 and 10485760
    and yba_contract_private.pending_pdf_upload_allowed(name)
  );
drop policy if exists yba_contract_admin_pdf_read on storage.objects;
create policy yba_contract_admin_pdf_read
  on storage.objects for select to authenticated
  using (bucket_id = 'shartnomalar' and yba_contract_private.is_admin());

comment on table public.yba_contract_documents is 'Private parent contract signing records for the YBA contract site.';
