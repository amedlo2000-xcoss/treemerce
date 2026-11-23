import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";

/**
 * ショップで購入する会員 (ログイン中のアカウント) の情報。注文画面の自動入力に使う。
 * 氏名・フリガナ・電話番号は、ショップからの会員登録のときにアカウントに保存した値
 * (本人が入力したもの)。顧客マスタ (customers) は読まない。
 * 未ログインなら null。
 */
export type ShopMember = {
  email: string;
  full_name: string;
  full_name_kana: string;
  phone: string;
};

export async function getShopMember(): Promise<ShopMember | null> {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user?.email) return null;

  const meta = (user.user_metadata ?? {}) as Record<string, unknown>;
  const text = (key: string) => (typeof meta[key] === "string" ? (meta[key] as string).trim() : "");
  return {
    email: user.email,
    full_name: text("full_name"),
    full_name_kana: text("full_name_kana"),
    phone: text("phone"),
  };
}
