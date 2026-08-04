import type { NextConfig } from "next";

// Vercel 使用自己的 serverless 构建流程，standalone 输出与之冲突；本地/自托管保留以支持 Docker 等部署。
const isVercel = process.env.VERCEL === "1";

const nextConfig: NextConfig = {
  ...(isVercel ? {} : { output: "standalone" as const }),
  serverExternalPackages: ["ws"],
  outputFileTracingRoot: __dirname,
  allowedDevOrigins: ["127.0.0.1"],
  turbopack: {
    root: __dirname,
  },
};

export default nextConfig;
