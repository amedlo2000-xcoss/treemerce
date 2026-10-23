-- ============================================================================
-- TREEMERCE : 0032_treemerce_observer_wording.sql
-- DB が返す表示用の文言の「代理店」を「オブザーバー」に変更
-- ----------------------------------------------------------------------------
-- 画面の呼び名を「代理店」から「オブザーバー」に変えたことに合わせ、DB の関数が返す
-- 表示用の文言 (中立メッセージ・申し込み受付の文面・入力エラーの理由) だけを差し替える。
--   ・関数は最新の定義をそのまま写し、文字列の文言だけを変更する
--   ・エラーコード (TREEMERCE_〜)・引数・戻り値・処理内容は変更しない
--   ・create or replace のため、実行権 (GRANT/REVOKE)・所有者・コメントはそのまま引き継がれる
--   ・テーブル名・関数名・列名、関数内のコメントは変更しない
--   ・代理店規約の版 (agent_terms_versions) の本文・タイトルは対象外
-- ============================================================================

begin;

-- ============================================================================
-- 1. 重複検知 (最新の定義: 0003)
-- ============================================================================

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
      then 'このご連絡先は既に登録されています。担当オブザーバーの変更は行われません。詳細は運営事務局までお問い合わせください。'
      else null end
  );
end;
$fn$;

-- ============================================================================
-- 2. 顧客登録 (最新の定義: 0003)
-- ============================================================================

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
      'message', 'このご連絡先は既に登録されています。担当オブザーバーの変更は行われません。詳細は運営事務局までお問い合わせください。'
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
-- 3. 運営の代行による持込み申請 (最新の定義: 0024)
-- ============================================================================

