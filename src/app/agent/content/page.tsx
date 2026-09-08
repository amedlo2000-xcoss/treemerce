import { Compass, Gift, HelpCircle, LifeBuoy, Package } from "lucide-react";
import type { LucideIcon } from "lucide-react";

import { BigStat, MobilePageHeader, Surface } from "@/components/mobile/primitives";
import { formatYen } from "@/components/ui";
import { requireAgentPage } from "@/lib/auth/viewer";
import {
  BENEFIT_STATUS_LABELS,
  PRODUCT_CATEGORIES,
  PRODUCT_CATEGORY_LABELS,
} from "@/lib/domain/enums";
import type { BenefitRow } from "@/lib/domain/types";

function ContentCard({
  icon: Icon,
  title,
  description,
}: {
  icon: LucideIcon;
  title: string;
  description: string;
}) {
  return (
    <Surface className="flex items-start gap-4">
      <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-brand-soft text-brand">
        <Icon size={22} strokeWidth={1.8} />
      </div>
      <div>
        <h3 className="text-[16px] font-semibold text-text-primary">{title}</h3>
        <p className="mt-1 text-[14px] leading-6 text-text-secondary">{description}</p>
      </div>
    </Surface>
  );
}

/**
 * コンテンツ画面 (STEP8): 商品・報酬・活動方法・サポート・FAQ を
 * 管理一覧ではなく「見たくなる入口」のビジュアルカードとして提示する。
 * 商流・担当データとは無関係な静的な案内コンテンツ。
 */
export default async function ContentPage() {
  const { supabase } = await requireAgentPage("/agent/content");

  const { data } = await supabase
    .from("benefits")
    .select("id, benefit_type, amount, status, period_month, created_at")
    .order("created_at", { ascending: false })
    .limit(5);
  const benefits = (data ?? []) as BenefitRow[];
  const paidTotal = benefits
    .filter((b) => b.status === "paid" || b.status === "confirmed")
    .reduce((sum, b) => sum + Number(b.amount ?? 0), 0);

  return (
    <>
      <MobilePageHeader title="コンテンツ" description="商品・報酬・活動の情報はこちらから。" />

      <div className="space-y-3">
        <Surface>
          <div className="mb-3 flex items-center gap-3">
            <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-brand-soft text-brand">
              <Package size={22} strokeWidth={1.8} />
            </div>
            <h3 className="text-[16px] font-semibold text-text-primary">取り扱い商品カテゴリ</h3>
          </div>
          <div className="flex flex-wrap gap-2">
            {PRODUCT_CATEGORIES.map((category) => (
              <span
                key={category}
                className="rounded-2xl border border-border-soft bg-surface-muted px-3.5 py-2 text-[13px] font-medium text-text-primary"
              >
                {PRODUCT_CATEGORY_LABELS[category]}
              </span>
            ))}
          </div>
        </Surface>

        <Surface>
          <div className="mb-3 flex items-center gap-3">
            <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-brand-soft text-brand">
              <Gift size={22} strokeWidth={1.8} />
            </div>
            <h3 className="text-[16px] font-semibold text-text-primary">報酬について</h3>
          </div>
          <BigStat label="確定・支払済み報酬の合計" value={formatYen(paidTotal)} />
          {benefits.length > 0 ? (
            <ul className="mt-4 divide-y divide-border-soft">
              {benefits.map((b) => (
                <li key={b.id} className="flex items-center justify-between py-2 text-[13px]">
                  <span className="text-text-secondary">
                    {b.period_month ? new Date(b.period_month).toLocaleDateString("ja-JP", { year: "numeric", month: "short" }) : "—"}
                    {" · "}
                    {BENEFIT_STATUS_LABELS[b.status]}
                  </span>
                  <span className="font-medium tabular-nums text-text-primary">
                    {formatYen(Number(b.amount))}
                  </span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="mt-4 text-[13px] text-text-secondary">まだ報酬の記録はありません。</p>
          )}
        </Surface>
        <div className="grid gap-3 md:grid-cols-3">
          <ContentCard
            icon={Compass}
            title="活動方法"
            description="登録URLの発行から顧客・代理店案内までの進め方。"
          />
          <ContentCard
            icon={LifeBuoy}
            title="サポート"
            description="困ったときは運営事務局までお問い合わせください。"
          />
          <ContentCard
            icon={HelpCircle}
            title="よくある質問"
            description="登録経路や担当に関する疑問にお答えします。"
          />
        </div>
      </div>
    </>
  );
}
