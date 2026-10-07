-- ============================================================================
-- TREEMERCE 受け入れテスト  CASE1 - CASE35
-- ----------------------------------------------------------------------------
-- Supabase SQL Editor にそのまま貼り付けて実行する。
-- 全体が 1 トランザクションで、最後に ROLLBACK するため本番データは残らない。
-- 途中で失敗した CASE があれば例外で停止する。全て通れば最後に
-- 「ALL 35 CASES PASSED」が NOTICE として出力される。
--
-- 木構造:
--            R  (root)
--          /   \
--         A     S            A の兄弟枝 = S
--        / \
--       B   D                B の兄弟枝 = D
--       |
--       C
--
-- 顧客:  Y→A  X→B  Z→C  W→D  V→S  U→R
--
-- 状態の受け渡しにはトランザクションローカルな GUC (tm.*) を使う。
-- (一時テーブルはロール切替時に権限問題を起こすため使わない)
-- ============================================================================

begin;

set local client_min_messages to notice;

-- ============================================================================
-- SETUP (postgres として実行)
-- ============================================================================

insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000001',
   'authenticated', 'authenticated', 'tm-test-r@treemerce.test', '', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000002',
   'authenticated', 'authenticated', 'tm-test-a@treemerce.test', '', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000003',
   'authenticated', 'authenticated', 'tm-test-b@treemerce.test', '', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000004',
   'authenticated', 'authenticated', 'tm-test-c@treemerce.test', '', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000005',
   'authenticated', 'authenticated', 'tm-test-d@treemerce.test', '', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000006',
   'authenticated', 'authenticated', 'tm-test-s@treemerce.test', '', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000007',
   'authenticated', 'authenticated', 'tm-test-admin@treemerce.test', '', now(), now(), now());

-- R (ルート) / A (R の傘下) / S (A の兄弟枝) を fixture として直接作成
insert into public.agents (id, auth_user_id, public_id, display_name, email, status, invited_by)
values
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001',
   'TM-TEST-R', 'テスト代理店R', 'tm-test-r@treemerce.test', 'active', null),
  ('10000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000002',
   'TM-TEST-A', 'テスト代理店A', 'tm-test-a@treemerce.test', 'active',
   '10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000006', '00000000-0000-4000-8000-000000000006',
   'TM-TEST-S', 'テスト代理店S', 'tm-test-s@treemerce.test', 'active',
   '10000000-0000-4000-8000-000000000001');

insert into public.admin_roles (auth_user_id, role)
values ('00000000-0000-4000-8000-000000000007', 'super_admin');

-- ============================================================================
-- CASE1 : A の招待URL経由で B を登録 → A→B の登録経路が保存される
-- ============================================================================

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

select set_config('tm.invite_a',
  public.treemerce_create_agent_invitation('for B', null, null) ->> 'code', true);

reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

select set_config('tm.agent_b',
  public.treemerce_register_agent('テスト代理店B', 'tm-test-b@treemerce.test', null,
                                  current_setting('tm.invite_a')) ->> 'agent_id', true);

reset role;
select set_config('request.jwt.claims', '', true);

do $$
declare v_inviter uuid;
begin
  select invited_by into v_inviter
  from public.agents where id = current_setting('tm.agent_b')::uuid;
  if v_inviter is distinct from '10000000-0000-4000-8000-000000000002'::uuid then
    raise exception 'CASE1 FAILED: B.invited_by = % (expected A)', v_inviter;
  end if;
  raise notice 'CASE1 OK: A -> B の登録経路が invited_by に保存された';
end $$;

-- ============================================================================
-- CASE2 : B の招待URL経由で C を登録 → B→C の登録経路が保存される
-- ============================================================================

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

select set_config('tm.invite_b',
  public.treemerce_create_agent_invitation('for C', null, null) ->> 'code', true);

reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000004","role":"authenticated"}', true);
set local role authenticated;

select set_config('tm.agent_c',
  public.treemerce_register_agent('テスト代理店C', 'tm-test-c@treemerce.test', null,
                                  current_setting('tm.invite_b')) ->> 'agent_id', true);

reset role;
select set_config('request.jwt.claims', '', true);

do $$
declare v_inviter uuid;
begin
  select invited_by into v_inviter
  from public.agents where id = current_setting('tm.agent_c')::uuid;
  if v_inviter is distinct from current_setting('tm.agent_b')::uuid then
    raise exception 'CASE2 FAILED: C.invited_by = % (expected B)', v_inviter;
  end if;
  raise notice 'CASE2 OK: B -> C の登録経路が invited_by に保存された';
end $$;

-- D (A の傘下 / B の兄弟枝) を fixture として追加
insert into public.agents (id, auth_user_id, public_id, display_name, email, status, invited_by)
values ('10000000-0000-4000-8000-000000000005', '00000000-0000-4000-8000-000000000005',
        'TM-TEST-D', 'テスト代理店D', 'tm-test-d@treemerce.test', 'active',
        '10000000-0000-4000-8000-000000000002');

-- ============================================================================
-- CASE3 : B 経由で顧客 X を登録 → X の担当が B で保存される
-- ============================================================================

do $$
declare v_b_public text; v_res jsonb; v_x uuid; v_assigned uuid; v_b uuid;
begin
  v_b := current_setting('tm.agent_b')::uuid;
  select public_id into v_b_public from public.agents where id = v_b;

  v_res := public.treemerce_register_customer(
    v_b_public, '山田太郎', 'tm-test-x@treemerce.test', '090-1111-2222',
    'ヤマダタロウ', '40s', 'male', '東京都', 'individual');

  if v_res ->> 'status' <> 'registered' then
    raise exception 'CASE3 FAILED: status = %', v_res ->> 'status';
  end if;

  select c.id into v_x from public.customers c
  where c.email_normalized = 'tm-test-x@treemerce.test';

  select ca.assigned_agent_id into v_assigned
  from public.customer_assignments ca
  where ca.customer_id = v_x and ca.status = 'active';

  if v_assigned is distinct from v_b then
    raise exception 'CASE3 FAILED: X の担当が % (expected B=%)', v_assigned, v_b;
  end if;

  perform set_config('tm.customer_x', v_x::text, true);
  raise notice 'CASE3 OK: X の担当代理店が B で保存された';
end $$;

-- 他の顧客 fixture (Y→A, Z→C, W→D, V→S, U→R)
do $$
begin
  perform public.treemerce_register_customer('TM-TEST-A', '佐藤花子',
    'tm-test-y@treemerce.test', '090-2222-3333', null, '30s', 'female', '大阪府', 'individual');
  perform public.treemerce_register_customer(
    (select public_id from public.agents where id = current_setting('tm.agent_c')::uuid),
    '鈴木一郎', 'tm-test-z@treemerce.test', '090-3333-4444', null, '50s', 'male',
    '東京都', 'individual');
  perform public.treemerce_register_customer('TM-TEST-D', '高橋次郎',
    'tm-test-w@treemerce.test', '090-4444-5555', null, '20s', 'male', '福岡県', 'individual');
  perform public.treemerce_register_customer('TM-TEST-S', '田中三郎',
    'tm-test-v@treemerce.test', '090-5555-6666', null, '60s', 'male', '北海道', 'individual');
  perform public.treemerce_register_customer('TM-TEST-R', '伊藤四郎',
    'tm-test-u@treemerce.test', '090-6666-7777', null, '40s', 'female', '愛知県', 'individual');
end $$;

-- 購入データ。X の販売額 999999 / 商品名が漏れないことを CASE15 で確認する。
insert into public.purchases (customer_id, agent_id, product_category, product_name,
                              quantity, unit_price, amount, purchased_at)
select c.id,
       (select ca.assigned_agent_id from public.customer_assignments ca
        where ca.customer_id = c.id and ca.status = 'active'),
       'health', 'ヒミツのサプリメントX', 1, 999999, 999999, now()
from public.customers c where c.email_normalized = 'tm-test-x@treemerce.test';

insert into public.purchases (customer_id, agent_id, product_category, product_name,
                              quantity, unit_price, amount, purchased_at)
select c.id,
       (select ca.assigned_agent_id from public.customer_assignments ca
        where ca.customer_id = c.id and ca.status = 'active'),
       'beauty', 'Aの自社商品', 1, 12000, 12000, now()
from public.customers c where c.email_normalized = 'tm-test-y@treemerce.test';

-- ============================================================================
-- CASE4 : A が X を再登録 → 重複検知され、担当は変更されない
-- ============================================================================

do $$
declare v_res jsonb; v_x uuid; v_assigned uuid; v_b uuid; v_hist_before int; v_hist_after int;
begin
  v_x := current_setting('tm.customer_x')::uuid;
  v_b := current_setting('tm.agent_b')::uuid;
  select count(*) into v_hist_before from public.customer_assignment_history where customer_id = v_x;

  v_res := public.treemerce_register_customer(
    'TM-TEST-A', '山田太郎', 'tm-test-x@treemerce.test', '090-1111-2222');

  if v_res ->> 'status' <> 'duplicate' then
    raise exception 'CASE4 FAILED: 重複が検知されなかった (status=%)', v_res ->> 'status';
  end if;
  if (v_res ->> 'assignment_changed')::boolean then
    raise exception 'CASE4 FAILED: assignment_changed が true になっている';
  end if;
  -- 絶対原則6: 中立メッセージ。担当代理店が誰かは漏らさない。
  if v_res::text like '%TM-TEST-B%' or v_res::text like '%代理店B%' then
    raise exception 'CASE4 FAILED: 中立でないメッセージ (担当代理店が漏れている)';
  end if;

  select ca.assigned_agent_id into v_assigned
  from public.customer_assignments ca where ca.customer_id = v_x and ca.status = 'active';
  if v_assigned is distinct from v_b then
    raise exception 'CASE4 FAILED: 担当が変更された (% / 期待 B=%)', v_assigned, v_b;
  end if;

  select count(*) into v_hist_after from public.customer_assignment_history where customer_id = v_x;
  if v_hist_after <> v_hist_before then
    raise exception 'CASE4 FAILED: 重複登録で履歴が増えた';
  end if;
  raise notice 'CASE4 OK: 重複検知・担当変更なし・中立メッセージ';
end $$;

-- ============================================================================
-- CASE5 : A が非担当の X へアクセス → 拒否 (行が見えない)
-- ============================================================================

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_x uuid; v_cnt int; v_pcnt int; v_acnt int;
begin
  v_x := current_setting('tm.customer_x')::uuid;
  select count(*) into v_cnt  from public.customers where id = v_x;
  select count(*) into v_pcnt from public.purchases where customer_id = v_x;
  select count(*) into v_acnt from public.customer_assignments where customer_id = v_x;

  if v_cnt <> 0 then raise exception 'CASE5 FAILED: A が X の顧客行を読めた'; end if;
  if v_pcnt <> 0 then raise exception 'CASE5 FAILED: A が X の購入行を読めた'; end if;
  if v_acnt <> 0 then raise exception 'CASE5 FAILED: A が X の担当行を読めた'; end if;
  raise notice 'CASE5 OK: 非担当代理店 A から X は行レベルで不可視';
end $$;

reset role;

-- ============================================================================
-- CASE6 : B が担当の X へアクセス → 許可 (氏名・購入内容まで見える)
-- ============================================================================

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_x uuid; v_name text; v_pcnt int;
begin
  v_x := current_setting('tm.customer_x')::uuid;
  select full_name into v_name from public.customers where id = v_x;
  select count(*) into v_pcnt from public.purchases where customer_id = v_x;

  if v_name is distinct from '山田太郎' then
    raise exception 'CASE6 FAILED: 担当代理店 B が X の氏名を取得できない (%)', v_name;
  end if;
  if v_pcnt < 1 then
    raise exception 'CASE6 FAILED: 担当代理店 B が X の購入内容を取得できない';
  end if;
  raise notice 'CASE6 OK: 担当代理店 B は X の氏名・購入内容を閲覧できる';
end $$;

-- ============================================================================
-- CASE7 : 一般代理店が担当変更を直接実行 → サーバー側で全経路拒否
-- ============================================================================

do $$
declare v_x uuid; v_c uuid; v_ok boolean;
begin
  v_x := current_setting('tm.customer_x')::uuid;
  v_c := current_setting('tm.agent_c')::uuid;

  -- (1) ADMIN 専用 RPC を一般代理店が直接呼ぶ
  v_ok := false;
  begin
    perform public.treemerce_admin_transfer_customer(v_x, v_c, '勝手に移管');
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then raise exception 'CASE7 FAILED: 一般代理店が担当変更RPCを実行できた'; end if;

  -- (2) テーブルを直接 UPDATE
  v_ok := false;
  begin
    update public.customer_assignments set assigned_agent_id = v_c where customer_id = v_x;
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then raise exception 'CASE7 FAILED: customer_assignments を直接 UPDATE できた'; end if;

  -- (3) テーブルを直接 DELETE
  v_ok := false;
  begin
    delete from public.customer_assignments where customer_id = v_x;
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then raise exception 'CASE7 FAILED: customer_assignments を直接 DELETE できた'; end if;

  -- (4) 担当を新規 INSERT して奪う
  v_ok := false;
  begin
    insert into public.customer_assignments (customer_id, assigned_agent_id, status)
    values (v_x, v_c, 'active');
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then raise exception 'CASE7 FAILED: customer_assignments に直接 INSERT できた'; end if;

  -- (5) 履歴の改ざん
  v_ok := false;
  begin
    delete from public.customer_assignment_history where customer_id = v_x;
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then raise exception 'CASE7 FAILED: 担当変更履歴を DELETE できた'; end if;

  raise notice 'CASE7 OK: RPC / UPDATE / DELETE / INSERT / 履歴改ざん の全経路で拒否';
end $$;

reset role;

-- ============================================================================
-- CASE8 : ADMIN が X の担当を B→C に変更 → 成功・履歴・監査ログ保存
-- ============================================================================

savepoint before_case8;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  v_x uuid; v_b uuid; v_c uuid; v_res jsonb;
  v_assigned uuid; v_hist record; v_audit record;
