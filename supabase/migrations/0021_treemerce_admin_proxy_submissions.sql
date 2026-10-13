-- ============================================================================
-- TREEMERCE : 0021_treemerce_admin_proxy_submissions.sql
-- super_admin による持込み申請の代行 (0017・0018 の拡張) と代理店一覧の概要
-- ----------------------------------------------------------------------------
-- 運営が代理店から話を聞き、その代理店の名義で持込み申請を作成し、そのまま審査・承認する。
--
--   product_submissions.created_via : 'agent' (本人が作成) / 'admin_proxy' (運営が代行作成)。
--     作成後は変更不可。代行の申請の agent_id は対象の代理店、created_by は実行した super_admin。
--
--   代行の申請
--     * 作成・編集・画像・申請・取り下げは super_admin だけが、代行の申請に対してだけ行える
--       (コンテキスト 'submission_admin_proxy')。本人が作成した申請には触れない。
--     * 本人の画面では閲覧のみ (本人の編集・申請・取り下げ・画像の操作はすべて拒否)。
--     * 承認・差し戻し・却下は従来の審査処理 ('submission_review') だけで行う。
--       承認では従来どおり申請の agent_id が持込み元 (product_sources) になる。
--     * 作成者本人 (同じ super_admin) が承認してよい。承認の監査ログに
--       created_via と approved_by_creator を残して追えるようにする。
--     * 作成は理由必須 (ヒアリングの日付・経緯など)。取り下げも理由必須。
--     * 対象は稼働中 (active) の代理店のみ (取り下げは状態を問わない)。
--
--   代理店一覧の概要 : treemerce_admin_list_agent_overview() (STABLE、件数のみ)
--
-- 監査ログ (admin_audit_logs は support / admin も閲覧可) には、生産者の連絡先を書かない
-- (app.submission_audit_state の「has_producer_contact」と、変更した項目名 'producer_contact' のみ)。
--   submission.proxy_create / proxy_update / proxy_submit / proxy_resubmit / proxy_withdraw /
--   proxy_image_add / proxy_image_remove                                    (actor_role = super_admin)
--
-- 絶対原則との対応
--   原則1   : customers には触れない。
--   原則3・4 : 招待経路 (invited_by)・顧客の担当 (customer_assignments)・売上の帰属 (orders.agent_id)
--             を参照も変更もしない。持込み元は従来の承認処理でのみ作られる。
--   原則5   : 返すのは申請と件数だけ。顧客の情報は含めない。
--
-- 実装の入口 (すべて super_admin のみ)
--   代行の作成・保存   : treemerce_admin_save_proxy_submission
--   代行の申請         : treemerce_admin_submit_proxy_submission
--   代行の取り下げ     : treemerce_admin_withdraw_proxy_submission       (理由必須)
--   代行の画像         : treemerce_admin_reserve_proxy_submission_image / treemerce_admin_remove_proxy_submission_image
--   代理店一覧の概要   : treemerce_admin_list_agent_overview              (STABLE)
--   変更               : treemerce_admin_list_submissions (p_agent_id を追加・代行の下書きを含める)
--                        treemerce_admin_get_submission / treemerce_admin_approve_submission /
--                        treemerce_my_submissions / treemerce_my_submission (created_via を返す)
-- ============================================================================

begin;

-- ============================================================================
-- 1. 列の追加 (作成経路)
-- ============================================================================

alter table public.product_submissions
  add column created_via text not null default 'agent'
    constraint product_submissions_created_via_valid check (created_via in ('agent', 'admin_proxy'));

comment on column public.product_submissions.created_via is
  'agent = 代理店本人が作成 / admin_proxy = super_admin が代理店の名義で代行作成。作成後は変更不可。'
  '代行の申請は本人の画面では閲覧のみ。';

create index product_submissions_proxy_idx
  on public.product_submissions (agent_id, status) where created_via = 'admin_proxy';

