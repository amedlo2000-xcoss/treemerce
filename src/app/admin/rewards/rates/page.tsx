import { DataTable, Notice, PageHeader, TD, TD_STRONG, formatDateTime } from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import { formatRate, type RewardRates } from "@/lib/domain/rewards";

import { RewardTabs } from "../RewardTabs";
import { RateForm } from "./RateForm";

/**
 * ランク別の割合 (super_admin)。treemerce_admin_list_reward_rates (0033, STABLE) の表示と、
 * treemerce_admin_set_reward_rate による紹介者の割合の変更 (% で入力・理由必須)。
 */
export default async function AdminRewardRatesPage() {
  const { supabase } = await requireSuperAdminPage("/admin/rewards/rates");

  const { data, error } = await supabase.rpc("treemerce_admin_list_reward_rates");
  if (error) throw new Error("報酬の割合を読み込めませんでした。");
  const rates = data as RewardRates;

  return (
    <>
      <PageHeader
        title="報酬"
        description="紹介者の割合はランクごとに決まります。運営の割合は、出店者以外の 30% から紹介者の割合を引いた残りです。"
      />

      <RewardTabs current="/admin/rewards/rates" />

      <Notice>
        出店者の割合は <strong>{formatRate(rates.seller_rate)} (固定)</strong> です。
        紹介者がいない・紹介者が稼働中でない場合は、{formatRate(rates.no_referrer_operator_rate)} すべてが運営になります。
      </Notice>

      <DataTable headers={["ランク", "出店者", "紹介者の割合", "運営の割合", "最終更新", "紹介者の割合を変更"]}>
        {rates.ranks.map((r) => (
          <tr key={r.rank}>
            <td className={`${TD_STRONG} whitespace-nowrap`}>{r.rank_label}</td>
            <td className={`${TD} whitespace-nowrap tabular-nums`}>{formatRate(rates.seller_rate)} (固定)</td>
            <td className={`${TD_STRONG} whitespace-nowrap tabular-nums`}>{formatRate(r.referrer_rate)}</td>
            <td className={`${TD} whitespace-nowrap tabular-nums`}>{formatRate(r.operator_rate)}</td>
            <td className={`${TD} whitespace-nowrap`}>{formatDateTime(r.updated_at)}</td>
            <td className={TD}>
              <RateForm rank={r.rank} currentRate={Number(r.referrer_rate)} />
            </td>
          </tr>
        ))}
      </DataTable>

      <Notice tone="warning">
        割合の変更は、変更後に確定する報酬から使われます。確定済みの報酬明細には確定時点の割合が記録されており、変わりません。
        変更は監査ログに記録されます。
      </Notice>
    </>
  );
}
