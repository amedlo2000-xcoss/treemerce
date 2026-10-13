-- ============================================================================
-- TREEMERCE : 0020_treemerce_admin_agent_profile.sql
-- 代理店の事業プロフィールを super_admin が入力・編集する (0016 の拡張)
-- ----------------------------------------------------------------------------
-- 運営が代理店から話を聞いてプロフィールを入力できるようにする。
--
--   * 保存処理 (整形・検証・差分・監査) を app.save_agent_profile に切り出し、
--     本人用 (treemerce_update_my_agent_profile) と運営用の両方から使う。
--     本人用の引数・応答・エラーは 0016 のまま変えない。
--   * agent_profiles.updated_by_role : 最後に更新したのが本人か運営か ('agent' / 'super_admin')。
--   * 運営の編集は、既存プロフィールの変更のときだけ理由必須 (初回の入力は任意)。
--   * 同時編集の検出: 運営は画面を開いた時点の updated_at (未入力なら NULL) を渡し、
--     現在の値と違えば保存せずに TREEMERCE_PROFILE_CONFLICT を返す。
--   * 退会済み (withdrawn) の代理店のプロフィールは運営も編集できない。
--
-- 監査ログ (admin_audit_logs) は support / admin も閲覧できるため、0016 と同じく
-- 値は書かず「入力済みの項目」「変更した項目」の名前と理由だけを記録する。
--   本人   : agent_profile.create / agent_profile.update             (actor_role = 'agent')
--   運営   : agent_profile.admin_create / agent_profile.admin_update (actor_role = super_admin)
--
-- 絶対原則との対応
--   原則1 : customers とは無関係。
--   原則3・4 : 招待経路 (invited_by)・顧客の担当 (customer_assignments) を参照も変更もしない。
--   派生  : 商流マップ / コミュニティマップ / 公開プロフィールの RPC は変更しない。
--
-- 書込みのコンテキスト (GUC app.agent_ctx):
--   'agent_profile'       : 本人の保存 (updated_by_role = 'agent' のみ)
--   'agent_profile_admin' : super_admin の保存 (updated_by_role = 'super_admin' のみ、
--                           実行者が app.is_super_admin() であること)
--
-- 実装の入口
--   super_admin の保存 : treemerce_admin_update_agent_profile(agent_id, ..., reason, expected_updated_at)
-- ============================================================================

begin;

-- ============================================================================
-- 1. 列の追加 (最後に更新したのは本人か運営か)
-- ============================================================================

alter table public.agent_profiles
  add column updated_by_role text not null default 'agent'
    constraint agent_profiles_updated_by_role_valid check (updated_by_role in ('agent', 'super_admin'));

comment on column public.agent_profiles.updated_by_role is
  '最後に更新したのが代理店本人 (agent) か運営 (super_admin) か。本人と super_admin にのみ返す。';

-- ============================================================================
-- 2. 書込みガード (0016 を置き換え)
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
    if new.updated_by_role <> 'agent' then
      raise exception 'TREEMERCE_PROFILE_WRITE_DENIED: 本人の保存では更新者を運営にできません'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if tg_op in ('INSERT', 'UPDATE') and v_ctx = 'agent_profile_admin' then
    if not app.is_super_admin() then
      raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 代理店のプロフィールは super_admin のみ編集できます'
        using errcode = '42501';
    end if;
    if new.updated_by_role <> 'super_admin' then
      raise exception 'TREEMERCE_PROFILE_WRITE_DENIED: 運営の保存では更新者を本人にできません'
        using errcode = '42501';
    end if;
    return new;
  end if;

  raise exception
    'TREEMERCE_PROFILE_WRITE_DENIED: プロフィールは本人または super_admin の保存処理でのみ書き込めます'
    using errcode = '42501';
end;
$fn$;

-- ============================================================================
-- 3. 返却用 (updated_by_role を追加。0016 を置き換え)
-- ============================================================================

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
    'updated_at',           p.updated_at,
    'updated_by_role',      p.updated_by_role
  );
$fn$;

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
    'updated_at',           null,
    'updated_by_role',      null
  );
$fn$;

