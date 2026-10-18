/**
 * TREEMERCE: /onboarding と /api/agents/register の画面・API 層の確認 (HTTP スモークテスト)。
 *
 * 一般の人 (super_admin 以外) が開いても新しい登録フォームへの案内だけが表示され、
 * 代理店が作られないことを確認する。DB 層の同じ確認は acceptance_cases.sql の CASE65。
 *
 *   ・このスクリプトはアカウントを作らない (signUp しない)。事前に用意した
 *     「代理店でも管理者でもない」テスト用アカウントでログインするだけ。
 *   ・本番の Supabase に対しては実行しないこと (テスト用のプロジェクトで実行する)。
 *
 * 実行例 (アプリを起動してから):
 *   npm run dev
 *   BASE_URL=http://localhost:3000 \
 *   SUPABASE_URL=... SUPABASE_ANON_KEY=... \
 *   TEST_EMAIL=... TEST_PASSWORD=... \
 *   node supabase/tests/http/onboarding-smoke.mjs
 */
import { createServerClient } from "@supabase/ssr";

const env = (name) => {
  const value = process.env[name];
  if (!value) {
    console.error(`環境変数 ${name} が必要です。`);
    process.exit(2);
  }
  return value;
};

const BASE_URL = env("BASE_URL").replace(/\/$/, "");
const SUPABASE_URL = env("SUPABASE_URL");
const SUPABASE_ANON_KEY = env("SUPABASE_ANON_KEY");
const TEST_EMAIL = env("TEST_EMAIL");
const TEST_PASSWORD = env("TEST_PASSWORD");

let failed = 0;
function check(label, condition, detail = "") {
  if (condition) {
    console.log(`  ✓ ${label}`);
  } else {
    failed += 1;
    console.log(`  ✗ ${label}${detail ? ` (${detail})` : ""}`);
  }
}

// アプリと同じ形式の認証 Cookie を作るため、@supabase/ssr のクライアントでログインする
const jar = new Map();
const supabase = createServerClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  cookies: {
    getAll: () => [...jar.entries()].map(([name, value]) => ({ name, value })),
    setAll: (cookies) => {
      for (const { name, value } of cookies) {
        if (value) jar.set(name, value);
        else jar.delete(name);
      }
    },
  },
});
const cookieHeader = () => [...jar.entries()].map(([n, v]) => `${n}=${encodeURIComponent(v)}`).join("; ");

async function agentRowCount(userId) {
  const { data, error } = await supabase.from("agents").select("id").eq("auth_user_id", userId);
  if (error) throw new Error(`agents を確認できません: ${error.message}`);
  return data.length;
}

async function main() {
  console.log("• 未ログインで POST /api/agents/register");
  {
    const res = await fetch(`${BASE_URL}/api/agents/register`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ display_name: "smoke", email: TEST_EMAIL }),
    });
    const body = await res.json().catch(() => null);
    check("403 で拒否される", res.status === 403, `status=${res.status}`);
    check("案内のコードが返る", body?.error?.code === "TREEMERCE_AGENT_APPLICATION_REQUIRED", JSON.stringify(body));
  }

  console.log("• テスト用アカウントでログイン");
  const { data: signIn, error: signInError } = await supabase.auth.signInWithPassword({
    email: TEST_EMAIL,
    password: TEST_PASSWORD,
  });
  if (signInError || !signIn.user) {
    console.error(`  ログインできません: ${signInError?.message ?? "unknown"}`);
    process.exit(2);
  }
  const userId = signIn.user.id;

  const before = await agentRowCount(userId);
  if (before !== 0) {
    console.error("  このアカウントは既に代理店です。代理店でないテスト用アカウントを使ってください。");
    process.exit(2);
  }
  const { data: adminRow } = await supabase.from("admin_roles").select("role").eq("auth_user_id", userId).maybeSingle();
  if (adminRow) {
    console.error("  このアカウントには管理者ロールがあります。一般のテスト用アカウントを使ってください。");
    process.exit(2);
  }

  console.log("• ログイン中の一般ユーザーで POST /api/agents/register (旧来の本文 / 新しい本文)");
  for (const payload of [
    { display_name: "smoke", email: TEST_EMAIL, phone: null, invitation_code: null },
    {
      auth_user_id: userId,
      display_name: "smoke",
      email: TEST_EMAIL,
      inviter_mode: "none",
      inviter_agent_id: null,
      reason: "smoke",
    },
  ]) {
    const res = await fetch(`${BASE_URL}/api/agents/register`, {
      method: "POST",
      headers: { "content-type": "application/json", cookie: cookieHeader() },
      body: JSON.stringify(payload),
    });
    const body = await res.json().catch(() => null);
    check("403 で拒否される", res.status === 403, `status=${res.status}`);
    check("案内のコードが返る", body?.error?.code === "TREEMERCE_AGENT_APPLICATION_REQUIRED", JSON.stringify(body));
  }

  console.log("• ログイン中の一般ユーザーで GET /onboarding");
  {
    const res = await fetch(`${BASE_URL}/onboarding`, { headers: { cookie: cookieHeader() }, redirect: "manual" });
    const html = await res.text();
    check("200 で表示される", res.status === 200, `status=${res.status}`);
    check("登録フォームへの案内が表示される", html.includes("紹介リンクの登録フォームからお申し込み"));
    check("フォームが無い (入力欄・送信ボタンなし)", !/<form[\s>]/i.test(html) && !/<input[\s>]/i.test(html));
    check("旧来の代理店登録ボタンが無い", !html.includes("代理店として登録する"));
  }

  console.log("• 代理店が作られていないこと");
  check("agents に本人の行が無い", (await agentRowCount(userId)) === 0);

  await supabase.auth.signOut();

  console.log(failed === 0 ? "\n✓ スモークテスト完了" : `\n✗ ${failed} 件失敗`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
