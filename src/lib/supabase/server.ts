import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`環境変数 ${name} が設定されていません (.env.local を確認してください)`);
  }
  return value;
}

/**
 * リクエストごとに作る Supabase クライアント。
 * anon key + ユーザーセッションで動くため、全てのクエリに RLS が適用される。
 * service_role キーは使わない (RLS を迂回する経路を作らないため)。唯一の例外は代理店登録リンクの
 * 申し込みでのアカウント作成で、src/lib/supabase/admin.ts に閉じ込めている (Auth の管理 API のみ)。
 */
export async function createSupabaseServerClient() {
  const cookieStore = await cookies();

  return createServerClient(
    requireEnv("NEXT_PUBLIC_SUPABASE_URL"),
    requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY"),
    {
      cookies: {
        getAll: () => cookieStore.getAll(),
        setAll: (cookiesToSet) => {
          try {
            for (const { name, value, options } of cookiesToSet) {
              cookieStore.set(name, value, options);
            }
          } catch {
            // Server Component のレンダリング中は Cookie を書けない。
            // セッション更新は proxy.ts 側で行うため、ここは握りつぶしてよい。
          }
        },
      },
    },
  );
}