-- ============================================================================
-- 4. 保存処理の共通部分
-- ----------------------------------------------------------------------------
-- p_actor = 'agent'       : 本人。呼び出し側で p_agent_id = app.current_agent_id() を保証する。
-- p_actor = 'super_admin' : 運営。権限・代理店の状態・同時編集・理由をここで確認する。
-- 前後の空白を除き、空文字は NULL に、配列は空要素を除いて重複を除く (入力順を保つ)。
-- 変更がなければ書込みも監査ログも行わない。
-- ============================================================================

create or replace function app.save_agent_profile(
  p_agent_id             uuid,
  p_actor                text,
  p_reason               text,
  p_expected_updated_at  timestamptz,
  p_industry             public.agent_industry,
  p_business_description text,
  p_offerings            text,
  p_target_customers     text,
  p_activity_prefectures text[],
  p_website_url          text,
  p_sns_urls             text[],
  p_self_introduction    text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid     uuid := auth.uid();
  v_admin   boolean := (p_actor = 'super_admin');
  v_status  public.agent_status;
  v_before  public.agent_profiles%rowtype;
  v_after   public.agent_profiles%rowtype;
  v_existed boolean;
  v_desc    text := nullif(btrim(coalesce(p_business_description, '')), '');
  v_offer   text := nullif(btrim(coalesce(p_offerings, '')), '');
  v_target  text := nullif(btrim(coalesce(p_target_customers, '')), '');
  v_web     text := nullif(btrim(coalesce(p_website_url, '')), '');
  v_intro   text := nullif(btrim(coalesce(p_self_introduction, '')), '');
  v_reason  text := nullif(btrim(coalesce(p_reason, '')), '');
  v_prefs   text[];
  v_sns     text[];
  v_changed text[];
begin
  if p_actor not in ('agent', 'super_admin') then
    raise exception 'TREEMERCE_FORBIDDEN: 不正な実行者です' using errcode = '42501';
  end if;

  if v_admin then
    if not app.is_super_admin() then
      raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 代理店のプロフィールは super_admin のみ編集できます'
        using errcode = '42501';
    end if;
    select a.status into v_status from public.agents a where a.id = p_agent_id;
    if not found then
      raise exception 'TREEMERCE_AGENT_NOT_FOUND: 代理店が見つかりません' using errcode = '22023';
    end if;
    if v_status = 'withdrawn' then
      raise exception 'TREEMERCE_AGENT_WITHDRAWN: 退会済みの代理店のプロフィールは編集できません'
        using errcode = '22023';
    end if;
    if v_reason is not null and char_length(v_reason) > 500 then
      raise exception 'TREEMERCE_INVALID_INPUT: 理由は 500 文字以内で入力してください' using errcode = '22023';
    end if;
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

  select * into v_before from public.agent_profiles where agent_id = p_agent_id for update;
  v_existed := found;

  -- 運営: 画面を開いた後に本人などが保存していたら上書きしない
  if v_admin and p_expected_updated_at is distinct from (case when v_existed then v_before.updated_at end) then
    raise exception 'TREEMERCE_PROFILE_CONFLICT: 画面を開いた後にプロフィールが更新されています。開き直してから編集してください'
      using errcode = '22023';
  end if;

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

    -- 運営による既存プロフィールの変更は理由必須
    if v_admin and v_reason is null then
      raise exception 'TREEMERCE_REASON_REQUIRED: 入力済みのプロフィールを変更する理由は必須です'
        using errcode = '22023';
    end if;
  end if;

  perform set_config('app.agent_ctx', case when v_admin then 'agent_profile_admin' else 'agent_profile' end, true);

  insert into public.agent_profiles as ap
    (agent_id, industry, business_description, offerings, target_customers,
     activity_prefectures, website_url, sns_urls, self_introduction, updated_by, updated_by_role)
  values
    (p_agent_id, p_industry, v_desc, v_offer, v_target,
     v_prefs, v_web, v_sns, v_intro, v_uid, p_actor)
  on conflict (agent_id) do update
    set industry             = excluded.industry,
        business_description = excluded.business_description,
        offerings            = excluded.offerings,
        target_customers     = excluded.target_customers,
        activity_prefectures = excluded.activity_prefectures,
        website_url          = excluded.website_url,
        sns_urls             = excluded.sns_urls,
        self_introduction    = excluded.self_introduction,
        updated_by           = excluded.updated_by,
        updated_by_role      = excluded.updated_by_role
  returning * into v_after;

  perform set_config('app.agent_ctx', '', true);

  if not v_existed then
    v_changed := array(select jsonb_array_elements_text(app.agent_profile_filled_fields(v_after)));
  end if;

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid,
          case when v_admin then coalesce(app.admin_role(), 'super_admin') else 'agent' end,
          case when v_admin then
                 case when v_existed then 'agent_profile.admin_update' else 'agent_profile.admin_create' end
               else
                 case when v_existed then 'agent_profile.update' else 'agent_profile.create' end
          end,
          'agent_profiles', p_agent_id,
          case when v_existed
               then jsonb_build_object('filled_fields', app.agent_profile_filled_fields(v_before),
                                       'updated_by_role', v_before.updated_by_role)
               else null end,
          jsonb_build_object('filled_fields',   app.agent_profile_filled_fields(v_after),
                             'changed_fields',  to_jsonb(v_changed),
                             'updated_by_role', v_after.updated_by_role),
          case when v_admin then v_reason else null end);

  return jsonb_build_object('found', true, 'changed', true) || app.agent_profile_json(v_after);
