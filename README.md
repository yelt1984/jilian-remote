# 极连远程账号服务

为「极连远程」客户端提供账号登录、设备列表同步、设备绑定/解绑能力。

## 接口列表

### 认证
- `POST /api/auth/send-sms` 发送验证码
- `POST /api/auth/register` 手机号+验证码+密码注册
- `POST /api/auth/login` 手机号+密码登录
- `POST /api/auth/login-by-sms` 手机号+验证码登录（未注册自动注册）
- `GET  /api/auth/profile` 获取个人信息（需 Bearer Token）
- `PUT  /api/auth/profile` 更新个人信息（需 Bearer Token）

### 设备
- `GET  /api/device/list` 设备列表（需 Bearer Token）
- `POST /api/device/bind` 绑定/更新当前设备（需 Bearer Token）
- `POST /api/device/unbind` 解绑设备（需 Bearer Token）
- `PUT  /api/device/alias` 设置别名（需 Bearer Token）
- `POST /api/device/heartbeat` 在线心跳（需 Bearer Token）

## 线上部署现状（已完成）

- 服务器：`61.160.194.116`（CentOS 7，与 RustDesk 中继同机）
- 部署目录：`/opt/jilian-account-server`
- 对外地址：`http://61.160.194.116:3000`
- 进程守护：systemd 服务 `jilian-account`（已 enable 开机自启，Restart=always）
- 日志：`/var/log/jilian-account.log`
- 数据库文件：`/opt/jilian-account-server/jilian.db`

常用运维命令：

```bash
systemctl status  jilian-account    # 查看状态
systemctl restart jilian-account    # 重启
journalctl -u jilian-account -f     # 跟踪日志
tail -f /var/log/jilian-account.log # 或直接看日志文件
```

### 存储层说明（重要）

CentOS 7 的 g++ 4.8 不支持 `-std=gnu++14`，无法从源码编译 `sqlite3`；
而官方预编译二进制又要求 `CXXABI_1.3.8`，系统 libstdc++ 太旧同样加载失败。

因此存储层改用 **sql.js**（SQLite 的 WebAssembly 版本，纯 JS/WASM）：
- 无需本机编译，不依赖系统 libstdc++
- 仍是完整 SQLite，SQL 语法与原来完全一致
- `db.js` 对外接口 `init/run/get/all` 保持不变，路由代码零改动
- 每次写操作后导出到 `jilian.db` 文件（先写 `.tmp` 再 rename，防止写坏）

### 本地重新部署

```bash
npm install
cp .env.example .env
# 编辑 .env 配置 JWT_SECRET 与短信服务
npm start
```

默认监听 0.0.0.0:3000。VPS 需要放行 TCP 3000 端口（firewalld + 云安全组，均已放行）。

## 短信服务

默认 `SMS_PROVIDER=console` 为测试模式，验证码会输出到控制台，测试时输入该验证码即可。

接入阿里云/腾讯云短信需补充对应环境变量，并修改 `utils/sms.js` 中的真实调用。