-- ============================================================================
-- 2. 申請の書込みガード (0017 を置き換え)
-- ----------------------------------------------------------------------------
-- 追加: コンテキスト 'submission_admin_proxy' (super_admin の代行)
--   * 作成は created_via = 'admin_proxy' の下書きのみ
--   * 変更は created_via = 'admin_proxy' の申請のみ。内容の編集は下書き・差し戻しの間だけ
--   * 状態は 下書き・差し戻し → 申請中・取り下げ のみ (承認・差し戻し・却下は 'submission_review' だけ)
-- 変更: 'submission_agent' (本人) は代行の申請を作成・変更できない
-- ============================================================================

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
    if v_db then
      return new;
    end if;
    if v_ctx = 'submission_agent' then
      if new.created_via <> 'agent' then
        raise exception 'TREEMERCE_SUBMISSION_WRITE_DENIED: 本人の作成処理では代行の申請を作れません'
          using errcode = '42501';
      end if;
      return new;
    end if;
    if v_ctx = 'submission_admin_proxy' then
      if not app.is_super_admin() then
        raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 申請の代行は super_admin のみ実行できます'
          using errcode = '42501';
      end if;
      if new.created_via <> 'admin_proxy' then
        raise exception 'TREEMERCE_SUBMISSION_WRITE_DENIED: 代行の作成処理では本人の申請を作れません'
          using errcode = '42501';
      end if;
      return new;
    end if;
    raise exception 'TREEMERCE_SUBMISSION_WRITE_DENIED: 申請は本人の作成処理または運営の代行でのみ作成できます'
      using errcode = '42501';
  end if;

  -- ---- UPDATE ----

  -- 誰にも変更させない列 (postgres 直接操作も含む)
  if new.id            is distinct from old.id
     or new.submission_no is distinct from old.submission_no
     or new.agent_id      is distinct from old.agent_id
     or new.created_via   is distinct from old.created_via
     or new.created_by    is distinct from old.created_by
     or new.created_at    is distinct from old.created_at then
    raise exception 'TREEMERCE_SUBMISSION_IMMUTABLE: 申請の番号・代理店・作成経路・作成情報は変更できません'
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

  if v_ctx in ('submission_agent', 'submission_admin_proxy') then
    if v_ctx = 'submission_agent' and old.created_via <> 'agent' then
      raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 運営が代行作成した申請は閲覧のみです'
        using errcode = '42501';
    end if;
    if v_ctx = 'submission_admin_proxy' then
      if not app.is_super_admin() then
        raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 申請の代行は super_admin のみ実行できます'
          using errcode = '42501';
      end if;
      if old.created_via <> 'admin_proxy' then
        raise exception 'TREEMERCE_SUBMISSION_NOT_PROXY: 代理店本人が作成した申請は運営が編集できません'
          using errcode = '42501';
      end if;
    end if;
    -- 審査・承認結果の列には触れない
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
    'TREEMERCE_SUBMISSION_WRITE_DENIED: 申請は専用の処理 (本人の申請 / 運営の代行 / super_admin の審査) でのみ書き込めます'
    using errcode = '42501';
end;
$fn$;

-- ============================================================================
-- 3. 履歴の追記ガード (0017 を置き換え。代行のコンテキストを追加)
-- ============================================================================

create or replace function app.guard_submission_events_append_only()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.submission_ctx', true), '');
begin
  if tg_op = 'INSERT'
     and (v_ctx in ('submission_agent', 'submission_admin_proxy', 'submission_review')
          or (current_user = 'postgres' and v_ctx = '')) then
    return new;
  end if;
  raise exception 'TREEMERCE_SUBMISSION_HISTORY_APPEND_ONLY: 申請の履歴は追記専用です'
    using errcode = '42501';
end;
$fn$;

-- ============================================================================
-- 4. 画像の書込みガード (0017 を置き換え)
-- ----------------------------------------------------------------------------
-- 本人の申請は 'submission_agent'、代行の申請は 'submission_admin_proxy' (super_admin) でのみ
-- 追加・削除できる。どちらも申請が下書き・差し戻しの間だけ。
-- ============================================================================

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
    if v_ctx = 'submission_agent' then
      if v_sub.created_via <> 'agent' then
        raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 運営が代行作成した申請の画像は変更できません'
          using errcode = '42501';
      end if;
    elsif v_ctx = 'submission_admin_proxy' then
      if not app.is_super_admin() then
        raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 申請の代行は super_admin のみ実行できます'
          using errcode = '42501';
      end if;
      if v_sub.created_via <> 'admin_proxy' then
        raise exception 'TREEMERCE_SUBMISSION_NOT_PROXY: 代理店本人が作成した申請の画像は運営が変更できません'
          using errcode = '42501';
      end if;
    else
      raise exception 'TREEMERCE_SUBMISSION_WRITE_DENIED: 申請画像は本人の処理または運営の代行でのみ変更できます'
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

-- ============================================================================
-- 5. Storage の判定 (0017 を置き換え。ポリシーは関数名で参照しているので作り直さない)
-- ----------------------------------------------------------------------------
--   追加 : 本人の申請は本人、代行の申請は super_admin。確保済みの枠のパスに、編集可能な間だけ。
--   閲覧 : 本人と super_admin (変更なし。代行の申請の画像も本人のフォルダにあるので本人が見られる)。
--   削除 : 本人は自分のフォルダのうち代行の申請以外。super_admin は代行の申請 (編集可能な間) のみ。
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
      and s.status in ('draft', 'returned')
      and (   (s.created_via = 'agent'       and s.agent_id = app.current_agent_id())
           or (s.created_via = 'admin_proxy' and app.is_super_admin()))
  );
$fn$;

