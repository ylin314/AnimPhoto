/// 版本更新后的本地数据清理配置。
///
/// 使用方法：
/// 1. 每次需要发布新的清理策略时，修改 [migrationId]。
/// 2. 将需要清理的项目改为 true，不需要清理的项目保持 false。
/// 3. 同一个 migrationId 在每台设备上只会执行一次。
abstract final class UpdateCleanupConfig {
  /// 清理批次标识。需要再次执行清理时必须修改，例如 `1.4.1-cleanup-1`。
  static const String migrationId = '1.4.2-initial';

  /// 删除动态照片扫描缓存。开启后，用户将执行一次全盘快速扫描。
  static const bool clearScanCache = false;

  /// 重置 APP 首次启动欢迎页，使其再次展示。
  static const bool resetAppIntro = true;

  /// 重置「本机不支持的动态照片」欢迎页，使其再次展示。
  static const bool resetUnsupportedPhotosIntro = false;

  /// 重置「长按照片进入多选」提示。
  static const bool resetMultiSelectEntryGuide = false;

  /// 重置多选状态右上角操作按钮的分步提示。
  static const bool resetMultiSelectActionsGuide = false;

  /// 重置照片查看页播放键、三点菜单及照片信息页提示。
  static const bool resetPhotoMenuGuide = false;

  /// 删除已生成分享链接的本地复用缓存。
  static const bool clearShareLinkCache = false;

  /// 清空 APP 诊断日志。
  static const bool clearDiagnosticLog = true;

  /// 删除 APP 在系统临时目录中生成的转换、提取和播放临时文件。
  static const bool clearTemporaryFiles = true;
}
