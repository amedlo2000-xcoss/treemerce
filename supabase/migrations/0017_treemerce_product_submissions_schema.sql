-- ============================================================================
-- TREEMERCE : 0017_treemerce_product_submissions_schema.sql
-- 商品の持込み申請 (P3: テーブル / 状態遷移 / 書込みガード / 持込み元 / 公開ガード /
--                     公開の監査 / 非公開画像バケット / RLS・GRANT)
-- ----------------------------------------------------------------------------
--   product_submissions        : 代理店からの持込み申請。生産者の連絡先を含む。
--   product_submission_events  : 申請の状態変更履歴 (追記専用、申請時点の内容のスナップショット付き)
--   product_submission_images  : 申請画像 (最大 5 枚)。実体は非公開バケット product-submission-images
--   product_sources            : 商品の持込み元 (products と 1:1)。作成後は誰にも変更・削除できない。
--
-- ステータス: draft (下書き) → submitted (申請中) → approved (承認) / returned (差し戻し・理由必須) /
--             rejected (却下・理由必須)。returned は本人が修正して再申請できる。
--             draft / returned は本人が withdrawn (取り下げ) にできる。申請は削除しない。
--             approved / rejected / withdrawn は終端 (以後どの列も変更できない)。
--
-- 書込みのコンテキスト (GUC app.submission_ctx):
--   'submission_agent'  : 本人の作成・保存・申請・取り下げ・画像の追加/削除 (0018 の代理店 RPC)
--   'submission_review' : super_admin の承認・差し戻し・却下と、承認時の持込み元の記録 (0018)
--   承認・差し戻し・却下への遷移は 'submission_review' の中でしか起こせない
--   → 代理店は構造的に承認できない。
--   DB 管理者 (postgres) のコンテキスト外の直接操作は、内容の修正のみ許可する
--   (状態の変更・削除・終端の申請の変更はできない)。
--
-- 公開ガード (products):
--   持込み元 (product_sources) がある商品は、ひも付く申請が approved で、実行者が super_admin
--   (app.is_super_admin()) で、生産者が有効かつ仮の生産者でない場合にのみ公開 (is_published を
--   true に) できる。postgres の直接操作でも例外にしない。持込み元は非公開の商品にしか
--   ひも付けられないので、公開済みの商品を後から持込み扱いにして抜けることもできない。
--   公開・非公開の変更は、経路を問わずトリガで admin_audit_logs に記録する。
--
-- 絶対原則との対応
--   原則1 : customers には列を追加しない。申請・持込み元は代理店と商品だけを指す。
--   原則3 : product_sources.sourced_by_agent_id は招待経路 (agents.invited_by)・
--           顧客の担当 (customer_assignments)・売上の帰属 (orders.agent_id) のいずれとも
--           連動しない (トリガ・外部キーでの連動を作らない)。
--   原則5 : 4 テーブルとも authenticated / anon に権限を与えない (0018 の RPC 経由のみ)。
--           持込み元はショップの RPC にも代理店の画面にも出さない。
--   監査  : admin_audit_logs は support / admin も閲覧できるため、生産者の連絡先は
--           監査ログに値を書かない (0018 で「設定あり / 変更あり」だけを記録する)。
--
-- 報酬計算は範囲外。将来は product_sources と expected_wholesale_price を結合して追加できる。
-- ============================================================================

begin;

-- ============================================================================
-- 1. 列挙型・採番
-- ============================================================================

create type public.submission_status as enum
  ('draft', 'submitted', 'returned', 'approved', 'rejected', 'withdrawn');

comment on type public.submission_status is
  'draft=下書き / submitted=申請中 / returned=差し戻し / approved=承認 / rejected=却下 / withdrawn=取り下げ';

create sequence public.product_submission_no_seq start with 1;

-- ============================================================================
-- 2. product_submissions (持込み申請)
-- ============================================================================

