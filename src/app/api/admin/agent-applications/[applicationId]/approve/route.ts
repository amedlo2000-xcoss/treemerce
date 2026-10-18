import { reviewAgentApplication } from "@/lib/api/agent-application-review";

/** 代理店申請の承認 (super_admin 専用・理由必須)。招待元は申請時点で固定された値が使われる。 */
export async function POST(request: Request, context: { params: Promise<{ applicationId: string }> }) {
  const { applicationId } = await context.params;
  return reviewAgentApplication(request, applicationId, "treemerce_admin_approve_agent_application");
}
