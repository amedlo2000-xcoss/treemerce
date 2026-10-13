-- ============================================================================
-- TREEMERCE : 0024_treemerce_submission_categories_and_analytics.sql
-- 持込み申請のカテゴリを 0022 のマスタへ切り替え、客層分析の購入カテゴリを新カテゴリで集計する
-- ----------------------------------------------------------------------------
-- 持込み申請 (product_submissions)
--   * category_id (product_categories) を追加する。確定前 (下書き・申請中・差し戻し) の申請は
--     旧列挙型から埋める。確定済みの申請は変更できないため書き換えず、旧列挙型で読み替える。
--   * 旧列挙型 category は NULL を許可する (新カテゴリに対応がなければ NULL)。
--     category_id ⇔ category はトリガで整合させる (画面の更新前の呼び出しの互換のため)。
--   * 下書きはカテゴリ未選択でよい。申請 (本人・代行) の時点でカテゴリを必須にする。
--   * 無効なカテゴリは新たに選べない (現在のカテゴリのままなら可)。
--   * 返却・監査・申請時点の内容に category_id / category_name を含める。
--   * 運営の申請一覧はカテゴリで絞り込める (p_category_id)。
--
-- 承認 (treemerce_admin_approve_submission)
--   p_category_id を追加。作る商品のカテゴリは 指定 → 申請のカテゴリ の順で決め、有効なカテゴリに限る。
--
-- 客層分析 (treemerce_customer_demographics)
--   購入カテゴリの集計単位を新カテゴリにする。明細の注文時点のカテゴリ (0023 以降) を使い、
--   それより前の明細と旧 purchases は旧列挙型を legacy_code で読み替える (同じカテゴリとして数える)。
--   キーは今のカテゴリ名 (名称変更は表示だけが変わり、集計単位は変わらない)。
--   購入者の人数で数えること・入金確認済み以降のみ・n<5 の丸め・代理店別の内訳なし・STABLE は維持。
--
-- 旧列挙型の写し (注文明細・商品) をやめる作業は、画面の切り替え後の整理 (0026) で行う。
-- 今の画面が旧列挙型の値を送るため、それまでは両方を整合させて残す。
--
-- 絶対原則との対応
--   原則3・4 : 招待経路・顧客の担当・注文の帰属・持込み元は参照も変更もしない。
--   原則5    : 申請の一覧・詳細の見える範囲 (本人 / super_admin) は変えない。
--   派生     : 客層分析は読み取り専用 (STABLE)・n<5 の丸め・内訳なしを維持する。
-- ============================================================================

begin;

-- ============================================================================
-- 1. 共通: カテゴリ名 (新カテゴリ → なければ旧列挙型の読み替え)
-- ============================================================================

create or replace function app.category_name_for(p_category_id uuid, p_legacy public.product_category)
returns text
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select coalesce(
    (select c.name from public.product_categories c where c.id = p_category_id),
    (select c.name from public.product_categories c where c.legacy_code = p_legacy));
$fn$;

-- 申請・商品に新たに設定するカテゴリの検証 (存在し、有効か、現在のカテゴリのままであること)
create or replace function app.require_assignable_category(p_category_id uuid, p_current uuid)
returns void
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_active boolean;
begin
  if p_category_id is null then
    return;
  end if;
  select c.is_active into v_active from public.product_categories c where c.id = p_category_id;
  if not found then
    raise exception 'TREEMERCE_CATEGORY_NOT_FOUND: カテゴリが見つかりません' using errcode = '22023';
  end if;
  if not v_active and p_category_id is distinct from p_current then
    raise exception 'TREEMERCE_CATEGORY_INACTIVE: 無効なカテゴリは選べません' using errcode = '22023';
  end if;
end;
$fn$;

-- ============================================================================
-- 2. product_submissions にカテゴリを追加し、確定前の申請を移す
-- ============================================================================

