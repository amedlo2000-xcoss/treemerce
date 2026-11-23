import { Info } from "lucide-react";

import {
  EmptyState,
  MobilePageHeader,
  StatTile,
  StatusPill,
  Surface,
} from "@/components/mobile/primitives";
import { formatAmount, formatDate } from "@/components/ui";
import { requireAgentPage } from "@/lib/auth/viewer";
import { MY_REWARD_ROLE_LABELS, formatRate, type MyRewards } from "@/lib/domain/rewards";

import { MyTabs } from "../MyTabs";

/**
 * MY › 報酬 (本人のみ)。treemerce_my_reward_entries (0033, STABLE) の表示。
 * 自分が受取人の明細だけで、購入者の情報や注文番号はレスポンス自体に含まれない (別の方法でも取得しない)。
 * 出店者報酬のときだけ基準額と割合を表示する (RPC も出店者の明細にだけ返す)。
 */
export default async function AgentRewardsPage() {
  const { supabase } = await requireAgentPage("/agent/my/rewards");

  const { data, error } = await supabase.rpc("treemerce_my_reward_entries");
  if (error) throw new Error("報酬を読み込めませんでした。");
  const rewards = data as MyRewards;

  return (
    <>
      <MobilePageHeader title="MY" />
      <MyTabs current="/agent/my/rewards" />

      <Surface>
        <p className="text-[13px] text-text-secondary">報酬の合計</p>
        <p className="mt-1 text-[28px] font-bold leading-tight tabular-nums text-text-primary">
          {formatAmount(Number(rewards.total_amount))}
        </p>
        <p className="mt-0.5 text-[12px] text-text-secondary">取り消しの明細を差し引いた額です</p>
        <div className="mt-4 grid grid-cols-2 gap-2">
          <StatTile label="あなたのランク" value={rewards.rank_label} />
          <StatTile label="明細" value={`${rewards.entries.length}件`} />
        </div>
      </Surface>

      {rewards.entries.length === 0 ? (
        <EmptyState
          title="まだ報酬はありません"
          description="持ち込んだ商品や、紹介したオブザーバーの商品が売れて発送が済むと、ここに表示されます。"
        />
      ) : (
        <ul className="space-y-3">
          {rewards.entries.map((e) => {
            const isReversal = e.kind === "reversal";
            return (
              <li key={e.id}>
                <Surface className={isReversal ? "!border-danger/40 !bg-danger-soft/40" : ""}>
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-1.5">
                        <StatusPill tone={e.role === "seller" ? "brand" : "success"}>
                          {MY_REWARD_ROLE_LABELS[e.role] ?? e.role}
                        </StatusPill>
                        {isReversal ? <StatusPill tone="danger">取り消し</StatusPill> : null}
                      </div>
                      <p className="mt-2 text-[15px] font-semibold leading-6 text-text-primary">
                        {e.product_names.join("、") || "—"}
                      </p>
                      <p className="mt-0.5 text-[12px] text-text-secondary">{formatDate(e.date)}</p>
                    </div>
                    <p
                      className={`shrink-0 text-[18px] font-bold tabular-nums ${
                        isReversal ? "text-danger" : "text-text-primary"
                      }`}
                    >
                      {formatAmount(Number(e.amount))}
                    </p>
                  </div>
                  {e.role === "seller" && e.base_amount != null ? (
                    <dl className="mt-3 grid grid-cols-2 gap-2">
                      <div className="rounded-2xl bg-surface-muted px-3 py-2.5">
                        <dt className="text-[12px] text-text-secondary">基準額</dt>
                        <dd className="truncate text-[15px] font-bold tabular-nums text-text-primary">
                          {formatAmount(Number(e.base_amount))}
                        </dd>
                      </div>
                      <div className="rounded-2xl bg-surface-muted px-3 py-2.5">
                        <dt className="text-[12px] text-text-secondary">割合</dt>
                        <dd className="text-[15px] font-bold tabular-nums text-text-primary">{formatRate(e.rate)}</dd>
                      </div>
                    </dl>
                  ) : null}
                </Surface>
              </li>
            );
          })}
        </ul>
      )}

      <div className="flex items-start gap-2.5 rounded-2xl bg-surface-muted px-3.5 py-3">
        <Info size={14} className="mt-0.5 shrink-0 text-text-secondary" />
        <p className="text-[12px] leading-5 text-text-secondary">
          出店者報酬はあなたが持ち込んだ商品の売上 (商品価格 × 数量・送料を除く) の 70%、紹介報酬はあなたが紹介した
          オブザーバーの商品の売上にランクの割合をかけた額です。お届けが済んだ注文が対象で、キャンセル・返品の分は
          「取り消し」として差し引かれます。購入者の情報は表示されません。
        </p>
      </div>
    </>
  );
}
