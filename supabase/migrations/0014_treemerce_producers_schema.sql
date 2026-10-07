-- ============================================================================
-- TREEMERCE : 0014_treemerce_producers_schema.sql
-- 生産者マスタ・生産者直送 (STEP1: テーブル / 制約 / 不変トリガ / RLS・GRANT / 既存商品の移行)
-- ----------------------------------------------------------------------------
-- 販売元は運営 1 つのまま (shop_settings は変更しない)。発送は各生産者がお客様へ直接行う。
--
--   producers        : 生産者マスタ。連絡先・発送依頼の送り先は super_admin 専用
--                      (テーブルの列 GRANT から除外し、0015 の super_admin RPC でのみ返す)。
--   products         : producer_id (必須) / 内容量・規格 / 原材料・成分 / 期限の目安 を追加。
--   order_items      : 注文時点の producer_id / 内容量 のスナップショットを追加。
--                      既存行は更新しない (NULL = 移行前の旧注文。旧注文は従来の手動フロー)。
--   order_shipments  : 注文 × 生産者 ごとの発送記録。代理店を指す列は持たない。
--
-- 絶対原則との対応
--   原則1   : customers には列を追加しない。producers は代理店とも顧客とも別テーブル。
--   原則3・4: order_shipments は agent_id を持たない。売上の帰属は orders.agent_id のみで、
--             発送記録の更新が帰属を変えることはない (0013 の不変トリガが引き続き拒否する)。
--   原則5   : 一般代理店には producers / order_shipments のテーブル権限を与えない。
--             order_items は列 GRANT に切り替え、producer_id を代理店に見せない。
--
-- 既存商品の移行: 仮の生産者「未設定（運営）」(固定 UUID) を作り、全商品をひも付ける。
-- 正しい生産者は公開前に管理画面で選び直す運用とする。
-- 書込みは 0015 の SECURITY DEFINER RPC からのみ行う。
-- ============================================================================

begin;

-- ============================================================================
-- 1. 列挙型
-- ============================================================================

create type public.shipment_status as enum
  ('awaiting_payment', 'ready', 'requested', 'shipped', 'cancelled');

comment on type public.shipment_status is
  'awaiting_payment=入金待ち / ready=発送依頼可能 (入金確認済み) / requested=発送依頼済み / shipped=発送済み / cancelled=キャンセル';

-- ============================================================================
-- 2. producers (生産者マスタ)
-- ============================================================================

