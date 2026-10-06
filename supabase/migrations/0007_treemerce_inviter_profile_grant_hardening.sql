-- ============================================================================
-- 0007: treemerce_my_inviter_profile の GRANT 是正
-- ----------------------------------------------------------------------------
-- 背景: 0006 は grant execute ... to authenticated; のみを行い、anon からの
-- revoke を行っていなかった。Supabase の public スキーマは新規オブジェクトに
-- 既定で anon / authenticated / service_role へ全権限が付く設定になっているため
-- (0004 の revoke all は「その時点で存在する関数」にしか効かない)、
-- 0006 適用直後は anon からも本関数を実行できてしまっていた。
--
-- 実害: 関数は常に auth.uid() から自分の invited_by を解決するだけで、
-- anon (auth.uid() が null) では app.current_agent_id() が null になり
-- {"found": false} 以上のデータは返らない。実データの漏洩はない。
-- ただし本プロジェクトの方針 (README「防御の多層構造」) は GRANT 層でも
-- 最小権限を徹底することなので、他の代理店向け RPC (0004) や 0005 の
-- 管理者 RPC と同じ「revoke してから authenticated のみに grant」の形に揃える。
-- ============================================================================

begin;

revoke all on function public.treemerce_my_inviter_profile()
  from public, anon, authenticated;

grant execute on function public.treemerce_my_inviter_profile() to authenticated;

commit;
