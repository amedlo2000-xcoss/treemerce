import { AGENT_NAV, AppShell } from "@/components/nav";
import { currentReturnTo } from "@/lib/auth/return-to";
import { requireAgentPage } from "@/lib/auth/viewer";

export default async function AgentLayout({ children }: LayoutProps<"/agent">) {
  // 未ログインで開いたページ (例: /agent/customers) へログイン後に戻す
  const { agent } = await requireAgentPage(await currentReturnTo("/agent"));

  return (
    <AppShell
      brand="TREEMERCE"
      subtitle="オブザーバーマイページ"
      nav={AGENT_NAV}
      identity={`${agent.display_name} (${agent.public_id})`}
    >
      {children}
    </AppShell>
  );
}
