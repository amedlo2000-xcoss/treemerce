-- ============================================================================
-- TREEMERCE : 0011_treemerce_commerce_rpc.sql
-- 商品登録・注文機能 (STEP2: 公開 RPC / 管理 RPC / 代理店向け集計 / 客層分析の拡張)
-- ----------------------------------------------------------------------------
-- 実装の入口
--   公開ショップ      : treemerce_shop_products / treemerce_shop_public_settings
--   注文受付          : treemerce_place_order            (anon 可。唯一の注文経路)
--   商品管理          : treemerce_admin_upsert_product    (super_admin)
--   ステータス変更    : treemerce_admin_set_order_status  (super_admin, 理由必須)
--   注文詳細 (ADMIN)  : treemerce_admin_get_order         (super_admin, 紹介元を含む)
--   ショップ設定      : treemerce_admin_update_shop_settings (super_admin, 理由必須)
--   代理店向け集計    : treemerce_agent_order_summary     (STABLE, 傘下は匿名・n<5丸め)
--   客層分析          : treemerce_customer_demographics を拡張 (STABLE のまま)
-- ============================================================================

begin;

-- ============================================================================
-- 1. 公開ショップ (未ログイン可・読み取り専用)
-- ============================================================================

-- 紹介リンクの代理店が稼働中のときだけ公開商品を返す。
-- 代理店名・在庫の正確な数・原価などは返さない。
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
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id',           p.id,
               'name',         p.name,
               'description',  p.description,
               'category',     p.category,
               'price',        p.price,
               'image_path',   p.image_path,
               'in_stock',     p.stock > 0,
               'low_stock',    p.stock between 1 and 5,
               'max_quantity', least(p.stock, 99)
             ) order by p.sort_order, p.created_at)
      from public.products p
      where p.is_published
        and (p_product_id is null or p.id = p_product_id)
    ), '[]'::jsonb)
  );
end;
$fn$;

-- 特定商取引法に基づく表記ページ用。振込先口座はここでは返さない (注文完了時のみ)。
create or replace function public.treemerce_shop_public_settings()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select jsonb_build_object(
    'seller_name',           s.seller_name,
    'seller_representative', s.seller_representative,
    'seller_address',        s.seller_address,
    'seller_phone',          s.seller_phone,
    'seller_email',          s.seller_email,
    'business_hours',        s.business_hours,
    'price_note',            s.price_note,
    'additional_fees',       s.additional_fees,
    'payment_method_note',   s.payment_method_note,
    'delivery_time',         s.delivery_time,
    'return_policy',         s.return_policy,
    'extra_notes',           s.extra_notes,
    'shipping_fee',          s.shipping_fee,
    'payment_due_days',      s.payment_due_days,
    'accepting_orders',      s.is_accepting_orders
  )
  from public.shop_settings s
  where s.id = 1;
$fn$;

-- ============================================================================
-- 2. 注文受付 (唯一の注文経路)
-- ----------------------------------------------------------------------------
--   原則7 : 同一人物の照合は email / 電話番号のみ。氏名だけでは照合しない。
--   原則4 : 既存顧客の注文は「現在の担当代理店」に帰属させる。紹介リンクの代理店が
--           別人でも担当は変えない。リンクの代理店は referral_agent_id (ADMIN 専用) に記録。
--   原則6 : 新規/既存で応答の形をまったく同じにし、担当代理店が誰かは一切返さない。
--   新規顧客の登録は既存の唯一の入口 treemerce_register_customer() を通す。
--   顧客マスタは注文で上書きしない (入力内容は注文のスナップショットにのみ保存)。
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
  v_link        public.agents%rowtype;
  v_settings    public.shop_settings%rowtype;
  v_customer_id uuid;
  v_master_name text;
  v_mismatch    boolean := false;
  v_assigned    uuid;
  v_reg         jsonb;
  v_line        record;
  v_product     public.products%rowtype;
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
      'amount',           v_product.price * v_line.quantity
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
    contact_email, contact_phone, customer_note, identity_mismatch
  ) values (
    v_customer_id, v_assigned, v_link.id, 'received',
    v_subtotal, v_settings.shipping_fee, v_subtotal + v_settings.shipping_fee,
    btrim(p_full_name), nullif(btrim(coalesce(p_ship_postal_code, '')), ''),
    btrim(p_ship_address), nullif(btrim(coalesce(p_phone, '')), ''),
    nullif(btrim(coalesce(p_email, '')), ''), nullif(btrim(coalesce(p_phone, '')), ''),
    nullif(btrim(coalesce(p_note, '')), ''), v_mismatch
  )
  returning * into v_order;

  insert into public.order_items
    (order_id, product_id, product_name, product_sku, product_category, unit_price, quantity, amount)
  select v_order.id, x.product_id, x.product_name, x.product_sku, x.product_category,
         x.unit_price, x.quantity, x.amount
  from jsonb_to_recordset(v_lines) as x(
    product_id uuid, product_name text, product_sku text,
    product_category public.product_category, unit_price numeric, quantity integer, amount numeric);

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
      'due_date',            ((v_order.ordered_at at time zone 'Asia/Tokyo')::date
                              + v_settings.payment_due_days),
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
-- 3. 商品の登録・編集 (super_admin)
-- ============================================================================

