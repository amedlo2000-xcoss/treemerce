-- ============================================================================
-- TREEMERCE : 0010_treemerce_commerce_schema.sql
-- 商品登録・注文機能 (STEP1: テーブル / 制約 / 不変トリガ / RLS・GRANT)
-- ----------------------------------------------------------------------------
-- 絶対原則との対応
--   原則1 : customers には列を追加しない。注文の帰属は orders.agent_id に持つ。
--   原則3 : 注文の帰属 (orders.agent_id) と担当 (customer_assignments) は別データ。
--           担当変更が過去注文の帰属を書き換えることはない (逆も同じ)。
--   原則4 : orders.agent_id は注文時点の担当代理店をサーバー側でコピーし、
--           以後は誰にも (postgres 直接操作でも) 変更できない。
--   原則5 : 注文の実データ (氏名・配送先・明細) が見えるのは
--           「その顧客を現に担当している代理店」と ADMIN だけ。
--           担当変更後、旧担当からは実データが見えなくなる (帰属は旧担当のまま)。
--   派生  : orders.referral_agent_id (経由した紹介リンク) は ADMIN 専用。
--           一般代理店には列 GRANT を与えない。
--
-- 書込みは 0011 の SECURITY DEFINER RPC からのみ行う。anon / authenticated には
-- これらのテーブルへの INSERT / UPDATE / DELETE の GRANT を一切与えない。
-- ============================================================================

begin;

-- ============================================================================
-- 1. 列挙型
-- ============================================================================

create type public.order_status as enum
  ('received', 'payment_confirmed', 'shipped', 'completed', 'cancelled');

comment on type public.order_status is
  'received=注文受付 / payment_confirmed=入金確認済み / shipped=発送済み / completed=完了 / cancelled=キャンセル';

-- ============================================================================
-- 2. products (商品マスタ)
-- ============================================================================

