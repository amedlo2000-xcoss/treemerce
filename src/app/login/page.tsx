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
    <div className="flex flex-1 items-center justify-center bg-zinc-50 px-6 py-16 dark:bg-zinc-950">
      <div className="w-full max-w-sm">
        <Link href="/" className="font-mono text-xs tracking-widest text-zinc-500">
          TREEMERCE
        </Link>
        <h1 className="mt-2 mb-6 text-xl font-semibold tracking-tight text-zinc-900 dark:text-zinc-50">
          アカウント
        </h1>
        <div className="rounded-xl border border-zinc-200 bg-white p-6 dark:border-zinc-800 dark:bg-zinc-900">
          <LoginForm next={target} />
        </div>
      </div>
    </div>
  );
}
