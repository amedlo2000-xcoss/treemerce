import "server-only";

import { createClient } from "@supabase/supabase-js";

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`環境変数 ${name} が設定されていません (.env.local を確認してください)`);
  }
  return value;
}

/**
 * service_role で動く Supabase Auth の管理クライアント。
 *
 * 使ってよいのは代理店登録リンクの申し込み (/api/public/agent-applications/via-link) だけ。
 * 用途は「メール確認済みのアカウントの作成」と「申し込みに失敗したときのそのアカウントの削除」に限る。
 * service_role は RLS を迂回するため、テーブルの読み書き・RPC の呼び出しには絶対に使わない
 * (申請の作成は、作成したアカウントの権限で RPC を呼んで行う)。
 */
export function createSupabaseAuthAdmin() {
  const client = createClient(
    requireEnv("NEXT_PUBLIC_SUPABASE_URL"),
    requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } },
  );
  // テーブル・RPC へのアクセス手段は渡さず、Auth の管理 API だけを返す
  return client.auth.admin;
}

/**
 * Cookie を使わない (ブラウザのログイン状態に影響しない) anon key のクライアント。
 * 申し込みの直前の確認と、作成したアカウントでの RPC 呼び出しに使う。RLS はそのまま適用される。
 */
export function createSupabaseIsolatedClient() {
  return createClient(requireEnv("NEXT_PUBLIC_SUPABASE_URL"), requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}
