import { ChevronRight, PackagePlus, Pencil, Search } from "lucide-react";
import Link from "next/link";

import {
  AGENT_STATUS_TONE,
  BUTTON_CLASS,
  Badge,
  DataTable,
  EmptyState,
  FIELD_CLASS,
  Field,
  FilterPanel,
  Mono,
  Notice,
  PageHeader,
  SectionTitle,
  TD,
  TD_STRONG,
  formatDate,
} from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import { AGENT_STATUSES, AGENT_STATUS_LABELS, PREFECTURES } from "@/lib/domain/enums";
import type { AgentOverviewRow, AgentRow } from "@/lib/domain/types";

/** 事業プロフィールの項目数 (0016 の app.agent_profile_filled_fields と同じ 8 項目) */
const PROFILE_FIELD_COUNT = 8;

/**
 * STEP8 + 統括管理: 代理店の横断一覧・検索。
 * ここで扱うのは「代理店の登録経路 (invited_by)」だけ。
 * 顧客の担当関係は別メニュー (顧客担当管理) の責務であり、この画面には出さない。
 * super_admin 専用 (requireSuperAdminPage)。
 */
export default async function AdminAgentsPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; status?: string; prefecture?: string }>;
}) {
  const { q, status, prefecture } = await searchParams;
  const { supabase } = await requireSuperAdminPage("/admin/agents");

  let query = supabase
    .from("agents")
    .select(
      "id, public_id, display_name, email, phone, prefecture, status, invited_by, registered_at",
    )
    .order("registered_at", { ascending: true });

  const term = q?.trim();
  if (term) {
    const safe = term.replace(/[,()%]/g, "");
    query = query.or(
      `display_name.ilike.%${safe}%,email.ilike.%${safe}%,phone.ilike.%${safe}%,public_id.ilike.%${safe}%`,
    );
  }
  if (status && (AGENT_STATUSES as readonly string[]).includes(status)) {
    query = query.eq("status", status);
  }
  if (prefecture) {
    query = query.eq("prefecture", prefecture);
  }

  // 0021: プロフィールの入力済み項目数と持込み申請の件数 (件数のみ・値は含まない)
  const [{ data }, { data: overviewData }] = await Promise.all([
    query,
    supabase.rpc("treemerce_admin_list_agent_overview"),
  ]);

  const agents = (data ?? []) as AgentRow[];
  const byId = new Map(agents.map((a) => [a.id, a]));
  const overview = new Map(((overviewData ?? []) as AgentOverviewRow[]).map((o) => [o.agent_id, o]));

  return (
    <>
      <PageHeader
        title="オブザーバー管理"
        description="全オブザーバーを横断して検索し、登録経路 (招待元) と利用開始状態を確認します。各行から詳細・プロフィール編集・持込み申請の代行へ移動できます。"
      />

      <Notice tone="warning">
        招待元は1オブザーバーにつき1つで、一度確定すると変更できません。
        招待元はオブザーバーの登録経路を表すもので、購入者の担当オブザーバーとは別のデータです。
      </Notice>

      <FilterPanel>
        <form
          method="get"
          className="grid gap-3 sm:grid-cols-2 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_minmax(0,1fr)_auto] lg:items-end"
        >
          <Field label="検索 (名前・email・電話・オブザーバーID)">
            <input
              type="text"
              name="q"
              defaultValue={q ?? ""}
              className={FIELD_CLASS}
              placeholder="例: 山田 / yamada@example.com"
            />
          </Field>
          <Field label="状態">
            <select name="status" defaultValue={status ?? ""} className={FIELD_CLASS}>
              <option value="">すべて</option>
              {AGENT_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {AGENT_STATUS_LABELS[s]}
                </option>
              ))}
            </select>
          </Field>
          <Field label="都道府県">
            <select name="prefecture" defaultValue={prefecture ?? ""} className={FIELD_CLASS}>
              <option value="">すべて</option>
              {PREFECTURES.map((p) => (
                <option key={p} value={p}>
                  {p}
                </option>
              ))}
            </select>
          </Field>
          <div className="flex items-center gap-3">
            <button type="submit" className={`${BUTTON_CLASS} flex-1 lg:flex-none`}>
              <Search size={16} />
              検索
            </button>
            {q || status || prefecture ? (
              <Link
                href="/admin/agents"
                className="whitespace-nowrap text-[13px] font-medium text-text-secondary hover:text-text-primary"
              >
                クリア
              </Link>
            ) : null}
          </div>
        </form>
      </FilterPanel>

      <SectionTitle count={agents.length}>オブザーバー一覧</SectionTitle>

      {agents.length === 0 ? (
        <EmptyState title="該当するオブザーバーがありません" />
      ) : (
        <DataTable
          headers={["オブザーバーID", "オブザーバー名", "連絡先", "招待元 (登録経路)", "プロフィール", "持込み", "状態", "登録日", "操作"]}
        >
          {agents.map((agent) => {
            const inviter = agent.invited_by ? byId.get(agent.invited_by) : null;
            const o = overview.get(agent.id);
            const counts = o?.submission_counts;
            return (
              <tr key={agent.id}>
                <td className={TD}>
                  <Mono>{agent.public_id}</Mono>
                </td>
                <td className={TD_STRONG}>
                  <Link href={`/admin/agents/${agent.id}`} className="hover:text-brand">
                    {agent.display_name}
                  </Link>
                </td>
                <td className={TD}>
                  {agent.email}
                  <br />
                  {agent.phone ?? "—"}
                </td>
                <td className={TD}>
                  {inviter ? (
                    <>
                      <Mono>{inviter.public_id}</Mono>{" "}
                      <span className="text-text-primary">{inviter.display_name}</span>
                    </>
                  ) : (
                    <span className="text-text-secondary">直接登録 (招待元なし)</span>
                  )}
                </td>
                <td className={`${TD} whitespace-nowrap`}>
                  {o && o.profile_filled_count > 0 ? (
                    <>
                      <span className="tabular-nums text-text-primary">
                        {o.profile_filled_count} / {PROFILE_FIELD_COUNT} 項目
                      </span>
                      <div className="text-[12px]">
                        {o.profile_updated_by_role === "super_admin" ? "運営が更新" : "本人が更新"}
                      </div>
                    </>
                  ) : (
                    "未入力"
                  )}
                </td>
                <td className={`${TD} whitespace-nowrap tabular-nums`}>
                  {counts && counts.submitted + counts.returned + counts.approved + counts.proxy_draft > 0 ? (
                    <>
                      {counts.submitted > 0 ? <div className="font-medium text-warning">申請中 {counts.submitted}</div> : null}
                      {counts.returned > 0 ? <div>差し戻し {counts.returned}</div> : null}
                      {counts.proxy_draft > 0 ? <div>代行の下書き {counts.proxy_draft}</div> : null}
                      <div>承認 {counts.approved}</div>
                    </>
                  ) : (
                    "—"
                  )}
                </td>
                <td className={TD}>
                  <Badge tone={AGENT_STATUS_TONE[agent.status] ?? "neutral"}>
                    {AGENT_STATUS_LABELS[agent.status] ?? agent.status}
                  </Badge>
                </td>
                <td className={TD}>{formatDate(agent.registered_at)}</td>
                <td className={TD}>
                  <div className="flex flex-col items-start gap-1.5">
                    <Link
                      href={`/admin/agents/${agent.id}`}
                      className="inline-flex items-center gap-0.5 whitespace-nowrap text-[13px] font-semibold text-brand hover:underline"
                    >
                      詳細
                      <ChevronRight size={14} />
                    </Link>
                    {agent.status !== "withdrawn" ? (
                      <Link
                        href={`/admin/agents/${agent.id}/profile`}
                        className="inline-flex items-center gap-1 whitespace-nowrap text-[13px] font-medium text-brand hover:underline"
                      >
                        <Pencil size={13} />
                        プロフィール編集
                      </Link>
                    ) : null}
                    {agent.status === "active" ? (
                      <Link
                        href={`/admin/agents/${agent.id}/submissions/new`}
                        className="inline-flex items-center gap-1 whitespace-nowrap text-[13px] font-medium text-brand hover:underline"
                      >
                        <PackagePlus size={13} />
                        持込み代行
                      </Link>
                    ) : null}
                  </div>
                </td>
              </tr>
            );
          })}
        </DataTable>
      )}
    </>
  );
}
