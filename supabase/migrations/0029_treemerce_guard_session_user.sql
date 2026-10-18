-- ============================================================================
-- TREEMERCE : 0029_treemerce_guard_session_user.sql
-- 書込みガードの「DB管理者の直接操作」判定を current_user → session_user に変更
-- ----------------------------------------------------------------------------
-- これまでのガードは「current_user = 'postgres' かつコンテキスト未設定」を
-- DB管理者 (マイグレーション / SQL Editor / 障害復旧) の直接操作として通していた。
-- しかし SECURITY DEFINER 関数 (postgres 所有) の中では current_user が postgres に
-- なるため、コンテキストを張らない関数からの書込みまで通ってしまう。
-- そこで session_user で判定する。PostgREST 経由の session_user は authenticator、
-- Supabase Auth は supabase_auth_admin なので、DB管理者の例外には当たらない。
--   ・SQL Editor / CLI / pg_cron (cron.job.username) の session_user は postgres (確認済み)
--   ・既存の SECURITY DEFINER 関数は全て書込み前にコンテキストを張っている (確認済み)。
--     そのため関数側の修正は不要。
--
-- アカウント削除 (auth.users の DELETE) では、外部キーの ON DELETE SET NULL が
-- 参照列を NULL にする UPDATE を発生させる。これまでは RI 処理の current_user が
-- テーブル所有者 (postgres) のため通っていたが、session_user 判定では拒否される。
-- 今まで削除できていた次の2列に限り、「その列だけが NULL になり、他の列は変わらない
-- UPDATE」を通す狭い例外を加え、従来の挙動を保つ。
--   ・producers.created_by       (app.guard_producers_write)
--   ・agent_profiles.updated_by  (app.guard_agent_profiles_write)
-- 他の参照列 (追記専用の履歴・変更不可の列) は従来どおり削除時も拒否される (挙動は変わらない)。
--
-- 各関数は、それぞれの最新の定義をそのまま写し、判定と上記の例外だけを変えている。
-- 0027 / 0028 には依存しない (0027 の新しいガードは最初から session_user 判定)。
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- app.guard_customer_assignment_write  (最新の定義: 0002_treemerce_security.sql)
-- ----------------------------------------------------------------------------

create or replace function app.guard_customer_assignment_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := app.assignment_ctx();
begin
  -- DB管理者(postgres)による直接操作 = マイグレーション/障害復旧の経路として明示的に許可。
  -- superuser はトリガ自体を無効化できるため、これは防御の弱体化ではない。
  if session_user = 'postgres' and v_ctx = '' then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    if v_ctx not in ('register', 'transfer') then
      raise exception
        'TREEMERCE_ASSIGNMENT_WRITE_DENIED: customer_assignments への直接INSERTは禁止です'
        using errcode = '42501';
    end if;
    return new;
  end if;

  -- 絶対原則4: 担当の変更・解除・移管は ADMIN 専用関数の中でしか起こしてはならない。
  if v_ctx <> 'transfer' then
    raise exception
      'TREEMERCE_ASSIGNMENT_IMMUTABLE: 担当代理店の変更/解除/移管は管理者専用処理でのみ可能です'
      using errcode = '42501';
  end if;

  return coalesce(new, old);
end;
$fn$;

-- ----------------------------------------------------------------------------
-- app.guard_history_append_only  (最新の定義: 0002_treemerce_security.sql)
-- ----------------------------------------------------------------------------

create or replace function app.guard_history_append_only()
returns trigger
language plpgsql
as $fn$
begin
  if tg_op = 'INSERT' then
    if session_user = 'postgres' and app.assignment_ctx() = '' then
      return new;
    end if;
    if app.assignment_ctx() not in ('register', 'transfer') then
      raise exception
        'TREEMERCE_HISTORY_WRITE_DENIED: customer_assignment_history への直接INSERTは禁止です'
        using errcode = '42501';
    end if;
    return new;
  end if;

  raise exception 'TREEMERCE_HISTORY_APPEND_ONLY: 担当変更履歴は更新・削除できません'
    using errcode = '42501';
