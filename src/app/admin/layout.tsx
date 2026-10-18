import { ADMIN_NAV, AppShell } from "@/components/nav";
import { currentReturnTo } from "@/lib/auth/return-to";
import { requireAdminPage } from "@/lib/auth/viewer";

export default async function AdminLayout({ children }: LayoutProps<"/admin">) {
  // 未ログインで開いたページ (例: /admin/agent-applications) へログイン後に戻す
  const { viewer } = await requireAdminPage(await currentReturnTo("/admin"));

  return (
    <AppShell
      brand="TREEMERCE"
      subtitle="管理画面"
      nav={ADMIN_NAV}
      wide
      identity={`${viewer.email ?? "管理者"} (${viewer.adminRole ?? "admin"})`}
    >
      {children}
    </AppShell>
  );
}
