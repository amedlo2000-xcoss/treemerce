-- ============================================================================
-- TREEMERCE : 代理店 / 商品購入者 分離管理システム
-- 0001_treemerce_init.sql   (STEP1: データモデル)
-- ----------------------------------------------------------------------------
-- 絶対原則 (CLAUDE.md) を DB 層で強制するための初期スキーマ。
--   1. agents と customers は同一会員区分ではない (別テーブル・別権限)
--   2. agents.invited_by は単一カラム。設定済みの再設定は不可 (immutable trigger)
--   3. 登録経路 (invited_by) と 顧客担当 (customer_assignments) は完全に別データ
--   4. 担当代理店は初回登録で確定・固定。一般代理店は変更/解除/移管 不可
--   5. 他代理店担当顧客の PII は行レベルで不可視
--   6. 重複検知しても担当は自動変更しない
--   7. 照合は email / 電話番号 等の識別子。氏名一致のみでは同定しない
--   8. 担当変更は ADMIN 専用。履歴と監査ログを必ず残す
-- ============================================================================

begin;

-- ============================================================================
-- 0. スキーマ
-- ============================================================================

create schema if not exists app;
comment on schema app is 'TREEMERCE: 権限判定・匿名化集計・書込みを行うサーバー強制ロジック置き場';

revoke all on schema app from public;
grant usage on schema app to anon, authenticated, service_role;

-- ============================================================================
-- 1. 列挙型
-- ============================================================================

create type public.agent_status as enum ('pending', 'active', 'suspended', 'withdrawn');
create type public.invitation_status as enum ('active', 'revoked', 'expired');

create type public.customer_age_group as enum
  ('under_20', '20s', '30s', '40s', '50s', '60s', '70_plus', 'unknown');
create type public.customer_gender as enum ('male', 'female', 'other', 'prefer_not_to_say');
create type public.customer_kind as enum ('individual', 'corporate', 'sole_proprietor', 'other');

create type public.assignment_source as enum
  ('initial_registration', 'admin_transfer', 'migration', 'system');
create type public.assignment_status as enum ('active', 'superseded', 'released');

create type public.product_category as enum
  ('health', 'beauty', 'food', 'apparel', 'household', 'digital', 'service', 'other');
create type public.purchase_status as enum ('pending', 'completed', 'cancelled', 'refunded');

create type public.benefit_type as enum
  ('referral_bonus', 'sales_commission', 'tier_bonus', 'adjustment');
create type public.benefit_status as enum ('pending', 'confirmed', 'paid', 'cancelled');

create type public.bank_account_type as enum ('ordinary', 'checking', 'savings');

create type public.notification_category as enum
  ('system', 'assignment', 'purchase', 'benefit', 'invitation');

create type public.admin_role_name as enum ('support', 'admin', 'super_admin');

-- ============================================================================
-- 2. 共通トリガ関数
-- ============================================================================

create or replace function app.touch_updated_at()
returns trigger
language plpgsql
as $fn$
begin
  new.updated_at := now();
  return new;
end;
$fn$;

-- ============================================================================
-- 3. agents (代理店)
-- ============================================================================

create sequence if not exists public.agent_public_id_seq start with 1001;

