-- ============================================================================
-- TREEMERCE : 0015_treemerce_producers_rpc.sql
-- 生産者マスタ・生産者直送 (STEP2: RPC)
-- ----------------------------------------------------------------------------
-- 実装の入口
--   生産者の登録・編集・無効化 : treemerce_admin_upsert_producer   (super_admin, 編集は理由必須)
--   生産者一覧 (連絡先を含む)  : treemerce_admin_list_producers    (super_admin, STABLE)
--   商品の登録・編集           : treemerce_admin_upsert_product    (引数を末尾に追加して作り直し)
--   公開商品一覧               : treemerce_shop_products           (生産者の公開項目を追加)
--   注文受付                   : treemerce_place_order             (生産者ごとの発送記録を作成)
--   ステータス変更             : treemerce_admin_set_order_status  (発送記録と連動)
--   注文詳細 (ADMIN)           : treemerce_admin_get_order         (発送記録を追加)
--   発送登録・訂正             : treemerce_admin_ship_shipment     (super_admin, 全発送で注文を発送済みに)
--   発送依頼書                 : treemerce_admin_shipment_request  (super_admin, STABLE)
--   発送依頼の記録             : treemerce_admin_record_shipment_request (super_admin)
--
-- 方針
--   * 発送記録の操作・生産者の変更はすべて admin_audit_logs に残す。
--     admin_audit_logs は support / admin も閲覧できるため、生産者の連絡先・
--     発送依頼の送り先は監査ログに値を書かず「設定あり / 変更あり」だけを記録する。
--   * 代理店には何も追加しない (発送記録・生産者の連絡先・依頼内容は見せない)。
--   * 仮の生産者「未設定（運営）」の発送記録は運営が自ら発送する扱いとし、
--     従来どおり注文ステータスの手動変更 (発送済み) で一括して発送済みにできる。
--     実在の生産者の発送記録は、発送登録 (treemerce_admin_ship_shipment) を経由しないと
--     発送済みにできない。
-- ============================================================================

begin;

-- ============================================================================
-- 0. 監査ログ用: 生産者の状態 (連絡先は値を出さない)
-- ============================================================================

create or replace function app.producer_audit_state(p public.producers)
returns jsonb
language sql
immutable
as $fn$
  select jsonb_build_object(
    'id',                   p.id,
    'name',                 p.name,
    'origin',               p.origin,
    'ship_from_prefecture', p.ship_from_prefecture,
    'ship_lead_time',       p.ship_lead_time,
    'is_active',            p.is_active,
    'has_notify_email',     p.notify_email is not null,
    'has_contact',          (p.contact_name is not null or p.contact_phone is not null
                             or p.contact_email is not null),
    'has_note',             p.note is not null
  );
$fn$;

revoke all on function app.producer_audit_state(public.producers) from public, anon, authenticated;

-- 発送記録の監査用の状態 (お届け先などの個人情報は含めない)
create or replace function app.shipment_audit_state(s public.order_shipments, p_order_no text)
returns jsonb
language sql
immutable
as $fn$
  select jsonb_build_object(
    'order_no',        p_order_no,
    'producer_id',     s.producer_id,
    'producer_name',   s.producer_name,
    'status',          s.status,
    'carrier',         s.carrier,
    'tracking_number', s.tracking_number,
    'shipped_on',      s.shipped_on,
    'request_channel', s.request_channel,
    'request_count',   s.request_count
  );
$fn$;

revoke all on function app.shipment_audit_state(public.order_shipments, text)
  from public, anon, authenticated;

-- ============================================================================
-- 1. 生産者の登録・編集・無効化 (super_admin)
-- ----------------------------------------------------------------------------
-- 新規は理由任意、編集 (無効化を含む) は理由必須。仮の生産者は編集できない。
-- 無効化すると、その生産者の商品は公開一覧から外れ、新規注文もできなくなる。
-- 入金済みで未発送の発送記録は残るので、応答の open_shipments で件数を返す。
-- ============================================================================

