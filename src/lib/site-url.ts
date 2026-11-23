import { headers } from "next/headers";

/**
 * サイトの URL (末尾のスラッシュなし)。サーバー側でのみ使う。
 *   1. NEXT_PUBLIC_SITE_URL (明示的な設定)
 *   2. 本番 (VERCEL_ENV=production) は Vercel の本番ドメイン (VERCEL_PROJECT_PRODUCTION_URL)
 *      → https://treemerce-fawn.vercel.app
 *   3. それ以外 (プレビュー・ローカル) は表示中のリクエストのホスト
 */
export async function getSiteOrigin(): Promise<string> {
  const explicit = process.env.NEXT_PUBLIC_SITE_URL?.trim();
  if (explicit) return explicit.replace(/\/+$/, "");

  const production = process.env.VERCEL_PROJECT_PRODUCTION_URL?.trim();
  if (process.env.VERCEL_ENV === "production" && production) {
    return `https://${production.replace(/^https?:\/\//, "").replace(/\/+$/, "")}`;
  }

  const headerList = await headers();
  const host = headerList.get("x-forwarded-host") ?? headerList.get("host") ?? "";
  const protocol = headerList.get("x-forwarded-proto") ?? (host.startsWith("localhost") ? "http" : "https");
  return host ? `${protocol}://${host}` : "";
}
