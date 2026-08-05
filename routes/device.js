const express = require('express');
const auth = require('../middleware/auth');
const db = require('../db');
// 极连远程 V72：心跳异步反查对端真实 IP + 地区，写回数据库
const { extractClientIp, lookupRegion } = require('../utils/ip-region');
const router = express.Router();

router.use(auth);

// 获取设备列表
router.get('/list', async (req, res) => {
  try {
    const devices = await db.all(
      // 极连远程：V69 列表加上 os/region/ip 三列，前端设备行内直接展示
      `SELECT id, device_id, device_name, device_alias, platform, is_online, last_active, created_at, os, region, ip
       FROM devices WHERE user_id = ? ORDER BY last_active DESC`,
      [req.userId]
    );
    res.json({ code: 0, data: devices });
  } catch (err) {
    console.error(err);
    res.status(500).json({ code: 1, msg: '获取失败' });
  }
});

// 绑定/更新当前设备
router.post('/bind', async (req, res) => {
  try {
    // 极连远程：V69 bind 接口接收 os/region/ip；用于前端行内显示与离线占位文案
    const { deviceId, deviceName, deviceAlias, platform, os, region, ip } = req.body;
    if (!deviceId) {
      return res.status(400).json({ code: 1, msg: 'deviceId 不能为空' });
    }
    const existing = await db.get(
      'SELECT id FROM devices WHERE user_id = ? AND device_id = ?',
      [req.userId, deviceId]
    );
    if (existing) {
      // 更新：device_alias 仅在显式传入非空值时覆盖，避免连接/心跳把用户手动设置的备注清掉
      // os/region/ip 同样只在显式非空时覆盖，避免心跳反复回写空串把刚生成的地区/IP 抹掉。
      const updates = [
        'device_name = ?',
        'platform = ?',
        'is_online = 1',
        'last_active = CURRENT_TIMESTAMP',
      ];
      const params = [deviceName || '', platform || ''];
      if (deviceAlias) {
        updates.push('device_alias = ?');
        params.push(deviceAlias);
      }
      if (os) {
        updates.push('os = ?');
        params.push(os);
      }
      if (region) {
        updates.push('region = ?');
        params.push(region);
      }
      if (ip) {
        updates.push('ip = ?');
        params.push(ip);
      }
      params.push(existing.id);
      await db.run(
        `UPDATE devices SET ${updates.join(', ')} WHERE id = ?`,
        params
      );
    } else {
      await db.run(
        `INSERT INTO devices (user_id, device_id, device_name, device_alias, platform, is_online, os, region, ip)
         VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?)`,
        [
          req.userId, deviceId, deviceName || '', deviceAlias || '', platform || '',
          os || '', region || '', ip || '',
        ]
      );
    }
    res.json({ code: 0, msg: '绑定成功' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ code: 1, msg: '绑定失败' });
  }
});

// 解绑设备
router.post('/unbind', async (req, res) => {
  try {
    const { deviceId } = req.body;
    if (!deviceId) {
      return res.status(400).json({ code: 1, msg: 'deviceId 不能为空' });
    }
    await db.run(
      'DELETE FROM devices WHERE user_id = ? AND device_id = ?',
      [req.userId, deviceId]
    );
    res.json({ code: 0, msg: '解绑成功' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ code: 1, msg: '解绑失败' });
  }
});

// 设置别名
router.put('/alias', async (req, res) => {
  try {
    const { deviceId, alias } = req.body;
    if (!deviceId) {
      return res.status(400).json({ code: 1, msg: 'deviceId 不能为空' });
    }
    await db.run(
      'UPDATE devices SET device_alias = ? WHERE user_id = ? AND device_id = ?',
      [alias || '', req.userId, deviceId]
    );
    res.json({ code: 0, msg: '设置成功' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ code: 1, msg: '设置失败' });
  }
});

// 心跳：上报在线状态 + 异步反查对端 IP + 地区写库
router.post('/heartbeat', async (req, res) => {
  try {
    const { deviceId } = req.body;
    if (!deviceId) {
      return res.status(400).json({ code: 1, msg: 'deviceId 不能为空' });
    }
    await db.run(
      'UPDATE devices SET is_online = 1, last_active = CURRENT_TIMESTAMP WHERE user_id = ? AND device_id = ?',
      [req.userId, deviceId]
    );
    res.json({ code: 0, msg: 'ok' });

    // 极连远程 V72：异步反查对端真实 IP + 地区，写回数据库。
    // 1) 不阻塞响应（先 res.json 再异步）；2) 私网/空 IP/查询失败一律静默跳过；
    // 3) 工具模块内置 30 分钟缓存，同 IP 不会重复打 ip-api.com；
    // 4) 只在拿到非空 region/ip 时才写库，避免空串覆盖已有值。
    const ip = extractClientIp(req);
    if (!ip) return;
    lookupRegion(ip).then(async (info) => {
      if (!info || !info.region) return;
      try {
        await db.run(
          'UPDATE devices SET ip = ?, region = ? WHERE user_id = ? AND device_id = ?',
          [info.ip, info.region, req.userId, deviceId]
        );
        console.log(`V72 心跳回写 ${deviceId} -> ${info.ip} ${info.region}`);
      } catch (e) {
        console.error('V72 回写地区失败:', e.message);
      }
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ code: 1, msg: '失败' });
  }
});

module.exports = router;
