import { redirect } from "next/navigation";

import { LinkButton } from "@/components/ui";
import { getViewer } from "@/lib/auth/viewer";

export default async function Home() {
  const viewer = await getViewer();

  if (viewer.role === "admin") redirect("/admin");
  if (viewer.role === "agent") redirect("/agent");

  return (
    <div className="flex flex-1 items-center justify-center bg-app-bg px-6 py-20">
      <main className="w-full max-w-xl">
        <p className="font-mono text-[11px] tracking-widest text-text-secondary">TREEMERCE</p>
        <h1 className="mt-3 text-[32px] font-bold tracking-tight text-text-primary">
          代理店と商品購入者を、
          <br />
          分離して管理する。
        </h1>
        <p className="mt-4 text-[15px] leading-7 text-text-secondary">
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

        <dl className="mt-12 grid gap-4 border-t border-border-soft pt-8 text-sm sm:grid-cols-2">
          <div>
            <dt className="font-medium text-text-primary">商流マップ</dt>
            <dd className="mt-1 text-[13px] leading-6 text-text-secondary">
              自分を根とした傘下の広がりを確認できます。自分の担当顧客は実名、傘下の他代理店が担当する顧客は匿名ノードで表示されます。
            </dd>
          </div>
          <div>
            <dt className="font-medium text-text-primary">客層分析</dt>
            <dd className="mt-1 text-[13px] leading-6 text-text-secondary">
              自分と傘下を合わせた客層を、個人が特定できない形の属性集計として確認できます。
            </dd>
          </div>
        </dl>
      </main>
    </div>
  );
}
