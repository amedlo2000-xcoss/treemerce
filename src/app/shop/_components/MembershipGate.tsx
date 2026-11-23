"use client";

import { LogIn, UserPlus } from "lucide-react";

import { PrimaryButton } from "@/components/mobile/primitives";
import type { CartSnapshotLine } from "@/lib/shop/return-to";
import { shopLoginUrl, shopRegisterUrl, shopReturnPath } from "@/lib/shop/return-to";

/**
 * 未ログインで「カートに入れる」「ご注文手続きへ」を押したときの案内。
 * 会員登録・ログインのあと、見ていたページ (returnPath) にカートの中身を付けて戻る。
 */
export function MembershipGate({
  agentPublicId,
  returnPath,
  lines,
}: {
  /** null は運営のショップ (/shop)。会員登録は担当なし (運営直接) になる */
  agentPublicId: string | null;
  /** 戻り先 (このショップ内のパス) */
  returnPath: string;
  /** 戻ったときに復元するカートの中身 */
  lines: CartSnapshotLine[];
}) {
  const returnTo = shopReturnPath(returnPath, lines);

  return (
    <div className="space-y-3 rounded-2xl border border-brand/30 bg-brand-soft px-4 py-4">
      <p className="text-[15px] font-semibold leading-6 text-text-primary">ご購入には会員登録（無料）が必要です</p>
      <p className="text-[12px] leading-5 text-text-secondary">
        登録・ログインのあと、このページに戻ります。カートの中身はそのまま引き継がれます。
      </p>
      <div className="grid gap-2 sm:grid-cols-2">
        <PrimaryButton href={shopRegisterUrl(agentPublicId, returnTo)}>
          <UserPlus size={18} />
          会員登録（無料）
        </PrimaryButton>
        <PrimaryButton href={shopLoginUrl(returnTo)} variant="secondary">
          <LogIn size={18} />
          ログイン
        </PrimaryButton>
      </div>
    </div>
  );
}
