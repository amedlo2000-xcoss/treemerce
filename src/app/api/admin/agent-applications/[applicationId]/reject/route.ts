import { reviewAgentApplication } from "@/lib/api/agent-application-review";

/** 代理店申請の却下 (super_admin 専用・理由必須)。代理店は作られず会員のまま。理由は監査ログにのみ残る。 */
export async function POST(request: Request, context: { params: Promise<{ applicationId: string }> }) {
  const { applicationId } = await context.params;
  return reviewAgentApplication(request, applicationId, "treemerce_admin_reject_agent_application");
}
