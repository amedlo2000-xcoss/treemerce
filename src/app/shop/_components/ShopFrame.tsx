import Link from "next/link";
import { Suspense } from "react";

import { shopBasePath } from "@/lib/shop/return-to";

import { CartLink } from "./CartLink";
import { CartRestore } from "./CartRestore";

/**
 * ショップの外枠 (ヘッダー・カート・フッター)。閲覧はログイン不要、購入は会員のみ。
 * agentPublicId = null は、どのオブザーバーにも紐づかない運営のショップ (/shop)。
 */
export function ShopFrame({
  agentPublicId,
  children,
}: {
  agentPublicId: string | null;
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-full flex-1 flex-col bg-app-bg">
      <header className="sticky top-0 z-30 border-b border-border-soft bg-surface/95 backdrop-blur">
        <div className="mx-auto flex max-w-5xl items-center justify-between gap-3 px-4 py-3 md:px-8">
          <Link
            href={shopBasePath(agentPublicId)}
            className="text-[16px] font-bold tracking-tight text-text-primary"
          >
            TREEMERCE <span className="font-medium text-text-secondary">SHOP</span>
          </Link>
          <CartLink agentPublicId={agentPublicId} />
        </div>
      </header>

      <Suspense fallback={null}>
        <CartRestore agentPublicId={agentPublicId} />
      </Suspense>

      <main className="mx-auto w-full max-w-5xl flex-1 space-y-5 px-4 py-5 md:px-8 md:py-8">
        {children}
      </main>

      <footer className="border-t border-border-soft bg-surface">
        <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-2 px-4 py-5 text-[12px] text-text-secondary md:px-8">
          <span>© TREEMERCE</span>
          <Link href="/legal/tokushoho" className="hover:text-text-primary hover:underline">
            特定商取引法に基づく表記
          </Link>
        </div>
      </footer>
    </div>
  );
}
