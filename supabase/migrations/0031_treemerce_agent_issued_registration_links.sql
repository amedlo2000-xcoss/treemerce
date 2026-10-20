-- ============================================================================
-- TREEMERCE : 0031_treemerce_agent_issued_registration_links.sql
-- 代理店も発行できる代理店登録リンク / 紹介者 (紐づけ先) の明示
-- ----------------------------------------------------------------------------
-- 代理店登録リンク (/join/{トークン}) は、運営と代理店のどちらも発行できる。
--   ・運営 (super_admin) が発行したリンク : 紐づけ先なし (運営直下)。経路 admin_link
--   ・代理店が発行したリンク             : 紐づけ先 = 発行した代理店。経路 agent_link
-- どちらも同じ申し込みフォームを使い、1回の送信でアカウント作成と申し込みを行う。
-- アカウント (メール確認済み) は API ルートがサーバー側で作成し、そのアカウントの権限で
-- treemerce_apply_agent_via_link() を呼ぶ (申請の作成は今までどおり DB の関数だけが行う)。
-- 代理店になるのは運営の承認 (app.create_agent()) のときだけ。
--
-- 絶対原則
--   1/3/4. customers・customer_assignments には一切触れない。
--   2.     紹介者 (inviter_agent_id) は申し込みに使われたリンクで決まり、申請時点で固定。
--          代理店のリンクでは「招待元 = リンクの発行代理店」をトリガで強制し、
--          経路ごとの招待元の有無は CHECK 制約で強制する。承認時に変更できない。
--          リンクの発行代理店 (issuer_agent_id) も発行後は変更できない。
--          発行した代理店が稼働中でないリンクでは申し込めない。
--   5.     代理店は自分が発行したリンクだけを一覧・無効化できる。申し込みの内容・連絡先・
--          他の代理店のリンクは返さない (申請テーブルは今までどおり直接読めない)。
--   6/7.   同じメールアドレス・電話番号の人が既にいる場合も、新規と同じ中立メッセージ。
--   8.     リンクの発行・無効化 (運営・代理店とも)、申し込み、承認・却下は admin_audit_logs に残す。
-- ガードの「DB管理者の直接操作」の例外は session_user で判定する (0029)。
-- ============================================================================

begin;

-- ============================================================================
-- 1. 申請の経路に「代理店の登録リンク」を追加
-- ============================================================================
-- 追加した列挙値はこのトランザクション内では値として使えないため、
-- このファイルの中では source を text にして比較する (関数本体は実行時に解釈されるため問題ない)。

alter type public.agent_application_source add value if not exists 'agent_link';

-- ============================================================================
-- 2. agent_registration_links: 発行した代理店 (紐づけ先)
-- ============================================================================

alter table public.agent_registration_links
  add column issuer_agent_id uuid references public.agents (id) on delete restrict;

comment on column public.agent_registration_links.issuer_agent_id is
  'リンクを発行した代理店 (= 申し込んだ人の紹介者・招待元)。NULL は運営が発行したリンク (運営直下)。発行後は変更不可。';
comment on table public.agent_registration_links is
  '代理店登録リンク。運営 (issuer_agent_id NULL) または代理店が発行する。トークンはハッシュのみ保存。';

create index agent_registration_links_issuer_idx on public.agent_registration_links (issuer_agent_id, created_at desc)
  where issuer_agent_id is not null;

-- 0030 のガードに、発行代理店の変更不可と、代理店による発行・無効化 (自分のリンクだけ) を加える
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
    -- 運営の発行は紐づけ先なし、代理店の発行は紐づけ先 = 発行した本人 (稼働中) に限る
    if v_ctx = 'link_admin' and new.issuer_agent_id is null then
      return new;
    end if;
    if v_ctx = 'link_agent' and new.issuer_agent_id is not null
       and new.issuer_agent_id = app.current_agent_id() then
      return new;
    end if;
    -- DB管理者の直接操作は session_user で判定する (0029)
    if session_user = 'postgres' and v_ctx = '' then
      return new;
    end if;
    raise exception 'TREEMERCE_REGISTRATION_LINK_WRITE_DENIED: 代理店登録リンクは発行処理でのみ作成できます'
      using errcode = '42501';
  end if;

  -- UPDATE
  if new.id is distinct from old.id
     or new.token_sha256 is distinct from old.token_sha256
     or new.note is distinct from old.note
     or new.max_uses is distinct from old.max_uses
     or new.expires_at is distinct from old.expires_at
     or new.issuer_agent_id is distinct from old.issuer_agent_id
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
    -- 運営はすべてのリンクを、代理店は自分が発行したリンクだけを無効化できる (1回だけ)
    if not (v_ctx = 'link_admin'
            or (v_ctx = 'link_agent' and old.issuer_agent_id is not null
                and old.issuer_agent_id = app.current_agent_id()))
       or old.status <> 'active' or new.status <> 'revoked' then
      raise exception 'TREEMERCE_REGISTRATION_LINK_WRITE_DENIED: リンクの無効化は発行者または super_admin の処理でのみ (1回だけ) 行えます'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$fn$;

