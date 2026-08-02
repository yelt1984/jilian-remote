import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../common.dart';
import '../../common/widgets/remote_input.dart';
import '../../consts.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../pages/remote_page.dart';
import 'package:flutter/gestures.dart';
import '../../common/shared_state.dart';

/// 屏幕墙用的小型远程视图：只渲染画面并转发输入，不创建独立窗口/标签页。
class MiniRemoteView extends StatefulWidget {
  final String id;
  final String? password;
  final VoidCallback? onDoubleTap;

  const MiniRemoteView({
    Key? key,
    required this.id,
    this.password,
    this.onDoubleTap,
  }) : super(key: key);

  @override
  State<MiniRemoteView> createState() => _MiniRemoteViewState();
}

class _MiniRemoteViewState extends State<MiniRemoteView> {
  late final FFI _ffi;
  late final RxBool _zoomCursor;
  late final RxBool _showRemoteCursor;
  late final RxBool _remoteCursorMoved;
  late final RxBool _keyboardEnabled;
  final _cursorOverImage = false.obs;
  Timer? _connectTimeoutTimer;
  bool _firstImage = false;
  Size? _lastSize;

  @override
  void initState() {
    super.initState();
    final id = widget.id.replaceAll(' ', '');
    initSharedStates(id);
    _ffi = FFI(Uuid().v4obj());
    Get.put<FFI>(_ffi, tag: _ffi.sessionId.toString());

    _zoomCursor = PeerBoolOption.find(id, kOptionZoomCursor);
    _showRemoteCursor = ShowRemoteCursorState.find(id);
    _keyboardEnabled = KeyboardEnabledState.find(id);
    _remoteCursorMoved = RemoteCursorMovedState.find(id);

    _ffi.imageModel.addCallbackOnFirstImage((String peerId) async {
      _firstImage = true;
      // 缩略画面固定用自适应缩放，保证整个远程桌面铺满小窗格
      await bind.sessionSetViewStyle(
          sessionId: _ffi.sessionId, value: kRemoteViewStyleAdaptive);
      await _ffi.canvasModel.updateViewStyle();
      _ffi.canvasModel.activateLocalCursor();
      if (mounted) setState(() {});
    });

    _ffi.start(
      id,
      password: widget.password ?? '',
      isSharedPassword: false,
      forceRelay: false,
    );

    _connectTimeoutTimer = Timer(const Duration(seconds: 20), () {
      if (!_firstImage && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _connectTimeoutTimer?.cancel();
    _ffi.canvasModel.setForcedSize(null);
    // close() 内部已经调用 bind.sessionClose，不要重复关闭
    _ffi.close(closeSession: true).catchError((e) {
      debugPrint('MiniRemoteView close error: $e');
    });
    Get.delete<FFI>(tag: _ffi.sessionId.toString(), force: true);
    super.dispose();
  }

  void _enterView(PointerEnterEvent evt) {
    _cursorOverImage.value = true;
    if (!isWindows) {
      _ffi.inputModel.enterOrLeave(true);
    }
  }

  void _leaveView(PointerExitEvent evt) {
    _cursorOverImage.value = false;
    if (!isWindows) {
      _ffi.inputModel.enterOrLeave(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _ffi.ffiModel),
        ChangeNotifierProvider.value(value: _ffi.imageModel),
        ChangeNotifierProvider.value(value: _ffi.cursorModel),
        ChangeNotifierProvider.value(value: _ffi.canvasModel),
        ChangeNotifierProvider.value(value: _ffi.recordingModel),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 让画布尺寸与容器一致；只在尺寸变化时更新，且延后到帧末，
          // 避免在 build 过程中触发 notifyListeners 导致断言崩溃。
          final size = constraints.biggest;
          if (_lastSize != size && size.width > 0 && size.height > 0) {
            _lastSize = size;
            _ffi.canvasModel.setForcedSize(size);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _ffi.canvasModel.updateViewStyle();
              }
            });
          }

          return GestureDetector(
            onDoubleTap: widget.onDoubleTap,
            child: Container(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildImage(context),
                  if (!_firstImage)
                    Container(
                      color: Colors.black54,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '连接中...',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    return Obx(
      () => _ffi.ffiModel.pi.isSet.isFalse
          ? Container(color: Colors.black)
          : ImagePaint(
              id: widget.id,
              zoomCursor: _zoomCursor,
              cursorOverImage: _cursorOverImage,
              keyboardEnabled: _keyboardEnabled,
              remoteCursorMoved: _remoteCursorMoved,
              ffi: _ffi,
              listenerBuilder: (child) => RawTouchGestureDetectorRegion(
                ffi: _ffi,
                child: RawPointerMouseRegion(
                  inputModel: _ffi.inputModel,
                  onEnter: _enterView,
                  onExit: _leaveView,
                  child: child,
                ),
              ),
            ),
    );
  }
}
