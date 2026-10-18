-- ============================================================================
-- TREEMERCE : 0030_treemerce_agent_registration_links.sql
-- 運営が発行する代理店登録リンク (代理店登録の入口 ②)
-- ----------------------------------------------------------------------------
-- 代理店登録の入口は2種類になる。
--   ① 既存代理店の紹介リンク (/register/{公開ID}) : 会員登録 + 任意で代理店申請 (0028)。
--      申請の招待元 = リンクの代理店。
--   ② 運営の登録リンク (/join/{トークン})          : 代理店の申し込みだけ (会員登録は行わない)。
--      申請の招待元 = なし (運営からの直接登録)。
-- どちらの申請も同じ承認画面に届き、承認で app.create_agent() を通して代理店になる。
--
-- 絶対原則
--   1/3/4. ②は customers・customer_assignments に一切触れない。
--   2.     申請の経路 (source)・リンク・招待元は申請時点で固定し、変更できない。
--          ①は招待元が必須、②は招待元なし (NULL) を CHECK 制約で強制する。
--          ②で作られた代理店に後から招待元を付けることも 0027 のトリガで拒否される。
--   6/7.   重複・既に代理店であるときは何も作らず、新規受付と同じ中立メッセージ。
--          照合はアカウント・メールアドレス・電話番号。
--   8.     リンクの発行・無効化、申し込み (①②とも)、承認・却下は admin_audit_logs に残す。
-- リンクのトークンは DB にハッシュ (SHA-256) だけを保存し、URL は発行の直後に一度だけ返す。
-- ガードの「DB管理者の直接操作」の例外は session_user で判定する (0029)。
-- ============================================================================

begin;

-- ============================================================================
-- 1. agent_registration_links (運営の代理店登録リンク)
-- ============================================================================

create type public.agent_registration_link_status as enum ('active', 'revoked');

create table public.agent_registration_links (
  id           uuid primary key default gen_random_uuid(),
  -- トークンそのものは保存しない (DB から読み取られてもリンクとして使えないようにする)
  token_sha256 text not null unique check (token_sha256 ~ '^[0-9a-f]{64}$'),
  note         text check (note is null or char_length(note) <= 200),
  max_uses     integer check (max_uses is null or max_uses > 0),
  used_count   integer not null default 0 check (used_count >= 0),
  expires_at   timestamptz,
  status       public.agent_registration_link_status not null default 'active',
  created_by   uuid,
  created_at   timestamptz not null default clock_timestamp(),
  revoked_by   uuid,
  revoked_at   timestamptz,

  constraint agent_registration_links_uses_within_limit
    check (max_uses is null or used_count <= max_uses),
  constraint agent_registration_links_revoke_consistency
    check ((status = 'active' and revoked_at is null and revoked_by is null)
        or (status = 'revoked' and revoked_at is not null))
);

comment on table public.agent_registration_links is
  '運営 (super_admin) が発行する代理店登録リンク。申し込みの招待元はなし。トークンはハッシュのみ保存。';

