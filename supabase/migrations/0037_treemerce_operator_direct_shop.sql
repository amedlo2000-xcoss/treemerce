-- ============================================================================
-- TREEMERCE : 0037_treemerce_operator_direct_shop.sql
-- どのオブザーバーにも紐づかないショップ (/shop) と「運営直接」の会員
-- ----------------------------------------------------------------------------
-- 運営直接の会員 = customers の行はあるが、customer_assignments に担当の行が無い会員。
--   ・customers に代理店を指す列は足さない (原則1)。担当の表し方は従来どおり customer_assignments のみ
--   ・担当は最初の登録で決まる (原則4)。運営直接で登録した会員が、あとからオブザーバーの紹介リンクで
--     登録し直しても、treemerce_register_customer は「既に登録済み」(中立メッセージ) を返すだけで
--     担当は作られない。担当変更 (treemerce_admin_transfer_customer) も担当の行が無いため対象外のまま
--
-- 変更点:
--   1. orders.agent_id (売上の帰属) を NULL 可にする。NULL = 運営に帰属 (担当オブザーバーなし)。
--      帰属は従来どおり注文時点の担当を写すだけで、作成後は変更できない (orders_guard)
--   2. treemerce_shop_products: p_agent_public_id が NULL のとき、運営のショップとして商品を返す
--      (オブザーバーの公開IDを渡した場合の動きは従来どおり。無効なIDは valid = false)
--   3. treemerce_register_direct_member (新規): /shop からの会員登録。担当を作らない。
--      重複は treemerce_register_customer と同じ中立メッセージ (原則6・7)
--   4. treemerce_place_order: p_agent_public_id が NULL のとき運営のショップからの注文として受け付ける
--        ・紹介元 (referral_agent_id) は NULL
--        ・顧客が未登録なら担当なし (運営直接) で登録する
--      担当のいない顧客の注文は帰属 NULL (運営) で受け付ける (これまでは受け付けなかった)。
--      担当のいる顧客は、どのショップから買っても帰属は現在の担当のまま (原則4、従来どおり)
--
-- 報酬 (0033) は出店者 (持込み元) と紹介者 (出店者の invited_by) で決まり orders.agent_id を
-- 参照しないため、変更しない。
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. 売上の帰属を NULL 可に
-- ----------------------------------------------------------------------------

alter table public.orders alter column agent_id drop not null;

comment on column public.orders.agent_id is
  '原則4: 注文時点の担当オブザーバー (customer_assignments から複写、以後不変)。NULL = 担当のいない運営直接の会員の注文で、売上は運営に帰属する。';

-- ----------------------------------------------------------------------------
-- 2. 公開商品一覧 (最新の定義: 0023)。p_agent_public_id = NULL で運営のショップ
-- ----------------------------------------------------------------------------

create or replace function public.treemerce_shop_products(
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
  -- NULL = 運営のショップ (/shop)。オブザーバーの公開IDが指定された場合は稼働中のものだけ有効
  if p_agent_public_id is not null and not exists (
    select 1 from public.agents
    where public_id = btrim(p_agent_public_id) and status = 'active'
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

-- ----------------------------------------------------------------------------
-- 3. 運営直接の会員登録 (担当を作らない)
-- ----------------------------------------------------------------------------

-- 共通処理: 識別子で照合し、未登録なら担当なしで顧客を作る。
-- 戻り値: 'registered' / 'duplicate'。重複時は何も書き込まない (既存の担当・マスタは変えない)。
create or replace function app.register_direct_customer(
  p_full_name      text,
  p_email          text,
  p_phone          text,
  p_full_name_kana text,
  p_customer_type  public.customer_kind,
  p_postal_code    text default null,
  p_address_line   text default null,
  p_age_group      public.customer_age_group default null,
  p_gender         public.customer_gender    default null,
  p_prefecture     text default null
)
returns text
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '');
begin
  if p_full_name is null or btrim(p_full_name) = '' then
    raise exception 'TREEMERCE_INVALID_INPUT: 氏名は必須です' using errcode = '22023';
  end if;
  -- 原則7: 識別子で照合する (氏名だけでは同一人物と確定しない)
  if v_email is null and v_phone is null then
    raise exception 'TREEMERCE_IDENTIFIER_REQUIRED: メールアドレスまたは電話番号のいずれかが必要です'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from public.customers c
    where (v_email is not null and c.email_normalized = v_email)
       or (v_phone is not null and c.phone_normalized = v_phone)
  ) then
    return 'duplicate';
  end if;

  insert into public.customers (
    full_name, full_name_kana, email, phone, postal_code, address_line,
    age_group, gender, prefecture, customer_type, first_assigned_at
  ) values (
    btrim(p_full_name), nullif(btrim(coalesce(p_full_name_kana, '')), ''),
    nullif(btrim(coalesce(p_email, '')), ''), nullif(btrim(coalesce(p_phone, '')), ''),
    nullif(btrim(coalesce(p_postal_code, '')), ''), nullif(btrim(coalesce(p_address_line, '')), ''),
    p_age_group, p_gender, nullif(btrim(coalesce(p_prefecture, '')), ''),
    coalesce(p_customer_type, 'individual'), now()
  );
  -- customer_assignments には書き込まない (担当なし = 運営直接)

  insert into public.notifications (for_admin, category, title, body)
  values (true, 'assignment', '運営直接の会員が登録されました',
          btrim(p_full_name) || ' 様がショップ (/shop) から会員登録しました (担当オブザーバーなし)。');

  return 'registered';
