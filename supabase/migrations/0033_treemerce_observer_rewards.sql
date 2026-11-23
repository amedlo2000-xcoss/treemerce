-- ============================================================================
-- TREEMERCE : 0033_treemerce_observer_rewards.sql
-- オブザーバーの報酬 (手数料): ランク / ランク別の割合 / 報酬明細 / 確定・取り消し / 閲覧
-- ----------------------------------------------------------------------------
-- 分け方 (注文ごと・出店者ごとに計算する)
--   基準     = 出店者の商品の「商品価格 (税込) × 数量」の合計 (order_items.amount。送料は含めない)
--   出店者   = 基準 × 70% (固定)。1 TWA 未満は切り捨て
--   紹介者   = 基準 × 紹介者のランクの割合 (agent_rank_reward_rates)。1 TWA 未満は切り捨て
--              紹介者 = 出店者の invited_by (1 段階だけ。その上には払わない)
--              紹介者がいない / 稼働中 (active) でない場合は紹介者の明細を作らない
--   運営     = 基準 − 出店者 − 紹介者 (30% から紹介者分を引いた残り + 切り捨ての端数)
--   出店者   = 商品の持込み元 (product_sources.sourced_by_agent_id)。
--              持込み元のない商品 (運営が登録した商品) は明細を作らない (生産者への支払いは扱わない)
--   お客様の担当オブザーバー (orders.agent_id / customer_assignments) への報酬はない
--
-- 確定
--   注文が「入金確認済み (paid_at あり)」かつ「全生産者の発送記録が発送済み」になった時点で
--   報酬明細 (出店者・紹介者・運営) を作る。発送記録のない旧注文は「発送済み」になった時点。
--   orders / order_shipments のステータス変更のトリガから app.settle_order_rewards() を呼ぶため、
--   経路 (自動の発送済み・手動変更・DB管理者の直接操作) を問わず確定する。
--   その時点のランク・割合を明細に複写し、あとでランク・割合を変えても過去の明細は変わらない。
--   同じ注文の明細は 1 度しか作らない (関数での確認 + 一意索引)。
--
-- 取り消し
--   明細は書き換え・削除できない (postgres の直接操作でも不可)。
--   確定後にキャンセルされた注文は、トリガで各明細の取り消し (マイナス) を自動で作る。
--   キャンセル以外の返品などは super_admin が treemerce_admin_reverse_order_rewards() で取り消す。
--   取り消しは元の明細 1 件につき 1 回だけ (一意索引)。確定前にキャンセルされた注文は明細を作らない。
--
-- ランク
--   agent_ranks (オブザーバー 1 人 1 行。行がなければ「一般」)。変更は super_admin の RPC のみで、
--   変更前後と理由が監査ログに残る (経路を問わずトリガで記録)。
--   ランク別の割合は agent_rank_reward_rates に持ち、変更は super_admin の RPC のみ (監査ログに記録)。
--
-- 見える範囲 (絶対原則5)
--   オブザーバー : treemerce_my_reward_entries() で自分が受取人の明細だけ。
--                 紹介者の明細は「商品名・金額・日付」(と区分) だけで、注文番号・購入者・
--                 担当オブザーバー・数量は返さない。出店者は加えて基準額と割合を見られる。
--                 テーブルは直接読めない。
--   運営        : treemerce_admin_list_reward_entries() で全件 (super_admin)。
--   明細は customers を参照せず、購入者の氏名・連絡先を持たない。
--
-- 絶対原則との対応
--   原則1・5 : 明細・ランクは customers を参照しない。
--   原則3・4 : 招待経路 (invited_by)・顧客の担当・売上の帰属 (orders.agent_id) を参照するだけで変更しない。
--   派生     : 閲覧の RPC は STABLE。
-- ============================================================================

begin;

-- ============================================================================
-- 1. 列挙型
-- ============================================================================

create type public.agent_rank as enum ('general', 'level3', 'level4', 'level5');

comment on type public.agent_rank is
  'オブザーバーのランク。general=一般 / level3=レベル3 / level4=レベル4 / level5=レベル5';

create type public.reward_entry_kind as enum ('accrual', 'reversal');

comment on type public.reward_entry_kind is 'accrual=確定 / reversal=取り消し (マイナス)';

create type public.reward_recipient_role as enum ('seller', 'referrer', 'operator');

comment on type public.reward_recipient_role is 'seller=出店者 / referrer=紹介者 / operator=運営';

create or replace function app.agent_rank_label(p_rank public.agent_rank)
returns text
language sql
immutable
as $fn$
  select case p_rank
           when 'general' then '一般'
           when 'level3'  then 'レベル3'
           when 'level4'  then 'レベル4'
           when 'level5'  then 'レベル5'
         end;
$fn$;

-- 出店者の割合 (固定) と、出店者以外で分ける割合
create or replace function app.reward_seller_rate()
returns numeric
language sql
immutable
as $fn$ select 0.70::numeric $fn$;

