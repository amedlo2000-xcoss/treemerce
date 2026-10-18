@AGENTS.md

# TREEMERCE 絶対原則

代理店 (`agents`) と 商品購入者 (`customers`) を完全に分離して管理するシステム。
以下は交渉不可の不変条件であり、**DB制約 / RLS / APIハンドラ / UI の全層**で守る。
どれか一層でも通ってしまう実装は不採用とする。

1. **agents と customers は同一会員区分として扱わない。**
   別テーブル・別権限・別画面。`customers` に代理店を指す列を持たせない。

2. **`agents.invited_by` は単一カラムの UUID 外部キー。1代理店につき必ず1つのみ。**
   複数の招待元は持てない。`invited_by` は代理店の作成時に `app.create_agent()` だけが
   設定し、作成後は再設定も「未設定からの設定」も DB 層 (`agents_invited_by_immutable`
   トリガ) で拒否する。代理店申請の招待元は「申請に使われたリンクの代理店」で申請時点に
   固定され (`agent_applications.inviter_agent_id`、変更不可)、承認でそのまま `invited_by` になる。

3. **代理店の登録経路 (`invited_by` の連なり) と顧客の担当代理店 (`customer_assignments`)
   は完全に別データ。** 片方の変更が他方を自動的に変更してはならない。

4. **担当代理店は最初の登録経路で確定・固定。**
   一般代理店は UI・API・サーバー処理のいずれからも担当の変更・解除・移管ができない。
   - GRANT: `customer_assignments` に INSERT/UPDATE/DELETE 権限を与えない
   - RLS: 一般代理店向けの書込みポリシーを作らない
   - TRIGGER: `app.guard_customer_assignment_write()` が認可コンテキスト外を拒否
   - API: 担当変更ハンドラは ADMIN 判定を通らないと実行されない

5. **他代理店が担当する顧客の氏名・連絡先・購入内容・販売情報は、いかなる
   API レスポンス・画面にも出さない。** 可視条件は「自分が現に担当しているか」だけ。
   傘下代理店の担当顧客であっても PII は不可視。

6. **重複登録を検知しても担当代理店は自動変更しない。** 中立メッセージのみを返し、
   「誰が担当しているか」は絶対に開示しない。

7. **同一人物の照合は email / 電話番号等の識別子で行う。**
   氏名の一致のみで同一人物と確定しない。氏名に一意制約を張らない。

8. **担当変更は ADMIN 専用。** 変更前後・理由・実行者・日時を
   `admin_audit_logs` と `customer_assignment_history` の両方に保存する。

## 派生ルール

- **商流マップ / 客層分析は完全に読み取り専用。** RPC は `STABLE` で定義し、
  書込みが構造的に不可能な状態を維持する。
- **部分木の算出と匿名化はサーバー側で強制する。** クライアントに実データを送って
  から隠す実装は禁止。API レスポンス自体に他代理店担当顧客の実データを含めない。
- **客層分析のレスポンスに代理店別の内訳を含めない。** 個々の顧客が
  「どの傘下代理店の担当か」を特定できてはならない。
- **n 数が極端に少ないセグメント (n < 5) は「該当データ少数」に丸める。**
- **代理店コミュニティマップに customers を一切含めない。**
- **書込みガードの「DB管理者の直接操作」の例外は `session_user = 'postgres'` で判定する (0029)。**
  `current_user` は SECURITY DEFINER 関数の中で postgres になるため使わない。
  関数からの書込みは必ず対応するコンテキスト (`app.*_ctx`) を張ってから行う。

## 実装の入口

