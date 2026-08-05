const Dysmsapi = require('@alicloud/dysmsapi20170525');
const OpenApi = require('@alicloud/openapi-client');

const SMS_PROVIDER = process.env.SMS_PROVIDER || 'console'; // console | aliyun | tencent

// 生成 6 位数字验证码
function generateCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

// 60 秒发送限频，避免重复扣费
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

async function sendSms(phone) {
  const db = require('../db');

  // 测试模式：仅写库 + 控制台打印，固定不真正下发
  if (SMS_PROVIDER === 'console') {
    const code = generateCode();
    await db.run('INSERT INTO sms_codes (phone, code) VALUES (?, ?)', [phone, code]);
    console.log(`[测试模式] 手机号: ${phone}, 验证码: ${code}`);
    return { success: true, testCode: code };
  }

  // 真实模式先做限频
  await checkRateLimit(phone);
  const code = generateCode();
  await db.run('INSERT INTO sms_codes (phone, code) VALUES (?, ?)', [phone, code]);

  if (SMS_PROVIDER === 'aliyun') {
    return await sendAliyunSms(phone, code);
  }
  if (SMS_PROVIDER === 'tencent') {
    return sendTencentSms(phone, code);
  }

  console.log(`[默认测试模式] 手机号: ${phone}, 验证码: ${code}`);
  return { success: true, testCode: code };
}

// 阿里云短信客户端
function createAliyunClient(accessKeyId, accessKeySecret) {
  const config = new OpenApi.Config({ accessKeyId, accessKeySecret });
  config.endpoint = 'dysmsapi.aliyuncs.com';
  return new Dysmsapi.default(config);
}

async function sendAliyunSms(phone, code) {
  // 短信签名需与阿里云实名主体一致。后台当前审核通过的签名为「海驭网络科技」。
  // 若发送返回“签名不存在/签名不合法”，请到阿里云后台确认实际可用签名并同步 ALIYUN_SMS_SIGN_NAME。
  const accessKeyId = process.env.ALIYUN_ACCESS_KEY_ID;
  const accessKeySecret = process.env.ALIYUN_ACCESS_KEY_SECRET;
  const signName = process.env.ALIYUN_SMS_SIGN_NAME;
  const templateCode = process.env.ALIYUN_SMS_TEMPLATE_CODE;
  if (!accessKeyId || !accessKeySecret || !signName || !templateCode) {
    throw new Error('阿里云短信环境变量未配置完整');
  }
  const client = createAliyunClient(accessKeyId, accessKeySecret);
  const request = new Dysmsapi.SendSmsRequest({
    phoneNumbers: phone,
    signName: signName,
    templateCode: templateCode,
    templateParam: JSON.stringify({ code: code }),
  });
  const resp = await client.sendSms(request);
  const body = (resp && resp.body) || {};
  if (body.code === 'OK') {
    console.log(`[阿里云短信] 发送成功 phone=${phone}`);
    return { success: true };
  }
  console.error(`[阿里云短信] 发送失败 code=${body.code} message=${body.message}`);
  throw new Error(`短信发送失败: ${body.code} ${body.message}`);
}

async function sendTencentSms(phone, code) {
  // TODO: 接入腾讯云短信服务，需要配置以下环境变量：
  // TENCENT_SMS_SECRET_ID, TENCENT_SMS_SECRET_KEY, TENCENT_SMS_SDK_APPID, TENCENT_SMS_SIGN_NAME, TENCENT_SMS_TEMPLATE_ID
  const secretId = process.env.TENCENT_SMS_SECRET_ID;
  const secretKey = process.env.TENCENT_SMS_SECRET_KEY;
  const sdkAppId = process.env.TENCENT_SMS_SDK_APPID;
  const signName = process.env.TENCENT_SMS_SIGN_NAME;
  const templateId = process.env.TENCENT_SMS_TEMPLATE_ID;
  if (!secretId || !secretKey || !sdkAppId || !signName || !templateId) {
    throw new Error('腾讯云短信环境变量未配置完整');
  }
  throw new Error('腾讯云短信尚未实现');
}

// 验证验证码（5 分钟内有效）
async function verifySms(phone, code) {
  if (SMS_PROVIDER === 'console') {
    // 测试模式：固定 123456 也放行
    if (code === '123456') return true;
  }
  const db = require('../db');
  const row = await db.get(
    'SELECT * FROM sms_codes WHERE phone = ? AND code = ? AND used = 0 AND created_at > datetime("now", "-5 minutes") ORDER BY id DESC LIMIT 1',
    [phone, code]
  );
  if (!row) return false;
  await db.run('UPDATE sms_codes SET used = 1 WHERE id = ?', [row.id]);
  return true;
}

module.exports = { sendSms, verifySms };