create or replace function app.reward_pool_rate()
returns numeric
language sql
immutable
as $fn$ select 0.30::numeric $fn$;

-- ============================================================================
-- 2. agent_ranks (オブザーバーのランク。行がなければ「一般」)
-- ============================================================================

create table public.agent_ranks (
  agent_id   uuid primary key references public.agents (id) on delete restrict,
  rank       public.agent_rank not null default 'general',
  updated_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now()
);

comment on table public.agent_ranks is
  'オブザーバーのランク。行がないオブザーバーは「一般」。変更は super_admin の RPC のみ (監査ログに記録)。削除不可。';

create or replace function app.agent_rank_of(p_agent_id uuid)
returns public.agent_rank
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select coalesce((select r.rank from public.agent_ranks r where r.agent_id = p_agent_id),
                  'general'::public.agent_rank);
$fn$;

create or replace function app.guard_agent_ranks_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.reward_ctx', true), '');
begin
  if tg_op = 'DELETE' then
    raise exception 'TREEMERCE_AGENT_RANK_DELETE_DENIED: ランクは削除できません (一般に変更してください)'
      using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.agent_id is distinct from old.agent_id then
    raise exception 'TREEMERCE_AGENT_RANK_IMMUTABLE: ランクのオブザーバーは付け替えられません'
      using errcode = '42501';
  end if;

  if v_ctx = 'agent_rank' then
    return new;
  end if;
  -- DB管理者の直接操作 (障害復旧)。監査ログは 5. のトリガで必ず残る。
  if session_user = 'postgres' and v_ctx = '' then
    return new;
  end if;

  raise exception
    'TREEMERCE_AGENT_RANK_WRITE_DENIED: ランクは運営 (super_admin) の変更処理でのみ変更できます'
    using errcode = '42501';
end;
$fn$;

create trigger agent_ranks_guard
  before insert or update or delete on public.agent_ranks
  for each row execute function app.guard_agent_ranks_write();

create trigger agent_ranks_touch_updated_at
  before update on public.agent_ranks
  for each row execute function app.touch_updated_at();

-- ============================================================================
-- 3. agent_rank_reward_rates (ランク別の紹介者の割合)
-- ============================================================================

create table public.agent_rank_reward_rates (
  rank          public.agent_rank primary key,
  referrer_rate numeric(5, 4) not null,
  updated_by    uuid references auth.users (id) on delete set null,
  updated_at    timestamptz not null default now(),

  -- 紹介者の割合は出店者以外の 30% を超えられない (運営の取り分がマイナスにならない)
  constraint agent_rank_reward_rates_range check (referrer_rate >= 0 and referrer_rate <= 0.30)
);

comment on table public.agent_rank_reward_rates is
  'ランク別の紹介者の割合 (基準額に対する比率。0.20 = 20%)。運営の割合は 30% − この値。'
  '変更は super_admin の RPC のみ (監査ログに記録)。削除不可。過去の明細には確定時点の値が複写済み。';

insert into public.agent_rank_reward_rates (rank, referrer_rate) values
  ('level5',  0.20),
  ('level4',  0.15),
  ('level3',  0.10),
  ('general', 0.05);

create trigger agent_rank_reward_rates_touch_updated_at
  before update on public.agent_rank_reward_rates
  for each row execute function app.touch_updated_at();

create or replace function app.guard_rank_rates_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.reward_ctx', true), '');
begin
  if tg_op = 'DELETE' then
    raise exception 'TREEMERCE_REWARD_RATE_DELETE_DENIED: ランク別の割合は削除できません'
      using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.rank is distinct from old.rank then
    raise exception 'TREEMERCE_REWARD_RATE_IMMUTABLE: 割合のランクは変更できません'
      using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' and v_ctx = 'reward_rate' then
    return new;
  end if;
  -- DB管理者の直接操作 (初期登録・障害復旧)。監査ログは 5. のトリガで必ず残る。
  if session_user = 'postgres' and v_ctx = '' then
    return new;
  end if;

  raise exception
    'TREEMERCE_REWARD_RATE_WRITE_DENIED: ランク別の割合は運営 (super_admin) の変更処理でのみ変更できます'
    using errcode = '42501';
end;
$fn$;

create trigger agent_rank_reward_rates_guard
  before insert or update or delete on public.agent_rank_reward_rates
  for each row execute function app.guard_rank_rates_write();

-- ============================================================================
-- 4. agent_reward_entries (報酬明細。追記専用)
-- ============================================================================

