import { LinkButton, Notice, PageHeader, Stat, formatDate } from "@/components/ui";
import { requireAgentPage } from "@/lib/auth/viewer";
import type { CommerceMap } from "@/lib/domain/types";

export default async function AgentDashboard() {
  const { supabase, agent } = await requireAgentPage("/agent");

  const [{ count: customerCount }, { data: mapData }, { data: notifications }] = await Promise.all([
    supabase
      .from("customer_assignments")
      .select("id", { count: "exact", head: true })
      .eq("status", "active"),
    supabase.rpc("treemerce_commerce_map", { p_root_agent_id: null }),
    supabase
      .from("notifications")
      .select("id, title, body, created_at, read_at")
      .order("created_at", { ascending: false })
      .limit(5),
  ]);

  const map = mapData as CommerceMap | null;
  const downlineCount = Math.max((map?.agents.length ?? 1) - 1, 0);

  return (
    <>
      <PageHeader
        title={`ようこそ、${agent.display_name} さん`}
        description="担当顧客・商流マップ・客層分析はすべて、あなたと傘下の範囲に限定して表示されます。"
        action={<LinkButton href="/agent/invitations">招待URLを発行</LinkButton>}
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <Stat label="担当顧客" value={customerCount ?? 0} hint="あなたが現に担当している購入者" />
        <Stat label="傘下代理店" value={downlineCount} hint="招待経路をたどった部分木の人数" />
        <Stat label="登録日" value={formatDate(agent.registered_at)} />
      </div>

      <Notice tone="info">
        担当代理店は購入者の初回登録時に確定し、以後は変更できません。変更が必要な場合は運営事務局へご連絡ください。
      </Notice>

      <section className="space-y-3">
        <h2 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">お知らせ</h2>
        {notifications && notifications.length > 0 ? (
          <ul className="divide-y divide-zinc-200 rounded-xl border border-zinc-200 dark:divide-zinc-800 dark:border-zinc-800">
            {notifications.map((n) => (
              <li key={n.id} className="px-4 py-3">
                <p className="text-sm font-medium text-zinc-900 dark:text-zinc-100">{n.title}</p>
                {n.body ? (
                  <p className="mt-0.5 text-xs text-zinc-600 dark:text-zinc-400">{n.body}</p>
                ) : null}
                <p className="mt-1 text-[11px] text-zinc-400">{formatDate(n.created_at)}</p>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-zinc-500 dark:text-zinc-400">お知らせはありません。</p>
        )}
      </section>
    </>
  );
}
