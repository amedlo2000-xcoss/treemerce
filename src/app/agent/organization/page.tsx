import Link from "next/link";
import type { SupabaseClient } from "@supabase/supabase-js";

import { CommerceMapTree } from "@/components/CommerceMapTree";
import { EmptyState, MobilePageHeader, Surface, BigStat } from "@/components/mobile/primitives";
import { requireAgentPage } from "@/lib/auth/viewer";
import type { CommerceMap, CommunityMap, CommunityMapNode } from "@/lib/domain/types";

import { CommunityView, type CommunityTreeNode } from "./CommunityView";

function buildCommunityTree(
  nodes: CommunityMapNode[],
  edges: { from: string; to: string }[],
): CommunityTreeNode[] {
  const byId = new Map<string, CommunityTreeNode>();
  for (const n of nodes) byId.set(n.agent_id, { ...n, children: [] });

  const hasParent = new Set<string>();
  for (const edge of edges) {
    const parent = byId.get(edge.from);
    const child = byId.get(edge.to);
    if (parent && child) {
      parent.children.push(child);
      hasParent.add(child.agent_id);
    }
  }

  return [...byId.values()].filter((n) => !hasParent.has(n.agent_id));
}

async function CommunityTab({ supabase }: { supabase: SupabaseClient }) {
  const { data } = await supabase.rpc("treemerce_community_map", { p_root_agent_id: null });
  const map = data as CommunityMap | null;
  const roots = map ? buildCommunityTree(map.nodes, map.edges) : [];

  return (
    <>
      <p className="px-1 text-[13px] leading-6 text-text-secondary">
        招待経路でつながった代理店のみを表示します（自分＋傘下）。商品購入者はここには含まれません。完全に閲覧専用です。ノードをタップすると詳細が開きます。
      </p>
      {roots.length === 0 ? (
        <Surface>
          <EmptyState title="表示できる代理店がありません" />
        </Surface>
      ) : (
        <CommunityView roots={roots} />
      )}
    </>
  );
}

async function CommerceTab({ supabase }: { supabase: SupabaseClient }) {
  const { data } = await supabase.rpc("treemerce_commerce_map", { p_root_agent_id: null });
  const map = data as CommerceMap | null;

  const namedCount = map?.customers.filter((c) => !c.anonymous).length ?? 0;
  const anonymousCount = map?.customers.filter((c) => c.anonymous).length ?? 0;

  return (
    <>
      <div className="grid grid-cols-3 gap-3">
        <Surface className="!p-4">
          <BigStat label="傘下代理店" value={map?.agents.length ?? 0} />
        </Surface>
        <Surface className="!p-4">
          <BigStat label="自分の担当" value={namedCount} hint="実名表示" />
        </Surface>
        <Surface className="!p-4">
          <BigStat label="傘下の担当" value={anonymousCount} hint="匿名表示" />
        </Surface>
      </div>

      <Surface>
        <p className="mb-4 text-[13px] leading-6 text-text-secondary">
          自分が担当する購入者は実名・購入商品を表示します。傘下の他代理店が担当する購入者は件数のみの匿名ノードです。招待元や別系統の代理店は表示されません。この画面は閲覧専用です。
        </p>
        {!map || map.agents.length === 0 ? (
          <EmptyState title="表示できるデータがありません" />
        ) : (
          <CommerceMapTree map={map} />
        )}
      </Surface>
    </>
  );
}

/**
 * STEP7 (組織画面): 「代理店コミュニティ」と「商流マップ」をタブで分離する。
 * 目的が異なるデータのため、片方のタブでもう片方のデータを混在させない。
 */
export default async function OrganizationPage({
  searchParams,
}: {
  searchParams: Promise<{ tab?: string }>;
}) {
  const { tab: rawTab } = await searchParams;
  const tab = rawTab === "commerce" ? "commerce" : "community";
  const { supabase } = await requireAgentPage("/agent/organization");

  return (
    <>
      <MobilePageHeader
        title="組織"
        description="代理店同士のつながりと、担当顧客の広がりを確認できます。"
      />

      <div className="flex gap-2 px-1">
        <Link
          href="/agent/organization?tab=community"
          className={`flex-1 rounded-2xl border px-4 py-2.5 text-center text-[14px] font-medium transition-colors ${
            tab === "community"
              ? "border-brand bg-brand-soft text-brand"
              : "border-border-soft bg-surface text-text-primary"
          }`}
        >
          代理店コミュニティ
        </Link>
        <Link
          href="/agent/organization?tab=commerce"
          className={`flex-1 rounded-2xl border px-4 py-2.5 text-center text-[14px] font-medium transition-colors ${
            tab === "commerce"
              ? "border-brand bg-brand-soft text-brand"
              : "border-border-soft bg-surface text-text-primary"
          }`}
        >
          商流マップ
        </Link>
      </div>

      {tab === "community" ? (
        <CommunityTab supabase={supabase} />
      ) : (
        <CommerceTab supabase={supabase} />
      )}
    </>
  );
}
