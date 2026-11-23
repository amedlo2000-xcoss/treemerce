-- ============================================================================
-- TREEMERCE : 0035_treemerce_observer_wording_rest.sql
-- DB が返す表示用の文言に残っていた「代理店」を「オブザーバー」に変更 (0032 の続き)
-- ----------------------------------------------------------------------------
-- 変更するのは表示される文言だけ。エラーコード (TREEMERCE_*)・引数・処理内容・権限・
-- 戻り値の型は変えない。各関数は最新の定義をそのまま写し、次の文言だけを差し替えている。
--   ・treemerce_save_my_submission
--       「稼働中の代理店アカウントが必要です」
--     → 「稼働中のオブザーバーアカウントが必要です」
--   ・treemerce_admin_save_proxy_submission
--       「申請の代理店と指定の代理店が一致しません」
--     → 「申請のオブザーバーと指定のオブザーバーが一致しません」
--
-- 写した元の定義:
--   treemerce_save_my_submission             0034_treemerce_twa_wording.sql:492
--   treemerce_admin_save_proxy_submission    0034_treemerce_twa_wording.sql:645
--
-- create or replace で同じ引数のまま置き換えるため、既存の GRANT / REVOKE・コメントはそのまま残る。
-- テーブル名・列名・関数名・エラーコードの agent / AGENT は変更しない。
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- public.treemerce_save_my_submission  (最新の定義: 0034_treemerce_twa_wording.sql)
-- ----------------------------------------------------------------------------

