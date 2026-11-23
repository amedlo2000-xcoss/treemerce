import Link from "next/link";
import { redirect } from "next/navigation";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { isShopPath } from "@/lib/shop/return-to";

import { DIRECT_SHOP_TITLE } from "../shop/_components/ShopParts";
import { ShopMemberSignup } from "./[agentPublicId]/ShopMemberSignup";

/**
 * 運営のショップ (/shop) の「会員登録（無料）」から来たときの会員登録 (/register?next=/shop...)。
 * どのオブザーバーにも紐づかない「運営直接」の会員として登録する (紹介者・担当なし。0037)。
 * 既存の会員なら担当は変わらない (原則4)。ログイン中ならそのままショップへ戻す。
 * ショップ以外から来た場合 (next が /shop 内のパスでない) はショップへ戻す。
 */
export default async function DirectRegisterPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;
  if (!isShopPath(null, next)) redirect("/shop");

  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (user) redirect(next);

  return (
    <div className="flex flex-1 justify-center bg-app-bg px-5 py-10 sm:py-16">
      <div className="w-full max-w-md space-y-5">
        <Link href="/" className="font-mono text-[11px] tracking-widest text-text-secondary">
          TREEMERCE
        </Link>
        <p className="text-[13px] text-text-secondary">{DIRECT_SHOP_TITLE}</p>

        <div className="rounded-[24px] border border-border-soft bg-surface p-5 shadow-[var(--shadow-card)] sm:p-6">
          <ShopMemberSignup agentPublicId={null} next={next} />
        </div>
      </div>
    </div>
  );
}