begin
  v_x := current_setting('tm.customer_x')::uuid;
  v_b := current_setting('tm.agent_b')::uuid;
  v_c := current_setting('tm.agent_c')::uuid;

  v_res := public.treemerce_admin_transfer_customer(v_x, v_c, '顧客からの担当変更申請のため');
  if v_res ->> 'status' <> 'transferred' then
    raise exception 'CASE8 FAILED: 担当変更が成功しなかった (%)', v_res::text;
  end if;

  select ca.assigned_agent_id into v_assigned
  from public.customer_assignments ca where ca.customer_id = v_x and ca.status = 'active';
  if v_assigned is distinct from v_c then
    raise exception 'CASE8 FAILED: 担当が C になっていない (%)', v_assigned;
  end if;

  -- 変更前後・理由・実行者・日時が履歴に残る
  -- (初回登録の履歴と区別するため previous_agent_id が入っている行を見る)
  select * into v_hist from public.customer_assignment_history
  where customer_id = v_x and previous_agent_id is not null
  order by changed_at desc limit 1;
  if v_hist.previous_agent_id is distinct from v_b
     or v_hist.new_agent_id is distinct from v_c
     or v_hist.reason <> '顧客からの担当変更申請のため'
     or v_hist.changed_by is distinct from '00000000-0000-4000-8000-000000000007'::uuid
     or v_hist.changed_at is null then
    raise exception 'CASE8 FAILED: 履歴の内容が不正 (%)', to_jsonb(v_hist)::text;
  end if;

  -- 監査ログにも変更前後・理由・実行者・日時が残る
  select * into v_audit from public.admin_audit_logs
  where target_id = v_x and action = 'customer_assignment.transfer'
  order by created_at desc limit 1;
  if v_audit.id is null then
    raise exception 'CASE8 FAILED: admin_audit_logs に記録がない';
  end if;
  if (v_audit.before_state ->> 'assigned_agent_id')::uuid is distinct from v_b
     or (v_audit.after_state ->> 'assigned_agent_id')::uuid is distinct from v_c
     or v_audit.reason <> '顧客からの担当変更申請のため'
     or v_audit.actor_user_id is distinct from '00000000-0000-4000-8000-000000000007'::uuid
     or v_audit.created_at is null then
    raise exception 'CASE8 FAILED: 監査ログの内容が不正 (%)', to_jsonb(v_audit)::text;
  end if;

  -- 旧担当 B からは見えなくなっている (担当解除の反映)
  if exists (select 1 from public.customer_assignments
             where customer_id = v_x and assigned_agent_id = v_b and status = 'active') then
    raise exception 'CASE8 FAILED: 旧担当の assignment が active のまま';
  end if;

  raise notice 'CASE8 OK: ADMIN による B->C 担当変更・履歴・監査ログを確認';
end $$;

reset role;

-- 以降の CASE のため CASE8 の変更は巻き戻す (X の担当を B に戻す)
rollback to savepoint before_case8;

-- ============================================================================
-- CASE9 : コミュニティマップ → 代理店のみ・購入者は一切出ない
-- ============================================================================

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_map jsonb; v_txt text;
begin
  v_map := public.treemerce_community_map(null);
  v_txt := v_map::text;

  if v_map ? 'customers' then
    raise exception 'CASE9 FAILED: コミュニティマップに customers キーが存在する';
  end if;
  if not (v_map ? 'nodes' and v_map ? 'edges') then
    raise exception 'CASE9 FAILED: nodes / edges が返っていない';
  end if;
  if v_txt like '%山田太郎%' or v_txt like '%佐藤花子%'
     or v_txt like '%@treemerce.test%' or v_txt like '%顧客#%' then
    raise exception 'CASE9 FAILED: 購入者の情報が含まれている';
  end if;
  if jsonb_array_length(v_map -> 'nodes') <> 4 then
    raise exception 'CASE9 FAILED: A の部分木が 4 件 (A,B,C,D) でない: %',
      jsonb_array_length(v_map -> 'nodes');
  end if;
  raise notice 'CASE9 OK: コミュニティマップは代理店ノードのみ';
end $$;

reset role;
select set_config('request.jwt.claims', '', true);

-- ============================================================================
-- CASE10 : 商品購入者管理 → 担当代理店との関係のみ。登録経路と混同しない
-- ============================================================================

do $$
declare v_fk int; v_col int; v_x uuid; v_active int;
begin
  -- customers から agents への直接 FK は存在してはならない
  select count(*) into v_fk
  from information_schema.table_constraints tc
  join information_schema.constraint_column_usage ccu
    on ccu.constraint_name = tc.constraint_name
   and ccu.constraint_schema = tc.constraint_schema
  where tc.constraint_type = 'FOREIGN KEY'
    and tc.table_schema = 'public' and tc.table_name = 'customers'
    and ccu.table_name = 'agents';
  if v_fk <> 0 then
    raise exception 'CASE10 FAILED: customers が agents を直接参照している (登録経路との混同)';
  end if;

  -- customers に登録経路系のカラムがあってはならない
  select count(*) into v_col from information_schema.columns
  where table_schema = 'public' and table_name = 'customers'
    and column_name in ('invited_by', 'inviter_id', 'agent_id', 'referrer_id');
  if v_col <> 0 then
    raise exception 'CASE10 FAILED: customers に登録経路カラムが存在する';
  end if;

  -- 担当関係は customer_assignments だけが表現する
  select count(*) into v_fk
  from information_schema.table_constraints tc
  join information_schema.constraint_column_usage ccu
    on ccu.constraint_name = tc.constraint_name
   and ccu.constraint_schema = tc.constraint_schema
  where tc.constraint_type = 'FOREIGN KEY'
    and tc.table_schema = 'public' and tc.table_name = 'customer_assignments'
    and ccu.table_name = 'agents';
  if v_fk = 0 then
    raise exception 'CASE10 FAILED: customer_assignments が agents を参照していない';
  end if;

  v_x := current_setting('tm.customer_x')::uuid;
  select count(*) into v_active from public.customer_assignments
  where customer_id = v_x and status = 'active'
    and assigned_agent_id = current_setting('tm.agent_b')::uuid;
  if v_active <> 1 then
    raise exception 'CASE10 FAILED: 有効な担当が customer_assignments に一意に存在しない';
  end if;

  raise notice 'CASE10 OK: 顧客担当は customer_assignments のみ。登録経路とは別データ';
end $$;

-- ============================================================================
-- CASE11 : A の商流マップ = 自分+傘下(B,C,D)、自分担当は実名、傘下担当は匿名
-- ============================================================================

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_map jsonb; v_agents text[]; v_own jsonb; v_anon int; v_named int;
begin
  v_map := public.treemerce_commerce_map(null);

  select array_agg(n ->> 'public_id' order by n ->> 'public_id')
  into v_agents from jsonb_array_elements(v_map -> 'agents') n;

  if not (v_agents @> array['TM-TEST-A', 'TM-TEST-D']) then
    raise exception 'CASE11 FAILED: A / D が商流マップに含まれない (%)', v_agents;
  end if;
  if array_length(v_agents, 1) <> 4 then
    raise exception 'CASE11 FAILED: 部分木の代理店が 4 件でない (%)', v_agents;
  end if;

  -- 自分担当 (Y = 佐藤花子) は実名 + 購入商品
  select c into v_own from jsonb_array_elements(v_map -> 'customers') c
  where c ->> 'label' = '佐藤花子';
  if v_own is null then
    raise exception 'CASE11 FAILED: 自分担当顧客が実名で出ていない';
  end if;
  if (v_own ->> 'anonymous')::boolean then
    raise exception 'CASE11 FAILED: 自分担当顧客が匿名化されている';
  end if;
  if jsonb_array_length(v_own -> 'purchases') < 1 then
    raise exception 'CASE11 FAILED: 自分担当顧客の購入商品が出ていない';
  end if;

  select count(*) into v_anon from jsonb_array_elements(v_map -> 'customers') c
  where (c ->> 'anonymous')::boolean;
  select count(*) into v_named from jsonb_array_elements(v_map -> 'customers') c
  where not (c ->> 'anonymous')::boolean;

  -- X(B) / Z(C) / W(D) の 3 件が匿名、Y(A) の 1 件だけ実名
  if v_anon <> 3 or v_named <> 1 then
    raise exception 'CASE11 FAILED: 匿名 % 件 / 実名 % 件 (期待 3 / 1)', v_anon, v_named;
  end if;
  -- 匿名ノードは「顧客#XXXX」形式のラベルと件数のみ
  if exists (select 1 from jsonb_array_elements(v_map -> 'customers') c
             where (c ->> 'anonymous')::boolean
               and (c ->> 'label' !~ '^顧客#[0-9A-F]{4}$' or c ? 'purchases')) then
    raise exception 'CASE11 FAILED: 匿名ノードの形式が不正';
  end if;

  raise notice 'CASE11 OK: 自分担当は実名+購入商品、傘下担当は匿名ノード';
end $$;

-- ============================================================================
-- CASE12 : A の兄弟枝 (S) の代理店・顧客が A のマップに一切出ない
-- ============================================================================

do $$
declare v_map jsonb; v_txt text;
begin
  v_map := public.treemerce_commerce_map(null);
  v_txt := v_map::text;

  if exists (select 1 from jsonb_array_elements(v_map -> 'agents') n
             where n ->> 'public_id' = 'TM-TEST-S') then
    raise exception 'CASE12 FAILED: 兄弟枝 S がマップに出ている';
  end if;
  if exists (select 1 from jsonb_array_elements(v_map -> 'customers') c
             where (c ->> 'agent_id')::uuid = '10000000-0000-4000-8000-000000000006'::uuid) then
    raise exception 'CASE12 FAILED: 兄弟枝 S 担当の顧客ノードが出ている';
  end if;
  if v_txt like '%TM-TEST-S%' or v_txt like '%テスト代理店S%' or v_txt like '%田中三郎%' then
    raise exception 'CASE12 FAILED: 兄弟枝の情報がレスポンスに含まれている';
  end if;

  raise notice 'CASE12 OK: 兄弟枝 S とその顧客はマップに一切出ない';
end $$;

-- ============================================================================
-- CASE13 : A の upline (招待元 R) が A のマップに出ない
-- ============================================================================

do $$
declare v_map jsonb; v_txt text;
begin
  v_map := public.treemerce_commerce_map(null);
  v_txt := v_map::text;

  if exists (select 1 from jsonb_array_elements(v_map -> 'agents') n
             where n ->> 'public_id' = 'TM-TEST-R') then
    raise exception 'CASE13 FAILED: upline R がマップに出ている';
  end if;
  if exists (select 1 from jsonb_array_elements(v_map -> 'customers') c
             where (c ->> 'agent_id')::uuid = '10000000-0000-4000-8000-000000000001'::uuid) then
    raise exception 'CASE13 FAILED: upline R 担当の顧客ノードが出ている';
  end if;
  if v_txt like '%TM-TEST-R%' or v_txt like '%テスト代理店R%' or v_txt like '%伊藤四郎%' then
    raise exception 'CASE13 FAILED: upline の情報がレスポンスに含まれている';
  end if;

  raise notice 'CASE13 OK: 招待元 R とその顧客はマップに一切出ない';
end $$;

-- ============================================================================
-- CASE15 : 商流マップAPIを直接叩いても他代理店担当顧客のPIIが含まれない
-- ============================================================================

do $$
declare v_txt text;
begin
  v_txt := public.treemerce_commerce_map(null)::text;

  if v_txt like '%山田太郎%' or v_txt like '%鈴木一郎%' or v_txt like '%高橋次郎%' then
    raise exception 'CASE15 FAILED: 傘下担当顧客の氏名が含まれる';
  end if;
  if v_txt like '%tm-test-x@%' or v_txt like '%tm-test-z@%' or v_txt like '%tm-test-w@%' then
    raise exception 'CASE15 FAILED: 傘下担当顧客のメールアドレスが含まれる';
  end if;
  if v_txt like '%090-1111-2222%' or v_txt like '%090-3333-4444%' then
    raise exception 'CASE15 FAILED: 傘下担当顧客の電話番号が含まれる';
  end if;
  if v_txt like '%999999%' or v_txt like '%ヒミツのサプリメントX%' then
    raise exception 'CASE15 FAILED: 傘下担当顧客の販売額 / 購入商品が含まれる';
  end if;

  raise notice 'CASE15 OK: 傘下担当顧客の氏名・連絡先・購入商品・販売額は含まれない';
end $$;

reset role;

-- ============================================================================
-- CASE14 : 商流マップ経由で担当変更・登録経路変更が発生しない
--          (全行を突き合わせるため postgres として実行。閲覧者は A のまま)
-- ============================================================================

do $$
declare
  v_assign_before text; v_assign_after text;
  v_route_before  text; v_route_after  text;
  v_hist_before int; v_hist_after int;
  v_vol_map char; v_vol_com char; v_vol_dem char;
begin
  select md5(coalesce(string_agg(id::text || assigned_agent_id::text || status::text,
                                 ',' order by id::text), ''))
  into v_assign_before from public.customer_assignments;
  select md5(coalesce(string_agg(id::text || coalesce(invited_by::text, '-'),
                                 ',' order by id::text), ''))
  into v_route_before from public.agents;
  select count(*) into v_hist_before from public.customer_assignment_history;

  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

  perform public.treemerce_commerce_map(null);
  perform public.treemerce_community_map(null);
  perform public.treemerce_customer_demographics(null, 'all');
  perform public.treemerce_customer_demographics(null, '3m');
  perform public.treemerce_customer_demographics(null, '1y');

  select md5(coalesce(string_agg(id::text || assigned_agent_id::text || status::text,
                                 ',' order by id::text), ''))
  into v_assign_after from public.customer_assignments;
  select md5(coalesce(string_agg(id::text || coalesce(invited_by::text, '-'),
                                 ',' order by id::text), ''))
  into v_route_after from public.agents;
  select count(*) into v_hist_after from public.customer_assignment_history;

  if v_assign_before is distinct from v_assign_after then
    raise exception 'CASE14 FAILED: 商流マップ呼び出しで担当が変化した';
  end if;
  if v_route_before is distinct from v_route_after then
    raise exception 'CASE14 FAILED: 商流マップ呼び出しで登録経路が変化した';
  end if;
  if v_hist_before <> v_hist_after then
    raise exception 'CASE14 FAILED: 商流マップ呼び出しで履歴が増えた';
  end if;

  -- STABLE 関数は書込みができない = 構造的に読み取り専用
  select provolatile into v_vol_map from pg_proc
  where oid = 'public.treemerce_commerce_map(uuid)'::regprocedure;
  select provolatile into v_vol_com from pg_proc
  where oid = 'public.treemerce_community_map(uuid)'::regprocedure;
  select provolatile into v_vol_dem from pg_proc
  where oid = 'public.treemerce_customer_demographics(uuid,text)'::regprocedure;
  if v_vol_map <> 's' or v_vol_com <> 's' or v_vol_dem <> 's' then
    raise exception 'CASE14 FAILED: マップ/集計関数が STABLE でない (%/%/%)',
      v_vol_map, v_vol_com, v_vol_dem;
  end if;

  raise notice 'CASE14 OK: 商流マップ・客層分析は完全に読み取り専用';
end $$;

-- ============================================================================
-- CASE16 : B の客層分析は B 自身 + B 傘下 (C) の匿名集計値が対象
-- ============================================================================

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_res jsonb;
begin
  v_res := public.treemerce_customer_demographics(null, 'all');

  if (v_res ->> 'scope_agent_count')::int <> 2 then
    raise exception 'CASE16 FAILED: 集計対象代理店が B+C の 2 件でない (%)',
      v_res ->> 'scope_agent_count';
  end if;
  if (v_res ->> 'total_customers')::int <> 2 then
    raise exception 'CASE16 FAILED: 集計対象顧客が X+Z の 2 件でない (%)',
      v_res ->> 'total_customers';
  end if;
  if not (v_res ? 'age_group' and v_res ? 'gender' and v_res ? 'prefecture'
          and v_res ? 'customer_type' and v_res ? 'product_category') then
    raise exception 'CASE16 FAILED: 必要なグラフ軸が揃っていない';
  end if;
  -- n < 5 のセグメントは「該当データ少数」に丸められる
  if ((v_res -> 'age_group')::text not like '%該当データ少数%') then
    raise exception 'CASE16 FAILED: 少数セグメントが丸められていない (%)',
      (v_res -> 'age_group')::text;
  end if;
  -- 期間フィルターが動作する
  if public.treemerce_customer_demographics(null, '3m') is null
     or public.treemerce_customer_demographics(null, '1y') is null then
    raise exception 'CASE16 FAILED: 期間フィルターが動作しない';
  end if;

  raise notice 'CASE16 OK: B 自身 + 傘下 C の匿名集計が対象 (期間フィルター含む)';
