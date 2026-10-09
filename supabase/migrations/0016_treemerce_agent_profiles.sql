-- ============================================================================
-- TREEMERCE : 0016_treemerce_agent_profiles.sql
-- 代理店の事業プロフィール (P1: テーブル / 書込みガード / RPC / 監査)
-- ----------------------------------------------------------------------------
-- 代理店が自分で入力する事業情報 (業種・事業内容・取扱商品・得意な客層・活動エリア・
-- Web サイト / SNS・自己紹介)。見られるのは本人と super_admin のみ。
--
-- agents に列を足さない理由:
--   0004 の agents_select は「自分 + 傘下」の行を返し、agents には全列の SELECT GRANT が
--   付いている。ここに列を足すと傘上の代理店がテーブル直接参照で読めてしまうため、
--   1:1 の別テーブルにして authenticated には一切の権限を与えない (RPC 経由のみ)。
--   既存の agents.profile_bio は使わない (同じ理由で傘上から読めるため)。
--
-- 絶対原則との対応
--   原則1 : customers とは無関係。代理店だけのテーブル。
--   原則3 : 招待経路 (invited_by)・顧客の担当 (customer_assignments) を参照も変更もしない。
--   派生  : 商流マップ / コミュニティマップ / 公開プロフィールの RPC は変更しない。
--
-- 監査ログ (admin_audit_logs) は support / admin も閲覧できるため、プロフィールの値は
-- 書かず「入力済みの項目」と「変更した項目」の名前だけを記録する。
--
-- 実装の入口
--   本人の取得      : treemerce_my_agent_profile()                (STABLE)
--   本人の保存      : treemerce_update_my_agent_profile(...)
--   super_admin 取得: treemerce_admin_get_agent_profile(agent_id)  (STABLE)
-- ============================================================================

begin;

-- ============================================================================
-- 1. 列挙型
-- ============================================================================

create type public.agent_industry as enum
  ('agriculture', 'food_manufacturing', 'retail', 'restaurant',
   'beauty_health', 'service', 'other');

comment on type public.agent_industry is
  'agriculture=農業・漁業 / food_manufacturing=食品製造・加工 / retail=小売・卸売 / '
  'restaurant=飲食 / beauty_health=美容・健康 / service=サービス / other=その他';

-- ============================================================================
-- 2. 検証ヘルパー (CHECK 制約から使う)
-- ============================================================================

-- http(s) の URL のみ許可する (javascript: / data: などを構造的に排除)
create or replace function app.is_http_url(p_url text)
returns boolean
language sql
immutable
as $fn$
  select p_url is not null
     and char_length(p_url) <= 500
     and p_url ~* '^https?://[^/\s<>"'']+(/[^\s<>"'']*)?$';
$fn$;

create or replace function app.all_http_urls(p_urls text[])
returns boolean
language sql
immutable
as $fn$
  select coalesce(bool_and(app.is_http_url(u)), true)
  from unnest(coalesce(p_urls, '{}'::text[])) u;
$fn$;

create or replace function app.prefecture_list()
returns text[]
language sql
immutable
as $fn$
  select array[
    '北海道', '青森県', '岩手県', '宮城県', '秋田県', '山形県', '福島県',
    '茨城県', '栃木県', '群馬県', '埼玉県', '千葉県', '東京都', '神奈川県',
    '新潟県', '富山県', '石川県', '福井県', '山梨県', '長野県', '岐阜県',
    '静岡県', '愛知県', '三重県', '滋賀県', '京都府', '大阪府', '兵庫県',
    '奈良県', '和歌山県', '鳥取県', '島根県', '岡山県', '広島県', '山口県',
    '徳島県', '香川県', '愛媛県', '高知県', '福岡県', '佐賀県', '長崎県',
    '熊本県', '大分県', '宮崎県', '鹿児島県', '沖縄県']::text[];
$fn$;

-- ============================================================================
-- 3. agent_profiles (agents と 1:1)
-- ============================================================================

