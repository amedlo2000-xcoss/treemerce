import { ShopFrame } from "../_components/ShopFrame";

/**
 * 紹介リンクのショップ (商品を紹介するページ) の外枠。閲覧はログイン不要、購入は会員のみ。
 * 一覧の上部に「○○さんのショップ」(リンクのオブザーバーの表示名) を出すが、
 * 購入者の担当が誰かは表示しない (既存の会員の担当は最初の登録のまま変わらない。原則4・6)。
 */
export default async function ShopLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ agentPublicId: string }>;
}) {
  const { agentPublicId } = await params;
  return <ShopFrame agentPublicId={agentPublicId}>{children}</ShopFrame>;
}
