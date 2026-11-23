-- ============================================================================
-- TREEMERCE : 0034_treemerce_twa_wording.sql
-- DB が返す表示用の文言の金額単位「円」を「TWA」に変更 (画面の表記「10,000 TWA」に合わせる)
-- ----------------------------------------------------------------------------
-- このサイトは実際の円を扱わないサンプルとして見せるため、金額の単位を TWA にする。
-- 変更するのは表示される文言だけ。エラーコード (TREEMERCE_*)・引数・処理内容・権限・
-- 戻り値の型は変えない。各関数は最新の定義をそのまま写し、次の文言だけを差し替えている。
--   ・「0 円以上 1 億円未満」 → 「0 TWA 以上 100,000,000 TWA 未満」
--   ・新規注文の通知 「合計 <金額> 円」 → 「合計 <3桁区切りの金額> TWA」
--     (金額の文字列化を v_order.total::text から to_char(v_order.total, 'FM999,999,999,990') に変更。
--      通知の本文の表記だけで、注文の金額そのものは変わらない)
--
-- 写した元の定義 (0033 はこれらの関数を定義し直していない):
--   treemerce_place_order                    0023_treemerce_product_status_and_categories.sql:622
--   treemerce_admin_save_product             0023_treemerce_product_status_and_categories.sql:348
--   treemerce_save_my_submission             0024_treemerce_submission_categories_and_analytics.sql:255
--   treemerce_admin_save_proxy_submission    0032_treemerce_observer_wording.sql:166
--   treemerce_admin_approve_submission       0024_treemerce_submission_categories_and_analytics.sql:831
--
-- create or replace で同じ引数のまま置き換えるため、既存の GRANT / REVOKE・コメントはそのまま残る。
-- 列の値・列名は変更しない (orders.currency 等も変更しない)。
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- public.treemerce_place_order  (最新の定義: 0023_treemerce_product_status_and_categories.sql)
-- ----------------------------------------------------------------------------

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
          '注文番号 ' || v_order.order_no || ' / 合計 ' || to_char(v_order.total, 'FM999,999,999,990') || ' TWA');

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

-- ----------------------------------------------------------------------------
-- public.treemerce_admin_save_product  (最新の定義: 0023_treemerce_product_status_and_categories.sql)
-- ----------------------------------------------------------------------------

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
    raise exception 'TREEMERCE_INVALID_INPUT: 価格は 0 TWA 以上 100,000,000 TWA 未満で入力してください' using errcode = '22023';
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

-- ----------------------------------------------------------------------------
-- public.treemerce_save_my_submission  (最新の定義: 0024_treemerce_submission_categories_and_analytics.sql)
-- ----------------------------------------------------------------------------

create or replace function public.treemerce_save_my_submission(
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
    raise exception 'TREEMERCE_INVALID_INPUT: 希望販売価格は 0 TWA 以上 100,000,000 TWA 未満で入力してください'
      using errcode = '22023';
  end if;
  if p_expected_wholesale_price is not null
     and (p_expected_wholesale_price < 0 or p_expected_wholesale_price >= 100000000) then
    raise exception 'TREEMERCE_INVALID_INPUT: 想定卸値は 0 TWA 以上 100,000,000 TWA 未満で入力してください'
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

-- ----------------------------------------------------------------------------
-- public.treemerce_admin_save_proxy_submission  (最新の定義: 0032_treemerce_observer_wording.sql)
-- ----------------------------------------------------------------------------

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
    raise exception 'TREEMERCE_INVALID_INPUT: 希望販売価格は 0 TWA 以上 100,000,000 TWA 未満で入力してください'
      using errcode = '22023';
  end if;
  if p_expected_wholesale_price is not null
     and (p_expected_wholesale_price < 0 or p_expected_wholesale_price >= 100000000) then
    raise exception 'TREEMERCE_INVALID_INPUT: 想定卸値は 0 TWA 以上 100,000,000 TWA 未満で入力してください'
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

-- ----------------------------------------------------------------------------
-- public.treemerce_admin_approve_submission  (最新の定義: 0024_treemerce_submission_categories_and_analytics.sql)
-- ----------------------------------------------------------------------------

create or replace function public.treemerce_admin_approve_submission(
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
    raise exception 'TREEMERCE_INVALID_INPUT: 価格は 0 TWA 以上 100,000,000 TWA 未満で指定してください' using errcode = '22023';
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

commit;
