require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const db = require('./db');
const authRoutes = require('./routes/auth');
const deviceRoutes = require('./routes/device');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ limit: '10mb', extended: true }));
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// 健康检查
app.get('/health', (req, res) => {
  res.json({ status: 'ok', time: new Date().toISOString() });
});

app.use('/api/auth', authRoutes);
app.use('/api/device', deviceRoutes);

// 初始化数据库
async function init() {
  await db.init();
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`极连远程账号服务已启动: http://0.0.0.0:${PORT}`);
  });
}

init().catch((err) => {
  console.error('启动失败:', err);
  process.exit(1);
});