end;
$fn$;

-- ----------------------------------------------------------------------------
-- app.guard_orders_write  (最新の定義: 0013_treemerce_commerce_hardening.sql)
-- ----------------------------------------------------------------------------

create or replace function app.guard_orders_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.commerce_ctx', true), '');
begin
  if tg_op = 'UPDATE' then
    -- 原則4: 帰属・顧客・金額・注文番号・支払期限は誰にも変更させない (postgres 直接操作も含む)
    if new.agent_id is distinct from old.agent_id
       or new.customer_id is distinct from old.customer_id
       or new.referral_agent_id is distinct from old.referral_agent_id
       or new.order_no is distinct from old.order_no
       or new.subtotal is distinct from old.subtotal
       or new.shipping_fee is distinct from old.shipping_fee
       or new.total is distinct from old.total
       or new.ordered_at is distinct from old.ordered_at
       or new.payment_due_date is distinct from old.payment_due_date then
      raise exception
        'TREEMERCE_ORDER_IMMUTABLE: 注文の帰属代理店・顧客・金額・注文番号・支払期限は変更できません'
        using errcode = '42501';
    end if;
  end if;

  if session_user = 'postgres' and v_ctx = '' then
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

-- ----------------------------------------------------------------------------
-- app.guard_order_items_write  (最新の定義: 0010_treemerce_commerce_schema.sql)
-- ----------------------------------------------------------------------------

create or replace function app.guard_order_items_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.commerce_ctx', true), '');
begin
  if tg_op = 'INSERT' and (v_ctx = 'place_order' or (session_user = 'postgres' and v_ctx = '')) then
    return new;
  end if;
  raise exception 'TREEMERCE_ORDER_ITEMS_IMMUTABLE: 注文明細は注文受付時にのみ作成でき、変更・削除できません'
    using errcode = '42501';
end;
$fn$;

-- ----------------------------------------------------------------------------
-- app.guard_order_history_append_only  (最新の定義: 0010_treemerce_commerce_schema.sql)
-- ----------------------------------------------------------------------------

create or replace function app.guard_order_history_append_only()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.commerce_ctx', true), '');
begin
  if tg_op = 'INSERT'
     and (v_ctx in ('place_order', 'order_status') or (session_user = 'postgres' and v_ctx = '')) then
    return new;
  end if;
  raise exception 'TREEMERCE_ORDER_HISTORY_APPEND_ONLY: 注文ステータス履歴は追記専用です'
    using errcode = '42501';
end;
$fn$;

-- ----------------------------------------------------------------------------
-- app.guard_producers_write  (最新の定義: 0014_treemerce_producers_schema.sql)
-- ----------------------------------------------------------------------------

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

  -- アカウント削除 (auth.users の ON DELETE SET NULL) で created_by だけが NULL になる
  -- UPDATE は通す。他の列が1つでも変わる場合や、NULL 以外の値への変更は対象外。
  -- (このトリガは producers_touch_updated_at より先に動くため updated_at もまだ変わっていない)
  if tg_op = 'UPDATE'
     and old.created_by is not null and new.created_by is null
     and (to_jsonb(new) - 'created_by') = (to_jsonb(old) - 'created_by') then
    return new;
  end if;

  if session_user = 'postgres' and v_ctx = '' then
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

-- ----------------------------------------------------------------------------
-- app.guard_order_shipments_write  (最新の定義: 0014_treemerce_producers_schema.sql)
-- ----------------------------------------------------------------------------

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

  if session_user = 'postgres' and v_ctx = '' then
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