create or replace function public.treemerce_save_my_submission(
  p_submission_id                 uuid                    default null,
  p_name                          text                    default null,
  p_category                      public.product_category default null,
  p_description                   text                    default null,
  p_desired_price                 numeric                 default null,
  p_expected_wholesale_price      numeric                 default null,
  p_content_volume                text                    default null,
  p_ingredients                   text                    default null,
  p_best_before_note              text                    default null,
  p_producer_name                 text                    default null,
  p_producer_origin               text                    default null,
  p_producer_ship_from_prefecture text                    default null,
  p_producer_ship_lead_time       text                    default null,
  p_producer_contact_name         text                    default null,
  p_producer_contact_phone        text                    default null,
  p_producer_contact_email        text                    default null,
  p_category_id                   uuid                    default null
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
  v_cat    uuid := coalesce(p_category_id, app.category_id_for_legacy(p_category));
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
    raise exception 'TREEMERCE_FORBIDDEN: 稼働中のオブザーバーアカウントが必要です' using errcode = '42501';
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
    raise exception 'TREEMERCE_INVALID_INPUT: 希望販売価格は 0 TWA 以上 100,000,000 TWA 未満で入力してください'
      using errcode = '22023';
  end if;
  if p_expected_wholesale_price is not null
     and (p_expected_wholesale_price < 0 or p_expected_wholesale_price >= 100000000) then
    raise exception 'TREEMERCE_INVALID_INPUT: 想定卸値は 0 TWA 以上 100,000,000 TWA 未満で入力してください'
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
    perform app.require_assignable_category(v_cat, null);

    perform set_config('app.submission_ctx', 'submission_agent', true);

    insert into public.product_submissions
      (agent_id, name, category_id, description, desired_price, expected_wholesale_price,
       content_volume, ingredients, best_before_note,
       producer_name, producer_origin, producer_ship_from_prefecture, producer_ship_lead_time,
       producer_contact_name, producer_contact_phone, producer_contact_email, created_by)
    values
      (v_self, v_name, v_cat, v_desc, p_desired_price, p_expected_wholesale_price,
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
    perform app.require_assignable_category(v_cat, v_before.category_id);

    perform set_config('app.submission_ctx', 'submission_agent', true);

    update public.product_submissions
    set name                          = v_name,
        category_id                   = v_cat,
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

-- ----------------------------------------------------------------------------
-- public.treemerce_admin_save_proxy_submission  (最新の定義: 0034_treemerce_twa_wording.sql)
-- ----------------------------------------------------------------------------

create or replace function public.treemerce_admin_save_proxy_submission(
  p_agent_id                      uuid                    default null,
  p_submission_id                 uuid                    default null,
  p_name                          text                    default null,
  p_category                      public.product_category default null,
  p_description                   text                    default null,
  p_desired_price                 numeric                 default null,
  p_expected_wholesale_price      numeric                 default null,
  p_content_volume                text                    default null,
  p_ingredients                   text                    default null,
  p_best_before_note              text                    default null,
  p_producer_name                 text                    default null,
  p_producer_origin               text                    default null,
  p_producer_ship_from_prefecture text                    default null,
  p_producer_ship_lead_time       text                    default null,
  p_producer_contact_name         text                    default null,
  p_producer_contact_phone        text                    default null,
  p_producer_contact_email        text                    default null,
  p_reason                        text                    default null,
  p_category_id                   uuid                    default null
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
  v_before public.product_submissions%rowtype;
  v_after  public.product_submissions%rowtype;
  v_cat    uuid := coalesce(p_category_id, app.category_id_for_legacy(p_category));
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
  v_reason text;
begin
  if not app.is_super_admin() then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 申請の代行は super_admin のみ実行できます'
      using errcode = '42501';
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
  v_reason := app.submission_text(p_reason, 500, '理由');

  if v_name is null then
    raise exception 'TREEMERCE_INVALID_INPUT: 商品名は必須です' using errcode = '22023';
  end if;
  if p_desired_price is not null and (p_desired_price < 0 or p_desired_price >= 100000000) then
    raise exception 'TREEMERCE_INVALID_INPUT: 希望販売価格は 0 TWA 以上 100,000,000 TWA 未満で入力してください'
      using errcode = '22023';
  end if;
  if p_expected_wholesale_price is not null
     and (p_expected_wholesale_price < 0 or p_expected_wholesale_price >= 100000000) then
    raise exception 'TREEMERCE_INVALID_INPUT: 想定卸値は 0 TWA 以上 100,000,000 TWA 未満で入力してください'
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
    if p_agent_id is null then
      raise exception 'TREEMERCE_INVALID_INPUT: 代行するオブザーバーを指定してください' using errcode = '22023';
    end if;
    if v_reason is null then
      raise exception 'TREEMERCE_REASON_REQUIRED: 代行で作成する理由 (ヒアリングの日付・経緯など) は必須です'
        using errcode = '22023';
    end if;
    perform app.require_proxy_target_agent(p_agent_id);
    perform app.require_assignable_category(v_cat, null);

    perform set_config('app.submission_ctx', 'submission_admin_proxy', true);

    insert into public.product_submissions
      (agent_id, created_via, name, category_id, description, desired_price, expected_wholesale_price,
       content_volume, ingredients, best_before_note,
       producer_name, producer_origin, producer_ship_from_prefecture, producer_ship_lead_time,
       producer_contact_name, producer_contact_phone, producer_contact_email, created_by)
    values
      (p_agent_id, 'admin_proxy', v_name, v_cat, v_desc, p_desired_price,
       p_expected_wholesale_price, v_volume, v_ingr, v_best,
       v_p_name, v_origin, v_pref, v_lead,
       v_c_name, v_c_tel, v_c_mail, v_uid)
    returning * into v_after;

    perform set_config('app.submission_ctx', '', true);

    insert into public.admin_audit_logs
      (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
    values (v_uid, v_role, 'submission.proxy_create', 'product_submissions', v_after.id,
            null, app.submission_audit_state(v_after), v_reason);
  else
    v_before := app.lock_proxy_submission(p_submission_id);
    if p_agent_id is not null and p_agent_id is distinct from v_before.agent_id then
      raise exception 'TREEMERCE_SUBMISSION_AGENT_MISMATCH: 申請のオブザーバーと指定のオブザーバーが一致しません'
        using errcode = '22023';
    end if;
    if v_before.status not in ('draft', 'returned') then
      raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 申請中・確定済みの申請は編集できません'
        using errcode = '22023';
    end if;
    perform app.require_proxy_target_agent(v_before.agent_id);
    perform app.require_assignable_category(v_cat, v_before.category_id);

    perform set_config('app.submission_ctx', 'submission_admin_proxy', true);

    update public.product_submissions
    set name                          = v_name,
        category_id                   = v_cat,
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
      values (v_uid, v_role, 'submission.proxy_update', 'product_submissions', v_after.id,
              app.submission_audit_state(v_before),
              app.submission_audit_state(v_after)
                || jsonb_build_object('changed_fields', app.submission_changed_fields(v_before, v_after)),
              v_reason);
    end if;
  end if;

  return app.submission_json(v_after, true)
         || jsonb_build_object('images', app.submission_images_json(v_after.id));
end;
$fn$;

commit;
