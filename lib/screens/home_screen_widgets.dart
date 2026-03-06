// ignore_for_file: prefer_interpolation_to_compose_strings, use_build_context_synchronously, empty_catches, unused_catch_stack

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmi/app/clash/clash_config.dart';
import 'package:clashmi/app/clash/clash_http_api.dart';
import 'package:clashmi/app/local_services/vpn_service.dart';
import 'package:clashmi/app/modules/auto_update_manager.dart';
import 'package:clashmi/app/modules/biz.dart';
import 'package:clashmi/app/modules/clash_setting_manager.dart';
import 'package:clashmi/app/modules/profile_manager.dart';
import 'package:clashmi/app/modules/setting_manager.dart';
import 'package:clashmi/app/modules/zashboard.dart';
import 'package:clashmi/app/runtime/return_result.dart';
import 'package:clashmi/app/utils/app_lifecycle_state_notify.dart';
import 'package:clashmi/app/utils/app_scheme_actions.dart';
import 'package:clashmi/app/utils/file_utils.dart';
import 'package:clashmi/app/utils/log.dart';
import 'package:clashmi/app/utils/move_to_background_utils.dart';
import 'package:clashmi/app/utils/network_utils.dart';
import 'package:clashmi/app/utils/path_utils.dart';
import 'package:clashmi/app/utils/platform_utils.dart';
import 'package:clashmi/i18n/strings.g.dart';
import 'package:clashmi/screens/about_screen.dart';
import 'package:clashmi/screens/account_screen.dart';
import 'package:clashmi/screens/dialog_utils.dart';
import 'package:clashmi/screens/file_view_screen.dart';
import 'package:clashmi/screens/group_helper.dart';
import 'package:clashmi/screens/profiles_board_screen.dart';
import 'package:clashmi/screens/proxy_board_screen.dart';
import 'package:clashmi/screens/richtext_viewer.screen.dart';
import 'package:clashmi/screens/theme_define.dart';
import 'package:clashmi/app/utils/vpn_action_handler.dart';
import 'package:clashmi/screens/webview_helper.dart';
import 'package:flutter/material.dart';
import 'package:libclash_vpn_service/state.dart';
import 'package:libclash_vpn_service/vpn_service.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:tuple/tuple.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VPN 仪表盘主控件
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreenWidgetPart1 extends StatefulWidget {
  const HomeScreenWidgetPart1({super.key});

  @override
  State<HomeScreenWidgetPart1> createState() => _HomeScreenWidgetPart1State();
}

