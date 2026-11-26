import { NextRequest } from "next/server";
import { ok } from "@/lib/api";
import { clearAuthCookies } from "@/lib/security";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  const response = ok({ loggedOut: true });
  clearAuthCookies(response, request);
  return response;
}
