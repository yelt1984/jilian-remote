// 极连远程 V72：IP → 地区 反查工具。
// 数据源：ip-api.com 免费档（45 req/min，HTTP JSON，支持中文）。
// 30 分钟内存缓存；局域网/私网/空值静默跳过；查询失败返回 null 不抛错。
// 用法：const { lookupRegion } = require('../utils/ip-region');

const REGION_TTL_MS = 30 * 60 * 1000;
const REQUEST_TIMEOUT_MS = 3500;
const cache = new Map(); // ip -> { region, ts }

function normalizeIp(ip) {
  if (!ip) return '';
  let v = String(ip).trim();
  // Express/Node IPv4-over-IPv6 前缀
  if (v.startsWith('::ffff:')) v = v.substring(7);
  return v;
}

function isPrivateIp(ip) {
  if (!ip) return true;
  if (ip === '127.0.0.1' || ip === '::1' || ip === 'localhost') return true;
  if (ip.startsWith('10.')) return true;
  if (ip.startsWith('192.168.')) return true;
  if (ip.startsWith('169.254.')) return true;
  if (ip.startsWith('172.')) {
    const second = parseInt(ip.split('.')[1], 10);
    if (second >= 16 && second <= 31) return true;
  }
  // IPv6 私网/链路本地（简单够用：出现 ":" 一律跳过第三方查询）
  if (ip.includes(':')) return true;
  return false;
}

function isValidPublicIpv4(ip) {
  return /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(ip);
}

async function fetchRegionOnce(ip) {
  const url = `http://ip-api.com/json/${encodeURIComponent(ip)}?lang=zh-CN&fields=status,country,regionName,city,query`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const resp = await fetch(url, { signal: controller.signal });
    if (!resp.ok) return null;
    const data = await resp.json();
    if (!data || data.status !== 'success') return null;
    const parts = [data.country, data.regionName, data.city].filter(Boolean);
    return {
      ip: data.query || ip,
      region: parts.join(' '),
    };
  } catch (e) {
    console.error('V72 ip-api 查地区失败:', ip, e.message);
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * 把 req.connection.remoteAddress / x-forwarded-for 解析成最可能的客户端公网 IPv4。
 * 拿不到、为私网/本地、为 IPv6 一律返回 ''，调用方据此跳过第三方查询。
 */
function extractClientIp(req) {
  const xff = req.headers['x-forwarded-for'];
  if (xff) {
    const first = String(xff).split(',')[0].trim();
    if (first) {
      const n = normalizeIp(first);
      if (isValidPublicIpv4(n) && !isPrivateIp(n)) return n;
    }
  }
  const sock = req.socket || req.connection;
  const raw = (sock && sock.remoteAddress) || '';
  const n = normalizeIp(raw);
  if (isValidPublicIpv4(n) && !isPrivateIp(n)) return n;
  return '';
}

/**
 * 查询 IP 对应的中文地区。命中缓存（30 分钟）直接返回；私网返回 null；失败返回 null。
 * 形参 ip 已经是 extractClientIp 规范化过的公网 IPv4。
 */
async function lookupRegion(ip) {
  if (!ip || !isValidPublicIpv4(ip)) return null;
  if (isPrivateIp(ip)) return null;
  const hit = cache.get(ip);
  if (hit && Date.now() - hit.ts < REGION_TTL_MS) {
    return { ip: hit.ip, region: hit.region };
  }
  const fresh = await fetchRegionOnce(ip);
  if (fresh) {
    cache.set(ip, { ...fresh, ts: Date.now() });
  }
  return fresh;
}

module.exports = {
  extractClientIp,
  lookupRegion,
  isPrivateIp,
  // 暴露给测试用
  _normalizeIp: normalizeIp,
};