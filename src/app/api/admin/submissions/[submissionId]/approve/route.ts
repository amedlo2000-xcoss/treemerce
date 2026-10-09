import type { SupabaseClient } from "@supabase/supabase-js";

import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { UUID, parseYen } from "@/lib/api/submission-input";
import { PRODUCT_CATEGORIES } from "@/lib/domain/enums";
import type { AdminSubmissionDetail, ProductRow } from "@/lib/domain/types";
import { PRODUCT_IMAGE_BUCKET } from "@/lib/storage";
import { SUBMISSION_IMAGE_BUCKET, SUBMISSION_IMAGE_TYPES } from "@/lib/submission-images";

/**
 * 持込み申請の承認 (super_admin 専用。DB 側でも app.is_super_admin() を再判定)。
 *
 *   producer_mode = "existing" : producer_id の既存生産者を使う
 *   producer_mode = "new"      : 申請の生産者情報から生産者を新規作成
 *
 * 承認すると生産者 (新規の場合) と商品 (在庫 0・非公開) が作られ、持込み元が記録される。
 * image_id を指定した場合は、承認のあとにその 1 枚だけを非公開バケットから公開用バケット
 * (product-images) へコピーし、商品画像に設定する。コピーに失敗しても承認は取り消さない
 * (商品管理の画面から画像を設定し直せる)。
 */
export async function POST(request: Request, context: { params: Promise<{ submissionId: string }> }) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;
  const { supabase } = guard.ctx;

  const { submissionId } = await context.params;
  if (!UUID.test(submissionId)) return fail("TREEMERCE_SUBMISSION_NOT_FOUND", "申請が見つかりません。", 404);

  const body = await readJson<Record<string, unknown>>(request);
  if (!body) return fail("TREEMERCE_INVALID_INPUT", "入力内容が不正です。", 400);

  const mode = body.producer_mode;
  if (mode !== "new" && mode !== "existing") {
    return fail("TREEMERCE_INVALID_INPUT", "生産者を「既存から選ぶ」か「新規作成」から選んでください。", 400);
  }
  const producerId = typeof body.producer_id === "string" ? body.producer_id : "";
  if (mode === "existing" && !UUID.test(producerId)) {
    return fail("TREEMERCE_INVALID_INPUT", "既存の生産者を選んでください。", 400);
  }

  const price = parseYen(body.price, "価格");
  if ("error" in price) return fail("TREEMERCE_INVALID_INPUT", price.error, 400);

  const text = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : null);
  const category = text(body.category);
  if (category && !(PRODUCT_CATEGORIES as readonly string[]).includes(category)) {
    return fail("TREEMERCE_INVALID_INPUT", "カテゴリが不正です。", 400);
  }
  const imageId = text(body.image_id);
  if (imageId && !UUID.test(imageId)) return fail("TREEMERCE_INVALID_INPUT", "画像の指定が不正です。", 400);

  // 画像は承認前に申請のものか確認しておく
  let imagePath: string | null = null;
  let submissionNo = "";
  if (imageId) {
    const { data: detail, error: detailError } = await supabase.rpc("treemerce_admin_get_submission", {
      p_submission_id: submissionId,
    });
    if (detailError) return failFromPostgrest(detailError);
    const submission = detail as AdminSubmissionDetail;
    submissionNo = submission.submission_no;
    imagePath = submission.images.find((i) => i.id === imageId)?.storage_path ?? null;
    if (!imagePath) return fail("TREEMERCE_INVALID_INPUT", "選んだ画像はこの申請のものではありません。", 400);
  }

  const { data, error } = await supabase.rpc("treemerce_admin_approve_submission", {
    p_submission_id: submissionId,
    p_producer_id: mode === "existing" ? producerId : null,
    p_product_name: text(body.product_name),
    p_price: price.value,
    p_category: category,
    p_reason: text(body.reason),
  });
  if (error) return failFromPostgrest(error);

  const result = data as { product_id: string; submission_no: string } & Record<string, unknown>;
  if (!imagePath) return ok({ ...result, image_copied: false });

  const copyError = await copyImageToProduct(
    supabase,
    imagePath,
    result.product_id,
    submissionNo || result.submission_no,
  );
  return ok({ ...result, image_copied: !copyError, image_error: copyError });
}

/** 非公開バケットの 1 枚を公開用バケットへコピーし、商品画像に設定する。失敗時はメッセージを返す。 */
async function copyImageToProduct(
  supabase: SupabaseClient,
  sourcePath: string,
  productId: string,
  submissionNo: string,
): Promise<string | null> {
  const { data: blob, error: downloadError } = await supabase.storage
    .from(SUBMISSION_IMAGE_BUCKET)
    .download(sourcePath);
  if (downloadError || !blob) {
    return "申請画像を読み込めませんでした (アップロードが完了していない可能性があります)。";
  }
  const contentType = blob.type || "image/jpeg";
  const ext = SUBMISSION_IMAGE_TYPES[contentType] ?? sourcePath.split(".").pop() ?? "jpg";
  // 推測できないファイル名にする (非公開商品の画像 URL を当てられないように)
  const targetPath = `products/${crypto.randomUUID()}.${ext}`;

  const { error: uploadError } = await supabase.storage
    .from(PRODUCT_IMAGE_BUCKET)
    .upload(targetPath, blob, { contentType, upsert: false });
  if (uploadError) return "公開用の画像の保存に失敗しました。";

  const { data: productData } = await supabase.from("products").select("*").eq("id", productId).maybeSingle();
  const product = productData as ProductRow | null;
  if (!product) return "作成した商品を読み込めませんでした。";

  const { error: updateError } = await supabase.rpc("treemerce_admin_upsert_product", {
    p_name: product.name,
    p_price: Number(product.price),
    p_stock: product.stock,
    p_is_published: product.is_published,
    p_category: product.category,
    p_description: product.description,
    p_image_path: targetPath,
    p_sku: product.sku,
    p_sort_order: product.sort_order,
    p_product_id: product.id,
    p_reason: `持込み申請 ${submissionNo} の画像を商品画像に設定`,
    p_producer_id: product.producer_id,
    p_content_volume: null,
    p_ingredients: null,
    p_best_before_note: null,
  });
  if (updateError) return "商品画像の設定に失敗しました。";
  return null;
}