end $$;

-- ============================================================================
-- CASE17 : B の兄弟枝(D)・upline(A, R)・別枝(S) の顧客が含まれない
-- ============================================================================

do $$
declare v_res jsonb; v_txt text; v_total int; v_ok boolean;
begin
  v_res   := public.treemerce_customer_demographics(null, 'all');
  v_txt   := v_res::text;
  v_total := (v_res ->> 'total_customers')::int;

  -- X(B) と Z(C) のみ = 2 件。D/A/R/S の顧客が混ざれば 2 を超える。
  if v_total <> 2 then
    raise exception 'CASE17 FAILED: 傘外の顧客が集計に混入 (total=%)', v_total;
  end if;

  -- 他代理店 (A) を根にした集計はサーバー側で拒否される
  v_ok := false;
  begin
    perform public.treemerce_customer_demographics(
      '10000000-0000-4000-8000-000000000002'::uuid, 'all');
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then
    raise exception 'CASE17 FAILED: 他代理店(A)を根とする集計が実行できてしまった';
  end if;

  if v_txt like '%TM-TEST-A%' or v_txt like '%TM-TEST-D%'
     or v_txt like '%TM-TEST-R%' or v_txt like '%TM-TEST-S%' then
    raise exception 'CASE17 FAILED: 傘外代理店の情報がレスポンスに含まれる';
  end if;

  raise notice 'CASE17 OK: 兄弟枝・upline・別枝の顧客は集計対象外';
end $$;

-- ============================================================================
-- CASE18 : レスポンスから「どの傘下代理店の担当か」を特定できない
-- ============================================================================

do $$
declare v_res jsonb; v_txt text; v_c uuid; v_x uuid; v_z uuid;
begin
  v_res := public.treemerce_customer_demographics(null, 'all');
  v_txt := v_res::text;

  v_c := current_setting('tm.agent_c')::uuid;
  v_x := current_setting('tm.customer_x')::uuid;
  select id into v_z from public.customers where email_normalized = 'tm-test-z@treemerce.test';

  if v_txt like '%' || v_c::text || '%' then
    raise exception 'CASE18 FAILED: 傘下代理店 C の ID がレスポンスに含まれる';
  end if;
  if v_txt like '%' || v_x::text || '%' or (v_z is not null and v_txt like '%' || v_z::text || '%') then
    raise exception 'CASE18 FAILED: 顧客 ID がレスポンスに含まれる';
  end if;
  if v_res ? 'by_agent' or v_res ? 'agents' or v_res ? 'agent_breakdown' or v_res ? 'customers' then
    raise exception 'CASE18 FAILED: 代理店別内訳が含まれる';
  end if;
  if v_txt like '%山田太郎%' or v_txt like '%鈴木一郎%' or v_txt like '%@treemerce.test%' then
    raise exception 'CASE18 FAILED: 個人PIIが含まれる';
  end if;

  raise notice 'CASE18 OK: どの傘下代理店の担当かを特定できる情報は含まれない';
end $$;

reset role;
select set_config('request.jwt.claims', '', true);

-- ============================================================================
-- CASE19 : 招待元が確定済みの代理店を別の招待URLで再登録 → 拒否
--          (C は既に B の招待で登録済み。A の招待URLでの再登録を試みる)
-- ============================================================================

do $$
declare v_ok boolean; v_c uuid; v_b uuid; v_before uuid; v_after uuid;
begin
  v_c := current_setting('tm.agent_c')::uuid;
  v_b := current_setting('tm.agent_b')::uuid;
  select invited_by into v_before from public.agents where id = v_c;

  -- (1) API 層 (RPC) で拒否されること
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000004","role":"authenticated"}', true);
  v_ok := false;
  begin
    perform public.treemerce_register_agent(
      'テスト代理店C', 'tm-test-c@treemerce.test', null, current_setting('tm.invite_a'));
  exception when check_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception 'CASE19 FAILED: 招待元が確定済みの代理店を RPC で再登録できてしまった';
  end if;

  -- (2) DB 層 (トリガ) でも拒否されること
  v_ok := false;
  begin
    update public.agents set invited_by = '10000000-0000-4000-8000-000000000002' where id = v_c;
  exception when check_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception 'CASE19 FAILED: invited_by を直接 UPDATE できてしまった';
  end if;

  select invited_by into v_after from public.agents where id = v_c;
  if v_after is distinct from v_before or v_after is distinct from v_b then
    raise exception 'CASE19 FAILED: invited_by が変化した (% -> %)', v_before, v_after;
  end if;

  raise notice 'CASE19 OK: 招待元は再設定不可。invited_by は元のまま';
end $$;

-- ============================================================================
-- CASE20 : treemerce_my_inviter_profile() は「自分の招待元」だけを返す
--          (agents_select の RLS では upline は見えないが、この RPC は例外的に
--           呼び出し本人の招待元1件だけを解決する。引数は取らない)
-- ============================================================================

do $$
declare v_profile jsonb;
begin
  -- A (R の招待で登録) として呼ぶ → R の display_name だけが返る (0009)
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  set local role authenticated;

  select public.treemerce_my_inviter_profile() into v_profile;
  if (v_profile ->> 'found') is distinct from 'true' then
    raise exception 'CASE20 FAILED: A から見た招待元が found=false だった (%)', v_profile;
  end if;
  if (v_profile ->> 'display_name') is distinct from 'テスト代理店R' then
    raise exception 'CASE20 FAILED: A の招待元が R ではなかった (%)', v_profile;
  end if;
  -- 代理店名以外 (public_id・連絡先・傘上の他情報) は一切含めない
  if (select array_agg(k order by k) from jsonb_object_keys(v_profile) k)
     is distinct from array['display_name', 'found'] then
    raise exception 'CASE20 FAILED: 代理店名以外の項目が返った (%)', v_profile;
  end if;

  reset role;

  -- R (招待元なし) として呼ぶ → found=false
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  set local role authenticated;

  select public.treemerce_my_inviter_profile() into v_profile;
  if (v_profile ->> 'found') is distinct from 'false' then
    raise exception 'CASE20 FAILED: 招待元なしの R で found=true になった (%)', v_profile;
  end if;

  reset role;
  raise notice 'CASE20 OK: 招待元の表示名は本人分のみ解決され、招待元なしなら found=false';
end $$;

-- ============================================================================
-- 補強検証 (EXTRA) : CASE1-20 が素通りしていないことを確認する追加の攻撃経路
-- ============================================================================

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_ok boolean; v_cnt int;
begin
  -- EXTRA1: 商流マップの根に他代理店を指定できない (CASE17 の商流マップ版)
  v_ok := false;
  begin
    perform public.treemerce_commerce_map('10000000-0000-4000-8000-000000000001'::uuid);
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then raise exception 'EXTRA1 FAILED: 他代理店を根とする商流マップを取得できた'; end if;

  -- EXTRA2: 一般代理店は監査ログを 1 行も読めない
  select count(*) into v_cnt from public.admin_audit_logs;
  if v_cnt <> 0 then raise exception 'EXTRA2 FAILED: 一般代理店が監査ログを読めた (%件)', v_cnt; end if;

  -- EXTRA3: 自分の invited_by を書き換えられない (列 GRANT なし)
  v_ok := false;
  begin
    update public.agents set invited_by = null
    where auth_user_id = '00000000-0000-4000-8000-000000000002'::uuid;
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then raise exception 'EXTRA3 FAILED: 自分の登録経路を書き換えられた'; end if;

  -- EXTRA4: 自分のステータスを勝手に active 以外へ変えられない (列 GRANT なし)
  v_ok := false;
  begin
    update public.agents set status = 'suspended'
    where auth_user_id = '00000000-0000-4000-8000-000000000002'::uuid;
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then raise exception 'EXTRA4 FAILED: 自分のステータスを変更できた'; end if;

  -- EXTRA5: 担当顧客であっても識別子 (email) は書き換えられない
  --         (絶対原則7 の照合基盤を代理店側から壊せないようにするため)
  v_ok := false;
  begin
    update public.customers set email = 'hijack@example.com'
    where email_normalized = 'tm-test-y@treemerce.test';
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then raise exception 'EXTRA5 FAILED: 担当顧客の識別子を書き換えられた'; end if;

  -- EXTRA6: 兄弟枝 (S) と upline (R) の代理店行そのものが見えない
  select count(*) into v_cnt from public.agents
  where public_id in ('TM-TEST-S', 'TM-TEST-R');
  if v_cnt <> 0 then
    raise exception 'EXTRA6 FAILED: 傘外の代理店行が見えている (%件)', v_cnt;
  end if;

  raise notice 'EXTRA1-6 OK: 根の偽装・監査ログ・登録経路/状態/識別子の改ざん・傘外参照を全て拒否';
end $$;

reset role;

-- EXTRA7: 未ログイン (anon) は顧客テーブルにも管理RPCにも一切到達できない
set local role anon;

do $$
declare v_ok boolean;
begin
  v_ok := false;
  begin
    perform count(*) from public.customers;
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then raise exception 'EXTRA7 FAILED: anon が customers を読めた'; end if;

  v_ok := false;
  begin
    perform public.treemerce_admin_transfer_customer(
      current_setting('tm.customer_x')::uuid,
      current_setting('tm.agent_c')::uuid, '匿名からの移管');
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then raise exception 'EXTRA7 FAILED: anon が担当変更RPCを実行できた'; end if;

  raise notice 'EXTRA7 OK: anon は顧客データにも担当変更RPCにも到達できない';
end $$;

reset role;

-- ============================================================================
-- EXTRA8 : 統括管理ページの書込みRPCは super_admin 以外 (admin/support) を拒否する
-- (0008_treemerce_admin_console.sql: app.is_super_admin() への格上げ)
-- ============================================================================

insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000008',
   'authenticated', 'authenticated', 'tm-test-admin-plain@treemerce.test', '', now(), now(), now());

insert into public.admin_roles (auth_user_id, role)
values ('00000000-0000-4000-8000-000000000008', 'admin');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000008","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_x uuid; v_c uuid; v_ok boolean;
begin
  v_x := current_setting('tm.customer_x')::uuid;
  v_c := current_setting('tm.agent_c')::uuid;

  v_ok := false;
  begin
    perform public.treemerce_admin_transfer_customer(v_x, v_c, '一般adminによる移管');
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then raise exception 'EXTRA8 FAILED: 一般adminが担当変更RPCを実行できた'; end if;

  v_ok := false;
  begin
    perform public.treemerce_admin_update_customer(v_x, jsonb_build_object('note', '改ざん'), '一般adminによる編集');
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then raise exception 'EXTRA8 FAILED: 一般adminが顧客更新RPCを実行できた'; end if;

  v_ok := false;
  begin
    perform public.treemerce_admin_set_agent_status(v_c, 'suspended', '一般adminによる停止');
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then raise exception 'EXTRA8 FAILED: 一般adminがステータス変更RPCを実行できた'; end if;

  raise notice 'EXTRA8 OK: 一般admin(非super_admin)は統括管理の3RPCすべてで拒否される';
end $$;

reset role;

-- ============================================================================
-- EXTRA9 : super_admin なら顧客更新/ステータス変更が成功し、監査ログに残る
-- ============================================================================

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  v_x uuid; v_c uuid; v_res jsonb; v_note text; v_audit_cnt int;
begin
  v_x := current_setting('tm.customer_x')::uuid;
  v_c := current_setting('tm.agent_c')::uuid;

  v_res := public.treemerce_admin_update_customer(
    v_x, jsonb_build_object('note', 'super_adminによる編集メモ'), '本人確認のため備考を更新');
  select note into v_note from public.customers where id = v_x;
  if v_note is distinct from 'super_adminによる編集メモ' then
    raise exception 'EXTRA9 FAILED: super_adminによる顧客更新が反映されていない (%)', v_note;
  end if;

  select count(*) into v_audit_cnt from public.admin_audit_logs
  where target_table = 'customers' and target_id = v_x and action = 'customer.update';
  if v_audit_cnt < 1 then
    raise exception 'EXTRA9 FAILED: 顧客更新が監査ログに残っていない';
  end if;

  v_res := public.treemerce_admin_set_agent_status(v_c, 'suspended', '本人確認のため一時停止');
  if v_res ->> 'status' <> 'suspended' then
    raise exception 'EXTRA9 FAILED: super_adminによるステータス変更が成功しなかった (%)', v_res::text;
  end if;

  -- 元に戻す (以降のテストに影響させない)
  perform public.treemerce_admin_set_agent_status(v_c, 'active', 'テスト後の復旧');

  raise notice 'EXTRA9 OK: super_adminは顧客更新/ステータス変更を実行でき、監査ログに残る';
end $$;

-- ============================================================================
-- EXTRA10 : 顧客更新は理由(reason)が必須
-- ============================================================================

do $$
declare v_x uuid; v_ok boolean;
begin
  v_x := current_setting('tm.customer_x')::uuid;

  v_ok := false;
  begin
    perform public.treemerce_admin_update_customer(v_x, jsonb_build_object('note', '理由なし更新'), null);
  exception when invalid_parameter_value then
    v_ok := true;
  end;
  if not v_ok then raise exception 'EXTRA10 FAILED: 理由なしで顧客更新が成功した'; end if;

  raise notice 'EXTRA10 OK: 顧客更新は理由が必須 (TREEMERCE_REASON_REQUIRED)';
end $$;

reset role;

-- ============================================================================
-- 商品・注文機能 (0010 / 0011)  CASE21 - CASE31
-- ----------------------------------------------------------------------------
-- 認証 ID: R=..001 A=..002 B=..003 C=..004 D=..005 S=..006 super_admin=..007 admin=..008
-- ============================================================================