-- いま使えるか。発行した代理店が稼働中でないリンクも使えない (issuer_inactive)
create or replace function app.registration_link_state(p_link public.agent_registration_links)
returns text
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select case
    when p_link.status = 'revoked' then 'revoked'
    when p_link.issuer_agent_id is not null
         and not exists (select 1 from public.agents a
                         where a.id = p_link.issuer_agent_id and a.status = 'active') then 'issuer_inactive'
    when p_link.expires_at is not null and p_link.expires_at <= now() then 'expired'
    when p_link.max_uses is not null and p_link.used_count >= p_link.max_uses then 'exhausted'
    else 'active'
  end;
$fn$;

-- ============================================================================
-- 3. agent_applications: 申込者の氏名 / 経路と紹介者の整合
-- ============================================================================

alter table public.agent_applications
  add column applicant_name text check (applicant_name is null or btrim(applicant_name) <> '');

comment on column public.agent_applications.applicant_name is
  '申込者の氏名 (代理店登録リンクからの申し込みで必須)。変更不可。照合には使わない (絶対原則7)。';

alter table public.agent_applications drop constraint agent_applications_source_consistency;
alter table public.agent_applications
  add constraint agent_applications_source_consistency check (
    (source::text = 'referral_link' and inviter_agent_id is not null and registration_link_id is null)
 or (source::text = 'admin_link'    and inviter_agent_id is null     and registration_link_id is not null)
 or (source::text = 'agent_link'    and inviter_agent_id is not null and registration_link_id is not null)
  );

comment on column public.agent_applications.inviter_agent_id is
  '紹介者 (招待元)。①紹介リンクと代理店の登録リンクではリンクの代理店 (必須)、運営の登録リンクでは NULL (運営直下)。申請時点で固定・変更不可。承認時にそのまま agents.invited_by になる。';
comment on column public.agent_applications.source is
  '申請の経路。referral_link = 既存代理店の紹介リンク、admin_link = 運営の代理店登録リンク、agent_link = 代理店が発行した代理店登録リンク。変更不可。';

-- 0030 のガードに、リンクと紹介者の整合 (全員に適用) と氏名の変更不可を加える
create or replace function app.guard_agent_applications_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx    text := coalesce(current_setting('app.agent_application_ctx', true), '');
  v_issuer uuid;
  v_source text;
begin
  if tg_op = 'DELETE' then
    raise exception 'TREEMERCE_APPLICATION_DELETE_DENIED: 代理店申請は削除できません'
      using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    -- 絶対原則2: リンクからの申請の紹介者は、そのリンクの発行代理店 (運営のリンクは NULL) と必ず一致する。
    -- DB管理者の直接操作でも例外にしない。
    if new.registration_link_id is not null then
      select l.issuer_agent_id into v_issuer
      from public.agent_registration_links l where l.id = new.registration_link_id;
      v_source := case when v_issuer is null then 'admin_link' else 'agent_link' end;
      if new.inviter_agent_id is distinct from v_issuer or new.source::text <> v_source then
        raise exception 'TREEMERCE_APPLICATION_INVITER_MISMATCH: 申請の紹介者はリンクの発行元と一致しなければなりません'
          using errcode = '23514';
      end if;
    end if;

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
     or new.applicant_name is distinct from old.applicant_name
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
-- 4. 申請の共通処理に氏名を追加 (0030 の引数の末尾に追加。① は NULL のまま)
-- ============================================================================

