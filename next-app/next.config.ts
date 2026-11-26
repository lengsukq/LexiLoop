import type { NextConfig } from "next";
import path from "node:path";

// Vercel 使用自己的 serverless 构建流程，standalone 输出与之冲突；本地/自托管保留以支持 Docker 等部署。
const isVercel = process.env.VERCEL === "1";

const nextConfig: NextConfig = {
  ...(isVercel ? {} : { output: "standalone" as const, outputFileTracingRoot: __dirname }),
  serverExternalPackages: ["ws", "@electric-sql/pglite"],
  allowedDevOrigins: ["127.0.0.1"],
  turbopack: {
    root: __dirname,
  },
  experimental: {
    // Queen 本地备份 JSON 约 20MB（22M 文件）；默认 10MB 会截断 FormData，导致解析失败。
    // 自托管/Queen 环境放宽到 50MB，Vercel 上不受此影响（由平台限制）。
    ...(isVercel ? {} : { proxyClientMaxBodySize: "50mb" as unknown as number }),
  },
  webpack: (config, { isServer, webpack }) => {
    if (!isServer) {
      const browserDbClient = path.resolve(__dirname, "src/local/browser-db-client.ts");
      const serverDbClient = path.resolve(__dirname, "src/db/client.ts");
      const serverDbClientNoExt = path.resolve(__dirname, "src/db/client");
      const emptyNodeShim = path.resolve(__dirname, "src/local/empty-node-shim.ts");

      config.resolve ??= {};
      config.resolve.alias = {
        ...config.resolve.alias,
        "@/db/client": browserDbClient,
        [serverDbClient]: browserDbClient,
        [serverDbClientNoExt]: browserDbClient,
      };
      config.resolve.fallback = {
        ...config.resolve.fallback,
        fs: false,
        "fs/promises": false,
        path: false,
        module: false,
        stream: false,
        "stream/promises": false,
        zlib: false,
        util: false,
      };
      config.plugins ??= [];
      config.plugins.push(
        new webpack.NormalModuleReplacementPlugin(/^@\/db\/client$/, browserDbClient),
        new webpack.NormalModuleReplacementPlugin(/^node:module$/, emptyNodeShim),
      );
      config.module ??= {};
      config.module.rules ??= [];
      config.module.rules.push({
        test: /\.(wasm|data)$/,
        include: /node_modules[\\/]@electric-sql[\\/]pglite/,
        type: "asset/resource",
      });
    }
    return config;
  },
};

export default nextConfig;
