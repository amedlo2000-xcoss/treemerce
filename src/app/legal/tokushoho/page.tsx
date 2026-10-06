import type { Metadata } from "next";
import Link from "next/link";

import { formatYen } from "@/components/ui";
import type { ShopPublicSettings } from "@/lib/domain/types";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "特定商取引法に基づく表記 | TREEMERCE" };

/**
 * 特定商取引法に基づく表記 (公開ページ)。内容は ADMIN の「ショップ設定」で編集する。
 * 振込先口座はここには表示しない (注文完了画面でのみ案内する)。
 */
export default async function TokushohoPage() {
  const supabase = await createSupabaseServerClient();
  const { data } = await supabase.rpc("treemerce_shop_public_settings");
  const s = (data ?? null) as ShopPublicSettings | null;

  const rows: [string, React.ReactNode][] = [
    ["販売事業者", s?.seller_name],
    ["運営責任者", s?.seller_representative],
    ["所在地", s?.seller_address],
    ["電話番号", s?.seller_phone],
    ["メールアドレス", s?.seller_email],
    ["営業時間", s?.business_hours],
    ["販売価格", s?.price_note ?? "各商品ページに税込価格で表示しています。"],
    [
      "商品代金以外の必要料金",
      [
        s && Number(s.shipping_fee) > 0
          ? `送料: 1回のご注文につき ${formatYen(Number(s.shipping_fee))}`
          : "送料: 無料",
        "振込手数料: お客様のご負担となります。",
        s?.additional_fees,
      ]
        .filter(Boolean)
        .join("\n"),
    ],
    [
      "お支払い方法・時期",
      [
        "銀行振込 (前払い)",
        s ? `ご注文日から ${s.payment_due_days} 日以内にお振込みください。期限を過ぎたご注文は自動的にキャンセルされます。` : null,
        s?.payment_method_note,
      ]
        .filter(Boolean)
        .join("\n"),
    ],
    ["商品の引渡時期", s?.delivery_time],
    ["返品・交換・キャンセル", s?.return_policy],
    ["その他", s?.extra_notes],
  ];

  return (
    <div className="flex flex-1 justify-center bg-app-bg px-4 py-10 md:py-14">
      <div className="w-full max-w-2xl space-y-5">
        <Link href="/" className="font-mono text-[11px] tracking-widest text-text-secondary">
          TREEMERCE
        </Link>
        <h1 className="text-[24px] font-bold tracking-tight text-text-primary">
          特定商取引法に基づく表記
        </h1>

        <section className="overflow-hidden rounded-[20px] border border-border-soft bg-surface shadow-[var(--shadow-card)]">
          <dl className="divide-y divide-border-soft">
            {rows.map(([label, value]) => (
              <div key={label} className="grid gap-1 px-5 py-4 sm:grid-cols-[11rem_minmax(0,1fr)] sm:gap-4">
                <dt className="text-[13px] font-semibold text-text-secondary">{label}</dt>
                <dd className="whitespace-pre-wrap text-[14px] leading-6 text-text-primary">
                  {value || <span className="text-text-secondary">準備中</span>}
                </dd>
              </div>
            ))}
          </dl>
        </section>
      </div>
    </div>
  );
}
