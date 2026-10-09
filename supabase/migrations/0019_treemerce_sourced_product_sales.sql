-- ============================================================================
-- TREEMERCE : 0019_treemerce_sourced_product_sales.sql
-- 持込み商品の売れ行き (P7: 読み取り専用 RPC)
-- ----------------------------------------------------------------------------
-- 実装の入口
--   持込み代理店本人の売れ行き : treemerce_my_sourced_product_sales(p_period)  (STABLE)
--
-- 返すもの
--   自分が持ち込んだ商品 (product_sources.sourced_by_agent_id = 自分) ごとの
--   「注文件数・数量・金額」だけ。対象は入金確認済み以降 (payment_confirmed / shipped / completed)。
--   購入者・販売した代理店・地域・日付などの内訳は一切返さない。
--
-- 丸め (n < 5 は「該当データ少数」)
--   (1) その商品の注文件数が 1〜4 件
--   (2) 「自分が把握できる注文」以外の件数が 1〜4 件
--       自分が把握できる注文 = 売上の帰属が自分 (orders.agent_id) または
--                              購入者を現に担当している (app.is_assigned_agent) 注文。
--       これを除かないと「合計 − 自分の担当分」で他の代理店の販売件数が分かってしまう
--       (例: 合計 6 件・自分の担当 5 件 → 他の代理店が 1 件)。
--   どちらかに当たる商品は件数・数量・金額をすべて null にする。0 件は 0 件として返す。
--   合計は「丸めていない商品だけの合計」とし、全商品の合計は返さない
--   (全体の合計から表示中の商品を引くと、丸めた商品の値が分かってしまうため)。
--
-- 絶対原則との対応
--   原則5 : 他の代理店が担当する顧客の購入内容・販売情報は、件数・金額の合算としてのみ扱い、
--           上の丸めで個別に特定できないようにする。代理店別の内訳は含めない。
--   原則3 : 持込み元・招待経路・顧客の担当・売上の帰属を参照するだけで、変更しない。
--   派生  : STABLE で定義し、書込みは構造的に不可能。
--
-- 期間をまたいだ差分 (全期間と直近 1 年の差など) には、期間ごとに同じ丸めをかける。
-- それでも残る差分のリスクは、期間を固定の 3 種類 (all / 1y / 3m) に限ることで小さくする。
-- ============================================================================

begin;

create or replace function public.treemerce_my_sourced_product_sales(p_period text default 'all')
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_self   uuid := app.current_agent_id();
  v_k      constant integer := 5;
  v_from   timestamptz;
  v_result jsonb;
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

  with src as (
    select ps.product_id, p.name, p.is_published, s.submission_no
    from public.product_sources ps
    join public.products p             on p.id = ps.product_id
    join public.product_submissions s  on s.id = ps.submission_id
    where ps.sourced_by_agent_id = v_self
  ),
  sales as (
    select oi.product_id,
           count(distinct o.id) as order_count,
           count(distinct o.id) filter (
             where o.agent_id = v_self or app.is_assigned_agent(o.customer_id)) as known_count,
           sum(oi.quantity) as quantity,
           sum(oi.amount)   as amount
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where oi.product_id in (select product_id from src)
      and o.status in ('payment_confirmed', 'shipped', 'completed')
      and (v_from is null or o.ordered_at >= v_from)
    group by oi.product_id
  ),
  merged as (
    select src.product_id, src.name, src.is_published, src.submission_no,
           coalesce(sales.order_count, 0)                                  as order_count,
           coalesce(sales.quantity, 0)                                     as quantity,
           coalesce(sales.amount, 0)                                       as amount,
           (   coalesce(sales.order_count, 0) between 1 and v_k - 1
            or (coalesce(sales.order_count, 0) - coalesce(sales.known_count, 0)) between 1 and v_k - 1
           )                                                                as suppressed
    from src
    left join sales on sales.product_id = src.product_id
  )
  select jsonb_build_object(
    'period',      p_period,
    'k_threshold', v_k,
    'products', coalesce(jsonb_agg(
      jsonb_build_object(
        'product_id',    m.product_id,
        'product_name',  m.name,
        'submission_no', m.submission_no,
        'is_published',  m.is_published,
        'suppressed',    m.suppressed,
        'label',         case when m.suppressed then '該当データ少数' end,
        'order_count',   case when m.suppressed then null else m.order_count end,
        'quantity',      case when m.suppressed then null else m.quantity end,
        'amount',        case when m.suppressed then null else m.amount end)
      order by m.name, m.product_id), '[]'::jsonb),
    'visible_total', jsonb_build_object(
      'product_count', count(*) filter (where not m.suppressed),
      'order_count',   coalesce(sum(m.order_count) filter (where not m.suppressed), 0),
      'quantity',      coalesce(sum(m.quantity)    filter (where not m.suppressed), 0),
      'amount',        coalesce(sum(m.amount)      filter (where not m.suppressed), 0)),
    'suppressed_product_count', count(*) filter (where m.suppressed),
    'generated_at', now()
  )
  into v_result
  from merged m;

  return v_result;
end;
$fn$;

comment on function public.treemerce_my_sourced_product_sales(text) is
  '持込み代理店本人の持込み商品の売れ行き (件数・数量・金額のみ、入金確認済み以降)。'
  '注文件数 1〜4 件、または本人が把握できない注文が 1〜4 件の商品は丸める。購入者・代理店別の内訳なし。STABLE。';

revoke all on function public.treemerce_my_sourced_product_sales(text) from public, anon, authenticated;
grant execute on function public.treemerce_my_sourced_product_sales(text) to authenticated;

commit;