create table public.agent_profiles (
  agent_id             uuid primary key references public.agents (id) on delete cascade,

  industry             public.agent_industry,
  business_description text check (business_description is null or char_length(business_description) <= 2000),
  offerings            text check (offerings is null or char_length(offerings) <= 2000),
  target_customers     text check (target_customers is null or char_length(target_customers) <= 1000),
  activity_prefectures text[] not null default '{}'::text[],
  website_url          text,
  sns_urls             text[] not null default '{}'::text[],
  self_introduction    text check (self_introduction is null or char_length(self_introduction) <= 2000),

  updated_by           uuid references auth.users (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint agent_profiles_prefectures_valid
    check (activity_prefectures <@ app.prefecture_list()),
  constraint agent_profiles_website_url_valid
    check (website_url is null or app.is_http_url(website_url)),
  constraint agent_profiles_sns_urls_valid
    check (cardinality(sns_urls) <= 5 and app.all_http_urls(sns_urls))
);

comment on table public.agent_profiles is
  '代理店の事業プロフィール。本人と super_admin のみ閲覧 (RPC 経由)。authenticated に権限なし。'
  '招待経路・顧客の担当とは無関係。商流マップ / コミュニティマップには含めない。';

create trigger agent_profiles_touch_updated_at
  before update on public.agent_profiles
  for each row execute function app.touch_updated_at();

-- ============================================================================
-- 4. 書込みガード (多層防御)
-- ----------------------------------------------------------------------------
-- コンテキスト (GUC app.agent_ctx):
--   'agent_profile' : 本人によるプロフィール保存 (INSERT / UPDATE)
-- DB 管理者 (postgres) のコンテキスト外の直接操作は、既存のガードと同じく障害復旧経路として
-- 許可する (代理店の削除に伴う cascade もこの経路)。ただし agent_id の付け替えは誰にもさせない。
-- ============================================================================

create or replace function app.guard_agent_profiles_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.agent_ctx', true), '');
begin
  if tg_op = 'UPDATE' and new.agent_id is distinct from old.agent_id then
    raise exception 'TREEMERCE_PROFILE_IMMUTABLE: プロフィールの代理店は変更できません'
      using errcode = '42501';
  end if;

  if current_user = 'postgres' and v_ctx = '' then
    return coalesce(new, old);
  end if;
  if tg_op in ('INSERT', 'UPDATE') and v_ctx = 'agent_profile' then
    return new;
  end if;

  raise exception
    'TREEMERCE_PROFILE_WRITE_DENIED: プロフィールは本人の保存処理でのみ書き込めます'
    using errcode = '42501';
end;
$fn$;

create trigger agent_profiles_guard
  before insert or update or delete on public.agent_profiles
  for each row execute function app.guard_agent_profiles_write();

-- ============================================================================
-- 5. 監査用・返却用の状態
-- ============================================================================

-- 監査ログ用: 値は出さず、入力済みの項目名だけを返す
create or replace function app.agent_profile_filled_fields(p public.agent_profiles)
returns jsonb
language sql
immutable
as $fn$
  select coalesce(jsonb_agg(f order by f), '[]'::jsonb)
  from unnest(array[
    case when p.industry is not null then 'industry' end,
    case when p.business_description is not null then 'business_description' end,
    case when p.offerings is not null then 'offerings' end,
    case when p.target_customers is not null then 'target_customers' end,
    case when cardinality(p.activity_prefectures) > 0 then 'activity_prefectures' end,
    case when p.website_url is not null then 'website_url' end,
    case when cardinality(p.sns_urls) > 0 then 'sns_urls' end,
    case when p.self_introduction is not null then 'self_introduction' end
  ]) f
  where f is not null;
$fn$;

-- RPC の返却用 (本人 / super_admin のみに返す)
create or replace function app.agent_profile_json(p public.agent_profiles)
returns jsonb
language sql
immutable
as $fn$
  select jsonb_build_object(
    'agent_id',             p.agent_id,
    'industry',             p.industry,
    'business_description', p.business_description,
    'offerings',            p.offerings,
    'target_customers',     p.target_customers,
    'activity_prefectures', to_jsonb(p.activity_prefectures),
    'website_url',          p.website_url,
    'sns_urls',             to_jsonb(p.sns_urls),
    'self_introduction',    p.self_introduction,
    'updated_at',           p.updated_at
  );
$fn$;

-- 未入力時の返却 (項目は揃えて返す)
create or replace function app.agent_profile_empty_json(p_agent_id uuid)
returns jsonb
language sql
immutable
as $fn$
  select jsonb_build_object(
    'agent_id',             p_agent_id,
    'industry',             null,
    'business_description', null,
    'offerings',            null,
    'target_customers',     null,
    'activity_prefectures', '[]'::jsonb,
    'website_url',          null,
    'sns_urls',             '[]'::jsonb,
    'self_introduction',    null,
    'updated_at',           null
  );
$fn$;

-- ============================================================================
-- 6. 本人の取得 (STABLE)
-- ============================================================================

create or replace function public.treemerce_my_agent_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_self uuid := app.current_agent_id();
  v_row  public.agent_profiles%rowtype;
begin
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店アカウントが必要です' using errcode = '42501';
  end if;

  select * into v_row from public.agent_profiles where agent_id = v_self;
  if not found then
    return jsonb_build_object('found', false) || app.agent_profile_empty_json(v_self);
  end if;
  return jsonb_build_object('found', true) || app.agent_profile_json(v_row);
end;
$fn$;

-- ============================================================================
-- 7. 本人の保存
-- ----------------------------------------------------------------------------
-- 前後の空白を除き、空文字は NULL に、配列は空要素を除いて重複を除く (入力順を保つ)。
-- 変更がなければ監査ログは書かない。
-- ============================================================================

create or replace function public.treemerce_update_my_agent_profile(
  p_industry             public.agent_industry default null,
  p_business_description text                  default null,
  p_offerings            text                  default null,
  p_target_customers     text                  default null,
  p_activity_prefectures text[]                default null,
  p_website_url          text                  default null,
  p_sns_urls             text[]                default null,
  p_self_introduction    text                  default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid     uuid := auth.uid();
  v_self    uuid := app.current_agent_id();
  v_before  public.agent_profiles%rowtype;
  v_after   public.agent_profiles%rowtype;
  v_existed boolean;
  v_desc    text := nullif(btrim(coalesce(p_business_description, '')), '');
  v_offer   text := nullif(btrim(coalesce(p_offerings, '')), '');
  v_target  text := nullif(btrim(coalesce(p_target_customers, '')), '');
  v_web     text := nullif(btrim(coalesce(p_website_url, '')), '');
  v_intro   text := nullif(btrim(coalesce(p_self_introduction, '')), '');
  v_prefs   text[];
  v_sns     text[];
  v_changed text[];
begin
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店アカウントが必要です' using errcode = '42501';
  end if;

  select coalesce(array_agg(x order by ord), '{}'::text[]) into v_prefs
  from (
    select x, min(ord) as ord
    from unnest(coalesce(p_activity_prefectures, '{}'::text[])) with ordinality as t(raw, ord)
    cross join lateral (select nullif(btrim(coalesce(t.raw, '')), '') as x) n
    where x is not null
    group by x
  ) q;

  select coalesce(array_agg(x order by ord), '{}'::text[]) into v_sns
  from (
    select x, min(ord) as ord
    from unnest(coalesce(p_sns_urls, '{}'::text[])) with ordinality as t(raw, ord)
    cross join lateral (select nullif(btrim(coalesce(t.raw, '')), '') as x) n
    where x is not null
    group by x
  ) q;

  -- 制約違反の前に分かりやすいエラーを返す
  if v_desc is not null and char_length(v_desc) > 2000 then
    raise exception 'TREEMERCE_INVALID_INPUT: 事業内容は 2000 文字以内で入力してください' using errcode = '22023';
  end if;
  if v_offer is not null and char_length(v_offer) > 2000 then
    raise exception 'TREEMERCE_INVALID_INPUT: 取扱商品・サービスは 2000 文字以内で入力してください' using errcode = '22023';
  end if;
  if v_target is not null and char_length(v_target) > 1000 then
    raise exception 'TREEMERCE_INVALID_INPUT: 得意な客層・地域は 1000 文字以内で入力してください' using errcode = '22023';
  end if;
  if v_intro is not null and char_length(v_intro) > 2000 then
    raise exception 'TREEMERCE_INVALID_INPUT: 自己紹介は 2000 文字以内で入力してください' using errcode = '22023';
  end if;
  if not (v_prefs <@ app.prefecture_list()) then
    raise exception 'TREEMERCE_INVALID_INPUT: 活動エリアの都道府県が正しくありません' using errcode = '22023';
  end if;
  if v_web is not null and not app.is_http_url(v_web) then
    raise exception 'TREEMERCE_INVALID_INPUT: Web サイトの URL は http:// または https:// で始めてください'
      using errcode = '22023';
  end if;
  if cardinality(v_sns) > 5 then
    raise exception 'TREEMERCE_INVALID_INPUT: SNS の URL は 5 件までです' using errcode = '22023';
  end if;
  if not app.all_http_urls(v_sns) then
    raise exception 'TREEMERCE_INVALID_INPUT: SNS の URL は http:// または https:// で始めてください'
      using errcode = '22023';
  end if;

  select * into v_before from public.agent_profiles where agent_id = v_self for update;
  v_existed := found;

  if v_existed then
    v_changed := array_remove(array[
      case when v_before.industry             is distinct from p_industry then 'industry' end,
      case when v_before.business_description is distinct from v_desc     then 'business_description' end,
      case when v_before.offerings            is distinct from v_offer    then 'offerings' end,
      case when v_before.target_customers     is distinct from v_target   then 'target_customers' end,
      case when v_before.activity_prefectures is distinct from v_prefs    then 'activity_prefectures' end,
      case when v_before.website_url          is distinct from v_web      then 'website_url' end,
      case when v_before.sns_urls             is distinct from v_sns      then 'sns_urls' end,
      case when v_before.self_introduction    is distinct from v_intro    then 'self_introduction' end
    ], null);

    if cardinality(v_changed) = 0 then
      return jsonb_build_object('found', true, 'changed', false) || app.agent_profile_json(v_before);
    end if;
  end if;

  perform set_config('app.agent_ctx', 'agent_profile', true);

  insert into public.agent_profiles as ap
    (agent_id, industry, business_description, offerings, target_customers,
     activity_prefectures, website_url, sns_urls, self_introduction, updated_by)
  values
    (v_self, p_industry, v_desc, v_offer, v_target,
     v_prefs, v_web, v_sns, v_intro, v_uid)
  on conflict (agent_id) do update
    set industry             = excluded.industry,
        business_description = excluded.business_description,
        offerings            = excluded.offerings,
        target_customers     = excluded.target_customers,
        activity_prefectures = excluded.activity_prefectures,
        website_url          = excluded.website_url,
        sns_urls             = excluded.sns_urls,
        self_introduction    = excluded.self_introduction,
        updated_by           = excluded.updated_by
  returning * into v_after;

  perform set_config('app.agent_ctx', '', true);

  if not v_existed then
    v_changed := array(select jsonb_array_elements_text(app.agent_profile_filled_fields(v_after)));
  end if;

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, 'agent',
          case when v_existed then 'agent_profile.update' else 'agent_profile.create' end,
          'agent_profiles', v_self,
          case when v_existed
               then jsonb_build_object('filled_fields', app.agent_profile_filled_fields(v_before))
               else null end,
          jsonb_build_object('filled_fields',  app.agent_profile_filled_fields(v_after),
                             'changed_fields', to_jsonb(v_changed)),
          null);

  return jsonb_build_object('found', true, 'changed', true) || app.agent_profile_json(v_after);
end;
$fn$;

-- ============================================================================
-- 8. super_admin の取得 (STABLE)
-- ============================================================================

create or replace function public.treemerce_admin_get_agent_profile(p_agent_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_row public.agent_profiles%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 代理店のプロフィールは super_admin のみ参照できます'
      using errcode = '42501';
  end if;
  if not exists (select 1 from public.agents where id = p_agent_id) then
    raise exception 'TREEMERCE_AGENT_NOT_FOUND: 代理店が見つかりません' using errcode = '22023';
  end if;

  select * into v_row from public.agent_profiles where agent_id = p_agent_id;
  if not found then
    return jsonb_build_object('found', false) || app.agent_profile_empty_json(p_agent_id);
  end if;
  return jsonb_build_object('found', true) || app.agent_profile_json(v_row);
end;
$fn$;

-- ============================================================================
-- 9. RLS / GRANT
-- ----------------------------------------------------------------------------
-- agent_profiles は authenticated / anon に一切の権限を与えない (RPC 経由のみ)。
-- RLS は有効化し、ポリシーは作らない (万一 GRANT が復活しても 0 行)。
-- ============================================================================

revoke all on public.agent_profiles from anon, authenticated;
alter table public.agent_profiles enable row level security;

revoke all on function app.is_http_url(text)                                 from public, anon, authenticated;
revoke all on function app.all_http_urls(text[])                             from public, anon, authenticated;
revoke all on function app.prefecture_list()                                 from public, anon, authenticated;
revoke all on function app.guard_agent_profiles_write()                      from public, anon, authenticated;
revoke all on function app.agent_profile_filled_fields(public.agent_profiles) from public, anon, authenticated;
revoke all on function app.agent_profile_json(public.agent_profiles)          from public, anon, authenticated;
revoke all on function app.agent_profile_empty_json(uuid)                    from public, anon, authenticated;

revoke all on function public.treemerce_my_agent_profile() from public, anon, authenticated;
revoke all on function public.treemerce_update_my_agent_profile(
  public.agent_industry, text, text, text, text[], text, text[], text) from public, anon, authenticated;
revoke all on function public.treemerce_admin_get_agent_profile(uuid) from public, anon, authenticated;

grant execute on function public.treemerce_my_agent_profile() to authenticated;
grant execute on function public.treemerce_update_my_agent_profile(
  public.agent_industry, text, text, text, text[], text, text[], text) to authenticated;
grant execute on function public.treemerce_admin_get_agent_profile(uuid) to authenticated;

commit;
