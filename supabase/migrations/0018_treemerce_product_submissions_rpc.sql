-- ============================================================================
-- TREEMERCE : 0018_treemerce_product_submissions_rpc.sql
-- 商品の持込み申請 (P4: RPC)
-- ----------------------------------------------------------------------------
-- 実装の入口
--   代理店 (本人のみ。対象は常に app.current_agent_id() の申請に限る)
--     申請の作成・保存     : treemerce_save_my_submission        (下書き・差し戻しのみ)
--     申請・再申請         : treemerce_submit_my_submission
--     取り下げ             : treemerce_withdraw_my_submission
--     自分の申請一覧       : treemerce_my_submissions            (STABLE)
--     自分の申請詳細       : treemerce_my_submission             (STABLE。生産者の連絡先を含む)
--     画像の枠の確保       : treemerce_reserve_submission_image  (確保したパスにだけアップロード可)
--     画像の削除           : treemerce_remove_submission_image
--   super_admin
--     申請一覧             : treemerce_admin_list_submissions    (STABLE。連絡先は含めない)
--     申請詳細             : treemerce_admin_get_submission      (STABLE。連絡先・履歴の内容を含む)
--     承認                 : treemerce_admin_approve_submission  (生産者と商品を非公開の下書きで作成)
--     差し戻し             : treemerce_admin_return_submission   (理由必須)
--     却下                 : treemerce_admin_reject_submission   (理由必須)
--
-- 方針
--   * 他の代理店の申請 ID を指定しても「見つかりません」を返す (存在も開示しない)。
--   * 承認すると、申請内容から生産者 (または既存の生産者を選択) と商品を作成する。
--     商品は在庫 0・非公開で作る。公開は super_admin が価格・在庫を確定してから
--     既存の treemerce_admin_upsert_product で行い、0017 の公開ガードと監査トリガが働く。
--   * 操作はすべて admin_audit_logs に残す (代理店の操作は actor_role = 'agent')。
--     admin_audit_logs は support / admin も閲覧できるため、生産者の連絡先は値を書かず
--     「設定あり / 変更あり」だけを記録する。申請時点の内容 (連絡先を含む) は
--     product_submission_events に残し、本人と super_admin にのみ返す。
--   * 持込み元 (product_sources) は承認時に記録する。招待経路・顧客の担当・売上の帰属は
--     参照も変更もしない (原則3)。
-- ============================================================================

begin;

-- ============================================================================
-- 0. 共通ヘルパー
-- ============================================================================

-- 前後の空白を除き、空なら NULL。上限を超えたら項目名付きで拒否する。
create or replace function app.submission_text(p_value text, p_max integer, p_label text)
returns text
language plpgsql
immutable
as $fn$
declare
  v text := nullif(btrim(coalesce(p_value, '')), '');
begin
  if v is not null and char_length(v) > p_max then
    raise exception 'TREEMERCE_INVALID_INPUT: %は % 文字以内で入力してください', p_label, p_max
      using errcode = '22023';
  end if;
  return v;
end;
$fn$;

-- 申請の内容 (本人 / super_admin にのみ返す)。p_with_contact = false で連絡先を除く。
create or replace function app.submission_json(s public.product_submissions, p_with_contact boolean)
returns jsonb
language sql
immutable
as $fn$
  select jsonb_build_object(
    'id',                            s.id,
    'submission_no',                 s.submission_no,
    'status',                        s.status,
    'revision',                      s.revision,
    'name',                          s.name,
    'category',                      s.category,
    'description',                   s.description,
    'desired_price',                 s.desired_price,
    'expected_wholesale_price',      s.expected_wholesale_price,
    'content_volume',                s.content_volume,
    'ingredients',                   s.ingredients,
    'best_before_note',              s.best_before_note,
    'producer_name',                 s.producer_name,
    'producer_origin',               s.producer_origin,
    'producer_ship_from_prefecture', s.producer_ship_from_prefecture,
    'producer_ship_lead_time',       s.producer_ship_lead_time,
    'submitted_at',                  s.submitted_at,
    'reviewed_at',                   s.reviewed_at,
    'review_reason',                 s.review_reason,
    'created_at',                    s.created_at,
    'updated_at',                    s.updated_at
  )
  || case when p_with_contact then jsonb_build_object(
       'producer_contact_name',  s.producer_contact_name,
       'producer_contact_phone', s.producer_contact_phone,
       'producer_contact_email', s.producer_contact_email)
     else '{}'::jsonb end;
$fn$;

-- 監査ログ用 (連絡先は値を出さない)
create or replace function app.submission_audit_state(s public.product_submissions)
returns jsonb
language sql
immutable
as $fn$
  select jsonb_build_object(
    'submission_no',          s.submission_no,
    'agent_id',               s.agent_id,
    'status',                 s.status,
    'revision',               s.revision,
    'name',                   s.name,
    'category',               s.category,
    'desired_price',          s.desired_price,
    'producer_name',          s.producer_name,
    'has_producer_contact',   (s.producer_contact_name is not null or s.producer_contact_phone is not null
                               or s.producer_contact_email is not null)
  );