create table public.product_submissions (
  id                            uuid primary key default gen_random_uuid(),
  submission_no                 text not null unique,
  agent_id                      uuid not null references public.agents (id) on delete restrict,
  status                        public.submission_status not null default 'draft',
  revision                      integer not null default 0 check (revision >= 0),

  -- 商品
  name                          text not null check (btrim(name) <> '' and char_length(name) <= 100),
  category                      public.product_category not null default 'other',
  description                   text check (description is null or char_length(description) <= 4000),
  desired_price                 numeric(12, 2) check (desired_price is null or desired_price >= 0),
  expected_wholesale_price      numeric(12, 2)
                                  check (expected_wholesale_price is null or expected_wholesale_price >= 0),
  content_volume                text check (content_volume is null or char_length(content_volume) <= 200),
  ingredients                   text check (ingredients is null or char_length(ingredients) <= 2000),
  best_before_note              text check (best_before_note is null or char_length(best_before_note) <= 200),

  -- 生産者 (公開項目の候補)
  producer_name                 text check (producer_name is null or char_length(producer_name) <= 100),
  producer_origin               text check (producer_origin is null or char_length(producer_origin) <= 100),
  producer_ship_from_prefecture text,
  producer_ship_lead_time       text check (producer_ship_lead_time is null or char_length(producer_ship_lead_time) <= 100),

  -- 生産者の連絡先 (申請した本人と super_admin のみ。監査ログには値を書かない)
  producer_contact_name         text check (producer_contact_name is null or char_length(producer_contact_name) <= 100),
  producer_contact_phone        text check (producer_contact_phone is null or char_length(producer_contact_phone) <= 30),
  producer_contact_email        text,

  -- 審査
  submitted_at                  timestamptz,
  reviewed_by                   uuid references auth.users (id) on delete set null,
  reviewed_at                   timestamptz,
  review_reason                 text,

  -- 承認の結果 (承認時にのみ設定し、以後変更不可)
  approved_product_id           uuid unique references public.products (id) on delete restrict,
  approved_producer_id          uuid references public.producers (id) on delete restrict,

  created_by                    uuid references auth.users (id) on delete set null,
  created_at                    timestamptz not null default now(),
  updated_at                    timestamptz not null default now(),

  constraint product_submissions_prefecture_valid check (
    producer_ship_from_prefecture is null
    or producer_ship_from_prefecture = any (app.prefecture_list())
  ),
  constraint product_submissions_contact_email_format check (
    producer_contact_email is null or producer_contact_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
  ),
  -- 申請以降は必須項目が揃っていること (下書き・取り下げは途中でもよい)
  constraint product_submissions_complete_when_submitted check (
    status in ('draft', 'withdrawn')
    or (    nullif(btrim(coalesce(description, '')), '') is not null
        and desired_price is not null
        and nullif(btrim(coalesce(content_volume, '')), '') is not null
        and nullif(btrim(coalesce(producer_name, '')), '') is not null
        and nullif(btrim(coalesce(producer_origin, '')), '') is not null
        and producer_ship_from_prefecture is not null
        and nullif(btrim(coalesce(producer_ship_lead_time, '')), '') is not null
        and (   nullif(btrim(coalesce(producer_contact_phone, '')), '') is not null
             or nullif(btrim(coalesce(producer_contact_email, '')), '') is not null))
  ),
  -- 差し戻し・却下は理由必須
  constraint product_submissions_reason_required check (
    status not in ('returned', 'rejected')
    or nullif(btrim(coalesce(review_reason, '')), '') is not null
  ),
  -- 承認の結果は承認のときだけ、かつ必ず持つ
  constraint product_submissions_approval_result check (
    (status = 'approved') = (approved_product_id is not null and approved_producer_id is not null)
    and (approved_product_id is null) = (approved_producer_id is null)
  ),
  constraint product_submissions_submitted_at check (
    status = 'draft' or status = 'withdrawn' or submitted_at is not null
  )
);

