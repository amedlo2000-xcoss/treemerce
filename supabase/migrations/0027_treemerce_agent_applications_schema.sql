-- ============================================================================
-- TREEMERCE : 0027_treemerce_agent_applications_schema.sql
-- 代理店申請・代理店規約の同意記録 (スキーマ)
-- ----------------------------------------------------------------------------
-- 紹介リンク (/register/{公開ID}) の登録フォームを1つにまとめ、
--   ・登録した人は全員「会員 (customers)」
--   ・「代理店登録も申し込む」「代理店規約に同意する」の両方にチェックした人だけ
--     代理店申請 (agent_applications) を作る
--   ・super_admin が承認したときだけ代理店 (agents) を作る
-- という流れにする。
--
-- 絶対原則との対応
--   1. 申請は agents とも customers とも別テーブル。customer_id は持たない。
--      人とのつながりは auth_user_id のみ。
--   2. 招待元 (inviter_agent_id) は申請時点で「申請に使われたリンクの代理店」に固定。
--      申請の招待元は変更不可 (トリガ)。agents.invited_by は作成時にのみ設定でき、
--      作成後は NULL → 値 を含めて一切変更できない (enforce_invited_by_immutable を強化)。
--   3. 会員の担当 (customer_assignments) とは独立。どちらも他方を参照・変更しない。
--   6. 却下理由を保存する列は作らない。理由は admin_audit_logs にだけ残す。
--
-- 代理店の行を作れるのは app.create_agent() (0028) だけ。agents への INSERT は
-- 認可コンテキスト (app.agent_create_ctx) 外では拒否する。
--
-- 番号 0026 は旧 treemerce_admin_upsert_product の削除用に予約しているため空けてある。
-- ============================================================================

begin;

-- ============================================================================
-- 1. agents: 作成経路の限定 / invited_by を作成時のみに
-- ============================================================================

-- 絶対原則2: 招待元は代理店の作成時にのみ決まる。作成後は「再設定」だけでなく
-- 「未設定からの設定」も拒否する (招待元を後から付ける経路を残さない)。
create or replace function app.enforce_invited_by_immutable()
returns trigger
language plpgsql
as $fn$
begin
  if new.invited_by is distinct from old.invited_by then
    if old.invited_by is not null then
      raise exception
        'TREEMERCE_INVITED_BY_ALREADY_SET: agent % already has an inviter; re-assignment is forbidden',
        old.id
        using errcode = '23514';
    end if;
    raise exception
      'TREEMERCE_INVITED_BY_CREATE_ONLY: 招待元は代理店の作成時にのみ設定できます'
      using errcode = '23514';
  end if;
  return new;
end;
$fn$;

-- 代理店の作成は app.create_agent() が張るコンテキスト内でのみ許可する。
-- authenticated はそもそも agents への INSERT 権限を持たないが、万一 GRANT が
-- 復活してもこのトリガで止まる。
create or replace function app.guard_agents_insert()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.agent_create_ctx', true), '');
begin
  if v_ctx = 'create' then
    return new;
  end if;

  -- DB管理者(postgres)による直接操作 = マイグレーション/リセット/障害復旧の経路として明示的に許可。
  -- superuser はトリガ自体を無効化できるため、これは防御の弱体化ではない。
  -- current_user ではなく session_user で判定する: SECURITY DEFINER 関数 (postgres 所有) の
  -- 中では current_user が postgres になるため、current_user だとコンテキストを張らない
  -- 他の関数からの INSERT まで通ってしまう。PostgREST 経由の session_user は authenticator。
  if session_user = 'postgres' and v_ctx = '' then
    return new;
  end if;

  raise exception
    'TREEMERCE_AGENT_CREATE_DENIED: 代理店は運営の承認処理でのみ作成できます'
    using errcode = '42501';
end;
$fn$;

create trigger agents_guard_insert
  before insert on public.agents
  for each row execute function app.guard_agents_insert();

-- ============================================================================
-- 2. agent_terms_versions (代理店規約の版)
-- ============================================================================
-- 版の公開は DB管理者が SQL で行う (RPC は設けない)。
--   begin;
--   update public.agent_terms_versions set is_current = false where is_current;
--   insert into public.agent_terms_versions (version, title, body, is_current)
--   values ('1.0', '代理店規約', '<本文>', true);
--   commit;
-- 現行の版が無い間は、申請の RPC が TREEMERCE_TERMS_NOT_AVAILABLE で拒否する。

