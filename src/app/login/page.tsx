import Link from "next/link";

import { LoginForm } from "./LoginForm";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;
  const target = next && next.startsWith("/") ? next : "/";

  return (
    <div className="flex flex-1 items-center justify-center bg-app-bg px-5 py-16">
      <div className="w-full max-w-sm">
        <Link href="/" className="font-mono text-[11px] tracking-widest text-text-secondary">
          TREEMERCE
        </Link>
        <h1 className="mt-2 mb-6 text-[26px] font-bold tracking-tight text-text-primary">
          アカウント
        </h1>
        <div className="rounded-[24px] border border-border-soft bg-surface p-6 shadow-[var(--shadow-card)]">
          <LoginForm next={target} />
        </div>
      </div>
    </div>
  );
}
