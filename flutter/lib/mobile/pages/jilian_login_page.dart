import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/jilian_api.dart';

import '../../common.dart';

/// 极连远程 - 登录/注册页
class JilianLoginPage extends StatefulWidget {
  @override
  State<JilianLoginPage> createState() => _JilianLoginPageState();
}

class _JilianLoginPageState extends State<JilianLoginPage> {
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isSmsLogin = false;
  bool _isRegister = false;
  bool _obscurePassword = true;
  bool _loading = false;
  int _countdown = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录 / 注册'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Text(
              '欢迎使用极连远程',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _isRegister
                  ? '注册后即可与电脑端设备同步'
                  : '登录后即可与电脑端设备同步',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _accountController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: '请输入手机号',
                prefixIcon: const Icon(Icons.phone_android),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
            const SizedBox(height: 16),
            if (!_isSmsLogin)
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: '请输入密码',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
            if (_isSmsLogin) ...[
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '请输入验证码',
                  prefixIcon: const Icon(Icons.sms_outlined),
                  suffixIcon: TextButton(
                    onPressed: _countdown == 0 ? _sendCode : null,
                    child: Text(_countdown == 0
                        ? '获取验证码'
                        : '$_countdown\u79d2'),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  disabledBackgroundColor: MyTheme.accent.withOpacity(0.5),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(_isRegister ? '注册' : '登录'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isSmsLogin = !_isSmsLogin;
                    });
                  },
                  child: Text(_isSmsLogin ? '密码登录' : '短信登录'),
                ),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isRegister = !_isRegister;
                    });
                  },
                  child: Text(_isRegister ? '已有账号？登录' : '注册账号'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendCode() async {
    final phone = _accountController.text.trim();
    if (phone.isEmpty) {
      showToast('请输入手机号');
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await jilianApi.sendSms(phone);
      if (res['code'] == 0) {
        showToast('验证码已发送');
        setState(() => _countdown = 60);
        _startCountdown();
      } else {
        showToast(res['msg'] ?? '发送失败');
      }
    } catch (e) {
      showToast('发送失败: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        if (_countdown > 0) {
          _countdown--;
          _startCountdown();
        }
      });
    });
  }

  Future<void> _submit() async {
    final account = _accountController.text.trim();
    if (account.isEmpty) {
      showToast('请输入手机号');
      return;
    }
    setState(() => _loading = true);
    try {
      Map<String, dynamic> res;
      if (_isRegister) {
        final password = _passwordController.text;
        final code = _codeController.text;
        if (password.isEmpty || code.isEmpty) {
          showToast('请输入密码和验证码');
          setState(() => _loading = false);
          return;
        }
        res = await jilianApi.register(account, code, password);
      } else if (_isSmsLogin) {
        final code = _codeController.text;
        if (code.isEmpty) {
          showToast('请输入验证码');
          setState(() => _loading = false);
          return;
        }
        res = await jilianApi.loginBySms(account, code);
      } else {
        final password = _passwordController.text;
        if (password.isEmpty) {
          showToast('请输入密码');
          setState(() => _loading = false);
          return;
        }
        res = await jilianApi.loginByAccount(account, password);
      }
      if (res['code'] == 0) {
        showToast(_isRegister ? '注册成功' : '登录成功');
        bindCurrentDeviceAndHeartbeat();
        Navigator.pop(context, true);
      } else {
        showToast(res['msg'] ?? '操作失败');
      }
    } catch (e) {
      showToast('网络错误: $e');
    } finally {
      setState(() => _loading = false);
    }
  }
}
