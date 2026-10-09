import { BarChart3, ChevronRight, ImageIcon, Plus } from "lucide-react";
import Link from "next/link";

import { EmptyState, MobilePageHeader, PrimaryButton, StatusPill } from "@/components/mobile/primitives";
import { BackLink, formatDate, formatYen } from "@/components/ui";
import { requireAgentPage } from "@/lib/auth/viewer";
import { SUBMISSION_STATUS_LABELS, SUBMISSION_STATUS_PILL } from "@/lib/domain/enums";
import type { MySubmissionListItem } from "@/lib/domain/types";

/**
 * 商品の持込み申請 (一覧)。表示されるのは自分の申請だけ (treemerce_my_submissions)。
 */
export default async function AgentSubmissionsPage() {
  const { supabase } = await requireAgentPage("/agent/submissions");

  const { data, error } = await supabase.rpc("treemerce_my_submissions");
  if (error) throw new Error("申請を読み込めませんでした。");
  const submissions = (data ?? []) as MySubmissionListItem[];

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
        {submissions.some((s) => s.status === "approved") ? (
          <PrimaryButton href="/agent/sourced-sales" variant="secondary">
            <BarChart3 size={18} />
            持込み商品の売れ行きを見る
          </PrimaryButton>
        ) : null}
      </div>

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
                    </div>
                    <p className="mt-2 truncate text-[16px] font-semibold text-text-primary">{s.name}</p>
                    <p className="mt-0.5 text-[12px] text-text-secondary">
                      <span className="font-mono">{s.submission_no}</span>・更新 {formatDate(s.updated_at)}
                    </p>
                  </div>
                  <ChevronRight size={18} className="mt-1 shrink-0 text-text-secondary" />
                </div>
                <div className="mt-2 flex items-center gap-3 text-[13px] text-text-secondary">
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