alter table public.product_submissions
  add column category_id uuid references public.product_categories (id) on delete restrict,
  alter column category drop not null,
  alter column category drop default;

create index product_submissions_category_idx on public.product_submissions (category_id);

comment on column public.product_submissions.category is
  '旧列挙型。category_id から自動で写す (新カテゴリに対応がなければ NULL)。確定済みの古い申請はこの値で読み替える。';

-- 確定前の申請だけを埋める (確定済みの申請は変更できない。DB 管理者の内容修正としてガードが許可する範囲)
update public.product_submissions s
set category_id = app.category_id_for_legacy(s.category)
where s.status in ('draft', 'submitted', 'returned')
  and s.category_id is null
  and s.category is not null;

alter table public.product_submissions
  add constraint product_submissions_category_when_submitted check (
    status in ('draft', 'withdrawn') or category_id is not null or category is not null
  );

-- category_id ⇔ 旧列挙型 (変更された側を正とする。ガードより先に動くよう名前を a_ で始める)
create or replace function app.sync_submission_category()
returns trigger
language plpgsql
security definer
set search_path = public, app, pg_temp
as $fn$
begin
  if (tg_op = 'INSERT' and new.category_id is not null)
     or (tg_op = 'UPDATE' and new.category_id is distinct from old.category_id) then
    new.category := (select c.legacy_code from public.product_categories c where c.id = new.category_id);
  elsif (tg_op = 'INSERT' and new.category is not null)
     or (tg_op = 'UPDATE' and new.category is distinct from old.category) then
    new.category_id := app.category_id_for_legacy(new.category);
  end if;
  return new;
end;
$fn$;

create trigger product_submissions_a_sync_category
  before insert or update on public.product_submissions
  for each row execute function app.sync_submission_category();

-- ============================================================================
-- 3. 申請の内容の比較・返却・監査にカテゴリを含める (0017 / 0018 / 0021 を置き換え)
-- ============================================================================

create or replace function app.submission_content_changed(o public.product_submissions, n public.product_submissions)
returns boolean
language sql
immutable
as $fn$
  select o.name                          is distinct from n.name
      or o.category                      is distinct from n.category
      or o.category_id                   is distinct from n.category_id
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

create or replace function app.submission_changed_fields(o public.product_submissions, n public.product_submissions)
returns jsonb
language sql
immutable
as $fn$
  select coalesce(jsonb_agg(f), '[]'::jsonb)
  from unnest(array[
    case when o.name                          is distinct from n.name then 'name' end,
    case when o.category                      is distinct from n.category
           or o.category_id                   is distinct from n.category_id then 'category' end,
    case when o.description                   is distinct from n.description then 'description' end,
    case when o.desired_price                 is distinct from n.desired_price then 'desired_price' end,
    case when o.expected_wholesale_price      is distinct from n.expected_wholesale_price then 'expected_wholesale_price' end,
    case when o.content_volume                is distinct from n.content_volume then 'content_volume' end,
    case when o.ingredients                   is distinct from n.ingredients then 'ingredients' end,
    case when o.best_before_note              is distinct from n.best_before_note then 'best_before_note' end,
    case when o.producer_name                 is distinct from n.producer_name then 'producer_name' end,
    case when o.producer_origin               is distinct from n.producer_origin then 'producer_origin' end,
    case when o.producer_ship_from_prefecture is distinct from n.producer_ship_from_prefecture then 'producer_ship_from_prefecture' end,
    case when o.producer_ship_lead_time       is distinct from n.producer_ship_lead_time then 'producer_ship_lead_time' end,
    case when o.producer_contact_name  is distinct from n.producer_contact_name
           or o.producer_contact_phone is distinct from n.producer_contact_phone
           or o.producer_contact_email is distinct from n.producer_contact_email then 'producer_contact' end
  ]) f
  where f is not null;
$fn$;

