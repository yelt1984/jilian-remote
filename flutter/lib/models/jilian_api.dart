import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../common.dart';

const String _kJilianToken = 'jilian_token';
const String _kJilianUser = 'jilian_user';
const String _kJilianAvatarB64 = 'jilian_avatar_b64';

// 极连远程账号服务地址
const String jilianApiBaseUrl = 'http://61.160.194.116:3000/api';

class JilianUser {
  final int id;
  final String phone;
  String nickname;
  String avatar;
  String signature;
  String email;

  JilianUser({
    required this.id,
    required this.phone,
    this.nickname = '',
    this.avatar = '',
    this.signature = '',
    this.email = '',
  });

  factory JilianUser.fromJson(Map<String, dynamic> json) {
    return JilianUser(
      id: json['id'] ?? 0,
      phone: json['phone'] ?? '',
      nickname: json['nickname'] ?? '',
      avatar: json['avatar'] ?? '',
      signature: json['signature'] ?? '',
      email: json['email'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'nickname': nickname,
        'avatar': avatar,
        'signature': signature,
        'email': email,
      };
}

class JilianDevice {
  final int id;
  final String deviceId;
  final String deviceName;
  final String deviceAlias;
  final String platform;
  final int isOnline;
  final String lastActive;

  JilianDevice({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.deviceAlias,
    required this.platform,
    required this.isOnline,
    required this.lastActive,
  });

  factory JilianDevice.fromJson(Map<String, dynamic> json) {
    return JilianDevice(
      id: json['id'] ?? 0,
      deviceId: json['device_id'] ?? '',
      deviceName: json['device_name'] ?? '',
      deviceAlias: json['device_alias'] ?? '',
      platform: json['platform'] ?? '',
      isOnline: json['is_online'] ?? 0,
      lastActive: json['last_active'] ?? '',
    );
  }
}

class JilianApi {
  static final JilianApi _instance = JilianApi._internal();
  factory JilianApi() => _instance;
  JilianApi._internal();

  String? _token;
  JilianUser? _user;
  String? _localAvatarB64;
  final RxBool _isLoggedIn = false.obs;

  String? get token => _token;
  JilianUser? get currentUser => _user;
  bool get isLoggedIn => _isLoggedIn.value;
  RxBool get loginState => _isLoggedIn;

  Future<void> loadFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kJilianToken);
    final userJson = prefs.getString(_kJilianUser);
    if (userJson != null && userJson.isNotEmpty) {
      try {
        _user = JilianUser.fromJson(jsonDecode(userJson));
      } catch (_) {}
    }
    _localAvatarB64 = prefs.getString(_kJilianAvatarB64);
    _isLoggedIn.value = _token != null && _token!.isNotEmpty;
  }

