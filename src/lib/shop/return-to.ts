/**
 * ショップから会員登録・ログインへ進み、終わったらショップへ戻るための URL を作る。
 *
 * 確認メールのリンクは別のブラウザ (メールアプリ内のブラウザ等) で開かれることがあり、
 * その場合は localStorage のカートが見えない。そのため戻り先の URL にカートの中身
 * (商品 ID と数量だけ。価格・個人情報は含めない) を ?cart= で載せ、戻った画面で復元する。
 */

export type CartSnapshotLine = { product_id: string; quantity: number };

export const CART_PARAM = "cart";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** 「商品ID.数量~商品ID.数量」の形にする (最大 20 種類) */
export function encodeCart(lines: CartSnapshotLine[]): string {
  return lines
    .filter((l) => UUID.test(l.product_id) && Number.isInteger(l.quantity) && l.quantity > 0)
    .slice(0, 20)
    .map((l) => `${l.product_id}.${Math.min(l.quantity, 99)}`)
    .join("~");
}

export function decodeCart(value: string | null | undefined): CartSnapshotLine[] {
  if (!value) return [];
  const lines: CartSnapshotLine[] = [];
  for (const part of value.split("~").slice(0, 20)) {
    const [id, qty] = part.split(".");
    const quantity = Number(qty);
    if (id && UUID.test(id) && Number.isInteger(quantity) && quantity > 0 && quantity <= 99) {
      lines.push({ product_id: id.toLowerCase(), quantity });
    }
  }
  return lines;
}

/** 戻り先: 見ていたページ (このショップ内のパス) にカートの中身を付ける */
export function shopReturnPath(path: string, lines: CartSnapshotLine[]): string {
  const encoded = encodeCart(lines);
  if (!encoded) return path;
  return `${path}${path.includes("?") ? "&" : "?"}${CART_PARAM}=${encoded}`;
}

/** 戻り先として使えるのは、そのオブザーバーのショップ内のパスだけ */
export function isShopPath(agentPublicId: string, value: string | null | undefined): value is string {
  if (!value) return false;
  const base = `/shop/${encodeURIComponent(agentPublicId)}`;
  return value === base || value.startsWith(`${base}/`) || value.startsWith(`${base}?`);
}

export function shopRegisterUrl(agentPublicId: string, returnTo: string): string {
  return `/register/${encodeURIComponent(agentPublicId)}?next=${encodeURIComponent(returnTo)}`;
}

export function shopLoginUrl(returnTo: string): string {
  return `/login?next=${encodeURIComponent(returnTo)}`;
}