create table public.agent_reward_entries (
  id                 uuid primary key default gen_random_uuid(),
  order_id           uuid not null references public.orders (id) on delete restrict,
  entry_kind         public.reward_entry_kind not null,
  recipient_role     public.reward_recipient_role not null,
  -- 受取人のオブザーバー (運営の明細は NULL)
  recipient_agent_id uuid references public.agents (id) on delete restrict,

  -- 計算の単位 (注文 × 出店者) と、確定時点のスナップショット
  seller_agent_id    uuid not null references public.agents (id) on delete restrict,
  referrer_agent_id  uuid references public.agents (id) on delete restrict,
  referrer_rank      public.agent_rank,
  referrer_rate      numeric(5, 4),
  base_amount        numeric(12, 2) not null,
  rate               numeric(5, 4) not null check (rate >= 0 and rate <= 1),
  amount             numeric(12, 2) not null,
  -- 対象の商品 (注文時点の商品名・数量・金額)。購入者の情報は持たない
  product_lines      jsonb not null check (jsonb_typeof(product_lines) = 'array'),

  -- 取り消し
  reverses_entry_id  uuid unique references public.agent_reward_entries (id) on delete restrict,
  reason             text,

  settled_on         date not null default ((now() at time zone 'Asia/Tokyo')::date),
  created_by         uuid references auth.users (id) on delete set null,
  created_at         timestamptz not null default clock_timestamp(),

  constraint agent_reward_entries_recipient check (
       (recipient_role = 'seller'   and recipient_agent_id = seller_agent_id)
    or (recipient_role = 'referrer' and referrer_agent_id is not null
                                    and recipient_agent_id = referrer_agent_id)
    or (recipient_role = 'operator' and recipient_agent_id is null)
  ),
  constraint agent_reward_entries_referrer_snapshot check (
    (referrer_agent_id is null) = (referrer_rank is null)
    and (referrer_agent_id is null) = (referrer_rate is null)
    and (referrer_agent_id is null or referrer_agent_id <> seller_agent_id)
  ),
  constraint agent_reward_entries_kind check (
       (entry_kind = 'accrual'  and reverses_entry_id is null
                                and base_amount >= 0 and amount >= 0)
    or (entry_kind = 'reversal' and reverses_entry_id is not null
                                and base_amount <= 0 and amount <= 0
                                and nullif(btrim(coalesce(reason, '')), '') is not null)
  )
);

comment on table public.agent_reward_entries is
  '報酬明細 (注文 × 出店者 × 受取人)。確定時点のランク・割合を複写し、書き換え・削除できない。'
  '取り消しはマイナスの明細 (reversal) で表す。購入者の情報は持たない。';

-- 二重作成の防止: 同じ注文・出店者・受取人の確定は 1 件だけ
create unique index agent_reward_entries_accrual_once
  on public.agent_reward_entries (order_id, seller_agent_id, recipient_role)
  where entry_kind = 'accrual';

create index agent_reward_entries_recipient_idx
  on public.agent_reward_entries (recipient_agent_id, created_at desc);
create index agent_reward_entries_order_idx
  on public.agent_reward_entries (order_id);

create or replace function app.guard_reward_entries_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx  text := coalesce(current_setting('app.reward_ctx', true), '');
  v_orig public.agent_reward_entries%rowtype;
begin
  -- 書き換え・削除は誰にもさせない (postgres の直接操作も含む)
  if tg_op <> 'INSERT' then
    raise exception 'TREEMERCE_REWARD_ENTRY_IMMUTABLE: 報酬明細は書き換え・削除できません (取り消しの明細で扱う)'
      using errcode = '42501';
  end if;

  if new.entry_kind = 'accrual' and v_ctx = 'reward_settle' then
    return new;
  end if;

  if new.entry_kind = 'reversal' and v_ctx = 'reward_reverse' then
    -- 取り消しは元の確定明細をちょうど打ち消すものに限る
    select * into v_orig from public.agent_reward_entries where id = new.reverses_entry_id;
    if not found or v_orig.entry_kind <> 'accrual'
       or v_orig.order_id           is distinct from new.order_id
       or v_orig.recipient_role     is distinct from new.recipient_role
       or v_orig.recipient_agent_id is distinct from new.recipient_agent_id
       or v_orig.seller_agent_id    is distinct from new.seller_agent_id
       or new.amount      <> -v_orig.amount
       or new.base_amount <> -v_orig.base_amount then
      raise exception 'TREEMERCE_REWARD_REVERSAL_MISMATCH: 取り消しの明細が元の明細と一致しません'
        using errcode = '42501';
    end if;
    return new;
  end if;

  raise exception
    'TREEMERCE_REWARD_ENTRY_WRITE_DENIED: 報酬明細は確定・取り消しの処理でのみ作成できます'
    using errcode = '42501';
end;
$fn$;

create trigger agent_reward_entries_guard
  before insert or update or delete on public.agent_reward_entries
  for each row execute function app.guard_reward_entries_write();

create or replace function app.guard_reward_entries_truncate()
returns trigger
language plpgsql
as $fn$
begin
  raise exception 'TREEMERCE_REWARD_ENTRY_IMMUTABLE: 報酬明細は削除できません'
    using errcode = '42501';
end;
$fn$;

