import { reviewSubmission } from "@/lib/api/submission-review";

/** 持込み申請の差し戻し (super_admin 専用・理由必須)。代理店は修正して再申請できる。 */
export async function POST(request: Request, context: { params: Promise<{ submissionId: string }> }) {
  const { submissionId } = await context.params;
  return reviewSubmission(request, submissionId, "treemerce_admin_return_submission");
}
