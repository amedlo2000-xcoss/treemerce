/**
 * TREEMERCE 受け入れテストのローカル実行ハーネス。
 *
 * PGlite (WebAssembly 版 PostgreSQL) 上に Supabase と同等の前提
 * (auth スキーマ / auth.uid() / anon・authenticated・service_role ロール /
 *  public スキーマへの既定 GRANT) を作ってから、
 *   supabase/migrations/*.sql  →  supabase/tests/acceptance_cases.sql
 * の順に実行する。
 *
 *   node supabase/tests/run-acceptance.mjs
 *
 * 依存: npm i -D @electric-sql/pglite
 */
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { PGlite } from "@electric-sql/pglite";

const here = path.dirname(fileURLToPath(import.meta.url));
const migrationsDir = path.join(here, "..", "migrations");

/** Supabase 本番環境が既に持っている前提を再現する。 */
const SUPABASE_SHIM = `
create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;

grant usage on schema public to anon, authenticated, service_role;

-- Supabase の既定: public スキーマの新規オブジェクトに全権限が付く。
-- これを再現しないと 0004 の REVOKE が「元々権限が無い」だけになり、
-- GRANT 層のテストが素通りしてしまう。
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;

create schema if not exists auth;

create table auth.users (
  instance_id        uuid,
  id                 uuid primary key,
  aud                varchar(255),
  role               varchar(255),
  email              varchar(255) unique,
  encrypted_password varchar(255),
  email_confirmed_at timestamptz,
  created_at         timestamptz default now(),
  updated_at         timestamptz default now(),
  is_sso_user        boolean not null default false,
  is_anonymous       boolean not null default false
);

create or replace function auth.uid() returns uuid
language sql stable
as $shim$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid;
$shim$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
grant select on auth.users to service_role;
`;

const notices = [];

function record(message) {
  const text = typeof message === "string" ? message : (message?.message ?? "");
  if (text) notices.push(text);
}

async function main() {
  const db = await PGlite.create();
  const onNotice = (notice) => record(notice);

  console.log("• Supabase 相当の前提を構築中…");
  await db.exec(SUPABASE_SHIM, { onNotice });

  const files = (await readdir(migrationsDir)).filter((f) => f.endsWith(".sql")).sort();

  for (const file of files) {
    console.log(`• マイグレーション適用: ${file}`);
    const sql = await readFile(path.join(migrationsDir, file), "utf8");
    await db.exec(sql, { onNotice });
  }

  console.log("• 受け入れテスト実行中…\n");
  const testSql = await readFile(path.join(here, "acceptance_cases.sql"), "utf8");

  try {
    await db.exec(testSql, { onNotice });
  } catch (error) {
    for (const line of notices) console.log("  " + line);
    console.error("\n✗ 受け入れテスト失敗:\n  " + error.message);
    await db.close();
    process.exit(1);
  }

  for (const line of notices) console.log("  " + line);

  const passed = notices.filter((n) => /CASE\d+ OK/.test(n)).length;
  console.log(`\n✓ 受け入れテスト完了 (${passed} / 19 CASE)`);

  await db.close();
  if (passed !== 19) process.exit(1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
