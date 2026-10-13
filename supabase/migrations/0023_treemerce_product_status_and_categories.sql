-- ============================================================================
-- TREEMERCE : 0023_treemerce_product_status_and_categories.sql
-- 商品のカテゴリ (0022 のマスタ)・販売状態 (非公開/準備中/公開中)・オブザーバー特典付きの印・
-- 物品/サービス。注文受付とショップ一覧を作り直す。
-- ----------------------------------------------------------------------------
-- products に追加する列
--   category_id          : product_categories (必須)。既存商品は旧列挙型から移す。
--                          五次元結晶 (旧 health) は「五次元結晶」、奉献漬 (旧 food) は「食品・飲料」へ。
--   sales_status         : unpublished (非公開) / preparing (準備中) / on_sale (公開中)。
--                          既存の is_published = true は on_sale、false は unpublished。
--   item_kind            : goods (物品) / service (サービス)。
--   has_observer_benefit : オブザーバー特典付きの印。
--   product_type_label   : 商品の種類 (例: はちみつ梅)。name_kana : 読み仮名。
--   placeholder_key      : 画像がないときに表示するイラストの種類。
--   price                : NULL を許可する。公開中は必須。準備中は運営だけが見られる予定価格として入力してよい
--                          (準備中は RLS で代理店から見えず、ショップ・公開 RPC は価格を返さない)。
--
-- 状態の整合 (経路を問わない)
--   * is_published は「sales_status = 'on_sale'」と常に一致する (CHECK)。今ある RLS・注文受付・
--     0017 の公開ガードと監査はこの列を見るため、そのまま働く。
--     旧来の書き方 (is_published だけ / 旧列挙型 category だけを書く) も、トリガが
--     sales_status / category_id に読み替えて整合させる (旧 RPC・承認処理の互換のため)。
--   * サービスは公開中 (注文可能) にできない (予約の仕組みができるまで。CHECK)。準備中としての表示は可。
--   * 公開中は価格が必須 (CHECK)。
--
-- 注文受付 (treemerce_place_order) の変更
--   * 準備中・非公開・サービスの商品は「お取り扱いできません」で拒否する (中立の文言は従来どおり)。
--   * 明細に注文時点のカテゴリ (product_category_id / product_category_name) を写す。
--     旧列挙型の product_category は 0024 まで従来どおり写す (新カテゴリに対応がなければ other)。
--
-- ショップ一覧 (treemerce_shop_products) の変更
--   * p_include_preparing (既定 false) を追加。false のときは従来どおり公開中だけを返す
--     (画面の更新前に準備中が「0 円」で表示されないため)。true で準備中も返す (価格・在庫は返さない)。
--   * カテゴリ ID・名前・販売状態・注文可否・物品/サービス・商品の種類・読み仮名・イラストの種類・
--     オブザーバー特典付きの印を返す。サービスは発送元・発送目安を返さない。
--
-- 商品の登録・編集の新しい入口 : treemerce_admin_save_product (super_admin)
--   旧 treemerce_admin_upsert_product は、画面の更新まで互換のため残す (後の migration で削除する)。
--
-- 監査ログ
--   product.create / product.update            : 登録・編集 (変更前後の全体)
--   product.publish / product.prepare / product.unpublish : 販売状態の変更 (トリガで経路を問わず記録)
--   product.migrate_category                   : この migration でのカテゴリの移行 (db_admin)
--   category.deactivate                        : 使っていない旧カテゴリの無効化 (db_admin)
--
-- 絶対原則との対応
--   原則3・4 : 招待経路・顧客の担当・注文の帰属は参照も変更もしない (注文受付の帰属の決め方は従来どおり)。
--   原則5・6 : ショップの応答に担当代理店・顧客の情報は含めない。注文拒否の文言は中立のまま。
--   派生     : 客層分析は 0024 で新カテゴリに切り替える (n<5 の丸めは維持)。
-- ============================================================================

begin;

-- ============================================================================
-- 1. 列挙型
-- ============================================================================

create type public.product_sales_status as enum ('unpublished', 'preparing', 'on_sale');
comment on type public.product_sales_status is
  'unpublished=非公開 / preparing=準備中 (価格未定・注文不可で表示) / on_sale=公開中 (注文可)';

create type public.product_item_kind as enum ('goods', 'service');
comment on type public.product_item_kind is 'goods=物品 / service=サービス (施術など。発送情報を持たない)';

-- ============================================================================
-- 2. products に列を追加し、既存の商品を移す
-- ============================================================================

alter table public.products
  add column category_id          uuid references public.product_categories (id) on delete restrict,
  add column sales_status         public.product_sales_status not null default 'unpublished',
  add column item_kind            public.product_item_kind not null default 'goods',
  add column has_observer_benefit boolean not null default false,
  add column product_type_label   text,
  add column name_kana            text,
  add column placeholder_key      text,
  alter column price drop not null;

update public.products set sales_status = 'on_sale' where is_published;