create or replace function app.can_delete_submission_image(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select
    (   -- 本人: 自分のフォルダ。確定済みの申請・代行の申請の画像は消せない
        app.current_agent_id() is not null
    and split_part(p_name, '/', 1) = app.current_agent_id()::text
    and not exists (
          select 1
          from public.product_submission_images i
          join public.product_submissions s on s.id = i.submission_id
          where i.storage_path = p_name
            and s.status not in ('draft', 'returned'))
    and not exists (
          select 1 from public.product_submissions s
          where s.id::text = split_part(p_name, '/', 2)
            and s.created_via = 'admin_proxy'))
    or
    (   -- super_admin: 代行の申請 (編集可能な間) のフォルダのみ
        app.is_super_admin()
    and exists (
          select 1 from public.product_submissions s
          where s.id::text       = split_part(p_name, '/', 2)
            and s.agent_id::text = split_part(p_name, '/', 1)
            and s.created_via    = 'admin_proxy'
            and s.status in ('draft', 'returned')));
$fn$;

-- ============================================================================
-- 6. 共通ヘルパー
-- ============================================================================

-- 返却用 (0018 を置き換え。created_via を追加)
create or replace function app.submission_json(s public.product_submissions, p_with_contact boolean)
returns jsonb
language sql
immutable
as $fn$
  select jsonb_build_object(
    'id',                            s.id,
    'submission_no',                 s.submission_no,
    'status',                        s.status,
    'revision',                      s.revision,
    'created_via',                   s.created_via,
    'name',                          s.name,
    'category',                      s.category,
    'description',                   s.description,
    'desired_price',                 s.desired_price,
    'expected_wholesale_price',      s.expected_wholesale_price,
    'content_volume',                s.content_volume,
    'ingredients',                   s.ingredients,
    'best_before_note',              s.best_before_note,
    'producer_name',                 s.producer_name,
    'producer_origin',               s.producer_origin,
    'producer_ship_from_prefecture', s.producer_ship_from_prefecture,
    'producer_ship_lead_time',       s.producer_ship_lead_time,
    'submitted_at',                  s.submitted_at,
    'reviewed_at',                   s.reviewed_at,
    'review_reason',                 s.review_reason,
    'created_at',                    s.created_at,
    'updated_at',                    s.updated_at
  )
  || case when p_with_contact then jsonb_build_object(
       'producer_contact_name',  s.producer_contact_name,
       'producer_contact_phone', s.producer_contact_phone,
       'producer_contact_email', s.producer_contact_email)
     else '{}'::jsonb end;
$fn$;

-- 監査ログ用 (0018 を置き換え。created_via を追加。連絡先は値を出さない)
create or replace function app.submission_audit_state(s public.product_submissions)
returns jsonb
language sql
immutable
as $fn$
  select jsonb_build_object(
    'submission_no',          s.submission_no,
    'agent_id',               s.agent_id,
    'created_via',            s.created_via,
    'status',                 s.status,
    'revision',               s.revision,
    'name',                   s.name,
    'category',               s.category,
    'desired_price',          s.desired_price,
    'producer_name',          s.producer_name,
    'has_producer_contact',   (s.producer_contact_name is not null or s.producer_contact_phone is not null
                               or s.producer_contact_email is not null)
  );
$fn$;

-- 本人の申請を 1 件ロックして取得 (0018 を置き換え)。
-- 本人の変更系 RPC だけが使う。代行の申請は本人には閲覧のみなので、ここで拒否する。
create or replace function app.lock_my_submission(p_submission_id uuid)
returns public.product_submissions
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_self uuid := app.current_agent_id();
  v_row  public.product_submissions%rowtype;
begin
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店アカウントが必要です' using errcode = '42501';
  end if;
  select * into v_row from public.product_submissions
  where id = p_submission_id and agent_id = v_self
  for update;
  if not found then
    raise exception 'TREEMERCE_SUBMISSION_NOT_FOUND: 申請が見つかりません' using errcode = '22023';
  end if;
  if v_row.created_via <> 'agent' then
    raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 運営が代行作成した申請は閲覧のみです'
      using errcode = '22023';
  end if;
  return v_row;
end;
$fn$;

-- 代行の申請を 1 件ロックして取得 (super_admin のみ・代行の申請のみ)
create or replace function app.lock_proxy_submission(p_submission_id uuid)
returns public.product_submissions
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_row public.product_submissions%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 申請の代行は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  select * into v_row from public.product_submissions where id = p_submission_id for update;
  if not found then
    raise exception 'TREEMERCE_SUBMISSION_NOT_FOUND: 申請が見つかりません' using errcode = '22023';
  end if;
  if v_row.created_via <> 'admin_proxy' then
    raise exception 'TREEMERCE_SUBMISSION_NOT_PROXY: 代理店本人が作成した申請は運営が編集できません'
      using errcode = '42501';
  end if;
  return v_row;
end;
$fn$;

-- 代行の対象にできる代理店か (稼働中のみ)
create or replace function app.require_proxy_target_agent(p_agent_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_status public.agent_status;
begin
  select a.status into v_status from public.agents a where a.id = p_agent_id;
  if not found then
    raise exception 'TREEMERCE_AGENT_NOT_FOUND: 代理店が見つかりません' using errcode = '22023';
  end if;
  if v_status <> 'active' then
    raise exception 'TREEMERCE_AGENT_NOT_ACTIVE: 稼働中の代理店のみ申請を代行できます (現在: %)', v_status
      using errcode = '22023';
  end if;
end;
$fn$;

-- ============================================================================
-- 7. super_admin: 代行の作成・保存 (下書き・差し戻しのみ)
-- ----------------------------------------------------------------------------
-- p_submission_id が NULL なら、p_agent_id の代理店の名義で下書きを作る (p_reason 必須)。
-- 指定した場合は、その代行の申請を全項目で置き換える。p_agent_id を渡すなら申請の代理店と
-- 一致すること (別の代理店の画面からの誤操作を防ぐ)。入力の整形・上限は本人の保存と同じ。
-- ============================================================================

create or replace function public.treemerce_admin_save_proxy_submission(
  p_agent_id                      uuid                    default null,
  p_submission_id                 uuid                    default null,
  p_name                          text                    default null,
  p_category                      public.product_category default 'other',
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
  p_reason                        text                    default null
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
      raise exception 'TREEMERCE_INVALID_INPUT: 代行する代理店を指定してください' using errcode = '22023';
    end if;
    if v_reason is null then
      raise exception 'TREEMERCE_REASON_REQUIRED: 代行で作成する理由 (ヒアリングの日付・経緯など) は必須です'
        using errcode = '22023';
    end if;
    perform app.require_proxy_target_agent(p_agent_id);

    perform set_config('app.submission_ctx', 'submission_admin_proxy', true);

    insert into public.product_submissions
      (agent_id, created_via, name, category, description, desired_price, expected_wholesale_price,
       content_volume, ingredients, best_before_note,
       producer_name, producer_origin, producer_ship_from_prefecture, producer_ship_lead_time,
       producer_contact_name, producer_contact_phone, producer_contact_email, created_by)
    values
      (p_agent_id, 'admin_proxy', v_name, coalesce(p_category, 'other'), v_desc, p_desired_price,
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

    perform set_config('app.submission_ctx', 'submission_admin_proxy', true);

    update public.product_submissions
    set name                          = v_name,
        category                      = coalesce(p_category, 'other'),
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
-- 8. super_admin: 代行の申請・再申請
-- ----------------------------------------------------------------------------
-- 必須項目の確認と申請時点の内容の保存は本人の申請 (0018) と同じ。履歴の actor_role は super_admin。
-- 申請中になった後は、従来の審査 (承認・差し戻し・却下) をそのまま使う。
-- ============================================================================

create or replace function public.treemerce_admin_submit_proxy_submission(p_submission_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid     uuid := auth.uid();
  v_role    text := coalesce(app.admin_role(), 'super_admin');
  v_before  public.product_submissions%rowtype;
  v_after   public.product_submissions%rowtype;
  v_missing text[];
begin
  v_before := app.lock_proxy_submission(p_submission_id);
  if v_before.status not in ('draft', 'returned') then
    raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: この申請は申請できる状態ではありません'
      using errcode = '22023';
  end if;
  perform app.require_proxy_target_agent(v_before.agent_id);

  v_missing := array_remove(array[
    case when v_before.description is null then '説明' end,
    case when v_before.desired_price is null then '希望販売価格' end,
    case when v_before.content_volume is null then '内容量' end,
    case when v_before.producer_name is null then '生産者名' end,
    case when v_before.producer_origin is null then '産地' end,
    case when v_before.producer_ship_from_prefecture is null then '発送元の都道府県' end,
    case when v_before.producer_ship_lead_time is null then '発送目安' end,
    case when v_before.producer_contact_phone is null and v_before.producer_contact_email is null
         then '生産者の連絡先 (電話またはメール)' end
  ], null);
  if cardinality(v_missing) > 0 then
    raise exception 'TREEMERCE_INVALID_INPUT: 未入力の項目があります: %', array_to_string(v_missing, '、')
      using errcode = '22023';
  end if;

  perform set_config('app.submission_ctx', 'submission_admin_proxy', true);

  update public.product_submissions
  set status       = 'submitted',
      revision     = v_before.revision + 1,
      submitted_at = clock_timestamp()
  where id = v_before.id
  returning * into v_after;

  insert into public.product_submission_events
    (submission_id, revision, from_status, to_status, reason, content_snapshot, actor_user_id, actor_role)
  values (v_after.id, v_after.revision, v_before.status, 'submitted', null,
          app.submission_json(v_after, true)
            || jsonb_build_object('images', app.submission_images_json(v_after.id)),
          v_uid, 'super_admin');

  perform set_config('app.submission_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, v_role,
          case when v_before.status = 'returned' then 'submission.proxy_resubmit' else 'submission.proxy_submit' end,
          'product_submissions', v_after.id,
          app.submission_audit_state(v_before), app.submission_audit_state(v_after), null);

  return app.submission_json(v_after, true)
         || jsonb_build_object('images', app.submission_images_json(v_after.id));
end;
$fn$;

-- ============================================================================
-- 9. super_admin: 代行の取り下げ (下書き・差し戻しのみ。理由必須。代理店の状態は問わない)
-- ============================================================================

create or replace function public.treemerce_admin_withdraw_proxy_submission(
  p_submission_id uuid,
  p_reason        text
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
  v_reason text;
begin
  v_before := app.lock_proxy_submission(p_submission_id);
  v_reason := app.submission_text(p_reason, 500, '取り下げの理由');
  if v_reason is null then
    raise exception 'TREEMERCE_REASON_REQUIRED: 代行の申請を取り下げる理由は必須です' using errcode = '22023';
  end if;
  if v_before.status not in ('draft', 'returned') then
    raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 申請中・確定済みの申請は取り下げられません'
      using errcode = '22023';
  end if;

  perform set_config('app.submission_ctx', 'submission_admin_proxy', true);

  update public.product_submissions set status = 'withdrawn'
  where id = v_before.id
  returning * into v_after;

  insert into public.product_submission_events
    (submission_id, revision, from_status, to_status, reason, actor_user_id, actor_role)
  values (v_after.id, v_after.revision, v_before.status, 'withdrawn', v_reason, v_uid, 'super_admin');

  perform set_config('app.submission_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, v_role, 'submission.proxy_withdraw', 'product_submissions', v_after.id,
          app.submission_audit_state(v_before), app.submission_audit_state(v_after), v_reason);

  return app.submission_json(v_after, true)
         || jsonb_build_object('images', app.submission_images_json(v_after.id));
end;
$fn$;

-- ============================================================================
-- 10. super_admin: 代行の画像の枠の確保・削除
-- ----------------------------------------------------------------------------
-- 保存先は本人の申請と同じ {agent_id}/{submission_id}/{uuid}.{ext} (本人も閲覧できる)。
-- ============================================================================

create or replace function public.treemerce_admin_reserve_proxy_submission_image(
  p_submission_id uuid,
  p_content_type  text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid   uuid := auth.uid();
  v_role  text := coalesce(app.admin_role(), 'super_admin');
  v_sub   public.product_submissions%rowtype;
  v_ext   text;
  v_slot  integer;
  v_image public.product_submission_images%rowtype;
begin
  v_sub := app.lock_proxy_submission(p_submission_id);
  if v_sub.status not in ('draft', 'returned') then
    raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 申請中・確定済みの申請には画像を追加できません'
      using errcode = '22023';
  end if;
  perform app.require_proxy_target_agent(v_sub.agent_id);

  v_ext := case p_content_type
             when 'image/jpeg' then 'jpg'
             when 'image/png'  then 'png'
             when 'image/webp' then 'webp'
           end;
  if v_ext is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 画像は JPEG・PNG・WebP のみ登録できます' using errcode = '22023';
  end if;

  select min(g) into v_slot
  from generate_series(0, 4) g
  where not exists (select 1 from public.product_submission_images i
                    where i.submission_id = v_sub.id and i.sort_order = g);
  if v_slot is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 画像は 1 件の申請につき 5 枚までです' using errcode = '22023';
  end if;

  perform set_config('app.submission_ctx', 'submission_admin_proxy', true);

  insert into public.product_submission_images (submission_id, storage_path, content_type, sort_order)
  values (v_sub.id, v_sub.agent_id || '/' || v_sub.id || '/' || gen_random_uuid() || '.' || v_ext,
          p_content_type, v_slot)
  returning * into v_image;

  perform set_config('app.submission_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, v_role, 'submission.proxy_image_add', 'product_submissions', v_sub.id, null,
          jsonb_build_object('submission_no', v_sub.submission_no, 'agent_id', v_sub.agent_id,
                             'image_id', v_image.id, 'sort_order', v_image.sort_order),
          null);

  return jsonb_build_object(
    'image_id',     v_image.id,
    'storage_path', v_image.storage_path,
    'content_type', v_image.content_type,
    'sort_order',   v_image.sort_order);
end;
$fn$;

create or replace function public.treemerce_admin_remove_proxy_submission_image(p_image_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid   uuid := auth.uid();
  v_role  text := coalesce(app.admin_role(), 'super_admin');
  v_image public.product_submission_images%rowtype;
  v_sub   public.product_submissions%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 申請の代行は super_admin のみ実行できます'
      using errcode = '42501';
  end if;

  select * into v_image from public.product_submission_images where id = p_image_id;
  if not found then
    raise exception 'TREEMERCE_SUBMISSION_NOT_FOUND: 画像が見つかりません' using errcode = '22023';
  end if;

  v_sub := app.lock_proxy_submission(v_image.submission_id);
  if v_sub.status not in ('draft', 'returned') then
    raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 申請中・確定済みの申請の画像は削除できません'
      using errcode = '22023';
  end if;

  perform set_config('app.submission_ctx', 'submission_admin_proxy', true);
  delete from public.product_submission_images where id = v_image.id;
  perform set_config('app.submission_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, v_role, 'submission.proxy_image_remove', 'product_submissions', v_sub.id,
          jsonb_build_object('submission_no', v_sub.submission_no, 'agent_id', v_sub.agent_id,
                             'image_id', v_image.id, 'sort_order', v_image.sort_order),
          null, null);

  return jsonb_build_object('storage_path', v_image.storage_path);
end;
$fn$;

-- ============================================================================
-- 11. 代理店: 自分の申請一覧・詳細 (0018 を置き換え。created_via を返し、代行の申請は閲覧のみ)
-- ============================================================================

create or replace function public.treemerce_my_submissions()
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
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店アカウントが必要です' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id',                   s.id,
             'submission_no',        s.submission_no,
             'status',               s.status,
             'revision',             s.revision,
             'created_via',          s.created_via,
             'name',                 s.name,
             'category',             s.category,
             'desired_price',        s.desired_price,
             'submitted_at',         s.submitted_at,
             'reviewed_at',          s.reviewed_at,
             'review_reason',        case when s.status in ('returned', 'rejected') then s.review_reason end,
             'image_count',          (select count(*) from public.product_submission_images i
                                      where i.submission_id = s.id),
             'product_is_published', (select p.is_published from public.products p
                                      where p.id = s.approved_product_id),
             'updated_at',           s.updated_at)
           order by s.updated_at desc)
    from public.product_submissions s
    where s.agent_id = v_self
  ), '[]'::jsonb);
end;
$fn$;

create or replace function public.treemerce_my_submission(p_submission_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_self uuid := app.current_agent_id();
  v_row  public.product_submissions%rowtype;
begin
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店アカウントが必要です' using errcode = '42501';
  end if;

  select * into v_row from public.product_submissions
  where id = p_submission_id and agent_id = v_self;
  if not found then
    raise exception 'TREEMERCE_SUBMISSION_NOT_FOUND: 申請が見つかりません' using errcode = '22023';
  end if;

  return app.submission_json(v_row, true)
         || jsonb_build_object(
              'editable',             v_row.status in ('draft', 'returned') and v_row.created_via = 'agent',
              'images',               app.submission_images_json(v_row.id),
              'events',               app.submission_events_json(v_row.id, false),
              'product_is_published', (select p.is_published from public.products p
                                       where p.id = v_row.approved_product_id));
end;
$fn$;

-- ============================================================================
-- 12. super_admin: 申請一覧・詳細 (0018 を置き換え)
-- ----------------------------------------------------------------------------
-- 一覧: p_agent_id で代理店を絞り込める。状態の指定がないときは、本人の下書きは出さず、
--       代行の下書きは出す (運営が作業中のため)。
-- 詳細: created_via / admin_editable (代行の申請で編集可能か) / created_by_me を返す。
-- ============================================================================

drop function public.treemerce_admin_list_submissions(public.submission_status);

create function public.treemerce_admin_list_submissions(
  p_status   public.submission_status default null,
  p_agent_id uuid                     default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 持込み申請は super_admin のみ参照できます'
      using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id',                 s.id,
             'submission_no',      s.submission_no,
             'status',             s.status,
             'revision',           s.revision,
             'created_via',        s.created_via,
             'name',               s.name,
             'category',           s.category,
             'desired_price',      s.desired_price,
             'producer_name',      s.producer_name,
             'agent_id',           a.id,
             'agent_public_id',    a.public_id,
             'agent_display_name', a.display_name,
             'image_count',        (select count(*) from public.product_submission_images i
                                    where i.submission_id = s.id),
             'submitted_at',       s.submitted_at,
             'reviewed_at',        s.reviewed_at,
             'approved_product_id', s.approved_product_id,
             'updated_at',         s.updated_at)
           order by (s.status = 'submitted') desc, s.submitted_at nulls last, s.updated_at desc)
    from public.product_submissions s
    join public.agents a on a.id = s.agent_id
    where ((p_status is null and (s.status <> 'draft' or s.created_via = 'admin_proxy'))
           or s.status = p_status)
      and (p_agent_id is null or s.agent_id = p_agent_id)
  ), '[]'::jsonb);
end;
$fn$;

create or replace function public.treemerce_admin_get_submission(p_submission_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_row   public.product_submissions%rowtype;
  v_agent public.agents%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 持込み申請は super_admin のみ参照できます'
      using errcode = '42501';
  end if;

  select * into v_row from public.product_submissions where id = p_submission_id;
  if not found then
    raise exception 'TREEMERCE_SUBMISSION_NOT_FOUND: 申請が見つかりません' using errcode = '22023';
  end if;
  select * into v_agent from public.agents where id = v_row.agent_id;

  return app.submission_json(v_row, true)
         || jsonb_build_object(
              'agent', jsonb_build_object(
                'id',           v_agent.id,
                'public_id',    v_agent.public_id,
                'display_name', v_agent.display_name,
                'status',       v_agent.status),
              'admin_editable',       v_row.created_via = 'admin_proxy' and v_row.status in ('draft', 'returned'),
              'created_by_me',        v_row.created_by is not distinct from auth.uid(),
              'images',               app.submission_images_json(v_row.id),
              'events',               app.submission_events_json(v_row.id, true),
              'approved_product_id',  v_row.approved_product_id,
              'approved_producer_id', v_row.approved_producer_id,
              'product_is_published', (select p.is_published from public.products p
                                       where p.id = v_row.approved_product_id));
end;
$fn$;

-- ============================================================================
-- 13. super_admin: 承認 (0018 を置き換え。処理は同じで、監査ログに代行の情報を追加)
-- ----------------------------------------------------------------------------
-- approved_by_creator : 代行の申請を、作成した super_admin 本人が承認したか。
-- ============================================================================

create or replace function public.treemerce_admin_approve_submission(
  p_submission_id uuid,
  p_producer_id   uuid                    default null,
  p_product_name  text                    default null,
  p_price         numeric                 default null,
  p_category      public.product_category default null,
  p_reason        text                    default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid      uuid := auth.uid();
  v_role     text := coalesce(app.admin_role(), 'super_admin');
  v_before   public.product_submissions%rowtype;
  v_after    public.product_submissions%rowtype;
  v_producer public.producers%rowtype;
  v_product  public.products%rowtype;
  v_created  boolean := false;
  v_name     text;
  v_price    numeric;
  v_reason   text;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 持込み申請の承認は super_admin のみ実行できます'
      using errcode = '42501';
  end if;

  v_reason := app.submission_text(p_reason, 1000, '理由');
  v_name   := app.submission_text(p_product_name, 100, '商品名');

  select * into v_before from public.product_submissions where id = p_submission_id for update;
  if not found then
    raise exception 'TREEMERCE_SUBMISSION_NOT_FOUND: 申請が見つかりません' using errcode = '22023';
  end if;
  if v_before.status <> 'submitted' then
    raise exception 'TREEMERCE_INVALID_TRANSITION: 申請中の申請のみ承認できます (現在: %)', v_before.status
      using errcode = '22023';
  end if;

  v_name  := coalesce(v_name, v_before.name);
  v_price := coalesce(p_price, v_before.desired_price);
  if v_price is null or v_price < 0 or v_price >= 100000000 then
    raise exception 'TREEMERCE_INVALID_INPUT: 価格は 0 円以上 1 億円未満で指定してください' using errcode = '22023';
  end if;

  -- 生産者の決定
  if p_producer_id is null then
    perform set_config('app.commerce_ctx', 'producer', true);

    insert into public.producers
      (name, origin, ship_from_prefecture, ship_lead_time,
       contact_name, contact_phone, contact_email, note, is_active, created_by)
    values
      (v_before.producer_name, v_before.producer_origin, v_before.producer_ship_from_prefecture,
       v_before.producer_ship_lead_time,
       v_before.producer_contact_name, v_before.producer_contact_phone, v_before.producer_contact_email,
       '持込み申請 ' || v_before.submission_no || ' から作成', true, v_uid)
    returning * into v_producer;

    perform set_config('app.commerce_ctx', '', true);
    v_created := true;

    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (v_uid, v_role, 'producer.create', 'producers', v_producer.id,
            null, app.producer_audit_state(v_producer),
            '持込み申請 ' || v_before.submission_no || ' の承認');
  else
    select * into v_producer from public.producers where id = p_producer_id;
    if not found then
      raise exception 'TREEMERCE_PRODUCER_NOT_FOUND: 生産者が見つかりません' using errcode = '22023';
    end if;
    if v_producer.is_placeholder then
      raise exception 'TREEMERCE_PRODUCER_PLACEHOLDER: 仮の生産者「未設定（運営）」は選べません'
        using errcode = '22023';
    end if;
    if not v_producer.is_active then
      raise exception 'TREEMERCE_PRODUCER_INACTIVE: 無効な生産者は選べません' using errcode = '22023';
    end if;
  end if;

  -- 商品 (在庫 0・非公開の下書き)
  insert into public.products
    (name, description, category, price, stock, is_published, created_by,
     producer_id, content_volume, ingredients, best_before_note)
  values
    (v_name, v_before.description, coalesce(p_category, v_before.category), v_price, 0, false, v_uid,
     v_producer.id, v_before.content_volume, v_before.ingredients, v_before.best_before_note)
  returning * into v_product;

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, v_role, 'product.create', 'products', v_product.id, null, to_jsonb(v_product),
          '持込み申請 ' || v_before.submission_no || ' の承認');

  -- 申請を承認し、持込み元を記録する
  perform set_config('app.submission_ctx', 'submission_review', true);

  update public.product_submissions
  set status               = 'approved',
      reviewed_by          = v_uid,
      reviewed_at          = clock_timestamp(),
      review_reason        = v_reason,
      approved_product_id  = v_product.id,
      approved_producer_id = v_producer.id
  where id = v_before.id
  returning * into v_after;

  insert into public.product_sources (product_id, sourced_by_agent_id, submission_id, created_by)
  values (v_product.id, v_after.agent_id, v_after.id, v_uid);

  insert into public.product_submission_events
    (submission_id, revision, from_status, to_status, reason, actor_user_id, actor_role)
  values (v_after.id, v_after.revision, 'submitted', 'approved', v_reason, v_uid, 'super_admin');

  perform set_config('app.submission_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, v_role, 'submission.approve', 'product_submissions', v_after.id,
          app.submission_audit_state(v_before),
          app.submission_audit_state(v_after) || jsonb_build_object(
            'product_id',          v_product.id,
            'producer_id',         v_producer.id,
            'producer_created',    v_created,
            'approved_by_creator', (v_before.created_via = 'admin_proxy'
                                    and v_before.created_by is not distinct from v_uid)),
          v_reason);

  return app.submission_json(v_after, true) || jsonb_build_object(
    'product_id',       v_product.id,
    'producer_id',      v_producer.id,
    'producer_created', v_created);
end;
$fn$;

-- ============================================================================
-- 14. super_admin: 代理店一覧の概要 (STABLE)
-- ----------------------------------------------------------------------------
-- 代理店ごとに、プロフィールの入力済み項目数と持込み申請の件数 (状態別) だけを返す。
-- プロフィールの値・申請の内容・顧客の情報は含めない。本人の下書きは数えない (一覧と同じ方針)。
-- ============================================================================

create or replace function public.treemerce_admin_list_agent_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 代理店の概要は super_admin のみ参照できます'
      using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'agent_id',                a.id,
             'profile_filled_count',    coalesce(jsonb_array_length(app.agent_profile_filled_fields(p)), 0),
             'profile_updated_at',      p.updated_at,
             'profile_updated_by_role', p.updated_by_role,
             'submission_counts', jsonb_build_object(
               'proxy_draft', coalesce(c.proxy_draft, 0),
               'submitted',   coalesce(c.submitted, 0),
               'returned',    coalesce(c.returned, 0),
               'approved',    coalesce(c.approved, 0)))
           order by a.registered_at)
    from public.agents a
    left join public.agent_profiles p on p.agent_id = a.id
    left join lateral (
      select count(*) filter (where s.status = 'draft' and s.created_via = 'admin_proxy') as proxy_draft,
             count(*) filter (where s.status = 'submitted') as submitted,
             count(*) filter (where s.status = 'returned')  as returned,
             count(*) filter (where s.status = 'approved')  as approved
      from public.product_submissions s
      where s.agent_id = a.id
    ) c on true
  ), '[]'::jsonb);
