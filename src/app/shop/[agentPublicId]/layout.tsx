import Link from "next/link";

import { CartLink } from "./CartLink";

/**
 * 公開ショップの外枠。紹介した代理店の名前はどこにも表示しない
 * (購入者に「誰の担当になるか」を示さない。原則6)。
 */
export default async function ShopLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ agentPublicId: string }>;
}) {
  const { agentPublicId } = await params;

  return (
    <div className="flex min-h-full flex-1 flex-col bg-app-bg">
      <header className="sticky top-0 z-30 border-b border-border-soft bg-surface/95 backdrop-blur">
        <div className="mx-auto flex max-w-5xl items-center justify-between gap-3 px-4 py-3 md:px-8">
          <Link
            href={`/shop/${agentPublicId}`}
            className="text-[16px] font-bold tracking-tight text-text-primary"
          >
            TREEMERCE <span className="font-medium text-text-secondary">SHOP</span>
          </Link>
          <CartLink agentPublicId={agentPublicId} />
        </div>
      </header>

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