-- 発行内容 (トークン・メモ・上限・期限・作成情報) は変更できない。
-- 変更できるのは、申し込みによる使用回数の +1 と、無効化 (1回だけ) のみ。削除は不可。
create or replace function app.guard_agent_registration_links_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.registration_link_ctx', true), '');
begin
  if tg_op = 'DELETE' then
    raise exception 'TREEMERCE_REGISTRATION_LINK_DELETE_DENIED: 代理店登録リンクは削除できません (無効化で扱う)'
      using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    -- DB管理者の直接操作は session_user で判定する (0029)
    if v_ctx = 'link_admin' or (session_user = 'postgres' and v_ctx = '') then
      return new;
    end if;
    raise exception 'TREEMERCE_REGISTRATION_LINK_WRITE_DENIED: 代理店登録リンクは super_admin の発行処理でのみ作成できます'
      using errcode = '42501';
  end if;

  -- UPDATE
  if new.id is distinct from old.id
     or new.token_sha256 is distinct from old.token_sha256
     or new.note is distinct from old.note
     or new.max_uses is distinct from old.max_uses
     or new.expires_at is distinct from old.expires_at
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'TREEMERCE_REGISTRATION_LINK_IMMUTABLE: 発行済みのリンクの内容は変更できません'
      using errcode = '42501';
  end if;

  if new.used_count is distinct from old.used_count then
    if v_ctx <> 'use' or new.used_count <> old.used_count + 1
       or new.status is distinct from old.status then
      raise exception 'TREEMERCE_REGISTRATION_LINK_WRITE_DENIED: 使用回数は申し込みの処理でのみ 1 ずつ増やせます'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if new.status is distinct from old.status
     or new.revoked_by is distinct from old.revoked_by
     or new.revoked_at is distinct from old.revoked_at then
    if v_ctx <> 'link_admin' or old.status <> 'active' or new.status <> 'revoked' then
      raise exception 'TREEMERCE_REGISTRATION_LINK_WRITE_DENIED: リンクの無効化は super_admin の処理でのみ (1回だけ) 行えます'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$fn$;

create trigger agent_registration_links_guard
  before insert or update or delete on public.agent_registration_links
  for each row execute function app.guard_agent_registration_links_write();

-- ============================================================================
-- 2. agent_applications: 申請の経路 (①紹介リンク / ②運営の登録リンク)
-- ============================================================================

create type public.agent_application_source as enum ('referral_link', 'admin_link');

-- 既存の申請はすべて ① (紹介リンク)
alter table public.agent_applications
  add column source public.agent_application_source not null default 'referral_link',
  add column registration_link_id uuid references public.agent_registration_links (id) on delete restrict;

-- ② は招待元なし。① の「招待元は必須」は経路ごとの CHECK 制約で引き続き強制する
alter table public.agent_applications alter column inviter_agent_id drop not null;

alter table public.agent_applications
  add constraint agent_applications_source_consistency check (
    (source = 'referral_link' and inviter_agent_id is not null and registration_link_id is null)
 or (source = 'admin_link'    and inviter_agent_id is null     and registration_link_id is not null)
  );

comment on column public.agent_applications.inviter_agent_id is
  '招待元。①紹介リンクではリンクの代理店 (必須)、②運営の登録リンクでは NULL (運営からの直接登録)。申請時点で固定・変更不可。承認時にそのまま agents.invited_by になる。';
comment on column public.agent_applications.source is
  '申請の経路。referral_link = 既存代理店の紹介リンク、admin_link = 運営の代理店登録リンク。変更不可。';

create index agent_applications_link_idx on public.agent_applications (registration_link_id)
  where registration_link_id is not null;

-- 0027 のガードに、経路とリンクの変更不可を加える (他は 0027 と同じ)
create or replace function app.guard_agent_applications_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.agent_application_ctx', true), '');
begin
  if tg_op = 'DELETE' then
    raise exception 'TREEMERCE_APPLICATION_DELETE_DENIED: 代理店申請は削除できません'
      using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    -- DB管理者の直接操作は session_user で判定する (理由は app.guard_agents_insert を参照)
    if v_ctx = 'apply' or (session_user = 'postgres' and v_ctx = '') then
      return new;
    end if;
    raise exception 'TREEMERCE_APPLICATION_WRITE_DENIED: 代理店申請は登録フォームからのみ作成できます'
      using errcode = '42501';
  end if;

  -- UPDATE
  if new.id is distinct from old.id
     or new.auth_user_id is distinct from old.auth_user_id
     or new.display_name is distinct from old.display_name
     or new.email is distinct from old.email
     or new.phone is distinct from old.phone
     or new.terms_version_id is distinct from old.terms_version_id
     or new.created_at is distinct from old.created_at then
    raise exception 'TREEMERCE_APPLICATION_IMMUTABLE: 申請内容は変更できません'
      using errcode = '42501';
  end if;

  -- 絶対原則2: 招待元・経路・リンクは申請時点で固定
  if new.inviter_agent_id is distinct from old.inviter_agent_id
     or new.source is distinct from old.source
     or new.registration_link_id is distinct from old.registration_link_id then
    raise exception 'TREEMERCE_APPLICATION_INVITER_IMMUTABLE: 申請の招待元・経路は変更できません'
      using errcode = '23514';
  end if;

  if new.status is distinct from old.status
     or new.reviewed_by is distinct from old.reviewed_by
     or new.reviewed_at is distinct from old.reviewed_at
     or new.created_agent_id is distinct from old.created_agent_id then
    if v_ctx <> 'review' then
      raise exception 'TREEMERCE_APPLICATION_WRITE_DENIED: 審査結果は運営の承認・却下処理でのみ記録できます'
        using errcode = '42501';
    end if;
    if old.status <> 'pending' or new.status = 'pending' then
      raise exception 'TREEMERCE_APPLICATION_NOT_PENDING: この申請は既に審査済みです'
        using errcode = '22023';
    end if;
  end if;

  return new;
