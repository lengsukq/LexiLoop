import { redirect } from "next/navigation";
import { isPasswordEnabled } from "@/lib/security";
import { LoginForm } from "./login-form";

export const dynamic = "force-dynamic";

function safeNextPath(value: string | undefined): string {
  return value && value.startsWith("/") && !value.startsWith("//") && !value.startsWith("/login") ? value : "/";
}

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  if (!isPasswordEnabled()) redirect("/");
  const params = await searchParams;
  return <LoginForm nextPath={safeNextPath(params.next)} />;
}