create or replace function public.treemerce_admin_upsert_producer(
  p_name                 text,
  p_origin               text,
  p_ship_from_prefecture text,
  p_ship_lead_time       text,
  p_notify_email         text    default null,
  p_contact_name         text    default null,
  p_contact_phone        text    default null,
  p_contact_email        text    default null,
  p_note                 text    default null,
  p_is_active            boolean default true,
  p_producer_id          uuid    default null,
  p_reason               text    default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid           uuid := auth.uid();
  v_role          text := coalesce(app.admin_role(), 'super_admin');
  v_before        public.producers%rowtype;
  v_after         public.producers%rowtype;
  v_name          text := nullif(btrim(coalesce(p_name, '')), '');
  v_origin        text := nullif(btrim(coalesce(p_origin, '')), '');
  v_pref          text := nullif(btrim(coalesce(p_ship_from_prefecture, '')), '');
  v_lead          text := nullif(btrim(coalesce(p_ship_lead_time, '')), '');
  v_notify        text := nullif(lower(btrim(coalesce(p_notify_email, ''))), '');
  v_c_name        text := nullif(btrim(coalesce(p_contact_name, '')), '');
  v_c_phone       text := nullif(btrim(coalesce(p_contact_phone, '')), '');
  v_c_email       text := nullif(lower(btrim(coalesce(p_contact_email, ''))), '');
  v_note          text := nullif(btrim(coalesce(p_note, '')), '');
  v_private_chg   boolean;
  v_open          integer := 0;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 生産者の登録・編集は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  if v_name is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 生産者名は必須です' using errcode = '22023';
  end if;
  if v_origin is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 産地は必須です' using errcode = '22023';
  end if;
  if v_pref is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 発送元の都道府県は必須です' using errcode = '22023';
  end if;
  if v_lead is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 発送目安は必須です' using errcode = '22023';
  end if;
  if v_notify is not null and v_notify !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'TREEMERCE_INVALID_INPUT: 発送依頼の送り先メールの形式が正しくありません'
      using errcode = '22023';
  end if;
  if v_c_email is not null and v_c_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'TREEMERCE_INVALID_INPUT: 連絡先メールの形式が正しくありません'
      using errcode = '22023';
  end if;
  if v_pref not in (
      '北海道', '青森県', '岩手県', '宮城県', '秋田県', '山形県', '福島県',
      '茨城県', '栃木県', '群馬県', '埼玉県', '千葉県', '東京都', '神奈川県',
      '新潟県', '富山県', '石川県', '福井県', '山梨県', '長野県', '岐阜県',
      '静岡県', '愛知県', '三重県', '滋賀県', '京都府', '大阪府', '兵庫県',
      '奈良県', '和歌山県', '鳥取県', '島根県', '岡山県', '広島県', '山口県',
      '徳島県', '香川県', '愛媛県', '高知県', '福岡県', '佐賀県', '長崎県',
      '熊本県', '大分県', '宮崎県', '鹿児島県', '沖縄県') then
    raise exception 'TREEMERCE_INVALID_INPUT: 発送元の都道府県が正しくありません' using errcode = '22023';
  end if;

  if p_producer_id is null then
    perform set_config('app.commerce_ctx', 'producer', true);

    insert into public.producers
      (name, origin, ship_from_prefecture, ship_lead_time, notify_email,
       contact_name, contact_phone, contact_email, note, is_active, created_by)
    values
      (v_name, v_origin, v_pref, v_lead, v_notify,
       v_c_name, v_c_phone, v_c_email, v_note, coalesce(p_is_active, true), v_uid)
    returning * into v_after;

    perform set_config('app.commerce_ctx', '', true);

    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (v_uid, v_role, 'producer.create', 'producers', v_after.id,
            null, app.producer_audit_state(v_after),
            nullif(btrim(coalesce(p_reason, '')), ''));
  else
    if p_reason is null or btrim(p_reason) = '' then
      raise exception 'TREEMERCE_REASON_REQUIRED: 変更理由は必須です' using errcode = '22023';
    end if;

    select * into v_before from public.producers where id = p_producer_id for update;
    if not found then
      raise exception 'TREEMERCE_PRODUCER_NOT_FOUND: 生産者が見つかりません' using errcode = '22023';
    end if;
    if v_before.is_placeholder then
      raise exception 'TREEMERCE_PRODUCER_PLACEHOLDER: 仮の生産者「未設定（運営）」は編集できません'
        using errcode = '22023';
    end if;

    perform set_config('app.commerce_ctx', 'producer', true);

    update public.producers
    set name                 = v_name,
        origin               = v_origin,
        ship_from_prefecture = v_pref,
        ship_lead_time       = v_lead,
        notify_email         = v_notify,
        contact_name         = v_c_name,
        contact_phone        = v_c_phone,
        contact_email        = v_c_email,
        note                 = v_note,
        is_active            = coalesce(p_is_active, true)
    where id = p_producer_id
    returning * into v_after;

    perform set_config('app.commerce_ctx', '', true);

    v_private_chg :=
         v_before.notify_email  is distinct from v_after.notify_email
      or v_before.contact_name  is distinct from v_after.contact_name
      or v_before.contact_phone is distinct from v_after.contact_phone
      or v_before.contact_email is distinct from v_after.contact_email
      or v_before.note          is distinct from v_after.note;

    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (v_uid, v_role,
            case when v_before.is_active and not v_after.is_active then 'producer.deactivate'
                 when not v_before.is_active and v_after.is_active then 'producer.activate'
                 else 'producer.update' end,
            'producers', v_after.id,
            app.producer_audit_state(v_before),
            app.producer_audit_state(v_after)
              || jsonb_build_object('private_fields_changed', v_private_chg),
            btrim(p_reason));
  end if;

  select count(*)::int into v_open
  from public.order_shipments s
  where s.producer_id = v_after.id
    and s.status in ('awaiting_payment', 'ready', 'requested');

  return to_jsonb(v_after) || jsonb_build_object('open_shipments', v_open);
end;
$fn$;

-- ============================================================================
-- 2. 生産者一覧 (super_admin。連絡先を含む。読み取り専用)
-- ============================================================================

create or replace function public.treemerce_admin_list_producers(p_producer_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 生産者の詳細は super_admin のみ参照できます'
      using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
             to_jsonb(pr) || jsonb_build_object(
               'product_count',   (select count(*) from public.products p where p.producer_id = pr.id),
               'published_count', (select count(*) from public.products p
                                   where p.producer_id = pr.id and p.is_published),
               'open_shipments',  (select count(*) from public.order_shipments s
                                   where s.producer_id = pr.id
                                     and s.status in ('awaiting_payment', 'ready', 'requested')))
             order by pr.is_placeholder desc, pr.is_active desc, pr.name)
    from public.producers pr
    where p_producer_id is null or pr.id = p_producer_id
  ), '[]'::jsonb);
