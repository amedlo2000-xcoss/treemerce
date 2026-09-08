"use client";

import { LayoutGrid, List, Search } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";

import { SwipeDeck } from "@/components/mobile/SwipeDeck";
import { Chip, StatusPill, Surface } from "@/components/mobile/primitives";
import { formatDate, formatYen } from "@/components/ui";
import {
  AGE_GROUP_LABELS,
  CUSTOMER_TYPE_LABELS,
  CUSTOMER_TYPES,
  GENDER_LABELS,
} from "@/lib/domain/enums";

export type CustomerListItem = {
  id: string;
  full_name: string;
  email: string | null;
  phone: string | null;
  prefecture: string | null;
  age_group: string | null;
  gender: string | null;
  customer_type: string;
  assigned_at: string;
  total_amount: number;
  product_names: string[];
};

function CustomerCard({ item }: { item: CustomerListItem }) {
  return (
    <Surface className="flex h-full flex-col">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="truncate text-[19px] font-bold text-text-primary">{item.full_name}</p>
          <p className="mt-0.5 text-[13px] text-text-secondary">
            {item.age_group ? (AGE_GROUP_LABELS[item.age_group] ?? "—") : "未回答"} ・{" "}
            {item.gender ? (GENDER_LABELS[item.gender] ?? "—") : "未回答"}
            {item.prefecture ? ` ・ ${item.prefecture}` : ""}
          </p>
        </div>
        <StatusPill tone="brand">{CUSTOMER_TYPE_LABELS[item.customer_type] ?? item.customer_type}</StatusPill>
      </div>

      <dl className="mt-4 grid grid-cols-2 gap-3">
        <div className="rounded-2xl bg-surface-muted px-3 py-2.5">
          <dt className="text-[12px] text-text-secondary">担当開始日</dt>
          <dd className="mt-0.5 text-[14px] font-semibold text-text-primary">
            {formatDate(item.assigned_at)}
          </dd>
        </div>
        <div className="rounded-2xl bg-surface-muted px-3 py-2.5">
          <dt className="text-[12px] text-text-secondary">購入合計</dt>
          <dd className="mt-0.5 text-[14px] font-semibold tabular-nums text-text-primary">
            {formatYen(item.total_amount)}
          </dd>
        </div>
      </dl>

      <div className="mt-4 flex-1">
        <p className="text-[12px] text-text-secondary">購入商品</p>
        {item.product_names.length > 0 ? (
          <div className="mt-1.5 flex flex-wrap gap-1.5">
            {item.product_names.map((name) => (
              <span
                key={name}
                className="rounded-full border border-border-soft px-2.5 py-1 text-[12px] text-text-primary"
              >
                {name}
              </span>
            ))}
          </div>
        ) : (
          <p className="mt-1 text-[13px] text-text-secondary">購入履歴はありません</p>
        )}
      </div>

      <Link
        href={`/agent/customers/${item.id}`}
        className="mt-4 inline-flex h-11 items-center justify-center rounded-2xl bg-brand text-[14px] font-semibold text-brand-foreground"
      >
        詳細を見る
      </Link>
    </Surface>
  );
}

function CustomerListRow({ item }: { item: CustomerListItem }) {
  return (
    <Link href={`/agent/customers/${item.id}`}>
      <Surface className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-[16px] font-semibold text-text-primary">{item.full_name}</p>
          <p className="mt-0.5 text-[12px] text-text-secondary">
            {item.age_group ? (AGE_GROUP_LABELS[item.age_group] ?? "—") : "未回答"}
            {item.prefecture ? ` ・ ${item.prefecture}` : ""}
            {item.product_names[0] ? ` ・ ${item.product_names[0]}` : ""}
          </p>
        </div>
        <div className="shrink-0 text-right">
          <p className="text-[14px] font-semibold tabular-nums text-text-primary">
            {formatYen(item.total_amount)}
          </p>
          <p className="text-[11px] text-text-secondary">{formatDate(item.assigned_at)}</p>
        </div>
      </Surface>
    </Link>
  );
}

export function CustomerBrowser({ items }: { items: CustomerListItem[] }) {
  const [view, setView] = useState<"card" | "list">("list");
  const [query, setQuery] = useState("");
  const [typeFilter, setTypeFilter] = useState<string | null>(null);

  const filtered = useMemo(() => {
    return items.filter((item) => {
      if (typeFilter && item.customer_type !== typeFilter) return false;
      if (query && !item.full_name.toLowerCase().includes(query.toLowerCase())) return false;
      return true;
    });
  }, [items, query, typeFilter]);

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <div className="flex flex-1 items-center gap-2 rounded-2xl border border-border-soft bg-surface px-3.5 py-2.5">
          <Search size={17} className="text-text-secondary" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="氏名で検索"
            className="w-full bg-transparent text-[15px] text-text-primary outline-none placeholder:text-text-secondary"
          />
        </div>
        <div className="flex shrink-0 overflow-hidden rounded-2xl border border-border-soft">
          <button
            type="button"
            aria-label="一覧表示"
            aria-pressed={view === "list"}
            onClick={() => setView("list")}
            className={`flex h-11 w-11 items-center justify-center ${
              view === "list" ? "bg-brand-soft text-brand" : "bg-surface text-text-secondary"
            }`}
          >
            <List size={18} />
          </button>
          <button
            type="button"
            aria-label="カード表示"
            aria-pressed={view === "card"}
            onClick={() => setView("card")}
            className={`flex h-11 w-11 items-center justify-center ${
              view === "card" ? "bg-brand-soft text-brand" : "bg-surface text-text-secondary"
            }`}
          >
            <LayoutGrid size={18} />
          </button>
        </div>
      </div>

      <div className="flex flex-wrap gap-2">
        <Chip selected={typeFilter === null} onClick={() => setTypeFilter(null)}>
          すべて
        </Chip>
        {CUSTOMER_TYPES.map((type) => (
          <Chip key={type} selected={typeFilter === type} onClick={() => setTypeFilter(type)}>
            {CUSTOMER_TYPE_LABELS[type]}
          </Chip>
        ))}
      </div>

      {filtered.length === 0 ? (
        <Surface>
          <p className="text-center text-[14px] text-text-secondary">該当する顧客が見つかりません</p>
        </Surface>
      ) : view === "list" ? (
        <div className="space-y-2.5 md:grid md:grid-cols-2 md:gap-3 md:space-y-0 lg:grid-cols-3">
          {filtered.map((item) => (
            <CustomerListRow key={item.id} item={item} />
          ))}
        </div>
      ) : (
        <SwipeDeck
          items={filtered}
          keyFor={(item) => item.id}
          renderCard={(item) => <CustomerCard item={item} />}
        />
      )}
    </div>
  );
}