comment on table public.product_submissions is
  '代理店からの商品の持込み申請。本人と super_admin のみ (0018 の RPC 経由)。authenticated に権限なし。'
  '招待経路・顧客の担当とは無関係。';
comment on column public.product_submissions.producer_contact_name is
  '生産者の連絡先 (申請した本人と super_admin のみ)。監査ログには値を書かない。';
comment on column public.product_submissions.expected_wholesale_price is
  '想定卸値 (任意)。将来の持込み報酬計算の参考値。現時点では計算に使わない。';

create index product_submissions_agent_idx  on public.product_submissions (agent_id, created_at desc);
create index product_submissions_status_idx on public.product_submissions (status, submitted_at);

create or replace function app.assign_submission_no()
returns trigger
language plpgsql
as $fn$
begin
  if new.submission_no is null or btrim(new.submission_no) = '' then
    new.submission_no := 'PS-' || to_char(now() at time zone 'Asia/Tokyo', 'YYYYMMDD') || '-'
                         || lpad(nextval('public.product_submission_no_seq')::text, 6, '0');
  end if;
  return new;
end;
$fn$;

create trigger product_submissions_assign_no
  before insert on public.product_submissions
  for each row execute function app.assign_submission_no();

create trigger product_submissions_touch_updated_at
  before update on public.product_submissions
  for each row execute function app.touch_updated_at();

-- ============================================================================
-- 3. 申請の書込みガード・状態遷移
-- ============================================================================

-- 内容の列が変わったか (審査・状態・時刻の列を除く)
create or replace function app.submission_content_changed(o public.product_submissions, n public.product_submissions)
returns boolean
language sql
immutable
as $fn$
  select o.name                          is distinct from n.name
      or o.category                      is distinct from n.category
      or o.description                   is distinct from n.description
      or o.desired_price                 is distinct from n.desired_price
      or o.expected_wholesale_price      is distinct from n.expected_wholesale_price
      or o.content_volume                is distinct from n.content_volume
      or o.ingredients                   is distinct from n.ingredients
      or o.best_before_note              is distinct from n.best_before_note
      or o.producer_name                 is distinct from n.producer_name
      or o.producer_origin               is distinct from n.producer_origin
      or o.producer_ship_from_prefecture is distinct from n.producer_ship_from_prefecture
      or o.producer_ship_lead_time       is distinct from n.producer_ship_lead_time
      or o.producer_contact_name         is distinct from n.producer_contact_name
      or o.producer_contact_phone        is distinct from n.producer_contact_phone
      or o.producer_contact_email        is distinct from n.producer_contact_email;
$fn$;

create or replace function app.guard_product_submissions_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.submission_ctx', true), '');
  v_db  boolean := (current_user = 'postgres' and v_ctx = '');
