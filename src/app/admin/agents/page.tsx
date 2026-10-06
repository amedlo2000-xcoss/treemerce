import { ChevronRight, Search } from "lucide-react";
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
import type { AgentRow } from "@/lib/domain/types";

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

  const { data } = await query;

  const agents = (data ?? []) as AgentRow[];
  const byId = new Map(agents.map((a) => [a.id, a]));

  return (
    <>
      <PageHeader
        title="代理店管理"
        description="全代理店を横断して検索し、登録経路 (招待元) と利用開始状態を確認します。"
      />

      <Notice tone="warning">
        招待元は1代理店につき1つで、一度確定すると変更できません。
        招待元は代理店の登録経路を表すもので、購入者の担当代理店とは別のデータです。
      </Notice>

      <FilterPanel>
        <form
          method="get"
          className="grid gap-3 sm:grid-cols-2 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_minmax(0,1fr)_auto] lg:items-end"
        >
          <Field label="検索 (名前・email・電話・代理店ID)">
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

      <SectionTitle count={agents.length}>代理店一覧</SectionTitle>

      {agents.length === 0 ? (
        <EmptyState title="該当する代理店がありません" />
      ) : (
        <DataTable
          headers={["代理店ID", "代理店名", "連絡先", "招待元 (登録経路)", "状態", "登録日", ""]}
        >
          {agents.map((agent) => {
            const inviter = agent.invited_by ? byId.get(agent.invited_by) : null;
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
                <td className={TD}>
                  <Badge tone={AGENT_STATUS_TONE[agent.status] ?? "neutral"}>
                    {AGENT_STATUS_LABELS[agent.status] ?? agent.status}
                  </Badge>
                </td>
                <td className={TD}>{formatDate(agent.registered_at)}</td>
                <td className={`${TD} text-right`}>
                  <Link
                    href={`/admin/agents/${agent.id}`}
                    className="inline-flex items-center gap-0.5 whitespace-nowrap text-[13px] font-semibold text-brand hover:underline"
                  >
                    詳細
                    <ChevronRight size={14} />
                  </Link>
                </td>
              </tr>
            );
          })}
        </DataTable>
      )}
    </>
  );
}