create trigger agent_reward_entries_no_truncate
  before truncate on public.agent_reward_entries
  for each statement execute function app.guard_reward_entries_truncate();

-- ============================================================================
-- 5. ランク・割合の変更の監査 (経路を問わず記録する)
-- ----------------------------------------------------------------------------
-- 理由は GUC app.audit_reason (RPC が設定する)。
-- ============================================================================

create or replace function app.audit_agent_rank_change()
returns trigger
language plpgsql
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_before public.agent_rank := case when tg_op = 'UPDATE' then old.rank else 'general' end;
begin
  if new.rank is not distinct from v_before then
    return new;
  end if;

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (
    auth.uid(),
    coalesce(app.admin_role(), case when session_user = 'postgres' and auth.uid() is null
                                    then 'db_admin' else 'unknown' end),
    'agent.rank_change', 'agents', new.agent_id,
    jsonb_build_object('rank', v_before, 'rank_label', app.agent_rank_label(v_before)),
    jsonb_build_object('rank', new.rank, 'rank_label', app.agent_rank_label(new.rank)),
    nullif(btrim(coalesce(current_setting('app.audit_reason', true), '')), ''));
  return new;
end;
$fn$;

create trigger agent_ranks_audit
  after insert or update of rank on public.agent_ranks
  for each row execute function app.audit_agent_rank_change();

create or replace function app.audit_rank_rate_change()
returns trigger
language plpgsql
security definer
set search_path = public, app, pg_temp
as $fn$
begin
  if new.referrer_rate is not distinct from old.referrer_rate then
    return new;
  end if;

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (
    auth.uid(),
    coalesce(app.admin_role(), case when session_user = 'postgres' and auth.uid() is null
                                    then 'db_admin' else 'unknown' end),
    'reward_rate.change', 'agent_rank_reward_rates', null,
    jsonb_build_object('rank', old.rank, 'rank_label', app.agent_rank_label(old.rank),
                       'referrer_rate', old.referrer_rate),
    jsonb_build_object('rank', new.rank, 'rank_label', app.agent_rank_label(new.rank),
                       'referrer_rate', new.referrer_rate),
    nullif(btrim(coalesce(current_setting('app.audit_reason', true), '')), ''));
  return new;
end;
$fn$;

create trigger agent_rank_reward_rates_audit
  after update of referrer_rate on public.agent_rank_reward_rates
  for each row execute function app.audit_rank_rate_change();

-- ============================================================================
-- 6. 報酬の確定 (app.settle_order_rewards)
-- ----------------------------------------------------------------------------
-- 条件を満たさない・既に明細がある注文では何もしない (何度呼んでも同じ結果)。
-- 戻り値は作成した明細の件数。
-- ============================================================================

