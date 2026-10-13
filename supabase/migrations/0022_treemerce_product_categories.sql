-- ============================================================================
-- TREEMERCE : 0022_treemerce_product_categories.sql
-- 商品カテゴリのマスタ (列挙型 product_category から、運営が管理できるテーブルへ)
-- ----------------------------------------------------------------------------
--   product_categories : カテゴリ。super_admin が追加・名称変更・並べ替え・有効/無効を切り替える。
--                        削除はできない (postgres の直接操作でも不可)。
--     code        : 英数字の固定キー。作成後は変更不可。客層分析の集計キーに使う。
--     name        : 表示名。名称変更はこの列だけを変える (過去の注文明細は注文時点の名前を持つ, 0024)。
--     legacy_code : 旧列挙型 product_category との対応 (1 対 1)。作成後は変更不可。
--                   確定済みの注文明細・申請・旧 purchases は書き換えず、この対応で読み替える。
--
-- 初期データ
--   一覧ページの 8 種類 + 旧カテゴリ (健康・美容・アパレル・デジタル・その他)。
--   旧の food → 食品・飲料、household → 生活雑貨、service → 施術・体験 に対応づける。
--   旧カテゴリはいったん有効で作り、0023 で商品を新カテゴリへ移したあと、使っていないものを無効にする。
--
-- 書込みのコンテキスト (GUC app.category_ctx):
--   'category_admin' : super_admin の RPC (実行者が app.is_super_admin() であること)
--   DB 管理者 (postgres) のコンテキスト外の直接操作は、初期データの投入のために許可する
--   (削除と id・code・legacy_code の変更は postgres でも不可)。
--
-- 使用中のカテゴリの無効化
--   公開中・準備中の商品が使っているカテゴリは無効にできない。商品のカテゴリ列は 0023 で追加するため、
--   判定関数 app.product_category_in_use は 0022 では常に false を返し、0023 で中身を入れる。
--
-- 監査ログ (admin_audit_logs): category.create / category.rename / category.activate /
--   category.deactivate / category.reorder (カテゴリ名は個人情報ではないため値を記録する)
--
-- 絶対原則との対応
--   原則1・3・4・5 : 代理店・顧客・招待経路・担当には触れない。顧客の情報は返さない。
--   派生           : 公開用の一覧 RPC は STABLE で、有効なカテゴリの名前と並び順だけを返す。
--
-- 実装の入口
--   公開 (未ログイン可) : treemerce_catalog_categories()                  (STABLE)
--   super_admin         : treemerce_admin_list_categories()               (STABLE)
--                         treemerce_admin_upsert_category(...)            (追加・名称変更)
--                         treemerce_admin_set_category_active(...)        (有効・無効、理由必須)
--                         treemerce_admin_reorder_categories(uuid[])      (並べ替え)
-- ============================================================================

begin;

-- ============================================================================
-- 1. product_categories
-- ============================================================================

