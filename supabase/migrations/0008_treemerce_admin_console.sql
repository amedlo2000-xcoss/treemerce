-- ============================================================================
-- TREEMERCE : 0008_treemerce_admin_console.sql
-- 運営(super_admin)専用の統括管理ページ向け DB 変更
-- ----------------------------------------------------------------------------
-- 背景:
--   /admin 配下に全代理店・全顧客を横断する詳細/編集/担当変更/ステータス変更の
--   統括ビューを新設する。このビューと、それが呼び出す書込み系 RPC は
--   admin_roles の全階層(support/admin/super_admin)ではなく super_admin のみに
--   限定する(既存の 0005 treemerce_admin_grant_role / revoke_role と同じ方針)。
--
--   読み取り専用の RLS (app.is_admin()) はここでは変更しない。既存の
--   /admin/analytics・/admin/audit-logs・ダッシュボード集計など他機能が
--   admin/support 階層でも動作することに影響を与えないため。
--   super_admin 限定は Next.js のページ/API 層 (requireSuperAdminPage /
--   requireSuperAdminApi) が担い、書込み系 RPC はここで DB 層としてもう一段
--   super_admin を強制する(多層防御)。
-- ============================================================================

begin;

-- ============================================================================
-- 1. app.is_super_admin() : super_admin 判定ヘルパー
-- ============================================================================

create or replace function app.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select exists (
    select 1
    from public.admin_roles r
    where r.auth_user_id = auth.uid()
      and r.revoked_at is null
      and r.role = 'super_admin'
  );
$fn$;

comment on function app.is_super_admin() is
  '統括管理ページ(全代理店・全顧客の横断詳細/編集/担当変更/ステータス変更)専用の判定。
   admin/support ロールはここでは true にならない。';

grant execute on function app.is_super_admin() to authenticated;

-- ============================================================================
-- 2. 担当変更 RPC を super_admin 限定に格上げ
-- ============================================================================

create or replace function public.treemerce_admin_transfer_customer(
  p_customer_id   uuid,
  p_new_agent_id  uuid,
  p_reason        text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid      uuid := auth.uid();
  v_current  public.customer_assignments%rowtype;
  v_new      public.agents%rowtype;
  v_customer public.customers%rowtype;
  v_before   jsonb;
  v_after    jsonb;
  v_new_id   uuid;
begin
  -- 統括管理ページの操作は super_admin のみ (絶対原則8 をさらに限定)
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 担当変更は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'TREEMERCE_REASON_REQUIRED: 変更理由は必須です' using errcode = '22023';
  end if;

  select * into v_customer from public.customers where id = p_customer_id;
  if not found then
    raise exception 'TREEMERCE_CUSTOMER_NOT_FOUND: 対象顧客が見つかりません' using errcode = '22023';
  end if;

  select * into v_new from public.agents where id = p_new_agent_id;
  if not found then
    raise exception 'TREEMERCE_AGENT_NOT_FOUND: 変更先の代理店が見つかりません' using errcode = '22023';
  end if;
  if v_new.status <> 'active' then
    raise exception 'TREEMERCE_AGENT_NOT_ACTIVE: 変更先の代理店が稼働状態ではありません' using errcode = '22023';
  end if;

  select * into v_current
  from public.customer_assignments
  where customer_id = p_customer_id and status = 'active'
  for update;
  if not found then
    raise exception 'TREEMERCE_ASSIGNMENT_NOT_FOUND: 有効な担当が見つかりません' using errcode = '22023';
  end if;
  if v_current.assigned_agent_id = p_new_agent_id then
    raise exception 'TREEMERCE_NO_CHANGE: 既に同じ代理店が担当しています' using errcode = '22023';
  end if;

  v_before := jsonb_build_object(
    'assignment_id', v_current.id,
    'customer_id', v_current.customer_id,
    'assigned_agent_id', v_current.assigned_agent_id,
    'assigned_at', v_current.assigned_at,
    'assignment_source', v_current.assignment_source,
    'status', v_current.status
  );

  perform set_config('app.assignment_ctx', 'transfer', true);

  update public.customer_assignments
  set status = 'superseded'
  where id = v_current.id;

  insert into public.customer_assignments
    (customer_id, assigned_agent_id, assignment_source, status)
  values (p_customer_id, p_new_agent_id, 'admin_transfer', 'active')
  returning id into v_new_id;

  insert into public.customer_assignment_history
    (customer_id, previous_agent_id, new_agent_id, reason, changed_by, changed_by_role)
  values (p_customer_id, v_current.assigned_agent_id, p_new_agent_id, btrim(p_reason), v_uid, 'admin');

  perform set_config('app.assignment_ctx', '', true);

  v_after := jsonb_build_object(
    'assignment_id', v_new_id,
    'customer_id', p_customer_id,
    'assigned_agent_id', p_new_agent_id,
    'assignment_source', 'admin_transfer',
    'status', 'active'
  );

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, coalesce(app.admin_role(), 'admin'), 'customer_assignment.transfer',
          'customer_assignments', p_customer_id, v_before, v_after, btrim(p_reason));

  insert into public.notifications (agent_id, category, title, body)
  values (p_new_agent_id, 'assignment', '担当顧客が追加されました',
          '管理者の操作により ' || v_customer.full_name || ' 様の担当になりました。');
  insert into public.notifications (agent_id, category, title, body)
  values (v_current.assigned_agent_id, 'assignment', '担当顧客が変更されました',
          '管理者の操作により担当顧客が1件変更されました。');

  return jsonb_build_object(
    'status', 'transferred',
    'customer_id', p_customer_id,
    'previous_agent_id', v_current.assigned_agent_id,
    'new_agent_id', p_new_agent_id,
    'assignment_id', v_new_id
  );
