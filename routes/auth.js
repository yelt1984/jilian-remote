const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const fs = require('fs');
const path = require('path');
const db = require('../db');
const { sendSms, verifySms } = require('../utils/sms');
const router = express.Router();

const UPLOAD_DIR = path.join(__dirname, '..', 'uploads', 'avatars');
if (!fs.existsSync(UPLOAD_DIR)) {
  fs.mkdirSync(UPLOAD_DIR, { recursive: true });
}

const JWT_SECRET = process.env.JWT_SECRET || 'jilian_default_secret_change_me';
const SALT_ROUNDS = 10;

// 发送验证码
router.post('/send-sms', async (req, res) => {
  try {
    const { phone } = req.body;
    if (!phone || !/^1[3-9]\d{9}$/.test(phone)) {
      return res.status(400).json({ code: 1, msg: '手机号格式错误' });
    }
    const result = await sendSms(phone);
    res.json({ code: 0, msg: '发送成功', testCode: result.testCode });
  } catch (err) {
    console.error(err);
    res.status(500).json({ code: 1, msg: '发送失败' });
  }
});

// 注册
router.post('/register', async (req, res) => {
  try {
    const { phone, code, password, nickname } = req.body;
    if (!phone || !code || !password) {
      return res.status(400).json({ code: 1, msg: '参数不完整' });
    }
    const ok = await verifySms(phone, code);
    if (!ok) {
      return res.status(400).json({ code: 1, msg: '验证码错误' });
    }
    const existing = await db.get('SELECT id FROM users WHERE phone = ?', [phone]);
    if (existing) {
      return res.status(400).json({ code: 1, msg: '手机号已注册' });
    }
    const hash = await bcrypt.hash(password, SALT_ROUNDS);
    const result = await db.run(
      'INSERT INTO users (phone, password_hash, nickname) VALUES (?, ?, ?)',
      [phone, hash, nickname || phone]
    );
    const token = jwt.sign({ userId: result.id, phone }, JWT_SECRET, { expiresIn: '30d' });
    res.json({ code: 0, msg: '注册成功', data: { token, user: { id: result.id, phone, nickname: nickname || phone } } });
  } catch (err) {
    console.error(err);
    res.status(500).json({ code: 1, msg: '注册失败' });
  }
});

// 登录（手机号/邮箱+密码）
router.post('/login', async (req, res) => {
  try {
    const { account, phone, email, password } = req.body;
    const loginAccount = account || phone || email;
    if (!loginAccount || !password) {
      return res.status(400).json({ code: 1, msg: '参数不完整' });
    }
    const isEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(loginAccount);
    const user = await db.get(
      isEmail ? 'SELECT * FROM users WHERE email = ?' : 'SELECT * FROM users WHERE phone = ?',
      [loginAccount]
    );
    if (!user) {
      return res.status(400).json({ code: 1, msg: isEmail ? '邮箱未注册' : '手机号未注册' });
    }
    const match = await bcrypt.compare(password, user.password_hash);
    if (!match) {
      return res.status(400).json({ code: 1, msg: '密码错误' });
    }
    const token = jwt.sign({ userId: user.id, phone: user.phone }, JWT_SECRET, { expiresIn: '30d' });
    res.json({
      code: 0,
      msg: '登录成功',
      data: {
        token,
        user: {
          id: user.id,
          phone: user.phone,
          nickname: user.nickname,
          avatar: user.avatar,
          signature: user.signature,
          email: user.email
        }
      }
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ code: 1, msg: '登录失败' });
  }
});

// 登录（手机号+验证码）
router.post('/login-by-sms', async (req, res) => {
  try {
    const { phone, code } = req.body;
    if (!phone || !code) {
      return res.status(400).json({ code: 1, msg: '参数不完整' });
    }
    const ok = await verifySms(phone, code);
    if (!ok) {
      return res.status(400).json({ code: 1, msg: '验证码错误' });
    }
    let user = await db.get('SELECT * FROM users WHERE phone = ?', [phone]);
    if (!user) {
      // 自动注册
      const hash = await bcrypt.hash('jilian123', SALT_ROUNDS);
      const result = await db.run(
        'INSERT INTO users (phone, password_hash, nickname) VALUES (?, ?, ?)',
        [phone, hash, phone]
      );
      user = { id: result.id, phone, nickname: phone, avatar: '', signature: '', email: '' };
    }
    const token = jwt.sign({ userId: user.id, phone: user.phone }, JWT_SECRET, { expiresIn: '30d' });
    res.json({
      code: 0,
      msg: '登录成功',
      data: {
        token,
        user: {
          id: user.id,
          phone: user.phone,
          nickname: user.nickname,
          avatar: user.avatar,
          signature: user.signature,
          email: user.email
        }
      }
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ code: 1, msg: '登录失败' });
  }
});