-- SETUP: super_admin がショップ設定と商品を登録する (RPC 経由)
-- B / C は招待経由で登録したため public_id は自動採番。実際の値を控えておく。
select set_config('tm.agent_b_public',
  (select public_id from public.agents where id = current_setting('tm.agent_b')::uuid), true);

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_ok boolean; v_p jsonb;
begin
  -- 振込先・販売事業者が未設定のまま注文受付を開始できない
  v_ok := false;
  begin
    perform public.treemerce_admin_update_shop_settings(
      jsonb_build_object('is_accepting_orders', true), '受付開始');
  exception when invalid_parameter_value then
    v_ok := true;
  end;
  if not v_ok then raise exception 'SETUP FAILED: 振込先未設定で注文受付を開始できた'; end if;

  perform public.treemerce_admin_update_shop_settings(jsonb_build_object(
    'seller_name', 'テスト運営株式会社', 'seller_address', '東京都港区テスト1-1',
    'seller_phone', '03-0000-0000', 'shipping_fee', 800, 'payment_due_days', 7,
    'bank_name', 'テスト銀行', 'bank_branch', '本店', 'bank_account_type', 'ordinary',
    'bank_account_number', '1234567', 'bank_account_holder', 'テストウンエイ(カ',
    'is_accepting_orders', true), '受付開始');

  v_p := public.treemerce_admin_upsert_product('テスト健康食品', 5000, 10, true, 'health');
  perform set_config('tm.p1', v_p ->> 'id', true);
  v_p := public.treemerce_admin_upsert_product('テスト美容液', 12000, 1, true, 'beauty');
  perform set_config('tm.p2', v_p ->> 'id', true);
  v_p := public.treemerce_admin_upsert_product('テスト非公開商品', 3000, 5, false, 'food');
  perform set_config('tm.p3', v_p ->> 'id', true);
end $$;

reset role;

-- ============================================================================
-- CASE21 : 未ログインは商品/注文/設定テーブルに直接触れない。
--          公開 RPC は稼働代理店のリンクでのみ、公開中の商品だけを返す。振込先は返さない。
-- ============================================================================

select set_config('request.jwt.claims', '', true);
set local role anon;

do $$
declare v_ok boolean; v_res jsonb;
begin
  v_ok := false;
  begin perform count(*) from public.products; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE21 FAILED: anon が products を直接読めた'; end if;

  v_ok := false;
  begin perform count(*) from public.orders; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE21 FAILED: anon が orders を直接読めた'; end if;

  v_ok := false;
  begin perform count(*) from public.shop_settings; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE21 FAILED: anon が shop_settings を直接読めた'; end if;

  v_res := public.treemerce_shop_products(current_setting('tm.agent_b_public'));
  if (v_res ->> 'valid')::boolean is not true then
    raise exception 'CASE21 FAILED: 稼働代理店のリンクで valid=false (%)', v_res;
  end if;
  if jsonb_array_length(v_res -> 'products') <> 2 or v_res::text like '%テスト非公開商品%' then
    raise exception 'CASE21 FAILED: 非公開商品が返った / 件数不一致 (%)', v_res;
  end if;
  if v_res::text like '%"stock"%' or v_res::text like '%テスト代理店B%' then
    raise exception 'CASE21 FAILED: 在庫の正確な数または代理店名が返った';
  end if;

  if (public.treemerce_shop_products('NO-SUCH-AGENT') ->> 'valid')::boolean then
    raise exception 'CASE21 FAILED: 無効なリンクで valid=true';
  end if;

  v_res := public.treemerce_shop_public_settings();
  if v_res ->> 'seller_name' is distinct from 'テスト運営株式会社' then
    raise exception 'CASE21 FAILED: 特商法表記の販売事業者が返らない';
  end if;
  if v_res::text like '%1234567%' then
    raise exception 'CASE21 FAILED: 公開設定に振込先口座番号が含まれる';
  end if;

  raise notice 'CASE21 OK: anon は公開RPC経由の公開商品のみ閲覧でき、テーブル直接・非公開商品・口座番号には届かない';
end $$;

-- ============================================================================
-- CASE22 : B の紹介リンクから新規顧客 N が注文 → N の担当は B、注文の帰属も B
-- ============================================================================

do $$
declare v_res jsonb;
begin
  v_res := public.treemerce_place_order(
    current_setting('tm.agent_b_public'),
    jsonb_build_array(jsonb_build_object('product_id', current_setting('tm.p1'), 'quantity', 2)),
    '新規花子', '東京都千代田区テスト1-1', 'tm-test-n@treemerce.test', '090-7777-8888', '100-0001');

  if v_res ->> 'status' <> 'received' then
    raise exception 'CASE22 FAILED: status=%', v_res ->> 'status';
  end if;
  if (v_res ->> 'total')::numeric <> 10800 then
    raise exception 'CASE22 FAILED: 合計金額 % (期待 5000*2+送料800=10800)', v_res ->> 'total';
  end if;
  if v_res -> 'payment' ->> 'bank_account_number' is distinct from '1234567' then
    raise exception 'CASE22 FAILED: 注文完了応答に振込先が含まれない';
  end if;
  if v_res ? 'customer_id' or v_res ? 'agent_id' or v_res::text like '%' || current_setting('tm.agent_b_public') || '%'
     or v_res::text like '%テスト代理店B%' then
    raise exception 'CASE22 FAILED: 応答に顧客ID/担当代理店が含まれる (%)', v_res;
  end if;

  perform set_config('tm.order_n_no', v_res ->> 'order_no', true);
  perform set_config('tm.keys_new',
    (select string_agg(k, ',' order by k) from jsonb_object_keys(v_res) k), true);
end $$;

reset role;

do $$
declare v_n uuid; v_assigned uuid; v_order public.orders%rowtype; v_stock int; v_hist int; v_b uuid;
begin
  v_b := current_setting('tm.agent_b')::uuid;
  select id into v_n from public.customers where email_normalized = 'tm-test-n@treemerce.test';
  if v_n is null then raise exception 'CASE22 FAILED: 新規顧客 N が作成されていない'; end if;

  select assigned_agent_id into v_assigned from public.customer_assignments
  where customer_id = v_n and status = 'active';
  select * into v_order from public.orders where order_no = current_setting('tm.order_n_no');
  select stock into v_stock from public.products where id = current_setting('tm.p1')::uuid;
  select count(*) into v_hist from public.order_status_history where order_id = v_order.id;

  if v_assigned is distinct from v_b then
    raise exception 'CASE22 FAILED: N の担当が B でない (%)', v_assigned;
  end if;
  if v_order.agent_id is distinct from v_b or v_order.referral_agent_id is distinct from v_b then
    raise exception 'CASE22 FAILED: 注文の帰属/紹介元が B でない (%/%)', v_order.agent_id, v_order.referral_agent_id;
  end if;
  if v_order.customer_id is distinct from v_n or v_order.status <> 'received' then
    raise exception 'CASE22 FAILED: 注文の顧客/ステータスが不正';
  end if;
  if v_stock <> 8 then raise exception 'CASE22 FAILED: 在庫が減っていない (%)', v_stock; end if;
  if v_hist <> 1 then raise exception 'CASE22 FAILED: 注文受付の履歴が 1 件でない (%)', v_hist; end if;

  perform set_config('tm.customer_n', v_n::text, true);
  perform set_config('tm.order_n', v_order.id::text, true);
  raise notice 'CASE22 OK: 新規顧客は紹介リンクの代理店が担当に確定し、注文もその代理店に帰属';
end $$;

-- ============================================================================
-- CASE23 : B 担当の既存顧客 X が、兄弟枝 S の紹介リンクから別の氏名で注文
--          → 帰属は現担当 B のまま (原則4)。担当・顧客マスタは変わらない。
--          応答は新規時と同じ形で、誰が担当かは出ない (原則6)。
-- ============================================================================

set local role anon;

do $$
declare v_res jsonb; v_keys text;
begin
  v_res := public.treemerce_place_order(
    'TM-TEST-S',
    jsonb_build_array(jsonb_build_object('product_id', current_setting('tm.p1'), 'quantity', 1)),
    '別人太郎', '北海道テスト市1-1', 'tm-test-x@treemerce.test', null);

  select string_agg(k, ',' order by k) into v_keys from jsonb_object_keys(v_res) k;
  if v_keys is distinct from current_setting('tm.keys_new') then
    raise exception 'CASE23 FAILED: 既存顧客と新規顧客で応答の形が異なる (% / %)',
      v_keys, current_setting('tm.keys_new');
  end if;
  if v_res::text like '%' || current_setting('tm.agent_b_public') || '%' or v_res::text like '%テスト代理店%'
     or v_res::text like '%山田太郎%' then
    raise exception 'CASE23 FAILED: 担当代理店または既存の顧客情報が応答に含まれる (%)', v_res;
  end if;
  perform set_config('tm.order_x_no', v_res ->> 'order_no', true);
end $$;

reset role;

do $$
declare v_order public.orders%rowtype; v_name text; v_assigned uuid; v_cnt int; v_x uuid;
begin
  v_x := current_setting('tm.customer_x')::uuid;
  select * into v_order from public.orders where order_no = current_setting('tm.order_x_no');

  if v_order.customer_id is distinct from v_x then
    raise exception 'CASE23 FAILED: 識別子一致の既存顧客 X に紐づいていない';
  end if;
  if v_order.agent_id is distinct from current_setting('tm.agent_b')::uuid then
    raise exception 'CASE23 FAILED: 帰属が現担当 B でない (%)', v_order.agent_id;
  end if;
  if v_order.referral_agent_id is distinct from '10000000-0000-4000-8000-000000000006'::uuid then
    raise exception 'CASE23 FAILED: 紹介元 S が記録されていない';
  end if;
  if not v_order.identity_mismatch then
    raise exception 'CASE23 FAILED: 氏名不一致フラグが立っていない';
  end if;

  select full_name into v_name from public.customers where id = v_x;
  if v_name <> '山田太郎' then raise exception 'CASE23 FAILED: 顧客マスタが上書きされた (%)', v_name; end if;

  select assigned_agent_id into v_assigned from public.customer_assignments
  where customer_id = v_x and status = 'active';
  if v_assigned is distinct from current_setting('tm.agent_b')::uuid then
    raise exception 'CASE23 FAILED: 注文で担当が変わった';
  end if;

  select count(*) into v_cnt from public.customers where email_normalized = 'tm-test-x@treemerce.test';
  if v_cnt <> 1 then raise exception 'CASE23 FAILED: 顧客が重複作成された (%)', v_cnt; end if;

  perform set_config('tm.order_x', v_order.id::text, true);
  raise notice 'CASE23 OK: 別代理店リンク経由でも帰属は現担当のまま。担当・マスタ不変、応答は中立';
end $$;

-- ============================================================================
-- CASE24 : 在庫不足・非公開商品・数量超過・識別子なしは拒否され、注文は作られない
-- ============================================================================

set local role anon;

do $$
declare v_ok boolean; v_before int; v_after int;
begin
  -- anon は orders を数えられないので SECURITY DEFINER の公開RPCの結果だけで判定する
  v_ok := false;
  begin
    perform public.treemerce_place_order(current_setting('tm.agent_b_public'),
      jsonb_build_array(jsonb_build_object('product_id', current_setting('tm.p2'), 'quantity', 2)),
      '在庫太郎', '大阪府テスト1-1', 'tm-test-stock@treemerce.test');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE24 FAILED: 在庫不足で注文できた'; end if;

  v_ok := false;
  begin
    perform public.treemerce_place_order(current_setting('tm.agent_b_public'),
      jsonb_build_array(jsonb_build_object('product_id', current_setting('tm.p3'), 'quantity', 1)),
      '非公開太郎', '大阪府テスト1-1', 'tm-test-hidden@treemerce.test');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE24 FAILED: 非公開商品を注文できた'; end if;

  v_ok := false;
  begin
    perform public.treemerce_place_order(current_setting('tm.agent_b_public'),
      jsonb_build_array(jsonb_build_object('product_id', current_setting('tm.p1'), 'quantity', 100)),
      '大量太郎', '大阪府テスト1-1', 'tm-test-bulk@treemerce.test');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE24 FAILED: 数量 100 で注文できた'; end if;

  v_ok := false;
  begin
    perform public.treemerce_place_order(current_setting('tm.agent_b_public'),
      jsonb_build_array(jsonb_build_object('product_id', current_setting('tm.p1'), 'quantity', 1)),
      '名前だけ太郎', '大阪府テスト1-1', null, null);
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE24 FAILED: 識別子なし (氏名のみ) で注文できた'; end if;

  v_ok := false;
  begin
    perform public.treemerce_place_order('TM-TEST-NOPE',
      jsonb_build_array(jsonb_build_object('product_id', current_setting('tm.p1'), 'quantity', 1)),
      'リンク太郎', '大阪府テスト1-1', 'tm-test-link@treemerce.test');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE24 FAILED: 無効な紹介リンクで注文できた'; end if;
end $$;

reset role;

do $$
declare v_cnt int; v_stock int;
begin
  select count(*) into v_cnt from public.orders;
  if v_cnt <> 2 then raise exception 'CASE24 FAILED: 拒否されたはずの注文が作られた (orders=%)', v_cnt; end if;
  select count(*) into v_cnt from public.customers
  where email_normalized in ('tm-test-stock@treemerce.test', 'tm-test-hidden@treemerce.test',
                             'tm-test-bulk@treemerce.test', 'tm-test-link@treemerce.test');
  if v_cnt <> 0 then raise exception 'CASE24 FAILED: 拒否された注文で顧客が作られた (%)', v_cnt; end if;
  select stock into v_stock from public.products where id = current_setting('tm.p2')::uuid;
  if v_stock <> 1 then raise exception 'CASE24 FAILED: 拒否された注文で在庫が動いた (%)', v_stock; end if;
  raise notice 'CASE24 OK: 在庫不足・非公開・数量超過・識別子なし・無効リンクはすべて拒否され、副作用なし';
end $$;

-- ============================================================================
-- CASE25 : 注文の帰属代理店・金額は postgres 直接操作でも変更できない。削除も不可。
--          明細・ステータス履歴は改ざんできない。
-- ============================================================================

do $$
declare v_ok boolean; v_o uuid;
begin
  v_o := current_setting('tm.order_x')::uuid;

  v_ok := false;
  begin
    update public.orders set agent_id = '10000000-0000-4000-8000-000000000006'::uuid where id = v_o;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE25 FAILED: 注文の帰属代理店を書き換えられた'; end if;

  v_ok := false;
  begin
    update public.orders set total = 1, subtotal = 1, shipping_fee = 0 where id = v_o;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE25 FAILED: 注文金額を書き換えられた'; end if;

  v_ok := false;
  begin
    delete from public.orders where id = v_o;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE25 FAILED: 注文を削除できた'; end if;

  v_ok := false;
  begin
    update public.order_items set quantity = 5, amount = unit_price * 5 where order_id = v_o;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE25 FAILED: 注文明細を書き換えられた'; end if;

  v_ok := false;
  begin
    update public.order_status_history set reason = '改ざん' where order_id = v_o;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE25 FAILED: ステータス履歴を書き換えられた'; end if;

  raise notice 'CASE25 OK: 帰属代理店・金額・注文番号は不変、削除不可、明細と履歴は改ざん不可';
end $$;