end;
$fn$;

-- ============================================================================
-- 3. 申請の共通処理 (①②で同じ検証・重複の扱い・同意の記録・監査ログ)
-- ============================================================================

-- 申請者の検証。失敗時は例外 (呼び出し元の処理全体を止める)。
-- 順序は 0028 と同じ: 同意 → ログイン → 規約の現行の版 → 版の一致 → 代理店名 → メール (確認済み・一致)
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
    raise exception 'TREEMERCE_INVALID_INPUT: 代理店名は必須です' using errcode = '22023';
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

-- 申請と同意記録を作る。既に代理店 / 承認待ちの申請あり / 同時の申請 の場合は何も作らず NULL を返す
-- (呼び出し元は、作った場合も作らなかった場合も同じ中立メッセージを返す)。
create or replace function app.submit_agent_application(
  p_display_name         text,
  p_email                text,
  p_phone                text,
  p_source               public.agent_application_source,
  p_inviter_agent_id     uuid,
  p_registration_link_id uuid,
  p_terms_id             uuid,
  p_user_email           text,
  p_ip_address           text,
  p_user_agent           text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid    uuid := auth.uid();
  v_email  text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_phone  text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '');
  v_app_id uuid;
begin
  if v_uid is null then
    raise exception 'TREEMERCE_UNAUTHENTICATED: ログインが必要です' using errcode = '42501';
  end if;

  -- 絶対原則6・7: 既に代理店 / 承認待ちの申請あり → 何も作らない
  if exists (select 1 from public.agents a
             where a.auth_user_id = v_uid or a.email_normalized = v_email)
     or exists (select 1 from public.agent_applications ap
                where ap.status = 'pending'
                  and (ap.auth_user_id = v_uid
                       or ap.email_normalized = v_email
                       or (v_phone is not null and ap.phone_normalized = v_phone))) then
    return null;
  end if;

  begin
    perform set_config('app.agent_application_ctx', 'apply', true);

    insert into public.agent_applications
      (auth_user_id, display_name, email, phone, source, inviter_agent_id, registration_link_id,
       terms_version_id)
    values (v_uid, btrim(p_display_name), btrim(p_email), nullif(btrim(coalesce(p_phone, '')), ''),
            p_source, p_inviter_agent_id, p_registration_link_id, p_terms_id)
    returning id into v_app_id;

    insert into public.agent_terms_acceptances
      (terms_version_id, application_id, auth_user_id, accepted_email, ip_address, user_agent)
    values (p_terms_id, v_app_id, v_uid, p_user_email,
            nullif(btrim(coalesce(p_ip_address, '')), ''),
            nullif(left(btrim(coalesce(p_user_agent, '')), 1000), ''));

    perform set_config('app.agent_application_ctx', '', true);
  exception when unique_violation then
    -- 同時に申請された場合も、何も作らずに中立メッセージで受け付けた扱いにする
    perform set_config('app.agent_application_ctx', '', true);
    return null;
  end;

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, 'applicant', 'agent_application.submit', 'agent_applications', v_app_id,
          null,
          jsonb_build_object(
            'source',               p_source,
            'inviter_agent_id',     p_inviter_agent_id,
            'registration_link_id', p_registration_link_id,
            'terms_version_id',     p_terms_id
          ),
          null);

  return v_app_id;
