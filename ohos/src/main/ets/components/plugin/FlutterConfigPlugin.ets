import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { util } from '@kit.ArkTS';
import bundleManager from '@ohos.bundle.bundleManager';

const TAG: string = "FlutterConfig";

export default class FlutterConfigPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private binding: FlutterPluginBinding | null = null;
  private static cachedEnv: Record<string, string> = {};

  constructor() {
  }

  getUniqueClassName(): string {
    return "FlutterConfigPlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "flutter_config");
    this.channel.setMethodCallHandler(this);
    this.binding = binding;
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
    }
    this.binding = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method == "loadEnvVariables") {
      this.loadEnvVariables(result);
    } else {
      result.notImplemented();
    }
  }

  /**
   * 从 rawfile 读取 env 文件并补充系统字段
   * 与 Android FlutterConfigPlugin.kt 行为一致：
   *   1. 读取 .env 文件中的自定义变量
   *   2. 追加 VERSION_NAME、APPLICATION_ID、VERSION_CODE、DEBUG 等系统字段
   *
   * 注意：鸿蒙 getRawFileContentSync 不支持以 '.' 开头的文件名（会报 Invalid relative path）
   * 所以 rawfile 中的文件命名为 "env" 而非 ".env"
   */
  private loadEnvVariables(result: MethodResult): void {
    try {
      // ---- 1. 读取 env 文件中的自定义变量 ----
      let envMap: Record<string, Object> = {};

      if (this.binding !== null) {
        try {
          let resMgr = this.binding.getApplicationContext().resourceManager;
          let envBytes: Uint8Array = resMgr.getRawFileContentSync('env');

          // Uint8Array → UTF-8 string
          let textDecoder = util.TextDecoder.create('utf-8');
          let text: string = textDecoder.decodeToString(envBytes);

          // Strip UTF-8 BOM if present (EF BB BF → U+FEFF)
          if (text.charCodeAt(0) === 0xFEFF) {
            text = text.substring(1);
          }

          // 解析 KEY=VALUE（与 Android dotenv.gradle 保持一致的正则）
          let lines: string[] = text.split('\n');
          let pattern: RegExp = /^\s*(?:export\s+|)([\w\d.\-_]+)\s*=\s*['"]?(.*?)?['"]?\s*$/;

          for (let line of lines) {
            let match: RegExpMatchArray | null = line.match(pattern);
            if (match && match.length >= 3) {
              envMap[match[1]] = match[2].replace(/"/g, '\\"');
            }
          }
        } catch (e) {
          // rawfile/env 不存在或读取失败，envMap 保持为空
        }
      }

      // ---- 2. 追加系统字段（与 Android BuildConfig 反射字段一致）----
      try {
        let bundleInfo: bundleManager.BundleInfo =
          bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);

        // VERSION_NAME
        envMap['VERSION_NAME'] = bundleInfo.versionName;
        // APPLICATION_ID (bundleName)
        envMap['APPLICATION_ID'] = bundleInfo.name;
        // VERSION_CODE
        envMap['VERSION_CODE'] = bundleInfo.versionCode;
        // DEBUG
        envMap['DEBUG'] = bundleInfo.appInfo.debug;
      } catch (e) {
        // bundleManager 获取失败时跳过系统字段
      }

      // ---- 3. 返回给 Dart ----
      result.success(envMap);

      // ---- 4. 缓存供原生侧静态方法使用 ----
      FlutterConfigPlugin.cachedEnv = {};
      let keys: string[] = Object.keys(envMap);
      for (let i = 0; i < keys.length; i++) {
        FlutterConfigPlugin.cachedEnv[keys[i]] = String(envMap[keys[i]]);
      }
    } catch (e) {
      // 兜底：返回空 map，与 Android/iOS 行为一致
      result.success({});
    }
  }

  /**
   * 供鸿蒙原生代码调用的静态方法
   * 类似 iOS 的 FlutterConfigPlugin.env / envFor:
   * 注意：必须在 loadEnvVariables 被调用后才有数据
   */
  static env(): Record<string, string> {
    return FlutterConfigPlugin.cachedEnv;
  }

  static envFor(key: string): string | undefined {
    return FlutterConfigPlugin.cachedEnv[key];
  }
}
