/// 启动更新检查与 Android APK 下载入口。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/log.dart';
import 'server_config.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersionName,
    required this.currentVersionCode,
    required this.latestVersionName,
    required this.latestVersionCode,
    required this.downloadUrl,
    required this.notes,
  });

  final String currentVersionName;
  final int currentVersionCode;
  final String latestVersionName;
  final int latestVersionCode;
  final String downloadUrl;
  final String notes;
}

class UpdateService {
  UpdateService._();

  static const MethodChannel _channel = MethodChannel('cn.ylin314/update');

  /// 返回 null 表示没有新版本；检查失败会抛出，由启动门禁阻止进入 APP。
  static Future<AppUpdateInfo?> checkForUpdate() async {
    Map<String, dynamic>? local;
    try {
      local = await _channel.invokeMapMethod<String, dynamic>(
        'getAppVersion',
      );
    } on MissingPluginException {
      // 单元测试或非 Android 平台没有原生通道实现，直接跳过更新检查。
      log('当前平台未实现更新通道，跳过更新检查');
      return null;
    }
    if (local == null) {
      // 测试环境可能返回 null（无原生实现），此时不阻断启动。
      log('未获取到本地版本信息，跳过更新检查');
      return null;
    }
    final currentCode = (local['versionCode'] as num?)?.toInt() ?? 0;
    final currentName = local['versionName'] as String? ?? '未知';

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(
        Uri.parse('${ServerConfig.baseUrl}/api/app/version'),
      );
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('版本服务返回 ${response.statusCode}：$body');
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['enabled'] != true) return null;
      final latestCode = (json['versionCode'] as num?)?.toInt();
      final latestName = json['versionName'] as String?;
      final apkPath = json['apkUrl'] as String?;
      if (latestCode == null || latestName == null || apkPath == null) {
        throw const FormatException('版本服务返回数据不完整');
      }
      if (latestCode <= currentCode) return null;
      final downloadUrl = apkPath.startsWith('http')
          ? apkPath
          : Uri.parse('${ServerConfig.baseUrl}$apkPath').toString();
      log(
        '发现新版本: $currentName($currentCode) → $latestName($latestCode)',
      );
      return AppUpdateInfo(
        currentVersionName: currentName,
        currentVersionCode: currentCode,
        latestVersionName: latestName,
        latestVersionCode: latestCode,
        downloadUrl: downloadUrl,
        notes: json['notes'] as String? ?? '',
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<bool> startUpdate(AppUpdateInfo update) async =>
      await _channel.invokeMethod<bool>('startAppUpdate', {
        'url': update.downloadUrl,
      }) ??
      false;
}