create or replace function app.settle_order_rewards(p_order_id uuid)
returns integer
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_order    public.orders%rowtype;
  v_group    record;
  v_inviter  public.agents%rowtype;
  v_ref_id   uuid;
  v_ref_rank public.agent_rank;
  v_ref_rate numeric(5, 4);
  v_seller   numeric(12, 2);
  v_referrer numeric(12, 2);
  v_operator numeric(12, 2);
  v_count    integer := 0;
  v_uid      uuid := auth.uid();
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    return 0;
  end if;

  -- 入金確認済み以降 (キャンセルは対象外)
  if v_order.status not in ('payment_confirmed', 'shipped', 'completed') or v_order.paid_at is null then
    return 0;
  end if;
  -- 全生産者が発送済み (キャンセルの発送記録は除く)
  if exists (select 1 from public.order_shipments s
             where s.order_id = p_order_id and s.status not in ('shipped', 'cancelled')) then
    return 0;
  end if;
  -- 入金確認済みのままなら、少なくとも 1 件が発送済みであること (発送記録のない旧注文は「発送済み」で確定)
  if v_order.status = 'payment_confirmed'
     and not exists (select 1 from public.order_shipments s
                     where s.order_id = p_order_id and s.status = 'shipped') then
    return 0;
  end if;
  -- 二重作成の防止 (取り消し済みの注文も再確定しない)
  if exists (select 1 from public.agent_reward_entries e where e.order_id = p_order_id) then
    return 0;
  end if;

  perform set_config('app.reward_ctx', 'reward_settle', true);

  for v_group in
    select ps.sourced_by_agent_id as seller_agent_id,
           sum(oi.amount)         as base_amount,
           jsonb_agg(jsonb_build_object(
             'product_id',   oi.product_id,
             'product_name', oi.product_name,
             'quantity',     oi.quantity,
             'amount',       oi.amount)
             order by oi.product_name, oi.id) as product_lines
    from public.order_items oi
    join public.product_sources ps on ps.product_id = oi.product_id
    where oi.order_id = p_order_id
      and not exists (select 1 from public.order_shipments s
                      where s.order_id = oi.order_id and s.producer_id = oi.producer_id
                        and s.status = 'cancelled')
    group by ps.sourced_by_agent_id
    order by ps.sourced_by_agent_id
  loop
    if v_group.base_amount <= 0 then
      continue;
    end if;

    -- 紹介者 = 出店者の invited_by (1 段階だけ)。稼働中でなければ紹介者なし
    v_ref_id := null; v_ref_rank := null; v_ref_rate := null; v_referrer := 0;

    select i.* into v_inviter
    from public.agents a
    join public.agents i on i.id = a.invited_by
    where a.id = v_group.seller_agent_id;

    if found and v_inviter.status = 'active' then
      v_ref_id   := v_inviter.id;
      v_ref_rank := app.agent_rank_of(v_inviter.id);
      select r.referrer_rate into v_ref_rate
      from public.agent_rank_reward_rates r where r.rank = v_ref_rank;
      if v_ref_rate is null then
        raise exception 'TREEMERCE_REWARD_RATE_MISSING: ランク % の割合が設定されていません', v_ref_rank
          using errcode = '22023';
      end if;
      v_referrer := floor(v_group.base_amount * v_ref_rate);
    end if;

    v_seller   := floor(v_group.base_amount * app.reward_seller_rate());
    v_operator := v_group.base_amount - v_seller - v_referrer;   -- 切り捨ての端数は運営

    insert into public.agent_reward_entries
      (order_id, entry_kind, recipient_role, recipient_agent_id, seller_agent_id,
       referrer_agent_id, referrer_rank, referrer_rate, base_amount, rate, amount,
       product_lines, created_by)
    values
      (p_order_id, 'accrual', 'seller', v_group.seller_agent_id, v_group.seller_agent_id,
       v_ref_id, v_ref_rank, v_ref_rate, v_group.base_amount, app.reward_seller_rate(), v_seller,
       v_group.product_lines, v_uid);
    v_count := v_count + 1;

    if v_ref_id is not null then
      insert into public.agent_reward_entries
        (order_id, entry_kind, recipient_role, recipient_agent_id, seller_agent_id,
         referrer_agent_id, referrer_rank, referrer_rate, base_amount, rate, amount,
         product_lines, created_by)
      values
        (p_order_id, 'accrual', 'referrer', v_ref_id, v_group.seller_agent_id,
         v_ref_id, v_ref_rank, v_ref_rate, v_group.base_amount, v_ref_rate, v_referrer,
         v_group.product_lines, v_uid);
      v_count := v_count + 1;
    end if;

    insert into public.agent_reward_entries
      (order_id, entry_kind, recipient_role, recipient_agent_id, seller_agent_id,
       referrer_agent_id, referrer_rank, referrer_rate, base_amount, rate, amount,
       product_lines, created_by)
    values
      (p_order_id, 'accrual', 'operator', null, v_group.seller_agent_id,
       v_ref_id, v_ref_rank, v_ref_rate, v_group.base_amount,
       app.reward_pool_rate() - coalesce(v_ref_rate, 0), v_operator,
       v_group.product_lines, v_uid);
    v_count := v_count + 1;
  end loop;

  perform set_config('app.reward_ctx', '', true);
  return v_count;
end;
$fn$;

-- ============================================================================
-- 7. 報酬の取り消し (app.reverse_order_rewards)
-- ----------------------------------------------------------------------------
-- 取り消されていない確定明細それぞれに、マイナスの明細を作る。監査ログに 1 件残す。
-- 戻り値は作成した取り消し明細の件数 (取り消す明細がなければ 0)。
-- ============================================================================

create or replace function app.reverse_order_rewards(p_order_id uuid, p_reason text, p_action text)
returns integer
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid   uuid := auth.uid();
  v_count integer;
  v_total numeric(12, 2);
begin
  perform 1 from public.orders where id = p_order_id for update;

  perform set_config('app.reward_ctx', 'reward_reverse', true);

  with targets as (
    select e.*
    from public.agent_reward_entries e
    where e.order_id = p_order_id
      and e.entry_kind = 'accrual'
      and not exists (select 1 from public.agent_reward_entries r where r.reverses_entry_id = e.id)
    order by e.seller_agent_id, e.recipient_role
  ),
  inserted as (
    insert into public.agent_reward_entries
      (order_id, entry_kind, recipient_role, recipient_agent_id, seller_agent_id,
       referrer_agent_id, referrer_rank, referrer_rate, base_amount, rate, amount,
       product_lines, reverses_entry_id, reason, created_by)
    select t.order_id, 'reversal', t.recipient_role, t.recipient_agent_id, t.seller_agent_id,
           t.referrer_agent_id, t.referrer_rank, t.referrer_rate, -t.base_amount, t.rate, -t.amount,
           t.product_lines, t.id, p_reason, v_uid
    from targets t
    returning amount
  )
  select count(*), coalesce(sum(amount), 0) into v_count, v_total from inserted;

  perform set_config('app.reward_ctx', '', true);

  if v_count > 0 then
    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (
      v_uid,
      coalesce(app.admin_role(), case when session_user = 'postgres' and v_uid is null
                                      then 'db_admin' else 'unknown' end),
      p_action, 'orders', p_order_id, null,
      jsonb_build_object('reversed_entries', v_count, 'reversed_total', v_total),
      p_reason);
  end if;

  return v_count;
