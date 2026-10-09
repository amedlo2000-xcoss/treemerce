import { fail, failFromPostgrest, ok, requireAgentApi } from "@/lib/api/http";
import { UUID } from "@/lib/api/submission-input";
import { SUBMISSION_IMAGE_BUCKET } from "@/lib/submission-images";

/**
 * 申請画像の削除 (本人の下書き・差し戻しのみ)。
 * 先に DB の枠を消し (RPC が所有者と状態を確認する)、そのあと本人の権限で実体を消す。
 * 実体の削除に失敗しても枠は消えているので画面には出ない (ファイルは本人フォルダに残る)。
 */
export async function DELETE(_request: Request, context: { params: Promise<{ imageId: string }> }) {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const { imageId } = await context.params;
  if (!UUID.test(imageId)) return fail("TREEMERCE_SUBMISSION_NOT_FOUND", "画像が見つかりません。", 404);

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_remove_submission_image", {
    p_image_id: imageId,
  });
  if (error) return failFromPostgrest(error);

  const path = (data as { storage_path?: string } | null)?.storage_path;
  if (path) {
    const { error: removeError } = await guard.ctx.supabase.storage.from(SUBMISSION_IMAGE_BUCKET).remove([path]);
    if (removeError) console.error("[treemerce] submission image remove failed", removeError.message);
  }
  return ok({ removed: true });
}
