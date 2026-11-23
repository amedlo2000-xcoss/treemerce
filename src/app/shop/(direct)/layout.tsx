import { ShopFrame } from "../_components/ShopFrame";

/**
 * どのオブザーバーにも紐づかない運営のショップ (/shop) の外枠。閲覧はログイン不要、購入は会員のみ。
 * 特定のオブザーバーの情報は表示しない。ここからの会員登録は担当なし (運営直接) になる (0037)。
 */
export default function DirectShopLayout({ children }: { children: React.ReactNode }) {
  return <ShopFrame agentPublicId={null}>{children}</ShopFrame>;
}
