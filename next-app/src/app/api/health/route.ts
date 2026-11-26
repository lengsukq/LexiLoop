import { ok } from "@/lib/api";
import { getHealthSnapshot } from "@/modules/health/service";

export const dynamic = "force-dynamic";

export async function GET() {
  const health = await getHealthSnapshot();
  return ok(health, {
    status: health.database === "error" ? 503 : 200,
    headers: { "Cache-Control": "no-store" },
  });
}