end;
$fn$;

-- ============================================================================
-- 8. 確定・取り消しのトリガ (orders / order_shipments のステータス変更)
-- ============================================================================

create or replace function app.on_order_status_rewards()
returns trigger
language plpgsql
security definer
set search_path = public, app, pg_temp
as $fn$
begin
  if new.status is not distinct from old.status then
    return null;
  end if;

  if new.status = 'cancelled' then
    perform app.reverse_order_rewards(new.id, '注文のキャンセル', 'reward.reverse_on_cancel');
  else
    perform app.settle_order_rewards(new.id);
  end if;
  return null;
end;
$fn$;

create trigger orders_rewards
  after update of status on public.orders
  for each row execute function app.on_order_status_rewards();

create or replace function app.on_shipment_status_rewards()
returns trigger
language plpgsql
security definer
set search_path = public, app, pg_temp
as $fn$
begin
  if new.status = 'shipped' and old.status is distinct from 'shipped' then
    perform app.settle_order_rewards(new.order_id);
  end if;
  return null;
end;
$fn$;

create trigger order_shipments_rewards
  after update of status on public.order_shipments
  for each row execute function app.on_shipment_status_rewards();

-- ============================================================================
-- 9. RPC: ランク (super_admin)
-- ============================================================================

create or replace function public.treemerce_admin_set_agent_rank(
  p_agent_id uuid,
  p_rank     public.agent_rank,
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
  v_before public.agent_rank;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: ランクの変更は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  if v_reason is null then
    raise exception 'TREEMERCE_REASON_REQUIRED: 変更理由は必須です' using errcode = '22023';
  end if;
  if p_rank is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 変更後のランクを指定してください' using errcode = '22023';
  end if;
  if not exists (select 1 from public.agents a where a.id = p_agent_id) then
    raise exception 'TREEMERCE_AGENT_NOT_FOUND: オブザーバーが見つかりません' using errcode = '22023';
  end if;

  perform 1 from public.agents a where a.id = p_agent_id for update;
  v_before := app.agent_rank_of(p_agent_id);
  if v_before = p_rank then
    raise exception 'TREEMERCE_NO_CHANGE: 既に同じランクです' using errcode = '22023';
  end if;

  perform set_config('app.reward_ctx', 'agent_rank', true);
  perform set_config('app.audit_reason', v_reason, true);

  insert into public.agent_ranks (agent_id, rank, updated_by)
  values (p_agent_id, p_rank, v_uid)
  on conflict (agent_id) do update
    set rank = excluded.rank, updated_by = excluded.updated_by;

  perform set_config('app.audit_reason', '', true);
  perform set_config('app.reward_ctx', '', true);

  return jsonb_build_object(
    'agent_id',    p_agent_id,
    'from_rank',   v_before,
    'rank',        p_rank,
    'rank_label',  app.agent_rank_label(p_rank));
end;
$fn$;

-- ============================================================================
-- 10. RPC: ランク別の割合 (super_admin)
-- ============================================================================

create or replace function public.treemerce_admin_list_reward_rates()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 報酬の割合は super_admin のみ参照できます'
      using errcode = '42501';
  end if;

  return jsonb_build_object(
    'seller_rate', app.reward_seller_rate(),
    'pool_rate',   app.reward_pool_rate(),
    'ranks', coalesce((
      select jsonb_agg(jsonb_build_object(
               'rank',          r.rank,
               'rank_label',    app.agent_rank_label(r.rank),
               'referrer_rate', r.referrer_rate,
               'operator_rate', app.reward_pool_rate() - r.referrer_rate,
               'updated_at',    r.updated_at)
             order by r.rank desc)
      from public.agent_rank_reward_rates r), '[]'::jsonb),
    'no_referrer_operator_rate', app.reward_pool_rate());
end;
$fn$;

create or replace function public.treemerce_admin_set_reward_rate(
  p_rank   public.agent_rank,
  p_rate   numeric,
  p_reason text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_before numeric(5, 4);
  v_after  public.agent_rank_reward_rates%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 報酬の割合の変更は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  if v_reason is null then
    raise exception 'TREEMERCE_REASON_REQUIRED: 変更理由は必須です' using errcode = '22023';
  end if;
  if p_rank is null or p_rate is null then
    raise exception 'TREEMERCE_INVALID_INPUT: ランクと割合を指定してください' using errcode = '22023';
  end if;
  if p_rate < 0 or p_rate > app.reward_pool_rate() or p_rate <> round(p_rate, 4) then
    raise exception 'TREEMERCE_INVALID_INPUT: 紹介者の割合は 0〜0.30 (0%%〜30%%) の範囲で、小数第4位までで指定してください'
      using errcode = '22023';
  end if;

  select r.referrer_rate into v_before
  from public.agent_rank_reward_rates r where r.rank = p_rank for update;
  if not found then
    raise exception 'TREEMERCE_REWARD_RATE_MISSING: ランク % の割合がありません', p_rank using errcode = '22023';
  end if;
  if v_before = p_rate then
    raise exception 'TREEMERCE_NO_CHANGE: 既に同じ割合です' using errcode = '22023';
  end if;

  perform set_config('app.reward_ctx', 'reward_rate', true);
  perform set_config('app.audit_reason', v_reason, true);

  update public.agent_rank_reward_rates
  set referrer_rate = p_rate, updated_by = auth.uid()
  where rank = p_rank
  returning * into v_after;

  perform set_config('app.audit_reason', '', true);
  perform set_config('app.reward_ctx', '', true);

  return jsonb_build_object(
    'rank',          v_after.rank,
    'rank_label',    app.agent_rank_label(v_after.rank),
    'from_rate',     v_before,
    'referrer_rate', v_after.referrer_rate,
    'operator_rate', app.reward_pool_rate() - v_after.referrer_rate);
end;
$fn$;

-- ============================================================================
-- 11. RPC: 取り消し (super_admin。キャンセル以外の返品など)
-- ============================================================================

create or replace function public.treemerce_admin_reverse_order_rewards(
  p_order_id uuid,
  p_reason   text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_count  integer;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 報酬の取り消しは super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  if v_reason is null then
    raise exception 'TREEMERCE_REASON_REQUIRED: 取り消しの理由は必須です' using errcode = '22023';
  end if;
  if not exists (select 1 from public.orders o where o.id = p_order_id) then
    raise exception 'TREEMERCE_ORDER_NOT_FOUND: 注文が見つかりません' using errcode = '22023';
  end if;

  v_count := app.reverse_order_rewards(p_order_id, v_reason, 'reward.reverse');
  if v_count = 0 then
    raise exception 'TREEMERCE_REWARD_NOTHING_TO_REVERSE: 取り消せる報酬明細がありません (未確定または取り消し済み)'
      using errcode = '22023';
  end if;

  return jsonb_build_object('order_id', p_order_id, 'reversed_entries', v_count);
end;
$fn$;

-- ============================================================================
-- 12. RPC: 閲覧
-- ----------------------------------------------------------------------------
-- オブザーバー本人 : 自分が受取人の明細だけ。注文番号・購入者・担当・数量は返さない。
--   紹介者の明細  : 商品名・金額・日付 (と区分)
--   出店者の明細  : 上記 + 基準額・割合
-- 運営 (super_admin): 全件。購入者の氏名・連絡先は明細に含まれない (注文詳細の RPC で別途参照)。
-- ============================================================================

create or replace function public.treemerce_my_reward_entries(p_limit integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_self  uuid := app.current_agent_id();
  v_rank  public.agent_rank;
  v_limit integer := least(greatest(coalesce(p_limit, 200), 1), 1000);
begin
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中のオブザーバーアカウントが必要です' using errcode = '42501';
  end if;
  v_rank := app.agent_rank_of(v_self);

  return jsonb_build_object(
    'rank',       v_rank,
    'rank_label', app.agent_rank_label(v_rank),
    'total_amount', coalesce((
      select sum(e.amount) from public.agent_reward_entries e
      where e.recipient_agent_id = v_self), 0),
    'entries', coalesce((
      select jsonb_agg(x.j order by x.created_at desc, x.id)
      from (
        select e.id, e.created_at,
               jsonb_build_object(
                 'id',            e.id,
                 'role',          e.recipient_role,
                 'kind',          e.entry_kind,
                 'product_names', (select coalesce(jsonb_agg(distinct l ->> 'product_name'), '[]'::jsonb)
                                   from jsonb_array_elements(e.product_lines) l),
                 'amount',        e.amount,
                 'date',          e.settled_on)
               || case when e.recipient_role = 'seller'
                       then jsonb_build_object('base_amount', e.base_amount, 'rate', e.rate)
                       else '{}'::jsonb end as j
        from public.agent_reward_entries e
        where e.recipient_agent_id = v_self
        order by e.created_at desc, e.id
        limit v_limit
      ) x), '[]'::jsonb));
end;
$fn$;

create or replace function public.treemerce_admin_list_reward_entries(
  p_order_id uuid    default null,
  p_agent_id uuid    default null,
  p_limit    integer default 500
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 500), 1), 5000);
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 報酬明細の一覧は super_admin のみ参照できます'
      using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(x.j order by x.created_at desc, x.id)
    from (
      select e.id, e.created_at,
             to_jsonb(e) || jsonb_build_object(
               'order_no',             o.order_no,
               'recipient_name',       ra.display_name,
               'recipient_public_id',  ra.public_id,
               'seller_name',          sa.display_name,
               'seller_public_id',     sa.public_id,
               'referrer_name',        fa.display_name,
               'referrer_public_id',   fa.public_id,
               'referrer_rank_label',  app.agent_rank_label(e.referrer_rank)) as j
      from public.agent_reward_entries e
      join public.orders o      on o.id  = e.order_id
      join public.agents sa     on sa.id = e.seller_agent_id
      left join public.agents ra on ra.id = e.recipient_agent_id
      left join public.agents fa on fa.id = e.referrer_agent_id
      where (p_order_id is null or e.order_id = p_order_id)
        and (p_agent_id is null or e.recipient_agent_id = p_agent_id
                                or e.seller_agent_id = p_agent_id)
      order by e.created_at desc, e.id
      limit v_limit
    ) x), '[]'::jsonb);
