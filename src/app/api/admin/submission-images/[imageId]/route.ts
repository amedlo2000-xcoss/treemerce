import { fail, failFromPostgrest, ok, requireSuperAdminApi } from "@/lib/api/http";
import { UUID } from "@/lib/api/submission-input";
import { SUBMISSION_IMAGE_BUCKET } from "@/lib/submission-images";

/**
 * 代行の申請の画像の削除 (super_admin 専用・下書き・差し戻しのみ, 0021)。
 * 先に DB の枠を消し (RPC が代行の申請か・状態を確認する)、そのあと super_admin の権限で実体を消す
 * (Storage の権限は、代行の申請が編集可能な間だけ super_admin の削除を許可する)。
 */
export async function DELETE(_request: Request, context: { params: Promise<{ imageId: string }> }) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { imageId } = await context.params;
  if (!UUID.test(imageId)) return fail("TREEMERCE_SUBMISSION_NOT_FOUND", "画像が見つかりません。", 404);

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_remove_proxy_submission_image", {
    p_image_id: imageId,
  });
  if (error) return failFromPostgrest(error);

  const path = (data as { storage_path?: string } | null)?.storage_path;
  if (path) {
    const { error: removeError } = await guard.ctx.supabase.storage.from(SUBMISSION_IMAGE_BUCKET).remove([path]);
    if (removeError) console.error("[treemerce] proxy submission image remove failed", removeError.message);
  }
  return ok({ removed: true });
}