create or replace function public.treemerce_admin_upsert_product(
  p_name         text,
  p_price        numeric,
  p_stock        integer,
  p_is_published boolean,
  p_category     public.product_category default 'other',
  p_description  text default null,
  p_image_path   text default null,
  p_sku          text default null,
  p_sort_order   integer default 0,
  p_product_id   uuid default null,
  p_reason       text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid    uuid := auth.uid();
  v_before public.products%rowtype;
  v_after  public.products%rowtype;
  v_image  text := nullif(btrim(coalesce(p_image_path, '')), '');
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

  if p_product_id is null then
    insert into public.products
      (sku, name, description, category, price, stock, is_published, image_path, sort_order, created_by)
    values
      (nullif(btrim(coalesce(p_sku, '')), ''), btrim(p_name),
       nullif(btrim(coalesce(p_description, '')), ''), coalesce(p_category, 'other'),
       p_price, p_stock, coalesce(p_is_published, false), v_image, coalesce(p_sort_order, 0), v_uid)
    returning * into v_after;

    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (v_uid, coalesce(app.admin_role(), 'super_admin'), 'product.create', 'products',
            v_after.id, null, to_jsonb(v_after), nullif(btrim(coalesce(p_reason, '')), ''));
  else
    select * into v_before from public.products where id = p_product_id for update;
    if not found then
      raise exception 'TREEMERCE_PRODUCT_NOT_FOUND: 商品が見つかりません' using errcode = '22023';
    end if;

    update public.products
    set sku          = nullif(btrim(coalesce(p_sku, '')), ''),
        name         = btrim(p_name),
        description  = nullif(btrim(coalesce(p_description, '')), ''),
        category     = coalesce(p_category, 'other'),
        price        = p_price,
        stock        = p_stock,
        is_published = coalesce(p_is_published, false),
        image_path   = v_image,
        sort_order   = coalesce(p_sort_order, 0)
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
-- 4. 注文ステータスの変更 (super_admin, 理由必須)
-- ----------------------------------------------------------------------------
-- 変更前後・理由・実行者・日時を order_status_history と admin_audit_logs の両方に保存。
-- 帰属代理店 (agent_id) はここでも変更できない (0010 の不変トリガ)。
-- ============================================================================

create or replace function public.treemerce_admin_set_order_status(
  p_order_id uuid,
  p_status   public.order_status,
  p_reason   text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid    uuid := auth.uid();
  v_before public.orders%rowtype;
  v_after  public.orders%rowtype;
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

  perform set_config('app.commerce_ctx', 'order_status', true);

  update public.orders
  set status       = p_status,
      paid_at      = case when p_status = 'payment_confirmed' then now() else paid_at end,
      shipped_at   = case when p_status = 'shipped'           then now() else shipped_at end,
      completed_at = case when p_status = 'completed'         then now() else completed_at end,
      cancelled_at = case when p_status = 'cancelled'         then now() else cancelled_at end
  where id = p_order_id
  returning * into v_after;

  -- キャンセル時は確保していた在庫を戻す
  if p_status = 'cancelled' then
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

  insert into public.order_status_history
    (order_id, from_status, to_status, reason, changed_by, changed_by_role)
  values (p_order_id, v_before.status, p_status, btrim(p_reason), v_uid,
          coalesce(app.admin_role(), 'super_admin'));

  perform set_config('app.commerce_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, coalesce(app.admin_role(), 'super_admin'), 'order.status_change', 'orders',
          p_order_id,
          jsonb_build_object('order_no', v_before.order_no, 'status', v_before.status),
          jsonb_build_object('order_no', v_after.order_no, 'status', v_after.status),
          btrim(p_reason));

  return jsonb_build_object(
    'order_id',    v_after.id,
    'order_no',    v_after.order_no,
    'from_status', v_before.status,
    'status',      v_after.status
  );
end;
$fn$;

-- ============================================================================
-- 5. 注文詳細 (super_admin。紹介元・本人確認フラグ・現担当を含む)
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
    'history', coalesce((
      select jsonb_agg(to_jsonb(h) order by h.changed_at desc)
      from public.order_status_history h where h.order_id = v_order.id
    ), '[]'::jsonb)
  );
end;
$fn$;

-- ============================================================================
-- 6. ショップ設定の更新 (super_admin, 理由必須)
-- ============================================================================

create or replace function public.treemerce_admin_update_shop_settings(
  p_patch  jsonb,
  p_reason text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid     uuid := auth.uid();
  v_allowed text[] := array[
    'seller_name', 'seller_representative', 'seller_address', 'seller_phone', 'seller_email',
    'business_hours', 'price_note', 'additional_fees', 'payment_method_note', 'delivery_time',
    'return_policy', 'extra_notes', 'shipping_fee', 'payment_due_days', 'is_accepting_orders',
    'bank_name', 'bank_branch', 'bank_account_type', 'bank_account_number', 'bank_account_holder'
  ];
  v_patch   jsonb;
  v_before  public.shop_settings%rowtype;
  v_new     public.shop_settings%rowtype;
  v_after   public.shop_settings%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: ショップ設定の変更は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'TREEMERCE_REASON_REQUIRED: 変更理由は必須です' using errcode = '22023';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'TREEMERCE_INVALID_INPUT: 更新内容が指定されていません' using errcode = '22023';
  end if;

  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) into v_patch
  from jsonb_each(p_patch) where key = any (v_allowed);

  select * into v_before from public.shop_settings where id = 1 for update;
  v_new := jsonb_populate_record(v_before, v_patch);

  -- 注文受付を開始するには、振込先と販売事業者情報が揃っている必要がある
  if v_new.is_accepting_orders and (
       nullif(btrim(coalesce(v_new.bank_name, '')), '') is null
    or nullif(btrim(coalesce(v_new.bank_branch, '')), '') is null
    or v_new.bank_account_type is null
    or nullif(btrim(coalesce(v_new.bank_account_number, '')), '') is null
    or nullif(btrim(coalesce(v_new.bank_account_holder, '')), '') is null
    or nullif(btrim(coalesce(v_new.seller_name, '')), '') is null
    or nullif(btrim(coalesce(v_new.seller_address, '')), '') is null
    or nullif(btrim(coalesce(v_new.seller_phone, '')), '') is null
  ) then
    raise exception 'TREEMERCE_SETTINGS_INCOMPLETE: 注文受付を開始するには振込先と販売事業者情報 (名称・所在地・電話番号) が必要です'
      using errcode = '22023';
  end if;

  update public.shop_settings
  set seller_name           = nullif(btrim(coalesce(v_new.seller_name, '')), ''),
      seller_representative = nullif(btrim(coalesce(v_new.seller_representative, '')), ''),
      seller_address        = nullif(btrim(coalesce(v_new.seller_address, '')), ''),
      seller_phone          = nullif(btrim(coalesce(v_new.seller_phone, '')), ''),
      seller_email          = nullif(btrim(coalesce(v_new.seller_email, '')), ''),
      business_hours        = nullif(btrim(coalesce(v_new.business_hours, '')), ''),
      price_note            = nullif(btrim(coalesce(v_new.price_note, '')), ''),
      additional_fees       = nullif(btrim(coalesce(v_new.additional_fees, '')), ''),
      payment_method_note   = nullif(btrim(coalesce(v_new.payment_method_note, '')), ''),
      delivery_time         = nullif(btrim(coalesce(v_new.delivery_time, '')), ''),
      return_policy         = nullif(btrim(coalesce(v_new.return_policy, '')), ''),
      extra_notes           = nullif(btrim(coalesce(v_new.extra_notes, '')), ''),
      shipping_fee          = v_new.shipping_fee,
      payment_due_days      = v_new.payment_due_days,
      is_accepting_orders   = v_new.is_accepting_orders,
      bank_name             = nullif(btrim(coalesce(v_new.bank_name, '')), ''),
      bank_branch           = nullif(btrim(coalesce(v_new.bank_branch, '')), ''),
      bank_account_type     = v_new.bank_account_type,
      bank_account_number   = nullif(btrim(coalesce(v_new.bank_account_number, '')), ''),
      bank_account_holder   = nullif(btrim(coalesce(v_new.bank_account_holder, '')), ''),
      updated_by            = v_uid
  where id = 1
  returning * into v_after;

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, coalesce(app.admin_role(), 'super_admin'), 'shop_settings.update', 'shop_settings',
          null, to_jsonb(v_before), to_jsonb(v_after), btrim(p_reason));

  return to_jsonb(v_after);