end;
$fn$;

revoke all on function app.register_direct_customer(
  text, text, text, text, public.customer_kind, text, text,
  public.customer_age_group, public.customer_gender, text)
  from public, anon, authenticated;

create or replace function public.treemerce_register_direct_member(
  p_full_name      text,
  p_email          text default null,
  p_phone          text default null,
  p_full_name_kana text default null,
  p_customer_type  public.customer_kind default 'individual'
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_status text;
begin
  v_status := app.register_direct_customer(
    p_full_name, p_email, p_phone, p_full_name_kana, p_customer_type);

  -- 原則6: 応答に顧客ID・担当は含めない。重複時の文面は treemerce_register_customer と同じ
  return jsonb_build_object(
    'member_status',  v_status,
    'member_message', case when v_status = 'duplicate'
      then 'このご連絡先は既に登録されています。担当オブザーバーの変更は行われません。詳細は運営事務局までお問い合わせください。'
      end
  );
end;
$fn$;

comment on function public.treemerce_register_direct_member(text, text, text, text, public.customer_kind) is
  'ショップ (/shop、オブザーバーに紐づかない) からの会員登録。担当を作らない (運営直接)。既存の会員なら何も変えず中立メッセージのみ (原則4・6・7)。';

revoke all on function public.treemerce_register_direct_member(text, text, text, text, public.customer_kind)
  from public, anon, authenticated;
grant execute on function public.treemerce_register_direct_member(text, text, text, text, public.customer_kind)
  to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 4. 注文受付 (最新の定義: 0036)。p_agent_public_id = NULL で運営のショップからの注文
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
  v_user_email  text;
  v_confirmed   timestamptz;
  v_email       text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_phone       text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '');
  v_max_unpaid  constant integer := 3;
  v_unpaid      integer;
  v_link        public.agents%rowtype;
  v_link_id     uuid;
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
  -- ---- 会員のみ (0036) --------------------------------------------------------
  if v_uid is null then
    raise exception 'TREEMERCE_UNAUTHENTICATED: ご購入には会員登録（無料）またはログインが必要です'
      using errcode = '42501';
  end if;
  select u.email, u.email_confirmed_at into v_user_email, v_confirmed
  from auth.users u where u.id = v_uid;
  if v_user_email is null or v_confirmed is null then
    raise exception 'TREEMERCE_UNAUTHENTICATED: メールアドレスの確認が済んだアカウントでログインしてください'
      using errcode = '42501';
  end if;
  if v_email is null or v_email <> lower(btrim(v_user_email)) then
    raise exception 'TREEMERCE_ORDER_EMAIL_MISMATCH: 連絡先のメールアドレスはログイン中のアカウントと同じにしてください'
      using errcode = '22023';
  end if;

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

  -- NULL = 運営のショップ (/shop、紹介元なし)。オブザーバーの公開IDは稼働中のものだけ有効 (0037)
  if p_agent_public_id is not null then
    select * into v_link
    from public.agents
    where public_id = btrim(p_agent_public_id) and status = 'active';
    if not found then
      raise exception 'TREEMERCE_AGENT_NOT_FOUND: 紹介リンクが無効です' using errcode = '22023';
    end if;
    v_link_id := v_link.id;
  end if;

  select * into v_settings from public.shop_settings where id = 1;
  if not found or not v_settings.is_accepting_orders then
    raise exception 'TREEMERCE_ORDERS_CLOSED: 現在ご注文を受け付けておりません' using errcode = '22023';
  end if;

  -- ---- 未入金注文の上限 (連絡先ごと。顧客マスタは参照しない) ------------------
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
    if not found or not v_product.is_published or v_product.sales_status <> 'on_sale'
       or v_product.item_kind <> 'goods' or v_product.price is null then
      raise exception 'TREEMERCE_PRODUCT_UNAVAILABLE: ご指定の商品は現在お取り扱いできません'
        using errcode = '22023';
    end if;

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
    if v_link_id is not null then
      -- オブザーバーのショップ: 既存の唯一の入口で登録し、担当をこのリンクのオブザーバーで確定する
      v_reg := public.treemerce_register_customer(
        v_link.public_id, p_full_name, p_email, p_phone, p_full_name_kana,
        p_age_group, p_gender, p_prefecture, p_customer_type,
        p_ship_postal_code, p_ship_address);
      if v_reg ->> 'status' <> 'registered' then
        raise exception 'TREEMERCE_ORDER_UNAVAILABLE: ご注文を受け付けられませんでした。運営事務局までお問い合わせください。'
          using errcode = '22023';
      end if;
    else
      -- 運営のショップ: 担当なし (運営直接) で登録する
      if app.register_direct_customer(
           p_full_name, p_email, p_phone, p_full_name_kana, p_customer_type,
           p_ship_postal_code, p_ship_address, p_age_group, p_gender, p_prefecture) <> 'registered' then
        raise exception 'TREEMERCE_ORDER_UNAVAILABLE: ご注文を受け付けられませんでした。運営事務局までお問い合わせください。'
          using errcode = '22023';
      end if;
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

  -- 原則4: 帰属は「現在の担当」。リンクのオブザーバーではない。
  -- 担当のいない (運営直接の) 会員は NULL = 運営に帰属 (0037)。担当はここでは作らない。
  select ca.assigned_agent_id into v_assigned
  from public.customer_assignments ca
  where ca.customer_id = v_customer_id and ca.status = 'active';

  -- ---- 書込み (認可コンテキスト内) --------------------------------------------
  perform set_config('app.commerce_ctx', 'place_order', true);

  insert into public.orders (
    customer_id, agent_id, referral_agent_id, status,
    subtotal, shipping_fee, total,
    ship_name, ship_postal_code, ship_address, ship_phone,
    contact_email, contact_phone, customer_note, identity_mismatch,
    payment_due_date
  ) values (
    v_customer_id, v_assigned, v_link_id, 'received',
    v_subtotal, v_settings.shipping_fee, v_subtotal + v_settings.shipping_fee,
    btrim(p_full_name), nullif(btrim(coalesce(p_ship_postal_code, '')), ''),
    btrim(p_ship_address), nullif(btrim(coalesce(p_phone, '')), ''),
    nullif(btrim(coalesce(p_email, '')), ''), nullif(btrim(coalesce(p_phone, '')), ''),
    nullif(btrim(coalesce(p_note, '')), ''), v_mismatch,
    (now() at time zone 'Asia/Tokyo')::date + v_settings.payment_due_days
  )
  returning * into v_order;

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

  -- 通知: 担当オブザーバー (自分の担当顧客なので実名可。担当がいる場合だけ) と運営
  if v_assigned is not null then
    insert into public.notifications (agent_id, category, title, body)
    select v_assigned, 'purchase', '担当顧客からご注文がありました',
           c.full_name || ' 様からのご注文 (注文番号 ' || v_order.order_no || ')'
    from public.customers c where c.id = v_customer_id;
  end if;

  insert into public.notifications (for_admin, category, title, body)
  values (true, 'purchase', '新しい注文を受け付けました',
          '注文番号 ' || v_order.order_no || ' / 合計 ' || to_char(v_order.total, 'FM999,999,999,990') || ' TWA'
          || case when v_assigned is null then ' (運営直接)' else '' end);

  -- 原則6: 新規/既存で同じ形。担当オブザーバー・顧客ID・紹介元は返さない。
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

-- 権限は 0036 と同じ (authenticated のみ)
revoke all on function public.treemerce_place_order(
  text, jsonb, text, text, text, text, text, text,
  public.customer_age_group, public.customer_gender, text, public.customer_kind, text)
  from public, anon;
grant execute on function public.treemerce_place_order(
  text, jsonb, text, text, text, text, text, text,
  public.customer_age_group, public.customer_gender, text, public.customer_kind, text)
  to authenticated;

commit;