end;
$fn$;

-- ============================================================================
-- 15. GRANT
-- ============================================================================

revoke all on function app.guard_product_submissions_write()            from public, anon, authenticated;
revoke all on function app.guard_submission_events_append_only()        from public, anon, authenticated;
revoke all on function app.guard_submission_images_write()              from public, anon, authenticated;
revoke all on function app.submission_json(public.product_submissions, boolean) from public, anon, authenticated;
revoke all on function app.submission_audit_state(public.product_submissions) from public, anon, authenticated;
revoke all on function app.lock_my_submission(uuid)                     from public, anon, authenticated;
revoke all on function app.lock_proxy_submission(uuid)                  from public, anon, authenticated;
revoke all on function app.require_proxy_target_agent(uuid)             from public, anon, authenticated;

-- Storage のポリシー式の評価に必要 (判定のみ。行の中身は返さない)
revoke all on function app.can_upload_submission_image(text) from public, anon, authenticated;
revoke all on function app.can_delete_submission_image(text) from public, anon, authenticated;
grant execute on function app.can_upload_submission_image(text) to authenticated;
grant execute on function app.can_delete_submission_image(text) to authenticated;

revoke all on function public.treemerce_admin_save_proxy_submission(
  uuid, uuid, text, public.product_category, text, numeric, numeric, text, text, text,
  text, text, text, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.treemerce_admin_submit_proxy_submission(uuid)          from public, anon, authenticated;
revoke all on function public.treemerce_admin_withdraw_proxy_submission(uuid, text)  from public, anon, authenticated;
revoke all on function public.treemerce_admin_reserve_proxy_submission_image(uuid, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_remove_proxy_submission_image(uuid)    from public, anon, authenticated;
revoke all on function public.treemerce_my_submissions()                             from public, anon, authenticated;
revoke all on function public.treemerce_my_submission(uuid)                          from public, anon, authenticated;
revoke all on function public.treemerce_admin_list_submissions(public.submission_status, uuid)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_get_submission(uuid)                   from public, anon, authenticated;
revoke all on function public.treemerce_admin_approve_submission(
  uuid, uuid, text, numeric, public.product_category, text) from public, anon, authenticated;
revoke all on function public.treemerce_admin_list_agent_overview()                  from public, anon, authenticated;

grant execute on function public.treemerce_admin_save_proxy_submission(
  uuid, uuid, text, public.product_category, text, numeric, numeric, text, text, text,
  text, text, text, text, text, text, text, text) to authenticated;
grant execute on function public.treemerce_admin_submit_proxy_submission(uuid)          to authenticated;
grant execute on function public.treemerce_admin_withdraw_proxy_submission(uuid, text)  to authenticated;
grant execute on function public.treemerce_admin_reserve_proxy_submission_image(uuid, text) to authenticated;
grant execute on function public.treemerce_admin_remove_proxy_submission_image(uuid)    to authenticated;
grant execute on function public.treemerce_my_submissions()                             to authenticated;
grant execute on function public.treemerce_my_submission(uuid)                          to authenticated;
grant execute on function public.treemerce_admin_list_submissions(public.submission_status, uuid) to authenticated;
grant execute on function public.treemerce_admin_get_submission(uuid)                   to authenticated;
grant execute on function public.treemerce_admin_approve_submission(
  uuid, uuid, text, numeric, public.product_category, text) to authenticated;
grant execute on function public.treemerce_admin_list_agent_overview()                  to authenticated;

commit;