end;
$fn$;

-- ============================================================================
-- 7. 代理店向け注文サマリ (STABLE / 読み取り専用)
-- ----------------------------------------------------------------------------
--   own_current     : 自分に帰属し、かつ現在も自分が担当している顧客の注文 (実数)
--   own_transferred : 自分に帰属するが、担当変更で現在は担当していない顧客の注文
--                     (原則5: 実データは見せない。件数・金額のみ、n<5 は丸め)
--   subtree         : 傘下代理店に帰属する注文 (件数・金額のみ、n<5 は丸め、内訳なし)
-- 集計対象は入金確認済み以降 (payment_confirmed / shipped / completed)。
-- ============================================================================

create or replace function public.treemerce_agent_order_summary(p_period text default 'all')
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_self  uuid := app.current_agent_id();
  v_k     constant integer := 5;
  v_from  timestamptz;
  v_own_cnt int; v_own_sum numeric;
  v_tr_cnt  int; v_tr_sum  numeric;
  v_sub_cnt int; v_sub_sum numeric;
  v_await   int;
begin
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店アカウントが必要です' using errcode = '42501';
  end if;
  if p_period not in ('all', '3m', '1y') then
    raise exception 'TREEMERCE_INVALID_PERIOD: 期間指定が不正です' using errcode = '22023';
  end if;

  v_from := case p_period
              when '3m' then now() - interval '3 months'
              when '1y' then now() - interval '1 year'
              else null
            end;

  select count(*)::int, coalesce(sum(o.total), 0)
    into v_own_cnt, v_own_sum
  from public.orders o
  where o.agent_id = v_self
    and o.status in ('payment_confirmed', 'shipped', 'completed')
    and (v_from is null or o.ordered_at >= v_from)
    and app.is_assigned_agent(o.customer_id);

  select count(*)::int, coalesce(sum(o.total), 0)
    into v_tr_cnt, v_tr_sum
  from public.orders o
  where o.agent_id = v_self
    and o.status in ('payment_confirmed', 'shipped', 'completed')
    and (v_from is null or o.ordered_at >= v_from)
    and not app.is_assigned_agent(o.customer_id);

  select count(*)::int, coalesce(sum(o.total), 0)
    into v_sub_cnt, v_sub_sum
  from public.orders o
  where o.agent_id in (
          select s.agent_id from app.agent_subtree(v_self, false) s where s.agent_id <> v_self)
    and o.status in ('payment_confirmed', 'shipped', 'completed')
    and (v_from is null or o.ordered_at >= v_from);

  select count(*)::int into v_await
  from public.orders o
  where o.status = 'received'
    and app.is_assigned_agent(o.customer_id);

  return jsonb_build_object(
    'period',      p_period,
    'k_threshold', v_k,
    'own_current', jsonb_build_object('count', v_own_cnt, 'total', v_own_sum),
    'own_awaiting_payment', v_await,
    'own_transferred', case when v_tr_cnt = 0
      then jsonb_build_object('suppressed', false, 'count', 0, 'total', 0)
      when v_tr_cnt < v_k
      then jsonb_build_object('suppressed', true, 'count', null, 'total', null, 'label', '該当データ少数')
      else jsonb_build_object('suppressed', false, 'count', v_tr_cnt, 'total', v_tr_sum) end,
    'subtree', case when v_sub_cnt = 0
      then jsonb_build_object('suppressed', false, 'count', 0, 'total', 0)
      when v_sub_cnt < v_k
      then jsonb_build_object('suppressed', true, 'count', null, 'total', null, 'label', '該当データ少数')
      else jsonb_build_object('suppressed', false, 'count', v_sub_cnt, 'total', v_sub_sum) end,
    'generated_at', now()
  );
