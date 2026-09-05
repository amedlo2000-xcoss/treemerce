# TREEMERCE — データベースのセットアップ

## 1. マイグレーションの適用

Supabase の SQL Editor で、**番号順に**次のファイルを実行してください。

| 順番 | ファイル | 内容 |
| --- | --- | --- |
| 1 | `migrations/0001_treemerce_init.sql` | テーブル・列挙型・制約・不変トリガ (STEP1) |
| 2 | `migrations/0002_treemerce_security.sql` | 役割判定・再帰CTE・書込みガード・匿名化 (STEP2) |
| 3 | `migrations/0003_treemerce_rpc.sql` | 公開 RPC / 商流マップ / 客層分析 (STEP2, 5, 6, 7) |
| 4 | `migrations/0004_treemerce_rls.sql` | GRANT の付け直しと RLS ポリシー (STEP3) |
| 5 | `migrations/0005_treemerce_admin_bootstrap.sql` | 管理者ロールの付与/剥奪 RPC |

各ファイルは `begin; … commit;` で囲まれているため、途中で失敗しても中途半端な状態にはなりません。

## 2. 最初の管理者を作る

Supabase Auth でアカウントを作ったあと、SQL Editor で次を実行します。

```sql
insert into public.admin_roles (auth_user_id, role)
select id, 'super_admin' from auth.users where email = 'you@example.com'
on conflict (auth_user_id) do update
  set role = 'super_admin', revoked_at = null;
```

2人目以降は管理画面から `treemerce_admin_grant_role()` で付与できます。

## 3. 環境変数

`.env.local` に以下を設定します。**service_role キーは使いません。**
アプリは常に anon キー + ユーザーセッションで動作し、すべてのクエリに RLS が適用されます。

```
NEXT_PUBLIC_SUPABASE_URL=https://<project>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key>
```

## 4. 受け入れテスト

### ローカル (推奨 / 本番DBに触れない)

PGlite (WebAssembly 版 PostgreSQL) 上に Supabase 相当の前提を作り、
マイグレーションを適用してから CASE1〜19 を実行します。

```
npm run test:db
```

### 本番 Supabase 上で確認する場合

`tests/acceptance_cases.sql` を SQL Editor に貼り付けて実行します。
全体が 1 トランザクションで最後に `rollback` するため、データは残りません。
失敗した CASE があればその場で例外が出て停止します。

## 防御の多層構造

| 層 | 何を守るか |
| --- | --- |
| GRANT | `customer_assignments` / `customer_assignment_history` に書込み権限を与えない |
| RLS | 自分が担当している顧客の行しか見えない。傘外の代理店行も見えない |
| TRIGGER | 認可コンテキスト外の担当書込み・`invited_by` の再設定・履歴/監査ログの改ざんを拒否 |
| FUNCTION | `SECURITY DEFINER` の中で役割判定と匿名化を強制。マップ/集計は `STABLE` で書込み不能 |
| API | Next.js のハンドラでも役割を再判定し、DB の例外を HTTP ステータスへ変換 |