begin
  -- 申請は削除しない (取り下げで扱う)。postgres でも不可。
  if tg_op = 'DELETE' then
    raise exception 'TREEMERCE_SUBMISSION_DELETE_DENIED: 申請は削除できません (取り下げで扱う)'
      using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'draft' or new.revision <> 0 or new.submitted_at is not null
       or new.reviewed_by is not null or new.reviewed_at is not null or new.review_reason is not null
       or new.approved_product_id is not null or new.approved_producer_id is not null then
      raise exception 'TREEMERCE_SUBMISSION_INVALID_STATE: 申請は下書きとしてのみ作成できます'
        using errcode = '42501';
    end if;
    if v_db or v_ctx = 'submission_agent' then
      return new;
    end if;
    raise exception 'TREEMERCE_SUBMISSION_WRITE_DENIED: 申請は本人の作成処理でのみ作成できます'
      using errcode = '42501';
  end if;

  -- ---- UPDATE ----

  -- 誰にも変更させない列 (postgres 直接操作も含む)
  if new.id            is distinct from old.id
     or new.submission_no is distinct from old.submission_no
     or new.agent_id      is distinct from old.agent_id
     or new.created_by    is distinct from old.created_by
     or new.created_at    is distinct from old.created_at then
    raise exception 'TREEMERCE_SUBMISSION_IMMUTABLE: 申請の番号・代理店・作成情報は変更できません'
      using errcode = '42501';
  end if;

  -- 終端 (承認・却下・取り下げ) の申請はどの列も変更できない
  if old.status in ('approved', 'rejected', 'withdrawn') then
    raise exception 'TREEMERCE_SUBMISSION_FINALIZED: この申請は確定済みのため変更できません'
      using errcode = '42501';
  end if;

  -- DB 管理者の直接操作: 状態・審査・承認結果は変えず、内容の修正だけ許可する
  if v_db then
    if new.status          is distinct from old.status
       or new.revision     is distinct from old.revision
       or new.submitted_at is distinct from old.submitted_at
       or new.reviewed_by  is distinct from old.reviewed_by
       or new.reviewed_at  is distinct from old.reviewed_at
       or new.review_reason is distinct from old.review_reason
       or new.approved_product_id  is distinct from old.approved_product_id
       or new.approved_producer_id is distinct from old.approved_producer_id then
      raise exception 'TREEMERCE_SUBMISSION_WRITE_DENIED: 申請の状態は専用の処理でのみ変更できます'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if v_ctx = 'submission_agent' then
    -- 本人: 審査・承認結果の列には触れない
    if new.reviewed_by  is distinct from old.reviewed_by
       or new.reviewed_at  is distinct from old.reviewed_at
       or new.review_reason is distinct from old.review_reason
       or new.approved_product_id  is distinct from old.approved_product_id
       or new.approved_producer_id is distinct from old.approved_producer_id then
      raise exception 'TREEMERCE_SUBMISSION_WRITE_DENIED: 審査結果は変更できません'
        using errcode = '42501';
    end if;
    -- 内容の編集は下書き・差し戻しの間だけ
    if app.submission_content_changed(old, new) and old.status not in ('draft', 'returned') then
      raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 申請中の内容は編集できません'
        using errcode = '42501';
    end if;
    if new.status is distinct from old.status and not (
         (old.status in ('draft', 'returned') and new.status in ('submitted', 'withdrawn'))
    ) then
      raise exception 'TREEMERCE_INVALID_TRANSITION: % から % へは変更できません', old.status, new.status
        using errcode = '22023';
    end if;
    if new.status = old.status and old.status not in ('draft', 'returned') then
      raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 申請中の申請は変更できません'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if v_ctx = 'submission_review' then
    -- super_admin: 内容は変えず、申請中から承認・差し戻し・却下へ進めるだけ
    if app.submission_content_changed(old, new)
       or new.revision     is distinct from old.revision
       or new.submitted_at is distinct from old.submitted_at then
      raise exception 'TREEMERCE_SUBMISSION_WRITE_DENIED: 審査では申請の内容を変更できません'
        using errcode = '42501';
    end if;
    if not (old.status = 'submitted' and new.status in ('approved', 'returned', 'rejected')) then
      raise exception 'TREEMERCE_INVALID_TRANSITION: % から % へは変更できません', old.status, new.status
        using errcode = '22023';
    end if;
    return new;
  end if;

  raise exception
    'TREEMERCE_SUBMISSION_WRITE_DENIED: 申請は専用の処理 (本人の申請 / super_admin の審査) でのみ書き込めます'
    using errcode = '42501';
end;
$fn$;

create trigger product_submissions_guard
  before insert or update or delete on public.product_submissions
  for each row execute function app.guard_product_submissions_write();

-- ============================================================================
-- 4. product_submission_events (状態変更履歴。追記専用)
-- ============================================================================