end;
$fn$;

-- ============================================================================
-- 8. 客層分析の拡張 (STABLE のまま。代理店別の内訳は含めない)
-- ----------------------------------------------------------------------------
--   product_category : 既存の purchases(completed) + 注文明細 (入金確認済み以降)
--   amount_band      : 顧客ごとの購入金額合計の帯 × 人数 (n<5 丸め)
--   purchasing_customers / total_sales : total_sales は購入者 n<5 なら null
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
    select p.customer_id, p.product_category::text as category, p.amount
    from public.purchases p
    join base b on b.id = p.customer_id
    where p.status = 'completed'
      and (v_from is null or p.purchased_at >= v_from)
    union all
    select o.customer_id, oi.product_category::text as category, oi.amount
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
    select jsonb_agg(jsonb_build_object('key', category, 'count', n)) as buckets
    from (select category, count(*)::int as n from paid_lines group by 1) t
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
  'STEP6 客層分析。読み取り専用。購入カテゴリ・金額帯は入金確認済み以降の注文と完了済み購入のみ。n<5 は丸める。';

-- ============================================================================
-- 9. EXECUTE 権限
-- ============================================================================

revoke all on function public.treemerce_shop_products(text, uuid)       from public, anon, authenticated;
revoke all on function public.treemerce_shop_public_settings()          from public, anon, authenticated;
revoke all on function public.treemerce_place_order(
  text, jsonb, text, text, text, text, text, text,
  public.customer_age_group, public.customer_gender, text, public.customer_kind, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_upsert_product(
  text, numeric, integer, boolean, public.product_category, text, text, text, integer, uuid, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_set_order_status(uuid, public.order_status, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_get_order(uuid)           from public, anon, authenticated;
revoke all on function public.treemerce_admin_update_shop_settings(jsonb, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_agent_order_summary(text)       from public, anon, authenticated;

-- 未ログインの購入者も使う公開エンドポイント
grant execute on function public.treemerce_shop_products(text, uuid)    to anon, authenticated;
grant execute on function public.treemerce_shop_public_settings()       to anon, authenticated;
grant execute on function public.treemerce_place_order(
  text, jsonb, text, text, text, text, text, text,
  public.customer_age_group, public.customer_gender, text, public.customer_kind, text)
  to anon, authenticated;

-- ログイン必須 (関数内部で super_admin / 稼働代理店を再判定する)
grant execute on function public.treemerce_admin_upsert_product(
  text, numeric, integer, boolean, public.product_category, text, text, text, integer, uuid, text)
  to authenticated;
grant execute on function public.treemerce_admin_set_order_status(uuid, public.order_status, text)
  to authenticated;
grant execute on function public.treemerce_admin_get_order(uuid)        to authenticated;
grant execute on function public.treemerce_admin_update_shop_settings(jsonb, text) to authenticated;
grant execute on function public.treemerce_agent_order_summary(text)    to authenticated;

commit;