create table public.producers (
  id                   uuid primary key default gen_random_uuid(),

  -- 公開項目 (商品ページに表示)
  name                 text not null check (btrim(name) <> ''),
  origin               text,
  ship_from_prefecture text,
  ship_lead_time       text,

  -- 非公開項目 (super_admin 専用。列 GRANT を与えない)
  notify_email         text,
  contact_name         text,
  contact_phone        text,
  contact_email        text,
  note                 text,

  is_active            boolean not null default true,
  -- 既存商品の移行用の仮の生産者 (1 行のみ)。管理 RPC からは編集できない。
  is_placeholder       boolean not null default false,

  created_by           uuid references auth.users (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  -- 仮の生産者以外は公開項目が必須
  constraint producers_public_fields_required check (
    is_placeholder
    or (    nullif(btrim(coalesce(origin, '')), '') is not null
        and nullif(btrim(coalesce(ship_from_prefecture, '')), '') is not null
        and nullif(btrim(coalesce(ship_lead_time, '')), '') is not null)
  ),
  constraint producers_prefecture_valid check (
    ship_from_prefecture is null or ship_from_prefecture in (
      '北海道', '青森県', '岩手県', '宮城県', '秋田県', '山形県', '福島県',
      '茨城県', '栃木県', '群馬県', '埼玉県', '千葉県', '東京都', '神奈川県',
      '新潟県', '富山県', '石川県', '福井県', '山梨県', '長野県', '岐阜県',
      '静岡県', '愛知県', '三重県', '滋賀県', '京都府', '大阪府', '兵庫県',
      '奈良県', '和歌山県', '鳥取県', '島根県', '岡山県', '広島県', '山口県',
      '徳島県', '香川県', '愛媛県', '高知県', '福岡県', '佐賀県', '長崎県',
      '熊本県', '大分県', '宮崎県', '鹿児島県', '沖縄県')
  ),
  constraint producers_notify_email_format check (
    notify_email is null or notify_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
  ),
  constraint producers_contact_email_format check (
    contact_email is null or contact_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
  )
);

comment on table public.producers is
  '生産者マスタ。name / origin / ship_from_prefecture / ship_lead_time は公開項目。'
  'notify_email / contact_* / note は super_admin 専用 (列 GRANT なし、RPC でのみ返す)。';
comment on column public.producers.notify_email is
  '発送依頼の送り先メール (非公開)。NULL の場合は管理画面の発送依頼書をコピーして手動で依頼する。';

create unique index producers_single_placeholder on public.producers (is_placeholder) where is_placeholder;
create index producers_active_idx on public.producers (is_active, name);

create trigger producers_touch_updated_at
  before update on public.producers
  for each row execute function app.touch_updated_at();

-- 仮の生産者 (固定 UUID)。既存商品・生産者未指定の商品はここにひも付く。
insert into public.producers (id, name, is_active, is_placeholder)
values ('00000000-0000-4000-8000-000000000001', '未設定（運営）', true, true);

-- ============================================================================
-- 3. products に列を追加 (既存商品はすべて仮の生産者へ移行)
-- ============================================================================

alter table public.products
  add column producer_id uuid not null
    default '00000000-0000-4000-8000-000000000001'
    references public.producers (id) on delete restrict,
  add column content_volume   text,
  add column ingredients      text,
  add column best_before_note text;

comment on column public.products.producer_id is
  '生産者 (必須)。既存商品は仮の生産者「未設定（運営）」に移行済み。公開前に正しい生産者を選ぶ。';
comment on column public.products.content_volume   is '内容量・規格 (例: 500g×2袋)';
comment on column public.products.ingredients      is '原材料・成分';
comment on column public.products.best_before_note is '賞味期限 / 使用期限の目安 (任意)';

create index products_producer_idx on public.products (producer_id);

-- ============================================================================
-- 4. order_items に注文時点のスナップショット列を追加
-- ----------------------------------------------------------------------------
-- 既存行は更新しない (0010 の guard_order_items_write は INSERT 以外を拒否する)。
-- producer_id IS NULL = 移行前の旧注文。
-- ============================================================================

alter table public.order_items
  add column producer_id uuid references public.producers (id) on delete restrict,
  add column product_content_volume text;

comment on column public.order_items.producer_id is
  '注文時点の生産者 (スナップショット)。NULL は生産者機能の導入前の旧注文。';

create index order_items_producer_idx on public.order_items (order_id, producer_id);

-- ============================================================================
-- 5. order_shipments (注文 × 生産者 の発送記録)
-- ============================================================================

create table public.order_shipments (
  id                  uuid primary key default gen_random_uuid(),
  order_id            uuid not null references public.orders (id) on delete restrict,
  producer_id         uuid not null references public.producers (id) on delete restrict,
  producer_name       text not null check (btrim(producer_name) <> ''),

  status              public.shipment_status not null default 'awaiting_payment',

  carrier             text,
  tracking_number     text,
  shipped_on          date,

  -- 発送依頼の記録 (送り先メールアドレスや本文は保存しない)
  request_channel     text check (request_channel is null or request_channel in ('email', 'manual')),
  requested_at        timestamptz,
  request_count       integer not null default 0 check (request_count >= 0),
  last_notify_error   text,
  provider_message_id text,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint order_shipments_unique_producer unique (order_id, producer_id),
  constraint order_shipments_shipped_on_required
    check (status <> 'shipped' or shipped_on is not null)
);

comment on table public.order_shipments is
  '注文 × 生産者 の発送記録。代理店を指す列は持たない (帰属は orders.agent_id のみ)。一般代理店には見せない。';

create index order_shipments_order_idx  on public.order_shipments (order_id);
create index order_shipments_status_idx on public.order_shipments (status, producer_id);

create trigger order_shipments_touch_updated_at
  before update on public.order_shipments
  for each row execute function app.touch_updated_at();

-- ============================================================================
-- 6. 書込みガード (多層防御)
-- ----------------------------------------------------------------------------
-- コンテキスト (GUC app.commerce_ctx):
--   'producer'     : 生産者の登録・編集 (producers の INSERT / UPDATE)
--   'place_order'  : 注文受付 (order_shipments の INSERT)
--   'order_status' : 注文ステータス変更に伴う発送記録の更新
--   'shipment'     : 発送記録の更新 (発送登録・依頼記録)
-- DB 管理者 (postgres) のコンテキスト外の直接操作は障害復旧経路として許可する
-- (既存のガードと同じ方針)。ただし削除と、発送記録の注文・生産者の付け替えは不可。
-- ============================================================================

create or replace function app.guard_producers_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.commerce_ctx', true), '');
begin
  if tg_op = 'DELETE' then
    raise exception 'TREEMERCE_PRODUCER_DELETE_DENIED: 生産者は削除できません (無効化で扱う)'
      using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.is_placeholder is distinct from old.is_placeholder then
    raise exception 'TREEMERCE_PRODUCER_IMMUTABLE: 仮の生産者の区分は変更できません'
      using errcode = '42501';
  end if;

  if current_user = 'postgres' and v_ctx = '' then
    return new;
  end if;
  if v_ctx = 'producer' then
    return new;
  end if;

  raise exception
    'TREEMERCE_PRODUCER_WRITE_DENIED: 生産者は専用の処理 (super_admin の登録・編集) でのみ書き込めます'
    using errcode = '42501';
end;
$fn$;

create trigger producers_guard
  before insert or update or delete on public.producers
  for each row execute function app.guard_producers_write();

create or replace function app.guard_order_shipments_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.commerce_ctx', true), '');
begin
  if tg_op = 'DELETE' then
    raise exception 'TREEMERCE_SHIPMENT_DELETE_DENIED: 発送記録は削除できません'
      using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' then
    -- 発送記録の注文・生産者の付け替えは誰にもさせない (postgres 直接操作も含む)
    if new.order_id is distinct from old.order_id
       or new.producer_id is distinct from old.producer_id
       or new.producer_name is distinct from old.producer_name then
      raise exception
        'TREEMERCE_SHIPMENT_IMMUTABLE: 発送記録の注文・生産者は変更できません'
        using errcode = '42501';
    end if;
  end if;

  if current_user = 'postgres' and v_ctx = '' then
    return new;
  end if;
  if tg_op = 'INSERT' and v_ctx = 'place_order' then
    return new;
  end if;
  if tg_op = 'UPDATE' and v_ctx in ('order_status', 'shipment') then
    return new;
  end if;

  raise exception
    'TREEMERCE_SHIPMENT_WRITE_DENIED: 発送記録は専用の処理 (注文受付 / super_admin の発送管理) でのみ書き込めます'
    using errcode = '42501';
end;
$fn$;

create trigger order_shipments_guard
  before insert or update or delete on public.order_shipments
  for each row execute function app.guard_order_shipments_write();

-- ============================================================================
-- 7. RLS / GRANT
-- ----------------------------------------------------------------------------
-- Supabase の既定 GRANT を剥がしてから必要分だけ付け直す (0010 と同じ手順)。
-- ============================================================================

revoke all on public.producers, public.order_shipments from anon, authenticated;

revoke all on function app.guard_producers_write()        from public, anon, authenticated;
revoke all on function app.guard_order_shipments_write()  from public, anon, authenticated;

alter table public.producers       enable row level security;
alter table public.order_shipments enable row level security;

-- producers: ADMIN (support / admin / super_admin) は公開項目のみ直接参照できる。
-- 連絡先・発送依頼の送り先・メモは列 GRANT から除外 (super_admin RPC でのみ返す)。
-- 一般代理店はポリシーで 0 行。購入者は公開 RPC (treemerce_shop_products) 経由のみ。
create policy producers_select on public.producers
  for select to authenticated
  using (app.is_admin());

grant select (id, name, origin, ship_from_prefecture, ship_lead_time,
              is_active, is_placeholder, created_at, updated_at)
  on public.producers to authenticated;

-- order_shipments: ADMIN (support / admin / super_admin) のみ。一般代理店は 0 行。
create policy order_shipments_select on public.order_shipments
  for select to authenticated
  using (app.is_admin());

grant select on public.order_shipments to authenticated;

-- order_items: テーブル単位の GRANT を列 GRANT に切り替え、producer_id を除外する。
-- (現担当の代理店には従来どおり明細が見える。生産者とのひも付けは見せない)
revoke select on public.order_items from authenticated;
grant select (id, order_id, product_id, product_name, product_sku, product_category,
              unit_price, quantity, amount, product_content_volume, created_at)
  on public.order_items to authenticated;

commit;
