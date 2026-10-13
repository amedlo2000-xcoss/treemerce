import type { Metadata } from "next";

import { ObserverSampleCatalog } from "./ObserverSampleCatalog";

export const metadata: Metadata = {
  title: "オブザーバー特典付き製品・サービス (サンプル) | TREEMERCE",
  description: "TREEMERCEで取り扱うオブザーバー特典付き製品・サービスの掲載イメージ (企画段階のサンプル)。",
  robots: { index: false, follow: false, googleBot: { index: false, follow: false } },
};

/**
 * オブザーバー特典付き製品・サービスのサンプル一覧 (ログイン不要・noindex)。
 * データはローカルの固定データ (src/lib/samples/observer-samples.ts) のみで、DB・RPC には接続しない。
 * 購入・決済・予約・問い合わせの機能は持たない。
 */
export default function ObserverSamplesPage() {
  return (
    <>
      <header className="space-y-3 px-1">
        <h1 className="text-[26px] font-bold leading-tight tracking-tight text-text-primary md:text-[30px]">
          オブザーバー特典付き製品・サービス
        </h1>
        <p className="max-w-3xl text-[15px] leading-7 text-text-secondary">
          食や工芸、アクセサリー、施術、アートなど。
          <br />
          TREEMERCEで取り扱うオブザーバー特典付き製品・サービスの掲載イメージをご紹介します。
        </p>
      </header>

      <div
        role="note"
        className="rounded-2xl border border-warning-soft bg-warning-soft px-4 py-3.5 text-[14px] leading-6 text-text-primary"
      >
        <p className="font-semibold">ご注意</p>
        <p className="mt-1">
          掲載内容は企画段階のサンプルです。実際の販売・提供を案内するものではありません。商品名、仕様、価格、提供者、特典内容は未確定です。
        </p>
      </div>

      <ObserverSampleCatalog />

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