// 获取个人信息
router.get('/profile', require('../middleware/auth'), async (req, res) => {
  try {
    const user = await db.get('SELECT id, phone, nickname, avatar, signature, email, created_at FROM users WHERE id = ?', [req.userId]);
    if (!user) return res.status(404).json({ code: 1, msg: '用户不存在' });
    res.json({ code: 0, data: user });
  } catch (err) {
    console.error(err);
    res.status(500).json({ code: 1, msg: '获取失败' });
  }
});

// 更新个人信息
router.put('/profile', require('../middleware/auth'), async (req, res) => {
  try {
    const { nickname, avatar, signature, email } = req.body;
    await db.run(
      'UPDATE users SET nickname = ?, avatar = ?, signature = ?, email = ? WHERE id = ?',
      [nickname, avatar, signature, email, req.userId]
    );
    res.json({ code: 0, msg: '更新成功' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ code: 1, msg: '更新失败' });
  }
});

// 邮箱+密码注册（邮箱体系）
router.post('/register-email', async (req, res) => {
  try {
    const { email, password, nickname } = req.body;
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !password) {
      return res.status(400).json({ code: 1, msg: '邮箱或密码格式错误' });
    }
    const existing = await db.get('SELECT id FROM users WHERE email = ?', [email]);
    if (existing) {
      return res.status(400).json({ code: 1, msg: '邮箱已注册' });
    }
    const hash = await bcrypt.hash(password, SALT_ROUNDS);
    // phone 列 NOT NULL+UNIQUE：邮箱账号用占位值，前端个人中心优先展示邮箱
    const phonePlaceholder = 'em_' + email.replace(/[^a-zA-Z0-9]/g, '_');
    const result = await db.run(
      'INSERT INTO users (phone, password_hash, nickname, email) VALUES (?, ?, ?, ?)',
      [phonePlaceholder, hash, nickname || email.split('@')[0], email]
    );
    const token = jwt.sign({ userId: result.id, phone: phonePlaceholder }, JWT_SECRET, { expiresIn: '30d' });
    res.json({
      code: 0,
      msg: '注册成功',
      data: {
        token,
        user: { id: result.id, phone: '', nickname: nickname || email.split('@')[0], avatar: '', signature: '', email }
      }
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ code: 1, msg: '注册失败' });
  }
});

// 修改密码
router.post('/change-password', require('../middleware/auth'), async (req, res) => {
  try {
    const { oldPassword, smsCode, newPassword } = req.body;
    if (!newPassword || newPassword.length < 6) {
      return res.status(400).json({ code: 1, msg: '新密码至少6位' });
    }
    const user = await db.get('SELECT * FROM users WHERE id = ?', [req.userId]);
    if (!user) return res.status(404).json({ code: 1, msg: '用户不存在' });

    // 邮箱账号以 em_ 占位 phone，且 email 有值
    const isEmailAccount = user.email && user.email.length > 0 && user.phone && user.phone.startsWith('em_');

    if (isEmailAccount) {
      if (!oldPassword) {
        return res.status(400).json({ code: 1, msg: '请输入旧密码' });
      }
      const match = await bcrypt.compare(oldPassword, user.password_hash);
      if (!match) {
        return res.status(400).json({ code: 1, msg: '旧密码错误' });
      }
    } else {
      if (!smsCode) {
        return res.status(400).json({ code: 1, msg: '请输入短信验证码' });
      }
      const ok = await verifySms(user.phone, smsCode);
      if (!ok) {
        return res.status(400).json({ code: 1, msg: '验证码错误' });
      }
    }

    const hash = await bcrypt.hash(newPassword, SALT_ROUNDS);
    await db.run('UPDATE users SET password_hash = ? WHERE id = ?', [hash, req.userId]);
    res.json({ code: 0, msg: '密码修改成功' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ code: 1, msg: '修改失败' });
  }
});

// 上传头像（base64 -> 文件），返回可访问 URL
router.post('/avatar', require('../middleware/auth'), async (req, res) => {
  try {
    const { avatarBase64, ext } = req.body;
    if (!avatarBase64) {
      return res.status(400).json({ code: 1, msg: '缺少头像数据' });
    }
    const safeExt = (ext || 'png').replace(/[^a-zA-Z0-9]/g, '').slice(0, 5);
    const base64Data = avatarBase64.includes(',') ? avatarBase64.split(',')[1] : avatarBase64;
    const buf = Buffer.from(base64Data, 'base64');
    if (buf.length > 3 * 1024 * 1024) {
      return res.status(400).json({ code: 1, msg: '头像过大(最大3MB)' });
    }
    const fileName = `avatar_${req.userId}.${safeExt}`;
    fs.writeFileSync(path.join(UPLOAD_DIR, fileName), buf);
    const url = `${req.protocol}://${req.get('host')}/uploads/avatars/${fileName}`;
    await db.run('UPDATE users SET avatar = ? WHERE id = ?', [url, req.userId]);
    res.json({ code: 0, msg: '上传成功', data: { url } });
  } catch (err) {
    console.error(err);
    res.status(500).json({ code: 1, msg: '上传失败' });
  }
});

module.exports = router;