-- ============================================================================
-- CASE26 : 注文の実データは現担当 B だけが見られる。
--          傘上 A・紹介元 S・傘下 C からは 0 行。紹介元列は B にも見えない。
-- ============================================================================

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_cnt int; v_name text; v_ok boolean; v_ref uuid;
begin
  select count(*) into v_cnt from public.orders where id = current_setting('tm.order_x')::uuid;
  if v_cnt <> 1 then raise exception 'CASE26 FAILED: 現担当 B が担当顧客 X の注文を見られない'; end if;
  select ship_name into v_name from public.orders where id = current_setting('tm.order_x')::uuid;
  if v_name is distinct from '別人太郎' then raise exception 'CASE26 FAILED: B から配送先氏名が見えない'; end if;
  select count(*) into v_cnt from public.order_items where order_id = current_setting('tm.order_x')::uuid;
  if v_cnt <> 1 then raise exception 'CASE26 FAILED: B が明細を見られない'; end if;

  v_ok := false;
  begin
    select referral_agent_id into v_ref from public.orders limit 1;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE26 FAILED: 一般代理店が referral_agent_id を参照できた'; end if;

  v_ok := false;
  begin
    perform identity_mismatch from public.orders limit 1;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE26 FAILED: 一般代理店が identity_mismatch を参照できた'; end if;
end $$;

reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_cnt int;
begin
  select count(*) into v_cnt from public.orders;
  if v_cnt <> 0 then raise exception 'CASE26 FAILED: 傘上 A に傘下 B 担当顧客の注文が見えた (%)', v_cnt; end if;
  select count(*) into v_cnt from public.order_items;
  if v_cnt <> 0 then raise exception 'CASE26 FAILED: 傘上 A に明細が見えた (%)', v_cnt; end if;
end $$;

reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000006","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_cnt int;
begin
  select count(*) into v_cnt from public.orders;
  if v_cnt <> 0 then raise exception 'CASE26 FAILED: 紹介元 S に他代理店担当顧客の注文が見えた (%)', v_cnt; end if;
end $$;

reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000004","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_cnt int;
begin
  select count(*) into v_cnt from public.orders;
  if v_cnt <> 0 then raise exception 'CASE26 FAILED: 傘下 C に B 担当顧客の注文が見えた (%)', v_cnt; end if;
  raise notice 'CASE26 OK: 注文の実データは現担当のみ。傘上・紹介元・傘下は 0 行、紹介元列は代理店に非公開';
end $$;

reset role;

-- ============================================================================
-- CASE27 : 一般代理店・一般admin は注文/商品/設定を書き込めない
-- ============================================================================

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_ok boolean; v_o uuid;
begin
  v_o := current_setting('tm.order_x')::uuid;

  v_ok := false;
  begin update public.orders set status = 'completed' where id = v_o;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE27 FAILED: 代理店が注文ステータスを直接更新できた'; end if;

  v_ok := false;
  begin
    insert into public.products (name, price) values ('代理店の商品', 1);
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE27 FAILED: 代理店が商品を直接登録できた'; end if;

  v_ok := false;
  begin perform public.treemerce_admin_set_order_status(v_o, 'payment_confirmed', '代理店による入金確認');
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE27 FAILED: 代理店がステータス変更RPCを実行できた'; end if;

  v_ok := false;
  begin perform public.treemerce_admin_upsert_product('代理店の商品', 1, 1, true);
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE27 FAILED: 代理店が商品登録RPCを実行できた'; end if;

  v_ok := false;
  begin perform public.treemerce_admin_update_shop_settings(
    jsonb_build_object('bank_account_number', '9999999'), '口座差し替え');
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE27 FAILED: 代理店が振込先を変更できた'; end if;

  v_ok := false;
  begin perform public.treemerce_admin_get_order(v_o);
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE27 FAILED: 代理店が管理者用注文詳細 (紹介元を含む) を取得できた'; end if;
end $$;

reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000008","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_ok boolean;
begin
  v_ok := false;
  begin perform public.treemerce_admin_set_order_status(
    current_setting('tm.order_x')::uuid, 'payment_confirmed', '一般adminによる入金確認');
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE27 FAILED: 一般adminがステータス変更RPCを実行できた'; end if;

  v_ok := false;
  begin perform public.treemerce_admin_upsert_product('一般adminの商品', 1, 1, true);
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE27 FAILED: 一般adminが商品登録RPCを実行できた'; end if;

  raise notice 'CASE27 OK: 一般代理店・一般adminは注文/商品/振込先を書き込めない';
end $$;

reset role;

-- ============================================================================
-- CASE28 : super_admin のステータス変更。正しい遷移のみ許可、理由必須、
--          履歴と監査ログの両方に記録。キャンセルで在庫が戻る。帰属は不変。
-- ============================================================================

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  v_n uuid; v_x uuid; v_ok boolean; v_res jsonb; v_cnt int; v_stock_before int; v_stock_after int;
  v_paid timestamptz; v_agent uuid;
begin
  v_n := current_setting('tm.order_n')::uuid;
  v_x := current_setting('tm.order_x')::uuid;

  v_res := public.treemerce_admin_set_order_status(v_n, 'payment_confirmed', '入金を確認');
  if v_res ->> 'status' <> 'payment_confirmed' then
    raise exception 'CASE28 FAILED: 入金確認に変更できない (%)', v_res;
  end if;
  select paid_at, agent_id into v_paid, v_agent from public.orders where id = v_n;
  if v_paid is null then raise exception 'CASE28 FAILED: paid_at が記録されていない'; end if;
  if v_agent is distinct from current_setting('tm.agent_b')::uuid then
    raise exception 'CASE28 FAILED: ステータス変更で帰属が変わった';
  end if;

  select count(*) into v_cnt from public.order_status_history where order_id = v_n;
  if v_cnt <> 2 then raise exception 'CASE28 FAILED: ステータス履歴が 2 件でない (%)', v_cnt; end if;
  select count(*) into v_cnt from public.admin_audit_logs
  where target_table = 'orders' and target_id = v_n and action = 'order.status_change';
  if v_cnt <> 1 then raise exception 'CASE28 FAILED: 監査ログに記録されていない (%)', v_cnt; end if;

  v_ok := false;
  begin perform public.treemerce_admin_set_order_status(v_n, 'received', '戻す');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE28 FAILED: 入金確認済み → 注文受付 に戻せた'; end if;

  v_ok := false;
  begin perform public.treemerce_admin_set_order_status(v_n, 'completed', '発送を飛ばして完了');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE28 FAILED: 発送済みを飛ばして完了にできた'; end if;

  v_ok := false;
  begin perform public.treemerce_admin_set_order_status(v_n, 'shipped', null);
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE28 FAILED: 理由なしでステータスを変更できた'; end if;

  select stock into v_stock_before from public.products where id = current_setting('tm.p1')::uuid;
  perform public.treemerce_admin_set_order_status(v_x, 'cancelled', '本人確認が取れないためキャンセル');
  select stock into v_stock_after from public.products where id = current_setting('tm.p1')::uuid;
  if v_stock_after <> v_stock_before + 1 then
    raise exception 'CASE28 FAILED: キャンセルで在庫が戻っていない (% → %)', v_stock_before, v_stock_after;
  end if;

  v_ok := false;
  begin perform public.treemerce_admin_set_order_status(v_x, 'payment_confirmed', 'キャンセル後に入金確認');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE28 FAILED: キャンセル済みの注文を復活できた'; end if;

  v_res := public.treemerce_admin_get_order(v_x);
  if v_res -> 'referral_agent' ->> 'public_id' is distinct from 'TM-TEST-S'
     or (v_res -> 'order' ->> 'identity_mismatch')::boolean is not true then
    raise exception 'CASE28 FAILED: super_admin の注文詳細に紹介元/本人確認フラグが無い (%)', v_res;
  end if;

  raise notice 'CASE28 OK: 正しい遷移のみ・理由必須・履歴と監査ログに記録・キャンセルで在庫復元・帰属不変';
end $$;

reset role;

-- ============================================================================
-- CASE29 : ADMIN が N の担当を B → C に変更すると、過去注文の実データは
--          新担当 C にだけ見え、旧担当 B からは見えなくなる。帰属は B のまま。
-- ============================================================================

savepoint before_case29;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;

select public.treemerce_admin_transfer_customer(
  current_setting('tm.customer_n')::uuid, current_setting('tm.agent_c')::uuid, '担当変更テスト');

reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_cnt int; v_sum jsonb;
begin
  select count(*) into v_cnt from public.orders where id = current_setting('tm.order_n')::uuid;
  if v_cnt <> 0 then raise exception 'CASE29 FAILED: 旧担当 B に移管済み顧客の注文が見えた'; end if;

  v_sum := public.treemerce_agent_order_summary('all');
  if (v_sum -> 'own_transferred' ->> 'suppressed')::boolean is not true then
    raise exception 'CASE29 FAILED: 移管済み顧客分の売上が n<5 で丸められていない (%)', v_sum;
  end if;
  if v_sum::text like '%新規花子%' or v_sum::text like '%tm-test-n%' then
    raise exception 'CASE29 FAILED: 移管済み顧客の PII が集計に含まれる';
  end if;
end $$;

reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000004","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_cnt int;
begin
  select count(*) into v_cnt from public.orders where id = current_setting('tm.order_n')::uuid;
  if v_cnt <> 1 then raise exception 'CASE29 FAILED: 新担当 C が担当顧客の過去注文を見られない'; end if;
end $$;

reset role;

do $$
declare v_agent uuid;
begin
  select agent_id into v_agent from public.orders where id = current_setting('tm.order_n')::uuid;
  if v_agent is distinct from current_setting('tm.agent_b')::uuid then
    raise exception 'CASE29 FAILED: 担当変更で注文の帰属が変わった (%)', v_agent;
  end if;
  raise notice 'CASE29 OK: 担当変更後、実データは新担当のみ・旧担当は匿名集計のみ・帰属は旧担当のまま';
end $$;

rollback to savepoint before_case29;

-- ============================================================================
-- CASE30 : 代理店向け注文サマリ。傘下は件数・金額のみで n<5 は丸め、代理店別内訳なし。
--          集計は入金確認済み以降のみ。
-- ============================================================================

-- C 担当の既存顧客 Z が C のリンクから注文 (各 5000 + 送料 800)。
-- 未入金は 1 連絡先あたり 3 件まで (0013) なので、3 件注文 → 入金確認 → 2 件注文 の順に行う。
select set_config('tm.agent_c_public',
  (select public_id from public.agents where id = current_setting('tm.agent_c')::uuid), true);

set local role anon;

do $$
declare i int;
begin
  for i in 1..3 loop
    perform public.treemerce_place_order(
      current_setting('tm.agent_c_public'),
      jsonb_build_array(jsonb_build_object('product_id', current_setting('tm.p1'), 'quantity', 1)),
      '鈴木一郎', '東京都テスト1-1', 'tm-test-z@treemerce.test');
  end loop;
end $$;

reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_o uuid;
begin
  for v_o in
    select o.id from public.orders o
    join public.customers c on c.id = o.customer_id
    where c.email_normalized = 'tm-test-z@treemerce.test' and o.status = 'received'
    order by o.ordered_at
  loop
    perform public.treemerce_admin_set_order_status(v_o, 'payment_confirmed', '入金を確認');
  end loop;
end $$;

reset role;

set local role anon;

do $$
declare i int;
begin
  for i in 1..2 loop
    perform public.treemerce_place_order(
      current_setting('tm.agent_c_public'),
      jsonb_build_array(jsonb_build_object('product_id', current_setting('tm.p1'), 'quantity', 1)),
      '鈴木一郎', '東京都テスト1-1', 'tm-test-z@treemerce.test');
  end loop;
end $$;

reset role;

-- 入金確認済みを 4 件にする → 傘下は n<5 で丸め
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_o uuid;
begin
  select o.id into v_o from public.orders o
  join public.customers c on c.id = o.customer_id
  where c.email_normalized = 'tm-test-z@treemerce.test' and o.status = 'received'
  order by o.ordered_at limit 1;
  perform public.treemerce_admin_set_order_status(v_o, 'payment_confirmed', '入金を確認');
end $$;

reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_sum jsonb; v_txt text;
begin
  v_sum := public.treemerce_agent_order_summary('all');
  v_txt := v_sum::text;
  if (v_sum -> 'subtree' ->> 'suppressed')::boolean is not true then
    raise exception 'CASE30 FAILED: 傘下 4 件が丸められていない (%)', v_sum;
  end if;
  if (v_sum -> 'own_current' ->> 'count')::int <> 1 then
    raise exception 'CASE30 FAILED: 自分の担当顧客の入金確認済み注文が 1 件でない (%)', v_sum;
  end if;
  if v_txt like '%' || current_setting('tm.agent_c') || '%' or v_txt like '%鈴木一郎%'
     or v_txt like '%' || current_setting('tm.agent_c_public') || '%' then
    raise exception 'CASE30 FAILED: 傘下代理店・顧客を特定できる情報が含まれる (%)', v_sum;
  end if;
end $$;

reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_o uuid;
begin
  select o.id into v_o from public.orders o
  join public.customers c on c.id = o.customer_id
  where c.email_normalized = 'tm-test-z@treemerce.test' and o.status = 'received'
  order by o.ordered_at limit 1;
  perform public.treemerce_admin_set_order_status(v_o, 'payment_confirmed', '入金を確認');
end $$;

reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_sum jsonb; v_ok boolean;
begin
  v_sum := public.treemerce_agent_order_summary('all');
  if (v_sum -> 'subtree' ->> 'suppressed')::boolean
     or (v_sum -> 'subtree' ->> 'count')::int <> 5
     or (v_sum -> 'subtree' ->> 'total')::numeric <> 29000 then
    raise exception 'CASE30 FAILED: 傘下 5 件の件数・金額が正しくない (%)', v_sum;
  end if;
  if v_sum ? 'by_agent' or v_sum ? 'agents' or v_sum ? 'customers' then
    raise exception 'CASE30 FAILED: 代理店別内訳が含まれる';
  end if;

  v_ok := false;
  begin perform public.treemerce_agent_order_summary('forever');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE30 FAILED: 不正な期間指定が通った'; end if;
end $$;

reset role;

do $$
declare v_vol char;
begin
  select provolatile into v_vol from pg_proc
  where oid = 'public.treemerce_agent_order_summary(text)'::regprocedure;
  if v_vol <> 's' then raise exception 'CASE30 FAILED: 注文サマリが STABLE でない (%)', v_vol; end if;
  raise notice 'CASE30 OK: 傘下は件数・金額のみ・n<5丸め・内訳なし・入金確認済み以降のみ・STABLE';
end $$;

-- ============================================================================
-- CASE31 : 客層分析に購入カテゴリ・金額帯が反映される (入金確認済み以降のみ)。
--          未入金の注文は集計されない。金額帯も n<5 は丸め。STABLE のまま。
-- ============================================================================

-- 未入金のまま残す注文: N が美容液 (beauty) を 1 点
set local role anon;
select public.treemerce_place_order(current_setting('tm.agent_b_public'),
  jsonb_build_array(jsonb_build_object('product_id', current_setting('tm.p2'), 'quantity', 1)),
  '新規花子', '東京都千代田区テスト1-1', 'tm-test-n@treemerce.test');
reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_res jsonb; v_txt text; v_merged int;
begin
  v_res := public.treemerce_customer_demographics(null, 'all');
  v_txt := v_res::text;

  -- 0013: 購入カテゴリは購入者の人数で数える。B 傘下で health を買ったのは X / N / Z の 3 人
  --       → n<5 なので「該当データ少数」1 つに丸められ、人数は 3。
  --       未入金の beauty (N) が集計されていれば 4 になる。
  if (v_res -> 'product_category')::text like '%"health"%' then
    raise exception 'CASE31 FAILED: 購入者 3 人のカテゴリが丸められていない (%)', v_res -> 'product_category';
  end if;
  select (e ->> 'count')::int into v_merged
  from jsonb_array_elements(v_res -> 'product_category') e where e ->> 'key' = '該当データ少数';
  if v_merged is distinct from 3 then
    raise exception 'CASE31 FAILED: 購入カテゴリが購入者の人数 (3) で数えられていない (%)',
      v_res -> 'product_category';
  end if;
  if not (v_res ? 'amount_band') or (v_res -> 'amount_band')::text not like '%該当データ少数%' then
    raise exception 'CASE31 FAILED: 金額帯が無い、または少数セグメントが丸められていない (%)',
      v_res -> 'amount_band';
  end if;
  if (v_res ->> 'purchasing_customers')::int <> 3 or v_res -> 'total_sales' <> 'null'::jsonb then
    raise exception 'CASE31 FAILED: 購入者 n<5 なのに売上合計が返った (%)', v_res;
  end if;
  if v_txt like '%999999%' or v_txt like '%山田太郎%' or v_txt like '%鈴木一郎%'
     or v_txt like '%' || current_setting('tm.agent_c') || '%' then
    raise exception 'CASE31 FAILED: 個人の購入額・PII・傘下代理店IDが含まれる';
  end if;

  raise notice 'CASE31 OK: 客層分析に購入カテゴリ(購入者の人数)・金額帯を反映 (入金確認済み以降のみ・n<5丸め・内訳なし)';
end $$;

reset role;

-- ============================================================================
-- CASE32 : 支払期限を過ぎた未入金注文は自動キャンセルされ、在庫が戻る。
--          理由は履歴と監査ログの両方に残る。期限内の注文は残る。
--          自動キャンセル関数は anon / authenticated から実行できない。
-- ============================================================================

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;

select set_config('tm.p4',
  public.treemerce_admin_upsert_product('テスト定番商品', 3000, 100, true, 'household') ->> 'id', true);

reset role;
select set_config('request.jwt.claims', '', true);

-- 期限切れ / 期限内の未入金注文を DB 管理者として直接用意する (時刻を戻せないため)
do $$
declare v_n uuid; v_b uuid; v_expired uuid; v_live uuid; v_today date;
begin
  v_n := current_setting('tm.customer_n')::uuid;
  v_b := current_setting('tm.agent_b')::uuid;
  v_today := (now() at time zone 'Asia/Tokyo')::date;

  insert into public.orders (customer_id, agent_id, referral_agent_id, status, subtotal, shipping_fee,
                             total, ship_name, ship_address, contact_email, ordered_at, payment_due_date)
  values (v_n, v_b, v_b, 'received', 6000, 0, 6000, '新規花子', '東京都千代田区テスト1-1',
          'tm-test-expired@treemerce.test', now() - interval '10 days', v_today - 1)
  returning id into v_expired;
  insert into public.order_items (order_id, product_id, product_name, product_category,
                                  unit_price, quantity, amount)
  values (v_expired, current_setting('tm.p4')::uuid, 'テスト定番商品', 'household', 3000, 2, 6000);

  insert into public.orders (customer_id, agent_id, referral_agent_id, status, subtotal, shipping_fee,
                             total, ship_name, ship_address, contact_email, ordered_at, payment_due_date)
  values (v_n, v_b, v_b, 'received', 3000, 0, 3000, '新規花子', '東京都千代田区テスト1-1',
          'tm-test-live@treemerce.test', now() - interval '7 days', v_today)
  returning id into v_live;
  insert into public.order_items (order_id, product_id, product_name, product_category,
                                  unit_price, quantity, amount)
  values (v_live, current_setting('tm.p4')::uuid, 'テスト定番商品', 'household', 3000, 1, 3000);

  -- 注文受付で確保されたのと同じ状態にする
  update public.products set stock = stock - 3 where id = current_setting('tm.p4')::uuid;

  perform set_config('tm.order_expired', v_expired::text, true);
  perform set_config('tm.order_live', v_live::text, true);
end $$;

set local role anon;
do $$
declare v_ok boolean := false;
begin
  begin perform public.treemerce_system_cancel_expired_orders();
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE32 FAILED: anon が自動キャンセル関数を実行できた'; end if;
end $$;
reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;
do $$
declare v_ok boolean := false;
begin
  begin perform public.treemerce_system_cancel_expired_orders();
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE32 FAILED: super_admin のセッションから自動キャンセル関数を直接実行できた'; end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

do $$
declare
  v_cnt int; v_status public.order_status; v_stock int; v_reason text; v_role text;
  v_audit int; v_due date;
begin
  v_cnt := public.treemerce_system_cancel_expired_orders();
  if v_cnt <> 1 then raise exception 'CASE32 FAILED: 自動キャンセル件数が 1 でない (%)', v_cnt; end if;

  select status into v_status from public.orders where id = current_setting('tm.order_expired')::uuid;
  if v_status <> 'cancelled' then raise exception 'CASE32 FAILED: 期限切れ注文がキャンセルされていない'; end if;
  select status into v_status from public.orders where id = current_setting('tm.order_live')::uuid;
  if v_status <> 'received' then raise exception 'CASE32 FAILED: 期限当日の注文までキャンセルされた'; end if;

  select stock into v_stock from public.products where id = current_setting('tm.p4')::uuid;
  if v_stock <> 99 then raise exception 'CASE32 FAILED: 自動キャンセルで在庫が戻っていない (%)', v_stock; end if;

  select reason, changed_by_role into v_reason, v_role from public.order_status_history
  where order_id = current_setting('tm.order_expired')::uuid and to_status = 'cancelled';
  if v_reason is distinct from '支払期限切れによる自動キャンセル' or v_role <> 'system' then
    raise exception 'CASE32 FAILED: 履歴の理由/実行者が不正 (% / %)', v_reason, v_role;
  end if;

  select count(*) into v_audit from public.admin_audit_logs
  where target_id = current_setting('tm.order_expired')::uuid and action = 'order.auto_cancel'
    and reason = '支払期限切れによる自動キャンセル' and (after_state ->> 'restocked')::boolean;
  if v_audit <> 1 then raise exception 'CASE32 FAILED: 監査ログに自動キャンセルが残っていない'; end if;

  -- 注文受付では支払期限が注文時点で確定している (日本時間の今日 + 7 日)
  select payment_due_date into v_due from public.orders
  where order_no = current_setting('tm.order_n_no');
  if v_due is distinct from ((now() at time zone 'Asia/Tokyo')::date + 7) then
    raise exception 'CASE32 FAILED: 注文時点の支払期限が保存されていない (%)', v_due;
  end if;

  -- 2 回目は何もしない (冪等)
  if public.treemerce_system_cancel_expired_orders() <> 0 then
    raise exception 'CASE32 FAILED: 2 回目の実行で再度キャンセルした';
  end if;

  raise notice 'CASE32 OK: 期限切れの未入金注文は自動キャンセル・在庫復元・履歴と監査ログに理由。期限内は残る。一般ロールは実行不可';
end $$;

-- ============================================================================
-- CASE33 : 同一メール / 同一電話番号の未入金注文は 3 件まで。
--          4 件目は新規・既存顧客どちらでも同じ中立メッセージで拒否される (原則6)。
-- ============================================================================

set local role anon;

do $$
declare
  i int; v_ok boolean; v_msg_new text; v_msg_existing text; v_msg_phone text;
  v_items jsonb := jsonb_build_array(jsonb_build_object('product_id', current_setting('tm.p4'), 'quantity', 1));
begin
  -- 新しい連絡先 (初回注文で顧客が作られる)
  for i in 1..3 loop
    perform public.treemerce_place_order(current_setting('tm.agent_b_public'), v_items,
      '連続太郎', '神奈川県テスト1-1', 'tm-test-rate@treemerce.test');
  end loop;
  v_ok := false;
  begin
    perform public.treemerce_place_order(current_setting('tm.agent_b_public'), v_items,
      '連続太郎', '神奈川県テスト1-1', 'tm-test-rate@treemerce.test');
  exception when invalid_parameter_value then v_ok := true; v_msg_new := sqlerrm; end;
  if not v_ok then raise exception 'CASE33 FAILED: 新しい連絡先で 4 件目の未入金注文ができた'; end if;

  -- 既存顧客 Y (A の担当) の連絡先
  for i in 1..3 loop
    perform public.treemerce_place_order('TM-TEST-A', v_items,
      '佐藤花子', '大阪府テスト1-1', 'tm-test-y@treemerce.test');
  end loop;
  v_ok := false;
  begin
    perform public.treemerce_place_order('TM-TEST-A', v_items,
      '佐藤花子', '大阪府テスト1-1', 'tm-test-y@treemerce.test');
  exception when invalid_parameter_value then v_ok := true; v_msg_existing := sqlerrm; end;
  if not v_ok then raise exception 'CASE33 FAILED: 既存顧客の連絡先で 4 件目の未入金注文ができた'; end if;

  if v_msg_new is distinct from v_msg_existing then
    raise exception 'CASE33 FAILED: 新規と既存で拒否メッセージが異なる (% / %)', v_msg_new, v_msg_existing;
  end if;
  if v_msg_new not like 'TREEMERCE_ORDER_UNAVAILABLE:%'
     or v_msg_new like '%担当%' or v_msg_new like '%登録済%' then
    raise exception 'CASE33 FAILED: 中立でない拒否メッセージ (%)', v_msg_new;
  end if;

  -- 同一電話番号 (メールアドレスを変えてもすり抜けられない)
  for i in 1..3 loop
    perform public.treemerce_place_order(current_setting('tm.agent_b_public'), v_items,
      '電話次郎', '千葉県テスト1-1', null, '080-1234-0000');
  end loop;
  v_ok := false;
  begin
    perform public.treemerce_place_order(current_setting('tm.agent_b_public'), v_items,
      '電話次郎', '千葉県テスト1-1', 'tm-test-phone-other@treemerce.test', '08012340000');
  exception when invalid_parameter_value then v_ok := true; v_msg_phone := sqlerrm; end;
  if not v_ok then raise exception 'CASE33 FAILED: 同一電話番号で 4 件目の未入金注文ができた'; end if;
  if v_msg_phone is distinct from v_msg_new then
    raise exception 'CASE33 FAILED: 電話番号での拒否メッセージが異なる (%)', v_msg_phone;
  end if;
end $$;

reset role;

do $$
declare v_cnt int;
begin
  select count(*) into v_cnt from public.orders where lower(contact_email) = 'tm-test-rate@treemerce.test';
  if v_cnt <> 3 then raise exception 'CASE33 FAILED: 拒否された注文が作られた (%)', v_cnt; end if;
  select count(*) into v_cnt from public.customers
  where email_normalized = 'tm-test-phone-other@treemerce.test';
  if v_cnt <> 0 then raise exception 'CASE33 FAILED: 拒否された注文で顧客が作られた'; end if;
end $$;

-- 1 件入金確認すれば、未入金が 2 件になるので再び注文できる
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;
do $$
declare v_o uuid;
begin
  select id into v_o from public.orders
  where lower(contact_email) = 'tm-test-rate@treemerce.test' and status = 'received'
  order by ordered_at limit 1;
  perform public.treemerce_admin_set_order_status(v_o, 'payment_confirmed', '入金を確認');
end $$;
reset role;

set local role anon;
do $$
declare v_res jsonb;
begin
  v_res := public.treemerce_place_order(current_setting('tm.agent_b_public'),
    jsonb_build_array(jsonb_build_object('product_id', current_setting('tm.p4'), 'quantity', 1)),
    '連続太郎', '神奈川県テスト1-1', 'tm-test-rate@treemerce.test');
  if v_res ->> 'status' <> 'received' then
    raise exception 'CASE33 FAILED: 入金確認後も注文できない (%)', v_res;
  end if;
  raise notice 'CASE33 OK: 未入金は連絡先ごとに 3 件まで。超過は新規/既存とも同一の中立メッセージ。入金確認で枠が戻る';
end $$;
reset role;

-- ============================================================================
-- CASE34 : 発送済みからのキャンセルは在庫を自動で戻さない。
--          p_restock の指定が必須で、true のときだけ在庫を戻す。監査ログに選択が残る。
-- ============================================================================

set local role anon;
do $$
begin
  perform public.treemerce_place_order(current_setting('tm.agent_b_public'),
    jsonb_build_array(jsonb_build_object('product_id', current_setting('tm.p4'), 'quantity', 2)),
    '発送一郎', '埼玉県テスト1-1', 'tm-test-ship1@treemerce.test');
  perform public.treemerce_place_order(current_setting('tm.agent_b_public'),
    jsonb_build_array(jsonb_build_object('product_id', current_setting('tm.p4'), 'quantity', 3)),
    '発送二郎', '埼玉県テスト1-1', 'tm-test-ship2@treemerce.test');
  perform public.treemerce_place_order(current_setting('tm.agent_b_public'),
    jsonb_build_array(jsonb_build_object('product_id', current_setting('tm.p4'), 'quantity', 1)),
    '入金三郎', '埼玉県テスト1-1', 'tm-test-ship3@treemerce.test');