-- ----------------------------------------------------------------------------
-- app.guard_agent_profiles_write  (最新の定義: 0020_treemerce_admin_agent_profile.sql)
-- ----------------------------------------------------------------------------

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

  -- アカウント削除 (auth.users の ON DELETE SET NULL) で updated_by だけが NULL になる
  -- UPDATE は通す。他の列 (updated_by_role を含む) が1つでも変わる場合や、
  -- NULL 以外の値への変更は対象外。
  -- (このトリガは agent_profiles_touch_updated_at より先に動くため updated_at もまだ変わっていない)
  if tg_op = 'UPDATE'
     and old.updated_by is not null and new.updated_by is null
     and (to_jsonb(new) - 'updated_by') = (to_jsonb(old) - 'updated_by') then
    return new;
  end if;

  if session_user = 'postgres' and v_ctx = '' then
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

-- ----------------------------------------------------------------------------
-- app.guard_product_submissions_write  (最新の定義: 0021_treemerce_admin_proxy_submissions.sql)
-- ----------------------------------------------------------------------------

create or replace function app.guard_product_submissions_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.submission_ctx', true), '');
  v_db  boolean := (session_user = 'postgres' and v_ctx = '');
begin
  -- 申請は削除しない (取り下げで扱う)。postgres でも不可。
  if tg_op = 'DELETE' then
    raise exception 'TREEMERCE_SUBMISSION_DELETE_DENIED: 申請は削除できません (取り下げで扱う)'
      using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'draft' or new.revision <> 0 or new.submitted_at is not null
       or new.reviewed_by is not null or new.reviewed_at is not null or new.review_reason is not null
       or new.approved_product_id is not null or new.approved_producer_id is not null then
      raise exception 'TREEMERCE_SUBMISSION_INVALID_STATE: 申請は下書きとしてのみ作成できます'
        using errcode = '42501';
    end if;
    if v_db then
      return new;
    end if;
    if v_ctx = 'submission_agent' then
      if new.created_via <> 'agent' then
        raise exception 'TREEMERCE_SUBMISSION_WRITE_DENIED: 本人の作成処理では代行の申請を作れません'
          using errcode = '42501';
      end if;
      return new;
    end if;
    if v_ctx = 'submission_admin_proxy' then
      if not app.is_super_admin() then
        raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 申請の代行は super_admin のみ実行できます'
          using errcode = '42501';
      end if;
      if new.created_via <> 'admin_proxy' then
        raise exception 'TREEMERCE_SUBMISSION_WRITE_DENIED: 代行の作成処理では本人の申請を作れません'
          using errcode = '42501';
      end if;
      return new;
    end if;
    raise exception 'TREEMERCE_SUBMISSION_WRITE_DENIED: 申請は本人の作成処理または運営の代行でのみ作成できます'
      using errcode = '42501';
  end if;

  -- ---- UPDATE ----

  -- 誰にも変更させない列 (postgres 直接操作も含む)
  if new.id            is distinct from old.id
     or new.submission_no is distinct from old.submission_no
     or new.agent_id      is distinct from old.agent_id
     or new.created_via   is distinct from old.created_via
     or new.created_by    is distinct from old.created_by
     or new.created_at    is distinct from old.created_at then
    raise exception 'TREEMERCE_SUBMISSION_IMMUTABLE: 申請の番号・代理店・作成経路・作成情報は変更できません'
      using errcode = '42501';
  end if;

  -- 終端 (承認・却下・取り下げ) の申請はどの列も変更できない
  if old.status in ('approved', 'rejected', 'withdrawn') then
    raise exception 'TREEMERCE_SUBMISSION_FINALIZED: この申請は確定済みのため変更できません'
      using errcode = '42501';
  end if;

  -- DB 管理者の直接操作: 状態・審査・承認結果は変えず、内容の修正だけ許可する
  if v_db then
    if new.status          is distinct from old.status
       or new.revision     is distinct from old.revision
       or new.submitted_at is distinct from old.submitted_at
       or new.reviewed_by  is distinct from old.reviewed_by
       or new.reviewed_at  is distinct from old.reviewed_at
       or new.review_reason is distinct from old.review_reason
       or new.approved_product_id  is distinct from old.approved_product_id
       or new.approved_producer_id is distinct from old.approved_producer_id then
      raise exception 'TREEMERCE_SUBMISSION_WRITE_DENIED: 申請の状態は専用の処理でのみ変更できます'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if v_ctx in ('submission_agent', 'submission_admin_proxy') then
    if v_ctx = 'submission_agent' and old.created_via <> 'agent' then
      raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 運営が代行作成した申請は閲覧のみです'
        using errcode = '42501';
    end if;
    if v_ctx = 'submission_admin_proxy' then
      if not app.is_super_admin() then
        raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 申請の代行は super_admin のみ実行できます'
          using errcode = '42501';
      end if;
      if old.created_via <> 'admin_proxy' then
        raise exception 'TREEMERCE_SUBMISSION_NOT_PROXY: 代理店本人が作成した申請は運営が編集できません'
          using errcode = '42501';
      end if;
    end if;
    -- 審査・承認結果の列には触れない
    if new.reviewed_by  is distinct from old.reviewed_by
       or new.reviewed_at  is distinct from old.reviewed_at
       or new.review_reason is distinct from old.review_reason
       or new.approved_product_id  is distinct from old.approved_product_id
       or new.approved_producer_id is distinct from old.approved_producer_id then
      raise exception 'TREEMERCE_SUBMISSION_WRITE_DENIED: 審査結果は変更できません'
        using errcode = '42501';
    end if;
    -- 内容の編集は下書き・差し戻しの間だけ
    if app.submission_content_changed(old, new) and old.status not in ('draft', 'returned') then
      raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 申請中の内容は編集できません'
        using errcode = '42501';
    end if;
    if new.status is distinct from old.status and not (
         (old.status in ('draft', 'returned') and new.status in ('submitted', 'withdrawn'))
    ) then
      raise exception 'TREEMERCE_INVALID_TRANSITION: % から % へは変更できません', old.status, new.status
        using errcode = '22023';
    end if;
    if new.status = old.status and old.status not in ('draft', 'returned') then
      raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 申請中の申請は変更できません'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if v_ctx = 'submission_review' then
    -- super_admin: 内容は変えず、申請中から承認・差し戻し・却下へ進めるだけ
    if app.submission_content_changed(old, new)
       or new.revision     is distinct from old.revision
       or new.submitted_at is distinct from old.submitted_at then
      raise exception 'TREEMERCE_SUBMISSION_WRITE_DENIED: 審査では申請の内容を変更できません'
        using errcode = '42501';
    end if;
    if not (old.status = 'submitted' and new.status in ('approved', 'returned', 'rejected')) then
      raise exception 'TREEMERCE_INVALID_TRANSITION: % から % へは変更できません', old.status, new.status
        using errcode = '22023';
    end if;
    return new;
  end if;

  raise exception
    'TREEMERCE_SUBMISSION_WRITE_DENIED: 申請は専用の処理 (本人の申請 / 運営の代行 / super_admin の審査) でのみ書き込めます'
    using errcode = '42501';