create table public.product_submission_events (
  id               uuid primary key default gen_random_uuid(),
  submission_id    uuid not null references public.product_submissions (id) on delete restrict,
  revision         integer not null check (revision >= 0),
  from_status      public.submission_status,
  to_status        public.submission_status not null,
  reason           text,
  -- 申請・再申請時点の内容 (差し戻し前後の差分確認用)。本人と super_admin にのみ返す。
  content_snapshot jsonb,
  actor_user_id    uuid references auth.users (id) on delete set null,
  actor_role       text not null check (actor_role in ('agent', 'super_admin', 'system')),
  changed_at       timestamptz not null default clock_timestamp(),

  constraint product_submission_events_reason_required check (
    to_status not in ('returned', 'rejected') or nullif(btrim(coalesce(reason, '')), '') is not null
  )
);

create index product_submission_events_submission_idx
  on public.product_submission_events (submission_id, changed_at desc);

create or replace function app.guard_submission_events_append_only()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.submission_ctx', true), '');
begin
  if tg_op = 'INSERT'
     and (v_ctx in ('submission_agent', 'submission_review') or (current_user = 'postgres' and v_ctx = '')) then
    return new;
  end if;
  raise exception 'TREEMERCE_SUBMISSION_HISTORY_APPEND_ONLY: 申請の履歴は追記専用です'
    using errcode = '42501';
end;
$fn$;

create trigger product_submission_events_guard
  before insert or update or delete on public.product_submission_events
  for each row execute function app.guard_submission_events_append_only();

-- ============================================================================
-- 5. product_submission_images (申請画像。最大 5 枚)
-- ----------------------------------------------------------------------------
-- パスは {agent_id}/{submission_id}/{uuid}.{jpg|png|webp}。
-- 先に行を作って枠を確保し (0018 の RPC)、そのパスにだけアップロードを許可する (Storage の権限)。
-- 追加・削除・並べ替えは、申請が下書き・差し戻しの間に本人だけができる。
-- ============================================================================

create table public.product_submission_images (
  id            uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.product_submissions (id) on delete restrict,
  storage_path  text not null unique,
  content_type  text not null check (content_type in ('image/jpeg', 'image/png', 'image/webp')),
  sort_order    integer not null default 0 check (sort_order between 0 and 4),
  created_at    timestamptz not null default now(),

  constraint product_submission_images_path_format check (
    storage_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$'
  )
);

create index product_submission_images_submission_idx
  on public.product_submission_images (submission_id, sort_order);

create or replace function app.guard_submission_images_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx    text := coalesce(current_setting('app.submission_ctx', true), '');
  v_sub    public.product_submissions%rowtype;
  v_count  integer;
begin
  if tg_op = 'UPDATE' and (new.submission_id is distinct from old.submission_id
                           or new.storage_path is distinct from old.storage_path
                           or new.content_type is distinct from old.content_type) then
    raise exception 'TREEMERCE_SUBMISSION_IMAGE_IMMUTABLE: 画像の申請・保存先は変更できません'
      using errcode = '42501';
  end if;

  -- 申請行をロックして枚数の競合を防ぐ
  select * into v_sub from public.product_submissions
  where id = coalesce(new.submission_id, old.submission_id)
  for update;

  if not (current_user = 'postgres' and v_ctx = '') then
    if v_ctx <> 'submission_agent' then
      raise exception 'TREEMERCE_SUBMISSION_WRITE_DENIED: 申請画像は本人の処理でのみ変更できます'
        using errcode = '42501';
    end if;
    if v_sub.status not in ('draft', 'returned') then
      raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 申請中・確定済みの申請の画像は変更できません'
        using errcode = '42501';
    end if;
  end if;

  if tg_op = 'INSERT' then
    if split_part(new.storage_path, '/', 1) <> v_sub.agent_id::text
       or split_part(new.storage_path, '/', 2) <> v_sub.id::text then
      raise exception 'TREEMERCE_INVALID_INPUT: 画像の保存先が申請と一致しません' using errcode = '22023';
    end if;
    select count(*) into v_count from public.product_submission_images where submission_id = v_sub.id;
    if v_count >= 5 then
      raise exception 'TREEMERCE_INVALID_INPUT: 画像は 1 件の申請につき 5 枚までです' using errcode = '22023';
    end if;
  end if;

  return coalesce(new, old);