| 目的 | 唯一の入口 |
| --- | --- |
| 代理店の作成・招待経路の確定 | `app.create_agent()` (0028、直接 EXECUTE 不可)。呼び出し元は次の2つだけ: 申請の承認 `public.treemerce_admin_approve_agent_application()` (招待元は申請に固定された値で、引数で受け取らない) と、super_admin の直接作成 `public.treemerce_register_agent()` (招待元の明示が必須: `'agent'` + 代理店ID か `'none'`)。どちらも監査ログ `agent.create` に実行者・日時・招待元・経路が残る。一般ユーザーが代理店を作る経路は無い |
| 紹介リンクからの登録 (会員 + 代理店申請) | `public.treemerce_register_member()` (0028)。全員を会員として `treemerce_register_customer()` で登録し、「申し込む」「規約に同意」の両方が true のときだけ申請を作る (ログイン・メール確認済み・規約の現行の版が必須)。IP・ブラウザ情報は API ルートがリクエストヘッダーから渡す |
| 代理店申請の審査 | `public.treemerce_admin_list_agent_applications()` / `treemerce_admin_get_agent_application()` / `treemerce_admin_approve_agent_application()` / `treemerce_admin_reject_agent_application()` (super_admin、理由必須。却下理由は監査ログにのみ保存) |
| 本人の申請状況 | `public.treemerce_my_agent_application()` (状態と中立的な文面のみ。却下理由・招待元は返さない) |
| 代理店規約 | `public.treemerce_current_agent_terms()` (公開・STABLE)。版は `agent_terms_versions` (公開は DB 管理者が SQL で行う)、同意は `agent_terms_acceptances` (追記専用) |
| 顧客登録 | `public.treemerce_register_customer()` |
| 重複検知 | `public.treemerce_check_customer_duplicate()` |
| 担当変更 | `public.treemerce_admin_transfer_customer()` (ADMIN のみ) |
| 商流マップ | `public.treemerce_commerce_map()` |
| コミュニティマップ | `public.treemerce_community_map()` |
| 客層分析 | `public.treemerce_customer_demographics()` |
| 生産者の登録・編集・無効化 | `public.treemerce_admin_upsert_producer()` (super_admin、編集は理由必須) |
| 生産者一覧 (連絡先を含む) | `public.treemerce_admin_list_producers()` (super_admin) |
| 商品の登録・編集 | `public.treemerce_admin_save_product()` (0023、super_admin。販売状態・カテゴリ・オブザーバー特典付き・物品/サービス。旧 `treemerce_admin_upsert_product` は 0026 で削除予定) |
| 商品カテゴリ | `public.treemerce_catalog_categories()` (公開・STABLE) / `treemerce_admin_list_categories()` / `treemerce_admin_upsert_category()` / `treemerce_admin_set_category_active()` / `treemerce_admin_reorder_categories()` (super_admin、0022。削除不可・名称変更と有効/無効は理由必須) |
| 公開商品一覧 | `public.treemerce_shop_products()` (0023 で準備中・カテゴリ・物品/サービスを追加。準備中は価格を返さない) |
| オブザーバー特典付き製品一覧 | `public.treemerce_observer_products()` (0025、公開・STABLE。代理店 ID を受け取らない) |
| 注文受付 | `public.treemerce_place_order()` (0015 で生産者ごとの発送記録を作成。0023 で準備中・サービスを拒否し、注文時点のカテゴリを明細に保存) |
| 注文ステータス変更 | `public.treemerce_admin_set_order_status()` (super_admin、0015 で発送記録と連動) |
| 注文詳細 (ADMIN) | `public.treemerce_admin_get_order()` (super_admin、0015 で発送記録を追加) |
| 発送登録・訂正 | `public.treemerce_admin_ship_shipment()` (super_admin、全発送で注文を自動で発送済み) |
| 発送依頼書 | `public.treemerce_admin_shipment_request()` (super_admin) |
| 発送依頼の記録 | `public.treemerce_admin_record_shipment_request()` (super_admin) |
| 事業プロフィール (本人) | `public.treemerce_my_agent_profile()` / `public.treemerce_update_my_agent_profile()` (0016) |
| 事業プロフィール (ADMIN) | `public.treemerce_admin_get_agent_profile()` (super_admin、0016) |
| 持込み申請 (本人) | `public.treemerce_save_my_submission()` / `treemerce_submit_my_submission()` / `treemerce_withdraw_my_submission()` / `treemerce_my_submissions()` / `treemerce_my_submission()` (0018) |
| 持込み申請の画像 (本人) | `public.treemerce_reserve_submission_image()` / `treemerce_remove_submission_image()` (0018、非公開バケット `product-submission-images`) |
| 持込み申請の審査 | `public.treemerce_admin_list_submissions()` / `treemerce_admin_get_submission()` / `treemerce_admin_approve_submission()` / `treemerce_admin_return_submission()` / `treemerce_admin_reject_submission()` (super_admin、0018) |
| 持込み商品の売れ行き | `public.treemerce_my_sourced_product_sales()` (本人、STABLE、0019) |

持込み元 (`product_sources`) は承認処理でのみ作られ、変更・削除できない。持込み元のある商品は、申請が承認済みで
super_admin が実行した場合にだけ公開でき (0017 の公開ガード)、公開・非公開は経路を問わず監査ログに残る。

テーブルへの直接書込みは行わない。受け入れテストは `supabase/tests/acceptance_cases.sql`。
