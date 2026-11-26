import type { NextConfig } from "next";

// Vercel 使用自己的 serverless 构建流程，standalone 输出与之冲突；本地/自托管保留以支持 Docker 等部署。
const isVercel = process.env.VERCEL === "1";

const nextConfig: NextConfig = {
  ...(isVercel ? {} : { output: "standalone" as const, outputFileTracingRoot: __dirname }),
  serverExternalPackages: ["ws"],
  allowedDevOrigins: ["127.0.0.1"],
  turbopack: {
    root: __dirname,
  },
  experimental: {
    // Queen 本地备份 JSON 约 20MB（22M 文件）；默认 10MB 会截断 FormData，导致解析失败。
    // 自托管/Queen 环境放宽到 50MB，Vercel 上不受此影响（由平台限制）。
    ...(isVercel ? {} : { proxyClientMaxBodySize: "50mb" as unknown as number }),
  },
};

export default nextConfig;