end $$;
reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  v_o1 uuid; v_o2 uuid; v_o3 uuid; v_ok boolean; v_before int; v_after int; v_res jsonb; v_audit int;
begin
  select id into v_o1 from public.orders where contact_email = 'tm-test-ship1@treemerce.test';
  select id into v_o2 from public.orders where contact_email = 'tm-test-ship2@treemerce.test';
  select id into v_o3 from public.orders where contact_email = 'tm-test-ship3@treemerce.test';

  perform public.treemerce_admin_set_order_status(v_o1, 'payment_confirmed', '入金を確認');
  perform public.treemerce_admin_set_order_status(v_o1, 'shipped', '発送');
  perform public.treemerce_admin_set_order_status(v_o2, 'payment_confirmed', '入金を確認');
  perform public.treemerce_admin_set_order_status(v_o2, 'shipped', '発送');

  -- p_restock 未指定は拒否
  v_ok := false;
  begin perform public.treemerce_admin_set_order_status(v_o1, 'cancelled', '返品');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE34 FAILED: 発送済みのキャンセルが p_restock 未指定で通った'; end if;

  -- p_restock = false: 在庫は戻らない
  select stock into v_before from public.products where id = current_setting('tm.p4')::uuid;
  v_res := public.treemerce_admin_set_order_status(v_o1, 'cancelled', '返品なし (商品破損)', false);
  select stock into v_after from public.products where id = current_setting('tm.p4')::uuid;
  if v_after <> v_before or (v_res ->> 'restocked')::boolean then
    raise exception 'CASE34 FAILED: p_restock=false なのに在庫が戻った (% → %)', v_before, v_after;
  end if;
  select count(*) into v_audit from public.admin_audit_logs
  where target_id = v_o1 and action = 'order.status_change'
    and after_state ->> 'status' = 'cancelled' and (after_state ->> 'restocked')::boolean = false;
  if v_audit <> 1 then raise exception 'CASE34 FAILED: 在庫を戻さない選択が監査ログに残っていない'; end if;

  -- p_restock = true: 在庫が戻る
  select stock into v_before from public.products where id = current_setting('tm.p4')::uuid;
  perform public.treemerce_admin_set_order_status(v_o2, 'cancelled', '返品受領', true);
  select stock into v_after from public.products where id = current_setting('tm.p4')::uuid;
  if v_after <> v_before + 3 then
    raise exception 'CASE34 FAILED: p_restock=true で在庫が戻っていない (% → %)', v_before, v_after;
  end if;

  -- 未発送 (入金確認済み) のキャンセルは常に在庫を戻す
  perform public.treemerce_admin_set_order_status(v_o3, 'payment_confirmed', '入金を確認');
  select stock into v_before from public.products where id = current_setting('tm.p4')::uuid;
  perform public.treemerce_admin_set_order_status(v_o3, 'cancelled', 'お客様都合のキャンセル');
  select stock into v_after from public.products where id = current_setting('tm.p4')::uuid;
  if v_after <> v_before + 1 then
    raise exception 'CASE34 FAILED: 未発送のキャンセルで在庫が戻っていない (% → %)', v_before, v_after;
  end if;

  raise notice 'CASE34 OK: 発送済みのキャンセルは p_restock 必須・true のときだけ在庫復元・選択は監査ログに記録。未発送は常に復元';
end $$;

reset role;

-- ============================================================================
-- CASE35 : 商品ページの max_quantity は「在庫数と 10 の小さい方」
-- ============================================================================

set local role anon;

do $$
declare v_res jsonb; v_p4 int; v_max int;
begin
  v_res := public.treemerce_shop_products(current_setting('tm.agent_b_public'));
  select (e ->> 'max_quantity')::int into v_p4
  from jsonb_array_elements(v_res -> 'products') e where e ->> 'id' = current_setting('tm.p4');
  select max((e ->> 'max_quantity')::int) into v_max from jsonb_array_elements(v_res -> 'products') e;
  if v_p4 is distinct from 10 or v_max > 10 then
    raise exception 'CASE35 FAILED: max_quantity が 10 を超える / 在庫が十分な商品で 10 でない (% / %)',
      v_p4, v_max;
  end if;
  raise notice 'CASE35 OK: max_quantity は在庫数と 10 の小さい方 (在庫が多い商品の正確な在庫数は出ない)';
end $$;

reset role;

-- ============================================================================
-- 生産者・発送 (0014 / 0015) の準備:
--   生産者 X (送り先メールあり) / Y (送り先メールなし) と、その商品 px / py を登録する。
-- ============================================================================

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_r jsonb;
begin
  v_r := public.treemerce_admin_upsert_producer(
    'テスト農園X', '静岡県 牧之原市', '静岡県', '入金確認後3営業日以内',
    'order-x@farm.test', '農園 太郎', '0548-00-0000', 'contact-x@farm.test', '取引条件メモ');
  perform set_config('tm.prod_x', v_r ->> 'id', true);
  v_r := public.treemerce_admin_upsert_producer(
    'テスト牧場Y', '北海道 十勝', '北海道', '入金確認後5営業日以内');
  perform set_config('tm.prod_y', v_r ->> 'id', true);

  v_r := public.treemerce_admin_upsert_product('テスト緑茶', 2000, 50, true, 'food',
    p_producer_id => current_setting('tm.prod_x')::uuid, p_content_volume => '100g×2袋',
    p_ingredients => '緑茶 (静岡県産)');
  perform set_config('tm.px', v_r ->> 'id', true);
  v_r := public.treemerce_admin_upsert_product('テストチーズ', 3000, 50, true, 'food',
    p_producer_id => current_setting('tm.prod_y')::uuid, p_content_volume => '200g',
    p_best_before_note => '製造日から60日');
  perform set_config('tm.py', v_r ->> 'id', true);
end $$;

reset role;

-- 代理店 B の紹介リンクから新規顧客が px・py を注文 (担当・帰属は B)
set local role anon;
do $$
begin
  perform public.treemerce_place_order(current_setting('tm.agent_b_public'),
    jsonb_build_array(
      jsonb_build_object('product_id', current_setting('tm.px'), 'quantity', 1),
      jsonb_build_object('product_id', current_setting('tm.py'), 'quantity', 1)),
    '直送花子', '東京都テスト区1-1', 'tm-test-case36@treemerce.test', '090-3636-3636');
end $$;
reset role;

-- ============================================================================
-- CASE36 : order_items は列 GRANT。現担当の代理店は許可列 (商品名・数量など) を読めるが、
--          producer_id は読めない。生産者マスタ・発送記録・発送依頼書には一切届かない。
-- ============================================================================

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_ok boolean; v_cnt int; v_order uuid; v_names text;
begin
  select id into v_order from public.orders where contact_email = 'tm-test-case36@treemerce.test';
  if v_order is null then raise exception 'CASE36 FAILED: 現担当 B が自分の担当顧客の注文を読めない'; end if;

  -- 許可された列は読める
  select count(*), string_agg(product_name || ':' || quantity::text || ':' || coalesce(product_content_volume, ''), ',')
    into v_cnt, v_names
  from public.order_items where order_id = v_order;
  if v_cnt <> 2 or v_names not like '%テスト緑茶:1:100g×2袋%' then
    raise exception 'CASE36 FAILED: 許可列 (商品名・数量・内容量) が読めない (% / %)', v_cnt, v_names;
  end if;

  -- producer_id は列 GRANT が無いため拒否される
  v_ok := false;
  begin perform producer_id from public.order_items where order_id = v_order;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE36 FAILED: 代理店が order_items.producer_id を読めた'; end if;

  v_ok := false;
  begin perform * from public.order_items where order_id = v_order;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE36 FAILED: 代理店が order_items を select * で読めた'; end if;

  -- 発送記録・生産者マスタは 0 行、連絡先列は権限なし
  select count(*) into v_cnt from public.order_shipments;
  if v_cnt <> 0 then raise exception 'CASE36 FAILED: 代理店に発送記録が % 行見えた', v_cnt; end if;
  select count(*) into v_cnt from public.producers;
  if v_cnt <> 0 then raise exception 'CASE36 FAILED: 代理店に生産者マスタが % 行見えた', v_cnt; end if;
  v_ok := false;
  begin perform notify_email from public.producers;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE36 FAILED: 代理店が生産者の送り先メール列に届いた'; end if;

  -- 発送依頼書・発送管理・生産者管理の RPC は拒否
  v_ok := false;
  begin
    perform public.treemerce_admin_shipment_request(
      (select '00000000-0000-0000-0000-000000000000'::uuid));
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE36 FAILED: 代理店が発送依頼書 RPC を実行できた'; end if;

  v_ok := false;
  begin perform public.treemerce_admin_list_producers();
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE36 FAILED: 代理店が生産者一覧 RPC を実行できた'; end if;

  raise notice 'CASE36 OK: 代理店は order_items の許可列のみ読め、producer_id・select *・生産者マスタ・発送記録・依頼書には届かない';
end $$;

reset role;

-- ============================================================================
-- CASE37 : 生産者マスタの操作は super_admin のみ。編集は理由必須、仮の生産者は編集不可。
--          一般 admin は公開項目のみ参照でき、連絡先列には届かない。
--          監査ログには連絡先・送り先メールの値を書かない (変更の有無のみ)。
-- ============================================================================

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000008","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_ok boolean; v_cnt int;
begin
  v_ok := false;
  begin
    perform public.treemerce_admin_upsert_producer('一般adminの生産者', '産地', '東京都', '3日以内');
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE37 FAILED: 一般 admin が生産者を登録できた'; end if;

  v_ok := false;
  begin perform public.treemerce_admin_list_producers();
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE37 FAILED: 一般 admin が生産者の連絡先一覧を取得できた'; end if;

  select count(*) into v_cnt from public.producers where name in ('テスト農園X', 'テスト牧場Y');
  if v_cnt <> 2 then raise exception 'CASE37 FAILED: 一般 admin が生産者の公開項目を読めない'; end if;

  v_ok := false;
  begin perform contact_phone from public.producers;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE37 FAILED: 一般 admin が生産者の連絡先列を読めた'; end if;

  -- support / admin は発送記録 (状況) を参照できる
  select count(*) into v_cnt from public.order_shipments s
  join public.orders o on o.id = s.order_id
  where o.contact_email = 'tm-test-case36@treemerce.test';
  if v_cnt <> 2 then raise exception 'CASE37 FAILED: 一般 admin が発送記録を参照できない (%)', v_cnt; end if;
end $$;

reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v_ok boolean; v_cnt int; v_list jsonb; v_audit public.admin_audit_logs%rowtype;
begin
  -- 編集は理由必須
  v_ok := false;
  begin
    perform public.treemerce_admin_upsert_producer('テスト農園X', '静岡県 牧之原市', '静岡県',
      '入金確認後3営業日以内', p_producer_id => current_setting('tm.prod_x')::uuid);
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE37 FAILED: 理由なしで生産者を編集できた'; end if;

  -- 仮の生産者は編集不可
  v_ok := false;
  begin
    perform public.treemerce_admin_upsert_producer('書き換え', '産地', '東京都', '3日以内',
      p_producer_id => '00000000-0000-4000-8000-000000000001'::uuid, p_reason => '試験');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE37 FAILED: 仮の生産者を編集できた'; end if;

  -- 不正な都道府県は拒否
  v_ok := false;
  begin
    perform public.treemerce_admin_upsert_producer('不正県の生産者', '産地', 'テスト県', '3日以内');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE37 FAILED: 不正な都道府県で登録できた'; end if;

  -- テーブルへの直接書込みは super_admin でも不可 (RPC 経由のみ)
  v_ok := false;
  begin
    update public.producers set name = '直接書換' where id = current_setting('tm.prod_x')::uuid;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE37 FAILED: producers を直接 UPDATE できた'; end if;

  -- 送り先メールを変更 (理由あり)
  perform public.treemerce_admin_upsert_producer('テスト農園X', '静岡県 牧之原市', '静岡県',
    '入金確認後3営業日以内', 'order-x2@farm.test', '農園 太郎', '0548-00-0000',
    'contact-x@farm.test', '取引条件メモ', true, current_setting('tm.prod_x')::uuid, '送り先メールの変更');

  select * into v_audit from public.admin_audit_logs
  where target_table = 'producers' and target_id = current_setting('tm.prod_x')::uuid
    and action = 'producer.update'
  order by created_at desc limit 1;
  if v_audit.id is null or (v_audit.after_state ->> 'private_fields_changed')::boolean is not true
     or v_audit.reason <> '送り先メールの変更' then
    raise exception 'CASE37 FAILED: 生産者の変更が監査ログに残っていない / 変更の有無が記録されていない';
  end if;

  select count(*) into v_cnt from public.admin_audit_logs
  where target_table = 'producers'
    and (coalesce(before_state::text, '') || coalesce(after_state::text, '')) ~ '(farm\.test|0548-00-0000|農園 太郎|取引条件メモ)';
  if v_cnt <> 0 then
    raise exception 'CASE37 FAILED: 監査ログに生産者の連絡先・送り先メール・メモの値が % 件残った', v_cnt;
  end if;

  -- super_admin の一覧 RPC では連絡先が見える
  v_list := public.treemerce_admin_list_producers(current_setting('tm.prod_x')::uuid);
  if v_list -> 0 ->> 'notify_email' is distinct from 'order-x2@farm.test' then
    raise exception 'CASE37 FAILED: super_admin の一覧で送り先メールが取得できない (%)', v_list;
  end if;

  raise notice 'CASE37 OK: 生産者の操作は super_admin のみ・編集は理由必須・仮の生産者は不可・直接書込み不可・監査ログに連絡先の値は残らない';
end $$;

reset role;

-- ============================================================================
-- CASE38 : 公開ショップには生産者の公開項目 (名前・産地・発送元・発送目安) と販売者名だけが出る。
--          連絡先・送り先メールは出ない。仮の生産者の商品は producer = null。
--          生産者を無効にすると、その商品は一覧から消え、注文もできない。
-- ============================================================================

set local role anon;

do $$
declare v_res jsonb; v_px jsonb; v_p4 jsonb;
begin
  v_res := public.treemerce_shop_products(current_setting('tm.agent_b_public'));
  select e into v_px from jsonb_array_elements(v_res -> 'products') e where e ->> 'id' = current_setting('tm.px');
  select e into v_p4 from jsonb_array_elements(v_res -> 'products') e where e ->> 'id' = current_setting('tm.p4');

  if v_px -> 'producer' ->> 'name' is distinct from 'テスト農園X'
     or v_px -> 'producer' ->> 'origin' is distinct from '静岡県 牧之原市'
     or v_px -> 'producer' ->> 'ship_from_prefecture' is distinct from '静岡県'
     or v_px -> 'producer' ->> 'ship_lead_time' is distinct from '入金確認後3営業日以内'
     or v_px ->> 'content_volume' is distinct from '100g×2袋' then
    raise exception 'CASE38 FAILED: 商品の生産者・内容量が返らない (%)', v_px;
  end if;
  if v_res::text ~ '(farm\.test|0548-00-0000|農園 太郎|取引条件メモ)' then
    raise exception 'CASE38 FAILED: 公開ショップに生産者の連絡先・送り先メール・メモが含まれる';
  end if;
  if v_p4 is null or jsonb_typeof(v_p4 -> 'producer') <> 'null' then
    raise exception 'CASE38 FAILED: 仮の生産者の商品で producer が null でない (%)', v_p4;
  end if;
  if v_res ->> 'seller_name' is distinct from 'テスト運営株式会社' then
    raise exception 'CASE38 FAILED: 販売者名が返らない';
  end if;
end $$;

reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;
do $$
declare v_r jsonb;
begin
  v_r := public.treemerce_admin_upsert_producer('テスト牧場Y', '北海道 十勝', '北海道',
    '入金確認後5営業日以内', p_is_active => false,
    p_producer_id => current_setting('tm.prod_y')::uuid, p_reason => '一時休止');
  if (v_r ->> 'open_shipments')::int <> 1 then
    raise exception 'CASE38 FAILED: 無効化時に未発送件数が返らない (%)', v_r;
  end if;
end $$;
reset role;

set local role anon;
do $$
declare v_res jsonb; v_ok boolean;
begin
  v_res := public.treemerce_shop_products(current_setting('tm.agent_b_public'));
  if v_res::text like '%' || current_setting('tm.py') || '%' then
    raise exception 'CASE38 FAILED: 無効な生産者の商品が公開一覧に出た';
  end if;

  v_ok := false;
  begin
    perform public.treemerce_place_order(current_setting('tm.agent_b_public'),
      jsonb_build_array(jsonb_build_object('product_id', current_setting('tm.py'), 'quantity', 1)),
      '休止注文', '東京都テスト区1-1', 'tm-test-case38@treemerce.test');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE38 FAILED: 無効な生産者の商品を注文できた'; end if;
