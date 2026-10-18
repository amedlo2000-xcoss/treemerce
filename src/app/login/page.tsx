import Link from "next/link";

import { Notice } from "@/components/ui";

import { LoginForm } from "./LoginForm";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; error?: string }>;
}) {
  const { next, error } = await searchParams;
  // 戻り先はこのサイト内のパスだけ ("//" 始まりは別サイトになるため使わない)
  const target =
    next && next.startsWith("/") && !next.startsWith("//") && !next.startsWith("/\\") ? next : "/";

  return (
    <div className="flex flex-1 items-center justify-center bg-app-bg px-5 py-16">
      <div className="w-full max-w-sm">
        <Link href="/" className="font-mono text-[11px] tracking-widest text-text-secondary">
          TREEMERCE
        </Link>
        <h1 className="mt-2 mb-6 text-[26px] font-bold tracking-tight text-text-primary">
          アカウント
        </h1>
        {error === "confirm_failed" ? (
          <div className="mb-4">
            <Notice tone="warning">
              メールアドレスの確認を完了できませんでした。リンクの有効期限が切れている可能性があります。
              確認済みの場合はログインしてください。
            </Notice>
          </div>
        ) : null}
        <div className="rounded-[24px] border border-border-soft bg-surface p-6 shadow-[var(--shadow-card)]">
          <LoginForm next={target} />
        </div>
      </div>
    </div>
  );
}