drop function app.submit_agent_application(
  text, text, text, public.agent_application_source, uuid, uuid, uuid, text, text, text);

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
  p_user_agent           text,
  p_applicant_name       text default null
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
      (auth_user_id, display_name, applicant_name, email, phone, source, inviter_agent_id,
       registration_link_id, terms_version_id)
    values (v_uid, btrim(p_display_name), nullif(btrim(coalesce(p_applicant_name, '')), ''),
            btrim(p_email), nullif(btrim(coalesce(p_phone, '')), ''),
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
-- 5. リンクの発行・無効化の共通処理 (運営・代理店とも監査ログに残す)
-- ============================================================================

-- p_issuer_agent_id が NULL なら運営の発行 (呼び出し元で super_admin を確認済み)、
-- 値があればその代理店の発行 (呼び出し元で本人の稼働中の代理店であることを確認済み)。
create or replace function app.issue_registration_link(
  p_issuer_agent_id uuid,
  p_note            text,
  p_max_uses        integer,
  p_expires_at      timestamptz,
  p_actor_role      text
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

  perform set_config('app.registration_link_ctx',
                     case when p_issuer_agent_id is null then 'link_admin' else 'link_agent' end, true);
  insert into public.agent_registration_links
    (token_sha256, note, max_uses, expires_at, issuer_agent_id, created_by)
  values (app.registration_link_hash(v_token), nullif(btrim(coalesce(p_note, '')), ''),
          p_max_uses, p_expires_at, p_issuer_agent_id, auth.uid())
  returning * into v_link;
  perform set_config('app.registration_link_ctx', '', true);

  -- トークンは監査ログにも残さない
  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (auth.uid(), p_actor_role, 'registration_link.create',
          'agent_registration_links', v_link.id, null,
          jsonb_build_object('issuer_agent_id', v_link.issuer_agent_id, 'note', v_link.note,
                             'max_uses', v_link.max_uses, 'expires_at', v_link.expires_at),
          null);

  return jsonb_build_object('id', v_link.id, 'token', v_token);
end;
$fn$;

-- p_issuer_agent_id が NULL なら運営の無効化 (どのリンクでも可)、値があればその代理店のリンクだけ。
create or replace function app.revoke_registration_link(
  p_link_id         uuid,
  p_reason          text,
  p_issuer_agent_id uuid,
  p_actor_role      text
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
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'TREEMERCE_REASON_REQUIRED: 無効化の理由は必須です' using errcode = '22023';
  end if;

  select * into v_before from public.agent_registration_links where id = p_link_id for update;
  -- 他の代理店のリンクは「見つからない」として扱う (存在も開示しない)
  if not found or (p_issuer_agent_id is not null and v_before.issuer_agent_id is distinct from p_issuer_agent_id) then
    raise exception 'TREEMERCE_REGISTRATION_LINK_NOT_FOUND: 代理店登録リンクが見つかりません' using errcode = '22023';
  end if;
  if v_before.status <> 'active' then
    raise exception 'TREEMERCE_REGISTRATION_LINK_NOT_ACTIVE: このリンクは既に無効化されています' using errcode = '22023';
  end if;

  perform set_config('app.registration_link_ctx',
                     case when p_issuer_agent_id is null then 'link_admin' else 'link_agent' end, true);
  update public.agent_registration_links
  set status = 'revoked', revoked_by = auth.uid(), revoked_at = clock_timestamp()
  where id = p_link_id
  returning * into v_after;
  perform set_config('app.registration_link_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (auth.uid(), p_actor_role, 'registration_link.revoke',
          'agent_registration_links', p_link_id,
          jsonb_build_object('status', v_before.status, 'used_count', v_before.used_count,
                             'issuer_agent_id', v_before.issuer_agent_id),
          jsonb_build_object('status', v_after.status, 'revoked_at', v_after.revoked_at),
          btrim(p_reason));

  return jsonb_build_object('id', v_after.id, 'status', v_after.status);
end;
$fn$;

-- ============================================================================
-- 6. 運営 (super_admin) のリンク管理 (引数・権限は 0030 と同じ。一覧は代理店のリンクも含む)
-- ============================================================================

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
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 代理店登録リンクの発行は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  -- 運営のリンクは紐づけ先なし (運営直下)
  return app.issue_registration_link(null, p_note, p_max_uses, p_expires_at,
                                     coalesce(app.admin_role(), 'admin'));
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
              'issuer', (select jsonb_build_object('id', a.id, 'public_id', a.public_id,
                                                   'display_name', a.display_name, 'status', a.status)
                         from public.agents a where a.id = l.issuer_agent_id),
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

-- 運営はどのリンクでも無効化できる (理由必須)。既に届いた申請はそのまま審査できる。
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
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 代理店登録リンクの無効化は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  return app.revoke_registration_link(p_link_id, p_reason, null, coalesce(app.admin_role(), 'admin'));
end;
$fn$;

-- ============================================================================
-- 7. 代理店本人のリンク管理 (自分が発行したリンクだけ)
-- ============================================================================

create or replace function public.treemerce_create_my_registration_link(
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
begin
  -- 稼働中の代理店だけ (未ログイン・代理店でない・停止中は不可)
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 代理店登録リンクは稼働中の代理店のみ発行できます'
      using errcode = '42501';
  end if;
  -- 紐づけ先は発行した本人 (引数で受け取らない)
  return app.issue_registration_link(v_self, p_note, p_max_uses, p_expires_at, 'agent');
end;
$fn$;

-- 自分が発行したリンクの一覧。申し込んだ人の情報 (氏名・連絡先・申請の状態) は返さない (絶対原則5)。
create or replace function public.treemerce_my_registration_links()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_self uuid := app.current_agent_id();
begin
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店のみ実行できます' using errcode = '42501';
  end if;

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
              'revoked_at', l.revoked_at
            ) order by l.created_at desc)
     from public.agent_registration_links l
     where l.issuer_agent_id = v_self),
    '[]'::jsonb
  );