end;
$fn$;

create trigger product_submission_images_guard
  before insert or update or delete on public.product_submission_images
  for each row execute function app.guard_submission_images_write();

-- ============================================================================
-- 6. product_sources (商品の持込み元。products と 1:1)
-- ----------------------------------------------------------------------------
-- 承認処理 ('submission_review') の中でだけ作成でき、作成後は誰にも変更・削除できない。
-- 作成時に、申請が承認済みで、その承認結果の商品であり、代理店が申請者と一致し、
-- 商品が非公開であることを検証する。
-- ============================================================================

create table public.product_sources (
  product_id          uuid primary key references public.products (id) on delete restrict,
  sourced_by_agent_id uuid not null references public.agents (id) on delete restrict,
  submission_id       uuid not null unique references public.product_submissions (id) on delete restrict,
  created_by          uuid references auth.users (id) on delete set null,
  created_at          timestamptz not null default now()
);

comment on table public.product_sources is
  '商品の持込み元 (持込み代理店)。招待経路・顧客の担当・売上の帰属とは別データで、互いに自動変更しない。'
  'super_admin のみ (RPC 経由)。ショップ・他の代理店には出さない。作成後は変更・削除不可。';

create index product_sources_agent_idx on public.product_sources (sourced_by_agent_id);

create or replace function app.guard_product_sources_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx       text := coalesce(current_setting('app.submission_ctx', true), '');
  v_sub       public.product_submissions%rowtype;
  v_published boolean;
begin
  if tg_op <> 'INSERT' then
    raise exception 'TREEMERCE_PRODUCT_SOURCE_IMMUTABLE: 商品の持込み元は変更・削除できません'
      using errcode = '42501';
  end if;
  if v_ctx <> 'submission_review' then
    raise exception 'TREEMERCE_PRODUCT_SOURCE_WRITE_DENIED: 持込み元は承認処理でのみ記録できます'
      using errcode = '42501';
  end if;

  select * into v_sub from public.product_submissions where id = new.submission_id;
  if not found or v_sub.status <> 'approved' then
    raise exception 'TREEMERCE_SUBMISSION_NOT_APPROVED: 承認済みの申請にのみ持込み元を記録できます'
      using errcode = '42501';
  end if;
  if v_sub.approved_product_id is distinct from new.product_id
     or v_sub.agent_id is distinct from new.sourced_by_agent_id then
    raise exception 'TREEMERCE_PRODUCT_SOURCE_MISMATCH: 申請の承認結果と持込み元が一致しません'
      using errcode = '42501';
  end if;

  select p.is_published into v_published from public.products p where p.id = new.product_id;
  if v_published then
    raise exception 'TREEMERCE_PRODUCT_SOURCE_PUBLISHED: 公開中の商品には持込み元を記録できません'
      using errcode = '42501';
  end if;

  return new;
end;
$fn$;

create trigger product_sources_guard
  before insert or update or delete on public.product_sources
  for each row execute function app.guard_product_sources_write();

-- ============================================================================
-- 7. 公開ガード (products)
-- ----------------------------------------------------------------------------
-- 持込み元のある商品を公開 (false → true) するには、次のすべてが必要:
--   (1) ひも付く申請が approved      (postgres の直接操作でも例外にしない)
--   (2) 実行者が super_admin         (app.is_super_admin()。postgres の直接操作は不可)
--   (3) 生産者が有効かつ仮の生産者でない
-- 非公開にする (true → false) のは制限しない (緊急停止の経路を残す)。監査は 8. で必ず残る。
-- ============================================================================

create or replace function app.guard_sourced_product_publish()
returns trigger
language plpgsql
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_status      public.submission_status;
  v_active      boolean;
  v_placeholder boolean;
