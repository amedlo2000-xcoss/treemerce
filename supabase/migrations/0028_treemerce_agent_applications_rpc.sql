-- ============================================================================
-- TREEMERCE : 0028_treemerce_agent_applications_rpc.sql
-- 代理店申請・承認 / 代理店作成の一本化 (RPC)
-- ----------------------------------------------------------------------------
-- 代理店の作成と招待経路 (agents.invited_by) の確定は app.create_agent() だけが行う。
-- 呼び出し元は次の2つに限る。
--   (1) treemerce_admin_approve_agent_application() : 申請の承認 (招待元 = 申請に固定された値)
--   (2) treemerce_register_agent()                  : super_admin による直接作成 (招待元を明示指定)
-- 一般ユーザーが代理店を作る経路は無い。申請は treemerce_register_member() から行う。
--
-- 絶対原則
--   2. 承認処理は招待元を受け取らない。申請の inviter_agent_id をそのまま使う。
--   3/4. 申請・承認のどちらも customer_assignments を読まず・書かない。
--   6. 申請の重複・既に代理店であるときも、新規受付と同じ中立メッセージだけを返す。
--      本人向けの RPC は却下理由・招待元・担当代理店を返さない。
--   7. 申請者の照合はアカウント・メールアドレス・電話番号で行う。氏名・代理店名は使わない。
--   8. 承認・却下・代理店作成は admin_audit_logs に記録する。
-- ============================================================================

begin;

-- ============================================================================
-- 1. 中立メッセージ
-- ============================================================================

-- 申請の受付・重複・既に代理店、のいずれでも同じ文面を返す (絶対原則6)
create or replace function app.agent_application_received_message()
returns text
language sql
immutable
as $fn$
  select '代理店登録のお申し込みを受け付けました。内容を確認のうえ、運営事務局よりご連絡します。'::text;
$fn$;

-- ============================================================================
-- 2. app.create_agent : 代理店作成と招待経路確定の唯一の処理
-- ============================================================================

create or replace function app.create_agent(
  p_auth_user_id     uuid,
  p_display_name     text,
  p_email            text,
  p_phone            text,
  p_inviter_agent_id uuid,
  p_source           text,
  p_application_id   uuid,
  p_reason           text
)
returns public.agents
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_agent   public.agents%rowtype;
  v_inviter public.agents%rowtype;
  v_email   text := nullif(lower(btrim(coalesce(p_email, ''))), '');
begin
  -- 呼び出し元の RPC でも判定しているが、ここでも必ず確認する (多層防御)
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 代理店の作成は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  if p_source not in ('application', 'direct') then
    raise exception 'TREEMERCE_INVALID_INPUT: 作成経路の指定が不正です' using errcode = '22023';
  end if;
  if p_source = 'application' and p_application_id is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 申請からの作成には申請IDが必要です' using errcode = '22023';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'TREEMERCE_REASON_REQUIRED: 理由は必須です' using errcode = '22023';
  end if;
  if p_display_name is null or btrim(p_display_name) = '' then
    raise exception 'TREEMERCE_INVALID_INPUT: 代理店名は必須です' using errcode = '22023';
  end if;
  if v_email is null then
    raise exception 'TREEMERCE_INVALID_INPUT: メールアドレスは必須です' using errcode = '22023';
  end if;

  if p_auth_user_id is null or not exists (select 1 from auth.users u where u.id = p_auth_user_id) then
    raise exception 'TREEMERCE_USER_NOT_FOUND: 対象のアカウントが見つかりません' using errcode = '22023';
  end if;
  if exists (select 1 from public.agents a where a.auth_user_id = p_auth_user_id) then
    raise exception 'TREEMERCE_AGENT_ALREADY_EXISTS: このアカウントは既に代理店です' using errcode = '23505';
  end if;
  if exists (select 1 from public.agents a where a.email_normalized = v_email) then
    raise exception 'TREEMERCE_AGENT_EMAIL_TAKEN: このメールアドレスの代理店が既に存在します' using errcode = '23505';
  end if;

  if p_inviter_agent_id is not null then
    select * into v_inviter from public.agents where id = p_inviter_agent_id;
    if not found or v_inviter.status <> 'active' then
      -- 招待元を別の代理店に置き換えることはしない (絶対原則2)
      raise exception 'TREEMERCE_INVITER_UNAVAILABLE: 招待元の代理店が稼働中ではないため作成できません'
        using errcode = '22023';
    end if;
  end if;

  perform set_config('app.agent_create_ctx', 'create', true);

  insert into public.agents (auth_user_id, display_name, email, phone, status, invited_by)
  values (p_auth_user_id, btrim(p_display_name), btrim(p_email),
          nullif(btrim(coalesce(p_phone, '')), ''), 'active', p_inviter_agent_id)
  returning * into v_agent;

  perform set_config('app.agent_create_ctx', '', true);

  -- 誰が (actor_user_id)・いつ (created_at)・どの招待元で (invited_by) 作ったか
  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (auth.uid(), coalesce(app.admin_role(), 'admin'), 'agent.create', 'agents', v_agent.id,
          null,
          jsonb_build_object(
            'agent_id',       v_agent.id,
            'public_id',      v_agent.public_id,
            'auth_user_id',   v_agent.auth_user_id,
            'display_name',   v_agent.display_name,
            'email',          v_agent.email,
            'status',         v_agent.status,
            'invited_by',     v_agent.invited_by,
            'source',         p_source,
            'application_id', p_application_id
          ),
          btrim(p_reason));

  return v_agent;