end;
$fn$;

create or replace function public.treemerce_revoke_my_registration_link(
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
  v_self uuid := app.current_agent_id();
begin
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店のみ実行できます' using errcode = '42501';
  end if;
  return app.revoke_registration_link(p_link_id, p_reason, v_self, 'agent');
end;
$fn$;

-- ============================================================================
-- 8. リンクを開いたときの確認 (公開): 使えるかどうかと紹介者だけを返す
-- ============================================================================
-- 紹介者は代理店名と代理店ID (公開ID) だけ。運営のリンクは inviter = null (運営からの直接登録)。
-- 発行した代理店が稼働中でないリンクは、理由を伏せて unavailable とする。

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
  if v_state = 'issuer_inactive' then
    return jsonb_build_object('valid', false, 'reason', 'unavailable');
  end if;
  if v_state <> 'active' then
    return jsonb_build_object('valid', false, 'reason', v_state);
  end if;
  return jsonb_build_object(
    'valid',   true,
    'inviter', (select jsonb_build_object('public_id', a.public_id, 'display_name', a.display_name)
                from public.agents a where a.id = v_link.issuer_agent_id)
  );
end;
$fn$;

-- ============================================================================
-- 9. 申し込み (運営・代理店のリンク共通)
-- ============================================================================
-- 呼び出し元は API ルート。API ルートがメール確認済みのアカウントをサーバー側で作成し、
-- そのアカウントでログインした権限でこの関数を呼ぶ。会員登録は行わない。
-- 紹介者はリンクの発行元 (運営のリンクは NULL) で申請時点に固定する。引数では受け取らない。
-- p_ip_address / p_user_agent はクライアントの値を信用せず、API ルートがヘッダーから取得して渡す。

drop function public.treemerce_apply_agent_via_link(text, text, text, text, boolean, text, text, text);

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
    raise exception 'TREEMERCE_INVALID_INPUT: 代理店名・氏名は 100 文字以内で入力してください' using errcode = '22023';
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

-- ============================================================================
-- 10. 審査の表示に氏名・リンクの発行元を追加 (承認・却下の処理は 0030 のまま)
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
    'applicant_name',   p_app.applicant_name,
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
                                                    'issuer_agent_id', l.issuer_agent_id,
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

-- ============================================================================
-- 11. 権限
-- ============================================================================

revoke all on function app.guard_agent_registration_links_write() from public, anon, authenticated;
revoke all on function app.guard_agent_applications_write()       from public, anon, authenticated;
revoke all on function app.registration_link_state(public.agent_registration_links)
  from public, anon, authenticated;
revoke all on function app.submit_agent_application(
  text, text, text, public.agent_application_source, uuid, uuid, uuid, text, text, text, text)
  from public, anon, authenticated;
revoke all on function app.issue_registration_link(uuid, text, integer, timestamptz, text)
  from public, anon, authenticated;
revoke all on function app.revoke_registration_link(uuid, text, uuid, text)
  from public, anon, authenticated;
revoke all on function app.agent_application_json(public.agent_applications)
  from public, anon, authenticated;

revoke all on function public.treemerce_create_my_registration_link(text, integer, timestamptz)
  from public, anon, authenticated;
revoke all on function public.treemerce_my_registration_links() from public, anon, authenticated;
revoke all on function public.treemerce_revoke_my_registration_link(uuid, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_apply_agent_via_link(
  text, text, text, text, text, boolean, text, text, text) from public, anon, authenticated;

-- 申し込み: API ルートが作成したアカウントの権限で呼ぶ (関数内でログイン・メール確認済みを必須にする)
grant execute on function public.treemerce_apply_agent_via_link(
  text, text, text, text, text, boolean, text, text, text) to authenticated;

-- 代理店本人 (関数内部で稼働中の代理店であることを必須チェック)
grant execute on function public.treemerce_create_my_registration_link(text, integer, timestamptz)
  to authenticated;
grant execute on function public.treemerce_my_registration_links() to authenticated;
grant execute on function public.treemerce_revoke_my_registration_link(uuid, text) to authenticated;

commit;
