-- ============================================================================
-- TREEMERCE : 0013_treemerce_commerce_hardening.sql
-- 商品・注文機能の補強 (0010 / 0011 の上に重ねる)
-- ----------------------------------------------------------------------------
--   1. 支払期限切れの未入金注文 (received) を自動キャンセルし、在庫を戻す。
--      理由「支払期限切れによる自動キャンセル」を履歴と監査ログの両方に残す。
--      支払期限は注文時点で orders.payment_due_date に確定させる
--      (後からショップ設定の日数を変えても、既存注文の期限は変わらない)。
--      実行は pg_cron (Supabase 標準の拡張) で 1 時間ごと。
--   2. 同一メールアドレス / 同一電話番号からの未入金注文は最大 3 件まで。
--      超過時は既存の中立エラー (TREEMERCE_ORDER_UNAVAILABLE) と同じ文言で拒否し、
--      判定は注文の連絡先だけで行う (既存顧客かどうかで応答・経路が変わらない。原則6)。
--   3. 発送済み (shipped) からのキャンセルでは在庫を自動で戻さない。
--      super_admin が p_restock で明示的に選ぶ (未指定はエラー)。
--   4. 客層分析の product_category を「明細件数」ではなく「購入者の人数」で数え、
--      その人数で n<5 の丸めを行う。
--   5. 商品ページの max_quantity の上限を「在庫数と 10 の小さい方」にする。
-- ============================================================================

begin;

-- ============================================================================
-- 1-a. 支払期限を注文時点で確定させる列
-- ============================================================================

alter table public.orders add column payment_due_date date;

-- 既存の注文は「注文日 (日本時間) + 現在の支払期限日数」で埋める
update public.orders o
set payment_due_date = (o.ordered_at at time zone 'Asia/Tokyo')::date + s.payment_due_days
from public.shop_settings s
where s.id = 1 and o.payment_due_date is null;

alter table public.orders alter column payment_due_date set not null;

comment on column public.orders.payment_due_date is
  '支払期限 (日本時間の日付)。この日を過ぎても入金確認されない received の注文は自動キャンセルされる。注文後は変更不可。';

-- 代理店も自分の担当顧客の注文の支払期限は見てよい (列 GRANT を追加)
grant select (payment_due_date) on public.orders to authenticated;

create index orders_unpaid_due_idx on public.orders (payment_due_date) where status = 'received';
create index orders_unpaid_email_idx
  on public.orders (lower(btrim(contact_email))) where status = 'received';
create index orders_unpaid_phone_idx
  on public.orders (regexp_replace(coalesce(contact_phone, ''), '[^0-9]', '', 'g'))
  where status = 'received';

-- 不変列に payment_due_date を追加 (それ以外は 0010 と同一)
create or replace function app.guard_orders_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.commerce_ctx', true), '');
begin
  if tg_op = 'UPDATE' then
    -- 原則4: 帰属・顧客・金額・注文番号・支払期限は誰にも変更させない (postgres 直接操作も含む)
    if new.agent_id is distinct from old.agent_id
       or new.customer_id is distinct from old.customer_id
       or new.referral_agent_id is distinct from old.referral_agent_id
       or new.order_no is distinct from old.order_no
       or new.subtotal is distinct from old.subtotal
       or new.shipping_fee is distinct from old.shipping_fee
       or new.total is distinct from old.total
       or new.ordered_at is distinct from old.ordered_at
       or new.payment_due_date is distinct from old.payment_due_date then
      raise exception
        'TREEMERCE_ORDER_IMMUTABLE: 注文の帰属代理店・顧客・金額・注文番号・支払期限は変更できません'
        using errcode = '42501';
    end if;
  end if;

  if current_user = 'postgres' and v_ctx = '' then
    if tg_op = 'DELETE' then
      raise exception 'TREEMERCE_ORDER_DELETE_DENIED: 注文は削除できません (キャンセルで扱う)'
        using errcode = '42501';
    end if;
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' and v_ctx = 'place_order' then
    return new;
  end if;
  if tg_op = 'UPDATE' and v_ctx = 'order_status' then
    return new;
  end if;

  raise exception
    'TREEMERCE_ORDER_WRITE_DENIED: 注文は専用の処理 (注文受付 / 管理者のステータス変更) でのみ書き込めます'
    using errcode = '42501';
end;
$fn$;

