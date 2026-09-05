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
 * service_role キーは意図的に一切使わない (RLS を迂回する経路を作らないため)。
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
