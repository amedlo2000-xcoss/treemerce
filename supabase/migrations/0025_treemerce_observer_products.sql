-- ============================================================================
-- TREEMERCE : 0025_treemerce_observer_products.sql
-- オブザーバー特典付き製品一覧の公開 RPC と、準備中 18 件の初期登録
-- ----------------------------------------------------------------------------
-- 公開 RPC : treemerce_observer_products()  (未ログイン可・STABLE)
--   * オブザーバー特典付きの印がある商品のうち、公開中・準備中だけを返す (非公開は返さない)。
--   * 代理店 ID を受け取らない。紹介者・担当・代理店との紐づけは一切発生しない。
--   * 返す形はショップと同じ公開用の形 (app.public_product_json)。準備中は価格・予定価格を返さない。
--     在庫の情報 (在庫あり・残りわずか・注文できる数量) は返さない (この一覧では注文しない)。
--   * 生産者は公開項目のみ (仮の生産者なら null)。連絡先・電話番号は決して返さない。
--   * カテゴリは有効なものを並び順で返す (件数は画面で商品から数える)。
--
-- 初期登録 (18 件)
--   一覧ページのサンプル 20 件のうち、既存の 2 件 (奉献漬・五次元結晶) を除く 18 件を、
--   準備中・価格なし・在庫 0・仮の生産者で登録する。価格・生産者・産地・電話番号・発送日数・
--   施術時間などの架空の値は登録しない。整丹はサービス (施術・体験) として登録する。
--   同じ名前の商品が既にあれば作らない (重複登録しない)。
--   奉献漬・五次元結晶へのオブザーバー特典付きの印とイラストの種類は、商品管理の画面で設定する。
--
-- 監査ログ: product.create (db_admin、1 件ずつ)。準備中の登録は 0023 のトリガが product.prepare も残す。
--
-- 絶対原則との対応
--   原則1・3・4・5 : 顧客・代理店・招待経路・担当には触れない。応答に顧客・代理店の情報を含めない。
--   派生           : 公開 RPC は STABLE (読み取り専用)。
-- ============================================================================

begin;

-- ============================================================================
-- 1. 公開: オブザーバー特典付き製品一覧 (未ログイン可・STABLE)
-- ============================================================================

create or replace function public.treemerce_observer_products()
returns jsonb
language sql
stable
security definer
set search_path = public, app, pg_temp
as $fn$
  select jsonb_build_object(
    'products', coalesce((
      select jsonb_agg(
               app.public_product_json(p, pr, c) - 'in_stock' - 'low_stock' - 'max_quantity'
               order by c.sort_order, p.sort_order, p.created_at)
      from public.products p
      join public.producers pr on pr.id = p.producer_id
      join public.product_categories c on c.id = p.category_id
      where p.has_observer_benefit
        and p.sales_status in ('on_sale', 'preparing')
        and pr.is_active
    ), '[]'::jsonb),
    'categories', public.treemerce_catalog_categories()
  );
$fn$;

comment on function public.treemerce_observer_products() is
  'オブザーバー特典付き製品一覧 (公開中・準備中のみ)。代理店 ID を受け取らず、紹介者・担当と紐づかない。'
  '準備中は価格を返さない。生産者の連絡先・在庫数は返さない。STABLE。';

-- ============================================================================
-- 2. 準備中 18 件の初期登録 (同じ名前の商品があれば作らない)
-- ============================================================================

select set_config('app.audit_reason', '0025: オブザーバー特典付き製品の初期登録 (準備中)', true);

