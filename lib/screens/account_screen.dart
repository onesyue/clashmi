// ignore_for_file: use_build_context_synchronously, empty_catches

import 'dart:collection';
import 'dart:io';

import 'package:clashmi/app/modules/profile_manager.dart';
import 'package:clashmi/app/modules/setting_manager.dart';
import 'package:clashmi/app/utils/log.dart';
import 'package:clashmi/app/utils/xboard_api.dart';
import 'package:clashmi/screens/dialog_utils.dart';
import 'package:clashmi/screens/inapp_webview_screen.dart';
import 'package:clashmi/screens/theme_config.dart';
import 'package:clashmi/screens/theme_define.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 悦通账号中心
/// 全屏 WebView 加载面板，支持登录/注册/购买/续费
/// 「同步订阅」FAB 从 localStorage 读取 auth_data，严格通过 XBoard API 拉取订阅
class AccountScreen extends StatefulWidget {
  static RouteSettings routSettings() {
    return const RouteSettings(name: 'AccountScreen');
  }

  /// 面板地址
  static const String kPanelUrl = 'https://my.yue.to';

  /// 是否是首次启动引导（无订阅自动跳转场景）
  final bool isOnboarding;

  const AccountScreen({super.key, this.isOnboarding = false});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  InAppWebViewController? _webViewController;
  double _progress = 0;
  bool _syncing = false;
  bool _webviewReady = false;
  PullToRefreshController? _pullToRefreshController;

  late InAppWebViewSettings _settings;
  final List<UserScript> _scripts = [];

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    if (!InAppWebViewScreen.isInited()) return;
    final userAgent = InAppWebViewScreen.isInited()
        ? null
        : null; // 使用默认 UA
    _settings = InAppWebViewSettings(
      isInspectable: false,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      javaScriptEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
    );

    _pullToRefreshController =
        ![TargetPlatform.iOS, TargetPlatform.android].contains(
              Theme.of(context).platform,
            )
        ? null
        : PullToRefreshController(
            settings: PullToRefreshSettings(
              color: ThemeDefine.kColorIndigo,
            ),
            onRefresh: () async {
              if (Platform.isAndroid) {
                _webViewController?.reload();
              } else if (Platform.isIOS) {
                _webViewController?.loadUrl(
                  urlRequest: URLRequest(
                    url: await _webViewController?.getUrl(),
                  ),
                );
              }
            },
          );
    InAppWebViewScreen.addRef();
  }

  @override
  void dispose() {
    InAppWebViewScreen.delRef();
    super.dispose();
  }

  /// 从 WebView localStorage 中读取 auth_data
  Future<String?> _extractAuthData() async {
    if (_webViewController == null) return null;
    try {
      final result = await _webViewController!.evaluateJavascript(
        source: "localStorage.getItem('auth_data')",
      );
      if (result == null || result.toString() == 'null') return null;
      return result.toString();
    } catch (e) {
      Log.w('AccountScreen._extractAuthData exception: $e');
      return null;
    }
  }

  /// 同步订阅：从 XBoard 面板拉取订阅 URL，然后通过 ProfileManager 添加
  Future<void> _syncSubscription() async {
    if (_syncing) return;
    setState(() => _syncing = true);

    try {
      // 1. 从 WebView localStorage 读取登录态
      final authData = await _extractAuthData();
      if (authData == null || authData.isEmpty) {
        _showError('请先登录账号');
        return;
      }

      // 2. 获取当前 WebView 的面板域名（支持自定义部署）
      final currentUrl = await _webViewController?.getUrl();
      String baseUrl = AccountScreen.kPanelUrl;
      if (currentUrl != null) {
        final uri = currentUrl;
        baseUrl = '${uri.scheme}://${uri.host}${uri.port != 80 && uri.port != 443 ? ":${uri.port}" : ""}';
      }

      // 3. 通过 XBoard API 获取订阅链接（严格从面板拉取，不自行生成）
      final result = await XBoardApi.getSubscribeUrl(baseUrl, authData);
      if (result.error != null) {
        _showError(result.error!.message);
        return;
      }

      final subscribeUrl = result.data!;
      Log.d('AccountScreen._syncSubscription subscribeUrl=$subscribeUrl');

      // 4. 通过 ProfileManager 添加/更新远程订阅
      final userAgent = SettingManager.getConfig().userAgent();
      final addResult = await ProfileManager.addRemote(
        subscribeUrl,
        remark: '悦通订阅',
        userAgent: userAgent,
        updateInterval: const Duration(hours: 24),
      );

      if (addResult.error != null) {
        _showError('添加订阅失败: ${addResult.error!.message}');
        return;
      }

      // 5. 设置为当前订阅
      if (addResult.data != null) {
        ProfileManager.setCurrent(addResult.data!);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('订阅同步成功！'),
          backgroundColor: ThemeDefine.kColorIndigo,
          duration: const Duration(seconds: 2),
        ),
      );

      // 引导模式：同步成功后直接返回主界面
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    DialogUtils.showAlertDialog(context, msg, withVersion: false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? ThemeDefine.kColorBgDark : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: AppBar(
          backgroundColor: isDark ? const Color(0xFF12122A) : Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          title: const Text(
            '账号中心',
            style: TextStyle(
              fontWeight: ThemeConfig.kFontWeightTitle,
              fontSize: ThemeConfig.kFontSizeTitle,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 22),
              onPressed: () => _webViewController?.reload(),
              tooltip: '刷新',
            ),
          ],
        ),
      ),
      body: FutureBuilder<bool>(
        future: InAppWebViewScreen.makeSureEnvironmentCreated(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.data!) {
            return const Center(child: Text('WebView 不可用'));
          }
          return Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(AccountScreen.kPanelUrl),
                ),
                initialUserScripts: UnmodifiableListView(_scripts),
                initialSettings: _settings,
                pullToRefreshController: _pullToRefreshController,
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                },
                onLoadStop: (controller, url) async {
                  _pullToRefreshController?.endRefreshing();
                  setState(() => _webviewReady = true);
                },
                onReceivedError: (controller, request, error) {
                  _pullToRefreshController?.endRefreshing();
                },
                onProgressChanged: (controller, progress) {
                  if (progress == 100) {
                    _pullToRefreshController?.endRefreshing();
                  }
                  setState(() => _progress = progress / 100);
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final uri = navigationAction.request.url;
                  if (uri == null) return NavigationActionPolicy.ALLOW;
                  final scheme = uri.scheme;
                  if (!['http', 'https', 'file', 'data', 'javascript', 'about']
                      .contains(scheme)) {
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
              ),
              if (_progress < 1.0)
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    ThemeDefine.kColorIndigo,
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: _webviewReady
          ? FloatingActionButton.extended(
              onPressed: _syncing ? null : _syncSubscription,
              backgroundColor: ThemeDefine.kColorIndigo,
              foregroundColor: Colors.white,
              icon: _syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(_syncing ? '同步中...' : '同步订阅'),
            )
          : null,
    );
  }
}
