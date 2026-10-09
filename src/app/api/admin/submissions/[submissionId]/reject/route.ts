import { reviewSubmission } from "@/lib/api/submission-review";

/** 持込み申請の却下 (super_admin 専用・理由必須)。却下後は再申請できない。 */
export async function POST(request: Request, context: { params: Promise<{ submissionId: string }> }) {
  const { submissionId } = await context.params;
  return reviewSubmission(request, submissionId, "treemerce_admin_reject_submission");
}
