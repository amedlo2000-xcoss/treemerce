-- ============================================================================
-- TREEMERCE : 0004_treemerce_rls.sql   (STEP3: RLS・権限)
-- ----------------------------------------------------------------------------
-- 方針
--   ・anon / authenticated からは既定の権限を全て剥がし、必要な分だけ付け直す。
--   ・customer_assignments と customer_assignment_history には
--     INSERT/UPDATE/DELETE の GRANT を一切与えない (絶対原則4)。
--   ・顧客 PII は「自分が現に担当している顧客」の行しか見えない (絶対原則5)。
--     傘下代理店担当の顧客は行レベルで不可視。集計は SECURITY DEFINER の
--     匿名化 RPC からのみ得られる。
-- ============================================================================

begin;

-- ============================================================================
-- 0. 既定権限の剥奪
-- ============================================================================

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
revoke all on all functions in schema app from public, anon, authenticated;

-- ============================================================================
-- 1. RLS 有効化
-- ============================================================================

alter table public.agents                     enable row level security;
alter table public.agent_invitations          enable row level security;
alter table public.agent_invitation_uses      enable row level security;
alter table public.customers                  enable row level security;
alter table public.customer_assignments       enable row level security;
alter table public.customer_assignment_history enable row level security;
alter table public.purchases                  enable row level security;
alter table public.benefits                   enable row level security;
alter table public.bank_accounts              enable row level security;
alter table public.notifications              enable row level security;
alter table public.admin_roles                enable row level security;
alter table public.admin_audit_logs           enable row level security;

-- ============================================================================
-- 2. agents
-- ============================================================================
-- 代理店は「自分」と「自分の傘下」の代理店を参照できる。
-- 傘上(招待元側)・兄弟枝は agent_subtree の構造上ここに現れない (CASE12 / CASE13)。

create policy agents_select on public.agents
  for select to authenticated
  using (
    app.is_admin()
    or agents.auth_user_id = auth.uid()
    or app.is_in_my_subtree(agents.id)
  );

-- invited_by / status / email は列 GRANT の対象外なので更新できない (絶対原則2)
create policy agents_update_self on public.agents
  for update to authenticated
  using (agents.auth_user_id = auth.uid() or app.is_admin())
  with check (agents.auth_user_id = auth.uid() or app.is_admin());

grant select on public.agents to authenticated;
grant update (display_name, legal_name, phone, profile_bio, avatar_url, prefecture)
  on public.agents to authenticated;

-- ============================================================================
-- 3. agent_invitations / agent_invitation_uses
-- ============================================================================

create policy agent_invitations_select on public.agent_invitations
  for select to authenticated
  using (app.is_admin() or agent_invitations.inviter_agent_id = app.current_agent_id());

create policy agent_invitations_update_own on public.agent_invitations
  for update to authenticated
  using (app.is_admin() or agent_invitations.inviter_agent_id = app.current_agent_id())
  with check (app.is_admin() or agent_invitations.inviter_agent_id = app.current_agent_id());

grant select on public.agent_invitations to authenticated;
grant update (status, note, expires_at, max_uses) on public.agent_invitations to authenticated;

create policy agent_invitation_uses_select on public.agent_invitation_uses
  for select to authenticated
  using (
    app.is_admin()
    or agent_invitation_uses.agent_id = app.current_agent_id()
    or app.is_in_my_subtree(agent_invitation_uses.agent_id)
  );

grant select on public.agent_invitation_uses to authenticated;

-- ============================================================================
-- 4. customers  (絶対原則5)
-- ============================================================================
-- 自分が担当している顧客のみ。傘下代理店が担当する顧客は 1 行も返らない。

create policy customers_select_assigned on public.customers
  for select to authenticated
  using (app.is_admin() or app.is_assigned_agent(customers.id));

create policy customers_update_assigned on public.customers
  for update to authenticated
  using (app.is_admin() or app.is_assigned_agent(customers.id))
  with check (app.is_admin() or app.is_assigned_agent(customers.id));

grant select on public.customers to authenticated;
-- 識別子 (full_name / email / phone) は更新させない。ADMIN は RPC 経由で更新する。
grant update (full_name_kana, postal_code, address_line, age_group, gender,
              prefecture, customer_type, note)
  on public.customers to authenticated;

-- ============================================================================
-- 5. customer_assignments  (絶対原則4)
-- ============================================================================
-- SELECT のみ。INSERT / UPDATE / DELETE の GRANT は一切与えない。
-- 万一 GRANT が復活しても app.guard_customer_assignment_write() が拒否する。

create policy customer_assignments_select on public.customer_assignments
  for select to authenticated
  using (
    app.is_admin()
    or customer_assignments.assigned_agent_id = app.current_agent_id()
  );

grant select on public.customer_assignments to authenticated;

-- ============================================================================
-- 6. customer_assignment_history
-- ============================================================================

create policy customer_assignment_history_select on public.customer_assignment_history
  for select to authenticated
  using (app.is_admin() or app.is_assigned_agent(customer_assignment_history.customer_id));