-- ============================================================================
-- 1-b. ステータス変更の共通処理 (内部専用)
-- ----------------------------------------------------------------------------
-- 認可は呼び出し側 (super_admin RPC / システムジョブ) で済ませてから呼ぶ。
-- anon / authenticated には EXECUTE を与えない。
-- 変更前後・理由・実行者・日時と在庫を戻したかどうかを、
-- order_status_history と admin_audit_logs の両方に保存する。
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
  v_before  public.orders%rowtype;
  v_after   public.orders%rowtype;
  v_restock boolean := (p_status = 'cancelled' and coalesce(p_restock, false));
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

  perform set_config('app.commerce_ctx', 'order_status', true);

  update public.orders
  set status       = p_status,
      paid_at      = case when p_status = 'payment_confirmed' then now() else paid_at end,
      shipped_at   = case when p_status = 'shipped'           then now() else shipped_at end,
      completed_at = case when p_status = 'completed'         then now() else completed_at end,
      cancelled_at = case when p_status = 'cancelled'         then now() else cancelled_at end
  where id = p_order_id
  returning * into v_after;

  if v_restock then
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
  values (p_order_id, v_before.status, p_status, btrim(p_reason), p_actor, p_actor_role);

  perform set_config('app.commerce_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (p_actor, p_actor_role, p_action, 'orders', p_order_id,
          jsonb_build_object('order_no', v_before.order_no, 'status', v_before.status),
          jsonb_build_object('order_no', v_after.order_no, 'status', v_after.status,
                             'restocked', v_restock),
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
-- 1-c. 支払期限切れの自動キャンセル (システムジョブ専用)
-- ----------------------------------------------------------------------------
-- 支払期限日 (payment_due_date) の当日中は入金を待ち、翌日 (日本時間) 以降に
-- まだ received のものを cancelled にして在庫を戻す。
-- 実行できるのは DB 管理者 (pg_cron のジョブ) のみ。anon / authenticated /
-- service_role には EXECUTE を与えない。
-- ============================================================================

create or replace function public.treemerce_system_cancel_expired_orders()
returns integer
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_id    uuid;
  v_count integer := 0;
begin
  for v_id in
    select o.id
    from public.orders o
    where o.status = 'received'
      and o.payment_due_date < v_today
    order by o.ordered_at
    for update skip locked
  loop
    perform app.apply_order_status_change(
      v_id, 'cancelled', '支払期限切れによる自動キャンセル',
      null, 'system', true, 'order.auto_cancel');
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$fn$;

revoke all on function public.treemerce_system_cancel_expired_orders()
  from public, anon, authenticated, service_role;

-- ============================================================================
-- 3. 注文ステータス変更 RPC を作り直す (p_restock を追加)
-- ----------------------------------------------------------------------------
--   received / payment_confirmed → cancelled : 在庫は常に戻す (未発送のため)
--   shipped → cancelled                       : p_restock の指定が必須。true のときだけ戻す
-- 引数が増えるため、旧 3 引数版は削除してから作り直す (呼び出しの曖昧さを避ける)。
-- ============================================================================

drop function if exists public.treemerce_admin_set_order_status(uuid, public.order_status, text);

create function public.treemerce_admin_set_order_status(
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
  v_current public.order_status;
  v_restock boolean := false;
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
    if v_current = 'shipped' then
      if p_restock is null then
        raise exception 'TREEMERCE_RESTOCK_REQUIRED: 発送済み注文のキャンセルでは、在庫を戻すかどうか (p_restock) を指定してください'
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

revoke all on function public.treemerce_admin_set_order_status(uuid, public.order_status, text, boolean)
  from public, anon, authenticated;
grant execute on function public.treemerce_admin_set_order_status(uuid, public.order_status, text, boolean)
  to authenticated;

-- ============================================================================
-- 2. 注文受付: 未入金 3 件までの制限 + 支払期限の確定
-- ----------------------------------------------------------------------------
-- 0011 からの変更点は次の 3 つだけ:
--   (a) 連絡先 (email / 電話) ごとのアドバイザリロックを取ってから未入金件数を数え、
--       3 件以上なら中立エラーで拒否 (同時送信による上限のすり抜けを防ぐ)。
--       判定は注文の連絡先だけで行い、顧客マスタを見ない = 既存顧客かどうかで差が出ない。
--   (b) payment_due_date を注文時点で確定して保存
--   (c) 応答の due_date は (b) の値を返す
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

  -- ---- (a) 未入金注文の上限 (連絡先ごと。顧客マスタは参照しない) --------------
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
-- 5. 公開商品一覧: max_quantity の上限を「在庫数と 10 の小さい方」に
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
               'max_quantity', least(p.stock, 10)
             ) order by p.sort_order, p.created_at)
      from public.products p
      where p.is_published
        and (p_product_id is null or p.id = p_product_id)
    ), '[]'::jsonb)
  );
end;
$fn$;

-- ============================================================================
-- 4. 客層分析: product_category を購入者の人数 (distinct customer) で数える
-- ----------------------------------------------------------------------------
-- 0011 からの変更点は agg_cat の集計単位だけ。各カテゴリの count は
-- 「そのカテゴリを購入した顧客の人数」になり、n<5 の丸めもその人数で判定する。
-- (1 人の顧客が複数カテゴリを買っていれば、それぞれのカテゴリで 1 人として数える)
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
    -- 購入者の人数で数える (明細件数ではない)
    select jsonb_agg(jsonb_build_object('key', category, 'count', n)) as buckets
    from (select category, count(distinct customer_id)::int as n from paid_lines group by 1) t
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
  'STEP6 客層分析。読み取り専用。購入カテゴリは購入者の人数、金額帯は顧客ごとの合計で集計 (入金確認済み以降の注文と完了済み購入のみ)。n<5 は丸める。';

-- ============================================================================
-- 1-d. 自動キャンセルの定期実行 (pg_cron)
-- ----------------------------------------------------------------------------
-- Supabase 標準の pg_cron 拡張で 1 時間ごと (毎時 5 分) に実行する。
-- ジョブは DB 管理者 (postgres) として動くため、service_role キーやアプリ側の
-- 秘密情報は不要。pg_cron が使えない環境 (ローカルの PGlite テスト等) では何もしない。
-- 同名のジョブが既にあれば作り直す (このファイルを再実行しても重複しない)。
-- ============================================================================

do $do$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    raise notice '0013: pg_cron が利用できないため、自動キャンセルの定期実行は登録していません';
    return;
  end if;

  execute 'create extension if not exists pg_cron with schema pg_catalog';

  execute $q$
    select cron.unschedule(jobid) from cron.job
    where jobname = 'treemerce-cancel-expired-orders'
  $q$;

  execute $q$
    select cron.schedule(
      'treemerce-cancel-expired-orders',
      '5 * * * *',
      'select public.treemerce_system_cancel_expired_orders()'
    )
  $q$;
end;
$do$;

commit;
