-- ============================================================================
-- TREEMERCE : 0002_treemerce_security.sql
-- STEP2 (絶対原則の実装) / STEP3 (RLS・権限) / STEP5 (商流マップ) / STEP6 (客層分析)
-- ----------------------------------------------------------------------------
-- 防御は多層で行う:
--   (a) GRANT     : そもそも権限を与えない (customer_assignments の UPDATE/DELETE 等)
--   (b) RLS       : 行レベルで他代理店のデータを不可視にする
--   (c) TRIGGER   : 認可コンテキスト外の書込みを例外で止める
--   (d) FUNCTION  : SECURITY DEFINER 内で役割判定・匿名化を強制する
-- API ハンドラ (Next.js) はこの上にさらにもう一層の判定を重ねる。
-- ============================================================================

begin;

-- ============================================================================
-- 1. 役割判定ヘルパー
-- ============================================================================

-- 稼働中 (status = 'active') の代理店のみ「代理店として」データにアクセスできる。
create or replace function app.current_agent_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select a.id
  from public.agents a
  where a.auth_user_id = auth.uid()
    and a.status = 'active'
  limit 1;
$fn$;

comment on function app.current_agent_id() is
  'ログイン中の稼働代理店ID。未ログイン/非代理店/停止中は NULL (fail-closed)。';

create or replace function app.is_admin()
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
  );
$fn$;

create or replace function app.admin_role()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select r.role::text
  from public.admin_roles r
  where r.auth_user_id = auth.uid()
    and r.revoked_at is null
  limit 1;
$fn$;

-- ----------------------------------------------------------------------------
-- 傘下代理店の再帰CTE。
--   p_all = false : p_root を根とする部分木のみ (自分 + 傘下)。
--                   傘上(招待元側)・兄弟枝は構造的に絶対に含まれない。
--   p_all = true  : ADMIN 用。全代理店ツリー。
-- ----------------------------------------------------------------------------
create or replace function app.agent_subtree(p_root uuid, p_all boolean default false)
returns table (agent_id uuid, depth integer, parent_id uuid)
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  with recursive tree as (
    select a.id, 0 as depth, a.invited_by, array[a.id] as path
    from public.agents a
    where (p_all and a.invited_by is null)
       or (not p_all and p_root is not null and a.id = p_root)
    union all
    select c.id, t.depth + 1, c.invited_by, t.path || c.id
    from public.agents c
    join tree t on c.invited_by = t.id
    where not (c.id = any (t.path))
      and t.depth < 50
  )
  select tree.id, tree.depth, tree.invited_by from tree;
$fn$;

comment on function app.agent_subtree(uuid, boolean) is
  '招待経路(invited_by)を辿る部分木。根を含み、上位・兄弟枝は含まない。';

