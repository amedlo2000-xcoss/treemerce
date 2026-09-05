import { redirect } from "next/navigation";

import { LinkButton } from "@/components/ui";
import { getViewer } from "@/lib/auth/viewer";

export default async function Home() {
  const viewer = await getViewer();

  if (viewer.role === "admin") redirect("/admin");
  if (viewer.role === "agent") redirect("/agent");

  return (
    <div className="flex flex-1 items-center justify-center bg-zinc-50 px-6 py-20 dark:bg-zinc-950">
      <main className="w-full max-w-xl">
        <p className="font-mono text-xs tracking-widest text-zinc-500 dark:text-zinc-400">
          TREEMERCE
        </p>
        <h1 className="mt-3 text-3xl font-semibold tracking-tight text-zinc-900 dark:text-zinc-50">
          代理店と商品購入者を、
          <br />
          分離して管理する。
        </h1>
        <p className="mt-4 text-sm leading-7 text-zinc-600 dark:text-zinc-400">
          代理店の登録経路と、購入者の担当代理店は別々のデータとして扱われます。
          担当代理店は最初の登録時に確定し、以後は管理者以外が変更することはできません。
          他の代理店が担当する購入者の情報が画面や API に出ることはありません。
        </p>

        <div className="mt-8 flex flex-wrap gap-3">
          <LinkButton href="/login">ログイン</LinkButton>
          <LinkButton href="/onboarding" variant="secondary">
            代理店として登録
          </LinkButton>
        </div>

        <dl className="mt-12 grid gap-4 border-t border-zinc-200 pt-8 text-sm sm:grid-cols-2 dark:border-zinc-800">
          <div>
            <dt className="font-medium text-zinc-900 dark:text-zinc-100">商流マップ</dt>
            <dd className="mt-1 text-xs leading-6 text-zinc-600 dark:text-zinc-400">
              自分を根とした傘下の広がりを確認できます。自分の担当顧客は実名、傘下の他代理店が担当する顧客は匿名ノードで表示されます。
            </dd>
          </div>
          <div>
            <dt className="font-medium text-zinc-900 dark:text-zinc-100">客層分析</dt>
            <dd className="mt-1 text-xs leading-6 text-zinc-600 dark:text-zinc-400">
              自分と傘下を合わせた客層を、個人が特定できない形の属性集計として確認できます。
            </dd>
          </div>
        </dl>
      </main>
    </div>
  );
}
