import type { SupabaseClient } from "@supabase/supabase-js";

import type { SubmissionImage, SubmissionImageView } from "@/lib/domain/types";

/**
 * 持込み申請の画像 (非公開バケット product-submission-images, 0017)。
 * 閲覧は本人と super_admin のみ (Storage の権限で判定)。画面には短時間だけ有効な
 * 署名付き URL を渡す。公開 URL は存在しない。
 */
export const SUBMISSION_IMAGE_BUCKET = "product-submission-images";

/** 署名付き URL の有効期間 (秒) */
const SIGNED_URL_TTL = 10 * 60;

export const SUBMISSION_IMAGE_TYPES: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};
export const SUBMISSION_IMAGE_MAX_BYTES = 5 * 1024 * 1024;
export const SUBMISSION_IMAGE_MAX_COUNT = 5;

/**
 * ログイン中のユーザーの権限で署名付き URL を発行する (権限がなければ url = null)。
 * アップロードが完了していない枠も url = null になる。
 */
export async function withSignedUrls(
  supabase: SupabaseClient,
  images: SubmissionImage[],
): Promise<SubmissionImageView[]> {
  if (images.length === 0) return [];
  const { data } = await supabase.storage
    .from(SUBMISSION_IMAGE_BUCKET)
    .createSignedUrls(
      images.map((i) => i.storage_path),
      SIGNED_URL_TTL,
    );
  const urls = new Map((data ?? []).map((d) => [d.path, d.error ? null : d.signedUrl]));
  return images.map((i) => ({ ...i, url: urls.get(i.storage_path) ?? null }));
}