end;
$fn$;

comment on function public.treemerce_my_reward_entries(integer) is
  'オブザーバー本人の報酬明細 (自分が受取人のものだけ)。紹介者は商品名・金額・日付のみ。購入者・注文番号は返さない。STABLE。';
comment on function public.treemerce_admin_list_reward_entries(uuid, uuid, integer) is
  '報酬明細の全件 (super_admin)。STABLE。';

-- ============================================================================
-- 13. RLS / GRANT
-- ----------------------------------------------------------------------------
-- 書込みの GRANT は一切与えない。テーブルの直接参照は運営のみ (ランクは本人の行も可)。
-- ============================================================================

revoke all on public.agent_ranks, public.agent_rank_reward_rates, public.agent_reward_entries
  from anon, authenticated;

revoke all on function app.agent_rank_label(public.agent_rank)         from public, anon, authenticated;
revoke all on function app.reward_seller_rate()                         from public, anon, authenticated;
revoke all on function app.reward_pool_rate()                           from public, anon, authenticated;
revoke all on function app.agent_rank_of(uuid)                          from public, anon, authenticated;
revoke all on function app.guard_agent_ranks_write()                    from public, anon, authenticated;
revoke all on function app.guard_rank_rates_write()                     from public, anon, authenticated;
revoke all on function app.guard_reward_entries_write()                 from public, anon, authenticated;
revoke all on function app.guard_reward_entries_truncate()              from public, anon, authenticated;
revoke all on function app.audit_agent_rank_change()                    from public, anon, authenticated;
revoke all on function app.audit_rank_rate_change()                     from public, anon, authenticated;
revoke all on function app.settle_order_rewards(uuid)                   from public, anon, authenticated;
revoke all on function app.reverse_order_rewards(uuid, text, text)      from public, anon, authenticated;
revoke all on function app.on_order_status_rewards()                    from public, anon, authenticated;
revoke all on function app.on_shipment_status_rewards()                 from public, anon, authenticated;