create table public.product_categories (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique check (code ~ '^[a-z][a-z0-9_]{1,39}$'),
  name        text not null unique check (btrim(name) = name and char_length(name) between 1 and 40),
  sort_order  integer not null default 0,
  is_active   boolean not null default true,
  legacy_code public.product_category unique,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.product_categories is
  '商品カテゴリのマスタ。super_admin が RPC で管理する。削除不可。code / legacy_code は作成後に変更不可。'
  'authenticated / anon に権限なし (RPC 経由のみ)。';
comment on column public.product_categories.legacy_code is
  '旧列挙型 product_category との対応。確定済みの注文明細・申請・旧 purchases の読み替えに使う。変更不可。';

create index product_categories_sort_idx on public.product_categories (sort_order, name);

create trigger product_categories_touch_updated_at
  before update on public.product_categories
  for each row execute function app.touch_updated_at();

-- ============================================================================
-- 2. 使用中かどうかの判定 (0023 で products.category_id を見るように置き換える)
-- ============================================================================

create or replace function app.product_category_in_use(p_category_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select false;
$fn$;

-- ============================================================================
-- 3. 書込みガード
-- ============================================================================

create or replace function app.guard_product_categories_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.category_ctx', true), '');
begin
  -- 削除は誰にもさせない (無効化で扱う)
  if tg_op = 'DELETE' then
    raise exception 'TREEMERCE_CATEGORY_DELETE_DENIED: カテゴリは削除できません (無効化で扱う)'
      using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' and (new.id is distinct from old.id
                           or new.code is distinct from old.code
                           or new.legacy_code is distinct from old.legacy_code
                           or new.created_by is distinct from old.created_by
                           or new.created_at is distinct from old.created_at) then
    raise exception 'TREEMERCE_CATEGORY_IMMUTABLE: カテゴリのキー・旧カテゴリとの対応・作成情報は変更できません'
      using errcode = '42501';
  end if;

  -- 公開中・準備中の商品が使っているカテゴリは無効にできない (経路を問わない)
  if tg_op = 'UPDATE' and old.is_active and not new.is_active and app.product_category_in_use(new.id) then
    raise exception 'TREEMERCE_CATEGORY_IN_USE: 公開中・準備中の商品が使っているカテゴリは無効にできません'
      using errcode = '22023';
  end if;

  if current_user = 'postgres' and v_ctx = '' then
    return new;
  end if;

  if v_ctx = 'category_admin' then
    if not app.is_super_admin() then
      raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: カテゴリは super_admin のみ変更できます' using errcode = '42501';
    end if;
    if tg_op = 'INSERT' and new.legacy_code is not null then
      raise exception 'TREEMERCE_CATEGORY_IMMUTABLE: 旧カテゴリとの対応は新たに作れません' using errcode = '42501';
    end if;
    return new;
  end if;

  raise exception 'TREEMERCE_CATEGORY_WRITE_DENIED: カテゴリは super_admin の管理処理でのみ変更できます'
    using errcode = '42501';
end;
$fn$;

create trigger product_categories_guard
  before insert or update or delete on public.product_categories
  for each row execute function app.guard_product_categories_write();

-- ============================================================================
-- 4. 初期データ (一覧ページの 8 種類 + 旧カテゴリ)
-- ============================================================================

insert into public.product_categories (code, name, sort_order, legacy_code) values
  ('food_beverage',            '食品・飲料',       10, 'food'),
  ('fragrance_candle',         '香り・キャンドル', 20, null),
  ('five_dimensional_crystal', '五次元結晶',       30, null),
  ('treatment_experience',     '施術・体験',       40, 'service'),
  ('accessory',                'アクセサリー',     50, null),
  ('art',                      'アート',           60, null),
  ('household_goods',          '生活雑貨',         70, 'household'),
  ('stationery',               '文具',             80, null),
  ('health',                   '健康',            110, 'health'),
  ('beauty',                   '美容',            120, 'beauty'),
  ('apparel',                  'アパレル',        130, 'apparel'),
  ('digital',                  'デジタル',        140, 'digital'),
  ('other',                    'その他',          150, 'other');

-- 旧列挙型 → カテゴリ (確定済みの明細・申請・旧 purchases の読み替え用)
create or replace function app.category_id_for_legacy(p_legacy public.product_category)
returns uuid
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select c.id from public.product_categories c where c.legacy_code = p_legacy;
$fn$;

-- 監査ログ・返却用
create or replace function app.category_json(c public.product_categories)
returns jsonb
language sql
immutable
as $fn$
  select jsonb_build_object(
    'id',          c.id,
    'code',        c.code,
    'name',        c.name,
    'sort_order',  c.sort_order,
    'is_active',   c.is_active,
    'legacy_code', c.legacy_code,
    'updated_at',  c.updated_at
  );
$fn$;

-- ============================================================================
-- 5. 公開: 有効なカテゴリの一覧 (未ログイン可・STABLE)
-- ============================================================================

create or replace function public.treemerce_catalog_categories()
returns jsonb
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',         c.id,
           'code',       c.code,
           'name',       c.name,
           'sort_order', c.sort_order)
         order by c.sort_order, c.name), '[]'::jsonb)
  from public.product_categories c
  where c.is_active;
$fn$;

-- ============================================================================
-- 6. super_admin: 一覧 (無効を含む・STABLE)
-- ============================================================================

create or replace function public.treemerce_admin_list_categories()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: カテゴリの管理は super_admin のみ実行できます' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(app.category_json(c) || jsonb_build_object('in_use', app.product_category_in_use(c.id))
           order by c.sort_order, c.name)
    from public.product_categories c
  ), '[]'::jsonb);
end;
$fn$;

-- ============================================================================
-- 7. super_admin: 追加・名称変更
-- ----------------------------------------------------------------------------
-- p_category_id が NULL なら追加。p_code を省略するとキーを自動で作る。並び順は末尾。
-- 指定した場合は名称変更 (理由必須)。キーは変更できない (p_code を渡すなら現在のキーと一致すること)。
-- ============================================================================

