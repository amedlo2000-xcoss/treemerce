import { Card, LinkButton, Notice, PageHeader, Stat, formatDateTime } from "@/components/ui";
import { requireAdminPage } from "@/lib/auth/viewer";

export default async function AdminDashboard() {
  const { supabase } = await requireAdminPage("/admin");

  const [agents, customers, assignments, { data: recentLogs }] = await Promise.all([
    supabase.from("agents").select("id", { count: "exact", head: true }),
    supabase.from("customers").select("id", { count: "exact", head: true }),
    supabase
      .from("customer_assignments")
      .select("id", { count: "exact", head: true })
      .eq("status", "active"),
    supabase
      .from("admin_audit_logs")
      .select("id, action, target_table, reason, created_at, actor_role")
      .order("created_at", { ascending: false })
      .limit(5),
  ]);

  return (
    <>
      <PageHeader
        title="管理ダッシュボード"
        description="代理店の登録経路と、購入者の担当関係は別々のメニューで管理します。"
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <Stat label="代理店" value={agents.count ?? 0} hint="登録経路 = invited_by" />
        <Stat label="商品購入者" value={customers.count ?? 0} />
        <Stat label="有効な担当関係" value={assignments.count ?? 0} hint="1購入者につき1件" />
      </div>

      <Notice tone="warning">
        担当代理店の変更は管理者のみが実行できます。変更前後・理由・実行者・日時は
        監査ログと担当変更履歴の両方に必ず記録されます。
      </Notice>

      <div className="grid gap-4 sm:grid-cols-3">
        <Card title="代理店管理" description="招待経路・ステータスの確認">
          <LinkButton href="/admin/agents" variant="secondary">
            開く
          </LinkButton>
        </Card>
        <Card title="商品購入者管理" description="購入者情報の確認・編集">
          <LinkButton href="/admin/customers" variant="secondary">
            開く
          </LinkButton>
        </Card>
        <Card title="顧客担当管理" description="担当代理店の確認・変更">
          <LinkButton href="/admin/assignments" variant="secondary">
            開く
          </LinkButton>
        </Card>
      </div>

      <section className="space-y-3">
        <h2 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">最近の監査ログ</h2>
        {recentLogs && recentLogs.length > 0 ? (
          <ul className="divide-y divide-zinc-200 rounded-xl border border-zinc-200 dark:divide-zinc-800 dark:border-zinc-800">
            {recentLogs.map((log) => (
              <li key={log.id} className="px-4 py-3 text-sm">
                <span className="font-mono text-xs text-zinc-500">{log.action}</span>
                <span className="ml-2 text-zinc-900 dark:text-zinc-100">{log.reason ?? "—"}</span>
                <span className="ml-2 text-xs text-zinc-400">
                  {formatDateTime(log.created_at)}
                </span>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-zinc-500 dark:text-zinc-400">記録はまだありません。</p>
        )}
      </section>
    </>
  );
}
