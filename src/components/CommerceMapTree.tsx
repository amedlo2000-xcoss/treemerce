import { Badge, formatYen } from "@/components/ui";
import { PRODUCT_CATEGORY_LABELS } from "@/lib/domain/enums";
import type { CommerceMap, CommerceMapAgent, CommerceMapCustomer } from "@/lib/domain/types";

type TreeNode = CommerceMapAgent & { children: TreeNode[] };

function buildTree(agents: CommerceMapAgent[]): TreeNode[] {
  const byId = new Map<string, TreeNode>();
  for (const agent of agents) byId.set(agent.agent_id, { ...agent, children: [] });

  const roots: TreeNode[] = [];
  for (const node of byId.values()) {
    // 招待元が部分木の外にいる場合 (= 自分自身が根) はここで root になる。
    const parent = node.invited_by ? byId.get(node.invited_by) : undefined;
    if (parent) parent.children.push(node);
    else roots.push(node);
  }

  const sortRec = (nodes: TreeNode[]) => {
    nodes.sort((a, b) => a.public_id.localeCompare(b.public_id));
    for (const n of nodes) sortRec(n.children);
  };
  sortRec(roots);

  return roots;
}

function CustomerNode({ customer }: { customer: CommerceMapCustomer }) {
  if (customer.anonymous) {
    return (
      <li className="flex items-center gap-2 rounded-lg border border-dashed border-zinc-300 px-3 py-2 dark:border-zinc-700">
        <span className="font-mono text-xs text-zinc-500 dark:text-zinc-400">{customer.label}</span>
        <Badge tone="neutral">匿名</Badge>
        <span className="text-[11px] text-zinc-400 dark:text-zinc-500">
          他代理店の担当のため詳細は表示されません
        </span>
      </li>
    );
  }

  const total = customer.purchases.reduce((sum, p) => sum + Number(p.amount ?? 0), 0);

  return (
    <li className="rounded-lg border border-zinc-200 bg-white px-3 py-2 dark:border-zinc-800 dark:bg-zinc-950">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm font-medium text-zinc-900 dark:text-zinc-100">
          {customer.label}
        </span>
        <Badge tone="blue">自分の担当</Badge>
        {customer.prefecture ? (
          <span className="text-[11px] text-zinc-500 dark:text-zinc-400">
            {customer.prefecture}
          </span>
        ) : null}
      </div>
      {customer.purchases.length > 0 ? (
        <ul className="mt-1.5 space-y-0.5">
          {customer.purchases.map((p) => (
            <li key={p.purchase_id} className="text-xs text-zinc-600 dark:text-zinc-400">
              {p.product_name}
              <span className="ml-1.5 text-zinc-400 dark:text-zinc-500">
                ({PRODUCT_CATEGORY_LABELS[p.product_category] ?? p.product_category} ·{" "}
                {formatYen(Number(p.amount))})
              </span>
            </li>
          ))}
          <li className="text-xs font-medium text-zinc-700 dark:text-zinc-300">
            合計 {formatYen(total)}
          </li>
        </ul>
      ) : (
        <p className="mt-1 text-xs text-zinc-400 dark:text-zinc-500">購入履歴はありません</p>
      )}
    </li>
  );
}

function AgentNode({
  node,
  customersByAgent,
}: {
  node: TreeNode;
  customersByAgent: Map<string, CommerceMapCustomer[]>;
}) {
  const customers = customersByAgent.get(node.agent_id) ?? [];
  const anonymousCount = customers.filter((c) => c.anonymous).length;

  return (
    <li className="space-y-2">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-mono text-xs text-zinc-500 dark:text-zinc-400">{node.public_id}</span>
        <span className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">
          {node.display_name}
        </span>
        {node.is_self ? <Badge tone="blue">自分</Badge> : null}
        <Badge tone="neutral">担当顧客 {node.customer_count}件</Badge>
        {anonymousCount > 0 ? (
          <span className="text-[11px] text-zinc-400 dark:text-zinc-500">
            (うち匿名表示 {anonymousCount}件)
          </span>
        ) : null}
      </div>

      {customers.length > 0 ? (
        <ul className="ml-4 space-y-1.5 border-l border-zinc-200 pl-4 dark:border-zinc-800">
          {customers.map((c, i) => (
            <CustomerNode key={c.anonymous ? `anon-${node.agent_id}-${i}` : c.customer_id} customer={c} />
          ))}
        </ul>
      ) : null}

      {node.children.length > 0 ? (
        <ul className="ml-4 space-y-4 border-l border-zinc-200 pl-4 dark:border-zinc-800">
          {node.children.map((child) => (
            <AgentNode key={child.agent_id} node={child} customersByAgent={customersByAgent} />
          ))}
        </ul>
      ) : null}
    </li>
  );
}

export function CommerceMapTree({ map }: { map: CommerceMap }) {
  const roots = buildTree(map.agents);

  const customersByAgent = new Map<string, CommerceMapCustomer[]>();
  for (const customer of map.customers) {
    const list = customersByAgent.get(customer.agent_id) ?? [];
    list.push(customer);
    customersByAgent.set(customer.agent_id, list);
  }

  return (
    <ul className="space-y-4">
      {roots.map((root) => (
        <AgentNode key={root.agent_id} node={root} customersByAgent={customersByAgent} />
      ))}
    </ul>
  );
}