end;
$fn$;

-- ----------------------------------------------------------------------------
-- app.guard_submission_events_append_only  (最新の定義: 0021_treemerce_admin_proxy_submissions.sql)
-- ----------------------------------------------------------------------------

create or replace function app.guard_submission_events_append_only()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx text := coalesce(current_setting('app.submission_ctx', true), '');
begin
  if tg_op = 'INSERT'
     and (v_ctx in ('submission_agent', 'submission_admin_proxy', 'submission_review')
          or (session_user = 'postgres' and v_ctx = '')) then
    return new;
  end if;
  raise exception 'TREEMERCE_SUBMISSION_HISTORY_APPEND_ONLY: 申請の履歴は追記専用です'
    using errcode = '42501';
end;
$fn$;

-- ----------------------------------------------------------------------------
-- app.guard_submission_images_write  (最新の定義: 0021_treemerce_admin_proxy_submissions.sql)
-- ----------------------------------------------------------------------------

create or replace function app.guard_submission_images_write()
returns trigger
language plpgsql
as $fn$
declare
  v_ctx    text := coalesce(current_setting('app.submission_ctx', true), '');
  v_sub    public.product_submissions%rowtype;
  v_count  integer;
begin
  if tg_op = 'UPDATE' and (new.submission_id is distinct from old.submission_id
                           or new.storage_path is distinct from old.storage_path
                           or new.content_type is distinct from old.content_type) then
    raise exception 'TREEMERCE_SUBMISSION_IMAGE_IMMUTABLE: 画像の申請・保存先は変更できません'
      using errcode = '42501';
  end if;

  -- 申請行をロックして枚数の競合を防ぐ
  select * into v_sub from public.product_submissions
  where id = coalesce(new.submission_id, old.submission_id)
  for update;

  if not (session_user = 'postgres' and v_ctx = '') then
    if v_ctx = 'submission_agent' then
      if v_sub.created_via <> 'agent' then
        raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 運営が代行作成した申請の画像は変更できません'
          using errcode = '42501';
      end if;
    elsif v_ctx = 'submission_admin_proxy' then
      if not app.is_super_admin() then
        raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: 申請の代行は super_admin のみ実行できます'
          using errcode = '42501';
      end if;
      if v_sub.created_via <> 'admin_proxy' then
        raise exception 'TREEMERCE_SUBMISSION_NOT_PROXY: 代理店本人が作成した申請の画像は運営が変更できません'
          using errcode = '42501';
      end if;
    else
      raise exception 'TREEMERCE_SUBMISSION_WRITE_DENIED: 申請画像は本人の処理または運営の代行でのみ変更できます'
        using errcode = '42501';
    end if;
    if v_sub.status not in ('draft', 'returned') then
      raise exception 'TREEMERCE_SUBMISSION_NOT_EDITABLE: 申請中・確定済みの申請の画像は変更できません'
        using errcode = '42501';
    end if;
  end if;

  if tg_op = 'INSERT' then
    if split_part(new.storage_path, '/', 1) <> v_sub.agent_id::text
       or split_part(new.storage_path, '/', 2) <> v_sub.id::text then
      raise exception 'TREEMERCE_INVALID_INPUT: 画像の保存先が申請と一致しません' using errcode = '22023';
    end if;
    select count(*) into v_count from public.product_submission_images where submission_id = v_sub.id;
    if v_count >= 5 then
      raise exception 'TREEMERCE_INVALID_INPUT: 画像は 1 件の申請につき 5 枚までです' using errcode = '22023';
    end if;
  end if;

  return coalesce(new, old);
