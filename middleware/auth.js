const jwt = require('jsonwebtoken');
const JWT_SECRET = process.env.JWT_SECRET || 'jilian_default_secret_change_me';

module.exports = function (req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ code: 1, msg: '未登录' });
  }
  const token = authHeader.substring(7);
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.userId = decoded.userId;
    req.phone = decoded.phone;
    next();
  } catch (err) {
    return res.status(401).json({ code: 1, msg: '登录已过期' });
  }
};