end;
$fn$;

-- ============================================================================
-- 3. 商品の登録・編集 (super_admin) を作り直す
-- ----------------------------------------------------------------------------
-- 0011 の引数はそのまま、末尾に生産者・内容量・原材料・期限の目安を追加する。
--   p_producer_id      : 新規で NULL → 仮の生産者。編集で NULL → 変更しない。
--                        無効な生産者は新たに選べない (現在の生産者のままなら可)。
--   p_content_volume 他: NULL → 変更しない (新規は空)。空文字 → 空にする。
-- 引数が増えるため旧版は削除してから作り直す (呼び出しの曖昧さを避ける)。
-- ============================================================================

drop function if exists public.treemerce_admin_upsert_product(
  text, numeric, integer, boolean, public.product_category, text, text, text, integer, uuid, text);

create function public.treemerce_admin_upsert_product(
  p_name             text,
  p_price            numeric,
  p_stock            integer,
  p_is_published     boolean,
  p_category         public.product_category default 'other',
  p_description      text    default null,
  p_image_path       text    default null,
  p_sku              text    default null,
  p_sort_order       integer default 0,
  p_product_id       uuid    default null,
  p_reason           text    default null,
  p_producer_id      uuid    default null,
  p_content_volume   text    default null,
  p_ingredients      text    default null,
  p_best_before_note text    default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid         uuid := auth.uid();
  v_before      public.products%rowtype;
  v_after       public.products%rowtype;
  v_image       text := nullif(btrim(coalesce(p_image_path, '')), '');
  v_placeholder constant uuid := '00000000-0000-4000-8000-000000000001';
  v_producer    uuid;
  v_active      boolean;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 商品の登録・編集は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  if p_name is null or btrim(p_name) = '' then
    raise exception 'TREEMERCE_INVALID_INPUT: 商品名は必須です' using errcode = '22023';
  end if;
  if p_price is null or p_price < 0 then
    raise exception 'TREEMERCE_INVALID_INPUT: 価格は 0 以上で指定してください' using errcode = '22023';
  end if;
  if p_stock is null or p_stock < 0 then
    raise exception 'TREEMERCE_INVALID_INPUT: 在庫は 0 以上で指定してください' using errcode = '22023';
  end if;
  -- 画像は Storage バケット product-images 内の products/ 配下のパスのみ
  if v_image is not null and (v_image !~ '^products/[A-Za-z0-9._/-]+$' or v_image like '%..%') then
    raise exception 'TREEMERCE_INVALID_INPUT: 画像パスが不正です' using errcode = '22023';
  end if;

  if p_product_id is not null then
    select * into v_before from public.products where id = p_product_id for update;
    if not found then
      raise exception 'TREEMERCE_PRODUCT_NOT_FOUND: 商品が見つかりません' using errcode = '22023';
    end if;
  end if;

  -- 生産者の決定と検証
  v_producer := coalesce(p_producer_id, v_before.producer_id, v_placeholder);
  select pr.is_active into v_active from public.producers pr where pr.id = v_producer;
  if not found then
    raise exception 'TREEMERCE_PRODUCER_NOT_FOUND: 生産者が見つかりません' using errcode = '22023';
  end if;
  if not v_active and v_producer is distinct from v_before.producer_id then
    raise exception 'TREEMERCE_PRODUCER_INACTIVE: 無効な生産者は選べません' using errcode = '22023';
  end if;

  if p_product_id is null then
    insert into public.products
      (sku, name, description, category, price, stock, is_published, image_path, sort_order,
       created_by, producer_id, content_volume, ingredients, best_before_note)
    values
      (nullif(btrim(coalesce(p_sku, '')), ''), btrim(p_name),
       nullif(btrim(coalesce(p_description, '')), ''), coalesce(p_category, 'other'),
       p_price, p_stock, coalesce(p_is_published, false), v_image, coalesce(p_sort_order, 0),
       v_uid, v_producer,
       nullif(btrim(coalesce(p_content_volume, '')), ''),
       nullif(btrim(coalesce(p_ingredients, '')), ''),
       nullif(btrim(coalesce(p_best_before_note, '')), ''))
    returning * into v_after;

    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (v_uid, coalesce(app.admin_role(), 'super_admin'), 'product.create', 'products',
            v_after.id, null, to_jsonb(v_after), nullif(btrim(coalesce(p_reason, '')), ''));
  else
    update public.products
    set sku              = nullif(btrim(coalesce(p_sku, '')), ''),
        name             = btrim(p_name),
        description      = nullif(btrim(coalesce(p_description, '')), ''),
        category         = coalesce(p_category, 'other'),
        price            = p_price,
        stock            = p_stock,
        is_published     = coalesce(p_is_published, false),
        image_path       = v_image,
        sort_order       = coalesce(p_sort_order, 0),
        producer_id      = v_producer,
        content_volume   = case when p_content_volume is null then content_volume
                                else nullif(btrim(p_content_volume), '') end,
        ingredients      = case when p_ingredients is null then ingredients
                                else nullif(btrim(p_ingredients), '') end,
        best_before_note = case when p_best_before_note is null then best_before_note
                                else nullif(btrim(p_best_before_note), '') end
    where id = p_product_id
    returning * into v_after;

    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (v_uid, coalesce(app.admin_role(), 'super_admin'), 'product.update', 'products',
            v_after.id, to_jsonb(v_before), to_jsonb(v_after),
            nullif(btrim(coalesce(p_reason, '')), ''));
  end if;

  return to_jsonb(v_after);
end;
$fn$;

-- ============================================================================
-- 4. 公開商品一覧 (未ログイン可・読み取り専用) を作り直す
-- ----------------------------------------------------------------------------
-- 0013 からの変更点:
--   * 無効な生産者の商品は返さない
--   * 内容量・原材料・期限の目安、生産者の公開項目 (名前・産地・発送元・発送目安) を返す
--     (仮の生産者の場合 producer は null。連絡先・送り先メールは決して返さない)
--   * 販売者名 (運営) を返す
-- ============================================================================

create or replace function public.treemerce_shop_products(
  p_agent_public_id text,
  p_product_id      uuid default null
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
      select jsonb_agg(jsonb_build_object(
               'id',               p.id,
               'name',             p.name,
               'description',      p.description,
               'category',         p.category,
               'price',            p.price,
               'image_path',       p.image_path,
               'in_stock',         p.stock > 0,
               'low_stock',        p.stock between 1 and 5,
               'max_quantity',     least(p.stock, 10),
               'content_volume',   p.content_volume,
               'ingredients',      p.ingredients,
               'best_before_note', p.best_before_note,
               'producer', case when pr.is_placeholder then null
                                else jsonb_build_object(
                                       'id',                   pr.id,
                                       'name',                 pr.name,
                                       'origin',               pr.origin,
                                       'ship_from_prefecture', pr.ship_from_prefecture,
                                       'ship_lead_time',       pr.ship_lead_time) end
             ) order by p.sort_order, p.created_at)
      from public.products p
      join public.producers pr on pr.id = p.producer_id
      where p.is_published
        and pr.is_active
        and (p_product_id is null or p.id = p_product_id)
    ), '[]'::jsonb)
  );
