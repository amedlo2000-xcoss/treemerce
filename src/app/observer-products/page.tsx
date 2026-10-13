import type { Metadata } from "next";

import type { ObserverCatalog } from "@/lib/domain/types";
import { createSupabaseServerClient } from "@/lib/supabase/server";

import { ObserverProductCatalog } from "./ObserverProductCatalog";

export const metadata: Metadata = {
  // 親レイアウトの title をそのまま使わず、タブ名をページタイトルと同じにする
  title: { absolute: "オブザーバー特典付き製品一覧" },
  description: "TREEMERCEで取り扱うオブザーバー特典付き製品・サービスをご紹介します。",
  robots: { index: false, follow: false, googleBot: { index: false, follow: false } },
};

/**
 * オブザーバー特典付き製品一覧 (/observer-products、ログイン不要・noindex)。
 * 商品管理でオブザーバー特典付きの印を付けた、公開中・準備中の商品を表示する (treemerce_observer_products, 0025)。
 * 代理店 ID・紹介者とは紐づけない。購入・決済・予約・問い合わせの機能は持たない。
 */
export default async function ObserverProductsPage() {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("treemerce_observer_products");
  if (error) throw new Error("製品を読み込めませんでした。");
  const catalog = (data ?? { products: [], categories: [] }) as ObserverCatalog;

  return (
    <>
      <header className="space-y-3 px-1">
        <h1 className="text-[26px] font-bold leading-tight tracking-tight text-text-primary md:text-[30px]">
          オブザーバー特典付き製品一覧
        </h1>
        <p className="max-w-3xl text-[15px] leading-7 text-text-secondary">
          食や工芸、アクセサリー、施術、アートなど。
          <br />
          TREEMERCEで取り扱うオブザーバー特典付き製品・サービスをご紹介します。
        </p>
      </header>

      <div
        role="note"
        className="rounded-2xl border border-warning-soft bg-warning-soft px-4 py-3.5 text-[14px] leading-6 text-text-primary"
      >
        <p>価格・仕様・提供開始時期は、準備が整い次第ご案内します。</p>
      </div>

      <ObserverProductCatalog products={catalog.products} categories={catalog.categories} />

      <section
        aria-labelledby="observer-benefit-heading"
        className="rounded-[20px] border border-border-soft bg-surface p-5 shadow-[var(--shadow-card)] md:p-7"
      >
        <h2 id="observer-benefit-heading" className="text-[19px] font-bold text-text-primary">
          製品・サービスとの出会いから、TOWAへ
        </h2>
        <p className="mt-3 max-w-3xl text-[15px] leading-7 text-text-primary">
          TREEMERCEで取り扱うオブザーバー特典付き製品・サービスは、購入を通じてアプリケーション「TOWA」のオブザーバーとして関わる入口となるものです。特典の具体的な内容、参加条件、提供時期は、各製品・サービスの正式な案内でお知らせします。
        </p>
        <p className="mt-4 text-[12px] leading-5 text-text-secondary">
          商品名は、神社や寺院の建物・風景などをモチーフにした仮称です。神社・寺院の公認・提携による商品ではありません。
        </p>
      </section>
    </>
  );
}
