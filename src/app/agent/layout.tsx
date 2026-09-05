import { AGENT_NAV, AppShell } from "@/components/nav";
import { requireAgentPage } from "@/lib/auth/viewer";

export default async function AgentLayout({ children }: LayoutProps<"/agent">) {
  const { agent } = await requireAgentPage("/agent");

  return (
    <AppShell
      brand="TREEMERCE"
      subtitle="代理店マイページ"
      nav={AGENT_NAV}
      identity={`${agent.display_name} (${agent.public_id})`}
    >
      {children}
    </AppShell>
  );
}