create table public.agent_terms_versions (
  id           uuid primary key default gen_random_uuid(),
  version      text not null unique check (btrim(version) <> ''),
  title        text not null check (btrim(title) <> ''),
  body         text not null check (btrim(body) <> ''),
  -- 同意した本文を後から特定できるよう、本文のハッシュを DB 側で算出する (INSERT トリガで設定。
  -- convert_to は STABLE なので生成列には使えない)
  body_sha256  text not null,
  published_at timestamptz not null default now(),
  is_current   boolean not null default false,
  created_at   timestamptz not null default clock_timestamp()
);

comment on table public.agent_terms_versions is
  '代理店規約の版。公開後は本文・版番号を変更できない。現行の版は常に高々1つ。';

create unique index agent_terms_versions_one_current
  on public.agent_terms_versions ((true)) where is_current;

-- 公開済みの版は内容を変更・削除できない。変更できるのは「現行かどうか」だけ。
create or replace function app.guard_agent_terms_versions_write()
returns trigger
language plpgsql
as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'TREEMERCE_TERMS_DELETE_DENIED: 代理店規約の版は削除できません'
      using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    -- 入力された値は使わず、必ず本文から算出する
    new.body_sha256 := encode(sha256(convert_to(new.body, 'UTF8')), 'hex');
    return new;
  end if;

  if new.id is distinct from old.id
     or new.version is distinct from old.version
     or new.title is distinct from old.title
     or new.body is distinct from old.body
     or new.body_sha256 is distinct from old.body_sha256
     or new.published_at is distinct from old.published_at
     or new.created_at is distinct from old.created_at then
    raise exception 'TREEMERCE_TERMS_IMMUTABLE: 公開済みの代理店規約は変更できません。新しい版を追加してください'
      using errcode = '42501';
  end if;

  return new;
end;
$fn$;

create trigger agent_terms_versions_guard
  before insert or update or delete on public.agent_terms_versions
  for each row execute function app.guard_agent_terms_versions_write();

-- ============================================================================
-- 3. agent_applications (代理店申請)
-- ============================================================================

create type public.agent_application_status as enum ('pending', 'approved', 'rejected');