end;
$fn$;

comment on function app.create_agent(uuid, text, text, text, uuid, text, uuid, text) is
  '代理店作成と招待経路(invited_by)確定の唯一の処理。super_admin のみ。直接 EXECUTE は不可。';

-- ============================================================================
-- 3. treemerce_register_agent : super_admin による直接作成 (旧: 誰でも即稼働で作成)
-- ============================================================================

drop function if exists public.treemerce_register_agent(text, text, text, text);

create or replace function public.treemerce_register_agent(
  p_auth_user_id     uuid,
  p_display_name     text,
  p_email            text,
  p_phone            text,
  p_inviter_mode     text,
  p_inviter_agent_id uuid,
  p_reason           text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_agent      public.agents%rowtype;
  v_user_email text;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 代理店の直接作成は super_admin のみ実行できます。代理店登録は登録フォームからお申し込みください'
      using errcode = '42501';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'TREEMERCE_REASON_REQUIRED: 作成理由は必須です' using errcode = '22023';
  end if;

  -- 招待元は必ず明示させる。「招待元なし」も 'none' として明示が必要。
  if p_inviter_mode is null or p_inviter_mode not in ('agent', 'none')
     or (p_inviter_mode = 'agent' and p_inviter_agent_id is null)
     or (p_inviter_mode = 'none' and p_inviter_agent_id is not null) then
    raise exception 'TREEMERCE_INVITER_REQUIRED: 招待元を指定してください (代理店を指定するか、招待元なしを明示)'
      using errcode = '22023';
  end if;

  select u.email into v_user_email from auth.users u where u.id = p_auth_user_id;
  if v_user_email is null then
    raise exception 'TREEMERCE_USER_NOT_FOUND: 対象のアカウントが見つかりません' using errcode = '22023';
  end if;
  -- 絶対原則7: 代理店のメールアドレスはログインアカウントのメールアドレスと一致させる
  if lower(btrim(v_user_email)) <> lower(btrim(coalesce(p_email, ''))) then
    raise exception 'TREEMERCE_EMAIL_MISMATCH: メールアドレスが対象アカウントと一致しません'
      using errcode = '22023';
  end if;

  v_agent := app.create_agent(p_auth_user_id, p_display_name, p_email, p_phone,
                              p_inviter_agent_id, 'direct', null, p_reason);

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
-- 4. 代理店規約 (公開)
-- ============================================================================

create or replace function public.treemerce_current_agent_terms()
returns jsonb
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select coalesce(
    (select jsonb_build_object(
              'available',    true,
              'version',      t.version,
              'title',        t.title,
              'body',         t.body,
              'body_sha256',  t.body_sha256,
              'published_at', t.published_at)
     from public.agent_terms_versions t
     where t.is_current),
    jsonb_build_object('available', false)
  );
$fn$;

-- ============================================================================
-- 5. treemerce_register_member : 紹介リンクからの登録 (会員登録 + 任意で代理店申請)
-- ============================================================================
-- 会員の部分は treemerce_register_customer() をそのまま呼ぶ (顧客登録の唯一の入口)。
-- 申請は「申し込む」「規約に同意」の両方が true のときだけ作る。
--   ・申し込む = true / 同意 = false → 全体を拒否 (何も作らない)
--   ・申し込む = false               → 会員登録のみ (同意の値は記録しない)
-- 申請するときはログイン必須で、フォームのメールアドレスは確認済みのアカウントの
-- メールアドレスと一致しなければならない。
--
-- p_ip_address / p_user_agent はクライアント (画面) から送られた値を信用しない。
-- API ルートがサーバー側でリクエストヘッダーから取得した値だけを渡すこと。
-- (画面のリクエスト本文にこの2項目を含めても API ルートは無視する。参考情報として
--  保存するだけで、認可や照合の判定には使わない)

create or replace function public.treemerce_register_member(
  p_agent_public_id     text,
  p_full_name           text,
  p_email               text default null,
  p_phone               text default null,
  p_full_name_kana      text default null,
  p_age_group           public.customer_age_group default null,
  p_gender              public.customer_gender    default null,
  p_prefecture          text default null,
  p_customer_type       public.customer_kind      default 'individual',
  p_postal_code         text default null,
  p_address_line        text default null,
  p_apply_agent         boolean default false,
  p_accept_agent_terms  boolean default false,
  p_agent_terms_version text default null,
  p_agent_display_name  text default null,
  p_ip_address          text default null,
  p_user_agent          text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid        uuid := auth.uid();
  v_apply      boolean := coalesce(p_apply_agent, false);
  v_email      text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_phone      text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '');
  v_user_email text;
  v_confirmed  timestamptz;
  v_terms      public.agent_terms_versions%rowtype;
  v_link       public.agents%rowtype;
  v_reg        jsonb;
  v_app_id     uuid;
  v_app_result text := null;
begin
  -- ---- 申請の事前検証 (失敗時は会員登録も含めて何も作らない) -------------------
  if v_apply then
    if not coalesce(p_accept_agent_terms, false) then
      raise exception 'TREEMERCE_TERMS_CONSENT_REQUIRED: 代理店登録のお申し込みには代理店規約への同意が必要です'
        using errcode = '22023';
    end if;
    if v_uid is null then
      raise exception 'TREEMERCE_UNAUTHENTICATED: 代理店登録のお申し込みにはログインが必要です'
        using errcode = '42501';
    end if;

    select * into v_terms from public.agent_terms_versions where is_current;
    if not found then
      raise exception 'TREEMERCE_TERMS_NOT_AVAILABLE: 代理店規約を準備中のため、現在お申し込みを受け付けていません'
        using errcode = '22023';
    end if;
    if p_agent_terms_version is null or btrim(p_agent_terms_version) <> v_terms.version then
      raise exception 'TREEMERCE_TERMS_VERSION_MISMATCH: 代理店規約が更新されています。最新の規約をご確認のうえ、改めて同意してください'
        using errcode = '22023';
    end if;

    if p_agent_display_name is null or btrim(p_agent_display_name) = '' then
      raise exception 'TREEMERCE_INVALID_INPUT: 代理店名は必須です' using errcode = '22023';
    end if;

    select u.email, u.email_confirmed_at into v_user_email, v_confirmed
    from auth.users u where u.id = v_uid;
    if v_user_email is null or v_confirmed is null
       or v_email is null or lower(btrim(v_user_email)) <> v_email then
      raise exception 'TREEMERCE_APPLICANT_EMAIL_MISMATCH: メールアドレスがログイン中のアカウントと一致しません'
        using errcode = '22023';
    end if;
  end if;

  -- ---- 会員登録 (担当の確定・重複時の中立メッセージは既存の入口に任せる) --------
  v_reg := public.treemerce_register_customer(
    p_agent_public_id => p_agent_public_id,
    p_full_name       => p_full_name,
    p_email           => p_email,
    p_phone           => p_phone,
    p_full_name_kana  => p_full_name_kana,
    p_age_group       => p_age_group,
    p_gender          => p_gender,
    p_prefecture      => p_prefecture,
    p_customer_type   => p_customer_type,
    p_postal_code     => p_postal_code,
    p_address_line    => p_address_line
  );

  -- ---- 代理店申請 ---------------------------------------------------------------
  if v_apply then
    -- 招待元 = 申請に使われたリンクの代理店 (treemerce_register_customer が稼働中であることを確認済み)
    select * into v_link
    from public.agents
    where public_id = btrim(p_agent_public_id) and status = 'active';
    if not found then
      -- 招待元が確定できない申請は作らない (別の代理店や NULL で代用しない)
      raise exception 'TREEMERCE_AGENT_NOT_FOUND: 紹介リンクが無効です' using errcode = '22023';
    end if;

    v_app_result := 'received';

    -- 既に代理店 / 承認待ちの申請あり → 何も作らず、新規受付と同じ文面 (絶対原則6・7)
    if exists (select 1 from public.agents a
               where a.auth_user_id = v_uid or a.email_normalized = v_email)
       or exists (select 1 from public.agent_applications ap
                  where ap.status = 'pending'
                    and (ap.auth_user_id = v_uid
                         or ap.email_normalized = v_email
                         or (v_phone is not null and ap.phone_normalized = v_phone))) then
      null;
    else
      begin
        perform set_config('app.agent_application_ctx', 'apply', true);

        insert into public.agent_applications
          (auth_user_id, display_name, email, phone, inviter_agent_id, terms_version_id)
        values (v_uid, btrim(p_agent_display_name), btrim(p_email),
                nullif(btrim(coalesce(p_phone, '')), ''), v_link.id, v_terms.id)
        returning id into v_app_id;

        insert into public.agent_terms_acceptances
          (terms_version_id, application_id, auth_user_id, accepted_email, ip_address, user_agent)
        values (v_terms.id, v_app_id, v_uid, v_user_email,
                nullif(btrim(coalesce(p_ip_address, '')), ''),
                nullif(left(btrim(coalesce(p_user_agent, '')), 1000), ''));

        perform set_config('app.agent_application_ctx', '', true);
      exception when unique_violation then
        -- 同時に申請された場合も中立メッセージで受け付けた扱いにする
        perform set_config('app.agent_application_ctx', '', true);
      end;
    end if;
  end if;

  -- customer_id・担当代理店・申請ID・招待元は返さない
  return jsonb_build_object(
    'member_status',       v_reg ->> 'status',
    'member_message',      v_reg ->> 'message',
    'application_status',  v_app_result,
    'application_message', case when v_app_result is not null
                             then app.agent_application_received_message() end
  );
end;
$fn$;

-- ============================================================================
-- 6. treemerce_my_agent_application : 本人の申請状況 (中立表示のみ)
-- ============================================================================

create or replace function public.treemerce_my_agent_application()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid    uuid := auth.uid();
  v_status public.agent_application_status;
begin
  if v_uid is null then
    raise exception 'TREEMERCE_UNAUTHENTICATED: ログインが必要です' using errcode = '42501';
  end if;

  select ap.status into v_status
  from public.agent_applications ap
  where ap.auth_user_id = v_uid
  order by ap.created_at desc
  limit 1;

  -- 却下理由・招待元・審査者は返さない
  return case
    when v_status is null then
      jsonb_build_object('state', 'none', 'message', null)
    when v_status = 'pending' then
      jsonb_build_object('state', 'received', 'message', app.agent_application_received_message())
    when v_status = 'approved' then
      jsonb_build_object('state', 'approved',
                         'message', '代理店としてご利用いただけます。')
    else
      jsonb_build_object('state', 'closed',
                         'message', '現在お受けしているお申し込みはありません。詳しくは運営事務局までお問い合わせください。')
  end;
end;
$fn$;

-- ============================================================================
-- 7. 審査 (super_admin)
-- ============================================================================

create or replace function app.agent_application_json(p_app public.agent_applications)
returns jsonb
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select jsonb_build_object(
    'id',               p_app.id,
    'status',           p_app.status,
    'auth_user_id',     p_app.auth_user_id,
    'display_name',     p_app.display_name,
    'email',            p_app.email,
    'phone',            p_app.phone,
    'created_at',       p_app.created_at,
    'reviewed_at',      p_app.reviewed_at,
    'reviewed_by',      p_app.reviewed_by,
    'created_agent_id', p_app.created_agent_id,
    'inviter', (select jsonb_build_object('id', a.id, 'public_id', a.public_id,
                                          'display_name', a.display_name, 'status', a.status)
                from public.agents a where a.id = p_app.inviter_agent_id),
    'terms', (select jsonb_build_object('version', t.version, 'title', t.title,
                                        'body_sha256', t.body_sha256,
                                        'accepted_at', ta.accepted_at,
                                        'accepted_email', ta.accepted_email,
                                        'ip_address', ta.ip_address,
                                        'user_agent', ta.user_agent)
              from public.agent_terms_versions t
              left join public.agent_terms_acceptances ta on ta.application_id = p_app.id
              where t.id = p_app.terms_version_id)
  );
$fn$;

create or replace function public.treemerce_admin_list_agent_applications(
  p_status public.agent_application_status default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: super_admin のみ実行できます' using errcode = '42501';
  end if;

  return coalesce(
    (select jsonb_agg(app.agent_application_json(ap) order by ap.created_at desc)
     from public.agent_applications ap
     where p_status is null or ap.status = p_status),
    '[]'::jsonb
  );
end;
$fn$;

create or replace function public.treemerce_admin_get_agent_application(p_application_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_app public.agent_applications%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: super_admin のみ実行できます' using errcode = '42501';
  end if;

  select * into v_app from public.agent_applications where id = p_application_id;
  if not found then
    raise exception 'TREEMERCE_APPLICATION_NOT_FOUND: 申請が見つかりません' using errcode = '22023';
  end if;

  -- 審査の履歴 (却下理由を含む) は super_admin にだけ返す
  return app.agent_application_json(v_app) || jsonb_build_object(
    'audit', coalesce(
      (select jsonb_agg(jsonb_build_object(
                'action', l.action, 'actor_user_id', l.actor_user_id, 'actor_role', l.actor_role,
                'reason', l.reason, 'created_at', l.created_at)
              order by l.created_at)
       from public.admin_audit_logs l
       where l.target_table = 'agent_applications' and l.target_id = v_app.id),
      '[]'::jsonb)
  );
end;
$fn$;

-- 承認: 招待元は引数で受け取らない。申請に固定された inviter_agent_id をそのまま使う。
create or replace function public.treemerce_admin_approve_agent_application(
  p_application_id uuid,
  p_reason         text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_before public.agent_applications%rowtype;
  v_after  public.agent_applications%rowtype;
  v_agent  public.agents%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 承認は super_admin のみ実行できます' using errcode = '42501';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'TREEMERCE_REASON_REQUIRED: 承認理由は必須です' using errcode = '22023';
  end if;

  select * into v_before from public.agent_applications where id = p_application_id for update;
  if not found then
    raise exception 'TREEMERCE_APPLICATION_NOT_FOUND: 申請が見つかりません' using errcode = '22023';
  end if;
  if v_before.status <> 'pending' then
    raise exception 'TREEMERCE_APPLICATION_NOT_PENDING: この申請は既に審査済みです' using errcode = '22023';
  end if;
  if not exists (select 1 from public.agent_terms_acceptances ta where ta.application_id = v_before.id) then
    raise exception 'TREEMERCE_TERMS_ACCEPTANCE_MISSING: 規約の同意記録がない申請は承認できません'
      using errcode = '22023';
  end if;

  v_agent := app.create_agent(v_before.auth_user_id, v_before.display_name, v_before.email,
                              v_before.phone, v_before.inviter_agent_id, 'application',
                              v_before.id, p_reason);

  perform set_config('app.agent_application_ctx', 'review', true);
  update public.agent_applications
  set status = 'approved', reviewed_by = auth.uid(), reviewed_at = clock_timestamp(),
      created_agent_id = v_agent.id
  where id = v_before.id
  returning * into v_after;
  perform set_config('app.agent_application_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (auth.uid(), coalesce(app.admin_role(), 'admin'), 'agent_application.approve',
          'agent_applications', v_before.id,
          jsonb_build_object('status', v_before.status, 'inviter_agent_id', v_before.inviter_agent_id),
          jsonb_build_object('status', v_after.status, 'inviter_agent_id', v_after.inviter_agent_id,
                             'created_agent_id', v_after.created_agent_id,
                             'reviewed_at', v_after.reviewed_at),
          btrim(p_reason));

  return jsonb_build_object(
    'application_id', v_after.id,
    'status',         v_after.status,
    'agent_id',       v_agent.id,
    'public_id',      v_agent.public_id,
    'invited_by',     v_agent.invited_by
  );
end;
$fn$;

-- 却下: 代理店は作らない (会員のまま)。理由は監査ログにだけ残す。
create or replace function public.treemerce_admin_reject_agent_application(
  p_application_id uuid,
  p_reason         text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_before public.agent_applications%rowtype;
  v_after  public.agent_applications%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 却下は super_admin のみ実行できます' using errcode = '42501';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'TREEMERCE_REASON_REQUIRED: 却下理由は必須です' using errcode = '22023';
  end if;

  select * into v_before from public.agent_applications where id = p_application_id for update;
  if not found then
    raise exception 'TREEMERCE_APPLICATION_NOT_FOUND: 申請が見つかりません' using errcode = '22023';
  end if;
  if v_before.status <> 'pending' then
    raise exception 'TREEMERCE_APPLICATION_NOT_PENDING: この申請は既に審査済みです' using errcode = '22023';
  end if;

  perform set_config('app.agent_application_ctx', 'review', true);
  update public.agent_applications
  set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = clock_timestamp()
  where id = v_before.id
  returning * into v_after;
  perform set_config('app.agent_application_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (auth.uid(), coalesce(app.admin_role(), 'admin'), 'agent_application.reject',
          'agent_applications', v_before.id,
          jsonb_build_object('status', v_before.status),
          jsonb_build_object('status', v_after.status, 'reviewed_at', v_after.reviewed_at),
          btrim(p_reason));

  return jsonb_build_object('application_id', v_after.id, 'status', v_after.status);
end;
$fn$;

-- ============================================================================
-- 8. 権限
-- ============================================================================

revoke all on function app.agent_application_received_message() from public, anon, authenticated;
revoke all on function app.create_agent(uuid, text, text, text, uuid, text, uuid, text)
  from public, anon, authenticated;
revoke all on function app.agent_application_json(public.agent_applications)
  from public, anon, authenticated;

revoke all on function public.treemerce_register_agent(uuid, text, text, text, text, uuid, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_current_agent_terms() from public, anon, authenticated;
revoke all on function public.treemerce_register_member(
  text, text, text, text, text,
  public.customer_age_group, public.customer_gender, text,
  public.customer_kind, text, text,
  boolean, boolean, text, text, text, text) from public, anon, authenticated;
revoke all on function public.treemerce_my_agent_application() from public, anon, authenticated;
revoke all on function public.treemerce_admin_list_agent_applications(public.agent_application_status)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_get_agent_application(uuid) from public, anon, authenticated;
revoke all on function public.treemerce_admin_approve_agent_application(uuid, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_reject_agent_application(uuid, text)
  from public, anon, authenticated;

-- 公開 (未ログインでも会員登録はできる。申請部分は関数内でログインを必須にする)
grant execute on function public.treemerce_current_agent_terms() to anon, authenticated;
grant execute on function public.treemerce_register_member(
  text, text, text, text, text,
  public.customer_age_group, public.customer_gender, text,
  public.customer_kind, text, text,
  boolean, boolean, text, text, text, text) to anon, authenticated;

-- ログインユーザー本人
grant execute on function public.treemerce_my_agent_application() to authenticated;

-- super_admin 専用 (関数内部で app.is_super_admin() を必須チェック)
grant execute on function public.treemerce_register_agent(uuid, text, text, text, text, uuid, text)
  to authenticated;
grant execute on function public.treemerce_admin_list_agent_applications(public.agent_application_status)
  to authenticated;
grant execute on function public.treemerce_admin_get_agent_application(uuid) to authenticated;
grant execute on function public.treemerce_admin_approve_agent_application(uuid, text) to authenticated;
grant execute on function public.treemerce_admin_reject_agent_application(uuid, text) to authenticated;

commit;
