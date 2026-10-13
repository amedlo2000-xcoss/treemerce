import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { UUID } from "@/lib/api/submission-input";
import { SUBMISSION_IMAGE_TYPES } from "@/lib/submission-images";

/**
 * 代行の申請の画像の枠を確保する (super_admin 専用・下書き・差し戻しのみ・5 枚まで, 0021)。
 * 保存先は代理店のフォルダ ({agent_id}/{submission_id}/...) で、代理店本人も閲覧できる。
 * 返した storage_path にだけ、ブラウザから非公開バケットへのアップロードが許可される。
 */
export async function POST(request: Request, context: { params: Promise<{ submissionId: string }> }) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { submissionId } = await context.params;
  if (!UUID.test(submissionId)) return fail("TREEMERCE_SUBMISSION_NOT_FOUND", "申請が見つかりません。", 404);

  const body = await readJson<{ content_type?: unknown }>(request);
  const contentType = typeof body?.content_type === "string" ? body.content_type : "";
  if (!SUBMISSION_IMAGE_TYPES[contentType]) {
    return fail("TREEMERCE_INVALID_INPUT", "画像は JPEG・PNG・WebP のみ登録できます。", 400);
  }

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_reserve_proxy_submission_image", {
    p_submission_id: submissionId,
    p_content_type: contentType,
  });
  if (error) return failFromPostgrest(error);
  return ok(data, 201);
}
