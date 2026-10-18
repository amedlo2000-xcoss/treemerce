import type { EmailOtpType } from "@supabase/supabase-js";
import { NextResponse, type NextRequest } from "next/server";

import { createSupabaseServerClient } from "@/lib/supabase/server";

/** 戻り先はこのサイト内のパスだけ (外部 URL・"//" 始まりは使わない) */
function safeNext(value: string | null): string {
  return value && value.startsWith("/") && !value.startsWith("//") && !value.startsWith("/\\") ? value : "/";
}

/**
 * 確認メールのリンクの戻り先。メールアドレスを確認してセッションを作り、
 * 申し込みを始めたページ (?next=、例: /register/{公開ID}?apply=1) へ戻す。
 *   ・PKCE (既定): ?code=...
 *   ・メールテンプレートで token_hash を使う場合: ?token_hash=...&type=signup
 * 確認できなかった場合はログイン画面へ戻す (戻り先は引き継ぐ)。
 */
export async function GET(request: NextRequest) {
  const url = request.nextUrl;
  const next = safeNext(url.searchParams.get("next"));
  const code = url.searchParams.get("code");
  const tokenHash = url.searchParams.get("token_hash");
  const type = url.searchParams.get("type") as EmailOtpType | null;

  const supabase = await createSupabaseServerClient();
  let ok = false;
  if (code) {
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    ok = !error;
  } else if (tokenHash && type) {
    const { error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type });
    ok = !error;
  }

  if (ok) {
    return NextResponse.redirect(new URL(next, request.url));
  }

  const login = new URL("/login", request.url);
  login.searchParams.set("next", next);
  login.searchParams.set("error", "confirm_failed");
  return NextResponse.redirect(login);
}
