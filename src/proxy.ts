import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import { PATHNAME_HEADER } from "@/lib/auth/pathname-header";

/**
 * Supabase のセッション Cookie を更新する。
 * Server Component からは Cookie を書けないため、ここで確実に書き戻す。
 * 認可の判定はここでは行わない (proxy は楽観的チェック用。実際の可否は
 * RLS + API ハンドラ + ページ側のガードで決まる)。
 */
export async function proxy(request: NextRequest) {
  // レイアウトは現在のパスを受け取れないため、ログイン後の戻り先に使うパスを
  // リクエストヘッダーで渡す。クライアントが同名のヘッダーを送っても必ず上書きする。
  // Cookie の更新後に作り直すときも、その時点のリクエストヘッダー (更新後の Cookie) から複製する。
  const forward = () => {
    const headers = new Headers(request.headers);
    headers.set(PATHNAME_HEADER, `${request.nextUrl.pathname}${request.nextUrl.search}`);
    return NextResponse.next({ request: { headers } });
  };

  let response = forward();

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) return response;

  const supabase = createServerClient(url, key, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (cookiesToSet) => {
        for (const { name, value } of cookiesToSet) {
          request.cookies.set(name, value);
        }
        response = forward();
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }
      },
    },
  });

  await supabase.auth.getUser();

  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"],
};
