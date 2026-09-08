-- ============================================================================
-- 0006: 自分の招待元 (登録経路) の表示名を返す読み取り専用 RPC
-- ----------------------------------------------------------------------------
-- 背景: agents_select の RLS は「根を含む自分の部分木 (自分+傘下)」しか許可せず、
-- 招待元 (upline) の行は絶対原則の設計上見えない (0002 参照)。
-- 一方で「誰の招待で自分が代理店になったか」は代理店自身の登録経路そのものであり、
-- MY ページ・代理店プロフィールに表示してよい情報 (絶対原則2)。
--
-- この関数は呼び出し本人の invited_by が指す1行の public_id / display_name のみを
-- 返す SECURITY DEFINER。引数を取らず常に auth.uid() 基準で解決するため、
-- 任意の agent_id を渡して他人の招待元を探索する経路にはならない。
-- 書込みは一切行わない (STABLE)。
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
  v_inviter  public.agents%rowtype;
begin
  if v_agent_id is null then
    return jsonb_build_object('found', false);
  end if;

  select inv.*
    into v_inviter
    from public.agents me
    join public.agents inv on inv.id = me.invited_by
   where me.id = v_agent_id;

  if not found then
    return jsonb_build_object('found', false);
  end if;

  return jsonb_build_object(
    'found', true,
    'public_id', v_inviter.public_id,
    'display_name', v_inviter.display_name
  );
end;
$fn$;

grant execute on function public.treemerce_my_inviter_profile() to authenticated;

commit;