with seed (sort_key, placeholder_key, name, name_kana, type_label, description, category_code, item_kind) as (
  values
    (20,  'sample-02', '梅結び',             'うめむすび',       'しそ漬け梅',
     '人とのご縁を結ぶ気持ちを込めた、しその香りを楽しむ梅干し。', 'food_beverage', 'goods'),
    (30,  'sample-03', '参道茶',             'さんどうちゃ',     '煎茶',
     '参道を歩く穏やかなひとときをイメージした、日々の休憩に楽しむ煎茶。', 'food_beverage', 'goods'),
    (40,  'sample-04', '禅庭茶',             'ぜんていちゃ',     'ほうじ茶',
     '禅寺の庭の静けさをイメージした、香ばしい香りのほうじ茶。', 'food_beverage', 'goods'),
    (50,  'sample-05', '蓮の雫',             'はすのしずく',     'はちみつ',
     '蓮の葉に宿る雫をイメージした、食卓や贈り物に取り入れるはちみつ。', 'food_beverage', 'goods'),
    (60,  'sample-06', '結び米',             'むすびまい',       '贈答米',
     '食を分かち合う喜びと、人とのつながりをテーマにした贈答用のお米。', 'food_beverage', 'goods'),
    (70,  'sample-07', '灯明菓',             'とうみょうか',     '羊羹',
     '寺院に灯る温かな明かりをイメージした、お茶の時間を彩る羊羹。', 'food_beverage', 'goods'),
    (80,  'sample-08', '石庭のかけら',       'せきていのかけら', '琥珀糖',
     '石庭の石をモチーフにした、色と形を楽しめる琥珀糖。', 'food_beverage', 'goods'),
    (90,  'sample-09', '社叢香',             'しゃそうこう',     'お香',
     '神社を囲む森をイメージした、落ち着いた香りを楽しむお香。', 'fragrance_candle', 'goods'),
    (100, 'sample-10', '伽藍の灯',           'がらんのあかり',   'キャンドル',
     '寺院の灯りをモチーフにした、温かな光で空間を彩るキャンドル。', 'fragrance_candle', 'goods'),
    (120, 'sample-12', '整丹・参道のひととき', null,              '整丹（ジャップカサイ）',
     '整丹（ジャップカサイ）の施術サービス。施術内容・対象・所要時間は提供者の案内に合わせて掲載予定。',
     'treatment_experience', 'service'),
    (130, 'sample-13', '社の雫',             'やしろのしずく',   '耳飾り・ピアス',
     '社の木々に宿る雫をモチーフにした、耳元を彩るピアス。', 'accessory', 'goods'),
    (140, 'sample-14', '蜜の結び',           'みつのむすび',     '蜜蝋を用いた指輪・アクセサリー',
     '結びの形を取り入れた、蜜蝋を用いて制作するアクセサリー。素材・製法の詳細は確認後に掲載予定。',
     'accessory', 'goods'),
    (150, 'sample-15', '杜の曲玉',           'もりのまがたま',   '勾玉',
     '神社を囲む杜をイメージし、伝統的な勾玉の形を現代的に表現した装飾品。', 'accessory', 'goods'),
    (160, 'sample-16', '結び文字',           'むすびもじ',       '創作文字作品',
     '名前や大切な言葉を、結びや和の意匠を取り入れた創作文字で表現するアート作品。', 'art', 'goods'),
    (170, 'sample-17', '結び布',             'むすびぬの',       '風呂敷',
     '結びをテーマにした模様で、包む・運ぶ・飾るを楽しめる風呂敷。', 'household_goods', 'goods'),
    (180, 'sample-18', '禅庭の器',           'ぜんていのうつわ', '湯のみ',
     '禅寺の庭の色や佇まいをイメージした、日々のお茶を楽しむ湯のみ。', 'household_goods', 'goods'),
    (190, 'sample-19', '石庭一輪',           'せきていいちりん', '一輪挿し',
     '石庭の静かな景色をモチーフにした、一輪の花を引き立てる花器。', 'household_goods', 'goods'),
    (200, 'sample-20', '巡り帳',             'めぐりちょう',     '自己対話ノート',
     '神社仏閣を巡る旅になぞらえ、日々の気づきや自分への問いを記録するノート。', 'stationery', 'goods')
),
inserted as (
  insert into public.products
    (name, name_kana, product_type_label, description, category_id, sales_status, is_published,
     price, stock, item_kind, has_observer_benefit, placeholder_key, sort_order, producer_id)
  select s.name, s.name_kana, s.type_label, s.description, c.id, 'preparing', false,
         null, 0, s.item_kind::public.product_item_kind, true, s.placeholder_key, s.sort_key,
         '00000000-0000-4000-8000-000000000001'
  from seed s
  join public.product_categories c on c.code = s.category_code
  where not exists (select 1 from public.products p where p.name = s.name)
  returning *
)
insert into public.admin_audit_logs
  (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
select null, 'db_admin', 'product.create', 'products', i.id, null, to_jsonb(i),
       '0025: オブザーバー特典付き製品の初期登録 (準備中)'
from inserted i;

select set_config('app.audit_reason', '', true);

-- ============================================================================
-- 3. GRANT
-- ============================================================================

revoke all on function public.treemerce_observer_products() from public, anon, authenticated;
grant execute on function public.treemerce_observer_products() to anon, authenticated;

commit;