create or replace function public.treemerce_admin_save_proxy_submission(
  p_agent_id                      uuid                    default null,
  p_submission_id                 uuid                    default null,
  p_name                          text                    default null,
  p_category                      public.product_category default null,
  p_description                   text                    default null,
  p_desired_price                 numeric                 default null,
  p_expected_wholesale_price      numeric                 default null,
  p_content_volume                text                    default null,
  p_ingredients                   text                    default null,
  p_best_before_note              text                    default null,
  p_producer_name                 text                    default null,
  p_producer_origin               text                    default null,
  p_producer_ship_from_prefecture text                    default null,
  p_producer_ship_lead_time       text                    default null,
  p_producer_contact_name         text                    default null,
  p_producer_contact_phone        text                    default null,
  p_producer_contact_email        text                    default null,
  p_reason                        text                    default null,
  p_category_id                   uuid                    default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid    uuid := auth.uid();
  v_role   text := coalesce(app.admin_role(), 'super_admin');
  v_before public.product_submissions%rowtype;
  v_after  public.product_submissions%rowtype;
  v_cat    uuid := coalesce(p_category_id, app.category_id_for_legacy(p_category));
  v_name   text;
  v_desc   text;
  v_volume text;
  v_ingr   text;
  v_best   text;
  v_p_name text;
  v_origin text;
  v_pref   text := nullif(btrim(coalesce(p_producer_ship_from_prefecture, '')), '');
  v_lead   text;
  v_c_name text;
  v_c_tel  text;
  v_c_mail text := nullif(lower(btrim(coalesce(p_producer_contact_email, ''))), '');
  v_reason text;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 申請の代行は super_admin のみ実行できます'
      using errcode = '42501';
  end if;

  v_name   := app.submission_text(p_name, 100, '商品名');
  v_desc   := app.submission_text(p_description, 4000, '説明');
  v_volume := app.submission_text(p_content_volume, 200, '内容量');
  v_ingr   := app.submission_text(p_ingredients, 2000, '原材料');
  v_best   := app.submission_text(p_best_before_note, 200, '期限の目安');
  v_p_name := app.submission_text(p_producer_name, 100, '生産者名');
  v_origin := app.submission_text(p_producer_origin, 100, '産地');
  v_lead   := app.submission_text(p_producer_ship_lead_time, 100, '発送目安');
  v_c_name := app.submission_text(p_producer_contact_name, 100, '生産者の担当者名');
  v_c_tel  := app.submission_text(p_producer_contact_phone, 30, '生産者の電話番号');
  v_reason := app.submission_text(p_reason, 500, '理由');

  if v_name is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 商品名は必須です' using errcode = '22023';
  end if;
  if p_desired_price is not null and (p_desired_price < 0 or p_desired_price >= 100000000) then
    raise exception 'TREEMERCE_INVALID_INPUT: 希望販売価格は 0 円以上 1 億円未満で入力してください'
      using errcode = '22023';
  end if;
  if p_expected_wholesale_price is not null
     and (p_expected_wholesale_price < 0 or p_expected_wholesale_price >= 100000000) then
    raise exception 'TREEMERCE_INVALID_INPUT: 想定卸値は 0 円以上 1 億円未満で入力してください'
      using errcode = '22023';
  end if;
  if v_pref is not null and not (v_pref = any (app.prefecture_list())) then
    raise exception 'TREEMERCE_INVALID_INPUT: 発送元の都道府県が正しくありません' using errcode = '22023';
  end if;
  if v_c_mail is not null and v_c_mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'TREEMERCE_INVALID_INPUT: 生産者の連絡先メールの形式が正しくありません'
      using errcode = '22023';
  end if;

  if p_submission_id is null then
    if p_agent_id is null then
      raise exception 'TREEMERCE_INVALID_INPUT: 代行するオブザーバーを指定してください' using errcode = '22023';
    end if;
    if v_reason is null then
      raise exception 'TREEMERCE_REASON_REQUIRED: 代行で作成する理由 (ヒアリングの日付・経緯など) は必須です'
        using errcode = '22023';
    end if;
    perform app.require_proxy_target_agent(p_agent_id);
    perform app.require_assignable_category(v_cat, null);

    perform set_config('app.submission_ctx', 'submission_admin_proxy', true);

    insert into public.product_submissions
      (agent_id, created_via, name, category_id, description, desired_price, expected_wholesale_price,
       content_volume, ingredients, best_before_note,
       producer_name, producer_origin, producer_ship_from_prefecture, producer_ship_lead_time,
       producer_contact_name, producer_contact_phone, producer_contact_email, created_by)
    values
      (p_agent_id, 'admin_proxy', v_name, v_cat, v_desc, p_desired_price,
       p_expected_wholesale_price, v_volume, v_ingr, v_best,
       v_p_name, v_origin, v_pref, v_lead,
       v_c_name, v_c_tel, v_c_mail, v_uid)
    returning * into v_after;

    perform set_config('app.submission_ctx', '', true);

    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (v_uid, v_role, 'submission.proxy_create', 'product_submissions', v_after.id,
            null, app.submission_audit_state(v_after), v_reason);
  else
    v_before := app.lock_proxy_submission(p_submission_id);
    if p_agent_id is not null and p_agent_id is distinct from v_before.agent_id then
      raise exception 'TREEMERCE_SUBMISSION_AGENT_MISMATCH: 申請の代理店と指定の代理店が一致しません'
        using errcode = '22023';
    end if;
    if v_before.status not in ('draft', 'returned') then
      raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 申請中・確定済みの申請は編集できません'
        using errcode = '22023';
    end if;
    perform app.require_proxy_target_agent(v_before.agent_id);
    perform app.require_assignable_category(v_cat, v_before.category_id);

    perform set_config('app.submission_ctx', 'submission_admin_proxy', true);

    update public.product_submissions
    set name                          = v_name,
        category_id                   = v_cat,
        description                   = v_desc,
        desired_price                 = p_desired_price,
        expected_wholesale_price      = p_expected_wholesale_price,
        content_volume                = v_volume,
        ingredients                   = v_ingr,
        best_before_note              = v_best,
        producer_name                 = v_p_name,
        producer_origin               = v_origin,
        producer_ship_from_prefecture = v_pref,
        producer_ship_lead_time       = v_lead,
        producer_contact_name         = v_c_name,
        producer_contact_phone        = v_c_tel,
        producer_contact_email        = v_c_mail
    where id = v_before.id
    returning * into v_after;

    perform set_config('app.submission_ctx', '', true);

    if jsonb_array_length(app.submission_changed_fields(v_before, v_after)) > 0 then
      insert into public.admin_audit_logs
        (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
      values (v_uid, v_role, 'submission.proxy_update', 'product_submissions', v_after.id,
              app.submission_audit_state(v_before),
              app.submission_audit_state(v_after)
                || jsonb_build_object('changed_fields', app.submission_changed_fields(v_before, v_after)),
              v_reason);
    end if;
  end if;

  return app.submission_json(v_after, true)
         || jsonb_build_object('images', app.submission_images_json(v_after.id));
end;
$fn$;

-- ============================================================================
-- 4. 申し込み受付の文面 (最新の定義: 0028)
-- ============================================================================

create or replace function app.agent_application_received_message()
returns text
language sql
immutable
as $fn$
  select 'オブザーバー登録のお申し込みを受け付けました。内容を確認のうえ、運営事務局よりご連絡します。'::text;
$fn$;

-- ============================================================================
-- 5. オブザーバーの作成 (最新の定義: 0028)
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
    raise exception 'TREEMERCE_INVALID_INPUT: オブザーバー名は必須です' using errcode = '22023';
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

-- ============================================================================
-- 6. 本人の申請状況 (最新の定義: 0028)
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
                         'message', 'オブザーバーとしてご利用いただけます。')
    else
      jsonb_build_object('state', 'closed',
                         'message', '現在お受けしているお申し込みはありません。詳しくは運営事務局までお問い合わせください。')
  end;
end;
$fn$;

-- ============================================================================
-- 7. 申込者の入力チェック (最新の定義: 0030)
-- ============================================================================

create or replace function app.check_agent_applicant(
  p_accept_terms  boolean,
  p_terms_version text,
  p_display_name  text,
  p_email         text,
  out o_terms_id   uuid,
  out o_user_email text
)
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid       uuid := auth.uid();
  v_terms     public.agent_terms_versions%rowtype;
  v_email     text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_confirmed timestamptz;
begin
  if not coalesce(p_accept_terms, false) then
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
  if p_terms_version is null or btrim(p_terms_version) <> v_terms.version then
    raise exception 'TREEMERCE_TERMS_VERSION_MISMATCH: 代理店規約が更新されています。最新の規約をご確認のうえ、改めて同意してください'
      using errcode = '22023';
  end if;

  if p_display_name is null or btrim(p_display_name) = '' then
    raise exception 'TREEMERCE_INVALID_INPUT: オブザーバー名は必須です' using errcode = '22023';
  end if;

  select u.email, u.email_confirmed_at into o_user_email, v_confirmed
  from auth.users u where u.id = v_uid;
  if o_user_email is null or v_confirmed is null
     or v_email is null or lower(btrim(o_user_email)) <> v_email then
    raise exception 'TREEMERCE_APPLICANT_EMAIL_MISMATCH: メールアドレスがログイン中のアカウントと一致しません'
      using errcode = '22023';
  end if;

  o_terms_id := v_terms.id;
end;
$fn$;

-- ============================================================================
-- 8. 登録リンクからの申し込み (最新の定義: 0031)
-- ============================================================================

create or replace function public.treemerce_apply_agent_via_link(
  p_token               text,
  p_agent_display_name  text,
  p_full_name           text,
  p_email               text,
  p_phone               text default null,
  p_accept_agent_terms  boolean default false,
  p_agent_terms_version text default null,
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
  v_terms_id   uuid;
  v_user_email text;
  v_link       public.agent_registration_links%rowtype;
  v_state      text;
  v_app_id     uuid;
begin
  select c.o_terms_id, c.o_user_email into v_terms_id, v_user_email
  from app.check_agent_applicant(p_accept_agent_terms, p_agent_terms_version,
                                 p_agent_display_name, p_email) c;

  if p_full_name is null or btrim(p_full_name) = '' then
    raise exception 'TREEMERCE_INVALID_INPUT: 氏名は必須です' using errcode = '22023';
  end if;
  if char_length(btrim(p_full_name)) > 100 or char_length(btrim(p_agent_display_name)) > 100 then
    raise exception 'TREEMERCE_INVALID_INPUT: オブザーバー名・氏名は 100 文字以内で入力してください' using errcode = '22023';
  end if;

  -- リンクをロックして使用回数の上限を守る
  select * into v_link from public.agent_registration_links
  where token_sha256 = app.registration_link_hash(p_token)
  for update;
  if not found then
    raise exception 'TREEMERCE_REGISTRATION_LINK_UNAVAILABLE: この代理店登録リンクは利用できません'
      using errcode = '22023';
  end if;
  v_state := app.registration_link_state(v_link);
  if v_state <> 'active' then
    raise exception 'TREEMERCE_REGISTRATION_LINK_UNAVAILABLE: この代理店登録リンクは利用できません (%)', v_state
      using errcode = '22023';
  end if;

  -- 紹介者 = リンクの発行元。運営のリンクは admin_link (紹介者なし)、代理店のリンクは agent_link
  v_app_id := app.submit_agent_application(
    p_agent_display_name, p_email, p_phone,
    case when v_link.issuer_agent_id is null then 'admin_link' else 'agent_link' end::public.agent_application_source,
    v_link.issuer_agent_id, v_link.id,
    v_terms_id, v_user_email, p_ip_address, p_user_agent, p_full_name);

  -- 申請を作れたときだけ使用回数を数える (重複・既に代理店のときは数えない)
  if v_app_id is not null then
    perform set_config('app.registration_link_ctx', 'use', true);
    update public.agent_registration_links set used_count = used_count + 1 where id = v_link.id;
    perform set_config('app.registration_link_ctx', '', true);
  end if;

  -- 申請ID・リンク・紹介者の情報は返さない
  return jsonb_build_object(
    'application_status',  'received',
    'application_message', app.agent_application_received_message()
  );
end;
$fn$;

commit;
