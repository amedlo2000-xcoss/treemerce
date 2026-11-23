import { Search } from "lucide-react";
import Link from "next/link";

import { ConfirmReasonDialog } from "@/components/ConfirmReasonDialog";
import {
  BUTTON_CLASS,
  Badge,
  CURRENCY_UNIT,
  DataTable,
  EmptyState,
  FIELD_CLASS,
  Field,
  FilterPanel,
  Mono,
  Notice,
  PageHeader,
  SectionTitle,
  Stat,
  TD,
  TD_STRONG,
  formatAmount,
  formatDate,
} from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import { REWARD_ROLE_LABELS, formatRate, type AdminRewardEntry } from "@/lib/domain/rewards";

import { RewardTabs } from "./RewardTabs";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * 報酬明細 (super_admin)。treemerce_admin_list_reward_entries (0033, STABLE) の全件表示。
 * オブザーバーは RPC の p_agent_id (受取人または出店者) で、注文番号は返った明細の注文番号で絞り込む。
 * 注文ごとに treemerce_admin_reverse_order_rewards で取り消し (マイナスの明細) を作れる (理由必須)。
 */
export default async function AdminRewardsPage({
  searchParams,
}: {
  searchParams: Promise<{ agent?: string; order?: string }>;
}) {
  const { agent: agentParam, order: orderParam } = await searchParams;
  const agentId = agentParam && UUID_RE.test(agentParam) ? agentParam : null;
  const orderTerm = orderParam?.trim() ?? "";
  const { supabase } = await requireSuperAdminPage("/admin/rewards");

  const [{ data, error }, { data: agentData }] = await Promise.all([
    supabase.rpc("treemerce_admin_list_reward_entries", {
      p_agent_id: agentId,
      p_limit: 5000,
    }),
    supabase.from("agents").select("id, public_id, display_name").order("registered_at", { ascending: true }),
  ]);
  if (error) throw new Error("報酬明細を読み込めませんでした。");

  const all = (data ?? []) as AdminRewardEntry[];
  const entries = orderTerm
    ? all.filter((e) => e.order_no.toLowerCase().includes(orderTerm.toLowerCase()))
    : all;
  const agents = (agentData ?? []) as { id: string; public_id: string; display_name: string }[];

  // 注文ごとにまとめる (新しい明細の注文から)
  const groups: { orderId: string; orderNo: string; entries: AdminRewardEntry[] }[] = [];
  const byOrder = new Map<string, (typeof groups)[number]>();
  for (const e of entries) {
    let g = byOrder.get(e.order_id);
    if (!g) {
      g = { orderId: e.order_id, orderNo: e.order_no, entries: [] };
      byOrder.set(e.order_id, g);
      groups.push(g);
    }
    g.entries.push(e);
  }

  const sumBy = (role: AdminRewardEntry["recipient_role"]) =>
    entries.filter((e) => e.recipient_role === role).reduce((s, e) => s + Number(e.amount), 0);

  return (
    <>
      <PageHeader
        title="報酬"
        description="注文が入金確認済みで全生産者の発送が済んだ時点で確定した報酬明細 (出店者・紹介者・運営) です。明細は書き換え・削除できず、取り消しはマイナスの明細で表します。"
      />

      <RewardTabs current="/admin/rewards" />

      <FilterPanel>
        <form
          method="get"
          className="grid gap-3 sm:grid-cols-2 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_auto] lg:items-end"
        >
          <Field label="オブザーバー (受取人または出店者)">
            <select name="agent" defaultValue={agentId ?? ""} className={FIELD_CLASS}>
              <option value="">すべて</option>
              {agents.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.public_id} {a.display_name}
                </option>
              ))}
            </select>
          </Field>
          <Field label="注文番号">
            <input
              type="text"
              name="order"
              defaultValue={orderTerm}
              className={FIELD_CLASS}
              placeholder="例: TM-20261123-000012"
            />
          </Field>
          <div className="flex items-center gap-3">
            <button type="submit" className={`${BUTTON_CLASS} flex-1 lg:flex-none`}>
              <Search size={16} />
              絞り込む
            </button>
            {agentId || orderTerm ? (
              <Link
                href="/admin/rewards"
                className="whitespace-nowrap text-[13px] font-medium text-text-secondary hover:text-text-primary"
              >
                クリア
              </Link>
            ) : null}
          </div>
        </form>
      </FilterPanel>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <Stat label="出店者 (合計)" value={formatAmount(sumBy("seller"))} />
        <Stat label="紹介者 (合計)" value={formatAmount(sumBy("referrer"))} />
        <Stat label="運営 (合計)" value={formatAmount(sumBy("operator"))} hint="取り消しを差し引いた額" />
      </div>

      <SectionTitle count={groups.length}>注文ごとの報酬明細</SectionTitle>

      {groups.length === 0 ? (
        <EmptyState
          title="該当する報酬明細がありません"
          description="注文が入金確認済みになり、全生産者の発送が済むと明細が作られます。"
        />
      ) : (
        <div className="space-y-5">
          {groups.map((g) => {
            const reversed = new Set(g.entries.filter((e) => e.reverses_entry_id).map((e) => e.reverses_entry_id));
            const canReverse = g.entries.some((e) => e.entry_kind === "accrual" && !reversed.has(e.id));
            const net = g.entries.reduce((s, e) => s + Number(e.amount), 0);
            const products = Array.from(
              new Set(g.entries.flatMap((e) => e.product_lines.map((l) => l.product_name))),
            );
            return (
              <section key={g.orderId} className="space-y-2">
                <div className="flex flex-wrap items-center justify-between gap-2 px-1">
                  <div className="min-w-0">
                    <p className="flex flex-wrap items-center gap-2 text-[15px] font-semibold text-text-primary">
                      <Link href={`/admin/orders/${g.orderId}`} className="hover:text-brand">
                        <Mono>{g.orderNo}</Mono>
                      </Link>
                      {!canReverse ? <Badge tone="red">取り消し済み</Badge> : null}
                    </p>
                    <p className="mt-0.5 truncate text-[12px] text-text-secondary">
                      {products.join("、")} ・ 差し引き {formatAmount(net)}
                    </p>
                  </div>
                  <ConfirmReasonDialog
                    triggerLabel="報酬を取り消す"
                    triggerClassName="whitespace-nowrap rounded-xl border border-danger px-3 py-1.5 text-[13px] font-semibold text-danger hover:bg-danger-soft disabled:cursor-not-allowed disabled:border-border-soft disabled:text-text-secondary disabled:hover:bg-transparent"
                    disabled={!canReverse}
                    disabledTitle="取り消せる明細がありません"
                    tone="danger"
                    sentence={`注文 ${g.orderNo} の報酬明細 (出店者・紹介者・運営) をすべて取り消します`}
                    note="取り消されていない明細それぞれに、同じ額のマイナスの明細を作ります。元の明細は残り、取り消しは元に戻せません。"
                    reasonLabel="取り消しの理由 (必須・監査ログに記録されます。例: 返品・商品破損)"
                    confirmLabel="取り消す"
                    endpoint="/api/admin/rewards/reverse"
                    payload={{ order_id: g.orderId }}
                  />
                </div>

                <DataTable headers={["日付", "区分", "受取人", "ランク", "割合", "基準額", "金額"]}>
                  {g.entries.map((e) => {
                    const isReversal = e.entry_kind === "reversal";
                    return (
                      <tr key={e.id} className={isReversal ? "bg-danger-soft/40" : undefined}>
                        <td className={`${TD} whitespace-nowrap`}>
                          {formatDate(e.settled_on)}
                          {isReversal ? (
                            <div className="mt-1">
                              <Badge tone="red">取り消し</Badge>
                            </div>
                          ) : null}
                        </td>
                        <td className={`${TD} whitespace-nowrap`}>{REWARD_ROLE_LABELS[e.recipient_role]}</td>
                        <td className={TD_STRONG}>
                          {e.recipient_role === "operator" ? (
                            "運営"
                          ) : (
                            <Link href={`/admin/agents/${e.recipient_agent_id}`} className="hover:text-brand">
                              {e.recipient_name}
                              <div className="text-[12px] font-normal text-text-secondary">
                                <Mono>{e.recipient_public_id}</Mono>
                              </div>
                            </Link>
                          )}
                          {e.recipient_role === "seller" && e.referrer_name ? (
                            <div className="mt-1 text-[12px] font-normal text-text-secondary">
                              紹介者: {e.referrer_name}
                            </div>
                          ) : null}
                          {isReversal && e.reason ? (
                            <div className="mt-1 text-[12px] font-normal text-danger">理由: {e.reason}</div>
                          ) : null}
                        </td>
                        <td className={`${TD} whitespace-nowrap`}>
                          {e.recipient_role === "referrer" ? (e.referrer_rank_label ?? "—") : "—"}
                        </td>
                        <td className={`${TD} whitespace-nowrap tabular-nums`}>{formatRate(e.rate)}</td>
                        <td className={`${TD} whitespace-nowrap tabular-nums`}>{formatAmount(Number(e.base_amount))}</td>
                        <td
                          className={`${TD_STRONG} whitespace-nowrap tabular-nums ${isReversal ? "!text-danger" : ""}`}
                        >
                          {formatAmount(Number(e.amount))}
                        </td>
                      </tr>
                    );
                  })}
                </DataTable>
              </section>
            );
          })}
        </div>
      )}

      <Notice>
        出店者は商品を持ち込んだオブザーバー (70%)、紹介者は出店者の招待元 (1段階のみ・ランクの割合)、運営は残りと
        1 {CURRENCY_UNIT} 未満の端数です。運営が登録した商品の注文には明細は作られません。
      </Notice>
    </>
  );
}
