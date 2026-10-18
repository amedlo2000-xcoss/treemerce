/**
 * 規約の同意記録に残す IP アドレスとブラウザ情報を、サーバー側でリクエストヘッダーから取り出す。
 * 画面 (リクエスト本文) から送られた値は使わない。参考情報として保存するだけで、
 * 認可や照合の判定には使わない。
 */
export function requestMeta(request: Request): { ipAddress: string | null; userAgent: string | null } {
  const forwarded = request.headers.get("x-forwarded-for");
  // x-forwarded-for は「クライアント, プロキシ1, ...」の順。先頭がクライアント
  const ip = forwarded?.split(",")[0]?.trim() || request.headers.get("x-real-ip")?.trim() || null;
  const userAgent = request.headers.get("user-agent")?.trim() || null;

  return {
    ipAddress: ip ? ip.slice(0, 100) : null,
    userAgent: userAgent ? userAgent.slice(0, 1000) : null,
  };
}