update public.products p
set category_id = coalesce(app.category_id_for_legacy(p.category),
                           (select c.id from public.product_categories c where c.code = 'other'));

-- 五次元結晶 (旧 health) は「五次元結晶」カテゴリへ (奉献漬は旧 food → 食品・飲料 で上の対応どおり)
update public.products p
set category_id = (select c.id from public.product_categories c where c.code = 'five_dimensional_crystal')
where p.name like '%五次元結晶%';

insert into public.admin_audit_logs
  (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
select null, 'db_admin', 'product.migrate_category', 'products', p.id,
       jsonb_build_object('category', p.category, 'is_published', p.is_published),
       jsonb_build_object('category_id', p.category_id, 'category_name', c.name, 'sales_status', p.sales_status),
       '0023: 商品カテゴリのマスタ化・販売状態の追加に伴う移行'
from public.products p
join public.product_categories c on c.id = p.category_id;

-- 旧列挙型の列も新カテゴリに合わせる (対応がなければ other)
update public.products p
set category = coalesce((select c.legacy_code from public.product_categories c where c.id = p.category_id), 'other')
where p.category is distinct from
      coalesce((select c.legacy_code from public.product_categories c where c.id = p.category_id), 'other');

alter table public.products
  alter column category_id set not null,
  add constraint products_status_matches_published check (is_published = (sales_status = 'on_sale')),
  add constraint products_price_required_on_sale check (sales_status <> 'on_sale' or price is not null),
  add constraint products_service_not_on_sale check (not (item_kind = 'service' and sales_status = 'on_sale')),
  add constraint products_type_label_length check (product_type_label is null or char_length(product_type_label) <= 100),
  add constraint products_name_kana_length check (name_kana is null or char_length(name_kana) <= 100),
  add constraint products_placeholder_key_format check (placeholder_key is null or placeholder_key ~ '^[a-z0-9-]{1,40}$');

comment on column public.products.price is
  '販売価格。公開中は必須。準備中は運営だけが見られる予定価格 (ショップ・公開 RPC には出さない)。';
comment on column public.products.is_published is
  'sales_status = on_sale と常に一致する (CHECK)。RLS・注文受付・公開ガードの互換のために残す。';
comment on column public.products.category is
  '旧列挙型。category_id から自動で写す (新カテゴリに対応がなければ other)。0024 以降で廃止予定。';

create index products_category_idx on public.products (category_id);
create index products_sales_status_idx on public.products (sales_status, sort_order, created_at);
create index products_observer_idx on public.products (sales_status) where has_observer_benefit;

-- ============================================================================
-- 3. 販売状態・カテゴリの整合 (BEFORE。公開ガードより先に動くよう名前を a_ で始める)
-- ----------------------------------------------------------------------------
-- 新しい書き方 (sales_status / category_id) と旧来の書き方 (is_published / category) のどちらでも
-- 整合させる。変更された側を正とする。
-- ============================================================================

create or replace function app.sync_product_status_and_category()
returns trigger
language plpgsql
security definer
set search_path = public, app, pg_temp
as $fn$
begin
  -- 販売状態 ⇔ is_published
  if tg_op = 'INSERT' then
    if new.is_published and new.sales_status = 'unpublished' then
      new.sales_status := 'on_sale';
    end if;
    new.is_published := (new.sales_status = 'on_sale');
  elsif new.sales_status is distinct from old.sales_status then
    new.is_published := (new.sales_status = 'on_sale');
  elsif new.is_published is distinct from old.is_published then
    new.sales_status := case when new.is_published then 'on_sale' else 'unpublished' end;
  end if;

  -- カテゴリ ⇔ 旧列挙型
  if new.category_id is null
     or (tg_op = 'UPDATE' and new.category_id is not distinct from old.category_id
         and new.category is distinct from old.category) then
    new.category_id := coalesce(app.category_id_for_legacy(new.category),
                                (select c.id from public.product_categories c where c.code = 'other'));
  end if;
  new.category := coalesce((select c.legacy_code from public.product_categories c where c.id = new.category_id),
                           'other');
  return new;
end;
$fn$;

create trigger products_a_sync_status_category
  before insert or update on public.products
  for each row execute function app.sync_product_status_and_category();

-- ============================================================================
-- 4. 持込み商品の公開ガード (0017 を置き換え)
-- ----------------------------------------------------------------------------
-- 持込み元のある商品を 非公開 → 準備中 / 公開中 にするには、申請が承認済みで、実行者が super_admin。
-- 公開中にするときは、さらに生産者が有効かつ仮の生産者でないこと (準備中は仮の生産者のままでよい)。
-- 非公開に戻すのは制限しない (緊急停止の経路を残す)。
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
  if new.sales_status = old.sales_status or new.sales_status = 'unpublished' then
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

  if new.sales_status = 'on_sale' then
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
  end if;

  return new;
end;
$fn$;

-- ============================================================================
-- 5. 販売状態の変更の監査 (0017 を置き換え。準備中を追加。経路を問わず記録する)
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
  if tg_op = 'UPDATE' and new.sales_status is not distinct from old.sales_status then
    return new;
  end if;
  if tg_op = 'INSERT' and new.sales_status = 'unpublished' then
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
    case new.sales_status
      when 'on_sale'   then 'product.publish'
      when 'preparing' then 'product.prepare'
      else 'product.unpublish' end,
    'products',
    new.id,
    case when tg_op = 'UPDATE'
         then jsonb_build_object('sales_status', old.sales_status, 'is_published', old.is_published)
         else null end,
    jsonb_build_object(
      'sales_status',  new.sales_status,
      'is_published',  new.is_published,
      'name',          new.name,
      'price',         new.price,
      'stock',         new.stock,
      'category_id',   new.category_id,
      'item_kind',     new.item_kind,
      'producer_id',   new.producer_id,
      'sourced',       v_submission_no is not null,
      'submission_no', v_submission_no),
    nullif(btrim(coalesce(current_setting('app.audit_reason', true), '')), '')
  );

  return new;