begin
  if not (new.is_published and not coalesce(old.is_published, false)) then
    return new;
  end if;

  select s.status into v_status
  from public.product_sources ps
  join public.product_submissions s on s.id = ps.submission_id
  where ps.product_id = new.id;

  if not found then
    return new;   -- 持込み元のない商品は従来どおり
  end if;

  if v_status is distinct from 'approved' then
    raise exception 'TREEMERCE_SUBMISSION_NOT_APPROVED: 持込み申請が承認されていない商品は公開できません'
      using errcode = '42501';
  end if;
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 持込み商品の公開は super_admin のみ実行できます'
      using errcode = '42501';
  end if;

  select pr.is_active, pr.is_placeholder into v_active, v_placeholder
  from public.producers pr where pr.id = new.producer_id;
  if v_placeholder then
    raise exception 'TREEMERCE_PRODUCER_PLACEHOLDER: 仮の生産者「未設定（運営）」のままでは持込み商品を公開できません'
      using errcode = '22023';
  end if;
  if not coalesce(v_active, false) then
    raise exception 'TREEMERCE_PRODUCER_INACTIVE: 無効な生産者の持込み商品は公開できません'
      using errcode = '22023';
  end if;

  return new;
end;
$fn$;

create trigger products_sourced_publish_guard
  before update on public.products
  for each row execute function app.guard_sourced_product_publish();

-- ============================================================================
-- 8. 公開・非公開の監査 (products。経路を問わず必ず記録する)
-- ----------------------------------------------------------------------------
-- 理由は GUC app.audit_reason が設定されていればそれを使う (0018 以降の RPC で設定する)。
-- ============================================================================

create or replace function app.audit_product_published()
returns trigger
language plpgsql
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_submission_no text;
begin
  if tg_op = 'UPDATE' and new.is_published is not distinct from old.is_published then
    return new;
  end if;
  if tg_op = 'INSERT' and not new.is_published then
    return new;
  end if;

  select s.submission_no into v_submission_no
  from public.product_sources ps
  join public.product_submissions s on s.id = ps.submission_id
  where ps.product_id = new.id;

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (
    auth.uid(),
    coalesce(app.admin_role(), case when current_user = 'postgres' and auth.uid() is null
                                    then 'db_admin' else 'unknown' end),
    case when new.is_published then 'product.publish' else 'product.unpublish' end,
    'products',
    new.id,
    case when tg_op = 'UPDATE' then jsonb_build_object('is_published', old.is_published) else null end,
    jsonb_build_object(
      'is_published',  new.is_published,
      'name',          new.name,
      'price',         new.price,
      'stock',         new.stock,
      'producer_id',   new.producer_id,
      'sourced',       v_submission_no is not null,
      'submission_no', v_submission_no),
    nullif(btrim(coalesce(current_setting('app.audit_reason', true), '')), '')
  );

  return new;
end;
$fn$;

create trigger products_audit_published
  after insert or update of is_published on public.products
  for each row execute function app.audit_product_published();

-- ============================================================================
-- 9. Storage: 申請画像の非公開バケット (product-submission-images)
-- ----------------------------------------------------------------------------
--   公開   : しない (public = false)。表示はサーバーで発行する短時間の署名付き URL のみ。
--   追加   : 本人が確保済みの枠 (product_submission_images の行) のパスにだけ。申請が編集可能な間のみ。
--   閲覧   : 本人と super_admin。
--   削除   : 本人のフォルダのみ。枠が残っている場合は申請が編集可能な間だけ。
--   上書き : 不可 (UPDATE ポリシーを作らない)。
--   制限   : 5MB まで / JPEG・PNG・WebP のみ。
-- ============================================================================

