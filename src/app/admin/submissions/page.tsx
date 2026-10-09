import Link from "next/link";

import {
  Badge,
  DataTable,
  EmptyState,
  Mono,
  PageHeader,
  SectionTitle,
  TD,
  TD_STRONG,
  formatDateTime,
  formatYen,
} from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import {
  SUBMISSION_STATUSES,
  SUBMISSION_STATUS_BADGE,
  SUBMISSION_STATUS_LABELS,
  type SubmissionStatus,
} from "@/lib/domain/enums";
import type { AdminSubmissionListItem } from "@/lib/domain/types";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * 持込み申請の一覧 (super_admin 専用)。連絡先は一覧に含めない (詳細でのみ表示)。
 * 既定では下書き以外を表示し、申請中を先頭に並べる。
 */
export default async function AdminSubmissionsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; agent?: string }>;
}) {
  const { status, agent } = await searchParams;
  const { supabase } = await requireSuperAdminPage("/admin/submissions");

  const statusFilter = (SUBMISSION_STATUSES as readonly string[]).includes(status ?? "")
    ? (status as SubmissionStatus)
    : null;
  const agentFilter = agent && UUID.test(agent) ? agent : null;

  const { data, error } = await supabase.rpc("treemerce_admin_list_submissions", { p_status: statusFilter });
  if (error) throw new Error("申請を読み込めませんでした。");
  const all = (data ?? []) as AdminSubmissionListItem[];
  const submissions = agentFilter ? all.filter((s) => s.agent_id === agentFilter) : all;
  const agentName = agentFilter ? submissions[0]?.agent_display_name : null;

  const link = (next: string | null) => {
    const params = new URLSearchParams();
    if (next) params.set("status", next);
    if (agentFilter) params.set("agent", agentFilter);
    const q = params.toString();
    return q ? `/admin/submissions?${q}` : "/admin/submissions";
  };

  return (
    <>
      <PageHeader
        title="持込み申請"
        description="代理店からの商品の持込み申請を審査します。承認すると生産者と商品が非公開の下書きで作られ、価格・在庫を確定してから公開します。"
      />

      <nav className="flex flex-wrap gap-2" aria-label="ステータスで絞り込み">
        {[null, ...SUBMISSION_STATUSES].map((s) => {
          const active = (s ?? null) === statusFilter;
          return (
            <Link
              key={s ?? "all"}
              href={link(s)}
              className={`rounded-full border px-3 py-1.5 text-[13px] font-medium ${
                active ? "border-brand bg-brand-soft text-brand" : "border-border-soft text-text-secondary hover:bg-surface-muted"
              }`}
            >
              {s ? SUBMISSION_STATUS_LABELS[s] : "すべて (下書き以外)"}
            </Link>
          );
        })}
      </nav>
      {agentFilter ? (
        <p className="text-[13px] text-text-secondary">
          代理店 {agentName ?? ""} の申請のみ表示中。{" "}
          <Link href={statusFilter ? `/admin/submissions?status=${statusFilter}` : "/admin/submissions"} className="text-brand hover:underline">
            絞り込みを解除
          </Link>
        </p>
      ) : null}

      <SectionTitle count={submissions.length}>申請一覧</SectionTitle>

      {submissions.length === 0 ? (
        <EmptyState title="該当する申請はありません" />
      ) : (
        <DataTable headers={["申請番号", "商品名", "代理店", "生産者", "希望価格", "画像", "状態", "申請日時"]}>
          {submissions.map((s) => (
            <tr key={s.id}>
              <td className={`${TD} whitespace-nowrap`}>
                <Mono>{s.submission_no}</Mono>
              </td>
              <td className={TD_STRONG}>
                <Link href={`/admin/submissions/${s.id}`} className="hover:text-brand">
                  {s.name}
                </Link>
                {s.revision > 1 ? <div className="text-[12px] font-normal text-text-secondary">{s.revision} 回目の申請</div> : null}
              </td>
              <td className={TD}>
                <Mono>{s.agent_public_id}</Mono>
                <div className="text-text-primary">{s.agent_display_name}</div>
              </td>
              <td className={TD}>{s.producer_name ?? "—"}</td>
              <td className={`${TD} tabular-nums`}>{s.desired_price != null ? formatYen(Number(s.desired_price)) : "—"}</td>
              <td className={`${TD} tabular-nums`}>{s.image_count}</td>
              <td className={TD}>
                <Badge tone={SUBMISSION_STATUS_BADGE[s.status] ?? "neutral"}>
                  {SUBMISSION_STATUS_LABELS[s.status] ?? s.status}
                </Badge>
              </td>
              <td className={`${TD} whitespace-nowrap`}>{formatDateTime(s.submitted_at)}</td>
            </tr>
          ))}
        </DataTable>
      )}
    </>
  );
}
