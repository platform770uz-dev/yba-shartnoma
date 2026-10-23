-- This first version intentionally authorizes at most one contract administrator.
create unique index if not exists yba_contract_single_admin_idx
  on public.yba_contract_admins ((true));

comment on index public.yba_contract_single_admin_idx is
  'Limits the YBA contract admin allowlist to one active account for v1.';
