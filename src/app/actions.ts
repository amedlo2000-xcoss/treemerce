"use server";

import { redirect } from "next/navigation";

import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function signOutAction() {
  const supabase = await createSupabaseServerClient();
  await supabase.auth.signOut();
  redirect("/login");
}

/** ショップのヘッダーからのログアウト。ログアウト後は見ていたショップのページに戻る (ショップ内のパスのみ) */
export async function shopSignOutAction(formData: FormData) {
  const supabase = await createSupabaseServerClient();
  await supabase.auth.signOut();
  const value = formData.get("return_to");
  const returnTo =
    typeof value === "string" && (value === "/shop" || value.startsWith("/shop/") || value.startsWith("/shop?"))
      ? value
      : "/shop";
  redirect(returnTo);
}
