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
   *
   * rawfile/env 由 Hvigor 构建脚本从项目根目录的 .env 文件自动生成，
   * 开发者无需手动在 rawfile 下放置 env 文件。
   *
   * 与 Android FlutterConfigPlugin.kt 行为一致：
   *   1. 读取 .env 文件中的自定义变量
   *   2. 追加 VERSION_NAME、APPLICATION_ID、VERSION_CODE、DEBUG 等系统字段
   *   3. 无 .env 文件时，仍返回系统字段（与安卓 BuildConfig 行为一致）
   */
  private loadEnvVariables(result: MethodResult): void {
    // ---- 1. 从 rawfile 读取 env 变量 ----
    let envVars: Record<string, Object> = {};
    let envLoaded: boolean = false;

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
            envVars[match[1]] = match[2].replace(/"/g, '\\"');
          }
        }

        envLoaded = true;
      } catch (e) {
        // rawfile/env 不存在或读取失败，继续获取系统字段
      }
    }

    // ---- 2. 获取系统字段（无论env是否存在，始终获取，与安卓BuildConfig行为一致）----
    let versionName: string = '';
    let applicationId: string = '';
    let versionCode: number = 0;
    let debug: boolean = false;

    try {
      let bundleInfo: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);

      versionName = bundleInfo.versionName;
      applicationId = bundleInfo.name;
      versionCode = bundleInfo.versionCode;
      debug = bundleInfo.appInfo.debug;
    } catch (e) {
      // bundleManager 获取失败时跳过系统字段
    }

    // ---- 3. 仅当既无env变量又无系统字段时返回空Map ----
    let hasSystemFields: boolean = versionName !== '' || applicationId !== '';
    if (!envLoaded && !hasSystemFields) {
      result.success({});
      return;
    }

    // ---- 4. 按 Android 字段顺序构建返回 Map ----
    //    顺序与 Android BuildConfig declaredFields 反射顺序一致
    let envMap: Record<string, Object> = {};

    envMap['VERSION_NAME'] = versionName;
    envMap['APPLICATION_ID'] = applicationId;
    // APP_NAME 来自 .env
    if (envVars['APP_NAME'] !== undefined) {
      envMap['APP_NAME'] = envVars['APP_NAME'];
    }
    envMap['BUILD_TYPE'] = debug ? 'debug' : 'release';
    // FABRIC_ID 来自 .env
    if (envVars['FABRIC_ID'] !== undefined) {
      envMap['FABRIC_ID'] = envVars['FABRIC_ID'];
    }
    envMap['VERSION_CODE'] = versionCode;
    envMap['DEBUG'] = debug;
    // PRODUCT 来自构建系统自动注入（dotenv.ts 写入 rawfile/env）
    // 等价于 Android BuildConfig.FLAVOR，鸿蒙用 PRODUCT 命名（对应 build-profile.json5 的 products）
    if (envVars['PRODUCT'] !== undefined) {
      envMap['PRODUCT'] = envVars['PRODUCT'];
    }

    // 追加 .env 中除已处理字段外的其他变量
    let handledKeys: string[] = ['APP_NAME', 'FABRIC_ID', 'PRODUCT'];
    for (let key of Object.keys(envVars)) {
      if (!handledKeys.includes(key)) {
        envMap[key] = envVars[key];
      }
    }

    // ---- 5. 返回给 Dart ----
    result.success(envMap);

    // ---- 6. 缓存供原生侧静态方法使用 ----
    FlutterConfigPlugin.cachedEnv = {};
    let keys: string[] = Object.keys(envMap);
    for (let i = 0; i < keys.length; i++) {
      FlutterConfigPlugin.cachedEnv[keys[i]] = String(envMap[keys[i]]);
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