create table public.agents (
  id               uuid primary key default gen_random_uuid(),
  auth_user_id     uuid unique references auth.users (id) on delete set null,
  public_id        text not null unique,
  display_name     text not null check (btrim(display_name) <> ''),
  legal_name       text,
  email            text not null,
  email_normalized text generated always as (nullif(lower(btrim(email)), '')) stored,
  phone            text,
  phone_normalized text generated always as
                     (nullif(regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g'), '')) stored,
  profile_bio      text,
  avatar_url       text,
  prefecture       text,
  registered_at    timestamptz not null default now(),
  status           public.agent_status not null default 'pending',

  -- 絶対原則2: 招待元は単一カラムの UUID 外部キー。1代理店につき必ず1つのみ。
  invited_by       uuid references public.agents (id) on delete restrict,

  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint agents_no_self_invite check (invited_by is null or invited_by <> id)
);

comment on column public.agents.invited_by is
  '招待元代理店ID。単一カラム・単一値。一度設定したら変更不可。顧客担当とは無関係。';

create unique index agents_email_normalized_key on public.agents (email_normalized)
  where email_normalized is not null;
create index agents_invited_by_idx on public.agents (invited_by);
create index agents_status_idx on public.agents (status);

create or replace function app.assign_agent_public_id()
returns trigger
language plpgsql
as $fn$
begin
  if new.public_id is null or btrim(new.public_id) = '' then
    new.public_id := 'AG-' || lpad(nextval('public.agent_public_id_seq')::text, 6, '0');
  end if;
  return new;
end;
$fn$;

create trigger agents_assign_public_id
  before insert on public.agents
  for each row execute function app.assign_agent_public_id();

create trigger agents_touch_updated_at
  before update on public.agents
  for each row execute function app.touch_updated_at();

-- 絶対原則2: invited_by の再設定を DB 層で拒否する
create or replace function app.enforce_invited_by_immutable()
returns trigger
language plpgsql
as $fn$
begin
  if old.invited_by is not null and new.invited_by is distinct from old.invited_by then
    raise exception
      'TREEMERCE_INVITED_BY_ALREADY_SET: agent % already has an inviter; re-assignment is forbidden',
      old.id
      using errcode = '23514';
  end if;
  return new;
end;
$fn$;

create trigger agents_invited_by_immutable
  before update on public.agents
  for each row execute function app.enforce_invited_by_immutable();

-- 招待経路の循環防止 (再帰CTEの無限ループを構造的に排除)
create or replace function app.enforce_invited_by_acyclic()
returns trigger
language plpgsql
as $fn$
declare
  v_cursor uuid := new.invited_by;
  v_depth  int  := 0;
begin
  while v_cursor is not null loop
    if v_cursor = new.id then
      raise exception 'TREEMERCE_INVITE_CYCLE: invited_by chain is cyclic'
        using errcode = '23514';
    end if;
    v_depth := v_depth + 1;
    if v_depth > 100 then
      raise exception 'TREEMERCE_INVITE_CHAIN_TOO_DEEP: invited_by chain exceeds 100 levels'
        using errcode = '23514';
    end if;
    select a.invited_by into v_cursor from public.agents a where a.id = v_cursor;
  end loop;
  return new;
end;
$fn$;

create trigger agents_invited_by_acyclic
  before insert or update of invited_by on public.agents
  for each row when (new.invited_by is not null)
  execute function app.enforce_invited_by_acyclic();

-- ============================================================================
-- 4. agent_invitations (代理店招待URL)
-- ============================================================================

create table public.agent_invitations (
  id               uuid primary key default gen_random_uuid(),
  inviter_agent_id uuid not null references public.agents (id) on delete cascade,
  code             text not null unique check (btrim(code) <> ''),
  status           public.invitation_status not null default 'active',
  max_uses         integer check (max_uses is null or max_uses > 0),
  used_count       integer not null default 0 check (used_count >= 0),
  note             text,
  expires_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index agent_invitations_inviter_idx on public.agent_invitations (inviter_agent_id);

create trigger agent_invitations_touch_updated_at
  before update on public.agent_invitations
  for each row execute function app.touch_updated_at();

-- どの招待から登録されたかの記録 (監査用。ツリーの正は agents.invited_by)
create table public.agent_invitation_uses (
  id            uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.agent_invitations (id) on delete cascade,
  agent_id      uuid not null unique references public.agents (id) on delete cascade,
  used_at       timestamptz not null default now()
);

-- ============================================================================
-- 5. customers (商品購入者)  ※ agents とは完全に別の会員区分 (絶対原則1)
-- ============================================================================

create table public.customers (
  id                uuid primary key default gen_random_uuid(),
  auth_user_id      uuid unique references auth.users (id) on delete set null,
  full_name         text not null check (btrim(full_name) <> ''),
  full_name_kana    text,
  email             text,
  email_normalized  text generated always as (nullif(lower(btrim(email)), '')) stored,
  phone             text,
  phone_normalized  text generated always as
                      (nullif(regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g'), '')) stored,
  postal_code       text,
  address_line      text,
  first_assigned_at timestamptz not null default now(),
  age_group         public.customer_age_group,
  gender            public.customer_gender,
  prefecture        text,
  customer_type     public.customer_kind not null default 'individual',
  note              text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint customers_requires_identifier
    check (nullif(lower(btrim(coalesce(email, ''))), '') is not null
        or nullif(regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g'), '') is not null)
);

comment on table public.customers is
  '商品購入者。代理店(agents)とは別会員区分。担当代理店は customer_assignments でのみ表現する。';
comment on constraint customers_requires_identifier on public.customers is
  '絶対原則7: 同一人物判定に使える識別子(email/電話)を必ず1つ以上持たせる。氏名のみでの同定はしない。';

-- 絶対原則7: 識別子ベースの重複検知。氏名には一意制約を張らない。
create unique index customers_email_normalized_key on public.customers (email_normalized)
  where email_normalized is not null;
create unique index customers_phone_normalized_key on public.customers (phone_normalized)
  where phone_normalized is not null;

create index customers_age_group_idx on public.customers (age_group);
create index customers_prefecture_idx on public.customers (prefecture);

create trigger customers_touch_updated_at
  before update on public.customers
  for each row execute function app.touch_updated_at();

-- ============================================================================
-- 6. customer_assignments (顧客担当)  ※ 登録経路とは別データ (絶対原則3)
-- ============================================================================

create table public.customer_assignments (
  id                uuid primary key default gen_random_uuid(),
  customer_id       uuid not null references public.customers (id) on delete cascade,
  assigned_agent_id uuid not null references public.agents (id) on delete restrict,
  assigned_at       timestamptz not null default now(),
  assignment_source public.assignment_source not null default 'initial_registration',
  status            public.assignment_status not null default 'active',
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.customer_assignments is
  '顧客の担当代理店。agents.invited_by (登録経路) とは完全に独立。片方が他方を自動変更してはならない。';

-- 1顧客につき有効な担当は常に1件
create unique index customer_assignments_one_active
  on public.customer_assignments (customer_id)
  where status = 'active';
create index customer_assignments_agent_idx
  on public.customer_assignments (assigned_agent_id) where status = 'active';

create trigger customer_assignments_touch_updated_at
  before update on public.customer_assignments
  for each row execute function app.touch_updated_at();

-- ============================================================================
-- 7. customer_assignment_history (担当変更履歴 / 追記専用)
-- ============================================================================

create table public.customer_assignment_history (
  id                uuid primary key default gen_random_uuid(),
  customer_id       uuid not null references public.customers (id) on delete cascade,
  previous_agent_id uuid references public.agents (id) on delete set null,
  new_agent_id      uuid not null references public.agents (id) on delete restrict,
  reason            text not null check (btrim(reason) <> ''),
  changed_by        uuid references auth.users (id) on delete set null,
  changed_by_role   text not null default 'system'
                      check (changed_by_role in ('admin', 'agent', 'self_registration', 'system')),
  -- clock_timestamp(): now() はトランザクション開始時刻で固定されるため、
  -- 1トランザクション内に複数の履歴が入ると順序が付かなくなる。
  changed_at        timestamptz not null default clock_timestamp()
);

create index customer_assignment_history_customer_idx
  on public.customer_assignment_history (customer_id, changed_at desc);

-- ============================================================================
-- 8. purchases (購入)
-- ============================================================================

create table public.purchases (
  id               uuid primary key default gen_random_uuid(),
  customer_id      uuid not null references public.customers (id) on delete cascade,
  agent_id         uuid references public.agents (id) on delete set null,
  product_category public.product_category not null default 'other',
  product_name     text not null check (btrim(product_name) <> ''),
  product_sku      text,
  quantity         integer not null default 1 check (quantity > 0),
  unit_price       numeric(12, 2) not null default 0 check (unit_price >= 0),
  amount           numeric(12, 2) not null default 0 check (amount >= 0),
  currency         text not null default 'JPY',
  status           public.purchase_status not null default 'completed',
  purchased_at     timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

comment on column public.purchases.agent_id is
  '購入時点の担当代理店スナップショット。担当変更で遡及的に書き換えない。';

create index purchases_customer_idx on public.purchases (customer_id, purchased_at desc);
create index purchases_agent_idx on public.purchases (agent_id);
create index purchases_category_idx on public.purchases (product_category);

create trigger purchases_touch_updated_at
  before update on public.purchases
  for each row execute function app.touch_updated_at();

-- ============================================================================
-- 9. benefits / bank_accounts / notifications
-- ============================================================================

create table public.benefits (
  id           uuid primary key default gen_random_uuid(),
  agent_id     uuid not null references public.agents (id) on delete cascade,
  purchase_id  uuid references public.purchases (id) on delete set null,
  benefit_type public.benefit_type not null default 'sales_commission',
  amount       numeric(12, 2) not null default 0,
  currency     text not null default 'JPY',
  period_month date,
  status       public.benefit_status not null default 'pending',
  paid_at      timestamptz,
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index benefits_agent_idx on public.benefits (agent_id, period_month desc);

create trigger benefits_touch_updated_at
  before update on public.benefits
  for each row execute function app.touch_updated_at();

create table public.bank_accounts (
  id                  uuid primary key default gen_random_uuid(),
  agent_id            uuid not null unique references public.agents (id) on delete cascade,
  bank_name           text not null,
  bank_code           text,
  branch_name         text not null,
  branch_code         text,
  account_type        public.bank_account_type not null default 'ordinary',
  account_number      text not null,
  account_holder_kana text not null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create trigger bank_accounts_touch_updated_at
  before update on public.bank_accounts
  for each row execute function app.touch_updated_at();

create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  agent_id   uuid references public.agents (id) on delete cascade,
  for_admin  boolean not null default false,
  category   public.notification_category not null default 'system',
  title      text not null,
  body       text,
  link_url   text,
  read_at    timestamptz,
  created_at timestamptz not null default now(),
  constraint notifications_has_recipient check (for_admin or agent_id is not null)
);

create index notifications_agent_idx on public.notifications (agent_id, created_at desc);

-- ============================================================================
-- 10. admin_roles / admin_audit_logs
-- ============================================================================

create table public.admin_roles (
  id           uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users (id) on delete cascade,
  role         public.admin_role_name not null default 'admin',
  granted_by   uuid references auth.users (id) on delete set null,
  granted_at   timestamptz not null default now(),
  revoked_at   timestamptz
);

create index admin_roles_active_idx on public.admin_roles (auth_user_id) where revoked_at is null;

create table public.admin_audit_logs (
  id            uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users (id) on delete set null,
  actor_role    text not null default 'admin',
  action        text not null,
  target_table  text not null,
  target_id     uuid,
  before_state  jsonb,
  after_state   jsonb,
  reason        text,
  ip_address    text,
  user_agent    text,
  -- 監査ログも同一トランザクション内で順序が付くよう clock_timestamp() を使う
  created_at    timestamptz not null default clock_timestamp()
);

create index admin_audit_logs_target_idx
  on public.admin_audit_logs (target_table, target_id, created_at desc);
create index admin_audit_logs_created_idx on public.admin_audit_logs (created_at desc);

commit;