create or replace function public.treemerce_admin_upsert_category(
  p_category_id uuid default null,
  p_name        text default null,
  p_code        text default null,
  p_reason      text default null
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
  v_name   text := nullif(btrim(coalesce(p_name, '')), '');
  v_code   text := nullif(lower(btrim(coalesce(p_code, ''))), '');
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_before public.product_categories%rowtype;
  v_after  public.product_categories%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: カテゴリの管理は super_admin のみ実行できます' using errcode = '42501';
  end if;
  if v_name is null or char_length(v_name) > 40 then
    raise exception 'TREEMERCE_INVALID_INPUT: カテゴリ名は 1〜40 文字で入力してください' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'TREEMERCE_INVALID_INPUT: 理由は 500 文字以内で入力してください' using errcode = '22023';
  end if;
  if v_code is not null and v_code !~ '^[a-z][a-z0-9_]{1,39}$' then
    raise exception 'TREEMERCE_INVALID_INPUT: キーは英小文字で始まる英小文字・数字・_ の 2〜40 文字で入力してください'
      using errcode = '22023';
  end if;
  if exists (select 1 from public.product_categories c
             where c.name = v_name and c.id is distinct from p_category_id) then
    raise exception 'TREEMERCE_INVALID_INPUT: 同じ名前のカテゴリがあります' using errcode = '22023';
  end if;

  if p_category_id is null then
    v_code := coalesce(v_code, 'cat_' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    if exists (select 1 from public.product_categories c where c.code = v_code) then
      raise exception 'TREEMERCE_INVALID_INPUT: 同じキーのカテゴリがあります' using errcode = '22023';
    end if;

    perform set_config('app.category_ctx', 'category_admin', true);
    insert into public.product_categories (code, name, sort_order, created_by)
    values (v_code, v_name,
            coalesce((select max(sort_order) from public.product_categories), 0) + 10, v_uid)
    returning * into v_after;
    perform set_config('app.category_ctx', '', true);

    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (v_uid, v_role, 'category.create', 'product_categories', v_after.id,
            null, app.category_json(v_after), v_reason);
  else
    select * into v_before from public.product_categories where id = p_category_id for update;
    if not found then
      raise exception 'TREEMERCE_CATEGORY_NOT_FOUND: カテゴリが見つかりません' using errcode = '22023';
    end if;
    if v_code is not null and v_code <> v_before.code then
      raise exception 'TREEMERCE_CATEGORY_IMMUTABLE: カテゴリのキーは変更できません' using errcode = '22023';
    end if;
    if v_name = v_before.name then
      return app.category_json(v_before) || jsonb_build_object('changed', false);
    end if;
    if v_reason is null then
      raise exception 'TREEMERCE_REASON_REQUIRED: カテゴリ名を変更する理由は必須です' using errcode = '22023';
    end if;

    perform set_config('app.category_ctx', 'category_admin', true);
    update public.product_categories set name = v_name where id = v_before.id returning * into v_after;
    perform set_config('app.category_ctx', '', true);

    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (v_uid, v_role, 'category.rename', 'product_categories', v_after.id,
            app.category_json(v_before), app.category_json(v_after), v_reason);
  end if;

  return app.category_json(v_after) || jsonb_build_object('changed', true);
end;
$fn$;

-- ============================================================================
-- 8. super_admin: 有効・無効 (理由必須。使用中のカテゴリはガードで無効化を拒否)
-- ============================================================================

create or replace function public.treemerce_admin_set_category_active(
  p_category_id uuid,
  p_is_active   boolean,
  p_reason      text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid    uuid := auth.uid();
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_before public.product_categories%rowtype;
  v_after  public.product_categories%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: カテゴリの管理は super_admin のみ実行できます' using errcode = '42501';
  end if;
  if p_is_active is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 有効か無効かを指定してください' using errcode = '22023';
  end if;
  if v_reason is null then
    raise exception 'TREEMERCE_REASON_REQUIRED: 有効・無効を切り替える理由は必須です' using errcode = '22023';
  end if;
  if char_length(v_reason) > 500 then
    raise exception 'TREEMERCE_INVALID_INPUT: 理由は 500 文字以内で入力してください' using errcode = '22023';
  end if;

  select * into v_before from public.product_categories where id = p_category_id for update;
  if not found then
    raise exception 'TREEMERCE_CATEGORY_NOT_FOUND: カテゴリが見つかりません' using errcode = '22023';
  end if;
  if v_before.is_active = p_is_active then
    return app.category_json(v_before) || jsonb_build_object('changed', false);
  end if;

  perform set_config('app.category_ctx', 'category_admin', true);
  update public.product_categories set is_active = p_is_active where id = v_before.id returning * into v_after;
  perform set_config('app.category_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, coalesce(app.admin_role(), 'super_admin'),
          case when p_is_active then 'category.activate' else 'category.deactivate' end,
          'product_categories', v_after.id, app.category_json(v_before), app.category_json(v_after), v_reason);

  return app.category_json(v_after) || jsonb_build_object('changed', true);
end;
$fn$;

-- ============================================================================
-- 9. super_admin: 並べ替え
-- ----------------------------------------------------------------------------
-- 全カテゴリの id を新しい順に 1 回ずつ並べて渡す (無効を含む)。過不足・重複は拒否する。
-- ============================================================================

create or replace function public.treemerce_admin_reorder_categories(
  p_category_ids uuid[],
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
  v_before jsonb;
  v_after  jsonb;
  v_total  integer;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: カテゴリの管理は super_admin のみ実行できます' using errcode = '42501';
  end if;

  -- 同時の並べ替え・追加と競合しないよう全行をロックする
  perform 1 from public.product_categories for update;
  select count(*) into v_total from public.product_categories;

  if p_category_ids is null
     or cardinality(p_category_ids) <> v_total
     or (select count(distinct x) from unnest(p_category_ids) x) <> v_total
     or exists (select 1 from unnest(p_category_ids) x
                where not exists (select 1 from public.product_categories c where c.id = x)) then
    raise exception 'TREEMERCE_INVALID_INPUT: すべてのカテゴリを 1 回ずつ並べて指定してください' using errcode = '22023';
  end if;

  select jsonb_agg(c.code order by c.sort_order, c.name) into v_before from public.product_categories c;

  perform set_config('app.category_ctx', 'category_admin', true);
  update public.product_categories c
  set sort_order = t.ord * 10
  from unnest(p_category_ids) with ordinality as t(id, ord)
  where c.id = t.id and c.sort_order is distinct from t.ord * 10;
  perform set_config('app.category_ctx', '', true);

  select jsonb_agg(c.code order by c.sort_order, c.name) into v_after from public.product_categories c;

  if v_before is distinct from v_after then
    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (v_uid, coalesce(app.admin_role(), 'super_admin'), 'category.reorder', 'product_categories', null,
            jsonb_build_object('order', v_before), jsonb_build_object('order', v_after),
            nullif(btrim(coalesce(p_reason, '')), ''));
  end if;

  return public.treemerce_admin_list_categories();
end;
$fn$;

-- ============================================================================
-- 10. RLS / GRANT
-- ----------------------------------------------------------------------------
-- product_categories は authenticated / anon に一切の権限を与えない (RPC 経由のみ)。
-- RLS は有効化し、ポリシーは作らない (万一 GRANT が復活しても 0 行)。
-- ============================================================================

revoke all on public.product_categories from anon, authenticated;
alter table public.product_categories enable row level security;

revoke all on function app.product_category_in_use(uuid)                    from public, anon, authenticated;
revoke all on function app.guard_product_categories_write()                 from public, anon, authenticated;
revoke all on function app.category_id_for_legacy(public.product_category)  from public, anon, authenticated;
revoke all on function app.category_json(public.product_categories)         from public, anon, authenticated;

revoke all on function public.treemerce_catalog_categories()                         from public, anon, authenticated;
revoke all on function public.treemerce_admin_list_categories()                      from public, anon, authenticated;
revoke all on function public.treemerce_admin_upsert_category(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.treemerce_admin_set_category_active(uuid, boolean, text) from public, anon, authenticated;
revoke all on function public.treemerce_admin_reorder_categories(uuid[], text)       from public, anon, authenticated;

grant execute on function public.treemerce_catalog_categories()                         to anon, authenticated;
grant execute on function public.treemerce_admin_list_categories()                      to authenticated;
grant execute on function public.treemerce_admin_upsert_category(uuid, text, text, text) to authenticated;
grant execute on function public.treemerce_admin_set_category_active(uuid, boolean, text) to authenticated;
grant execute on function public.treemerce_admin_reorder_categories(uuid[], text)       to authenticated;

commit;
