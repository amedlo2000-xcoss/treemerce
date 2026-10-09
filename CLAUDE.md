@AGENTS.md

# TREEMERCE 絶対原則

代理店 (`agents`) と 商品購入者 (`customers`) を完全に分離して管理するシステム。
以下は交渉不可の不変条件であり、**DB制約 / RLS / APIハンドラ / UI の全層**で守る。
どれか一層でも通ってしまう実装は不採用とする。

1. **agents と customers は同一会員区分として扱わない。**
   別テーブル・別権限・別画面。`customers` に代理店を指す列を持たせない。

2. **`agents.invited_by` は単一カラムの UUID 外部キー。1代理店につき必ず1つのみ。**
   複数の招待元は持てない。既に `invited_by` が設定済みの代理店への再設定は
   API 層 (`treemerce_register_agent`) と DB 層 (`agents_invited_by_immutable` トリガ)
   の両方で拒否する。

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

## 実装の入口

| 目的 | 唯一の入口 |
| --- | --- |
| 代理店登録・招待経路の確定 | `public.treemerce_register_agent()` |
| 顧客登録 | `public.treemerce_register_customer()` |
| 重複検知 | `public.treemerce_check_customer_duplicate()` |
| 担当変更 | `public.treemerce_admin_transfer_customer()` (ADMIN のみ) |
| 商流マップ | `public.treemerce_commerce_map()` |
| コミュニティマップ | `public.treemerce_community_map()` |
| 客層分析 | `public.treemerce_customer_demographics()` |
| 生産者の登録・編集・無効化 | `public.treemerce_admin_upsert_producer()` (super_admin、編集は理由必須) |
| 生産者一覧 (連絡先を含む) | `public.treemerce_admin_list_producers()` (super_admin) |
| 商品の登録・編集 | `public.treemerce_admin_upsert_product()` (0015 で生産者・内容量などを追加) |
| 公開商品一覧 | `public.treemerce_shop_products()` (0015 で生産者の公開項目・販売者名を追加) |
| 注文受付 | `public.treemerce_place_order()` (0015 で生産者ごとの発送記録を作成) |
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
