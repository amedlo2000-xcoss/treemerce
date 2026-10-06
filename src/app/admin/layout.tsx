import { ADMIN_NAV, AppShell } from "@/components/nav";
import { requireAdminPage } from "@/lib/auth/viewer";

export default async function AdminLayout({ children }: LayoutProps<"/admin">) {
  const { viewer } = await requireAdminPage("/admin");

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