end $$;
reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
  perform public.treemerce_admin_upsert_producer('テスト牧場Y', '北海道 十勝', '北海道',
    '入金確認後5営業日以内', p_is_active => true,
    p_producer_id => current_setting('tm.prod_y')::uuid, p_reason => '再開');
  raise notice 'CASE38 OK: ショップには生産者の公開項目と販売者名のみ・連絡先は出ない・仮の生産者は null・無効な生産者の商品は非表示で注文不可';
end $$;
reset role;

-- ============================================================================
-- CASE39 : 複数生産者の注文は生産者ごとに発送記録ができる。入金確認で依頼可能になり、
--          依頼書はその生産者の分だけ (代理店・顧客メール・価格を含まない)。
--          実在の生産者の未発送分がある間は手動で「発送済み」にできない。
--          発送登録・訂正は監査ログに残り、帰属代理店は変わらない。
-- ============================================================================

set local role anon;
do $$
begin
  perform public.treemerce_place_order(current_setting('tm.agent_b_public'),
    jsonb_build_array(
      jsonb_build_object('product_id', current_setting('tm.px'), 'quantity', 2),
      jsonb_build_object('product_id', current_setting('tm.py'), 'quantity', 1),
      jsonb_build_object('product_id', current_setting('tm.p4'), 'quantity', 1)),
    '直送三郎', '大阪府テスト市1-1', 'tm-test-case39@treemerce.test', '090-3939-3939',
    '530-0001', p_note => '置き配希望');
end $$;
reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  v_o uuid; v_agent uuid; v_detail jsonb; v_sx uuid; v_sy uuid; v_sp uuid;
  v_req jsonb; v_ok boolean; v_cnt int; v_res jsonb;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  select id, agent_id into v_o, v_agent from public.orders where contact_email = 'tm-test-case39@treemerce.test';
  select id into v_sx from public.order_shipments where order_id = v_o and producer_id = current_setting('tm.prod_x')::uuid;
  select id into v_sy from public.order_shipments where order_id = v_o and producer_id = current_setting('tm.prod_y')::uuid;
  select id into v_sp from public.order_shipments
  where order_id = v_o and producer_id = '00000000-0000-4000-8000-000000000001'::uuid;

  select count(*) into v_cnt from public.order_shipments where order_id = v_o and status = 'awaiting_payment';
  if v_cnt <> 3 or v_sx is null or v_sy is null or v_sp is null then
    raise exception 'CASE39 FAILED: 生産者ごとの発送記録 (3件・入金待ち) が作られていない (%)', v_cnt;
  end if;

  v_detail := public.treemerce_admin_get_order(v_o);
  if exists (select 1 from jsonb_array_elements(v_detail -> 'items') e where e ->> 'producer_id' is null)
     or jsonb_array_length(v_detail -> 'shipments') <> 3 then
    raise exception 'CASE39 FAILED: 明細に生産者のスナップショットが無い / 注文詳細に発送記録が無い';
  end if;

  -- 入金確認前は依頼書を作れない
  v_ok := false;
  begin perform public.treemerce_admin_shipment_request(v_sx);
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE39 FAILED: 入金確認前に発送依頼書が作れた'; end if;

  perform public.treemerce_admin_set_order_status(v_o, 'payment_confirmed', '入金を確認');
  select count(*) into v_cnt from public.order_shipments where order_id = v_o and status = 'ready';
  if v_cnt <> 3 then raise exception 'CASE39 FAILED: 入金確認で発送記録が依頼可能にならない (%)', v_cnt; end if;

  -- 実在の生産者が未発送のうちは手動で発送済みにできない
  v_ok := false;
  begin perform public.treemerce_admin_set_order_status(v_o, 'shipped', '発送');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE39 FAILED: 生産者が未発送なのに手動で発送済みにできた'; end if;

  -- 依頼書は X の分だけ。代理店・顧客メール・価格は含まない
  v_req := public.treemerce_admin_shipment_request(v_sx);
  if jsonb_array_length(v_req -> 'items') <> 1
     or v_req -> 'items' -> 0 ->> 'product_name' <> 'テスト緑茶'
     or (v_req -> 'items' -> 0 ->> 'quantity')::int <> 2
     or v_req -> 'items' -> 0 ->> 'content_volume' <> '100g×2袋'
     or v_req -> 'ship_to' ->> 'name' <> '直送三郎'
     or v_req -> 'ship_to' ->> 'postal_code' <> '530-0001'
     or v_req ->> 'customer_note' <> '置き配希望'
     or v_req -> 'sender' ->> 'name' <> 'テスト運営株式会社'
     or v_req -> 'producer' ->> 'notify_email' <> 'order-x2@farm.test' then
    raise exception 'CASE39 FAILED: 依頼書の内容が不正 (%)', v_req;
  end if;
  if v_req::text ~ '(tm-test-case39@|テストチーズ|テスト代理店|unit_price|amount|agent)'
     or v_req::text like '%' || current_setting('tm.agent_b_public') || '%' then
    raise exception 'CASE39 FAILED: 依頼書に他の生産者の商品・顧客メール・代理店・価格が含まれる (%)', v_req;
  end if;

  -- 手動で依頼済みにする
  v_res := public.treemerce_admin_record_shipment_request(v_sx, 'manual');
  if v_res ->> 'status' <> 'requested' or (v_res ->> 'request_count')::int <> 1 then
    raise exception 'CASE39 FAILED: 依頼済みの記録ができない (%)', v_res;
  end if;

  -- 未来日の発送日は拒否
  v_ok := false;
  begin perform public.treemerce_admin_ship_shipment(v_sx, v_today + 1, 'ヤマト運輸', '1234-5678-9012');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE39 FAILED: 未来の発送日で登録できた'; end if;

  v_res := public.treemerce_admin_ship_shipment(v_sx, v_today, 'ヤマト運輸', '1234-5678-9012');
  perform public.treemerce_admin_ship_shipment(v_sy, v_today, '佐川急便', '9999-0000');
  if (select status from public.orders where id = v_o) <> 'payment_confirmed' then
    raise exception 'CASE39 FAILED: 仮の生産者 (運営) の分が未発送なのに注文が発送済みになった';
  end if;

  -- 残りは仮の生産者 (運営が発送) のみ → 手動で発送済みにでき、運営分も発送済みになる
  perform public.treemerce_admin_set_order_status(v_o, 'shipped', '運営分を発送');
  if (select status from public.order_shipments where id = v_sp) <> 'shipped'
     or (select shipped_on from public.order_shipments where id = v_sp) is null then
    raise exception 'CASE39 FAILED: 手動の発送済みで運営分の発送記録が発送済みにならない';
  end if;

  -- 訂正は理由必須・監査ログに残る
  v_ok := false;
  begin perform public.treemerce_admin_ship_shipment(v_sx, v_today, 'ヤマト運輸', '1234-5678-0000');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE39 FAILED: 理由なしで発送記録を訂正できた'; end if;
  perform public.treemerce_admin_ship_shipment(v_sx, v_today, 'ヤマト運輸', '1234-5678-0000', '送り状番号の誤記');

  select count(*) into v_cnt from public.admin_audit_logs
  where target_table = 'order_shipments' and target_id = v_sx
    and action in ('shipment.request', 'shipment.ship', 'shipment.correct');
  if v_cnt <> 3 then raise exception 'CASE39 FAILED: 発送記録の操作が監査ログに残っていない (%)', v_cnt; end if;
  select count(*) into v_cnt from public.admin_audit_logs
  where target_table = 'order_shipments'
    and (coalesce(before_state::text, '') || coalesce(after_state::text, '')) ~ '(直送三郎|大阪府テスト市|090-3939|farm\.test)';
  if v_cnt <> 0 then raise exception 'CASE39 FAILED: 発送記録の監査ログにお届け先・送り先メールが残った'; end if;

  if (select agent_id from public.orders where id = v_o) is distinct from v_agent
     or v_agent is distinct from current_setting('tm.agent_b')::uuid then
    raise exception 'CASE39 FAILED: 発送処理で帰属代理店が変わった';
  end if;

  raise notice 'CASE39 OK: 生産者ごとの発送記録・入金確認で依頼可能・依頼書は自分の分のみ (代理店/顧客メール/価格なし)・実在生産者の未発送中は手動発送不可・訂正は理由必須・監査ログ・帰属不変';
end $$;

reset role;

-- 一般 admin は発送登録できない
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000008","role":"authenticated"}', true);
set local role authenticated;
do $$
declare v_ok boolean;
begin
  v_ok := false;
  begin
    perform public.treemerce_admin_ship_shipment(
      (select s.id from public.order_shipments s limit 1), (now() at time zone 'Asia/Tokyo')::date);
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'CASE39 FAILED: 一般 admin が発送登録できた'; end if;
end $$;
reset role;

-- ============================================================================
-- CASE40 : 全生産者の発送登録で注文が自動で「発送済み」になる (履歴・監査ログに理由)。
--          一部発送済みの注文のキャンセルは p_restock 必須。未発送分の在庫は常に戻り、
--          発送済み分は指定時のみ戻る。未発送の発送記録はキャンセルになる。
-- ============================================================================

set local role anon;
do $$
begin
  perform public.treemerce_place_order(current_setting('tm.agent_b_public'),
    jsonb_build_array(
      jsonb_build_object('product_id', current_setting('tm.px'), 'quantity', 1),
      jsonb_build_object('product_id', current_setting('tm.py'), 'quantity', 1)),
    '自動発送', '福岡県テスト市1-1', 'tm-test-case40a@treemerce.test');
  perform public.treemerce_place_order(current_setting('tm.agent_b_public'),
    jsonb_build_array(
      jsonb_build_object('product_id', current_setting('tm.px'), 'quantity', 2),
      jsonb_build_object('product_id', current_setting('tm.py'), 'quantity', 3)),
    '一部発送', '福岡県テスト市1-1', 'tm-test-case40b@treemerce.test');
end $$;
reset role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  v_a uuid; v_b uuid; v_ax uuid; v_ay uuid; v_bx uuid; v_by uuid;
  v_res jsonb; v_ok boolean; v_cnt int;
  v_px_before int; v_py_before int; v_px_after int; v_py_after int;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  select id into v_a from public.orders where contact_email = 'tm-test-case40a@treemerce.test';
  select id into v_b from public.orders where contact_email = 'tm-test-case40b@treemerce.test';
  select id into v_ax from public.order_shipments where order_id = v_a and producer_id = current_setting('tm.prod_x')::uuid;
  select id into v_ay from public.order_shipments where order_id = v_a and producer_id = current_setting('tm.prod_y')::uuid;
  select id into v_bx from public.order_shipments where order_id = v_b and producer_id = current_setting('tm.prod_x')::uuid;
  select id into v_by from public.order_shipments where order_id = v_b and producer_id = current_setting('tm.prod_y')::uuid;

  -- (1) 全生産者の発送登録 → 自動で発送済み
  perform public.treemerce_admin_set_order_status(v_a, 'payment_confirmed', '入金を確認');
  v_res := public.treemerce_admin_ship_shipment(v_ax, v_today, 'ヤマト運輸', 'A-1');
  if v_res ->> 'order_status' <> 'payment_confirmed' then
    raise exception 'CASE40 FAILED: 1 生産者だけの発送で注文が発送済みになった';
  end if;
  v_res := public.treemerce_admin_ship_shipment(v_ay, v_today, '佐川急便', 'A-2');
  if v_res ->> 'order_status' <> 'shipped' or (select status from public.orders where id = v_a) <> 'shipped' then
    raise exception 'CASE40 FAILED: 全生産者の発送で注文が発送済みにならない (%)', v_res;
  end if;
  select count(*) into v_cnt from public.order_status_history
  where order_id = v_a and to_status = 'shipped' and reason = '全生産者の発送完了';
  if v_cnt <> 1 then raise exception 'CASE40 FAILED: 自動の発送済みが履歴に残っていない'; end if;
  select count(*) into v_cnt from public.admin_audit_logs
  where target_id = v_a and action = 'order.auto_shipped';
  if v_cnt <> 1 then raise exception 'CASE40 FAILED: 自動の発送済みが監査ログに残っていない'; end if;

  -- (2) 一部発送済みのキャンセル
  perform public.treemerce_admin_set_order_status(v_b, 'payment_confirmed', '入金を確認');
  perform public.treemerce_admin_ship_shipment(v_bx, v_today, 'ヤマト運輸', 'B-1');

  v_ok := false;
  begin perform public.treemerce_admin_set_order_status(v_b, 'cancelled', 'お客様都合');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE40 FAILED: 一部発送済みのキャンセルが p_restock 未指定で通った'; end if;

  select stock into v_px_before from public.products where id = current_setting('tm.px')::uuid;
  select stock into v_py_before from public.products where id = current_setting('tm.py')::uuid;
  perform public.treemerce_admin_set_order_status(v_b, 'cancelled', 'お客様都合 (発送済み分は返品なし)', false);
  select stock into v_px_after from public.products where id = current_setting('tm.px')::uuid;
  select stock into v_py_after from public.products where id = current_setting('tm.py')::uuid;

  if v_px_after <> v_px_before or v_py_after <> v_py_before + 3 then
    raise exception 'CASE40 FAILED: 在庫の戻しが不正 (発送済み X: % → %, 未発送 Y: % → %)',
      v_px_before, v_px_after, v_py_before, v_py_after;
  end if;
  if (select status from public.order_shipments where id = v_bx) <> 'shipped'
     or (select status from public.order_shipments where id = v_by) <> 'cancelled' then
    raise exception 'CASE40 FAILED: キャンセル後の発送記録の状態が不正';
  end if;
  select count(*) into v_cnt from public.admin_audit_logs
  where target_id = v_b and action = 'order.status_change' and after_state ->> 'status' = 'cancelled'
    and (after_state ->> 'restocked')::boolean = false
    and (after_state ->> 'restocked_unshipped')::boolean = true;
  if v_cnt <> 1 then raise exception 'CASE40 FAILED: 在庫の戻し方が監査ログに残っていない'; end if;

  -- キャンセル済みの発送記録は依頼・発送できない
  v_ok := false;
  begin perform public.treemerce_admin_record_shipment_request(v_by, 'manual');
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'CASE40 FAILED: キャンセル済みの発送記録に依頼を記録できた'; end if;

  raise notice 'CASE40 OK: 全生産者の発送で自動的に発送済み (履歴・監査ログ)。一部発送済みのキャンセルは p_restock 必須、未発送分は常に在庫復元・発送済み分は指定時のみ';
end $$;

reset role;

do $$
begin
  raise notice '==========================================';
  raise notice '  TREEMERCE: ALL 40 CASES PASSED (+EXTRA)';
  raise notice '==========================================';
end $$;

rollback;