$fn$;

-- 変更した項目名 (連絡先は 'producer_contact' にまとめる)
create or replace function app.submission_changed_fields(o public.product_submissions, n public.product_submissions)
returns jsonb
language sql
immutable
as $fn$
  select coalesce(jsonb_agg(f), '[]'::jsonb)
  from unnest(array[
    case when o.name                          is distinct from n.name then 'name' end,
    case when o.category                      is distinct from n.category then 'category' end,
    case when o.description                   is distinct from n.description then 'description' end,
    case when o.desired_price                 is distinct from n.desired_price then 'desired_price' end,
    case when o.expected_wholesale_price      is distinct from n.expected_wholesale_price then 'expected_wholesale_price' end,
    case when o.content_volume                is distinct from n.content_volume then 'content_volume' end,
    case when o.ingredients                   is distinct from n.ingredients then 'ingredients' end,
    case when o.best_before_note              is distinct from n.best_before_note then 'best_before_note' end,
    case when o.producer_name                 is distinct from n.producer_name then 'producer_name' end,
    case when o.producer_origin               is distinct from n.producer_origin then 'producer_origin' end,
    case when o.producer_ship_from_prefecture is distinct from n.producer_ship_from_prefecture then 'producer_ship_from_prefecture' end,
    case when o.producer_ship_lead_time       is distinct from n.producer_ship_lead_time then 'producer_ship_lead_time' end,
    case when o.producer_contact_name  is distinct from n.producer_contact_name
           or o.producer_contact_phone is distinct from n.producer_contact_phone
           or o.producer_contact_email is distinct from n.producer_contact_email then 'producer_contact' end
  ]) f
  where f is not null;
$fn$;

create or replace function app.submission_images_json(p_submission_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',           i.id,
           'storage_path', i.storage_path,
           'content_type', i.content_type,
           'sort_order',   i.sort_order)
         order by i.sort_order, i.created_at), '[]'::jsonb)
  from public.product_submission_images i
  where i.submission_id = p_submission_id;
$fn$;

-- 状態変更履歴。p_with_snapshot = true は super_admin 用 (申請時点の内容を含む)
create or replace function app.submission_events_json(p_submission_id uuid, p_with_snapshot boolean)
returns jsonb
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'revision',    e.revision,
             'from_status', e.from_status,
             'to_status',   e.to_status,
             'reason',      e.reason,
             'actor_role',  e.actor_role,
             'changed_at',  e.changed_at)
           || case when p_with_snapshot then jsonb_build_object('content_snapshot', e.content_snapshot)
                   else '{}'::jsonb end
         order by e.changed_at), '[]'::jsonb)
  from public.product_submission_events e
  where e.submission_id = p_submission_id;
$fn$;

-- 本人の申請を 1 件ロックして取得 (他人の申請・存在しない申請は同じ「見つかりません」)
create or replace function app.lock_my_submission(p_submission_id uuid)
returns public.product_submissions
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_self uuid := app.current_agent_id();
  v_row  public.product_submissions%rowtype;
begin
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店アカウントが必要です' using errcode = '42501';
  end if;
  select * into v_row from public.product_submissions
  where id = p_submission_id and agent_id = v_self
  for update;
  if not found then
    raise exception 'TREEMERCE_SUBMISSION_NOT_FOUND: 申請が見つかりません' using errcode = '22023';
  end if;
  return v_row;
end;
$fn$;

-- ============================================================================
-- 1. 代理店: 申請の作成・保存 (下書き・差し戻しの間のみ)
-- ----------------------------------------------------------------------------
-- 全項目を受け取り、そのまま置き換える (フォームの保存)。p_submission_id が NULL なら下書きを作る。
-- 商品名は下書きでも必須。その他の必須項目は申請時 (treemerce_submit_my_submission) に確認する。
-- ============================================================================