end;
$fn$;

-- ============================================================================
-- 3. 顧客更新 RPC を super_admin 限定に格上げ + 理由を必須化
-- ============================================================================

create or replace function public.treemerce_admin_update_customer(
  p_customer_id  uuid,
  p_patch        jsonb,
  p_reason       text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_before public.customers%rowtype;
  v_after  public.customers%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 購入者情報の更新は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'TREEMERCE_REASON_REQUIRED: 変更理由は必須です' using errcode = '22023';
  end if;

  select * into v_before from public.customers where id = p_customer_id;
  if not found then
    raise exception 'TREEMERCE_CUSTOMER_NOT_FOUND: 対象顧客が見つかりません' using errcode = '22023';
  end if;

  update public.customers c
  set full_name      = coalesce(nullif(btrim(p_patch ->> 'full_name'), ''), c.full_name),
      full_name_kana = coalesce(p_patch ->> 'full_name_kana', c.full_name_kana),
      email          = coalesce(p_patch ->> 'email', c.email),
      phone          = coalesce(p_patch ->> 'phone', c.phone),
      postal_code    = coalesce(p_patch ->> 'postal_code', c.postal_code),
      address_line   = coalesce(p_patch ->> 'address_line', c.address_line),
      prefecture     = coalesce(p_patch ->> 'prefecture', c.prefecture),
      age_group      = coalesce((p_patch ->> 'age_group')::public.customer_age_group, c.age_group),
      gender         = coalesce((p_patch ->> 'gender')::public.customer_gender, c.gender),
      customer_type  = coalesce((p_patch ->> 'customer_type')::public.customer_kind, c.customer_type),
      note           = coalesce(p_patch ->> 'note', c.note)
  where c.id = p_customer_id
  returning * into v_after;

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (auth.uid(), coalesce(app.admin_role(), 'admin'), 'customer.update', 'customers',
          p_customer_id, to_jsonb(v_before), to_jsonb(v_after), btrim(p_reason));

  return to_jsonb(v_after);
end;
$fn$;

-- ============================================================================
-- 4. 代理店ステータス変更 RPC を super_admin 限定に格上げ
-- ============================================================================

create or replace function public.treemerce_admin_set_agent_status(
  p_agent_id uuid,
  p_status   public.agent_status,
  p_reason   text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_before public.agents%rowtype;
  v_after  public.agents%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: ステータス変更は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'TREEMERCE_REASON_REQUIRED: 変更理由は必須です' using errcode = '22023';
  end if;

  select * into v_before from public.agents where id = p_agent_id;
  if not found then
    raise exception 'TREEMERCE_AGENT_NOT_FOUND: 対象代理店が見つかりません' using errcode = '22023';
  end if;

  update public.agents set status = p_status where id = p_agent_id returning * into v_after;

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (auth.uid(), coalesce(app.admin_role(), 'admin'), 'agent.status_change', 'agents',
          p_agent_id,
          jsonb_build_object('status', v_before.status),
          jsonb_build_object('status', v_after.status),
          btrim(p_reason));

  return jsonb_build_object('agent_id', p_agent_id, 'status', v_after.status);
end;
$fn$;

commit;