create or replace function app.is_in_my_subtree(p_agent_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select exists (
    select 1 from app.agent_subtree(app.current_agent_id(), false) s
    where s.agent_id = p_agent_id
  );
$fn$;

-- 絶対原則5: 「自分が担当している顧客か」だけが PII 可視の条件。傘下は対象外。
create or replace function app.is_assigned_agent(p_customer_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select exists (
    select 1
    from public.customer_assignments ca
    where ca.customer_id = p_customer_id
      and ca.status = 'active'
      and ca.assigned_agent_id = app.current_agent_id()
  );
$fn$;

comment on function app.is_assigned_agent(uuid) is
  '絶対原則5: 自分が現に担当している顧客のみ true。傘下代理店担当の顧客では false。';

-- ============================================================================
-- 2. 書込みガード (絶対原則4 / 8)
-- ============================================================================
-- customer_assignments と customer_assignment_history への書込みは、
-- SECURITY DEFINER の認可済み関数が張ったコンテキスト内でのみ許可する。
-- 一般代理店はそもそも GRANT を持たないが、万一 GRANT が復活しても
-- このトリガで確実に止まる。

create or replace function app.assignment_ctx()
returns text
language sql
stable
as $fn$
  select coalesce(current_setting('app.assignment_ctx', true), '');
$fn$;

create or replace function app.guard_customer_assignment_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := app.assignment_ctx();
begin
  -- DB管理者(postgres)による直接操作 = マイグレーション/障害復旧の経路として明示的に許可。
  -- superuser はトリガ自体を無効化できるため、これは防御の弱体化ではない。
  if current_user = 'postgres' and v_ctx = '' then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    if v_ctx not in ('register', 'transfer') then
      raise exception
        'TREEMERCE_ASSIGNMENT_WRITE_DENIED: customer_assignments への直接INSERTは禁止です'
        using errcode = '42501';
    end if;
    return new;
  end if;

  -- 絶対原則4: 担当の変更・解除・移管は ADMIN 専用関数の中でしか起こしてはならない。
  if v_ctx <> 'transfer' then
    raise exception
      'TREEMERCE_ASSIGNMENT_IMMUTABLE: 担当代理店の変更/解除/移管は管理者専用処理でのみ可能です'
      using errcode = '42501';
  end if;

  return coalesce(new, old);
end;
$fn$;

create trigger customer_assignments_guard
  before insert or update or delete on public.customer_assignments
  for each row execute function app.guard_customer_assignment_write();

-- 履歴は追記専用
create or replace function app.guard_history_append_only()
returns trigger
language plpgsql
as $fn$
begin
  if tg_op = 'INSERT' then
    if current_user = 'postgres' and app.assignment_ctx() = '' then
      return new;
    end if;
    if app.assignment_ctx() not in ('register', 'transfer') then
      raise exception
        'TREEMERCE_HISTORY_WRITE_DENIED: customer_assignment_history への直接INSERTは禁止です'
        using errcode = '42501';
    end if;
    return new;
  end if;

  raise exception 'TREEMERCE_HISTORY_APPEND_ONLY: 担当変更履歴は更新・削除できません'
    using errcode = '42501';
end;
$fn$;

create trigger customer_assignment_history_guard
  before insert or update or delete on public.customer_assignment_history
  for each row execute function app.guard_history_append_only();

-- 監査ログも追記専用
create or replace function app.guard_audit_append_only()
returns trigger
language plpgsql
as $fn$
begin
  if tg_op = 'INSERT' then
    return new;
  end if;
  raise exception 'TREEMERCE_AUDIT_APPEND_ONLY: 監査ログは更新・削除できません'
    using errcode = '42501';
end;
$fn$;

create trigger admin_audit_logs_guard
  before update or delete on public.admin_audit_logs
  for each row execute function app.guard_audit_append_only();

-- ============================================================================
-- 3. 匿名化ユーティリティ
-- ============================================================================

-- 顧客の匿名ラベル: 「顧客#<UUID下4桁>」
create or replace function app.customer_anon_label(p_customer_id uuid)
returns text
language sql
immutable
as $fn$
  select '顧客#' || upper(right(p_customer_id::text, 4));
$fn$;

-- n数が極端に少ないセグメントを「該当データ少数」に丸める (k-匿名性)
create or replace function app.apply_k_anonymity(p_rows jsonb, p_k integer default 5)
returns jsonb
language sql
immutable
as $fn$
  with r as (
    select coalesce(nullif(btrim(e ->> 'key'), ''), '未回答') as key,
           (e ->> 'count')::int as cnt
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) e
  ),
  total as (select coalesce(sum(cnt), 0)::int as t from r),
  merged as (
    select case when cnt < p_k then '該当データ少数' else key end as key,
           sum(cnt)::int as cnt
    from r
    group by 1
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'key', m.key,
        'count', m.cnt,
        'ratio', case when t.t > 0 then round(m.cnt::numeric * 100 / t.t, 1) else 0 end
      )
      order by (m.key = '該当データ少数'), m.cnt desc, m.key
    ),
    '[]'::jsonb
  )
  from merged m cross join total t;
$fn$;

comment on function app.apply_k_anonymity(jsonb, integer) is
  'n < k のセグメントを「該当データ少数」へ統合し、構成比を付与する。';

-- ============================================================================
-- 4. スコープ解決 (商流マップ / 客層分析 共通の認可)
-- ============================================================================
-- 一般代理店は「自分を根とする部分木」しか要求できない。
-- 他人のIDを渡した場合はサーバー側で拒否する (CASE12 / CASE13 / CASE17)。

create or replace function app.resolve_scope(p_requested_root uuid, out root_id uuid, out is_all boolean)
returns record
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_self uuid := app.current_agent_id();
begin
  if app.is_admin() then
    root_id := p_requested_root;
    is_all  := p_requested_root is null;
    return;
  end if;

  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店アカウントが必要です'
      using errcode = '42501';
  end if;

  if p_requested_root is not null and p_requested_root <> v_self then
    raise exception 'TREEMERCE_FORBIDDEN: 他代理店を根とするスコープは要求できません'
      using errcode = '42501';
  end if;

  root_id := v_self;
  is_all  := false;
end;
$fn$;

commit;