create or replace function public.treemerce_save_my_submission(
  p_submission_id                 uuid                   default null,
  p_name                          text                   default null,
  p_category                      public.product_category default 'other',
  p_description                   text                   default null,
  p_desired_price                 numeric                default null,
  p_expected_wholesale_price      numeric                default null,
  p_content_volume                text                   default null,
  p_ingredients                   text                   default null,
  p_best_before_note              text                   default null,
  p_producer_name                 text                   default null,
  p_producer_origin               text                   default null,
  p_producer_ship_from_prefecture text                   default null,
  p_producer_ship_lead_time       text                   default null,
  p_producer_contact_name         text                   default null,
  p_producer_contact_phone        text                   default null,
  p_producer_contact_email        text                   default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid    uuid := auth.uid();
  v_self   uuid := app.current_agent_id();
  v_before public.product_submissions%rowtype;
  v_after  public.product_submissions%rowtype;
  v_name   text;
  v_desc   text;
  v_volume text;
  v_ingr   text;
  v_best   text;
  v_p_name text;
  v_origin text;
  v_pref   text := nullif(btrim(coalesce(p_producer_ship_from_prefecture, '')), '');
  v_lead   text;
  v_c_name text;
  v_c_tel  text;
  v_c_mail text := nullif(lower(btrim(coalesce(p_producer_contact_email, ''))), '');
begin
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店アカウントが必要です' using errcode = '42501';
  end if;

  v_name   := app.submission_text(p_name, 100, '商品名');
  v_desc   := app.submission_text(p_description, 4000, '説明');
  v_volume := app.submission_text(p_content_volume, 200, '内容量');
  v_ingr   := app.submission_text(p_ingredients, 2000, '原材料');
  v_best   := app.submission_text(p_best_before_note, 200, '期限の目安');
  v_p_name := app.submission_text(p_producer_name, 100, '生産者名');
  v_origin := app.submission_text(p_producer_origin, 100, '産地');
  v_lead   := app.submission_text(p_producer_ship_lead_time, 100, '発送目安');
  v_c_name := app.submission_text(p_producer_contact_name, 100, '生産者の担当者名');
  v_c_tel  := app.submission_text(p_producer_contact_phone, 30, '生産者の電話番号');

  if v_name is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 商品名は必須です' using errcode = '22023';
  end if;
  if p_desired_price is not null and (p_desired_price < 0 or p_desired_price >= 100000000) then
    raise exception 'TREEMERCE_INVALID_INPUT: 希望販売価格は 0 円以上 1 億円未満で入力してください'
      using errcode = '22023';
  end if;
  if p_expected_wholesale_price is not null
     and (p_expected_wholesale_price < 0 or p_expected_wholesale_price >= 100000000) then
    raise exception 'TREEMERCE_INVALID_INPUT: 想定卸値は 0 円以上 1 億円未満で入力してください'
      using errcode = '22023';
  end if;
  if v_pref is not null and not (v_pref = any (app.prefecture_list())) then
    raise exception 'TREEMERCE_INVALID_INPUT: 発送元の都道府県が正しくありません' using errcode = '22023';
  end if;
  if v_c_mail is not null and v_c_mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'TREEMERCE_INVALID_INPUT: 生産者の連絡先メールの形式が正しくありません'
      using errcode = '22023';
  end if;

  if p_submission_id is null then
    perform set_config('app.submission_ctx', 'submission_agent', true);

    insert into public.product_submissions
      (agent_id, name, category, description, desired_price, expected_wholesale_price,
       content_volume, ingredients, best_before_note,
       producer_name, producer_origin, producer_ship_from_prefecture, producer_ship_lead_time,
       producer_contact_name, producer_contact_phone, producer_contact_email, created_by)
    values
      (v_self, v_name, coalesce(p_category, 'other'), v_desc, p_desired_price, p_expected_wholesale_price,
       v_volume, v_ingr, v_best,
       v_p_name, v_origin, v_pref, v_lead,
       v_c_name, v_c_tel, v_c_mail, v_uid)
    returning * into v_after;

    perform set_config('app.submission_ctx', '', true);

    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (v_uid, 'agent', 'submission.create', 'product_submissions', v_after.id,
            null, app.submission_audit_state(v_after), null);
  else
    v_before := app.lock_my_submission(p_submission_id);
    if v_before.status not in ('draft', 'returned') then
      raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 申請中・確定済みの申請は編集できません'
        using errcode = '22023';
    end if;

    perform set_config('app.submission_ctx', 'submission_agent', true);

    update public.product_submissions
    set name                          = v_name,
        category                      = coalesce(p_category, 'other'),
        description                   = v_desc,
        desired_price                 = p_desired_price,
        expected_wholesale_price      = p_expected_wholesale_price,
        content_volume                = v_volume,
        ingredients                   = v_ingr,
        best_before_note              = v_best,
        producer_name                 = v_p_name,
        producer_origin               = v_origin,
        producer_ship_from_prefecture = v_pref,
        producer_ship_lead_time       = v_lead,
        producer_contact_name         = v_c_name,
        producer_contact_phone        = v_c_tel,
        producer_contact_email        = v_c_mail
    where id = v_before.id
    returning * into v_after;

    perform set_config('app.submission_ctx', '', true);

    if jsonb_array_length(app.submission_changed_fields(v_before, v_after)) > 0 then
      insert into public.admin_audit_logs
        (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
      values (v_uid, 'agent', 'submission.update', 'product_submissions', v_after.id,
              app.submission_audit_state(v_before),
              app.submission_audit_state(v_after)
                || jsonb_build_object('changed_fields', app.submission_changed_fields(v_before, v_after)),
              null);
    end if;
  end if;

  return app.submission_json(v_after, true)
         || jsonb_build_object('images', app.submission_images_json(v_after.id));
end;
$fn$;

-- ============================================================================
-- 2. 代理店: 申請・再申請
-- ============================================================================

create or replace function public.treemerce_submit_my_submission(p_submission_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid     uuid := auth.uid();
  v_before  public.product_submissions%rowtype;
  v_after   public.product_submissions%rowtype;
  v_missing text[];
begin
  v_before := app.lock_my_submission(p_submission_id);
  if v_before.status not in ('draft', 'returned') then
    raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: この申請は申請できる状態ではありません'
      using errcode = '22023';
  end if;

  v_missing := array_remove(array[
    case when v_before.description is null then '説明' end,
    case when v_before.desired_price is null then '希望販売価格' end,
    case when v_before.content_volume is null then '内容量' end,
    case when v_before.producer_name is null then '生産者名' end,
    case when v_before.producer_origin is null then '産地' end,
    case when v_before.producer_ship_from_prefecture is null then '発送元の都道府県' end,
    case when v_before.producer_ship_lead_time is null then '発送目安' end,
    case when v_before.producer_contact_phone is null and v_before.producer_contact_email is null
         then '生産者の連絡先 (電話またはメール)' end
  ], null);
  if cardinality(v_missing) > 0 then
    raise exception 'TREEMERCE_INVALID_INPUT: 未入力の項目があります: %', array_to_string(v_missing, '、')
      using errcode = '22023';
  end if;

  perform set_config('app.submission_ctx', 'submission_agent', true);

  update public.product_submissions
  set status       = 'submitted',
      revision     = v_before.revision + 1,
      submitted_at = clock_timestamp()
  where id = v_before.id
  returning * into v_after;

  insert into public.product_submission_events
    (submission_id, revision, from_status, to_status, reason, content_snapshot, actor_user_id, actor_role)
  values (v_after.id, v_after.revision, v_before.status, 'submitted', null,
          app.submission_json(v_after, true)
            || jsonb_build_object('images', app.submission_images_json(v_after.id)),
          v_uid, 'agent');

  perform set_config('app.submission_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, 'agent',
          case when v_before.status = 'returned' then 'submission.resubmit' else 'submission.submit' end,
          'product_submissions', v_after.id,
          app.submission_audit_state(v_before), app.submission_audit_state(v_after), null);

  return app.submission_json(v_after, true)
         || jsonb_build_object('images', app.submission_images_json(v_after.id));
end;
$fn$;

-- ============================================================================
-- 3. 代理店: 取り下げ (下書き・差し戻しのみ。削除はしない)
-- ============================================================================

create or replace function public.treemerce_withdraw_my_submission(
  p_submission_id uuid,
  p_reason        text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid    uuid := auth.uid();
  v_before public.product_submissions%rowtype;
  v_after  public.product_submissions%rowtype;
  v_reason text := app.submission_text(p_reason, 500, '取り下げの理由');
begin
  v_before := app.lock_my_submission(p_submission_id);
  if v_before.status not in ('draft', 'returned') then
    raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 申請中・確定済みの申請は取り下げられません'
      using errcode = '22023';
  end if;

  perform set_config('app.submission_ctx', 'submission_agent', true);

  update public.product_submissions set status = 'withdrawn'
  where id = v_before.id
  returning * into v_after;

  insert into public.product_submission_events
    (submission_id, revision, from_status, to_status, reason, actor_user_id, actor_role)
  values (v_after.id, v_after.revision, v_before.status, 'withdrawn', v_reason, v_uid, 'agent');

  perform set_config('app.submission_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, 'agent', 'submission.withdraw', 'product_submissions', v_after.id,
          app.submission_audit_state(v_before), app.submission_audit_state(v_after), v_reason);

  return app.submission_json(v_after, true)
         || jsonb_build_object('images', app.submission_images_json(v_after.id));
end;
$fn$;

-- ============================================================================
-- 4. 代理店: 自分の申請一覧・詳細 (STABLE)
-- ----------------------------------------------------------------------------
-- 承認済みの申請は、作成された商品の公開状態 (自分が持ち込んだ商品) だけを返す。
-- 審査した super_admin のユーザー ID は返さない。
-- ============================================================================

create or replace function public.treemerce_my_submissions()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_self uuid := app.current_agent_id();
begin
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店アカウントが必要です' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id',                   s.id,
             'submission_no',        s.submission_no,
             'status',               s.status,
             'revision',             s.revision,
             'name',                 s.name,
             'category',             s.category,
             'desired_price',        s.desired_price,
             'submitted_at',         s.submitted_at,
             'reviewed_at',          s.reviewed_at,
             'review_reason',        case when s.status in ('returned', 'rejected') then s.review_reason end,
             'image_count',          (select count(*) from public.product_submission_images i
                                      where i.submission_id = s.id),
             'product_is_published', (select p.is_published from public.products p
                                      where p.id = s.approved_product_id),
             'updated_at',           s.updated_at)
           order by s.updated_at desc)
    from public.product_submissions s
    where s.agent_id = v_self
  ), '[]'::jsonb);