end;
$fn$;

-- ----------------------------------------------------------------------------
-- app.guard_product_categories_write  (最新の定義: 0022_treemerce_product_categories.sql)
-- ----------------------------------------------------------------------------

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

  if session_user = 'postgres' and v_ctx = '' then
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

-- ============================================================================
-- 権限 (create or replace で既存の権限は保たれるが、念のため明示する)
-- ============================================================================

revoke all on function app.guard_customer_assignment_write() from public, anon, authenticated;
revoke all on function app.guard_history_append_only() from public, anon, authenticated;
revoke all on function app.guard_orders_write() from public, anon, authenticated;
revoke all on function app.guard_order_items_write() from public, anon, authenticated;
revoke all on function app.guard_order_history_append_only() from public, anon, authenticated;
revoke all on function app.guard_producers_write() from public, anon, authenticated;
revoke all on function app.guard_order_shipments_write() from public, anon, authenticated;
revoke all on function app.guard_agent_profiles_write() from public, anon, authenticated;
revoke all on function app.guard_product_submissions_write() from public, anon, authenticated;
revoke all on function app.guard_submission_events_append_only() from public, anon, authenticated;
revoke all on function app.guard_submission_images_write() from public, anon, authenticated;
revoke all on function app.guard_product_categories_write() from public, anon, authenticated;

commit;
