import { lookup } from "node:dns/promises";
import net from "node:net";
import { ApiError } from "@/lib/api";

const BLOCKED_HOSTNAMES = new Set([
  "localhost",
  "ip6-localhost",
  "ip6-loopback",
  "metadata.google.internal",
  "metadata",
]);

function ipv4ToInt(ip: string): number {
  const parts = ip.split(".").map((segment) => Number.parseInt(segment, 10));
  if (parts.length !== 4 || parts.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) {
    return 0;
  }
  return ((parts[0]! << 24) | (parts[1]! << 16) | (parts[2]! << 8) | parts[3]!) >>> 0;
}

function inCidr4(ipInt: number, base: string, prefixLen: number): boolean {
  const baseInt = ipv4ToInt(base);
  const mask = prefixLen === 0 ? 0 : (0xffffffff << (32 - prefixLen)) >>> 0;
  return (ipInt & mask) === (baseInt & mask);
}

const BLOCKED_IPV4_RANGES: ReadonlyArray<readonly [string, number]> = [
  ["0.0.0.0", 8],
  ["10.0.0.0", 8],
  ["100.64.0.0", 10],
  ["127.0.0.0", 8],
  ["169.254.0.0", 16],
  ["172.16.0.0", 12],
  ["192.0.0.0", 24],
  ["192.0.2.0", 24],
  ["192.168.0.0", 16],
  ["198.18.0.0", 15],
  ["198.51.100.0", 24],
  ["203.0.113.0", 24],
  ["224.0.0.0", 4],
  ["240.0.0.0", 4],
];

function isBlockedIpv4(ip: string): boolean {
  const ipInt = ipv4ToInt(ip);
  return BLOCKED_IPV4_RANGES.some(([base, prefix]) => inCidr4(ipInt, base, prefix));
}

function parseIpv6Groups(ip: string): number[] | null {
  let normalized = ip;
  const lastColon = normalized.lastIndexOf(":");
  const tail = lastColon >= 0 ? normalized.slice(lastColon + 1) : "";
  if (tail.includes(".")) {
    const v4Int = ipv4ToInt(tail);
    const hi = ((v4Int >>> 16) & 0xffff).toString(16);
    const lo = (v4Int & 0xffff).toString(16);
    normalized = `${normalized.slice(0, lastColon)}:${hi}:${lo}`;
  }

  const sides = normalized.split("::");
  if (sides.length > 2) return null;
  const left = sides[0] ? sides[0].split(":").filter(Boolean) : [];
  const right = sides.length === 2 && sides[1] ? sides[1].split(":").filter(Boolean) : [];
  const missing = 8 - (left.length + right.length);
  if ((sides.length === 1 && missing !== 0) || missing < 0) return null;

  const rawGroups = [...left, ...Array<string>(missing).fill("0"), ...right];
  if (rawGroups.length !== 8) return null;
  const parsed = rawGroups.map((hex) => Number.parseInt(hex, 16));
  if (parsed.some((n) => !Number.isInteger(n) || n < 0 || n > 0xffff)) return null;
  return parsed;
}

function isBlockedIpv6(ip: string): boolean {
  const groups = parseIpv6Groups(ip);
  if (!groups) return true;

  // Unspecified (::) and loopback (::1)
  if (groups.slice(0, 7).every((g) => g === 0) && (groups[7] === 0 || groups[7] === 1)) return true;
  // IPv4-mapped (::ffff:0:0/96) and IPv4-compatible (::/96) -> validate embedded IPv4
  if (groups.slice(0, 5).every((g) => g === 0) && (groups[5] === 0xffff || groups[5] === 0)) {
    const v4Int = ((groups[6]! << 16) | groups[7]!) >>> 0;
    return BLOCKED_IPV4_RANGES.some(([base, prefix]) => inCidr4(v4Int, base, prefix));
  }
  // NAT64 (64:ff9b::/96 & 64:ff9b:1::/48)
  if (groups[0] === 0x0064 && groups[1] === 0xff9b) {
    const v4Int = ((groups[6]! << 16) | groups[7]!) >>> 0;
    return groups[2] === 1 || BLOCKED_IPV4_RANGES.some(([base, prefix]) => inCidr4(v4Int, base, prefix));
  }
  // 6to4 (2002::/16) and Teredo (2001::/32)
  if (groups[0] === 0x2002 || (groups[0] === 0x2001 && groups[1] === 0x0000)) return true;
  // Unique local (fc00::/7)
  if ((groups[0]! & 0xfe00) === 0xfc00) return true;
  // Link-local (fe80::/10)
  if ((groups[0]! & 0xffc0) === 0xfe80) return true;
  // Multicast (ff00::/8)
  if ((groups[0]! & 0xff00) === 0xff00) return true;

  return false;
}

function isBlockedIp(ipRaw: string): boolean {
  const ip = ipRaw.trim().toLowerCase().split("%")[0] ?? "";
  const kind = net.isIP(ip);
  if (kind === 4) return isBlockedIpv4(ip);
  if (kind === 6) return isBlockedIpv6(ip);
  return true;
}

/**
 * Prevents SSRF against localhost, cloud metadata endpoints, and private networks
 * when stateless AI/model relays are invoked from unauthenticated Local Browser Mode.
 */
export async function assertPublicSafeUrl(rawUrl: string): Promise<URL> {
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new ApiError("VALIDATION_ERROR", "接口地址不是有效的 URL。", 400);
  }

  if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
    throw new ApiError("VALIDATION_ERROR", "仅支持 HTTP/HTTPS 协议的接口地址。", 400);
  }
  if (parsed.username || parsed.password) {
    throw new ApiError("VALIDATION_ERROR", "接口地址不允许包含用户名或密码。", 400);
  }

  const hostname = parsed.hostname.replace(/^\[|\]$/g, "").toLowerCase();
  if (
    !hostname
    || BLOCKED_HOSTNAMES.has(hostname)
    || hostname.endsWith(".local")
    || hostname.endsWith(".internal")
    || hostname.endsWith(".localhost")
  ) {
    throw new ApiError("SSRF_BLOCKED", "本地免密模式仅允许访问公网接口，已拦截本机或内网地址。", 400);
  }

  if (net.isIP(hostname) !== 0) {
    if (isBlockedIp(hostname)) {
      throw new ApiError("SSRF_BLOCKED", "本地免密模式仅允许访问公网 IP，已拦截内网或保留地址。", 400);
    }
    return parsed;
  }

  let resolved: Array<{ address: string }>;
  try {
    resolved = await lookup(hostname, { all: true });
  } catch {
    throw new ApiError("DNS_RESOLUTION_FAILED", "无法解析该接口域名，请检查地址是否正确。", 400);
  }

  if (!resolved.length || resolved.some((entry) => isBlockedIp(entry.address))) {
    throw new ApiError("SSRF_BLOCKED", "目标域名解析到内网或保留地址，已安全拦截。", 400);
  }

  return parsed;
}
