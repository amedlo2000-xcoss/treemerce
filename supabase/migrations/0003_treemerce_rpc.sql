-- ============================================================================
-- TREEMERCE : 0003_treemerce_rpc.sql
-- PostgREST から呼び出す公開 RPC (public スキーマ / SECURITY DEFINER)
-- ----------------------------------------------------------------------------
-- ここに定義した関数だけが「書込み」と「傘下データの集計」の唯一の入口。
-- テーブルへの直接 INSERT/UPDATE/DELETE は GRANT と TRIGGER で塞いである。
-- ============================================================================

begin;

-- ============================================================================
-- 1. 招待 / 代理店登録  (STEP2, CASE1 / CASE2 / CASE19)
-- ============================================================================

-- 招待コードの下見 (サインアップ画面用)。招待元の公開情報のみ返す。
create or replace function public.treemerce_resolve_invitation(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_inv     public.agent_invitations%rowtype;
  v_inviter public.agents%rowtype;
begin
  select * into v_inv from public.agent_invitations where code = btrim(p_code);
  if not found then
    return jsonb_build_object('valid', false, 'reason', 'not_found');
  end if;
  if v_inv.status <> 'active' then
    return jsonb_build_object('valid', false, 'reason', 'inactive');
  end if;
  if v_inv.expires_at is not null and v_inv.expires_at < now() then
    return jsonb_build_object('valid', false, 'reason', 'expired');
  end if;
  if v_inv.max_uses is not null and v_inv.used_count >= v_inv.max_uses then
    return jsonb_build_object('valid', false, 'reason', 'exhausted');
  end if;

  select * into v_inviter from public.agents where id = v_inv.inviter_agent_id;
  if not found or v_inviter.status <> 'active' then
    return jsonb_build_object('valid', false, 'reason', 'inviter_unavailable');
  end if;

  return jsonb_build_object(
    'valid', true,
    'inviter_public_id', v_inviter.public_id,
    'inviter_display_name', v_inviter.display_name
  );
end;
$fn$;

-- 代理店の招待URL発行
create or replace function public.treemerce_create_agent_invitation(
  p_note       text        default null,
  p_max_uses   integer     default null,
  p_expires_at timestamptz default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_self uuid := app.current_agent_id();
  v_code text;
  v_id   uuid;
begin
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店アカウントが必要です' using errcode = '42501';
  end if;

  -- gen_random_uuid() は pg_catalog 組込みなので search_path に依存しない
  v_code := substr(upper(replace(gen_random_uuid()::text, '-', '')), 1, 16);

  insert into public.agent_invitations (inviter_agent_id, code, note, max_uses, expires_at)
  values (v_self, v_code, p_note, p_max_uses, p_expires_at)
  returning id, code into v_id, v_code;

  return jsonb_build_object('invitation_id', v_id, 'code', v_code);
end;
$fn$;

-- 代理店登録 / 招待経路の確定
--   絶対原則2 & CASE19: invited_by が既に入っている代理店への再設定は必ず拒否。
create or replace function public.treemerce_register_agent(
  p_display_name    text,
  p_email           text,
  p_phone           text default null,
  p_invitation_code text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid     uuid := auth.uid();
  v_agent   public.agents%rowtype;
  v_inv     public.agent_invitations%rowtype;
  v_inviter uuid;
  v_has_code boolean := p_invitation_code is not null and btrim(p_invitation_code) <> '';
begin
  if v_uid is null then
    raise exception 'TREEMERCE_UNAUTHENTICATED: ログインが必要です' using errcode = '42501';
  end if;
  if p_display_name is null or btrim(p_display_name) = '' then
    raise exception 'TREEMERCE_INVALID_INPUT: 代理店名は必須です' using errcode = '22023';
  end if;
  if p_email is null or btrim(p_email) = '' then
    raise exception 'TREEMERCE_INVALID_INPUT: メールアドレスは必須です' using errcode = '22023';
  end if;

  select * into v_agent from public.agents where auth_user_id = v_uid;

  -- 招待コードの検証
  if v_has_code then
    select * into v_inv
    from public.agent_invitations
    where code = btrim(p_invitation_code)
    for update;

    if not found then
      raise exception 'TREEMERCE_INVITATION_NOT_FOUND: 招待コードが見つかりません' using errcode = '22023';
    end if;
    if v_inv.status <> 'active' then
      raise exception 'TREEMERCE_INVITATION_INACTIVE: 招待コードが無効です' using errcode = '22023';
    end if;
    if v_inv.expires_at is not null and v_inv.expires_at < now() then
      raise exception 'TREEMERCE_INVITATION_EXPIRED: 招待コードの有効期限が切れています' using errcode = '22023';
    end if;
    if v_inv.max_uses is not null and v_inv.used_count >= v_inv.max_uses then
      raise exception 'TREEMERCE_INVITATION_EXHAUSTED: 招待コードの利用上限に達しています' using errcode = '22023';
    end if;
    v_inviter := v_inv.inviter_agent_id;
  end if;

  -- 既存代理店
  if v_agent.id is not null then
    -- CASE19: 既に招待元が確定している代理店に、別の招待URLで再登録は不可。
    if v_has_code and v_agent.invited_by is not null then
      raise exception
        'TREEMERCE_INVITED_BY_ALREADY_SET: この代理店の招待元は既に確定しています。変更はできません。'
        using errcode = '23514';
    end if;

    if v_has_code then
      if v_inviter = v_agent.id then
        raise exception 'TREEMERCE_SELF_INVITE: 自分自身を招待元にはできません' using errcode = '23514';
      end if;

      update public.agents
      set invited_by = v_inviter,
          status     = case when status = 'pending' then 'active' else status end
      where id = v_agent.id;

      update public.agent_invitations set used_count = used_count + 1 where id = v_inv.id;
      insert into public.agent_invitation_uses (invitation_id, agent_id)
      values (v_inv.id, v_agent.id)
      on conflict (agent_id) do nothing;
    end if;

    select * into v_agent from public.agents where id = v_agent.id;
    return jsonb_build_object(
      'agent_id',   v_agent.id,
      'public_id',  v_agent.public_id,
      'invited_by', v_agent.invited_by,
      'status',     v_agent.status,
      'created',    false
    );
  end if;

  -- 新規代理店
  insert into public.agents (auth_user_id, display_name, email, phone, status, invited_by)
  values (v_uid, btrim(p_display_name), btrim(p_email), nullif(btrim(coalesce(p_phone, '')), ''),
          'active', v_inviter)
  returning * into v_agent;

  if v_has_code then
    update public.agent_invitations set used_count = used_count + 1 where id = v_inv.id;
    insert into public.agent_invitation_uses (invitation_id, agent_id) values (v_inv.id, v_agent.id);
  end if;

  return jsonb_build_object(
    'agent_id',   v_agent.id,
    'public_id',  v_agent.public_id,
    'invited_by', v_agent.invited_by,
    'status',     v_agent.status,
    'created',    true
  );
end;
$fn$;

-- ============================================================================
-- 2. 顧客登録 / 重複検知  (STEP2, CASE3 / CASE4)
-- ============================================================================

-- 代理店の公開プロフィール (顧客向け登録フォーム用)。顧客情報は一切含まない。
create or replace function public.treemerce_agent_public_profile(p_public_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_agent public.agents%rowtype;
begin
  select * into v_agent from public.agents where public_id = btrim(p_public_id) and status = 'active';
  if not found then
    return jsonb_build_object('found', false);
  end if;
  return jsonb_build_object(
    'found', true,
    'public_id', v_agent.public_id,
    'display_name', v_agent.display_name
  );
end;
$fn$;

-- 絶対原則6 & 7: 識別子(email/電話)で照合し、中立メッセージのみ返す。
-- 「誰が担当しているか」は絶対に返さない。担当も一切変更しない。
create or replace function public.treemerce_check_customer_duplicate(
  p_email text default null,
  p_phone text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '');
  v_hit   boolean;
begin
  if v_email is null and v_phone is null then
    return jsonb_build_object('duplicate', false, 'message', null);
  end if;

  select exists (
    select 1 from public.customers c
    where (v_email is not null and c.email_normalized = v_email)
       or (v_phone is not null and c.phone_normalized = v_phone)
  ) into v_hit;

  return jsonb_build_object(
    'duplicate', v_hit,
    'message', case when v_hit
      then 'このご連絡先は既に登録されています。担当代理店の変更は行われません。詳細は運営事務局までお問い合わせください。'
      else null end
  );
end;
$fn$;

-- 顧客登録。担当は「最初の登録経路」で確定し、以後固定される (絶対原則4)。
create or replace function public.treemerce_register_customer(
  p_agent_public_id text,
  p_full_name       text,
  p_email           text default null,
  p_phone           text default null,
  p_full_name_kana  text default null,
  p_age_group       public.customer_age_group default null,
  p_gender          public.customer_gender    default null,
  p_prefecture      text default null,
  p_customer_type   public.customer_kind      default 'individual',
  p_postal_code     text default null,
  p_address_line    text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_agent    public.agents%rowtype;
  v_email    text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_phone    text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '');
  v_existing uuid;
  v_customer public.customers%rowtype;
  v_uid      uuid := auth.uid();
  v_role     text;
begin
  if p_full_name is null or btrim(p_full_name) = '' then
    raise exception 'TREEMERCE_INVALID_INPUT: 氏名は必須です' using errcode = '22023';
  end if;
  -- 絶対原則7: 氏名だけでは同一人物と確定できないため、識別子を必須にする。
  if v_email is null and v_phone is null then
    raise exception 'TREEMERCE_IDENTIFIER_REQUIRED: メールアドレスまたは電話番号のいずれかが必要です'
      using errcode = '22023';
  end if;

  select * into v_agent
  from public.agents
  where public_id = btrim(p_agent_public_id) and status = 'active';
  if not found then
    raise exception 'TREEMERCE_AGENT_NOT_FOUND: 指定の代理店が見つかりません' using errcode = '22023';
  end if;

  -- 絶対原則6: 重複検知しても担当代理店は自動変更しない。中立メッセージのみ。
  select c.id into v_existing
  from public.customers c
  where (v_email is not null and c.email_normalized = v_email)
     or (v_phone is not null and c.phone_normalized = v_phone)
  limit 1;

  if v_existing is not null then
    return jsonb_build_object(
      'status', 'duplicate',
      'customer_id', null,
      'assignment_changed', false,
      'message', 'このご連絡先は既に登録されています。担当代理店の変更は行われません。詳細は運営事務局までお問い合わせください。'
    );
  end if;

  v_role := case
              when app.is_admin() then 'admin'
              when v_uid is not null and v_uid = v_agent.auth_user_id then 'agent'
              else 'self_registration'
            end;

  insert into public.customers (
    full_name, full_name_kana, email, phone, postal_code, address_line,
    age_group, gender, prefecture, customer_type, first_assigned_at
  ) values (
    btrim(p_full_name), nullif(btrim(coalesce(p_full_name_kana, '')), ''),
    nullif(btrim(coalesce(p_email, '')), ''), nullif(btrim(coalesce(p_phone, '')), ''),
    nullif(btrim(coalesce(p_postal_code, '')), ''), nullif(btrim(coalesce(p_address_line, '')), ''),
    p_age_group, p_gender, nullif(btrim(coalesce(p_prefecture, '')), ''),
    coalesce(p_customer_type, 'individual'), now()
  )
  returning * into v_customer;

  perform set_config('app.assignment_ctx', 'register', true);

  insert into public.customer_assignments
    (customer_id, assigned_agent_id, assignment_source, status)
  values (v_customer.id, v_agent.id, 'initial_registration', 'active');

  insert into public.customer_assignment_history
    (customer_id, previous_agent_id, new_agent_id, reason, changed_by, changed_by_role)
  values (v_customer.id, null, v_agent.id, '初回登録による担当確定', v_uid, v_role);

  perform set_config('app.assignment_ctx', '', true);

  insert into public.notifications (agent_id, category, title, body)
  values (v_agent.id, 'assignment', '新しい担当顧客が登録されました',
          v_customer.full_name || ' 様が担当顧客として登録されました。');

  return jsonb_build_object(
    'status', 'registered',
    'customer_id', case when v_role in ('admin', 'agent') then v_customer.id else null end,
    'assignment_changed', false,
    'assigned_agent_public_id', v_agent.public_id,
    'message', null
  );
end;
$fn$;

-- ============================================================================
-- 3. 担当変更 (ADMIN 専用)  (STEP2 原則8, CASE7 / CASE8)
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
  -- 絶対原則8: ADMIN 以外は例外なく拒否 (CASE7)
  if not app.is_admin() then
    raise exception 'TREEMERCE_ADMIN_ONLY: 担当変更は管理者のみ実行できます' using errcode = '42501';
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

-- ADMIN による顧客情報の更新 (識別子を含む全項目)
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
  if not app.is_admin() then
    raise exception 'TREEMERCE_ADMIN_ONLY: 管理者のみ実行できます' using errcode = '42501';
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
          p_customer_id, to_jsonb(v_before), to_jsonb(v_after), p_reason);

  return to_jsonb(v_after);
end;
$fn$;

-- ADMIN による代理店ステータス変更 (登録経路 invited_by は対象外 = 絶対原則2)
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
  if not app.is_admin() then
    raise exception 'TREEMERCE_ADMIN_ONLY: 管理者のみ実行できます' using errcode = '42501';
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

-- ============================================================================
-- 4. 商流マップ (STEP5)  — 完全に読み取り専用
-- ============================================================================
-- ・ログイン代理店を根とする部分木のみ (傘上・兄弟枝は再帰CTEの構造上入らない)
-- ・自分が担当する顧客のみ実名 + 購入商品
-- ・傘下の他代理店が担当する顧客は匿名ノード + 件数のみ
--   (氏名・連絡先・購入商品・販売額はレスポンスに一切含めない)

create or replace function public.treemerce_commerce_map(p_root_agent_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_scope     record;
  v_self      uuid := app.current_agent_id();
  v_is_admin  boolean := app.is_admin();
  v_agents    jsonb;
  v_customers jsonb;
begin
  select * into v_scope from app.resolve_scope(p_root_agent_id);

  select coalesce(jsonb_agg(node order by depth, public_id), '[]'::jsonb)
  into v_agents
  from (
    select s.depth,
           a.public_id,
           jsonb_build_object(
             'agent_id',       a.id,
             'public_id',      a.public_id,
             'display_name',   a.display_name,
             'status',         a.status,
             'depth',          s.depth,
             'invited_by',     s.parent_id,
             'is_self',        (a.id = v_self),
             'customer_count', (
               select count(*)
               from public.customer_assignments ca
               where ca.assigned_agent_id = a.id and ca.status = 'active'
             )
           ) as node
    from app.agent_subtree(v_scope.root_id, v_scope.is_all) s
    join public.agents a on a.id = s.agent_id
  ) q;

  select coalesce(jsonb_agg(node order by agent_sort, label), '[]'::jsonb)
  into v_customers
  from (
    select ca.assigned_agent_id::text as agent_sort,
           case when v_is_admin or ca.assigned_agent_id = v_self
                then c.full_name
                else app.customer_anon_label(c.id)
           end as label,
           case
             when v_is_admin or ca.assigned_agent_id = v_self then
               jsonb_build_object(
                 'anonymous',    false,
                 'customer_id',  c.id,
                 'agent_id',     ca.assigned_agent_id,
                 'label',        c.full_name,
                 'email',        c.email,
                 'phone',        c.phone,
                 'prefecture',   c.prefecture,
                 'assigned_at',  ca.assigned_at,
                 'purchases', (
                   select coalesce(jsonb_agg(jsonb_build_object(
                            'purchase_id',      p.id,
                            'product_name',     p.product_name,
                            'product_category', p.product_category,
                            'quantity',         p.quantity,
                            'amount',           p.amount,
                            'purchased_at',     p.purchased_at
                          ) order by p.purchased_at desc), '[]'::jsonb)
                   from public.purchases p
                   where p.customer_id = c.id
                 )
               )
             else
               -- 匿名ノード: 実データは一切含めない (CASE15)
               jsonb_build_object(
                 'anonymous',   true,
                 'customer_id', null,
                 'agent_id',    ca.assigned_agent_id,
                 'label',       app.customer_anon_label(c.id)
               )
           end as node
    from public.customer_assignments ca
    join public.customers c on c.id = ca.customer_id
    join app.agent_subtree(v_scope.root_id, v_scope.is_all) s
      on s.agent_id = ca.assigned_agent_id
    where ca.status = 'active'
  ) q;

  return jsonb_build_object(
    'viewer_role',   case when v_is_admin then 'admin' else 'agent' end,
    'root_agent_id', v_scope.root_id,
    'scope',         case when v_scope.is_all then 'all' else 'subtree' end,
    'agents',        v_agents,
    'customers',     v_customers,
    'generated_at',  now()
  );
end;
$fn$;

comment on function public.treemerce_commerce_map(uuid) is
  'STEP5 商流マップ。読み取り専用。傘下他代理店担当の顧客は匿名ノードのみを返す。';

-- ============================================================================
-- 5. 代理店コミュニティマップ (STEP7) — 代理店のみ。customers を一切含めない。
-- ============================================================================

create or replace function public.treemerce_community_map(p_root_agent_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_scope  record;
  v_self   uuid := app.current_agent_id();
  v_nodes  jsonb;
  v_edges  jsonb;
begin
  select * into v_scope from app.resolve_scope(p_root_agent_id);

  select coalesce(jsonb_agg(node order by depth, public_id), '[]'::jsonb)
  into v_nodes
  from (
    select s.depth, a.public_id,
           jsonb_build_object(
             'agent_id',     a.id,
             'public_id',    a.public_id,
             'display_name', a.display_name,
             'status',       a.status,
             'prefecture',   a.prefecture,
             'depth',        s.depth,
             'is_self',      (a.id = v_self),
             'registered_at', a.registered_at
           ) as node
    from app.agent_subtree(v_scope.root_id, v_scope.is_all) s
    join public.agents a on a.id = s.agent_id
  ) q;

  select coalesce(jsonb_agg(jsonb_build_object('from', parent_id, 'to', agent_id)), '[]'::jsonb)
  into v_edges
  from app.agent_subtree(v_scope.root_id, v_scope.is_all) s
  where s.parent_id is not null
    and exists (
      select 1 from app.agent_subtree(v_scope.root_id, v_scope.is_all) p
      where p.agent_id = s.parent_id
    );

  -- 顧客データは構造上ここに存在しない (STEP7 / CASE9)
  return jsonb_build_object(
    'root_agent_id', v_scope.root_id,
    'nodes',         v_nodes,
    'edges',         v_edges,
    'generated_at',  now()
  );
end;
$fn$;

-- ============================================================================
-- 6. 客層分析 (STEP6)
-- ============================================================================
-- ・集計対象 = 自分 + 傘下代理店全員 (商流マップと同じ再帰CTE)
-- ・傘下他代理店担当の顧客は属性値のみを匿名のまま合算
-- ・レスポンスに代理店別の内訳を一切含めない → どの代理店の担当か特定不能 (CASE18)
-- ・n < 5 のセグメントは「該当データ少数」に統合

create or replace function public.treemerce_customer_demographics(
  p_root_agent_id uuid default null,
  p_period        text default 'all'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_scope  record;
  v_from   timestamptz;
  v_k      constant integer := 5;
  v_result jsonb;
begin
  if p_period not in ('all', '3m', '1y') then
    raise exception 'TREEMERCE_INVALID_PERIOD: 期間指定が不正です' using errcode = '22023';
  end if;

  select * into v_scope from app.resolve_scope(p_root_agent_id);

  v_from := case p_period
              when '3m' then now() - interval '3 months'
              when '1y' then now() - interval '1 year'
              else null
            end;

  with scope as (
    select s.agent_id from app.agent_subtree(v_scope.root_id, v_scope.is_all) s
  ),
  base as (
    -- 個人PII (氏名・連絡先・購入明細) は一切取り出さず、属性値のみを扱う。
    select c.id,
           coalesce(c.age_group::text, 'unknown')      as age_group,
           coalesce(c.gender::text, 'prefer_not_to_say') as gender,
           coalesce(nullif(btrim(c.prefecture), ''), '未回答') as prefecture,
           c.customer_type::text                        as customer_type
    from public.customer_assignments ca
    join public.customers c on c.id = ca.customer_id
    where ca.status = 'active'
      and ca.assigned_agent_id in (select agent_id from scope)
      and (v_from is null or ca.assigned_at >= v_from)
  ),
  agg_age as (
    select jsonb_agg(jsonb_build_object('key', age_group, 'count', n)) as buckets
    from (select age_group, count(*)::int as n from base group by 1) t
  ),
  agg_gender as (
    select jsonb_agg(jsonb_build_object('key', gender, 'count', n)) as buckets
    from (select gender, count(*)::int as n from base group by 1) t
  ),
  agg_pref as (
    select jsonb_agg(jsonb_build_object('key', prefecture, 'count', n)) as buckets
    from (select prefecture, count(*)::int as n from base group by 1) t
  ),
  agg_type as (
    select jsonb_agg(jsonb_build_object('key', customer_type, 'count', n)) as buckets
    from (select customer_type, count(*)::int as n from base group by 1) t
  ),
  agg_cat as (
    select jsonb_agg(jsonb_build_object('key', category, 'count', n)) as buckets
    from (
      select p.product_category::text as category, count(*)::int as n
      from public.purchases p
      join base b on b.id = p.customer_id
      where p.status = 'completed'
        and (v_from is null or p.purchased_at >= v_from)
      group by 1
    ) t
  )
  select jsonb_build_object(
    'scope',            case when v_scope.is_all then 'all' else 'subtree' end,
    'root_agent_id',    v_scope.root_id,
    'period',           p_period,
    'k_threshold',      v_k,
    'total_customers',  (select count(*)::int from base),
    'scope_agent_count',(select count(*)::int from scope),
    'age_group',        app.apply_k_anonymity((select buckets from agg_age), v_k),
    'gender',           app.apply_k_anonymity((select buckets from agg_gender), v_k),
    'prefecture',       app.apply_k_anonymity((select buckets from agg_pref), v_k),
    'customer_type',    app.apply_k_anonymity((select buckets from agg_type), v_k),
    'product_category', app.apply_k_anonymity((select buckets from agg_cat), v_k),
    'generated_at',     now()
  ) into v_result;

  return v_result;
end;
$fn$;

comment on function public.treemerce_customer_demographics(uuid, text) is
  'STEP6 客層分析。自分+傘下を属性値のみで匿名合算。代理店別内訳は返さない。';

commit;