end;
$fn$;

-- ============================================================================
-- 5. 本人の保存 (0016 を置き換え。引数・応答は変えない)
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
  v_self uuid := app.current_agent_id();
begin
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店アカウントが必要です' using errcode = '42501';
  end if;

  return app.save_agent_profile(
    v_self, 'agent', null, null,
    p_industry, p_business_description, p_offerings, p_target_customers,
    p_activity_prefectures, p_website_url, p_sns_urls, p_self_introduction);
end;
$fn$;

-- ============================================================================
-- 6. super_admin の保存
-- ----------------------------------------------------------------------------
-- p_expected_updated_at : 画面を開いた時点の updated_at (未入力のプロフィールなら NULL)。
-- p_reason              : 既存プロフィールの変更では必須 (初回の入力は任意)。
-- ============================================================================

create or replace function public.treemerce_admin_update_agent_profile(
  p_agent_id             uuid,
  p_industry             public.agent_industry default null,
  p_business_description text                  default null,
  p_offerings            text                  default null,
  p_target_customers     text                  default null,
  p_activity_prefectures text[]                default null,
  p_website_url          text                  default null,
  p_sns_urls             text[]                default null,
  p_self_introduction    text                  default null,
  p_reason               text                  default null,
  p_expected_updated_at  timestamptz           default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 代理店のプロフィールは super_admin のみ編集できます'
      using errcode = '42501';
  end if;

  return app.save_agent_profile(
    p_agent_id, 'super_admin', p_reason, p_expected_updated_at,
    p_industry, p_business_description, p_offerings, p_target_customers,
    p_activity_prefectures, p_website_url, p_sns_urls, p_self_introduction);
end;
$fn$;

-- ============================================================================
-- 7. GRANT
-- ============================================================================

revoke all on function app.guard_agent_profiles_write()                      from public, anon, authenticated;
revoke all on function app.agent_profile_json(public.agent_profiles)          from public, anon, authenticated;
revoke all on function app.agent_profile_empty_json(uuid)                    from public, anon, authenticated;
revoke all on function app.save_agent_profile(
  uuid, text, text, timestamptz, public.agent_industry, text, text, text, text[], text, text[], text)
  from public, anon, authenticated;

revoke all on function public.treemerce_update_my_agent_profile(
  public.agent_industry, text, text, text, text[], text, text[], text) from public, anon, authenticated;
revoke all on function public.treemerce_admin_update_agent_profile(
  uuid, public.agent_industry, text, text, text, text[], text, text[], text, text, timestamptz)
  from public, anon, authenticated;

grant execute on function public.treemerce_update_my_agent_profile(
  public.agent_industry, text, text, text, text[], text, text[], text) to authenticated;
grant execute on function public.treemerce_admin_update_agent_profile(
  uuid, public.agent_industry, text, text, text, text[], text, text[], text, text, timestamptz)
  to authenticated;

commit;
