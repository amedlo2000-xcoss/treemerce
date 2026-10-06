"use client";

import { LayoutGrid, Network as NetworkIcon } from "lucide-react";
import { useMemo, useState } from "react";

import { BottomSheet } from "@/components/mobile/BottomSheet";
import { SwipeDeck } from "@/components/mobile/SwipeDeck";
import { ProfileHero, StatTile, StatusPill, Surface } from "@/components/mobile/primitives";
import { formatDate } from "@/components/ui";
import { AGENT_STATUS_LABELS } from "@/lib/domain/enums";
import type { CommunityMapNode } from "@/lib/domain/types";

export type CommunityTreeNode = CommunityMapNode & { children: CommunityTreeNode[] };

type FlatAgent = {
  node: CommunityTreeNode;
  parentName: string | null;
  descendantCount: number;
};

function countDescendants(node: CommunityTreeNode): number {
  return node.children.reduce((sum, c) => sum + 1 + countDescendants(c), 0);
}

function flatten(roots: CommunityTreeNode[], parentName: string | null = null): FlatAgent[] {
  return roots.flatMap((node) => [
    { node, parentName, descendantCount: countDescendants(node) },
    ...flatten(node.children, node.display_name),
  ]);
}

const STATUS_TONE = {
  active: "success",
  pending: "warning",
  suspended: "danger",
  withdrawn: "neutral",
} as const;

function AgentProfileCard({ item }: { item: FlatAgent }) {
  const { node } = item;
  return (
    <div className="h-full [&>section]:h-full">
      <ProfileHero
        compact
        name={node.display_name}
        subtitle={node.public_id}
        mono
        pills={
          <>
            {node.is_self ? <StatusPill tone="brand">自分</StatusPill> : null}
            <StatusPill tone={STATUS_TONE[node.status] ?? "neutral"}>
              {AGENT_STATUS_LABELS[node.status] ?? node.status}
            </StatusPill>
            {node.prefecture ? <StatusPill>{node.prefecture}</StatusPill> : null}
          </>
        }
        meta={
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-2">
              <StatTile label="登録日" value={formatDate(node.registered_at)} />
              <StatTile label="傘下代理店" value={item.descendantCount} />
            </div>
            <div className="rounded-2xl border border-border-soft px-3 py-2.5">
              <p className="text-[12px] text-text-secondary">招待元 (登録経路)</p>
              <p className="mt-0.5 text-[14px] font-medium text-text-primary">
                {node.is_self ? "自分" : (item.parentName ?? "—")}
              </p>
            </div>
          </div>
        }
      />
    </div>
  );
}

function TreeNodeItem({
  node,
  parentName,
  onSelect,
}: {
  node: CommunityTreeNode;
  parentName: string | null;
  onSelect: (item: FlatAgent) => void;
}) {
  return (
    <li className="space-y-2">
      <button
        type="button"
        onClick={() => onSelect({ node, parentName, descendantCount: countDescendants(node) })}
        className="flex w-full flex-wrap items-center gap-2 rounded-xl px-1 py-1 text-left transition-colors hover:bg-surface-muted"
      >
        <span className="font-mono text-[11px] text-text-secondary">{node.public_id}</span>
        <span className="text-[14px] font-medium text-text-primary">{node.display_name}</span>
        {node.is_self ? <StatusPill tone="brand">自分</StatusPill> : null}
        <StatusPill tone={STATUS_TONE[node.status] ?? "neutral"}>
          {AGENT_STATUS_LABELS[node.status] ?? node.status}
        </StatusPill>
      </button>
      {node.children.length > 0 ? (
        <ul className="ml-4 space-y-2 border-l border-border-soft pl-4">
          {node.children.map((child) => (
            <TreeNodeItem
              key={child.agent_id}
              node={child}
              parentName={node.display_name}
              onSelect={onSelect}
            />
          ))}
        </ul>
      ) : null}
    </li>
  );
}

export function CommunityView({ roots }: { roots: CommunityTreeNode[] }) {
  const [view, setView] = useState<"tree" | "card">("tree");
  const [selected, setSelected] = useState<FlatAgent | null>(null);
  const flat = useMemo(() => flatten(roots), [roots]);

  return (
    <div className="space-y-3">
      <div className="flex justify-end">
        <div className="flex shrink-0 overflow-hidden rounded-2xl border border-border-soft">
          <button
            type="button"
            aria-pressed={view === "tree"}
            onClick={() => setView("tree")}
            className={`flex h-10 items-center gap-1.5 px-3 text-[13px] font-medium ${
              view === "tree" ? "bg-brand-soft text-brand" : "bg-surface text-text-secondary"
            }`}
          >
            <NetworkIcon size={16} /> ツリー
          </button>
          <button
            type="button"
            aria-pressed={view === "card"}
            onClick={() => setView("card")}
            className={`flex h-10 items-center gap-1.5 px-3 text-[13px] font-medium ${
              view === "card" ? "bg-brand-soft text-brand" : "bg-surface text-text-secondary"
            }`}
          >
            <LayoutGrid size={16} /> カード
          </button>
        </div>
      </div>

      {view === "tree" ? (
        <Surface>
          <ul className="space-y-3">
            {roots.map((root) => (
              <TreeNodeItem key={root.agent_id} node={root} parentName={null} onSelect={setSelected} />
            ))}
          </ul>
        </Surface>
      ) : (
        <SwipeDeck
          items={flat}
          keyFor={(item) => item.node.agent_id}
          renderCard={(item) => <AgentProfileCard item={item} />}
        />
      )}

      <BottomSheet open={!!selected} onClose={() => setSelected(null)} title={selected?.node.display_name}>
        {selected ? <AgentProfileCard item={selected} /> : null}
      </BottomSheet>
    </div>
  );
}
