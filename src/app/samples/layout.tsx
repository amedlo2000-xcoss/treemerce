import type { Metadata } from "next";
import Link from "next/link";

/**
 * 企画段階のサンプルページの外枠 (/samples/...)。
 * 紹介リンク (/shop/{代理店ID}) とは別の独立した URL で、代理店 ID・紹介者・担当との紐づけは一切持たない。
 * ログイン不要。検索エンジンに載らないよう noindex / nofollow を設定する。
 */
export const metadata: Metadata = {
  robots: { index: false, follow: false, googleBot: { index: false, follow: false } },
};

export default function SamplesLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-full flex-1 flex-col bg-app-bg">
      <header className="sticky top-0 z-30 border-b border-border-soft bg-surface/95 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-3 px-4 py-3 md:px-8">
          <Link href="/samples/observer" className="text-[16px] font-bold tracking-tight text-text-primary">
            TREEMERCE <span className="font-medium text-text-secondary">SAMPLE</span>
          </Link>
          <span className="rounded-full bg-warning-soft px-2.5 py-1 text-[11px] font-semibold text-warning">
            企画段階のサンプル
          </span>
        </div>
      </header>

      <main className="mx-auto w-full max-w-6xl flex-1 space-y-6 px-4 py-6 md:px-8 md:py-8">{children}</main>

      <footer className="border-t border-border-soft bg-surface">
        <div className="mx-auto max-w-6xl px-4 py-5 text-[12px] text-text-secondary md:px-8">© TREEMERCE</div>
      </footer>
    </div>
  );
}
