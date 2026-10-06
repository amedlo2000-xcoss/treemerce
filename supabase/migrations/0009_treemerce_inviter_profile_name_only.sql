-- ============================================================================
-- 0009: treemerce_my_inviter_profile を「招待元の代理店名のみ」に絞る
-- ----------------------------------------------------------------------------
-- 背景: 0006 は表示名に加えて招待元の public_id も返していた。MY ページで
-- 使うのは表示名だけであり、方針として「返すのは自分の invited_by に該当する
-- 代理店名のみ (連絡先・傘上の他情報・顧客情報は一切返さない)」と定めたため、
-- 返却項目を display_name だけに削る。
--
-- 性質は 0006/0007 と同じ:
--   - 引数なし。常に auth.uid() → app.current_agent_id() 本人の invited_by だけを解決する
--   - STABLE / SECURITY DEFINER。書込みは一切行わない
--   - 実行権は authenticated のみ (anon からは revoke)
--   - 商流マップ (treemerce_commerce_map) の「傘上非表示」には一切関与しない別経路
-- ============================================================================

begin;

create or replace function public.treemerce_my_inviter_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_agent_id uuid := app.current_agent_id();
  v_name     text;
begin
  if v_agent_id is null then
    return jsonb_build_object('found', false);
  end if;

  select inv.display_name
    into v_name
    from public.agents me
    join public.agents inv on inv.id = me.invited_by
   where me.id = v_agent_id;

  if not found then
    return jsonb_build_object('found', false);
  end if;

  return jsonb_build_object('found', true, 'display_name', v_name);
end;
$fn$;

revoke all on function public.treemerce_my_inviter_profile()
  from public, anon, authenticated;

grant execute on function public.treemerce_my_inviter_profile() to authenticated;

commit;
