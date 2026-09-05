import { Badge, EmptyState, Notice, PageHeader, formatDate } from "@/components/ui";
import { requireAgentPage } from "@/lib/auth/viewer";
import { AGENT_STATUS_LABELS } from "@/lib/domain/enums";
import type { CommunityMap, CommunityMapNode } from "@/lib/domain/types";

type TreeNode = CommunityMapNode & { children: TreeNode[] };

function buildTree(nodes: CommunityMapNode[], edges: { from: string; to: string }[]): TreeNode[] {
  const byId = new Map<string, TreeNode>();
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

function NodeItem({ node }: { node: TreeNode }) {
  return (
    <li className="space-y-2">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-mono text-xs text-zinc-500 dark:text-zinc-400">{node.public_id}</span>
        <span className="text-sm font-medium text-zinc-900 dark:text-zinc-100">
          {node.display_name}
        </span>
        {node.is_self ? <Badge tone="blue">自分</Badge> : null}
        <Badge tone={node.status === "active" ? "green" : "neutral"}>
          {AGENT_STATUS_LABELS[node.status] ?? node.status}
        </Badge>
        {node.prefecture ? (
          <span className="text-[11px] text-zinc-400 dark:text-zinc-500">{node.prefecture}</span>
        ) : null}
        <span className="text-[11px] text-zinc-400 dark:text-zinc-500">
          {formatDate(node.registered_at)} 登録
        </span>
      </div>
      {node.children.length > 0 ? (
        <ul className="ml-4 space-y-2 border-l border-zinc-200 pl-4 dark:border-zinc-800">
          {node.children.map((child) => (
            <NodeItem key={child.agent_id} node={child} />
          ))}
        </ul>
      ) : null}
    </li>
  );
}

/** STEP7: 代理店コミュニティマップ。代理店のみをノードとして表示し、購入者は含めない。 */
export default async function CommunityMapPage() {
  const { supabase } = await requireAgentPage("/agent/community");

  const { data } = await supabase.rpc("treemerce_community_map", { p_root_agent_id: null });
  const map = data as CommunityMap | null;
  const roots = map ? buildTree(map.nodes, map.edges) : [];

  return (
    <>
      <PageHeader
        title="代理店コミュニティマップ"
        description="招待経路でつながった代理店のつながりを表示します。"
      />

      <Notice tone="info">
        このマップに表示されるのは代理店のみです。商品購入者はここには含まれません。
      </Notice>

      {roots.length === 0 ? (
        <EmptyState title="表示できる代理店がありません" />
      ) : (
        <div className="rounded-xl border border-zinc-200 bg-white p-5 dark:border-zinc-800 dark:bg-zinc-950">
          <ul className="space-y-3">
            {roots.map((root) => (
              <NodeItem key={root.agent_id} node={root} />
            ))}
          </ul>
        </div>
      )}
    </>
  );
}
