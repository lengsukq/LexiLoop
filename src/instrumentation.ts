export async function register() {
  if (process.env.NEXT_RUNTIME !== "nodejs") return;
  const { startBackgroundEngine } = await import("@/modules/background/engine");
  startBackgroundEngine();
}
