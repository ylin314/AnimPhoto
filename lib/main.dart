import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/onboarding/intro_page.dart';
import 'features/update/mandatory_update_page.dart';
import 'features/update/update_check_failed_page.dart';
import 'features/scan/scan_page.dart';
import 'services/update_service.dart';
import 'services/update_cleanup_service.dart';
import 'theme/app_theme.dart';
import 'utils/log.dart';

void main() {
  log('App 启动');
  runApp(const AnimPhotoApp());
}

/// 瞬影 AnimPhoto — 动态照片扫描 / 播放 / 转换。
/// UI 风格：Material 3，温暖、克制的回忆感。
class AnimPhotoApp extends StatelessWidget {
  const AnimPhotoApp({
    super.key,
    this.checkForUpdate = UpdateService.checkForUpdate,
  });

  final Future<AppUpdateInfo?> Function() checkForUpdate;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '瞬影 AnimPhoto',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: StartupGate(checkForUpdate: checkForUpdate),
    );
  }
}

/// 启动门卫：首次启动展示介绍页。
class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    this.checkForUpdate = UpdateService.checkForUpdate,
  });

  final Future<AppUpdateInfo?> Function() checkForUpdate;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  static const _minimumLoaderDuration = Duration(seconds: 1);
  static const _updateCheckTimeout = Duration(seconds: 5);

  bool? _neverShow;
  AppUpdateInfo? _update;
  Object? _updateError;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() {
        _checking = true;
        _update = null;
        _updateError = null;
      });
    }
    // 偏好读取、版本检查与最短展示时间并行进行。检查较快时等待页至少
    // 保留 1 秒；检查较慢时则持续展示，直到成功或检查自身超时抛错。
    final minimumVisible = Future<void>.delayed(_minimumLoaderDuration);
    final cleanupFuture = UpdateCleanupService.run().catchError((error) {
      // 本地清理失败不应阻断启动；未写入完成标记时，下次启动会自动重试。
      log('版本更新本地数据清理失败（下次重试）：$error');
    });

    AppUpdateInfo? update;
    Object? updateError;
    try {
      update = await widget.checkForUpdate().timeout(_updateCheckTimeout);
    } catch (error) {
      updateError = error;
      log('启动更新检查失败：$error');
    }
    await cleanupFuture;
    final prefs = await SharedPreferences.getInstance();
    final never = prefs.getBool(kIntroNeverShowKey) ?? false;
    await minimumVisible;

    if (mounted) {
      setState(() {
        _neverShow = never;
        _update = update;
        _updateError = updateError;
        _checking = false;
      });
    }
  }

  void _enter(bool neverShow) {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const ScanPage()));
  }

  @override
  Widget build(BuildContext context) {
    if (_checking || _neverShow == null) {
      // 启动时先完成版本检查，避免用户进入主流程后再被中断。
      return const _WarmStartupLoader();
    }
    if (_update != null) {
      return MandatoryUpdatePage(update: _update!);
    }
    if (_updateError != null) {
      return UpdateCheckFailedPage(
        errorText: _updateError.toString(),
        onRetry: _bootstrap,
      );
    }
    if (_neverShow!) {
      return const ScanPage();
    }
    return IntroPage(onDone: _enter);
  }
}

class _WarmStartupLoader extends StatefulWidget {
  const _WarmStartupLoader();

  @override
  State<_WarmStartupLoader> createState() => _WarmStartupLoaderState();
}

class _WarmStartupLoaderState extends State<_WarmStartupLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.72),
              scheme.surface,
              scheme.secondaryContainer.withValues(alpha: 0.52),
            ],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final value = reduceMotion ? 0.5 : _controller.value;
              return Transform.scale(
                scale: 0.98 + value * 0.04,
                child: Opacity(opacity: 0.82 + value * 0.18, child: child),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.14),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset('assets/icon/app_icon.png'),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '正在唤醒你的鲜活回忆',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '稍等片刻',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