  Future<void> _saveToken(String token, JilianUser user) async {
    _token = token;
    _user = user;
    _isLoggedIn.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kJilianToken, token);
    await prefs.setString(_kJilianUser, jsonEncode(user.toJson()));
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    _localAvatarB64 = null;
    _isLoggedIn.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kJilianToken);
    await prefs.remove(_kJilianUser);
    await prefs.remove(_kJilianAvatarB64);
  }

  Future<void> updateUser(JilianUser user) async {
    _user = user;
    // 触发监听登录态的 Obx 重建，使头像/昵称变更在侧边栏等位置即时生效
    _isLoggedIn.refresh();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kJilianUser, jsonEncode(user.toJson()));
  }

  Map<String, String> get _headers {
    final h = {'Content-Type': 'application/json'};
    if (_token != null && _token!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_token';
    }
    return h;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final url = Uri.parse('$jilianApiBaseUrl$path');
    final resp = await http.post(url, headers: _headers, body: jsonEncode(body));
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final url = Uri.parse('$jilianApiBaseUrl$path');
    final resp = await http.get(url, headers: _headers);
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  /// 发送验证码
  Future<Map<String, dynamic>> sendSms(String phone) async {
    return _post('/auth/send-sms', {'phone': phone});
  }

  /// 手机号+验证码+密码注册
  Future<Map<String, dynamic>> register(String phone, String code, String password, {String nickname = ''}) async {
    final res = await _post('/auth/register', {
      'phone': phone,
      'code': code,
      'password': password,
      'nickname': nickname,
    });
    await _handleLoginResponse(res);
    return res;
  }

  /// 手机号/邮箱+密码登录
  Future<Map<String, dynamic>> loginByAccount(String account, String password) async {
    final body = {'account': account, 'password': password};
    if (account.contains('@')) {
      body['email'] = account;
    } else {
      body['phone'] = account;
    }
    final res = await _post('/auth/login', body);
    await _handleLoginResponse(res);
    return res;
  }

  /// 手机号+密码登录（兼容旧调用）
  Future<Map<String, dynamic>> login(String phone, String password) async {
    return loginByAccount(phone, password);
  }

  /// 手机号+验证码登录
  Future<Map<String, dynamic>> loginBySms(String phone, String code) async {
    final res = await _post('/auth/login-by-sms', {'phone': phone, 'code': code});
    await _handleLoginResponse(res);
    return res;
  }

  Future<void> _handleLoginResponse(Map<String, dynamic> res) async {
    if (res['code'] == 0 && res['data'] != null) {
      final token = res['data']['token'] as String?;
      final userJson = res['data']['user'] as Map<String, dynamic>?;
      if (token != null && userJson != null) {
        await _saveToken(token, JilianUser.fromJson(userJson));
      }
    }
  }

  /// 获取个人信息
  Future<Map<String, dynamic>> getProfile() async {
    return _get('/auth/profile');
  }

  /// 更新个人信息
  Future<Map<String, dynamic>> updateProfile(JilianUser user) async {
    final url = Uri.parse('$jilianApiBaseUrl/auth/profile');
    final resp = await http.put(url,
        headers: _headers,
        body: jsonEncode({
          'nickname': user.nickname,
          'avatar': user.avatar,
          'signature': user.signature,
          'email': user.email,
        }));
    final res = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    if (res['code'] == 0) await updateUser(user);
    return res;
  }

  /// 绑定当前设备
  Future<Map<String, dynamic>> bindDevice(String deviceId, String deviceName, {String platform = '', String alias = ''}) async {
    return _post('/device/bind', {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'platform': platform,
      'deviceAlias': alias,
    });
  }

  /// 把最近连接中的远端设备同步到账号设备列表
  Future<Map<String, dynamic>> bindPeerDevice(String deviceId, String deviceName, {String platform = '', String alias = ''}) async {
    return bindDevice(deviceId, deviceName, platform: platform, alias: alias);
  }

  /// 解绑设备
  Future<Map<String, dynamic>> unbindDevice(String deviceId) async {
    return _post('/device/unbind', {'deviceId': deviceId});
  }

  /// 设置别名
  Future<Map<String, dynamic>> setDeviceAlias(String deviceId, String alias) async {
    final url = Uri.parse('$jilianApiBaseUrl/device/alias');
    final resp = await http.put(url,
        headers: _headers,
        body: jsonEncode({'deviceId': deviceId, 'alias': alias}));
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  /// 邮箱+密码注册
  Future<Map<String, dynamic>> registerEmail(String email, String password, {String nickname = ''}) async {
    final res = await _post('/auth/register-email', {
      'email': email,
      'password': password,
      'nickname': nickname,
    });
    await _handleLoginResponse(res);
    return res;
  }

  /// 修改密码
  /// 邮箱账号传 [oldPassword]；手机账号传 [smsCode]
  Future<Map<String, dynamic>> changePassword({String? oldPassword, String? smsCode, required String newPassword}) async {
    return _post('/auth/change-password', {
      if (oldPassword != null && oldPassword.isNotEmpty) 'oldPassword': oldPassword,
      if (smsCode != null && smsCode.isNotEmpty) 'smsCode': smsCode,
      'newPassword': newPassword,
    });
  }

  /// 上传头像（base64）。
  /// 采用「乐观更新」：先把 base64 存到本地并刷新界面，保证头像立刻变化；
  /// 无论服务器是否可达，本地显示都不会再回退成旧 URL。
  Future<Map<String, dynamic>> uploadAvatar(String base64, String ext) async {
    // 1) 先更新本地内存图 + 持久化 + 触发侧边栏/个人中心重建
    _localAvatarB64 = base64;
    await _saveLocalAvatar();
    _isLoggedIn.refresh();

    // 2) 再同步到服务器（失败也不影响本地显示）
    Map<String, dynamic> res;
    try {
      res = await _post('/auth/avatar', {'avatarBase64': base64, 'ext': ext});
    } catch (e) {
      debugPrint('avatar upload to server failed (local kept): $e');
      return {'code': -1, 'msg': '本地已保存，服务器同步失败'};
    }
    if (res['code'] == 0 && res['data'] != null && res['data']['url'] != null) {
      if (_user != null) {
        _user!.avatar = res['data']['url'] as String;
        await updateUser(_user!);
      }
    }
    return res;
  }

  /// 头像来源：本地 base64（优先）或远程 URL（其次），供 UI 层构建 ImageProvider
  String? get avatarSource {
    if (_localAvatarB64 != null && _localAvatarB64!.isNotEmpty) return _localAvatarB64;
    if (_user?.avatar != null && _user!.avatar.isNotEmpty) return _user!.avatar;
    return null;
  }

  bool get hasLocalAvatar => _localAvatarB64 != null && _localAvatarB64!.isNotEmpty;

  Future<void> _saveLocalAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    if (_localAvatarB64 != null && _localAvatarB64!.isNotEmpty) {
      await prefs.setString(_kJilianAvatarB64, _localAvatarB64!);
    } else {
      await prefs.remove(_kJilianAvatarB64);
    }
  }

  /// 获取设备列表
  Future<List<JilianDevice>> getDeviceList() async {
    final res = await _get('/device/list');
    if (res['code'] == 0 && res['data'] is List) {
      return (res['data'] as List).map((e) => JilianDevice.fromJson(e)).toList();
    }
    return [];
  }

  /// 心跳
  Future<void> heartbeat(String deviceId) async {
    try {
      await _post('/device/heartbeat', {'deviceId': deviceId});
    } catch (_) {}
  }
}

final jilianApi = JilianApi();

/// 登录后把当前 RustDesk 设备 ID 绑定到极连账号，并定时心跳保活
void bindCurrentDeviceAndHeartbeat() {
  if (!jilianApi.isLoggedIn) return;
  Future<void> bind() async {
    try {
      final deviceId = gFFI.serverModel.serverId.text;
      if (deviceId.isEmpty || deviceId == translate('Generating ...')) {
        await Future.delayed(const Duration(seconds: 2));
        return bind();
      }
      final hostname = Platform.localHostname;
      final platform = isAndroid
          ? 'android'
          : isWindows
              ? 'windows'
              : isIOS
                  ? 'ios'
                  : isMacOS
                      ? 'macos'
                      : 'linux';
      await jilianApi.bindDevice(deviceId, hostname, platform: platform);
      Timer.periodic(const Duration(minutes: 2), (_) {
        jilianApi.heartbeat(deviceId);
      });
    } catch (e) {
      debugPrint('绑定设备失败: $e');
    }
  }
  bind();
}