create table public.products (
  id           uuid primary key default gen_random_uuid(),
  sku          text unique,
  name         text not null check (btrim(name) <> ''),
  description  text,
  category     public.product_category not null default 'other',
  price        numeric(12, 2) not null check (price >= 0),
  stock        integer not null default 0 check (stock >= 0),
  is_published boolean not null default false,
  image_path   text,
  sort_order   integer not null default 0,
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index products_published_idx on public.products (is_published, sort_order, created_at);

create trigger products_touch_updated_at
  before update on public.products
  for each row execute function app.touch_updated_at();

-- ============================================================================
-- 3. orders (注文ヘッダ)
-- ============================================================================

create sequence public.order_no_seq start with 1;

create table public.orders (
  id                uuid primary key default gen_random_uuid(),
  order_no          text not null unique,
  customer_id       uuid not null references public.customers (id) on delete restrict,

  -- 原則4: 注文時点の担当代理店。サーバー側で customer_assignments から複写し、以後不変。
  agent_id          uuid not null references public.agents (id) on delete restrict,

  -- 経由した紹介リンクの代理店。ADMIN 専用 (一般代理店に列 GRANT を与えない)。
  -- 既存顧客が別代理店のリンクから注文した場合、agent_id とは異なる値になる。
  referral_agent_id uuid references public.agents (id) on delete restrict,

  status            public.order_status not null default 'received',

  subtotal          numeric(12, 2) not null check (subtotal >= 0),
  shipping_fee      numeric(12, 2) not null default 0 check (shipping_fee >= 0),
  total             numeric(12, 2) not null check (total >= 0),
  currency          text not null default 'JPY',

  -- 注文ごとの配送先スナップショット。顧客マスタは注文で上書きしない。
  ship_name         text not null check (btrim(ship_name) <> ''),
  ship_postal_code  text,
  ship_address      text not null check (btrim(ship_address) <> ''),
  ship_phone        text,
  contact_email     text,
  contact_phone     text,
  customer_note     text,

  -- 既存顧客と識別子は一致したが氏名が異なる注文 (ADMIN の確認用。代理店には見せない)
  identity_mismatch boolean not null default false,

  ordered_at        timestamptz not null default now(),
  paid_at           timestamptz,
  shipped_at        timestamptz,
  completed_at      timestamptz,
  cancelled_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint orders_total_matches check (total = subtotal + shipping_fee),
  constraint orders_contact_required
    check (nullif(btrim(coalesce(contact_email, '')), '') is not null
        or nullif(btrim(coalesce(contact_phone, '')), '') is not null)
);

comment on column public.orders.agent_id is
  '注文時点の担当代理店 (売上の帰属)。一度設定したら変更不可。担当変更の影響を受けない。';
comment on column public.orders.referral_agent_id is
  '経由した紹介リンクの代理店。ADMIN 専用。一般代理店には列 GRANT を与えない。';

create index orders_customer_idx on public.orders (customer_id, ordered_at desc);
create index orders_agent_idx    on public.orders (agent_id, ordered_at desc);
create index orders_status_idx   on public.orders (status, ordered_at desc);

create or replace function app.assign_order_no()
returns trigger
language plpgsql
as $fn$
begin
  if new.order_no is null or btrim(new.order_no) = '' then
    new.order_no := 'TM-' || to_char(now() at time zone 'Asia/Tokyo', 'YYYYMMDD') || '-'
                    || lpad(nextval('public.order_no_seq')::text, 6, '0');
  end if;
  return new;
end;
$fn$;

create trigger orders_assign_order_no
  before insert on public.orders
  for each row execute function app.assign_order_no();

create trigger orders_touch_updated_at
  before update on public.orders
  for each row execute function app.touch_updated_at();

-- ============================================================================
-- 4. order_items (明細。商品名・カテゴリ・単価は注文時点のスナップショット)
-- ============================================================================

create table public.order_items (
  id               uuid primary key default gen_random_uuid(),
  order_id         uuid not null references public.orders (id) on delete restrict,
  product_id       uuid not null references public.products (id) on delete restrict,
  product_name     text not null check (btrim(product_name) <> ''),
  product_sku      text,
  product_category public.product_category not null,
  unit_price       numeric(12, 2) not null check (unit_price >= 0),
  quantity         integer not null check (quantity between 1 and 99),
  amount           numeric(12, 2) not null check (amount >= 0),
  created_at       timestamptz not null default now(),

  constraint order_items_amount_matches check (amount = unit_price * quantity)
);

create index order_items_order_idx   on public.order_items (order_id);
create index order_items_product_idx on public.order_items (product_id);

-- ============================================================================
-- 5. order_status_history (ステータス変更履歴。追記専用)
-- ============================================================================

create table public.order_status_history (
  id              uuid primary key default gen_random_uuid(),
  order_id        uuid not null references public.orders (id) on delete restrict,
  from_status     public.order_status,
  to_status       public.order_status not null,
  reason          text not null check (btrim(reason) <> ''),
  changed_by      uuid references auth.users (id) on delete set null,
  changed_by_role text not null,
  changed_at      timestamptz not null default clock_timestamp()
);

create index order_status_history_order_idx
  on public.order_status_history (order_id, changed_at desc);

-- ============================================================================
-- 6. shop_settings (運営の振込先・特定商取引法に基づく表記。1 行のみ)
-- ----------------------------------------------------------------------------
-- 振込先はここに持つ「運営の口座」。bank_accounts (代理店の報酬受取口座) とは別物。
-- ============================================================================

create table public.shop_settings (
  id                    smallint primary key default 1 check (id = 1),

  -- 特定商取引法に基づく表記
  seller_name           text,
  seller_representative text,
  seller_address        text,
  seller_phone          text,
  seller_email          text,
  business_hours        text,
  price_note            text,
  additional_fees       text,
  payment_method_note   text,
  delivery_time         text,
  return_policy         text,
  extra_notes           text,

  -- 注文
  shipping_fee          numeric(12, 2) not null default 0 check (shipping_fee >= 0),
  payment_due_days      integer not null default 7 check (payment_due_days between 1 and 60),
  is_accepting_orders   boolean not null default false,

  -- 運営の振込先
  bank_name             text,
  bank_branch           text,
  bank_account_type     public.bank_account_type,
  bank_account_number   text,
  bank_account_holder   text,

  updated_by            uuid references auth.users (id) on delete set null,
  updated_at            timestamptz not null default now()
);

insert into public.shop_settings (id) values (1);

create trigger shop_settings_touch_updated_at
  before update on public.shop_settings
  for each row execute function app.touch_updated_at();

-- ============================================================================
-- 7. 書込みガード (多層防御)
-- ----------------------------------------------------------------------------
-- 書込みは 0011 の RPC が張るコンテキスト (GUC app.commerce_ctx) の中でのみ許可する。
--   'place_order'  : 注文受付 (orders / order_items / 初回履歴の INSERT)
--   'order_status' : ADMIN によるステータス変更 (orders の UPDATE / 履歴 INSERT)
-- DB 管理者 (postgres) のコンテキスト外の直接操作は、既存の担当ガードと同じく
-- 障害復旧経路として許可する。ただし帰属 (agent_id) などの不変列は postgres でも変更不可。
-- ============================================================================

create or replace function app.guard_orders_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.commerce_ctx', true), '');
begin
  if tg_op = 'UPDATE' then
    -- 原則4: 帰属・顧客・金額・注文番号は誰にも変更させない (postgres 直接操作も含む)
    if new.agent_id is distinct from old.agent_id
       or new.customer_id is distinct from old.customer_id
       or new.referral_agent_id is distinct from old.referral_agent_id
       or new.order_no is distinct from old.order_no
       or new.subtotal is distinct from old.subtotal
       or new.shipping_fee is distinct from old.shipping_fee
       or new.total is distinct from old.total
       or new.ordered_at is distinct from old.ordered_at then
      raise exception
        'TREEMERCE_ORDER_IMMUTABLE: 注文の帰属代理店・顧客・金額・注文番号は変更できません'
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

create trigger orders_guard
  before insert or update or delete on public.orders
  for each row execute function app.guard_orders_write();

-- 状態遷移の検証 (RPC 側でも検証するが、DB 層でも強制する)
create or replace function app.enforce_order_status_transition()
returns trigger
language plpgsql
as $fn$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  if not (
       (old.status = 'received'          and new.status in ('payment_confirmed', 'cancelled'))
    or (old.status = 'payment_confirmed' and new.status in ('shipped', 'cancelled'))
    or (old.status = 'shipped'           and new.status in ('completed', 'cancelled'))
  ) then
    raise exception 'TREEMERCE_INVALID_TRANSITION: % から % へは変更できません',
      old.status, new.status
      using errcode = '22023';
  end if;
  return new;
end;
$fn$;

create trigger orders_status_transition
  before update of status on public.orders
  for each row execute function app.enforce_order_status_transition();

create or replace function app.guard_order_items_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.commerce_ctx', true), '');
begin
  if tg_op = 'INSERT' and (v_ctx = 'place_order' or (current_user = 'postgres' and v_ctx = '')) then
    return new;
  end if;
  raise exception 'TREEMERCE_ORDER_ITEMS_IMMUTABLE: 注文明細は注文受付時にのみ作成でき、変更・削除できません'
    using errcode = '42501';
end;
$fn$;

create trigger order_items_guard
  before insert or update or delete on public.order_items
  for each row execute function app.guard_order_items_write();

create or replace function app.guard_order_history_append_only()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.commerce_ctx', true), '');
begin
  if tg_op = 'INSERT'
     and (v_ctx in ('place_order', 'order_status') or (current_user = 'postgres' and v_ctx = '')) then
    return new;
  end if;
  raise exception 'TREEMERCE_ORDER_HISTORY_APPEND_ONLY: 注文ステータス履歴は追記専用です'
    using errcode = '42501';
end;
$fn$;

create trigger order_status_history_guard
  before insert or update or delete on public.order_status_history
  for each row execute function app.guard_order_history_append_only();

-- ============================================================================
-- 8. 閲覧可否ヘルパー
-- ============================================================================

-- 原則5: 注文の実データが見えるのは ADMIN と「その顧客を現に担当している代理店」のみ。
-- orders.agent_id (帰属) ではなく現在の担当で判定する。
create or replace function app.can_view_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select app.is_admin()
      or exists (
           select 1 from public.orders o
           where o.id = p_order_id
             and app.is_assigned_agent(o.customer_id)
         );
$fn$;

comment on function app.can_view_order(uuid) is
  '原則5: ADMIN または注文の顧客を現に担当している代理店のみ true。帰属 (agent_id) では判定しない。';

-- ============================================================================
-- 9. RLS / GRANT
-- ----------------------------------------------------------------------------
-- Supabase は public スキーマの新規オブジェクトに anon / authenticated へ全権限を
-- 自動付与するため、ここで明示的に剥がしてから必要分だけ付け直す。
-- ============================================================================

revoke all on public.products, public.orders, public.order_items,
              public.order_status_history, public.shop_settings
  from anon, authenticated;
revoke all on sequence public.order_no_seq from anon, authenticated;

revoke all on function app.assign_order_no()                  from public, anon, authenticated;
revoke all on function app.guard_orders_write()               from public, anon, authenticated;
revoke all on function app.enforce_order_status_transition()  from public, anon, authenticated;
revoke all on function app.guard_order_items_write()          from public, anon, authenticated;
revoke all on function app.guard_order_history_append_only()  from public, anon, authenticated;
revoke all on function app.can_view_order(uuid)               from public, anon, authenticated;

alter table public.products             enable row level security;
alter table public.orders               enable row level security;
alter table public.order_items          enable row level security;
alter table public.order_status_history enable row level security;
alter table public.shop_settings        enable row level security;

-- products: 公開中のものはログイン済みなら誰でも。非公開は ADMIN のみ。
-- (未ログインの購入者は 0011 の treemerce_shop_products RPC 経由で閲覧する)
create policy products_select on public.products
  for select to authenticated
  using (products.is_published or app.is_admin());

grant select on public.products to authenticated;

-- orders: 原則5 (現担当のみ)。referral_agent_id / identity_mismatch は列 GRANT から除外。
create policy orders_select on public.orders
  for select to authenticated
  using (app.is_admin() or app.is_assigned_agent(orders.customer_id));

grant select (id, order_no, customer_id, agent_id, status, subtotal, shipping_fee, total,
              currency, ship_name, ship_postal_code, ship_address, ship_phone,
              contact_email, contact_phone, customer_note, ordered_at, paid_at,
              shipped_at, completed_at, cancelled_at, created_at, updated_at)
  on public.orders to authenticated;

create policy order_items_select on public.order_items
  for select to authenticated
  using (app.can_view_order(order_items.order_id));

grant select on public.order_items to authenticated;

-- 履歴・ショップ設定のテーブル直接参照は ADMIN のみ
create policy order_status_history_select on public.order_status_history
  for select to authenticated
  using (app.is_admin());

grant select on public.order_status_history to authenticated;

create policy shop_settings_select on public.shop_settings
  for select to authenticated
  using (app.is_admin());

grant select on public.shop_settings to authenticated;

-- RLS ポリシー式の評価に必要
grant execute on function app.can_view_order(uuid) to authenticated;

commit;