end;
$fn$;

drop trigger products_audit_published on public.products;
create trigger products_audit_published
  after insert or update of is_published, sales_status on public.products
  for each row execute function app.audit_product_published();

-- ============================================================================
-- 6. 使用中のカテゴリ (0022 の判定に中身を入れる) と、使っていない旧カテゴリの無効化
-- ----------------------------------------------------------------------------
-- 使用中 = 公開中・準備中の商品が使っている。
-- 旧カテゴリ (健康・美容・アパレル・デジタル・その他) は、商品にも確定前の申請にも使われていなければ無効にする。
-- ============================================================================

create or replace function app.product_category_in_use(p_category_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select exists (
    select 1 from public.products p
    where p.category_id = p_category_id and p.sales_status in ('preparing', 'on_sale')
  );
$fn$;

with deactivated as (
  update public.product_categories c
  set is_active = false
  where c.code in ('health', 'beauty', 'apparel', 'digital', 'other')
    and c.is_active
    and not exists (select 1 from public.products p where p.category_id = c.id)
    and not exists (select 1 from public.product_submissions s
                    where s.category = c.legacy_code and s.status in ('draft', 'submitted', 'returned'))
  returning c.id, c.code, c.name
)
insert into public.admin_audit_logs
  (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
select null, 'db_admin', 'category.deactivate', 'product_categories', d.id,
       jsonb_build_object('code', d.code, 'name', d.name, 'is_active', true),
       jsonb_build_object('code', d.code, 'name', d.name, 'is_active', false),
       '0023: 使われていない旧カテゴリを無効化'
from deactivated d;

-- ============================================================================
-- 7. 注文明細に注文時点のカテゴリを写す列を追加 (既存の明細は書き換えない)
-- ============================================================================

alter table public.order_items
  add column product_category_id   uuid references public.product_categories (id) on delete restrict,
  add column product_category_name text,
  add constraint order_items_category_snapshot check ((product_category_id is null) = (product_category_name is null));

comment on column public.order_items.product_category_name is
  '注文時点のカテゴリ名。カテゴリの名称を後で変えても変わらない。0023 より前の明細は NULL (旧列挙型で読み替える)。';

-- ============================================================================
-- 8. super_admin: 商品の登録・編集 (新しい入口)
-- ----------------------------------------------------------------------------
-- フォームの全項目で置き換える。p_producer_id が NULL なら、編集では現在の生産者、新規では仮の生産者。
--   * カテゴリ: 無効なカテゴリは新たに選べない (現在のカテゴリのままなら可)
--   * 価格: 公開中は必須。準備中は予定価格として任意 (画面・公開 RPC には出さない)
--   * サービス: 公開中にはできない (予約の仕組みができるまで)
-- ============================================================================

create or replace function public.treemerce_admin_save_product(
  p_product_id           uuid                         default null,
  p_name                 text                         default null,
  p_category_id          uuid                         default null,
  p_sales_status         public.product_sales_status  default 'unpublished',
  p_price                numeric                      default null,
  p_stock                integer                      default 0,
  p_item_kind            public.product_item_kind     default 'goods',
  p_has_observer_benefit boolean                      default false,
  p_product_type_label   text                         default null,
  p_name_kana            text                         default null,
  p_placeholder_key      text                         default null,
  p_description          text                         default null,
  p_image_path           text                         default null,
  p_sku                  text                         default null,
  p_sort_order           integer                      default 0,
  p_producer_id          uuid                         default null,
  p_content_volume       text                         default null,
  p_ingredients          text                         default null,
  p_best_before_note     text                         default null,
  p_reason               text                         default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid         uuid := auth.uid();
  v_role        text := coalesce(app.admin_role(), 'super_admin');
  v_before      public.products%rowtype;
  v_after       public.products%rowtype;
  v_name        text := nullif(btrim(coalesce(p_name, '')), '');
  v_image       text := nullif(btrim(coalesce(p_image_path, '')), '');
  v_type        text := nullif(btrim(coalesce(p_product_type_label, '')), '');
  v_kana        text := nullif(btrim(coalesce(p_name_kana, '')), '');
  v_ph_key      text := nullif(btrim(coalesce(p_placeholder_key, '')), '');
  v_reason      text := nullif(btrim(coalesce(p_reason, '')), '');
  v_status      public.product_sales_status := coalesce(p_sales_status, 'unpublished');
  v_kind        public.product_item_kind := coalesce(p_item_kind, 'goods');
  v_placeholder constant uuid := '00000000-0000-4000-8000-000000000001';
  v_producer    uuid;
  v_active      boolean;
  v_cat_active  boolean;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 商品の登録・編集は super_admin のみ実行できます'
      using errcode = '42501';
  end if;

  -- ---- 入力検証 ---------------------------------------------------------------
  if v_name is null or char_length(v_name) > 200 then
    raise exception 'TREEMERCE_INVALID_INPUT: 商品名は 1〜200 文字で入力してください' using errcode = '22023';
  end if;
  if p_price is not null and (p_price < 0 or p_price >= 100000000) then
    raise exception 'TREEMERCE_INVALID_INPUT: 価格は 0 円以上 1 億円未満で入力してください' using errcode = '22023';
  end if;
  if v_status = 'on_sale' and p_price is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 公開中にするには販売価格が必要です (価格が未定なら「準備中」にしてください)'
      using errcode = '22023';
  end if;
  if v_kind = 'service' and v_status = 'on_sale' then
    raise exception 'TREEMERCE_SERVICE_NOT_ORDERABLE: サービスは予約の仕組みができるまで公開 (注文可能) にできません。「準備中」で表示できます'
      using errcode = '22023';
  end if;
  if p_stock is null or p_stock < 0 or p_stock > 1000000 then
    raise exception 'TREEMERCE_INVALID_INPUT: 在庫は 0 以上で指定してください' using errcode = '22023';
  end if;
  if v_type is not null and char_length(v_type) > 100 then
    raise exception 'TREEMERCE_INVALID_INPUT: 商品の種類は 100 文字以内で入力してください' using errcode = '22023';
  end if;
  if v_kana is not null and char_length(v_kana) > 100 then
    raise exception 'TREEMERCE_INVALID_INPUT: 読み仮名は 100 文字以内で入力してください' using errcode = '22023';
  end if;
  if v_ph_key is not null and v_ph_key !~ '^[a-z0-9-]{1,40}$' then
    raise exception 'TREEMERCE_INVALID_INPUT: イラストの種類が不正です' using errcode = '22023';
  end if;
  -- 画像は Storage バケット product-images 内の products/ 配下のパスのみ
  if v_image is not null and (v_image !~ '^products/[A-Za-z0-9._/-]+$' or v_image like '%..%') then
    raise exception 'TREEMERCE_INVALID_INPUT: 画像パスが不正です' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'TREEMERCE_INVALID_INPUT: 理由は 500 文字以内で入力してください' using errcode = '22023';
  end if;

  if p_product_id is not null then
    select * into v_before from public.products where id = p_product_id for update;
    if not found then
      raise exception 'TREEMERCE_PRODUCT_NOT_FOUND: 商品が見つかりません' using errcode = '22023';
    end if;
  end if;

  -- カテゴリ (無効なカテゴリは、現在のカテゴリのままでなければ選べない)
  select c.is_active into v_cat_active from public.product_categories c where c.id = p_category_id;
  if not found then
    raise exception 'TREEMERCE_CATEGORY_NOT_FOUND: カテゴリを選択してください' using errcode = '22023';
  end if;
  if not v_cat_active and p_category_id is distinct from v_before.category_id then
    raise exception 'TREEMERCE_CATEGORY_INACTIVE: 無効なカテゴリは選べません' using errcode = '22023';
  end if;

  -- 生産者
  v_producer := coalesce(p_producer_id, v_before.producer_id, v_placeholder);
  select pr.is_active into v_active from public.producers pr where pr.id = v_producer;
  if not found then
    raise exception 'TREEMERCE_PRODUCER_NOT_FOUND: 生産者が見つかりません' using errcode = '22023';
  end if;
  if not v_active and v_producer is distinct from v_before.producer_id then
    raise exception 'TREEMERCE_PRODUCER_INACTIVE: 無効な生産者は選べません' using errcode = '22023';
  end if;

  perform set_config('app.audit_reason', coalesce(v_reason, ''), true);

  if p_product_id is null then
    insert into public.products
      (sku, name, description, category_id, sales_status, is_published, price, stock, item_kind,
       has_observer_benefit, product_type_label, name_kana, placeholder_key,
       image_path, sort_order, created_by, producer_id, content_volume, ingredients, best_before_note)
    values
      (nullif(btrim(coalesce(p_sku, '')), ''), v_name, nullif(btrim(coalesce(p_description, '')), ''),
       p_category_id, v_status, v_status = 'on_sale', p_price, p_stock, v_kind,
       coalesce(p_has_observer_benefit, false), v_type, v_kana, v_ph_key,
       v_image, coalesce(p_sort_order, 0), v_uid, v_producer,
       nullif(btrim(coalesce(p_content_volume, '')), ''),
       nullif(btrim(coalesce(p_ingredients, '')), ''),
       nullif(btrim(coalesce(p_best_before_note, '')), ''))
    returning * into v_after;

    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (v_uid, v_role, 'product.create', 'products', v_after.id, null, to_jsonb(v_after), v_reason);
  else
    update public.products
    set sku                  = nullif(btrim(coalesce(p_sku, '')), ''),
        name                 = v_name,
        description          = nullif(btrim(coalesce(p_description, '')), ''),
        category_id          = p_category_id,
        sales_status         = v_status,
        is_published         = (v_status = 'on_sale'),
        price                = p_price,
        stock                = p_stock,
        item_kind            = v_kind,
        has_observer_benefit = coalesce(p_has_observer_benefit, false),
        product_type_label   = v_type,
        name_kana            = v_kana,
        placeholder_key      = v_ph_key,
        image_path           = v_image,
        sort_order           = coalesce(p_sort_order, 0),
        producer_id          = v_producer,
        content_volume       = nullif(btrim(coalesce(p_content_volume, '')), ''),
        ingredients          = nullif(btrim(coalesce(p_ingredients, '')), ''),
        best_before_note     = nullif(btrim(coalesce(p_best_before_note, '')), '')
    where id = p_product_id
    returning * into v_after;

    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (v_uid, v_role, 'product.update', 'products', v_after.id,
            to_jsonb(v_before), to_jsonb(v_after), v_reason);
  end if;

  perform set_config('app.audit_reason', '', true);

  return to_jsonb(v_after);
end;
$fn$;

-- ============================================================================
-- 9. 公開商品一覧 (未ログイン可・読み取り専用) を作り直す
-- ----------------------------------------------------------------------------
-- p_include_preparing = false (既定) : 公開中のみ (従来どおり)
-- p_include_preparing = true         : 準備中も返す (価格・在庫は返さず、注文不可)
-- 連絡先・送り先メール・正確な在庫数・予定価格は決して返さない。
-- ============================================================================

drop function public.treemerce_shop_products(text, uuid);

create function public.treemerce_shop_products(
  p_agent_public_id   text,
  p_product_id        uuid    default null,
  p_include_preparing boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_settings public.shop_settings%rowtype;
begin
  if not exists (
    select 1 from public.agents
    where public_id = btrim(coalesce(p_agent_public_id, '')) and status = 'active'
  ) then
    return jsonb_build_object('valid', false);
  end if;

  select * into v_settings from public.shop_settings where id = 1;

  return jsonb_build_object(
    'valid',             true,
    'accepting_orders',  coalesce(v_settings.is_accepting_orders, false),
    'shipping_fee',      coalesce(v_settings.shipping_fee, 0),
    'seller_name',       v_settings.seller_name,
    'products', coalesce((
      select jsonb_agg(app.public_product_json(p, pr, c) order by c.sort_order, p.sort_order, p.created_at)
      from public.products p
      join public.producers pr on pr.id = p.producer_id
      join public.product_categories c on c.id = p.category_id
      where (p.sales_status = 'on_sale' or (p_include_preparing and p.sales_status = 'preparing'))
        and pr.is_active
        and (p_product_id is null or p.id = p_product_id)
    ), '[]'::jsonb)
  );
end;
$fn$;

-- 公開用の商品の形 (ショップ・オブザーバー特典付き製品一覧で共用。公開中・準備中の商品にだけ使う)
create or replace function app.public_product_json(
  p  public.products,
  pr public.producers,
  c  public.product_categories
)
returns jsonb
language sql
stable
as $fn$
  select jsonb_build_object(
    'id',                   p.id,
    'name',                 p.name,
    'name_kana',            p.name_kana,
    'product_type_label',   p.product_type_label,
    'description',          p.description,
    'category',             p.category,
    'category_id',          c.id,
    'category_code',        c.code,
    'category_name',        c.name,
    'sales_status',         p.sales_status,
    'orderable',            p.sales_status = 'on_sale',
    'item_kind',            p.item_kind,
    'has_observer_benefit', p.has_observer_benefit,
    -- 準備中は価格 (予定価格) も在庫も返さない
    'price',                case when p.sales_status = 'on_sale' then p.price end,
    'image_path',           p.image_path,
    'placeholder_key',      p.placeholder_key,
    'in_stock',             p.sales_status = 'on_sale' and p.stock > 0,
    'low_stock',            p.sales_status = 'on_sale' and p.stock between 1 and 5,
    'max_quantity',         case when p.sales_status = 'on_sale' then least(p.stock, 10) else 0 end,
    'content_volume',       p.content_volume,
    'ingredients',          p.ingredients,
    'best_before_note',     p.best_before_note,
    'producer', case when pr.is_placeholder then null
                     else jsonb_build_object(
                            'id',     pr.id,
                            'name',   pr.name,
                            'origin', pr.origin)
                          -- サービスは発送情報を返さない
                          || case when p.item_kind = 'service' then '{}'::jsonb
                                  else jsonb_build_object(
                                         'ship_from_prefecture', pr.ship_from_prefecture,
                                         'ship_lead_time',       pr.ship_lead_time) end end
  );
$fn$;

-- ============================================================================
-- 10. 注文受付を作り直す (0015 からの変更点だけ)
-- ----------------------------------------------------------------------------
--   (d) 公開中でない商品 (準備中・非公開) とサービスは「お取り扱いできません」で拒否
--   (e) 明細に注文時点のカテゴリ (ID・名前) を写す
-- 応答の形は 0015 と同じ (原則6: 新規/既存で同じ形。担当代理店は返さない)。
-- ============================================================================

create or replace function public.treemerce_place_order(
  p_agent_public_id  text,
  p_items            jsonb,
  p_full_name        text,
  p_ship_address     text,
  p_email            text default null,
  p_phone            text default null,
  p_ship_postal_code text default null,
  p_full_name_kana   text default null,
  p_age_group        public.customer_age_group default null,
  p_gender           public.customer_gender    default null,
  p_prefecture       text default null,
  p_customer_type    public.customer_kind      default 'individual',
  p_note             text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid         uuid := auth.uid();
  v_email       text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_phone       text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '');
  v_max_unpaid  constant integer := 3;
  v_unpaid      integer;
  v_link        public.agents%rowtype;
  v_settings    public.shop_settings%rowtype;
  v_customer_id uuid;
  v_master_name text;
  v_mismatch    boolean := false;
  v_assigned    uuid;
  v_reg         jsonb;
  v_line        record;
  v_product     public.products%rowtype;
  v_prod_active boolean;
  v_cat_name    text;
  v_lines       jsonb := '[]'::jsonb;
  v_subtotal    numeric(12, 2) := 0;
  v_order       public.orders%rowtype;
begin
  -- ---- 入力検証 ---------------------------------------------------------------
  if p_full_name is null or btrim(p_full_name) = '' then
    raise exception 'TREEMERCE_INVALID_INPUT: 氏名は必須です' using errcode = '22023';
  end if;
  if v_email is null and v_phone is null then
    raise exception 'TREEMERCE_IDENTIFIER_REQUIRED: メールアドレスまたは電話番号のいずれかが必要です'
      using errcode = '22023';
  end if;
  if p_ship_address is null or btrim(p_ship_address) = '' then
    raise exception 'TREEMERCE_INVALID_INPUT: お届け先住所は必須です' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 20 then
    raise exception 'TREEMERCE_INVALID_ITEMS: 商品は 1〜20 種類で指定してください' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) e
    where jsonb_typeof(e) <> 'object'
       or coalesce(e ->> 'product_id', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
       or coalesce(e ->> 'quantity', '') !~ '^[0-9]{1,3}$'
  ) then
    raise exception 'TREEMERCE_INVALID_ITEMS: 商品の指定が不正です' using errcode = '22023';
  end if;

  select * into v_link
  from public.agents
  where public_id = btrim(coalesce(p_agent_public_id, '')) and status = 'active';
  if not found then
    raise exception 'TREEMERCE_AGENT_NOT_FOUND: 紹介リンクが無効です' using errcode = '22023';
  end if;

  select * into v_settings from public.shop_settings where id = 1;
  if not found or not v_settings.is_accepting_orders then
    raise exception 'TREEMERCE_ORDERS_CLOSED: 現在ご注文を受け付けておりません' using errcode = '22023';
  end if;

  -- ---- 未入金注文の上限 (連絡先ごと。顧客マスタは参照しない) ------------------
  -- ロック順は常に email → 電話 (デッドロック回避)
  if v_email is not null then
    perform pg_advisory_xact_lock(hashtextextended('treemerce:unpaid:email:' || v_email, 0));
  end if;
  if v_phone is not null then
    perform pg_advisory_xact_lock(hashtextextended('treemerce:unpaid:phone:' || v_phone, 0));
  end if;

  select count(*)::int into v_unpaid
  from public.orders o
  where o.status = 'received'
    and ((v_email is not null and lower(btrim(o.contact_email)) = v_email)
      or (v_phone is not null
          and regexp_replace(coalesce(o.contact_phone, ''), '[^0-9]', '', 'g') = v_phone));

  if v_unpaid >= v_max_unpaid then
    raise exception 'TREEMERCE_ORDER_UNAVAILABLE: ご注文を受け付けられませんでした。運営事務局までお問い合わせください。'
      using errcode = '22023';
  end if;

  -- ---- 商品の確保 (行ロックで売り越しを防ぐ。デッドロック回避のため ID 順) --------
  for v_line in
    select (e ->> 'product_id')::uuid as product_id, sum((e ->> 'quantity')::int)::int as quantity
    from jsonb_array_elements(p_items) e
    group by 1
    order by 1
  loop
    if v_line.quantity < 1 or v_line.quantity > 99 then
      raise exception 'TREEMERCE_INVALID_ITEMS: 数量は 1〜99 で指定してください' using errcode = '22023';
    end if;

    select * into v_product from public.products where id = v_line.product_id for update;
    -- (d) 公開中のみ注文できる (準備中・非公開は不可)。サービスは注文できない。
    if not found or not v_product.is_published or v_product.sales_status <> 'on_sale'
       or v_product.item_kind <> 'goods' or v_product.price is null then
      raise exception 'TREEMERCE_PRODUCT_UNAVAILABLE: ご指定の商品は現在お取り扱いできません'
        using errcode = '22023';
    end if;

    -- 生産者が無効な商品は扱わない
    select pr.is_active into v_prod_active from public.producers pr where pr.id = v_product.producer_id;
    if not coalesce(v_prod_active, false) then
      raise exception 'TREEMERCE_PRODUCT_UNAVAILABLE: ご指定の商品は現在お取り扱いできません'
        using errcode = '22023';
    end if;

    if v_product.stock < v_line.quantity then
      raise exception 'TREEMERCE_OUT_OF_STOCK: 「%」の在庫が不足しています', v_product.name
        using errcode = '22023';
    end if;

    select c.name into v_cat_name from public.product_categories c where c.id = v_product.category_id;

    v_lines := v_lines || jsonb_build_object(
      'product_id',            v_product.id,
      'product_name',          v_product.name,
      'product_sku',           v_product.sku,
      'product_category',      v_product.category,
      'product_category_id',   v_product.category_id,
      'product_category_name', v_cat_name,
      'unit_price',            v_product.price,
      'quantity',              v_line.quantity,
      'amount',                v_product.price * v_line.quantity,
      'producer_id',           v_product.producer_id,
      'content_volume',        v_product.content_volume
    );
    v_subtotal := v_subtotal + v_product.price * v_line.quantity;
  end loop;

  -- ---- 顧客の解決 (原則7: 識別子で照合。email 一致を優先) ---------------------
  select c.id, c.full_name into v_customer_id, v_master_name
  from public.customers c
  where (v_email is not null and c.email_normalized = v_email)
     or (v_phone is not null and c.phone_normalized = v_phone)
  order by (v_email is not null and c.email_normalized = v_email) desc, c.created_at
  limit 1;

  if v_customer_id is null then
    -- 新規顧客: 既存の唯一の入口で登録し、担当をこのリンクの代理店で確定する
    v_reg := public.treemerce_register_customer(
      v_link.public_id, p_full_name, p_email, p_phone, p_full_name_kana,
      p_age_group, p_gender, p_prefecture, p_customer_type,
      p_ship_postal_code, p_ship_address);
    if v_reg ->> 'status' <> 'registered' then
      raise exception 'TREEMERCE_ORDER_UNAVAILABLE: ご注文を受け付けられませんでした。運営事務局までお問い合わせください。'
        using errcode = '22023';
    end if;

    select c.id into v_customer_id
    from public.customers c
    where (v_email is not null and c.email_normalized = v_email)
       or (v_phone is not null and c.phone_normalized = v_phone)
    order by c.created_at desc
    limit 1;
  else
    -- 既存顧客: マスタは上書きしない。氏名の不一致・識別子の食い違いは ADMIN 向けフラグのみ
    v_mismatch :=
         regexp_replace(lower(v_master_name), '\s', '', 'g')
           <> regexp_replace(lower(p_full_name), '\s', '', 'g')
      or exists (
           select 1 from public.customers c2
           where c2.id <> v_customer_id
             and ((v_email is not null and c2.email_normalized = v_email)
               or (v_phone is not null and c2.phone_normalized = v_phone))
         );
  end if;

  -- 原則4: 帰属は「現在の担当」。リンクの代理店ではない。
  select ca.assigned_agent_id into v_assigned
  from public.customer_assignments ca
  where ca.customer_id = v_customer_id and ca.status = 'active';
  if v_assigned is null then
    raise exception 'TREEMERCE_ORDER_UNAVAILABLE: ご注文を受け付けられませんでした。運営事務局までお問い合わせください。'
      using errcode = '22023';
  end if;

  -- ---- 書込み (認可コンテキスト内) --------------------------------------------
  perform set_config('app.commerce_ctx', 'place_order', true);

  insert into public.orders (
    customer_id, agent_id, referral_agent_id, status,
    subtotal, shipping_fee, total,
    ship_name, ship_postal_code, ship_address, ship_phone,
    contact_email, contact_phone, customer_note, identity_mismatch,
    payment_due_date
  ) values (
    v_customer_id, v_assigned, v_link.id, 'received',
    v_subtotal, v_settings.shipping_fee, v_subtotal + v_settings.shipping_fee,
    btrim(p_full_name), nullif(btrim(coalesce(p_ship_postal_code, '')), ''),
    btrim(p_ship_address), nullif(btrim(coalesce(p_phone, '')), ''),
    nullif(btrim(coalesce(p_email, '')), ''), nullif(btrim(coalesce(p_phone, '')), ''),
    nullif(btrim(coalesce(p_note, '')), ''), v_mismatch,
    (now() at time zone 'Asia/Tokyo')::date + v_settings.payment_due_days
  )
  returning * into v_order;

  -- 明細に注文時点の生産者・内容量・カテゴリを保存
  insert into public.order_items
    (order_id, product_id, product_name, product_sku, product_category,
     product_category_id, product_category_name, unit_price, quantity, amount,
     producer_id, product_content_volume)
  select v_order.id, x.product_id, x.product_name, x.product_sku, x.product_category,
         x.product_category_id, x.product_category_name, x.unit_price, x.quantity, x.amount,
         x.producer_id, x.content_volume
  from jsonb_to_recordset(v_lines) as x(
    product_id uuid, product_name text, product_sku text,
    product_category public.product_category, product_category_id uuid, product_category_name text,
    unit_price numeric, quantity integer, amount numeric,
    producer_id uuid, content_volume text);

  -- 生産者ごとの発送記録
  insert into public.order_shipments (order_id, producer_id, producer_name, status)
  select v_order.id, pr.id, pr.name, 'awaiting_payment'
  from public.producers pr
  where pr.id in (select x.producer_id from jsonb_to_recordset(v_lines) as x(producer_id uuid));

  update public.products p
  set stock = p.stock - x.quantity
  from jsonb_to_recordset(v_lines) as x(product_id uuid, quantity integer)
  where p.id = x.product_id;

  insert into public.order_status_history
    (order_id, from_status, to_status, reason, changed_by, changed_by_role)
  values (v_order.id, null, 'received', '注文受付', v_uid, 'customer');

  perform set_config('app.commerce_ctx', '', true);

  -- 通知: 担当代理店 (自分の担当顧客なので実名可) と運営
  insert into public.notifications (agent_id, category, title, body)
  select v_assigned, 'purchase', '担当顧客からご注文がありました',
         c.full_name || ' 様からのご注文 (注文番号 ' || v_order.order_no || ')'
  from public.customers c where c.id = v_customer_id;

  insert into public.notifications (for_admin, category, title, body)
  values (true, 'purchase', '新しい注文を受け付けました',
          '注文番号 ' || v_order.order_no || ' / 合計 ' || v_order.total::text || ' 円');

  -- 原則6: 新規/既存で同じ形。担当代理店・顧客ID・紹介元は返さない。
  return jsonb_build_object(
    'status',       'received',
    'order_no',     v_order.order_no,
    'ordered_at',   v_order.ordered_at,
    'subtotal',     v_order.subtotal,
    'shipping_fee', v_order.shipping_fee,
    'total',        v_order.total,
    'items', (
      select jsonb_agg(jsonb_build_object(
               'product_name', x.product_name,
               'unit_price',   x.unit_price,
               'quantity',     x.quantity,
               'amount',       x.amount) order by x.product_name)
      from jsonb_to_recordset(v_lines) as x(product_name text, unit_price numeric,
                                            quantity integer, amount numeric)
    ),
    'payment', jsonb_build_object(
      'method',              'bank_transfer',
      'due_date',            v_order.payment_due_date,
      'bank_name',           v_settings.bank_name,
      'bank_branch',         v_settings.bank_branch,
      'bank_account_type',   v_settings.bank_account_type,
      'bank_account_number', v_settings.bank_account_number,
      'bank_account_holder', v_settings.bank_account_holder
    )
  );
end;
$fn$;

-- ============================================================================
-- 11. GRANT
-- ============================================================================

revoke all on function app.sync_product_status_and_category()  from public, anon, authenticated;
revoke all on function app.guard_sourced_product_publish()      from public, anon, authenticated;
revoke all on function app.audit_product_published()            from public, anon, authenticated;
revoke all on function app.product_category_in_use(uuid)        from public, anon, authenticated;
revoke all on function app.public_product_json(public.products, public.producers, public.product_categories)
  from public, anon, authenticated;

revoke all on function public.treemerce_admin_save_product(
  uuid, text, uuid, public.product_sales_status, numeric, integer, public.product_item_kind, boolean,
  text, text, text, text, text, text, integer, uuid, text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_shop_products(text, uuid, boolean) from public, anon, authenticated;
revoke all on function public.treemerce_place_order(
  text, jsonb, text, text, text, text, text, text,
  public.customer_age_group, public.customer_gender, text, public.customer_kind, text)
  from public, anon, authenticated;

grant execute on function public.treemerce_admin_save_product(
  uuid, text, uuid, public.product_sales_status, numeric, integer, public.product_item_kind, boolean,
  text, text, text, text, text, text, integer, uuid, text, text, text, text)
  to authenticated;
grant execute on function public.treemerce_shop_products(text, uuid, boolean) to anon, authenticated;
grant execute on function public.treemerce_place_order(
  text, jsonb, text, text, text, text, text, text,
  public.customer_age_group, public.customer_gender, text, public.customer_kind, text)
  to anon, authenticated;

commit;
