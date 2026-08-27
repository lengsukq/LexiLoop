export async function register(): Promise<void> {
  if (process.env.NEXT_RUNTIME === "edge") return;
  const isVercel = process.env.VERCEL === "1";
  const isProd = process.env.NODE_ENV === "production";
  const enabled = process.env.BACKGROUND_DOCKER_TICK_ENABLED !== "false";

  if (isVercel || !isProd || !enabled) return;

  const { startDockerTick } = await import("@/modules/background/docker-tick");
  startDockerTick();
}