end;
$fn$;

-- ============================================================================
-- 4. treemerce_register_member (①) を共通処理で作り直す (引数・応答・動きは 0028 と同じ)
-- ============================================================================
-- p_ip_address / p_user_agent はクライアント (画面) から送られた値を信用しない。
-- API ルートがサーバー側でリクエストヘッダーから取得した値だけを渡すこと。

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
  v_apply      boolean := coalesce(p_apply_agent, false);
  v_terms_id   uuid;
  v_user_email text;
  v_link       public.agents%rowtype;
  v_reg        jsonb;
  v_app_result text := null;
begin
  -- ---- 申請の事前検証 (失敗時は会員登録も含めて何も作らない) -------------------
  if v_apply then
    select c.o_terms_id, c.o_user_email into v_terms_id, v_user_email
    from app.check_agent_applicant(p_accept_agent_terms, p_agent_terms_version,
                                   p_agent_display_name, p_email) c;
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

  -- ---- 代理店申請 (①: 招待元 = リンクの代理店) ----------------------------------
  if v_apply then
    select * into v_link
    from public.agents
    where public_id = btrim(p_agent_public_id) and status = 'active';
    if not found then
      -- 招待元が確定できない申請は作らない (別の代理店や NULL で代用しない)
      raise exception 'TREEMERCE_AGENT_NOT_FOUND: 紹介リンクが無効です' using errcode = '22023';
    end if;

    perform app.submit_agent_application(
      p_agent_display_name, p_email, p_phone, 'referral_link', v_link.id, null,
      v_terms_id, v_user_email, p_ip_address, p_user_agent);
    v_app_result := 'received';
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
-- 5. 運営の代理店登録リンク (②)
-- ============================================================================

create or replace function app.registration_link_hash(p_token text)
returns text
language sql
stable
as $fn$
  select encode(sha256(convert_to(btrim(coalesce(p_token, '')), 'UTF8')), 'hex');
$fn$;

-- 有効期限・使用回数の上限・無効化から、いま使えるかを判定する
create or replace function app.registration_link_state(p_link public.agent_registration_links)
returns text
language sql
stable
as $fn$
  select case
    when p_link.status = 'revoked' then 'revoked'
    when p_link.expires_at is not null and p_link.expires_at <= now() then 'expired'
    when p_link.max_uses is not null and p_link.used_count >= p_link.max_uses then 'exhausted'
    else 'active'
  end;
$fn$;