-- 返却用 (本人 / super_admin にのみ返す)。カテゴリ名を引くため STABLE にする。
create or replace function app.submission_json(s public.product_submissions, p_with_contact boolean)
returns jsonb
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select jsonb_build_object(
    'id',                            s.id,
    'submission_no',                 s.submission_no,
    'status',                        s.status,
    'revision',                      s.revision,
    'created_via',                   s.created_via,
    'name',                          s.name,
    'category',                      s.category,
    'category_id',                   coalesce(s.category_id, app.category_id_for_legacy(s.category)),
    'category_name',                 app.category_name_for(s.category_id, s.category),
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

-- 監査ログ用 (連絡先は値を出さない)。カテゴリは ID と名前のみ。
create or replace function app.submission_audit_state(s public.product_submissions)
returns jsonb
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select jsonb_build_object(
    'submission_no',          s.submission_no,
    'agent_id',               s.agent_id,
    'created_via',            s.created_via,
    'status',                 s.status,
    'revision',               s.revision,
    'name',                   s.name,
    'category',               s.category,
    'category_id',            s.category_id,
    'category_name',          app.category_name_for(s.category_id, s.category),
    'desired_price',          s.desired_price,
    'producer_name',          s.producer_name,
    'has_producer_contact',   (s.producer_contact_name is not null or s.producer_contact_phone is not null
                               or s.producer_contact_email is not null)
  );
$fn$;

-- ============================================================================
-- 4. 代理店: 申請の作成・保存 (0018 を置き換え。p_category_id を追加)
-- ----------------------------------------------------------------------------
-- p_category_id を優先し、なければ旧列挙型 p_category を読み替える (画面の更新前の互換)。
-- どちらも NULL ならカテゴリ未選択 (下書きは可。申請時に必須)。
-- ============================================================================

drop function public.treemerce_save_my_submission(
  uuid, text, public.product_category, text, numeric, numeric, text, text, text,
  text, text, text, text, text, text, text);

create function public.treemerce_save_my_submission(
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
  v_self   uuid := app.current_agent_id();
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
begin
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店アカウントが必要です' using errcode = '42501';
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
    perform app.require_assignable_category(v_cat, null);

    perform set_config('app.submission_ctx', 'submission_agent', true);

    insert into public.product_submissions
      (agent_id, name, category_id, description, desired_price, expected_wholesale_price,
       content_volume, ingredients, best_before_note,
       producer_name, producer_origin, producer_ship_from_prefecture, producer_ship_lead_time,
       producer_contact_name, producer_contact_phone, producer_contact_email, created_by)
    values
      (v_self, v_name, v_cat, v_desc, p_desired_price, p_expected_wholesale_price,
       v_volume, v_ingr, v_best,
       v_p_name, v_origin, v_pref, v_lead,
       v_c_name, v_c_tel, v_c_mail, v_uid)
    returning * into v_after;

    perform set_config('app.submission_ctx', '', true);

    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (v_uid, 'agent', 'submission.create', 'product_submissions', v_after.id,
            null, app.submission_audit_state(v_after), null);
  else
    v_before := app.lock_my_submission(p_submission_id);
    if v_before.status not in ('draft', 'returned') then
      raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 申請中・確定済みの申請は編集できません'
        using errcode = '22023';
    end if;
    perform app.require_assignable_category(v_cat, v_before.category_id);

    perform set_config('app.submission_ctx', 'submission_agent', true);

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
      values (v_uid, 'agent', 'submission.update', 'product_submissions', v_after.id,
              app.submission_audit_state(v_before),
              app.submission_audit_state(v_after)
                || jsonb_build_object('changed_fields', app.submission_changed_fields(v_before, v_after)),
              null);
    end if;
  end if;

  return app.submission_json(v_after, true)
         || jsonb_build_object('images', app.submission_images_json(v_after.id));
end;
$fn$;

-- ============================================================================
-- 5. 代理店: 申請・再申請 (0018 を置き換え。カテゴリを必須項目に追加)
-- ============================================================================

create or replace function public.treemerce_submit_my_submission(p_submission_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid     uuid := auth.uid();
  v_before  public.product_submissions%rowtype;
  v_after   public.product_submissions%rowtype;
  v_missing text[];
begin
  v_before := app.lock_my_submission(p_submission_id);
  if v_before.status not in ('draft', 'returned') then
    raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: この申請は申請できる状態ではありません'
      using errcode = '22023';
  end if;

  v_missing := app.submission_missing_fields(v_before);
  if cardinality(v_missing) > 0 then
    raise exception 'TREEMERCE_INVALID_INPUT: 未入力の項目があります: %', array_to_string(v_missing, '、')
      using errcode = '22023';
  end if;

  perform set_config('app.submission_ctx', 'submission_agent', true);

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
          v_uid, 'agent');

  perform set_config('app.submission_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, 'agent',
          case when v_before.status = 'returned' then 'submission.resubmit' else 'submission.submit' end,
          'product_submissions', v_after.id,
          app.submission_audit_state(v_before), app.submission_audit_state(v_after), null);

  return app.submission_json(v_after, true)
         || jsonb_build_object('images', app.submission_images_json(v_after.id));
end;
$fn$;

-- 申請時に必須の項目 (本人の申請と運営の代行で共通)。カテゴリは有効なものに限る。
create or replace function app.submission_missing_fields(s public.product_submissions)
returns text[]
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select array_remove(array[
    case when s.category_id is null
           or not exists (select 1 from public.product_categories c where c.id = s.category_id and c.is_active)
         then 'カテゴリ' end,
    case when s.description is null then '説明' end,
    case when s.desired_price is null then '希望販売価格' end,
    case when s.content_volume is null then '内容量' end,
    case when s.producer_name is null then '生産者名' end,
    case when s.producer_origin is null then '産地' end,
    case when s.producer_ship_from_prefecture is null then '発送元の都道府県' end,
    case when s.producer_ship_lead_time is null then '発送目安' end,
    case when s.producer_contact_phone is null and s.producer_contact_email is null
         then '生産者の連絡先 (電話またはメール)' end
  ], null);
$fn$;

-- ============================================================================
-- 6. super_admin: 代行の作成・保存 (0021 を置き換え。p_category_id を追加)
-- ============================================================================

drop function public.treemerce_admin_save_proxy_submission(
  uuid, uuid, text, public.product_category, text, numeric, numeric, text, text, text,
  text, text, text, text, text, text, text, text);

create function public.treemerce_admin_save_proxy_submission(
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
      raise exception 'TREEMERCE_INVALID_INPUT: 代行する代理店を指定してください' using errcode = '22023';
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
-- 7. super_admin: 代行の申請・再申請 (0021 を置き換え。必須項目の確認を共通化)
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

  v_missing := app.submission_missing_fields(v_before);
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
-- 8. 一覧 (本人・super_admin) にカテゴリを含める (0021 を置き換え)
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
             'category_id',          coalesce(s.category_id, app.category_id_for_legacy(s.category)),
             'category_name',        app.category_name_for(s.category_id, s.category),
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

drop function public.treemerce_admin_list_submissions(public.submission_status, uuid);

create function public.treemerce_admin_list_submissions(
  p_status      public.submission_status default null,
  p_agent_id    uuid                     default null,
  p_category_id uuid                     default null
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
             'category_id',        coalesce(s.category_id, app.category_id_for_legacy(s.category)),
             'category_name',      app.category_name_for(s.category_id, s.category),
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
      and (p_category_id is null
           or coalesce(s.category_id, app.category_id_for_legacy(s.category)) = p_category_id)
  ), '[]'::jsonb);
end;
$fn$;

-- ============================================================================
-- 9. super_admin: 承認 (0021 を置き換え。p_category_id を追加)
-- ----------------------------------------------------------------------------
-- 作る商品のカテゴリ: p_category_id → p_category (旧列挙型の読み替え) → 申請のカテゴリ。
-- 有効なカテゴリに限る。商品は従来どおり在庫 0・非公開・物品で作る。
-- ============================================================================

drop function public.treemerce_admin_approve_submission(
  uuid, uuid, text, numeric, public.product_category, text);

create function public.treemerce_admin_approve_submission(
  p_submission_id uuid,
  p_producer_id   uuid                    default null,
  p_product_name  text                    default null,
  p_price         numeric                 default null,
  p_category      public.product_category default null,
  p_reason        text                    default null,
  p_category_id   uuid                    default null
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
  v_cat      uuid;
  v_active   boolean;
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

  -- 商品のカテゴリ (有効なカテゴリに限る)
  v_cat := coalesce(p_category_id, app.category_id_for_legacy(p_category),
                    v_before.category_id, app.category_id_for_legacy(v_before.category));
  select c.is_active into v_active from public.product_categories c where c.id = v_cat;
  if not found then
    raise exception 'TREEMERCE_CATEGORY_NOT_FOUND: 商品のカテゴリを選択してください' using errcode = '22023';
  end if;
  if not v_active then
    raise exception 'TREEMERCE_CATEGORY_INACTIVE: 無効なカテゴリは選べません。商品のカテゴリを選び直してください'
      using errcode = '22023';
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
    (name, description, category_id, price, stock, sales_status, is_published, created_by,
     producer_id, content_volume, ingredients, best_before_note)
  values
    (v_name, v_before.description, v_cat, v_price, 0, 'unpublished', false, v_uid,
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
            'product_category_id', v_cat,
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
-- 10. 客層分析 (0013 を置き換え。購入カテゴリだけを新カテゴリで集計する)
-- ============================================================================

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
  paid_lines as (
    -- 購入カテゴリ: 明細の注文時点のカテゴリ → なければ旧列挙型を新カテゴリへ読み替え (同じ集計単位)
    select p.customer_id, app.category_id_for_legacy(p.product_category) as category_id, p.amount
    from public.purchases p
    join base b on b.id = p.customer_id
    where p.status = 'completed'
      and (v_from is null or p.purchased_at >= v_from)
    union all
    select o.customer_id,
           coalesce(oi.product_category_id, app.category_id_for_legacy(oi.product_category)) as category_id,
           oi.amount
    from public.orders o
    join public.order_items oi on oi.order_id = o.id
    join base b on b.id = o.customer_id
    where o.status in ('payment_confirmed', 'shipped', 'completed')
      and (v_from is null or o.ordered_at >= v_from)
  ),
  per_customer as (
    select customer_id, sum(amount) as spent from paid_lines group by customer_id
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
    -- 購入者の人数で数える (明細件数ではない)。集計単位はカテゴリ、キーは今のカテゴリ名。
    select jsonb_agg(jsonb_build_object('key', coalesce(c.name, '未分類'), 'count', t.n)) as buckets
    from (select category_id, count(distinct customer_id)::int as n from paid_lines group by 1) t
    left join public.product_categories c on c.id = t.category_id
  ),
  agg_band as (
    select jsonb_agg(jsonb_build_object('key', band, 'count', n)) as buckets
    from (
      select case
               when spent < 10000  then 'lt_10k'
               when spent < 30000  then '10k_30k'
               when spent < 50000  then '30k_50k'
               when spent < 100000 then '50k_100k'
               else 'gte_100k'
             end as band,
             count(*)::int as n
      from per_customer
      group by 1
    ) t
  )
  select jsonb_build_object(
    'scope',                case when v_scope.is_all then 'all' else 'subtree' end,
    'root_agent_id',        v_scope.root_id,
    'period',               p_period,
    'k_threshold',          v_k,
    'total_customers',      (select count(*)::int from base),
    'scope_agent_count',    (select count(*)::int from scope),
    'purchasing_customers', (select count(*)::int from per_customer),
    'total_sales',          case when (select count(*) from per_customer) >= v_k
                                 then (select coalesce(sum(spent), 0) from per_customer)
                                 else null end,
    'age_group',            app.apply_k_anonymity((select buckets from agg_age), v_k),
    'gender',               app.apply_k_anonymity((select buckets from agg_gender), v_k),
    'prefecture',           app.apply_k_anonymity((select buckets from agg_pref), v_k),
    'customer_type',        app.apply_k_anonymity((select buckets from agg_type), v_k),
    'product_category',     app.apply_k_anonymity((select buckets from agg_cat), v_k),
    'amount_band',          app.apply_k_anonymity((select buckets from agg_band), v_k),
    'generated_at',         now()
  ) into v_result;

  return v_result;
end;
$fn$;

comment on function public.treemerce_customer_demographics(uuid, text) is
  'STEP6 客層分析。読み取り専用。購入カテゴリは新カテゴリ (旧列挙型は読み替え) ごとの購入者の人数、'
  '金額帯は顧客ごとの合計で集計 (入金確認済み以降の注文と完了済み購入のみ)。n<5 は丸める。';

-- ============================================================================
-- 11. GRANT
-- ============================================================================

revoke all on function app.category_name_for(uuid, public.product_category)     from public, anon, authenticated;
revoke all on function app.require_assignable_category(uuid, uuid)              from public, anon, authenticated;
revoke all on function app.sync_submission_category()                           from public, anon, authenticated;
revoke all on function app.submission_content_changed(public.product_submissions, public.product_submissions)
  from public, anon, authenticated;
revoke all on function app.submission_changed_fields(public.product_submissions, public.product_submissions)
  from public, anon, authenticated;
revoke all on function app.submission_json(public.product_submissions, boolean)  from public, anon, authenticated;
revoke all on function app.submission_audit_state(public.product_submissions)    from public, anon, authenticated;
revoke all on function app.submission_missing_fields(public.product_submissions) from public, anon, authenticated;

revoke all on function public.treemerce_save_my_submission(
  uuid, text, public.product_category, text, numeric, numeric, text, text, text,
  text, text, text, text, text, text, text, uuid) from public, anon, authenticated;
revoke all on function public.treemerce_submit_my_submission(uuid)            from public, anon, authenticated;
revoke all on function public.treemerce_admin_save_proxy_submission(
  uuid, uuid, text, public.product_category, text, numeric, numeric, text, text, text,
  text, text, text, text, text, text, text, text, uuid) from public, anon, authenticated;
revoke all on function public.treemerce_admin_submit_proxy_submission(uuid)   from public, anon, authenticated;
revoke all on function public.treemerce_my_submissions()                      from public, anon, authenticated;
revoke all on function public.treemerce_admin_list_submissions(public.submission_status, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_approve_submission(
  uuid, uuid, text, numeric, public.product_category, text, uuid) from public, anon, authenticated;
revoke all on function public.treemerce_customer_demographics(uuid, text)     from public, anon, authenticated;

grant execute on function public.treemerce_save_my_submission(
  uuid, text, public.product_category, text, numeric, numeric, text, text, text,
  text, text, text, text, text, text, text, uuid) to authenticated;
grant execute on function public.treemerce_submit_my_submission(uuid)            to authenticated;
grant execute on function public.treemerce_admin_save_proxy_submission(
  uuid, uuid, text, public.product_category, text, numeric, numeric, text, text, text,
  text, text, text, text, text, text, text, text, uuid) to authenticated;
grant execute on function public.treemerce_admin_submit_proxy_submission(uuid)   to authenticated;
grant execute on function public.treemerce_my_submissions()                      to authenticated;
grant execute on function public.treemerce_admin_list_submissions(public.submission_status, uuid, uuid)
  to authenticated;
grant execute on function public.treemerce_admin_approve_submission(
  uuid, uuid, text, numeric, public.product_category, text, uuid) to authenticated;
grant execute on function public.treemerce_customer_demographics(uuid, text)     to authenticated;

commit;