end;
$fn$;

create or replace function public.treemerce_my_submission(p_submission_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_self uuid := app.current_agent_id();
  v_row  public.product_submissions%rowtype;
begin
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店アカウントが必要です' using errcode = '42501';
  end if;

  select * into v_row from public.product_submissions
  where id = p_submission_id and agent_id = v_self;
  if not found then
    raise exception 'TREEMERCE_SUBMISSION_NOT_FOUND: 申請が見つかりません' using errcode = '22023';
  end if;

  return app.submission_json(v_row, true)
         || jsonb_build_object(
              'editable',             v_row.status in ('draft', 'returned'),
              'images',               app.submission_images_json(v_row.id),
              'events',               app.submission_events_json(v_row.id, false),
              'product_is_published', (select p.is_published from public.products p
                                       where p.id = v_row.approved_product_id));
end;
$fn$;

-- ============================================================================
-- 5. 代理店: 画像の枠の確保・削除
-- ----------------------------------------------------------------------------
-- 確保した storage_path にだけ Storage へのアップロードが許可される (0017 のポリシー)。
-- アップロードに失敗した場合は、画面側で treemerce_remove_submission_image を呼んで枠を戻す。
-- 削除は行を消してから、返した storage_path の実体を画面側で Storage から消す
-- (行が無くなった本人フォルダのファイルは本人が削除できる)。
-- ============================================================================

create or replace function public.treemerce_reserve_submission_image(
  p_submission_id uuid,
  p_content_type  text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid   uuid := auth.uid();
  v_sub   public.product_submissions%rowtype;
  v_ext   text;
  v_slot  integer;
  v_image public.product_submission_images%rowtype;
begin
  v_sub := app.lock_my_submission(p_submission_id);
  if v_sub.status not in ('draft', 'returned') then
    raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 申請中・確定済みの申請には画像を追加できません'
      using errcode = '22023';
  end if;

  v_ext := case p_content_type
             when 'image/jpeg' then 'jpg'
             when 'image/png'  then 'png'
             when 'image/webp' then 'webp'
           end;
  if v_ext is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 画像は JPEG・PNG・WebP のみ登録できます' using errcode = '22023';
  end if;

  select min(g) into v_slot
  from generate_series(0, 4) g
  where not exists (select 1 from public.product_submission_images i
                    where i.submission_id = v_sub.id and i.sort_order = g);
  if v_slot is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 画像は 1 件の申請につき 5 枚までです' using errcode = '22023';
  end if;

  perform set_config('app.submission_ctx', 'submission_agent', true);

  insert into public.product_submission_images (submission_id, storage_path, content_type, sort_order)
  values (v_sub.id, v_sub.agent_id || '/' || v_sub.id || '/' || gen_random_uuid() || '.' || v_ext,
          p_content_type, v_slot)
  returning * into v_image;

  perform set_config('app.submission_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, 'agent', 'submission.image_add', 'product_submissions', v_sub.id, null,
          jsonb_build_object('submission_no', v_sub.submission_no, 'image_id', v_image.id,
                             'sort_order', v_image.sort_order),
          null);

  return jsonb_build_object(
    'image_id',     v_image.id,
    'storage_path', v_image.storage_path,
    'content_type', v_image.content_type,
    'sort_order',   v_image.sort_order);
end;
$fn$;

create or replace function public.treemerce_remove_submission_image(p_image_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid   uuid := auth.uid();
  v_self  uuid := app.current_agent_id();
  v_image public.product_submission_images%rowtype;
  v_sub   public.product_submissions%rowtype;
begin
  if v_self is null then
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中の代理店アカウントが必要です' using errcode = '42501';
  end if;

  select i.* into v_image
  from public.product_submission_images i
  join public.product_submissions s on s.id = i.submission_id
  where i.id = p_image_id and s.agent_id = v_self;
  if not found then
    raise exception 'TREEMERCE_SUBMISSION_NOT_FOUND: 画像が見つかりません' using errcode = '22023';
  end if;

  v_sub := app.lock_my_submission(v_image.submission_id);
  if v_sub.status not in ('draft', 'returned') then
    raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 申請中・確定済みの申請の画像は削除できません'
      using errcode = '22023';
  end if;

  perform set_config('app.submission_ctx', 'submission_agent', true);
  delete from public.product_submission_images where id = v_image.id;
  perform set_config('app.submission_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, 'agent', 'submission.image_remove', 'product_submissions', v_sub.id,
          jsonb_build_object('submission_no', v_sub.submission_no, 'image_id', v_image.id,
                             'sort_order', v_image.sort_order),
          null, null);

  return jsonb_build_object('storage_path', v_image.storage_path);
end;
$fn$;

-- ============================================================================
-- 6. super_admin: 申請一覧・詳細 (STABLE)
-- ============================================================================

create or replace function public.treemerce_admin_list_submissions(
  p_status public.submission_status default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 持込み申請は super_admin のみ参照できます'
      using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id',                 s.id,
             'submission_no',      s.submission_no,
             'status',             s.status,
             'revision',           s.revision,
             'name',               s.name,
             'category',           s.category,
             'desired_price',      s.desired_price,
             'producer_name',      s.producer_name,
             'agent_id',           a.id,
             'agent_public_id',    a.public_id,
             'agent_display_name', a.display_name,
             'image_count',        (select count(*) from public.product_submission_images i
                                    where i.submission_id = s.id),
             'submitted_at',       s.submitted_at,
             'reviewed_at',        s.reviewed_at,
             'approved_product_id', s.approved_product_id,
             'updated_at',         s.updated_at)
           order by (s.status = 'submitted') desc, s.submitted_at nulls last, s.updated_at desc)
    from public.product_submissions s
    join public.agents a on a.id = s.agent_id
    where (p_status is null and s.status <> 'draft') or s.status = p_status
  ), '[]'::jsonb);
