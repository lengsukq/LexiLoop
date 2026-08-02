import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  serverExternalPackages: ["ws"],
  outputFileTracingRoot: __dirname,
  allowedDevOrigins: ["127.0.0.1"],
  turbopack: {
    root: __dirname,
  },
};

export default nextConfig;