class _HomeScreenWidgetPart1State extends State<HomeScreenWidgetPart1>
    with SingleTickerProviderStateMixin {
  static const String _kNoSpeed = '0 B/s';
  static const String _kNoTrafficTotal = '0 B';

  final FocusNode _focusNodeConnect = FocusNode();
  FlutterVpnServiceState _state = FlutterVpnServiceState.disconnected;
  Timer? _timerStateChecker;
  Timer? _timerConnectToCore;
  QuickActions? _quickActions;
  bool _quickActionWorking = false;

  final ValueNotifier<String> _uploadSpeed = ValueNotifier<String>(_kNoSpeed);
  final ValueNotifier<String> _downloadSpeed = ValueNotifier<String>(_kNoSpeed);
  final ValueNotifier<String> _uploadTotal = ValueNotifier<String>(_kNoTrafficTotal);
  final ValueNotifier<String> _downloadTotal = ValueNotifier<String>(_kNoTrafficTotal);
  final ValueNotifier<String> _proxyNow = ValueNotifier<String>('');
  bool _proxyNowUpdating = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    VPNService.onEventStateChanged.add(_onStateChanged);
    AppLifecycleStateNofity.onStateResumed(hashCode, _onStateResumed);
    AppLifecycleStateNofity.onStatePaused(hashCode, _onStatePaused);
    ProfileManager.onEventCurrentChanged.add(_onCurrentChanged);
    ProfileManager.onEventUpdate.add(_onUpdate);
    if (!AppLifecycleStateNofity.isPaused()) {
      _onStateResumed();
    }
    Biz.onEventInitAllFinish.add(() async {
      if (Platform.isAndroid) {
        if (SettingManager.getConfig().excludeFromRecent) {
          FlutterVpnService.setExcludeFromRecents(true);
        }
      }
      await _onInitAllFinish();
    });
    ClashSettingManager.onEventModeChanged.add(() async {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _focusNodeConnect.dispose();
    super.dispose();
  }

  bool get _isConnected => _state == FlutterVpnServiceState.connected;
  bool get _isTransitioning =>
      _state == FlutterVpnServiceState.connecting ||
      _state == FlutterVpnServiceState.disconnecting ||
      _state == FlutterVpnServiceState.reasserting;

  void _startPulse() {
    _pulseController.repeat(reverse: true);
  }

  void _stopPulse() {
    _pulseController.stop();
    _pulseController.reset();
  }

  // ───────────────────────── Build ──────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tcontext = Translations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentProfile = ProfileManager.getCurrent();
    final settings = SettingManager.getConfig();

    String trafficUsed = '';
    String trafficTotal = '';
    Tuple2<bool, String>? expireInfo;

    if (currentProfile != null && currentProfile.isRemote()) {
      if (currentProfile.upload != 0 ||
          currentProfile.download != 0 ||
          currentProfile.total != 0) {
        trafficUsed = ClashHttpApi.convertTrafficToStringDouble(
          currentProfile.upload + currentProfile.download,
        );
        trafficTotal = ClashHttpApi.convertTrafficToStringDouble(
          currentProfile.total,
        );
      }
      if (currentProfile.expire.isNotEmpty) {
        expireInfo = currentProfile.getExpireTime(settings.languageTag);
      }
    }

    return Column(
      children: [
        // ── 大圆形连接按钮区域 ──
        _buildConnectButton(isDark),
        const SizedBox(height: 24),

        // ── 实时速度（连接时显示）──
        if (_isConnected) _buildSpeedRow(isDark),
        if (_isConnected) const SizedBox(height: 20),

        // ── 节点模式卡片 ──
        _buildModeCard(tcontext, isDark),
        const SizedBox(height: 12),

        // ── 订阅卡片 ──
        _buildSubscriptionCard(
          tcontext,
          isDark,
          currentProfile,
          trafficUsed,
          trafficTotal,
          expireInfo,
        ),
        const SizedBox(height: 12),

        // ── 连接时：代理节点 + 控制面板 ──
        if (_isConnected) ...[
          _buildConnectedCard(tcontext, isDark),
          const SizedBox(height: 12),
        ],

        // ── 底部快捷操作栏 ──
        _buildQuickBar(tcontext, isDark),
      ],
    );
  }

  // ─────────────── 圆形连接按钮 ────────────────────────────────────────────

  Widget _buildConnectButton(bool isDark) {
    final Color innerColor;
    final Color ringColor;
    final IconData icon;
    String label;

    if (_isConnected) {
      innerColor = ThemeDefine.kColorIndigo;
      ringColor = ThemeDefine.kColorIndigo.withOpacity(0.25);
      icon = Icons.shield_rounded;
      label = '已连接';
    } else if (_isTransitioning) {
      innerColor = const Color(0xFF6B6B9A);
      ringColor = const Color(0xFF6B6B9A).withOpacity(0.2);
      icon = Icons.sync_rounded;
      label = _state == FlutterVpnServiceState.connecting ? '连接中...' : '断开中...';
    } else {
      innerColor = isDark ? const Color(0xFF2A2A45) : const Color(0xFFE8E8F5);
      ringColor = isDark ? const Color(0xFF2A2A45) : const Color(0xFFDDDDF5);
      icon = Icons.power_settings_new_rounded;
      label = '未连接';
    }

    return Column(
      children: [
        GestureDetector(
          onTap: () async {
            if (_isTransitioning) return;
            if (_isConnected) {
              await stop();
            } else {
              await start('button');
            }
          },
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _isConnected ? _pulseAnimation.value : 1.0,
                child: child,
              );
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 外环
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ringColor,
                  ),
                ),
                // 内圆
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: _isConnected
                          ? [
                              const Color(0xFF6366F1),
                              ThemeDefine.kColorIndigo,
                            ]
                          : [
                              innerColor,
                              innerColor,
                            ],
                    ),
                    boxShadow: _isConnected
                        ? [
                            BoxShadow(
                              color: ThemeDefine.kColorIndigo.withOpacity(0.5),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ]
                        : [],
                  ),
                  child: _isTransitioning
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        )
                      : Icon(
                          icon,
                          size: 52,
                          color: _isConnected
                              ? Colors.white
                              : isDark
                              ? Colors.white54
                              : const Color(0xFF9090C0),
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        // 状态文字
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isConnected
                    ? ThemeDefine.kColorGreenBright
                    : _isTransitioning
                    ? Colors.orange
                    : Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _isConnected
                    ? ThemeDefine.kColorGreenBright
                    : isDark
                    ? Colors.white70
                    : Colors.black54,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─────────────── 实时速度行 ──────────────────────────────────────────────

  Widget _buildSpeedRow(bool isDark) {
    final textStyle = TextStyle(
      fontSize: 13,
      color: isDark ? Colors.white60 : Colors.black54,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.arrow_upward_rounded, size: 14, color: ThemeDefine.kColorIndigo),
        const SizedBox(width: 4),
        ValueListenableBuilder<String>(
          valueListenable: _uploadSpeed,
          builder: (_, v, __) => Text(v, style: textStyle),
        ),
        const SizedBox(width: 20),
        Icon(Icons.arrow_downward_rounded, size: 14, color: ThemeDefine.kColorGreenBright),
        const SizedBox(width: 4),
        ValueListenableBuilder<String>(
          valueListenable: _downloadSpeed,
          builder: (_, v, __) => Text(v, style: textStyle),
        ),
      ],
    );
  }

  // ─────────────── 节点模式卡片 ────────────────────────────────────────────

  Widget _buildModeCard(TranslationsEn tcontext, bool isDark) {
    final cardColor = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final modes = [
      _ModeItem(
        index: ClashConfigsMode.rule.index,
        label: '规则',
        icon: Icons.rule_rounded,
      ),
      _ModeItem(
        index: ClashConfigsMode.global.index,
        label: '全局',
        icon: Icons.language_rounded,
      ),
      _ModeItem(
        index: ClashConfigsMode.direct.index,
        label: '直连',
        icon: Icons.link_off_rounded,
      ),
    ];
    final currentMode = ClashSettingManager.getConfigsMode().index;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Row(
        children: [
          Icon(Icons.tune_rounded, size: 18, color: ThemeDefine.kColorIndigo),
          const SizedBox(width: 8),
          Text(
            '代理模式',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const Spacer(),
          Row(
            children: modes.map((mode) {
              final isSelected = mode.index == currentMode;
              return GestureDetector(
                onTap: () async {
                  final type = ClashConfigsMode.values[mode.index];
                  final error = await ClashSettingManager.setConfigsMode(type);
                  if (!context.mounted) return;
                  if (error != null) {
                    DialogUtils.showAlertDialog(context, error.message, withVersion: true);
                    return;
                  }
                  _updateProxyNow();
                  setState(() {});
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? ThemeDefine.kColorIndigo
                        : isDark
                        ? const Color(0xFF2A2A45)
                        : const Color(0xFFF0F0F8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    mode.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : isDark
                          ? Colors.white60
                          : Colors.black54,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─────────────── 订阅卡片 ────────────────────────────────────────────────

  Widget _buildSubscriptionCard(
    TranslationsEn tcontext,
    bool isDark,
    ProfileSetting? profile,
    String trafficUsed,
    String trafficTotal,
    Tuple2<bool, String>? expireInfo,
  ) {
    final cardColor = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final hasProfile = profile != null;
    final isExpiring = expireInfo?.item1 == true;

    double trafficRatio = 0;
    if (trafficUsed.isNotEmpty && trafficTotal.isNotEmpty && profile != null) {
      final used = (profile.upload + profile.download).toDouble();
      final total = profile.total.toDouble();
      if (total > 0) trafficRatio = (used / total).clamp(0.0, 1.0);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.card_membership_rounded,
                size: 18,
                color: ThemeDefine.kColorIndigo,
              ),
              const SizedBox(width: 8),
              Text(
                '我的订阅',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const Spacer(),
              // 账号中心按钮
              GestureDetector(
                onTap: _openAccountCenter,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ThemeDefine.kColorIndigo.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_rounded,
                        size: 14,
                        color: ThemeDefine.kColorIndigo,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '账号',
                        style: TextStyle(
                          fontSize: 12,
                          color: ThemeDefine.kColorIndigo,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 添加/切换订阅
              GestureDetector(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      settings: ProfilesBoardScreen.routSettings(),
                      builder: (_) => ProfilesBoardScreen(navigateToAdd: !hasProfile),
                    ),
                  );
                  setState(() {});
                },
                child: Icon(
                  hasProfile ? Icons.swap_horiz_rounded : Icons.add_circle_outline_rounded,
                  size: 22,
                  color: ThemeDefine.kColorIndigo,
                ),
              ),
            ],
          ),
          if (!hasProfile) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _openAccountCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      ThemeDefine.kColorIndigo.withOpacity(0.8),
                      const Color(0xFF6366F1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      '登录账号并同步订阅',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              profile.getShowName(),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (trafficUsed.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '已用 $trafficUsed',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                  Text(
                    '总计 $trafficTotal',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: trafficRatio,
                  minHeight: 6,
                  backgroundColor: isDark
                      ? const Color(0xFF2A2A45)
                      : const Color(0xFFE8E8F5),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    trafficRatio > 0.8
                        ? Colors.red
                        : ThemeDefine.kColorIndigo,
                  ),
                ),
              ),
            ],
            if (expireInfo != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 12,
                    color: isExpiring ? Colors.red : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '到期：${expireInfo.item2}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isExpiring ? Colors.red : Colors.grey,
                    ),
                  ),
                  if (isExpiring) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _openAccountCenter,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '续费',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ─────────────── 连接时的代理/控制面板卡片 ───────────────────────────────

  Widget _buildConnectedCard(TranslationsEn tcontext, bool isDark) {
    final cardColor = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          // 当前节点
          ListTile(
            dense: true,
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: ThemeDefine.kColorIndigo.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.location_on_rounded,
                size: 16,
                color: ThemeDefine.kColorIndigo,
              ),
            ),
            title: Text(
              '当前节点',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: ValueListenableBuilder<String>(
              valueListenable: _proxyNow,
              builder: (_, v, __) => Text(
                v.isEmpty ? '获取中...' : v,
                style: TextStyle(
                  fontSize: 12,
                  color: ThemeDefine.kColorIndigo,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  settings: ProxyBoardScreen.routSettings(),
                  builder: (_) => ProxyBoardScreen(),
                ),
              );
              _updateProxyNow();
            },
          ),
          Divider(height: 1, thickness: 0.3, indent: 52),
          // 控制面板
          ListTile(
            dense: true,
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: ThemeDefine.kColorGreenBright.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.dashboard_rounded,
                size: 16,
                color: ThemeDefine.kColorGreenBright,
              ),
            ),
            title: Text(
              '控制面板',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
            onTap: () async {
              final tcontext = Translations.of(context);
              final setting = SettingManager.getConfig();
              if (setting.boardOnline && setting.boardUrl.isNotEmpty) {
                final uri = Uri.tryParse(setting.boardUrl);
                if (uri == null) {
                  DialogUtils.showAlertDialog(
                    context,
                    '${tcontext.meta.urlInvalid}:${setting.boardUrl}',
                    withVersion: true,
                  );
                  return;
                }
                final shortUrl = Uri(
                  scheme: uri.scheme,
                  userInfo: uri.userInfo,
                  host: uri.host,
                  port: uri.port,
                );
                String host = Platform.isIOS
                    ? await _getLocalAddress()
                    : '127.0.0.1';
                String secret = await ClashHttpApi.getSecret();
                final url =
                    '${shortUrl}/?hostname=$host&port=${ClashSettingManager.getControlPort()}&secret=$secret&http=true';
                if (!context.mounted) return;
                await WebviewHelper.loadUrl(
                  context,
                  url,
                  'onlineboard',
                  title: tcontext.meta.board,
                  inappWebViewOpenExternal: false,
                );
                return;
              }
              ReturnResult result = await Zashboard.start();
              if (result.error != null) {
                if (!context.mounted) return;
                DialogUtils.showAlertDialog(
                  context,
                  result.error!.message,
                  withVersion: true,
                );
                return;
              }
              String url = result.data!;
              if (!context.mounted) return;
              await WebviewHelper.loadUrl(
                context,
                url,
                'board',
                title: tcontext.meta.board,
                inappWebViewOpenExternal: false,
              );
              if (PlatformUtils.isMobile()) {
                await Zashboard.stop();
              }
              _updateProxyNow();
            },
          ),
          Divider(height: 1, thickness: 0.3, indent: 52),
          // 流量统计
          ListTile(
            dense: true,
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.data_usage_rounded,
                size: 16,
                color: Colors.orange,
              ),
            ),
            title: Text(
              '本次流量',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: Row(
              children: [
                Icon(Icons.arrow_upward_rounded, size: 11, color: ThemeDefine.kColorIndigo),
                const SizedBox(width: 2),
                ValueListenableBuilder<String>(
                  valueListenable: _uploadTotal,
                  builder: (_, v, __) => Text(
                    v,
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black45),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_downward_rounded, size: 11, color: ThemeDefine.kColorGreenBright),
                const SizedBox(width: 2),
                ValueListenableBuilder<String>(
                  valueListenable: _downloadTotal,
                  builder: (_, v, __) => Text(
                    v,
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black45),
                  ),
                ),
              ],
            ),
            onTap: () async {
              final tcontext = Translations.of(context);
              late String content;
              try {
                final path = await PathUtils.serviceCoreRuntimeProfileFilePath();
                content = await File(path).readAsString();
              } catch (err) {
                if (!context.mounted) return;
                DialogUtils.showAlertDialog(
                  context,
                  err.toString(),
                  showCopy: true,
                  showFAQ: true,
                  withVersion: true,
                );
                return;
              }
              if (!context.mounted) return;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  settings: FileViewScreen.routSettings(),
                  builder: (_) => FileViewScreen(
                    title: tcontext.meta.runtimeProfile,
                    content: content,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ─────────────── 底部快捷栏 ──────────────────────────────────────────────

  Widget _buildQuickBar(TranslationsEn tcontext, bool isDark) {
    final barColor = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: barColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Row(
        children: [
          _buildQuickBarItem(
            icon: Icons.settings_rounded,
            label: '设置',
            isDark: isDark,
            onTap: () => GroupHelper.showAppSettings(context),
          ),
          _buildQuickBarDivider(isDark),
          _buildQuickBarItem(
            icon: Icons.article_rounded,
            label: '日志',
            isDark: isDark,
            onTap: () async {
              final tcontext = Translations.of(context);
              String content = '';
              final filePath = await PathUtils.serviceLogFilePath();
              final item = await FileUtils.readAsStringReverse(filePath, 20 * 1024, false);
              if (item != null) content = item.item1;
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  settings: RichtextViewScreen.routSettings(),
                  builder: (_) => RichtextViewScreen(
                    title: tcontext.meta.coreLog,
                    file: '',
                    content: content,
                    showAction: true,
                  ),
                ),
              );
            },
          ),
          _buildQuickBarDivider(isDark),
          _buildQuickBarItem(
            icon: Icons.store_rounded,
            label: '购买',
            isDark: isDark,
            onTap: _openAccountCenter,
          ),
          _buildQuickBarDivider(isDark),
          _buildQuickBarItem(
            icon: Icons.info_outline_rounded,
            label: '关于',
            isDark: isDark,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                settings: AboutScreen.routSettings(),
                builder: (_) => AboutScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickBarItem({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isDark ? Colors.white60 : Colors.black45,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : Colors.black45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickBarDivider(bool isDark) {
    return Container(
      width: 1,
      height: 28,
      color: isDark ? Colors.white12 : Colors.black12,
    );
  }

  // ─────────────── 账号中心入口 ────────────────────────────────────────────

  Future<void> _openAccountCenter() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        settings: AccountScreen.routSettings(),
        builder: (_) => const AccountScreen(),
      ),
    );
    if (result == true) {
      setState(() {});
    }
  }

  // ─────────────── VPN 控制 ────────────────────────────────────────────────

  Future<void> stop() async {
    await VPNService.stop();
  }

  Future<bool> start(String from) async {
    final currentProfile = ProfileManager.getCurrent();
    if (currentProfile == null) {
      // 无订阅 → 跳账号中心，而非订阅列表
      await _openAccountCenter();
      setState(() {});
      return false;
    }
    if (Platform.isLinux) {
      String? installer = await AutoUpdateManager.checkReplace();
      if (installer != null) return true;
      final servicePath = PathUtils.serviceExePath();
      if (!await FlutterVpnService.isServiceAuthorized(servicePath)) {
        if (!mounted) return false;
        String? password = await DialogUtils.showPasswordInputDialog(context);
        if (password == null || password.isEmpty) {
          setState(() {});
          return true;
        }
        final result = await FlutterVpnService.authorizeService(servicePath, password);
        if (result != null) {
          if (!mounted) return false;
          DialogUtils.showAlertDialog(context, result.message, withVersion: true);
          setState(() {});
          return false;
        }
      }
    }
    var state = await VPNService.getState();
    if (state == FlutterVpnServiceState.connecting ||
        state == FlutterVpnServiceState.disconnecting ||
        state == FlutterVpnServiceState.reasserting) {
      setState(() {});
      return false;
    }
    var err = await VPNService.start(const Duration(seconds: 60));
    if (!mounted) return false;
    setState(() {});
    if (err != null) {
      if (err.message == 'willCompleteAfterRebootInstall') {
        err.message = t.meta.willCompleteAfterRebootInstall;
      } else if (err.message == 'requestNeedsUserApproval') {
        err.message = t.meta.requestNeedsUserApproval;
      } else if (err.message.contains('FullDiskAccessPermissionRequired')) {
        err.message = t.meta.FullDiskAccessPermissionRequired;
      } else if (err.message.contains('configure tun interface: Access is denied')) {
        err.message += '\n${t.meta.tunModeRunAsAdmin}';
      }
      DialogUtils.showAlertDialog(context, err.message, withVersion: true);
      return false;
    }
    return true;
  }

  // ─────────────── 事件处理 ────────────────────────────────────────────────

  Future<void> _vpnConnect(String from, bool background) async {
    Future.delayed(Duration.zero, () async {
      bool ok = await start(from);
      if (ok && background) {
        MoveToBackgroundUtils.moveToBackground(duration: const Duration(milliseconds: 300));
      }
    });
  }

  Future<void> _vpnDisconnect(String from, bool background) async {
    Future.delayed(Duration.zero, () async {
      await stop();
      if (background) {
        MoveToBackgroundUtils.moveToBackground(duration: const Duration(milliseconds: 300));
      }
    });
  }

  Future<void> _vpnReconnect(String from, bool background) async {
    Future.delayed(Duration.zero, () async {
      await stop();
      bool ok = await start(from);
      if (ok && background) {
        MoveToBackgroundUtils.moveToBackground(duration: const Duration(milliseconds: 300));
      }
    });
  }

  Future<void> _onStateChanged(
    FlutterVpnServiceState state,
    Map<String, String> params,
  ) async {
    if (_state == state) return;
    _state = state;
    if (state == FlutterVpnServiceState.disconnected) {
      _stopPulse();
      _disconnectToCore();
      Biz.vpnStateChanged(false);
    } else if (state == FlutterVpnServiceState.connecting) {
      _stopPulse();
    } else if (state == FlutterVpnServiceState.connected) {
      _startPulse();
      if (!AppLifecycleStateNofity.isPaused()) {
        _connectToCore();
      }
      Biz.vpnStateChanged(true);
    } else if (state == FlutterVpnServiceState.reasserting) {
      _disconnectToCore();
    } else if (state == FlutterVpnServiceState.disconnecting) {
      _stopStateCheckTimer();
      Zashboard.stop();
    } else {
      _stopPulse();
      _disconnectToCore();
      Biz.vpnStateChanged(false);
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _onStateResumed() async {
    _checkState();
    _startStateCheckTimer();
    _connectToCore();
    _updateProxyNow();
  }

  Future<void> _onStatePaused() async {
    _stopStateCheckTimer();
    _disconnectToCore(resetUI: false);
  }

  Future<void> _onCurrentChanged(String id) async {
    if (id.isEmpty) {
      await VPNService.stop();
      return;
    }
    final err = await VPNService.restart(const Duration(seconds: 60));
    if (err != null) {
      if (!mounted) return;
      DialogUtils.showAlertDialog(context, err.message, withVersion: true);
    }
  }

  Future<void> _onUpdate(String id, bool finish) async {
    setState(() {});
  }

  Future<void> _checkState() async {
    var state = await VPNService.getState();
    await _onStateChanged(state, {});
  }

  void _startStateCheckTimer() {
    const Duration duration = Duration(seconds: 1);
    _timerStateChecker ??= Timer.periodic(duration, (timer) async {
      if (!Platform.isMacOS) {
        if (AppLifecycleStateNofity.isPaused()) return;
      }
      await _checkState();
    });
  }

  void _stopStateCheckTimer() {
    if (!Platform.isMacOS) {
      _timerStateChecker?.cancel();
      _timerStateChecker = null;
    }
  }

  Future<void> _connectToCore() async {
    bool started = await VPNService.getStarted();
    if (!started) return;
    if (AppLifecycleStateNofity.isPaused()) return;
    const Duration duration = Duration(seconds: 1);
    _timerConnectToCore ??= Timer.periodic(duration, (timer) async {
      if (AppLifecycleStateNofity.isPaused()) return;
      String connections = await FlutterVpnService.clashiApiConnections(false);
      String traffic = await FlutterVpnService.clashiApiTraffic();
      if (AppLifecycleStateNofity.isPaused()) return;
      try {
        var obj = jsonDecode(connections);
        ClashConnections body = ClashConnections();
        body.fromJson(obj);
        _uploadTotal.value = ClashHttpApi.convertTrafficToStringDouble(body.uploadTotal);
        _downloadTotal.value = ClashHttpApi.convertTrafficToStringDouble(body.downloadTotal);
      } catch (err) {}
      try {
        var obj = jsonDecode(traffic);
        ClashTraffic t = ClashTraffic();
        t.fromJson(obj);
        _uploadSpeed.value =
            '${ClashHttpApi.convertTrafficToStringDouble(t.upload)}/s';
        _downloadSpeed.value =
            '${ClashHttpApi.convertTrafficToStringDouble(t.download)}/s';
      } catch (err) {}
      if (_proxyNow.value.isEmpty) {
        Future.delayed(const Duration(seconds: 1), () => _updateProxyNow());
      }
    });
  }

  Future<void> _disconnectToCore({bool resetUI = true}) async {
    _timerConnectToCore?.cancel();
    _timerConnectToCore = null;
    if (resetUI) {
      _uploadTotal.value = _kNoTrafficTotal;
      _downloadTotal.value = _kNoTrafficTotal;
      _uploadSpeed.value = _kNoSpeed;
      _downloadSpeed.value = _kNoSpeed;
      _proxyNow.value = '';
    }
  }

  Future<void> _updateProxyNow() async {
    if (_state != FlutterVpnServiceState.connected) {
      _proxyNow.value = '';
      return;
    }
    if (AppLifecycleStateNofity.isPaused()) return;
    if (_proxyNowUpdating) return;
    _proxyNowUpdating = true;
    final result = await ClashHttpApi.getNowProxy(
      ClashSettingManager.getConfig().Mode ?? ClashConfigsMode.rule.name,
    );
    if (result.error != null || result.data!.isEmpty) {
      _proxyNow.value = '';
    } else {
      if (result.data!.length >= 2) {
        if (result.data!.first.delay != null) {
          _proxyNow.value =
              '${result.data![1].name} → ${result.data!.first.name} (${result.data!.first.delay} ms)';
        } else {
          _proxyNow.value =
              '${result.data![1].name} → ${result.data!.first.name}';
        }
      } else {
        if (result.data!.first.delay != null) {
          _proxyNow.value =
              '${result.data!.first.name} (${result.data!.first.delay} ms)';
        } else {
          _proxyNow.value = result.data!.first.name;
        }
      }
    }
    _proxyNowUpdating = false;
  }

  Future<String> _getLocalAddress() async {
    String ipInterface = '127.0.0.1';
    List<NetInterfacesInfo> interfaces = await NetworkUtils.getInterfaces(
      addressType: InternetAddressType.IPv4,
    );
    if (interfaces.isNotEmpty) ipInterface = interfaces.first.address;
    for (var interf in interfaces) {
      if (interf.name.startsWith('en') || interf.name.startsWith('wlan')) {
        ipInterface = interf.address;
        break;
      }
    }
    return ipInterface;
  }

  Future<void> _onInitAllFinish() async {
    VpnActionHandler.vpnConnect = _vpnConnect;
    VpnActionHandler.vpnDisconnect = _vpnDisconnect;
    VpnActionHandler.vpnReconnect = _vpnReconnect;
    initQuickAction();
    if (PlatformUtils.isPC()) {
      if (SettingManager.getConfig().autoConnectAfterLaunch) {
        await start('launch');
      }
    }
  }

  void initQuickAction() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    String connect = AppSchemeActions.connectAction();
    String disconnect = AppSchemeActions.disconnectAction();
    try {
      _quickActions ??= QuickActions();
      await _quickActions!.initialize((String shortcutType) async {
        if (_quickActionWorking) return;
        _quickActionWorking = true;
        var state = await VPNService.getState();
        if (shortcutType == connect) {
          if (state != FlutterVpnServiceState.invalid &&
              state != FlutterVpnServiceState.disconnected) {
            MoveToBackgroundUtils.moveToBackground(
              duration: const Duration(milliseconds: 300),
            );
            _quickActionWorking = false;
            return;
          }
          bool ok = await start('quickAction');
          if (ok) {
            MoveToBackgroundUtils.moveToBackground(
              duration: const Duration(milliseconds: 300),
            );
          }
        } else if (shortcutType == disconnect) {
          if (state == FlutterVpnServiceState.connected) await stop();
          MoveToBackgroundUtils.moveToBackground(
            duration: const Duration(milliseconds: 300),
          );
        }
        _quickActionWorking = false;
      });
      await _quickActions!.setShortcutItems(<ShortcutItem>[
        ShortcutItem(type: connect, localizedTitle: '连接', icon: 'ic_launcher'),
        ShortcutItem(type: disconnect, localizedTitle: '断开', icon: 'ic_launcher'),
      ]);
    } catch (err) {
      Log.w('initQuickAction exception ${err.toString()}');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 辅助数据类
// ─────────────────────────────────────────────────────────────────────────────

class _ModeItem {
  final int index;
  final String label;
  final IconData icon;
  const _ModeItem({required this.index, required this.label, required this.icon});
}

// ─────────────────────────────────────────────────────────────────────────────
// Part2 不再使用（功能已整合进 Part1 的快捷栏），保留空实现以免破坏导入
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreenWidgetPart2 extends StatelessWidget {
  const HomeScreenWidgetPart2({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