end;
$fn$;

create or replace function public.treemerce_admin_get_submission(p_submission_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_row   public.product_submissions%rowtype;
  v_agent public.agents%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 持込み申請は super_admin のみ参照できます'
      using errcode = '42501';
  end if;

  select * into v_row from public.product_submissions where id = p_submission_id;
  if not found then
    raise exception 'TREEMERCE_SUBMISSION_NOT_FOUND: 申請が見つかりません' using errcode = '22023';
  end if;
  select * into v_agent from public.agents where id = v_row.agent_id;

  return app.submission_json(v_row, true)
         || jsonb_build_object(
              'agent', jsonb_build_object(
                'id',           v_agent.id,
                'public_id',    v_agent.public_id,
                'display_name', v_agent.display_name,
                'status',       v_agent.status),
              'images',               app.submission_images_json(v_row.id),
              'events',               app.submission_events_json(v_row.id, true),
              'approved_product_id',  v_row.approved_product_id,
              'approved_producer_id', v_row.approved_producer_id,
              'product_is_published', (select p.is_published from public.products p
                                       where p.id = v_row.approved_product_id));
end;
$fn$;

-- ============================================================================
-- 7. super_admin: 差し戻し・却下 (理由必須)
-- ============================================================================

create or replace function app.review_submission(
  p_submission_id uuid,
  p_to            public.submission_status,
  p_reason        text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid    uuid := auth.uid();
  v_before public.product_submissions%rowtype;
  v_after  public.product_submissions%rowtype;
  v_reason text;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 持込み申請の審査は super_admin のみ実行できます'
      using errcode = '42501';
  end if;
  if p_to not in ('returned', 'rejected') then
    raise exception 'TREEMERCE_INVALID_TRANSITION: この操作では % にできません', p_to using errcode = '22023';
  end if;

  v_reason := app.submission_text(p_reason, 1000, '理由');
  if v_reason is null then
    raise exception 'TREEMERCE_REASON_REQUIRED: 差し戻し・却下の理由は必須です' using errcode = '22023';
  end if;

  select * into v_before from public.product_submissions where id = p_submission_id for update;
  if not found then
    raise exception 'TREEMERCE_SUBMISSION_NOT_FOUND: 申請が見つかりません' using errcode = '22023';
  end if;
  if v_before.status <> 'submitted' then
    raise exception 'TREEMERCE_INVALID_TRANSITION: 申請中の申請のみ審査できます (現在: %)', v_before.status
      using errcode = '22023';
  end if;

  perform set_config('app.submission_ctx', 'submission_review', true);

  update public.product_submissions
  set status        = p_to,
      reviewed_by   = v_uid,
      reviewed_at   = clock_timestamp(),
      review_reason = v_reason
  where id = v_before.id
  returning * into v_after;

  insert into public.product_submission_events
    (submission_id, revision, from_status, to_status, reason, actor_user_id, actor_role)
  values (v_after.id, v_after.revision, 'submitted', p_to, v_reason, v_uid, 'super_admin');

  perform set_config('app.submission_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, coalesce(app.admin_role(), 'super_admin'),
          case p_to when 'returned' then 'submission.return' else 'submission.reject' end,
          'product_submissions', v_after.id,
          app.submission_audit_state(v_before), app.submission_audit_state(v_after), v_reason);

  return app.submission_json(v_after, true);
end;
$fn$;

create or replace function public.treemerce_admin_return_submission(p_submission_id uuid, p_reason text)
returns jsonb
language sql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
  select app.review_submission(p_submission_id, 'returned', p_reason);
$fn$;

create or replace function public.treemerce_admin_reject_submission(p_submission_id uuid, p_reason text)
returns jsonb
language sql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
  select app.review_submission(p_submission_id, 'rejected', p_reason);
$fn$;

-- ============================================================================
-- 8. super_admin: 承認
-- ----------------------------------------------------------------------------
--   p_producer_id      : NULL → 申請の生産者情報から生産者を新規作成 (連絡先は super_admin 専用列へ)
--                        指定 → 既存の生産者を使う (有効かつ仮の生産者でないこと)
--   p_product_name     : NULL → 申請の商品名
--   p_price            : NULL → 希望販売価格 (公開前に super_admin が確定する前提の仮の値)
--   p_category         : NULL → 申請のカテゴリ
--   p_reason           : 任意 (監査ログ・履歴に残る)
-- 商品は在庫 0・非公開で作成し、持込み元 (product_sources) を記録する。
-- ============================================================================

create or replace function public.treemerce_admin_approve_submission(
  p_submission_id uuid,
  p_producer_id   uuid                    default null,
  p_product_name  text                    default null,
  p_price         numeric                 default null,
  p_category      public.product_category default null,
  p_reason        text                    default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid      uuid := auth.uid();
  v_role     text := coalesce(app.admin_role(), 'super_admin');
  v_before   public.product_submissions%rowtype;
  v_after    public.product_submissions%rowtype;
  v_producer public.producers%rowtype;
  v_product  public.products%rowtype;
  v_created  boolean := false;
  v_name     text;
  v_price    numeric;
  v_reason   text;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 持込み申請の承認は super_admin のみ実行できます'
      using errcode = '42501';
  end if;

  v_reason := app.submission_text(p_reason, 1000, '理由');
  v_name   := app.submission_text(p_product_name, 100, '商品名');

  select * into v_before from public.product_submissions where id = p_submission_id for update;
  if not found then
    raise exception 'TREEMERCE_SUBMISSION_NOT_FOUND: 申請が見つかりません' using errcode = '22023';
  end if;
  if v_before.status <> 'submitted' then
    raise exception 'TREEMERCE_INVALID_TRANSITION: 申請中の申請のみ承認できます (現在: %)', v_before.status
      using errcode = '22023';
  end if;

  v_name  := coalesce(v_name, v_before.name);
  v_price := coalesce(p_price, v_before.desired_price);
  if v_price is null or v_price < 0 or v_price >= 100000000 then
    raise exception 'TREEMERCE_INVALID_INPUT: 価格は 0 円以上 1 億円未満で指定してください' using errcode = '22023';
  end if;

  -- 生産者の決定
  if p_producer_id is null then
    perform set_config('app.commerce_ctx', 'producer', true);

    insert into public.producers
      (name, origin, ship_from_prefecture, ship_lead_time,
       contact_name, contact_phone, contact_email, note, is_active, created_by)
    values
      (v_before.producer_name, v_before.producer_origin, v_before.producer_ship_from_prefecture,
       v_before.producer_ship_lead_time,
       v_before.producer_contact_name, v_before.producer_contact_phone, v_before.producer_contact_email,
       '持込み申請 ' || v_before.submission_no || ' から作成', true, v_uid)
    returning * into v_producer;

    perform set_config('app.commerce_ctx', '', true);
    v_created := true;

    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (v_uid, v_role, 'producer.create', 'producers', v_producer.id,
            null, app.producer_audit_state(v_producer),
            '持込み申請 ' || v_before.submission_no || ' の承認');
  else
    select * into v_producer from public.producers where id = p_producer_id;
    if not found then
      raise exception 'TREEMERCE_PRODUCER_NOT_FOUND: 生産者が見つかりません' using errcode = '22023';
    end if;
    if v_producer.is_placeholder then
      raise exception 'TREEMERCE_PRODUCER_PLACEHOLDER: 仮の生産者「未設定（運営）」は選べません'
        using errcode = '22023';
    end if;
    if not v_producer.is_active then
      raise exception 'TREEMERCE_PRODUCER_INACTIVE: 無効な生産者は選べません' using errcode = '22023';
    end if;
  end if;

  -- 商品 (在庫 0・非公開の下書き)
  insert into public.products
    (name, description, category, price, stock, is_published, created_by,
     producer_id, content_volume, ingredients, best_before_note)
  values
    (v_name, v_before.description, coalesce(p_category, v_before.category), v_price, 0, false, v_uid,
     v_producer.id, v_before.content_volume, v_before.ingredients, v_before.best_before_note)
  returning * into v_product;

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, v_role, 'product.create', 'products', v_product.id, null, to_jsonb(v_product),
          '持込み申請 ' || v_before.submission_no || ' の承認');

  -- 申請を承認し、持込み元を記録する
  perform set_config('app.submission_ctx', 'submission_review', true);

  update public.product_submissions
  set status               = 'approved',
      reviewed_by          = v_uid,
      reviewed_at          = clock_timestamp(),
      review_reason        = v_reason,
      approved_product_id  = v_product.id,
      approved_producer_id = v_producer.id
  where id = v_before.id
  returning * into v_after;

  insert into public.product_sources (product_id, sourced_by_agent_id, submission_id, created_by)
  values (v_product.id, v_after.agent_id, v_after.id, v_uid);

  insert into public.product_submission_events
    (submission_id, revision, from_status, to_status, reason, actor_user_id, actor_role)
  values (v_after.id, v_after.revision, 'submitted', 'approved', v_reason, v_uid, 'super_admin');

  perform set_config('app.submission_ctx', '', true);

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (v_uid, v_role, 'submission.approve', 'product_submissions', v_after.id,
          app.submission_audit_state(v_before),
          app.submission_audit_state(v_after) || jsonb_build_object(
            'product_id',       v_product.id,
            'producer_id',      v_producer.id,
            'producer_created', v_created),
          v_reason);

  return app.submission_json(v_after, true) || jsonb_build_object(
    'product_id',       v_product.id,
    'producer_id',      v_producer.id,
    'producer_created', v_created);
end;
$fn$;

-- ============================================================================
-- 9. GRANT
-- ============================================================================

revoke all on function app.submission_text(text, integer, text)            from public, anon, authenticated;
revoke all on function app.submission_json(public.product_submissions, boolean) from public, anon, authenticated;
revoke all on function app.submission_audit_state(public.product_submissions) from public, anon, authenticated;
revoke all on function app.submission_changed_fields(public.product_submissions, public.product_submissions)
  from public, anon, authenticated;
revoke all on function app.submission_images_json(uuid)                    from public, anon, authenticated;
revoke all on function app.submission_events_json(uuid, boolean)           from public, anon, authenticated;
revoke all on function app.lock_my_submission(uuid)                        from public, anon, authenticated;
revoke all on function app.review_submission(uuid, public.submission_status, text)
  from public, anon, authenticated;

revoke all on function public.treemerce_save_my_submission(
  uuid, text, public.product_category, text, numeric, numeric, text, text, text,
  text, text, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.treemerce_submit_my_submission(uuid)            from public, anon, authenticated;
revoke all on function public.treemerce_withdraw_my_submission(uuid, text)    from public, anon, authenticated;
revoke all on function public.treemerce_my_submissions()                      from public, anon, authenticated;
revoke all on function public.treemerce_my_submission(uuid)                   from public, anon, authenticated;
revoke all on function public.treemerce_reserve_submission_image(uuid, text)  from public, anon, authenticated;
revoke all on function public.treemerce_remove_submission_image(uuid)         from public, anon, authenticated;
revoke all on function public.treemerce_admin_list_submissions(public.submission_status)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_get_submission(uuid)            from public, anon, authenticated;
revoke all on function public.treemerce_admin_return_submission(uuid, text)   from public, anon, authenticated;
revoke all on function public.treemerce_admin_reject_submission(uuid, text)   from public, anon, authenticated;
revoke all on function public.treemerce_admin_approve_submission(
  uuid, uuid, text, numeric, public.product_category, text) from public, anon, authenticated;

grant execute on function public.treemerce_save_my_submission(
  uuid, text, public.product_category, text, numeric, numeric, text, text, text,
  text, text, text, text, text, text, text) to authenticated;
grant execute on function public.treemerce_submit_my_submission(uuid)            to authenticated;
grant execute on function public.treemerce_withdraw_my_submission(uuid, text)    to authenticated;
grant execute on function public.treemerce_my_submissions()                      to authenticated;
grant execute on function public.treemerce_my_submission(uuid)                   to authenticated;
grant execute on function public.treemerce_reserve_submission_image(uuid, text)  to authenticated;
grant execute on function public.treemerce_remove_submission_image(uuid)         to authenticated;
grant execute on function public.treemerce_admin_list_submissions(public.submission_status) to authenticated;
grant execute on function public.treemerce_admin_get_submission(uuid)            to authenticated;
grant execute on function public.treemerce_admin_return_submission(uuid, text)   to authenticated;
grant execute on function public.treemerce_admin_reject_submission(uuid, text)   to authenticated;
grant execute on function public.treemerce_admin_approve_submission(
  uuid, uuid, text, numeric, public.product_category, text) to authenticated;

commit;