revoke all on function public.treemerce_admin_set_agent_rank(uuid, public.agent_rank, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_list_reward_rates()      from public, anon, authenticated;
revoke all on function public.treemerce_admin_set_reward_rate(public.agent_rank, numeric, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_reverse_order_rewards(uuid, text)
  from public, anon, authenticated;
revoke all on function public.treemerce_my_reward_entries(integer)     from public, anon, authenticated;
revoke all on function public.treemerce_admin_list_reward_entries(uuid, uuid, integer)
  from public, anon, authenticated;

grant execute on function public.treemerce_admin_set_agent_rank(uuid, public.agent_rank, text) to authenticated;
grant execute on function public.treemerce_admin_list_reward_rates()                          to authenticated;
grant execute on function public.treemerce_admin_set_reward_rate(public.agent_rank, numeric, text) to authenticated;
grant execute on function public.treemerce_admin_reverse_order_rewards(uuid, text)            to authenticated;
grant execute on function public.treemerce_my_reward_entries(integer)                         to authenticated;
grant execute on function public.treemerce_admin_list_reward_entries(uuid, uuid, integer)     to authenticated;

alter table public.agent_ranks             enable row level security;
alter table public.agent_rank_reward_rates enable row level security;
alter table public.agent_reward_entries    enable row level security;

create policy agent_ranks_select on public.agent_ranks
  for select to authenticated
  using (app.is_super_admin() or agent_ranks.agent_id = app.current_agent_id());

grant select on public.agent_ranks to authenticated;

create policy agent_rank_reward_rates_select on public.agent_rank_reward_rates
  for select to authenticated
  using (app.is_super_admin());

grant select on public.agent_rank_reward_rates to authenticated;

-- 明細のテーブルは運営のみ。オブザーバーは treemerce_my_reward_entries() で自分の分だけ。
create policy agent_reward_entries_select on public.agent_reward_entries
  for select to authenticated
  using (app.is_super_admin());

grant select on public.agent_reward_entries to authenticated;

commit;
