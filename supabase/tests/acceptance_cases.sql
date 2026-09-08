-- ============================================================================
-- TREEMERCE 受け入れテスト  CASE1 - CASE20
-- ----------------------------------------------------------------------------
-- Supabase SQL Editor にそのまま貼り付けて実行する。
-- 全体が 1 トランザクションで、最後に ROLLBACK するため本番データは残らない。
-- 途中で失敗した CASE があれば例外で停止する。全て通れば最後に
-- 「ALL 20 CASES PASSED」が NOTICE として出力される。
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
  -- A (R の招待で登録) として呼ぶ → R の public_id/display_name が返る
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  set local role authenticated;

  select public.treemerce_my_inviter_profile() into v_profile;
  if (v_profile ->> 'found') is distinct from 'true' then
    raise exception 'CASE20 FAILED: A から見た招待元が found=false だった (%)', v_profile;
  end if;
  if (v_profile ->> 'public_id') is distinct from 'TM-TEST-R' then
    raise exception 'CASE20 FAILED: A の招待元が R ではなかった (%)', v_profile;
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

do $$
begin
  raise notice '==========================================';
  raise notice '  TREEMERCE: ALL 20 CASES PASSED (+EXTRA)';
  raise notice '==========================================';
end $$;

rollback;
