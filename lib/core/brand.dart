/// 设备品牌识别与目标格式选择（见 AGENT.md 5.6）。
library;

import 'motion_photo.dart';

enum DeviceBrand { oppo, vivo, xiaomi, honor, huawei, other }

class BrandDetector {
  BrandDetector._();

  /// 由设备厂商字符串（Build.MANUFACTURER / Build.BRAND / ro.product.brand）判定品牌。
  static DeviceBrand fromManufacturer(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('oppo') || s.contains('realme') || s.contains('oneplus')) {
      return DeviceBrand.oppo;
    }
    if (s.contains('vivo') || s.contains('iqoo')) {
      return DeviceBrand.vivo;
    }
    if (s.contains('xiaomi') ||
        s.contains('redmi') ||
        s.contains('poco') ||
        s.contains('blackshark')) {
      return DeviceBrand.xiaomi;
    }
    if (s.contains('honor')) {
      return DeviceBrand.honor;
    }
    if (s.contains('huawei')) {
      return DeviceBrand.huawei;
    }
    return DeviceBrand.other;
  }

  /// 本机品牌对应的转换目标格式。
  static TargetFormat targetForDevice(DeviceBrand brand) {
    switch (brand) {
      case DeviceBrand.oppo:
        return TargetFormat.oppo;
      case DeviceBrand.vivo:
        return TargetFormat.vivo;
      case DeviceBrand.xiaomi:
        return TargetFormat.xiaomi;
      case DeviceBrand.honor:
      case DeviceBrand.huawei:
        return TargetFormat.honorHuawei;
      case DeviceBrand.other:
        return TargetFormat.google;
    }
  }

  static String targetLabel(TargetFormat fmt) {
    switch (fmt) {
      case TargetFormat.google:
        return 'Google 标准';
      case TargetFormat.oppo:
        return 'OPPO/一加/realme';
      case TargetFormat.vivo:
        return 'vivo/iQOO';
      case TargetFormat.xiaomi:
        return '小米/REDMI';
      case TargetFormat.honorHuawei:
        return '华为/荣耀';
    }
  }
}
