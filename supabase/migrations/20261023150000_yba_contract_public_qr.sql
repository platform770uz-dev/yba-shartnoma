-- Permanent public QR: each fresh scan creates one short-lived draft contract.
-- Existing signed records and administrator-created links are preserved.

alter table public.yba_contract_documents
  add column if not exists expires_at timestamptz;

create table if not exists yba_contract_private.public_start_rate_limits (
  ip_hash text primary key check (ip_hash ~ '^[0-9a-f]{64}$'),
  window_started_at timestamptz not null,
  request_count integer not null check (request_count between 1 and 6),
  updated_at timestamptz not null default now()
);
alter table yba_contract_private.public_start_rate_limits enable row level security;
revoke all on table yba_contract_private.public_start_rate_limits from public, anon, authenticated;

create or replace function public.start_public_contract(p_ip_hash text)
returns table (contract_id uuid, contract_number text, monthly_price integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
  v_number text;
  v_count integer;
begin
  if p_ip_hash is null or p_ip_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid_request';
  end if;

  insert into yba_contract_private.public_start_rate_limits as rl
    (ip_hash, window_started_at, request_count, updated_at)
  values (p_ip_hash, now(), 1, now())
  on conflict (ip_hash) do update
    set window_started_at = case
          when rl.window_started_at <= now() - interval '1 hour' then now()
          else rl.window_started_at end,
        request_count = case
          when rl.window_started_at <= now() - interval '1 hour' then 1
          else rl.request_count + 1 end,
        updated_at = now()
  returning request_count into v_count;

  if v_count > 5 then raise exception 'rate_limited'; end if;

  v_number := yba_contract_private.next_contract_number();
  insert into public.yba_contract_documents
    (id, monthly_price, status, contract_number, expires_at)
  values (v_id, 400000, 'pending', v_number, now() + interval '24 hours');

  delete from yba_contract_private.public_start_rate_limits
  where updated_at < now() - interval '2 days';

  return query select v_id, v_number, 400000;
end;
$$;
revoke all on function public.start_public_contract(text) from public, anon, authenticated;
grant execute on function public.start_public_contract(text) to service_role;

create or replace function public.get_contract(p_contract_id uuid)
returns table (monthly_price integer, status text)
language sql
stable
security definer
set search_path = ''
as $$
  select d.monthly_price, d.status
  from public.yba_contract_documents d
  where d.id = p_contract_id
    and (d.expires_at is null or d.expires_at > now());
$$;
revoke all on function public.get_contract(uuid) from public;
grant execute on function public.get_contract(uuid) to anon, authenticated;

create or replace function public.get_contract_number(p_contract_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select d.contract_number
  from public.yba_contract_documents d
  where d.id = p_contract_id and d.status = 'pending'
    and (d.expires_at is null or d.expires_at > now());
$$;
revoke all on function public.get_contract_number(uuid) from public;
grant execute on function public.get_contract_number(uuid) to anon, authenticated;

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
      and (d.expires_at is null or d.expires_at > now())
  );
exception when others then
  return false;
end;
$$;
revoke all on function yba_contract_private.pending_pdf_upload_allowed(text) from public;
grant execute on function yba_contract_private.pending_pdf_upload_allowed(text) to anon, authenticated;

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
     set status = 'signed', parent_name = btrim(p_parent_name),
         parent_passport = p_parent_passport, parent_phone = p_parent_phone,
         child_name = btrim(p_child_name), child_birth_date = p_child_birth_date,
         consents = p_consents, pdf_sha256 = p_pdf_sha256,
         contract_version = p_contract_version, user_agent = p_user_agent,
         signed_at = v_signed_at, pdf_path = v_path
   where d.id = p_contract_id and d.status = 'pending'
     and (d.expires_at is null or d.expires_at > now())
   returning d.contract_number into v_number;
  if v_number is null then raise exception 'Shartnoma muddati tugagan yoki allaqachon imzolangan'; end if;
  return query select v_number, v_signed_at;
end;
$$;
revoke all on function public.submit_contract(uuid,text,text,text,text,date,jsonb,text,text,text) from public;
grant execute on function public.submit_contract(uuid,text,text,text,text,date,jsonb,text,text,text) to anon, authenticated;

create or replace function public.admin_list_contracts()
returns table (
  contract_id uuid, contract_number text, status text, parent_name text,
  parent_phone text, created_at timestamptz, signed_at timestamptz, pdf_path text
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
    where d.status = 'signed' or d.expires_at is null or d.expires_at > now()
    order by d.created_at desc
    limit 500;
end;
$$;
revoke all on function public.admin_list_contracts() from public, anon, authenticated;
grant execute on function public.admin_list_contracts() to authenticated;
