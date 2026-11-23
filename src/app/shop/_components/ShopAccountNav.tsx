"use client";

import { LogIn, LogOut, User, UserPlus } from "lucide-react";
import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";

import { shopSignOutAction } from "@/app/actions";
import { useCart } from "@/lib/shop/cart";
import { CART_PARAM, shopLoginUrl, shopRegisterUrl, shopReturnPath } from "@/lib/shop/return-to";

const BUTTON =
  "inline-flex h-10 shrink-0 items-center gap-1 rounded-full border border-border-soft bg-surface px-2.5 text-[12px] font-semibold text-text-primary transition-colors hover:bg-surface-muted sm:px-3.5 sm:text-[13px]";

/**
 * ショップのヘッダーのログイン状態の表示 (カートのアイコンの左)。
 *   未ログイン: 「ログイン」「会員登録（無料）」。終わったら今いるページへ戻る (カートの中身も引き継ぐ)。
 *               会員登録は、運営のショップ (agentPublicId = null) なら運営直接、
 *               オブザーバーのショップならその紹介リンクの会員登録へ進む
 *   ログイン中: 「○○様」(会員名、なければメールアドレス) と「ログアウト」
 * 狭い画面ではアイコンと短い文字にする。
 */
export function ShopAccountNav({
  agentPublicId,
  memberLabel,
}: {
  agentPublicId: string | null;
  /** ログイン中の会員の表示名 (会員名、なければメールアドレス)。未ログインなら null */
  memberLabel: string | null;
}) {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const { lines } = useCart(agentPublicId);

  // 今いるページ (戻り先)。URL に残っている ?cart= は外してから、カートの中身を付け直す
  const query = new URLSearchParams(searchParams.toString());
  query.delete(CART_PARAM);
  const qs = query.toString();
  const current = qs ? `${pathname}?${qs}` : pathname;

  if (memberLabel) {
    return (
      <div className="flex min-w-0 items-center gap-1.5">
        <span className="flex min-w-0 items-center gap-1 text-[12px] font-semibold text-text-primary sm:text-[13px]">
          <User size={16} className="shrink-0 text-text-secondary" />
          <span className="max-w-[6.5rem] truncate sm:max-w-[14rem]">{memberLabel}</span>
          <span className="shrink-0">様</span>
        </span>
        <form action={shopSignOutAction}>
          <input type="hidden" name="return_to" value={current} />
          <button type="submit" className={BUTTON} aria-label="ログアウト">
            <LogOut size={16} />
            <span className="hidden sm:inline">ログアウト</span>
          </button>
        </form>
      </div>
    );
  }

  const returnTo = shopReturnPath(current, lines);
  return (
    <div className="flex items-center gap-1.5">
      <Link href={shopLoginUrl(returnTo)} className={BUTTON}>
        <LogIn size={16} />
        ログイン
      </Link>
      <Link
        href={shopRegisterUrl(agentPublicId, returnTo)}
        className={`${BUTTON} border-brand bg-brand text-brand-foreground hover:bg-brand/90`}
      >
        <UserPlus size={16} />
        <span className="sm:hidden">登録</span>
        <span className="hidden sm:inline">会員登録（無料）</span>
      </Link>
    </div>
  );
}
