-- Supabase project defaults also grant EXECUTE directly to anon.
-- Keep public contract RPCs anonymous, but restrict admin RPCs to authenticated accounts.
revoke execute on function public.admin_create_contract(integer) from public, anon;
revoke execute on function public.admin_list_contracts() from public, anon;
revoke execute on function yba_contract_private.is_admin() from public, anon;
revoke execute on function yba_contract_private.next_contract_number() from public, anon, authenticated;