grant select on public.customer_assignment_history to authenticated;

-- ============================================================================
-- 7. purchases
-- ============================================================================

create policy purchases_select on public.purchases
  for select to authenticated
  using (app.is_admin() or app.is_assigned_agent(purchases.customer_id));

create policy purchases_insert on public.purchases
  for insert to authenticated
  with check (app.is_admin() or app.is_assigned_agent(purchases.customer_id));

create policy purchases_update on public.purchases
  for update to authenticated
  using (app.is_admin() or app.is_assigned_agent(purchases.customer_id))
  with check (app.is_admin() or app.is_assigned_agent(purchases.customer_id));

create policy purchases_delete on public.purchases
  for delete to authenticated
  using (app.is_admin());

grant select, insert, update, delete on public.purchases to authenticated;

-- ============================================================================
-- 8. benefits / bank_accounts / notifications
-- ============================================================================

create policy benefits_select on public.benefits
  for select to authenticated
  using (app.is_admin() or benefits.agent_id = app.current_agent_id());

grant select on public.benefits to authenticated;

create policy bank_accounts_select on public.bank_accounts
  for select to authenticated
  using (app.is_admin() or bank_accounts.agent_id = app.current_agent_id());

create policy bank_accounts_insert on public.bank_accounts
  for insert to authenticated
  with check (bank_accounts.agent_id = app.current_agent_id());

create policy bank_accounts_update on public.bank_accounts
  for update to authenticated
  using (bank_accounts.agent_id = app.current_agent_id())
  with check (bank_accounts.agent_id = app.current_agent_id());

grant select, insert, update on public.bank_accounts to authenticated;

create policy notifications_select on public.notifications
  for select to authenticated
  using (
    notifications.agent_id = app.current_agent_id()
    or (notifications.for_admin and app.is_admin())
  );

create policy notifications_update on public.notifications
  for update to authenticated
  using (
    notifications.agent_id = app.current_agent_id()
    or (notifications.for_admin and app.is_admin())
  )
  with check (
    notifications.agent_id = app.current_agent_id()
    or (notifications.for_admin and app.is_admin())
  );

grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

-- ============================================================================
-- 9. admin_roles / admin_audit_logs
-- ============================================================================

create policy admin_roles_select on public.admin_roles
  for select to authenticated
  using (admin_roles.auth_user_id = auth.uid() or app.is_admin());

grant select on public.admin_roles to authenticated;

create policy admin_audit_logs_select on public.admin_audit_logs
  for select to authenticated
  using (app.is_admin());

grant select on public.admin_audit_logs to authenticated;

-- ============================================================================
-- 10. 関数の EXECUTE 権限
-- ============================================================================

-- RLS ポリシー式の評価に必要なヘルパーのみ公開する。
-- (自分自身の身元・真偽値しか返さないため安全)
grant execute on function app.current_agent_id()            to authenticated;
grant execute on function app.is_admin()                    to authenticated;
grant execute on function app.admin_role()                  to authenticated;
grant execute on function app.is_assigned_agent(uuid)       to authenticated;
grant execute on function app.is_in_my_subtree(uuid)        to authenticated;
-- ガードトリガ (SECURITY INVOKER) が内部で呼ぶため。GUC を読むだけで副作用はない。
grant execute on function app.assignment_ctx()              to authenticated;

-- app.agent_subtree / app.resolve_scope / app.apply_k_anonymity /
-- app.customer_anon_label は直接呼ばせない (任意の根を指定させないため)。

-- 未ログインでも使う公開エンドポイント
grant execute on function public.treemerce_resolve_invitation(text)      to anon, authenticated;
grant execute on function public.treemerce_agent_public_profile(text)    to anon, authenticated;
grant execute on function public.treemerce_check_customer_duplicate(text, text)
  to anon, authenticated;
grant execute on function public.treemerce_register_customer(
  text, text, text, text, text,
  public.customer_age_group, public.customer_gender, text,
  public.customer_kind, text, text) to anon, authenticated;

-- ログイン代理店向け
grant execute on function public.treemerce_register_agent(text, text, text, text)
  to authenticated;
grant execute on function public.treemerce_create_agent_invitation(text, integer, timestamptz)
  to authenticated;
grant execute on function public.treemerce_commerce_map(uuid)               to authenticated;
grant execute on function public.treemerce_community_map(uuid)              to authenticated;
grant execute on function public.treemerce_customer_demographics(uuid, text) to authenticated;

-- ADMIN 専用 (関数内部で app.is_admin() を必須チェック。一般代理店が直接叩いても
-- TREEMERCE_ADMIN_ONLY で拒否される = CASE7)
grant execute on function public.treemerce_admin_transfer_customer(uuid, uuid, text)
  to authenticated;
grant execute on function public.treemerce_admin_update_customer(uuid, jsonb, text)
  to authenticated;
grant execute on function public.treemerce_admin_set_agent_status(
  uuid, public.agent_status, text) to authenticated;

commit;
