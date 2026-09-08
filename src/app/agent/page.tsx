import { Network, UserCircle, UserPlus, Users } from "lucide-react";

import { PrimaryButton, BigStat, Surface, EmptyState } from "@/components/mobile/primitives";
import { formatDate } from "@/components/ui";
import { requireAgentPage } from "@/lib/auth/viewer";
import type { CommerceMap } from "@/lib/domain/types";

function startOfMonthISOString() {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), 1).toISOString();
}

/**
 * ホーム (STEP2): システム構造の説明ではなく「今の状態」を見せる画面。
 * 数字を主役にし、詳細は各タブ (顧客・組織・コンテンツ・MY) 側に譲る。
 */
export default async function AgentDashboard() {
  const { supabase, agent } = await requireAgentPage("/agent");

  const [{ count: customerCount }, { count: newThisMonthCount }, { data: mapData }, { data: notifications }] =
    await Promise.all([
      supabase
        .from("customer_assignments")
        .select("id", { count: "exact", head: true })
        .eq("status", "active"),
      supabase
        .from("customer_assignments")
        .select("id", { count: "exact", head: true })
        .eq("status", "active")
        .gte("assigned_at", startOfMonthISOString()),
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
      <Surface className="flex items-center gap-4">
        <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-brand-soft text-brand">
          <UserCircle size={30} strokeWidth={1.6} />
        </div>
        <div className="min-w-0">
          <p className="text-[13px] text-text-secondary">おかえりなさい</p>
          <p className="truncate text-[19px] font-bold text-text-primary">{agent.display_name} さん</p>
        </div>
      </Surface>

      <div className="grid grid-cols-3 gap-3">
        <Surface className="!p-4">
          <BigStat label="担当顧客" value={customerCount ?? 0} />
        </Surface>
        <Surface className="!p-4">
          <BigStat label="傘下代理店" value={downlineCount} />
        </Surface>
        <Surface className="!p-4">
          <BigStat label="今月新規" value={newThisMonthCount ?? 0} />
        </Surface>
      </div>

      <PrimaryButton href="/agent/invitations">
        <UserPlus size={20} strokeWidth={2} />
        招待する
      </PrimaryButton>

      <div className="grid grid-cols-2 gap-3">
        <PrimaryButton href="/agent/customers" variant="secondary">
          <Users size={18} strokeWidth={1.9} />
          顧客を見る
        </PrimaryButton>
        <PrimaryButton href="/agent/organization" variant="secondary">
          <Network size={18} strokeWidth={1.9} />
          組織を見る
        </PrimaryButton>
      </div>

      <div className="space-y-3">
        <h2 className="px-1 text-[13px] font-semibold tracking-wide text-text-secondary">
          最近の動き
        </h2>
        {notifications && notifications.length > 0 ? (
          <Surface padded={false} className="divide-y divide-border-soft px-4">
            {notifications.map((n) => (
              <div key={n.id} className="py-3.5">
                <p className="text-[14px] font-semibold text-text-primary">{n.title}</p>
                {n.body ? (
                  <p className="mt-0.5 text-[13px] leading-5 text-text-secondary">{n.body}</p>
                ) : null}
                <p className="mt-1 text-[12px] text-text-secondary">{formatDate(n.created_at)}</p>
              </div>
            ))}
          </Surface>
        ) : (
          <EmptyState title="最近の動きはありません" />
        )}
      </div>
    </>
  );
}