create table public.agent_applications (
  id               uuid primary key default gen_random_uuid(),
  -- 申請者のログインアカウント。customers / agents の行は参照しない (絶対原則1)
  auth_user_id     uuid not null references auth.users (id) on delete restrict,
  display_name     text not null check (btrim(display_name) <> ''),
  email            text not null check (btrim(email) <> ''),
  email_normalized text generated always as (nullif(lower(btrim(email)), '')) stored,
  phone            text,
  phone_normalized text generated always as
                     (nullif(regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g'), '')) stored,

  -- 絶対原則2・3: 申請に使われたリンクの代理店。申請時点で固定し、変更できない。
  -- 会員の担当 (customer_assignments) から導出しない。
  inviter_agent_id uuid not null references public.agents (id) on delete restrict,

  terms_version_id uuid not null references public.agent_terms_versions (id) on delete restrict,
  status           public.agent_application_status not null default 'pending',

  -- 審査の記録。却下理由はここには持たず admin_audit_logs にだけ残す (本人に出さないため)
  reviewed_by      uuid,
  reviewed_at      timestamptz,
  created_agent_id uuid references public.agents (id) on delete restrict,

  created_at       timestamptz not null default clock_timestamp(),
  updated_at       timestamptz not null default now(),

  constraint agent_applications_review_consistency check (
    (status = 'pending'  and reviewed_at is null and reviewed_by is null and created_agent_id is null)
 or (status = 'approved' and reviewed_at is not null and created_agent_id is not null)
 or (status = 'rejected' and reviewed_at is not null and created_agent_id is null)
  )
);

comment on table public.agent_applications is
  '代理店申請。承認されるまで agents の行は作らない。却下理由は admin_audit_logs にのみ保存。';
comment on column public.agent_applications.inviter_agent_id is
  '申請に使われたリンクの代理店。申請時点で固定・変更不可。承認時にそのまま agents.invited_by になる。';

-- 承認待ちの申請は 1アカウント / 1メールアドレス / 1電話番号 につき1件まで (絶対原則7)。
-- 却下・承認済みの申請は対象外なので、却下後の再申請は新しい申請として受け付けられる。
create unique index agent_applications_one_pending_per_user
  on public.agent_applications (auth_user_id) where status = 'pending';
create unique index agent_applications_one_pending_per_email
  on public.agent_applications (email_normalized) where status = 'pending';
create unique index agent_applications_one_pending_per_phone
  on public.agent_applications (phone_normalized)
  where status = 'pending' and phone_normalized is not null;

create index agent_applications_status_idx on public.agent_applications (status, created_at desc);
create index agent_applications_user_idx on public.agent_applications (auth_user_id, created_at desc);
create index agent_applications_inviter_idx on public.agent_applications (inviter_agent_id);

create trigger agent_applications_touch_updated_at
  before update on public.agent_applications
  for each row execute function app.touch_updated_at();

-- 申請内容と招待元は変更不可。状態は pending からの1回だけ、審査処理の中でのみ変更できる。
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

  -- 絶対原則2: 招待元は申請時点で固定
  if new.inviter_agent_id is distinct from old.inviter_agent_id then
    raise exception 'TREEMERCE_APPLICATION_INVITER_IMMUTABLE: 申請の招待元は変更できません'
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

create trigger agent_applications_guard
  before insert or update or delete on public.agent_applications
  for each row execute function app.guard_agent_applications_write();

-- ============================================================================
-- 4. agent_terms_acceptances (代理店規約への同意 / 追記専用)
-- ============================================================================

create table public.agent_terms_acceptances (
  id               uuid primary key default gen_random_uuid(),
  terms_version_id uuid not null references public.agent_terms_versions (id) on delete restrict,
  application_id   uuid not null unique references public.agent_applications (id) on delete restrict,
  -- 同意の記録はアカウント削除後も残すため、auth.users への外部キーは張らずに値として保存する
  auth_user_id     uuid not null,
  accepted_email   text not null,
  -- 同意日時はサーバー側で記録する (クライアントの時刻は使わない)
  accepted_at      timestamptz not null default clock_timestamp(),
  ip_address       text,
  user_agent       text
);

comment on table public.agent_terms_acceptances is
  '代理店規約への同意記録。追記専用 (変更・削除不可)。どの版の本文に同意したかは terms_version_id で特定する。';

create index agent_terms_acceptances_user_idx
  on public.agent_terms_acceptances (auth_user_id, accepted_at desc);

create or replace function app.guard_agent_terms_acceptances_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.agent_application_ctx', true), '');
begin
  if tg_op <> 'INSERT' then
    raise exception 'TREEMERCE_TERMS_ACCEPTANCE_APPEND_ONLY: 規約の同意記録は変更・削除できません'
      using errcode = '42501';
  end if;
  -- DB管理者の直接操作は session_user で判定する (理由は app.guard_agents_insert を参照)
  if v_ctx = 'apply' or (session_user = 'postgres' and v_ctx = '') then
    return new;
  end if;
  raise exception 'TREEMERCE_TERMS_ACCEPTANCE_WRITE_DENIED: 規約の同意は登録フォームからのみ記録できます'
    using errcode = '42501';
end;
$fn$;

create trigger agent_terms_acceptances_guard
  before insert or update or delete on public.agent_terms_acceptances
  for each row execute function app.guard_agent_terms_acceptances_write();

-- ============================================================================
-- 5. 権限
-- ============================================================================
-- 3テーブルとも anon / authenticated には一切の権限を与えない (fail-closed)。
-- 読み書きは 0028 の SECURITY DEFINER RPC からのみ行う。
-- 申請者本人・リンクの代理店を含む一般代理店は、テーブルを直接読めない。

revoke all on public.agent_terms_versions    from anon, authenticated;
revoke all on public.agent_applications      from anon, authenticated;
revoke all on public.agent_terms_acceptances from anon, authenticated;

alter table public.agent_terms_versions    enable row level security;
alter table public.agent_applications      enable row level security;
alter table public.agent_terms_acceptances enable row level security;

revoke all on function app.enforce_invited_by_immutable()        from public, anon, authenticated;
revoke all on function app.guard_agents_insert()                 from public, anon, authenticated;
revoke all on function app.guard_agent_terms_versions_write()    from public, anon, authenticated;
revoke all on function app.guard_agent_applications_write()      from public, anon, authenticated;
revoke all on function app.guard_agent_terms_acceptances_write() from public, anon, authenticated;

commit;