-- 発行 (super_admin)。トークンは応答でこのときだけ返し、DB にはハッシュだけを保存する。
create or replace function public.treemerce_admin_create_registration_link(
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
  v_token text;
  v_link  public.agent_registration_links%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 代理店登録リンクの発行は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  if p_max_uses is not null and p_max_uses <= 0 then
    raise exception 'TREEMERCE_INVALID_INPUT: 使用回数の上限は 1 以上で指定してください' using errcode = '22023';
  end if;
  if p_expires_at is not null and p_expires_at <= now() then
    raise exception 'TREEMERCE_INVALID_INPUT: 有効期限は現在より後の日時を指定してください' using errcode = '22023';
  end if;
  if p_note is not null and char_length(btrim(p_note)) > 200 then
    raise exception 'TREEMERCE_INVALID_INPUT: メモは 200 文字以内で入力してください' using errcode = '22023';
  end if;

  -- 推測できない 64 桁の 16 進数 (gen_random_uuid 2 つ分)
  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');

  perform set_config('app.registration_link_ctx', 'link_admin', true);
  insert into public.agent_registration_links (token_sha256, note, max_uses, expires_at, created_by)
  values (app.registration_link_hash(v_token), nullif(btrim(coalesce(p_note, '')), ''),
          p_max_uses, p_expires_at, auth.uid())
  returning * into v_link;
  perform set_config('app.registration_link_ctx', '', true);

  -- トークンは監査ログにも残さない
  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (auth.uid(), coalesce(app.admin_role(), 'admin'), 'registration_link.create',
          'agent_registration_links', v_link.id, null,
          jsonb_build_object('note', v_link.note, 'max_uses', v_link.max_uses,
                             'expires_at', v_link.expires_at),
          null);

  return jsonb_build_object('id', v_link.id, 'token', v_token);
end;
$fn$;

create or replace function public.treemerce_admin_list_registration_links()
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

  -- トークン (のハッシュ) は返さない
  return coalesce(
    (select jsonb_agg(jsonb_build_object(
              'id',         l.id,
              'note',       l.note,
              'status',     l.status,
              'state',      app.registration_link_state(l),
              'max_uses',   l.max_uses,
              'used_count', l.used_count,
              'expires_at', l.expires_at,
              'created_at', l.created_at,
              'created_by', l.created_by,
              'revoked_at', l.revoked_at,
              'applications', jsonb_build_object(
                'pending',  (select count(*) from public.agent_applications ap
                             where ap.registration_link_id = l.id and ap.status = 'pending'),
                'approved', (select count(*) from public.agent_applications ap
                             where ap.registration_link_id = l.id and ap.status = 'approved'),
                'rejected', (select count(*) from public.agent_applications ap
                             where ap.registration_link_id = l.id and ap.status = 'rejected'))
            ) order by l.created_at desc)
     from public.agent_registration_links l),
    '[]'::jsonb
  );
end;
$fn$;

-- 無効化 (super_admin・理由必須)。以後の申し込みを受け付けない。既に届いた申請はそのまま審査できる。
create or replace function public.treemerce_admin_revoke_registration_link(
  p_link_id uuid,
  p_reason  text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_before public.agent_registration_links%rowtype;
  v_after  public.agent_registration_links%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 代理店登録リンクの無効化は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'TREEMERCE_REASON_REQUIRED: 無効化の理由は必須です' using errcode = '22023';
  end if;

  select * into v_before from public.agent_registration_links where id = p_link_id for update;
  if not found then
    raise exception 'TREEMERCE_REGISTRATION_LINK_NOT_FOUND: 代理店登録リンクが見つかりません' using errcode = '22023';
  end if;
  if v_before.status <> 'active' then
    raise exception 'TREEMERCE_REGISTRATION_LINK_NOT_ACTIVE: このリンクは既に無効化されています' using errcode = '22023';
  end if;

  perform set_config('app.registration_link_ctx', 'link_admin', true);
  update public.agent_registration_links
  set status = 'revoked', revoked_by = auth.uid(), revoked_at = clock_timestamp()
  where id = p_link_id
  returning * into v_after;
  perform set_config('app.registration_link_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (auth.uid(), coalesce(app.admin_role(), 'admin'), 'registration_link.revoke',
          'agent_registration_links', p_link_id,
          jsonb_build_object('status', v_before.status, 'used_count', v_before.used_count),
          jsonb_build_object('status', v_after.status, 'revoked_at', v_after.revoked_at),
          btrim(p_reason));

  return jsonb_build_object('id', v_after.id, 'status', v_after.status);
end;
$fn$;

-- リンクを開いたときの確認 (公開)。使えるかどうかと理由だけを返す。
create or replace function public.treemerce_resolve_registration_link(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_link  public.agent_registration_links%rowtype;
  v_state text;
begin
  select * into v_link from public.agent_registration_links
  where token_sha256 = app.registration_link_hash(p_token);
  if not found then
    return jsonb_build_object('valid', false, 'reason', 'not_found');
  end if;
  v_state := app.registration_link_state(v_link);
  if v_state <> 'active' then
    return jsonb_build_object('valid', false, 'reason', v_state);
  end if;
  return jsonb_build_object('valid', true);
end;
$fn$;

-- ② の申し込み。会員登録は行わない (customers・customer_assignments に触れない)。
-- 招待元はなし (運営からの直接登録) で申請時点に固定する。
-- p_ip_address / p_user_agent はクライアントの値を信用せず、API ルートがヘッダーから取得して渡す。
create or replace function public.treemerce_apply_agent_via_link(
  p_token               text,
  p_agent_display_name  text,
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

  v_app_id := app.submit_agent_application(
    p_agent_display_name, p_email, p_phone, 'admin_link', null, v_link.id,
    v_terms_id, v_user_email, p_ip_address, p_user_agent);

  -- 申請を作れたときだけ使用回数を数える (重複・既に代理店のときは数えない)
  if v_app_id is not null then
    perform set_config('app.registration_link_ctx', 'use', true);
    update public.agent_registration_links set used_count = used_count + 1 where id = v_link.id;
    perform set_config('app.registration_link_ctx', '', true);
  end if;

  -- 申請ID・リンクの情報は返さない
  return jsonb_build_object(
    'application_status',  'received',
    'application_message', app.agent_application_received_message()
  );
end;
$fn$;

-- ============================================================================
-- 6. 審査の RPC を経路に対応させる (承認は今までどおり招待元を受け取らない)
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
    'source',           p_app.source,
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
    'registration_link', (select jsonb_build_object('id', l.id, 'note', l.note,
                                                    'state', app.registration_link_state(l))
                          from public.agent_registration_links l
                          where l.id = p_app.registration_link_id),
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

-- 承認: 申請に固定された招待元 (② は NULL) をそのまま app.create_agent() に渡す。
-- リンクがあとから無効化・期限切れになっても、既に届いた申請は審査できる。
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
          jsonb_build_object('status', v_before.status, 'source', v_before.source,
                             'inviter_agent_id', v_before.inviter_agent_id,
                             'registration_link_id', v_before.registration_link_id),
          jsonb_build_object('status', v_after.status, 'source', v_after.source,
                             'inviter_agent_id', v_after.inviter_agent_id,
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

-- ============================================================================
-- 7. 権限
-- ============================================================================

revoke all on public.agent_registration_links from anon, authenticated;
alter table public.agent_registration_links enable row level security;

revoke all on function app.guard_agent_registration_links_write() from public, anon, authenticated;
revoke all on function app.guard_agent_applications_write()       from public, anon, authenticated;
revoke all on function app.check_agent_applicant(boolean, text, text, text)
  from public, anon, authenticated;
revoke all on function app.submit_agent_application(
  text, text, text, public.agent_application_source, uuid, uuid, uuid, text, text, text)
  from public, anon, authenticated;
revoke all on function app.registration_link_hash(text) from public, anon, authenticated;
revoke all on function app.registration_link_state(public.agent_registration_links)
  from public, anon, authenticated;
revoke all on function app.agent_application_json(public.agent_applications)
  from public, anon, authenticated;

revoke all on function public.treemerce_admin_create_registration_link(text, integer, timestamptz)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_list_registration_links() from public, anon, authenticated;
revoke all on function public.treemerce_admin_revoke_registration_link(uuid, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_resolve_registration_link(text) from public, anon, authenticated;
revoke all on function public.treemerce_apply_agent_via_link(
  text, text, text, text, boolean, text, text, text) from public, anon, authenticated;

-- 公開 (申し込みは関数内でログインを必須にする)
grant execute on function public.treemerce_resolve_registration_link(text) to anon, authenticated;
grant execute on function public.treemerce_apply_agent_via_link(
  text, text, text, text, boolean, text, text, text) to anon, authenticated;

-- super_admin 専用 (関数内部で app.is_super_admin() を必須チェック)
grant execute on function public.treemerce_admin_create_registration_link(text, integer, timestamptz)
  to authenticated;
grant execute on function public.treemerce_admin_list_registration_links() to authenticated;
grant execute on function public.treemerce_admin_revoke_registration_link(uuid, text) to authenticated;

commit;
