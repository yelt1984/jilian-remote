// 使用 sql.js（SQLite 的 WebAssembly 版）实现，纯 JS/WASM，
// 无需本机编译、不依赖系统 libstdc++，适配 CentOS 7 等老系统。
// 对外仍暴露 init/run/get/all，与原 sqlite3 版本完全兼容。
const path = require('path');
const fs = require('fs');
const initSqlJs = require('sql.js');

const DB_PATH = process.env.DB_PATH
  ? (path.isAbsolute(process.env.DB_PATH)
      ? process.env.DB_PATH
      : path.join(__dirname, process.env.DB_PATH))
  : path.join(__dirname, 'jilian.db');

let SQL = null;
let db = null;

function persist() {
  const data = db.export();
  const tmp = DB_PATH + '.tmp';
  fs.writeFileSync(tmp, Buffer.from(data));
  fs.renameSync(tmp, DB_PATH);
}

async function init() {
  SQL = await initSqlJs({
    locateFile: (file) => path.join(__dirname, 'node_modules', 'sql.js', 'dist', file),
  });
  if (fs.existsSync(DB_PATH)) {
    const buf = fs.readFileSync(DB_PATH);
    db = new SQL.Database(new Uint8Array(buf));
  } else {
    db = new SQL.Database();
  }
  createTables();
  persist();
  console.log('数据库已连接(sql.js):', DB_PATH);
}

function createTables() {
  const sqls = [
    `CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      phone TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      nickname TEXT DEFAULT '',
      avatar TEXT DEFAULT '',
      signature TEXT DEFAULT '',
      email TEXT DEFAULT '',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )`,
    `CREATE TABLE IF NOT EXISTS devices (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      device_id TEXT NOT NULL,
      device_name TEXT DEFAULT '',
      device_alias TEXT DEFAULT '',
      platform TEXT DEFAULT '',
      is_online INTEGER DEFAULT 1,
      last_active DATETIME DEFAULT CURRENT_TIMESTAMP,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      -- 极连远程：V69 补 OS/地区/IP 三列，给前端设备列表行内显示。
      -- CREATE IF NOT EXISTS 不会给已存在的旧表加列，启动时另用 ALTER TABLE 兜底。
      os TEXT DEFAULT '',
      region TEXT DEFAULT '',
      ip TEXT DEFAULT '',
      UNIQUE(user_id, device_id),
      FOREIGN KEY(user_id) REFERENCES users(id)
    )`,
    `CREATE TABLE IF NOT EXISTS sms_codes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      phone TEXT NOT NULL,
      code TEXT NOT NULL,
      used INTEGER DEFAULT 0,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )`,
  ];
  for (const sql of sqls) {
    db.run(sql);
  }
  // 极连远程：V69 给旧库补 os/region/ip 三列（CREATE IF NOT EXISTS 不会改已有表结构）
  try {
    const cols = db.exec('PRAGMA table_info(devices)');
    const names = (cols && cols[0] && cols[0].values
      ? cols[0].values.map((r) => r[1])
      : []);
    if (!names.includes('os')) db.run("ALTER TABLE devices ADD COLUMN os TEXT DEFAULT ''");
    if (!names.includes('region')) db.run("ALTER TABLE devices ADD COLUMN region TEXT DEFAULT ''");
    if (!names.includes('ip')) db.run("ALTER TABLE devices ADD COLUMN ip TEXT DEFAULT ''");
  } catch (e) {
    console.error('补列失败（可忽略）:', e.message);
  }
}

// 写操作：返回 { id: lastInsertRowId, changes }
async function run(sql, params = []) {
  const stmt = db.prepare(sql);
  try {
    stmt.bind(params);
    stmt.step();
  } finally {
    stmt.free();
  }
  const changes = db.getRowsModified();
  let id;
  const r = db.exec('SELECT last_insert_rowid() AS id');
  if (r && r[0] && r[0].values && r[0].values[0]) {
    id = r[0].values[0][0];
  }
  persist();
  return { id, changes };
}

// 读单行：返回 row 对象或 undefined
async function get(sql, params = []) {
  const stmt = db.prepare(sql);
  try {
    stmt.bind(params);
    if (stmt.step()) {
      return stmt.getAsObject();
    }
    return undefined;
  } finally {
    stmt.free();
  }
}

// 读多行：返回 row 对象数组
async function all(sql, params = []) {
  const stmt = db.prepare(sql);
  const rows = [];
  try {
    stmt.bind(params);
    while (stmt.step()) {
      rows.push(stmt.getAsObject());
    }
  } finally {
    stmt.free();
  }
  return rows;
}

module.exports = { init, run, get, all };
