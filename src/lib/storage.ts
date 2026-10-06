/**
 * 商品画像 (Storage バケット product-images, 0012) の公開 URL。
 * 画像は公開バケットにあるため、署名なしの公開 URL をそのまま使う。
 */
export const PRODUCT_IMAGE_BUCKET = "product-images";

export function productImageUrl(path: string | null | undefined): string | null {
  if (!path) return null;
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!base) return null;
  return `${base.replace(/\/$/, "")}/storage/v1/object/public/${PRODUCT_IMAGE_BUCKET}/${path
    .split("/")
    .map(encodeURIComponent)
    .join("/")}`;
}
