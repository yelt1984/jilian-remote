// 懒加载 aliyun SDK：只有 SMS_PROVIDER=aliyun 才 require，
// console/tencent 模式下不强制依赖这两个包，避免缺包时服务整体崩。
function generateCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

async function checkRateLimit(phone) {
  const db = require('../db');
  const row = await db.get(
    'SELECT created_at FROM sms_codes WHERE phone = ? ORDER BY id DESC LIMIT 1',
    [phone]
  );
  if (row && row.created_at) {
    const t = new Date(row.created_at.replace(' ', 'T') + 'Z').getTime();
    if (Date.now() - t < 60000) {
      throw new Error('发送过于频繁，请 60 秒后再试');
    }
  }
}

// ---- 阿里云短信（零依赖实现，只用 node 内置 crypto + https）----
// 不再依赖 @alicloud/dysmsapi20170525 / @alicloud/openapi-client，
// 直接按阿里云 RPC 签名规范 v1.0 (HMAC-SHA1) 构造请求，避免服务器装包失败。
function aliPercentEncode(str) {
  return encodeURIComponent(String(str))
    .replace(/\+/g, '%20')
    .replace(/\*/g, '%2A')
    .replace(/%7E/g, '~');
}

function aliBuildSignedBody(params, accessKeySecret) {
  const keys = Object.keys(params).sort();
  const canonical = keys
    .map((k) => aliPercentEncode(k) + '=' + aliPercentEncode(params[k]))
    .join('&');
  const stringToSign =
    'POST&' + aliPercentEncode('/') + '&' + aliPercentEncode(canonical);
  const crypto = require('crypto');
  const signature = crypto
    .createHmac('sha1', accessKeySecret + '&')
    .update(stringToSign)
    .digest('base64');
  return 'Signature=' + aliPercentEncode(signature) + '&' + canonical;
}

function aliPost(body) {
  const https = require('https');
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: 'dysmsapi.aliyuncs.com',
        path: '/',
        method: 'POST',
        timeout: 10000,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': Buffer.byteLength(body),
        },
      },
      (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => {
          try {
            resolve(JSON.parse(data));
          } catch (e) {
            reject(new Error('阿里云返回非 JSON: ' + data.slice(0, 200)));
          }
        });
      }
    );
    req.on('timeout', () => { req.destroy(new Error('阿里云短信请求超时')); });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function sendAliyunSms(phone, code) {
  const accessKeyId = process.env.ALIYUN_ACCESS_KEY_ID;
  const accessKeySecret = process.env.ALIYUN_ACCESS_KEY_SECRET;
  const signName = process.env.ALIYUN_SMS_SIGN_NAME;
  const templateCode = process.env.ALIYUN_SMS_TEMPLATE_CODE;
  if (!accessKeyId || !accessKeySecret || !signName || !templateCode) {
    throw new Error('阿里云短信配置缺失（ALIYUN_ACCESS_KEY_ID / SECRET / SIGN_NAME / TEMPLATE_CODE）');
  }

  const crypto = require('crypto');
  const params = {
    // --- 公共参数 ---
    AccessKeyId: accessKeyId,
    Action: 'SendSms',
    Format: 'JSON',
    RegionId: 'cn-hangzhou',
    SignatureMethod: 'HMAC-SHA1',
    SignatureNonce: crypto.randomUUID(),
    SignatureVersion: '1.0',
    Timestamp: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'),
    Version: '2017-05-25',
    // --- 业务参数 ---
    PhoneNumbers: phone,
    SignName: signName,
    TemplateCode: templateCode,
    TemplateParam: JSON.stringify({ code }),
  };

  const body = aliBuildSignedBody(params, accessKeySecret);
  const result = await aliPost(body);

  if (result && result.Code === 'OK') {
    console.log(`[阿里云短信] 已下发 ${phone} BizId=${result.BizId}`);
    return { success: true, bizId: result.BizId };
  }
  throw new Error(
    '阿里云短信下发失败: ' +
      (result && (result.Code + ' / ' + result.Message))
  );
}

async function sendSms(phone) {
  const db = require('../db');
  const SMS_PROVIDER = process.env.SMS_PROVIDER || 'console';

  if (SMS_PROVIDER === 'console') {
    const code = generateCode();
    await db.run('INSERT INTO sms_codes (phone, code, used) VALUES (?, ?, 0)', [phone, code]);
    console.log(`[测试模式] 手机号: ${phone}, 验证码: ${code}`);
    return { success: true, testCode: code };
  }

  await checkRateLimit(phone);
  const code = generateCode();
  await db.run('INSERT INTO sms_codes (phone, code, used) VALUES (?, ?, 0)', [phone, code]);

  if (SMS_PROVIDER === 'aliyun') return await sendAliyunSms(phone, code);
  if (SMS_PROVIDER === 'tencent') {
    console.log(`[腾讯云-未实装回退到测试模式] 手机号: ${phone}, 验证码: ${code}`);
    return { success: true, testCode: code };
  }
  console.log(`[默认测试模式] 手机号: ${phone}, 验证码: ${code}`);
  return { success: true, testCode: code };
}

async function verifySms(phone, code) {
  const db = require('../db');
  const row = await db.get(
    'SELECT id, used FROM sms_codes WHERE phone = ? AND code = ? ORDER BY id DESC LIMIT 1',
    [phone, code]
  );
  if (!row) return false;
  if (row.used) return false;
  await db.run('UPDATE sms_codes SET used = 1 WHERE id = ?', [row.id]);
  return true;
}

module.exports = { sendSms, verifySms };