create or replace function app.can_upload_submission_image(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select exists (
    select 1
    from public.product_submission_images i
    join public.product_submissions s on s.id = i.submission_id
    where i.storage_path = p_name
      and s.agent_id = app.current_agent_id()
      and s.status in ('draft', 'returned')
  );
$fn$;

create or replace function app.can_view_submission_image(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select exists (
    select 1
    from public.product_submission_images i
    join public.product_submissions s on s.id = i.submission_id
    where i.storage_path = p_name
      and (app.is_super_admin() or s.agent_id = app.current_agent_id())
  );
$fn$;

create or replace function app.can_delete_submission_image(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select app.current_agent_id() is not null
     and split_part(p_name, '/', 1) = app.current_agent_id()::text
     and not exists (
       select 1
       from public.product_submission_images i
       join public.product_submissions s on s.id = i.submission_id
       where i.storage_path = p_name
         and s.status not in ('draft', 'returned')
     );
$fn$;

do $do$
begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise notice '0017: storage スキーマが無いためバケットの作成をスキップしました';
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('product-submission-images', 'product-submission-images', false, 5242880,
          array['image/jpeg', 'image/png', 'image/webp'])
  on conflict (id) do update
    set public             = false,
        file_size_limit    = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

  execute 'drop policy if exists treemerce_submission_images_insert on storage.objects';
  execute 'drop policy if exists treemerce_submission_images_select on storage.objects';
  execute 'drop policy if exists treemerce_submission_images_delete on storage.objects';

  execute $p$
    create policy treemerce_submission_images_insert on storage.objects
      for insert to authenticated
      with check (
        bucket_id = 'product-submission-images'
        and app.can_upload_submission_image(name)
      )
  $p$;

  execute $p$
    create policy treemerce_submission_images_select on storage.objects
      for select to authenticated
      using (
        bucket_id = 'product-submission-images'
        and app.can_view_submission_image(name)
      )
  $p$;

  execute $p$
    create policy treemerce_submission_images_delete on storage.objects
      for delete to authenticated
      using (
        bucket_id = 'product-submission-images'
        and app.can_delete_submission_image(name)
      )
  $p$;
end;
$do$;

-- ============================================================================
-- 10. RLS / GRANT
-- ----------------------------------------------------------------------------
-- 4 テーブルとも authenticated / anon に一切の権限を与えない (0018 の RPC 経由のみ)。
-- RLS は有効化し、ポリシーは作らない (万一 GRANT が復活しても 0 行)。
-- ============================================================================

revoke all on public.product_submissions, public.product_submission_events,
              public.product_submission_images, public.product_sources
  from anon, authenticated;
revoke all on sequence public.product_submission_no_seq from anon, authenticated;

alter table public.product_submissions       enable row level security;
alter table public.product_submission_events enable row level security;
alter table public.product_submission_images enable row level security;
alter table public.product_sources           enable row level security;

revoke all on function app.assign_submission_no()                       from public, anon, authenticated;
revoke all on function app.submission_content_changed(public.product_submissions, public.product_submissions)
  from public, anon, authenticated;
revoke all on function app.guard_product_submissions_write()            from public, anon, authenticated;
revoke all on function app.guard_submission_events_append_only()        from public, anon, authenticated;
revoke all on function app.guard_submission_images_write()              from public, anon, authenticated;
revoke all on function app.guard_product_sources_write()                from public, anon, authenticated;
revoke all on function app.guard_sourced_product_publish()              from public, anon, authenticated;
revoke all on function app.audit_product_published()                    from public, anon, authenticated;
revoke all on function app.can_upload_submission_image(text)            from public, anon, authenticated;
revoke all on function app.can_view_submission_image(text)              from public, anon, authenticated;
revoke all on function app.can_delete_submission_image(text)            from public, anon, authenticated;

-- Storage のポリシー式の評価に必要 (判定のみ。行の中身は返さない)
grant execute on function app.can_upload_submission_image(text) to authenticated;
grant execute on function app.can_view_submission_image(text)   to authenticated;
grant execute on function app.can_delete_submission_image(text) to authenticated;

commit;