end;
$fn$;

-- ============================================================================
-- 5. 注文受付を作り直す (生産者ごとの発送記録を作成)
-- ----------------------------------------------------------------------------
-- 0013 からの変更点だけ:
--   (a) 生産者が無効な商品は「お取り扱いできません」で拒否
--   (b) 明細に注文時点の producer_id / 内容量 を保存
--   (c) 生産者ごとに order_shipments を awaiting_payment で作成
-- 応答の形は 0013 と同じ (原則6: 新規/既存で同じ形。担当代理店は返さない)。
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
    if not found or not v_product.is_published then
      raise exception 'TREEMERCE_PRODUCT_UNAVAILABLE: ご指定の商品は現在お取り扱いできません'
        using errcode = '22023';
    end if;

    -- (a) 生産者が無効な商品は扱わない
    select pr.is_active into v_prod_active from public.producers pr where pr.id = v_product.producer_id;
    if not coalesce(v_prod_active, false) then
      raise exception 'TREEMERCE_PRODUCT_UNAVAILABLE: ご指定の商品は現在お取り扱いできません'
        using errcode = '22023';
    end if;

    if v_product.stock < v_line.quantity then
      raise exception 'TREEMERCE_OUT_OF_STOCK: 「%」の在庫が不足しています', v_product.name
        using errcode = '22023';
    end if;

    v_lines := v_lines || jsonb_build_object(
      'product_id',       v_product.id,
      'product_name',     v_product.name,
      'product_sku',      v_product.sku,
      'product_category', v_product.category,
      'unit_price',       v_product.price,
      'quantity',         v_line.quantity,
      'amount',           v_product.price * v_line.quantity,
      'producer_id',      v_product.producer_id,
      'content_volume',   v_product.content_volume
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

  -- (b) 明細に注文時点の生産者・内容量を保存
  insert into public.order_items
    (order_id, product_id, product_name, product_sku, product_category, unit_price, quantity, amount,
     producer_id, product_content_volume)
  select v_order.id, x.product_id, x.product_name, x.product_sku, x.product_category,
         x.unit_price, x.quantity, x.amount, x.producer_id, x.content_volume
  from jsonb_to_recordset(v_lines) as x(
    product_id uuid, product_name text, product_sku text,
    product_category public.product_category, unit_price numeric, quantity integer, amount numeric,
    producer_id uuid, content_volume text);

  -- (c) 生産者ごとの発送記録
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
-- 6. ステータス変更の共通処理 (内部専用) を作り直す: 発送記録と連動
-- ----------------------------------------------------------------------------
-- 0013 からの変更点:
--   * payment_confirmed : 発送記録 awaiting_payment → ready
--   * shipped           : 実在の生産者で未発送の発送記録が残っていれば拒否。
--                         仮の生産者の未発送分は「運営が発送した」として発送済みにする。
--   * cancelled         : 未発送の発送記録の分は常に在庫を戻し、発送記録を cancelled にする。
--                         発送済みの分は p_restock が true のときだけ戻す。
--                         発送記録の無い旧注文は従来どおり p_restock で全体を戻す。
-- 認可は呼び出し側で済ませてから呼ぶ。anon / authenticated には EXECUTE を与えない。
-- ============================================================================

create or replace function app.apply_order_status_change(
  p_order_id   uuid,
  p_status     public.order_status,
  p_reason     text,
  p_actor      uuid,
  p_actor_role text,
  p_restock    boolean,
  p_action     text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_before          public.orders%rowtype;
  v_after           public.orders%rowtype;
  v_restock         boolean := (p_status = 'cancelled' and coalesce(p_restock, false));
  v_has_shipments   boolean;
  v_restock_unshipd boolean := false;
  v_today           date := (now() at time zone 'Asia/Tokyo')::date;
begin
  select * into v_before from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'TREEMERCE_ORDER_NOT_FOUND: 注文が見つかりません' using errcode = '22023';
  end if;
  if v_before.status = p_status then
    raise exception 'TREEMERCE_NO_CHANGE: 既に同じステータスです' using errcode = '22023';
  end if;
  if not (
       (v_before.status = 'received'          and p_status in ('payment_confirmed', 'cancelled'))
    or (v_before.status = 'payment_confirmed' and p_status in ('shipped', 'cancelled'))
    or (v_before.status = 'shipped'           and p_status in ('completed', 'cancelled'))
  ) then
    raise exception 'TREEMERCE_INVALID_TRANSITION: % から % へは変更できません',
      v_before.status, p_status
      using errcode = '22023';
  end if;

  select exists (select 1 from public.order_shipments s where s.order_id = p_order_id)
    into v_has_shipments;

  -- 実在の生産者の発送は、発送登録 (送り状番号など) を経由しないと発送済みにできない
  if p_status = 'shipped' and exists (
       select 1
       from public.order_shipments s
       join public.producers pr on pr.id = s.producer_id
       where s.order_id = p_order_id
         and s.status not in ('shipped', 'cancelled')
         and not pr.is_placeholder
     ) then
    raise exception 'TREEMERCE_SHIPMENTS_PENDING: 未発送の生産者があります。生産者ごとの発送登録を完了してください'
      using errcode = '22023';
  end if;

  perform set_config('app.commerce_ctx', 'order_status', true);

  update public.orders
  set status       = p_status,
      paid_at      = case when p_status = 'payment_confirmed' then now() else paid_at end,
      shipped_at   = case when p_status = 'shipped'           then now() else shipped_at end,
      completed_at = case when p_status = 'completed'         then now() else completed_at end,
      cancelled_at = case when p_status = 'cancelled'         then now() else cancelled_at end
  where id = p_order_id
  returning * into v_after;

  if p_status = 'payment_confirmed' then
    update public.order_shipments
    set status = 'ready'
    where order_id = p_order_id and status = 'awaiting_payment';

  elsif p_status = 'shipped' then
    -- 仮の生産者 (運営が発送) の未発送分を発送済みにする
    update public.order_shipments s
    set status = 'shipped', shipped_on = coalesce(s.shipped_on, v_today)
    from public.producers pr
    where pr.id = s.producer_id
      and pr.is_placeholder
      and s.order_id = p_order_id
      and s.status not in ('shipped', 'cancelled');

  elsif p_status = 'cancelled' then
    if v_has_shipments then
      -- 発送記録の状態を見てから在庫を戻す (未発送分は常に、発送済み分は指定時のみ)
      select exists (
        select 1 from public.order_shipments s
        where s.order_id = p_order_id and s.status not in ('shipped', 'cancelled')
      ) into v_restock_unshipd;

      update public.products p
      set stock = p.stock + q.quantity
      from (
        select oi.product_id, sum(oi.quantity)::int as quantity
        from public.order_items oi
        join public.order_shipments s
          on s.order_id = oi.order_id and s.producer_id = oi.producer_id
        where oi.order_id = p_order_id
          and ((s.status not in ('shipped', 'cancelled'))
            or (s.status = 'shipped' and v_restock))
        group by oi.product_id
      ) q
      where p.id = q.product_id;

      update public.order_shipments
      set status = 'cancelled'
      where order_id = p_order_id and status not in ('shipped', 'cancelled');
    elsif v_restock then
      -- 旧注文 (発送記録なし): 従来どおり全体を戻す
      update public.products p
      set stock = p.stock + q.quantity
      from (
        select oi.product_id, sum(oi.quantity)::int as quantity
        from public.order_items oi
        where oi.order_id = p_order_id
        group by oi.product_id
      ) q
      where p.id = q.product_id;
    end if;
  end if;

  insert into public.order_status_history
    (order_id, from_status, to_status, reason, changed_by, changed_by_role)
  values (p_order_id, v_before.status, p_status, btrim(p_reason), p_actor, p_actor_role);

  perform set_config('app.commerce_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (p_actor, p_actor_role, p_action, 'orders', p_order_id,
          jsonb_build_object('order_no', v_before.order_no, 'status', v_before.status),
          jsonb_build_object('order_no', v_after.order_no, 'status', v_after.status,
                             'restocked', v_restock,
                             'restocked_unshipped', v_restock_unshipd),
          btrim(p_reason));

  return jsonb_build_object(
    'order_id',    v_after.id,
    'order_no',    v_after.order_no,
    'from_status', v_before.status,
    'status',      v_after.status,
    'restocked',   v_restock
  );
end;
$fn$;

revoke all on function app.apply_order_status_change(
  uuid, public.order_status, text, uuid, text, boolean, text)
  from public, anon, authenticated;

-- ============================================================================
-- 7. 注文ステータス変更 RPC (super_admin) を作り直す
-- ----------------------------------------------------------------------------
-- 0013 からの変更点: 一部の生産者が発送済みの payment_confirmed 注文をキャンセルする場合も、
-- 発送済み注文と同じく「発送済み分の在庫を戻すか (p_restock)」の指定を必須にする。
-- 発送済みへの手動変更の可否は共通処理 (6) で判定する。
-- ============================================================================

create or replace function public.treemerce_admin_set_order_status(
  p_order_id uuid,
  p_status   public.order_status,
  p_reason   text,
  p_restock  boolean default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_current         public.order_status;
  v_restock         boolean := false;
  v_partial_shipped boolean;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 注文ステータスの変更は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'TREEMERCE_REASON_REQUIRED: 変更理由は必須です' using errcode = '22023';
  end if;
  if p_status is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 変更後のステータスを指定してください' using errcode = '22023';
  end if;

  select o.status into v_current from public.orders o where o.id = p_order_id for update;
  if not found then
    raise exception 'TREEMERCE_ORDER_NOT_FOUND: 注文が見つかりません' using errcode = '22023';
  end if;

  if p_status = 'cancelled' then
    select exists (
      select 1 from public.order_shipments s
      where s.order_id = p_order_id and s.status = 'shipped'
    ) into v_partial_shipped;

    if v_current = 'shipped' or v_partial_shipped then
      if p_restock is null then
        raise exception 'TREEMERCE_RESTOCK_REQUIRED: 発送済みの商品を含む注文のキャンセルでは、発送済み分の在庫を戻すかどうか (p_restock) を指定してください'
          using errcode = '22023';
      end if;
      v_restock := p_restock;
    else
      v_restock := true;
    end if;
  end if;

  return app.apply_order_status_change(
    p_order_id, p_status, p_reason, auth.uid(),
    coalesce(app.admin_role(), 'super_admin'), v_restock, 'order.status_change');
end;
$fn$;

-- ============================================================================
-- 8. 注文詳細 (super_admin) を作り直す: 生産者ごとの発送記録を追加
-- ============================================================================

create or replace function public.treemerce_admin_get_order(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_order public.orders%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 注文詳細は super_admin のみ参照できます'
      using errcode = '42501';
  end if;

  select * into v_order from public.orders where id = p_order_id;
  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'order', to_jsonb(v_order),
    'customer', (
      select jsonb_build_object('id', c.id, 'full_name', c.full_name,
                                'email', c.email, 'phone', c.phone)
      from public.customers c where c.id = v_order.customer_id
    ),
    'agent', (
      select jsonb_build_object('id', a.id, 'public_id', a.public_id, 'display_name', a.display_name)
      from public.agents a where a.id = v_order.agent_id
    ),
    'referral_agent', (
      select jsonb_build_object('id', a.id, 'public_id', a.public_id, 'display_name', a.display_name)
      from public.agents a where a.id = v_order.referral_agent_id
    ),
    'current_agent', (
      select jsonb_build_object('id', a.id, 'public_id', a.public_id, 'display_name', a.display_name)
      from public.customer_assignments ca
      join public.agents a on a.id = ca.assigned_agent_id
      where ca.customer_id = v_order.customer_id and ca.status = 'active'
    ),
    'items', coalesce((
      select jsonb_agg(to_jsonb(oi) order by oi.created_at, oi.product_name)
      from public.order_items oi where oi.order_id = v_order.id
    ), '[]'::jsonb),
    'shipments', coalesce((
      select jsonb_agg(
               to_jsonb(s) || jsonb_build_object(
                 'is_placeholder',   pr.is_placeholder,
                 'producer_active',  pr.is_active,
                 'ship_lead_time',   pr.ship_lead_time,
                 'has_notify_email', pr.notify_email is not null)
               order by pr.is_placeholder, s.producer_name)
      from public.order_shipments s
      join public.producers pr on pr.id = s.producer_id
      where s.order_id = v_order.id
    ), '[]'::jsonb),
    'history', coalesce((
      select jsonb_agg(to_jsonb(h) order by h.changed_at desc)
      from public.order_status_history h where h.order_id = v_order.id
    ), '[]'::jsonb)
  );
end;
$fn$;

-- ============================================================================
-- 9. 発送登録・訂正 (super_admin)
-- ----------------------------------------------------------------------------
--   ready / requested → shipped : 発送登録。注文が payment_confirmed のときのみ。理由は任意。
--   shipped           → shipped : 発送日・配送業者・送り状番号の訂正。理由必須。
-- 発送日は必須で、未来日は不可 (日本時間)。
-- 発送登録の結果、注文の全発送記録 (キャンセル以外) が発送済みになったら、
-- 同じトランザクションで注文を「発送済み」にする (履歴・監査ログにも残る)。
-- ============================================================================

create or replace function public.treemerce_admin_ship_shipment(
  p_shipment_id     uuid,
  p_shipped_on      date,
  p_carrier         text default null,
  p_tracking_number text default null,
  p_reason          text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid       uuid := auth.uid();
  v_role      text := coalesce(app.admin_role(), 'super_admin');
  v_order_id  uuid;
  v_order     public.orders%rowtype;
  v_before    public.order_shipments%rowtype;
  v_after     public.order_shipments%rowtype;
  v_correct   boolean;
  v_today     date := (now() at time zone 'Asia/Tokyo')::date;
  v_auto      jsonb;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 発送登録は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  if p_shipped_on is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 発送日は必須です' using errcode = '22023';
  end if;
  if p_shipped_on > v_today then
    raise exception 'TREEMERCE_INVALID_INPUT: 発送日に未来の日付は指定できません' using errcode = '22023';
  end if;

  -- ロック順: 注文 → 発送記録 (ステータス変更処理と同じ順)
  select s.order_id into v_order_id from public.order_shipments s where s.id = p_shipment_id;
  if v_order_id is null then
    raise exception 'TREEMERCE_SHIPMENT_NOT_FOUND: 発送記録が見つかりません' using errcode = '22023';
  end if;
  select * into v_order from public.orders where id = v_order_id for update;
  select * into v_before from public.order_shipments where id = p_shipment_id for update;

  v_correct := (v_before.status = 'shipped');

  if v_correct then
    if p_reason is null or btrim(p_reason) = '' then
      raise exception 'TREEMERCE_REASON_REQUIRED: 発送済みの記録を訂正するには理由が必要です'
        using errcode = '22023';
    end if;
    if v_order.status not in ('payment_confirmed', 'shipped', 'completed') then
      raise exception 'TREEMERCE_SHIPMENT_INVALID_STATE: この注文の発送記録は訂正できません'
        using errcode = '22023';
    end if;
  else
    if v_before.status not in ('ready', 'requested') then
      raise exception 'TREEMERCE_SHIPMENT_INVALID_STATE: 入金確認前またはキャンセル済みの発送記録は発送登録できません'
        using errcode = '22023';
    end if;
    if v_order.status <> 'payment_confirmed' then
      raise exception 'TREEMERCE_SHIPMENT_INVALID_STATE: 入金確認済みの注文のみ発送登録できます'
        using errcode = '22023';
    end if;
  end if;

  perform set_config('app.commerce_ctx', 'shipment', true);

  update public.order_shipments
  set status          = 'shipped',
      shipped_on      = p_shipped_on,
      carrier         = nullif(btrim(coalesce(p_carrier, '')), ''),
      tracking_number = nullif(btrim(coalesce(p_tracking_number, '')), '')
  where id = p_shipment_id
  returning * into v_after;

  perform set_config('app.commerce_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, v_role,
          case when v_correct then 'shipment.correct' else 'shipment.ship' end,
          'order_shipments', v_after.id,
          app.shipment_audit_state(v_before, v_order.order_no),
          app.shipment_audit_state(v_after, v_order.order_no),
          nullif(btrim(coalesce(p_reason, '')), ''));

  -- 全発送完了 → 注文を発送済みに
  if not v_correct
     and v_order.status = 'payment_confirmed'
     and not exists (
       select 1 from public.order_shipments s
       where s.order_id = v_order.id and s.status not in ('shipped', 'cancelled')
     ) then
    v_auto := app.apply_order_status_change(
      v_order.id, 'shipped', '全生産者の発送完了', v_uid, v_role, false, 'order.auto_shipped');
  end if;

  return jsonb_build_object(
    'shipment',     to_jsonb(v_after),
    'order_status', coalesce(v_auto ->> 'status', v_order.status::text)
  );
end;
$fn$;

-- ============================================================================
-- 10. 発送依頼書 (super_admin。読み取り専用)
-- ----------------------------------------------------------------------------
-- その生産者の分だけ: 注文番号・お届け先・商品・数量。送り状の依頼主は運営 (販売者)。
-- 代理店の情報・顧客のメールアドレス・販売価格は含めない。
-- 入金確認前 (awaiting_payment) とキャンセル済みは返さない。
-- STEP6 (メール送信) でも同じ内容を使う。
-- ============================================================================

create or replace function public.treemerce_admin_shipment_request(p_shipment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_s        public.order_shipments%rowtype;
  v_order    public.orders%rowtype;
  v_pr       public.producers%rowtype;
  v_settings public.shop_settings%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 発送依頼書は super_admin のみ参照できます'
      using errcode = '42501';
  end if;

  select * into v_s from public.order_shipments where id = p_shipment_id;
  if not found then
    raise exception 'TREEMERCE_SHIPMENT_NOT_FOUND: 発送記録が見つかりません' using errcode = '22023';
  end if;
  if v_s.status not in ('ready', 'requested', 'shipped') then
    raise exception 'TREEMERCE_SHIPMENT_NOT_READY: 入金確認前またはキャンセル済みのため発送依頼書は作成できません'
      using errcode = '22023';
  end if;

  select * into v_order    from public.orders    where id = v_s.order_id;
  select * into v_pr       from public.producers where id = v_s.producer_id;
  select * into v_settings from public.shop_settings where id = 1;

  return jsonb_build_object(
    'shipment_id',     v_s.id,
    'status',          v_s.status,
    'request_channel', v_s.request_channel,
    'requested_at',    v_s.requested_at,
    'request_count',   v_s.request_count,
    'order_no',        v_order.order_no,
    'ordered_at',      v_order.ordered_at,
    'paid_at',         v_order.paid_at,
    'producer', jsonb_build_object(
      'id',             v_pr.id,
      'name',           v_s.producer_name,
      'notify_email',   v_pr.notify_email,
      'ship_lead_time', v_pr.ship_lead_time,
      'is_placeholder', v_pr.is_placeholder
    ),
    'ship_to', jsonb_build_object(
      'name',        v_order.ship_name,
      'postal_code', v_order.ship_postal_code,
      'address',     v_order.ship_address,
      'phone',       v_order.ship_phone
    ),
    'customer_note', v_order.customer_note,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'product_name',   oi.product_name,
               'product_sku',    oi.product_sku,
               'content_volume', oi.product_content_volume,
               'quantity',       oi.quantity) order by oi.product_name)
      from public.order_items oi
      where oi.order_id = v_s.order_id and oi.producer_id = v_s.producer_id
    ), '[]'::jsonb),
    'sender', jsonb_build_object(
      'name',    v_settings.seller_name,
      'address', v_settings.seller_address,
      'phone',   v_settings.seller_phone,
      'email',   v_settings.seller_email
    )
  );
end;
$fn$;

-- ============================================================================
-- 11. 発送依頼の記録 (super_admin)
-- ----------------------------------------------------------------------------
--   p_channel = 'manual' : 依頼書をコピーして手動で依頼した
--   p_channel = 'email'  : メールで送信した (STEP6 で使用)
--   p_error が指定された場合は送信失敗として記録し、ステータスは変えない。
-- 送り先メールアドレス・本文は保存しない。監査ログにも残さない。
-- ============================================================================

create or replace function public.treemerce_admin_record_shipment_request(
  p_shipment_id         uuid,
  p_channel             text,
  p_provider_message_id text default null,
  p_error               text default null
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
  v_order_no text;
  v_before   public.order_shipments%rowtype;
  v_after    public.order_shipments%rowtype;
  v_error    text := nullif(btrim(coalesce(p_error, '')), '');
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 発送依頼の記録は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  if p_channel is null or p_channel not in ('email', 'manual') then
    raise exception 'TREEMERCE_INVALID_INPUT: 依頼方法が正しくありません' using errcode = '22023';
  end if;

  select * into v_before from public.order_shipments where id = p_shipment_id for update;
  if not found then
    raise exception 'TREEMERCE_SHIPMENT_NOT_FOUND: 発送記録が見つかりません' using errcode = '22023';
  end if;
  if v_before.status not in ('ready', 'requested') then
    raise exception 'TREEMERCE_SHIPMENT_INVALID_STATE: 入金確認済みで未発送の発送記録のみ依頼できます'
      using errcode = '22023';
  end if;

  select o.order_no into v_order_no from public.orders o where o.id = v_before.order_id;

  perform set_config('app.commerce_ctx', 'shipment', true);

  if v_error is not null then
    update public.order_shipments
    set last_notify_error = left(v_error, 500),
        request_channel   = p_channel
    where id = p_shipment_id
    returning * into v_after;
  else
    update public.order_shipments
    set status              = 'requested',
        request_channel     = p_channel,
        requested_at        = now(),
        request_count       = request_count + 1,
        provider_message_id = nullif(btrim(coalesce(p_provider_message_id, '')), ''),
        last_notify_error   = null
    where id = p_shipment_id
    returning * into v_after;
  end if;

  perform set_config('app.commerce_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, v_role,
          case when v_error is not null then 'shipment.request_failed' else 'shipment.request' end,
          'order_shipments', v_after.id,
          app.shipment_audit_state(v_before, v_order_no),
          app.shipment_audit_state(v_after, v_order_no),
          case when v_error is not null then left(v_error, 500) end);

  return to_jsonb(v_after);
end;
$fn$;

-- ============================================================================
-- 12. EXECUTE 権限
-- ----------------------------------------------------------------------------
-- 既定の GRANT を剥がしてから付け直す。管理 RPC は関数内で super_admin を判定する。
-- (shop_products / place_order / set_order_status / get_order は create or replace の
--  ため既存の GRANT がそのまま残るが、念のため明示的に付け直す)
-- ============================================================================

revoke all on function public.treemerce_admin_upsert_producer(
  text, text, text, text, text, text, text, text, text, boolean, uuid, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_list_producers(uuid)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_upsert_product(
  text, numeric, integer, boolean, public.product_category, text, text, text, integer, uuid, text,
  uuid, text, text, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_shop_products(text, uuid)
  from public, anon, authenticated;
revoke all on function public.treemerce_place_order(
  text, jsonb, text, text, text, text, text, text,
  public.customer_age_group, public.customer_gender, text, public.customer_kind, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_set_order_status(uuid, public.order_status, text, boolean)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_get_order(uuid)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_ship_shipment(uuid, date, text, text, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_shipment_request(uuid)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_record_shipment_request(uuid, text, text, text)
  from public, anon, authenticated;

grant execute on function public.treemerce_shop_products(text, uuid) to anon, authenticated;
grant execute on function public.treemerce_place_order(
  text, jsonb, text, text, text, text, text, text,
  public.customer_age_group, public.customer_gender, text, public.customer_kind, text)
  to anon, authenticated;

grant execute on function public.treemerce_admin_upsert_producer(
  text, text, text, text, text, text, text, text, text, boolean, uuid, text) to authenticated;
grant execute on function public.treemerce_admin_list_producers(uuid) to authenticated;
grant execute on function public.treemerce_admin_upsert_product(
  text, numeric, integer, boolean, public.product_category, text, text, text, integer, uuid, text,
  uuid, text, text, text) to authenticated;
grant execute on function public.treemerce_admin_set_order_status(uuid, public.order_status, text, boolean)
  to authenticated;
grant execute on function public.treemerce_admin_get_order(uuid) to authenticated;
grant execute on function public.treemerce_admin_ship_shipment(uuid, date, text, text, text)
  to authenticated;
grant execute on function public.treemerce_admin_shipment_request(uuid) to authenticated;
grant execute on function public.treemerce_admin_record_shipment_request(uuid, text, text, text)
  to authenticated;

commit;
