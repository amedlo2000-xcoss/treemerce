import { BarChart3, ChevronRight, ImageIcon, Plus } from "lucide-react";
import Link from "next/link";

import { EmptyState, MobilePageHeader, PrimaryButton, StatusPill } from "@/components/mobile/primitives";
import { BackLink, formatDate, formatYen } from "@/components/ui";
import { requireAgentPage } from "@/lib/auth/viewer";
import { SUBMISSION_STATUS_LABELS, SUBMISSION_STATUS_PILL } from "@/lib/domain/enums";
import type { MySubmissionListItem } from "@/lib/domain/types";

/**
 * 商品の持込み申請 (一覧)。表示されるのは自分の申請だけ (treemerce_my_submissions)。
 * 運営が自分の名義で代行作成した申請 (0021) も自分の申請として表示する (閲覧のみ)。
 */
export default async function AgentSubmissionsPage({
  searchParams,
}: {
  searchParams: Promise<{ category?: string }>;
}) {
  const { category } = await searchParams;
  const { supabase } = await requireAgentPage("/agent/submissions");

  const { data, error } = await supabase.rpc("treemerce_my_submissions");
  if (error) throw new Error("申請を読み込めませんでした。");
  const all = (data ?? []) as MySubmissionListItem[];

  // カテゴリで絞り込み (自分の申請にあるカテゴリだけを出す)
  const categories: { id: string; name: string; count: number }[] = [];
  for (const s of all) {
    if (!s.category_id || !s.category_name) continue;
    const entry = categories.find((c) => c.id === s.category_id);
    if (entry) entry.count += 1;
    else categories.push({ id: s.category_id, name: s.category_name, count: 1 });
  }
  const active = categories.some((c) => c.id === category) ? category : undefined;
  const submissions = active ? all.filter((s) => s.category_id === active) : all;
  const chip = (selected: boolean) =>
    `inline-flex items-center gap-1.5 rounded-2xl border px-3 py-1.5 text-[13px] font-medium ${
      selected ? "border-brand bg-brand-soft text-brand" : "border-border-soft bg-surface text-text-primary"
    }`;

  return (
    <>
      <BackLink href="/agent/my">MY</BackLink>
      <MobilePageHeader
        title="商品の持込み申請"
        description="扱ってほしい商品を運営に申請できます。承認されると、運営が価格・在庫を確定してから販売を始めます。"
      />

      <div className="space-y-2">
        <PrimaryButton href="/agent/submissions/new">
          <Plus size={18} />
          新しく申請する
        </PrimaryButton>
        {all.some((s) => s.status === "approved") ? (
          <PrimaryButton href="/agent/sourced-sales" variant="secondary">
            <BarChart3 size={18} />
            持込み商品の売れ行きを見る
          </PrimaryButton>
        ) : null}
      </div>

      {categories.length > 1 ? (
        <nav aria-label="カテゴリで絞り込み" className="flex flex-wrap gap-2">
          <Link href="/agent/submissions" aria-current={!active ? "page" : undefined} className={chip(!active)}>
            すべて <span className="tabular-nums">{all.length}</span>
          </Link>
          {categories.map((c) => (
            <Link
              key={c.id}
              href={`/agent/submissions?category=${c.id}`}
              aria-current={active === c.id ? "page" : undefined}
              className={chip(active === c.id)}
            >
              {c.name} <span className="tabular-nums">{c.count}</span>
            </Link>
          ))}
        </nav>
      ) : null}

      {submissions.length === 0 ? (
        <EmptyState title="まだ申請はありません" description="「新しく申請する」から下書きを作成できます。" />
      ) : (
        <ul className="space-y-3">
          {submissions.map((s) => (
            <li key={s.id}>
              <Link
                href={`/agent/submissions/${s.id}`}
                className="block rounded-[20px] border border-border-soft bg-surface p-4 shadow-[var(--shadow-card)] transition-colors hover:bg-surface-muted"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-1.5">
                      <StatusPill tone={SUBMISSION_STATUS_PILL[s.status] ?? "neutral"}>
                        {SUBMISSION_STATUS_LABELS[s.status] ?? s.status}
                      </StatusPill>
                      {s.status === "approved" ? (
                        <StatusPill tone={s.product_is_published ? "success" : "neutral"}>
                          {s.product_is_published ? "販売中" : "販売準備中"}
                        </StatusPill>
                      ) : null}
                      {s.created_via === "admin_proxy" ? <StatusPill tone="brand">運営が代行作成</StatusPill> : null}
                    </div>
                    <p className="mt-2 truncate text-[16px] font-semibold text-text-primary">{s.name}</p>
                    <p className="mt-0.5 text-[12px] text-text-secondary">
                      <span className="font-mono">{s.submission_no}</span>・更新 {formatDate(s.updated_at)}
                    </p>
                  </div>
                  <ChevronRight size={18} className="mt-1 shrink-0 text-text-secondary" />
                </div>
                <div className="mt-2 flex items-center gap-3 text-[13px] text-text-secondary">
                  {s.category_name ? <span>{s.category_name}</span> : null}
                  <span>希望価格 {s.desired_price != null ? formatYen(Number(s.desired_price)) : "—"}</span>
                  <span className="inline-flex items-center gap-1">
                    <ImageIcon size={14} />
                    {s.image_count}
                  </span>
                </div>
                {s.review_reason ? (
                  <p className="mt-2 line-clamp-2 rounded-xl bg-warning-soft px-3 py-2 text-[13px] leading-5 text-text-primary">
                    {s.status === "returned" ? "差し戻し理由: " : "却下理由: "}
                    {s.review_reason}
                  </p>
                ) : null}
              </Link>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
