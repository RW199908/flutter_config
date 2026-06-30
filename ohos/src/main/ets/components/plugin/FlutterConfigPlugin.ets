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
import resourceManager from '@ohos.resourceManager';

const TAG: string = "FlutterConfig";

/** 解析 KEY=VALUE 的正则（与 Android dotenv.gradle 保持一致） */
const ENV_PATTERN: RegExp = /^\s*(?:export\s+|)([\w\d.\-_]+)\s*=\s*['"]?(.*?)?['"]?\s*$/;

/** 已在构建返回 Map 中按固定顺序处理的 key */
const HANDLED_KEYS: string[] = ['APP_NAME', 'FABRIC_ID', 'PRODUCT'];

/** 系统字段接口（ArkTS 要求对象字面量对应显式声明的类或接口） */
interface SystemFields {
  versionName: string;
  applicationId: string;
  versionCode: number;
  debug: boolean;
}

export default class FlutterConfigPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private binding: FlutterPluginBinding | null = null;
  private static cachedEnv: Record<string, string> = {};

  constructor() {
  }

  /**
   * 返回插件在 Flutter 引擎中注册时使用的唯一类名
   *
   * @returns 插件唯一类名字符串
   */
  getUniqueClassName(): string {
    return "FlutterConfigPlugin";
  }

  /**
   * 插件被附加到 Flutter 引擎时回调，创建并注册 MethodChannel
   *
   * @param binding - Flutter 插件绑定信息
   */
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    try {
      this.channel = new MethodChannel(binding.getBinaryMessenger(), "flutter_config");
      this.channel.setMethodCallHandler(this);
      this.binding = binding;
    } catch (e) {
      console.error(`[${TAG}] onAttachedToEngine failed: ${e}`);
    }
  }

  /**
   * 插件从 Flutter 引擎分离时回调，释放 MethodChannel 与缓存
   *
   * @param binding - Flutter 插件绑定信息
   */
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    try {
      if (this.channel !== null) {
        this.channel.setMethodCallHandler(null);
        this.channel = null;
      }
      this.binding = null;
      FlutterConfigPlugin.cachedEnv = {};
    } catch (e) {
      console.error(`[${TAG}] onDetachedFromEngine failed: ${e}`);
    }
  }

  /**
   * 处理来自 Dart 层的 MethodChannel 调用
   *
   * @param call - 方法调用信息，包含方法名与参数
   * @param result - 方法调用结果回调
   */
  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      if (call.method === "loadEnvVariables") {
        this.loadEnvVariables(result);
      } else {
        result.notImplemented();
      }
    } catch (e) {
      console.error(`[${TAG}] onMethodCall error for '${call.method}': ${e}`);
      result.error("FLUTTER_CONFIG_ERROR", `Method call error: ${e}`, null);
    }
  }

  /**
   * 从 rawfile 读取 env 文件并返回解析后的变量 Map
   * 读取失败时返回 null
   *
   * @returns 解析后的环境变量 Map，读取失败时返回 null
   */
  private readRawFileEnv(): Record<string, Object> | null {
    if (this.binding === null) {
      return null;
    }
    try {
      let resMgr: resourceManager.ResourceManager = this.binding.getApplicationContext().resourceManager;
      let envBytes: Uint8Array = resMgr.getRawFileContentSync('env');

      // Uint8Array → UTF-8 string
      let textDecoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      let text: string = textDecoder.decodeToString(envBytes);

      // Strip UTF-8 BOM if present (EF BB BF → U+FEFF)
      if (text.charCodeAt(0) === 0xFEFF) {
        text = text.substring(1);
      }

      return this.parseEnvText(text);
    } catch (e) {
      console.warn(`[${TAG}] Failed to read rawfile/env: ${e}`);
      return null;
    }
  }

  /**
   * 将 env 文本内容解析为 KEY=VALUE 的 Map
   *
   * @param text - env 文件文本内容
   * @returns 解析后的环境变量 Map
   */
  private parseEnvText(text: string): Record<string, Object> {
    let envVars: Record<string, Object> = {};
    let lines: string[] = text.split('\n');

    for (let line of lines) {
      let match: RegExpMatchArray | null = line.match(ENV_PATTERN);
      if (match && match.length >= 3) {
        envVars[match[1]] = match[2].replace(/"/g, '\\"');
      }
    }
    return envVars;
  }

  /**
   * 获取系统字段（versionName, applicationId, versionCode, debug）
   * 获取失败时返回默认值
   *
   * @returns 系统字段对象，获取失败时返回各字段默认值
   */
  private getSystemFields(): SystemFields {
    try {
      let bundleInfo: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);

      let fields: SystemFields = {
        versionName: bundleInfo.versionName,
        applicationId: bundleInfo.name,
        versionCode: bundleInfo.versionCode,
        debug: bundleInfo.appInfo.debug,
      };
      return fields;
    } catch (e) {
      console.warn(`[${TAG}] Failed to get bundle info: ${e}`);
      let defaults: SystemFields = { versionName: '', applicationId: '', versionCode: 0, debug: false };
      return defaults;
    }
  }

  /**
   * 按 Android BuildConfig 字段顺序构建返回 Map
   *
   * @param envVars - .env 中解析出的自定义变量
   * @param versionName - 版本名
   * @param applicationId - 应用包名
   * @param versionCode - 版本号
   * @param debug - 是否为 debug 构建
   * @returns 按固定顺序排列的环境变量 Map
   */
  private buildEnvMap(
    envVars: Record<string, Object>,
    versionName: string,
    applicationId: string,
    versionCode: number,
    debug: boolean,
  ): Record<string, Object> {
    let envMap: Record<string, Object> = {};

    envMap['VERSION_NAME'] = versionName;
    envMap['APPLICATION_ID'] = applicationId;
    if (envVars['APP_NAME'] !== undefined) {
      envMap['APP_NAME'] = envVars['APP_NAME'];
    }
    envMap['BUILD_TYPE'] = debug ? 'debug' : 'release';
    if (envVars['FABRIC_ID'] !== undefined) {
      envMap['FABRIC_ID'] = envVars['FABRIC_ID'];
    }
    envMap['VERSION_CODE'] = versionCode;
    envMap['DEBUG'] = debug;
    if (envVars['PRODUCT'] !== undefined) {
      envMap['PRODUCT'] = envVars['PRODUCT'];
    }

    // 追加 .env 中除已处理字段外的其他变量
    for (let key of Object.keys(envVars)) {
      if (!HANDLED_KEYS.includes(key)) {
        envMap[key] = envVars[key];
      }
    }

    return envMap;
  }

  /**
   * 缓存 envMap 供原生侧静态方法使用
   *
   * @param envMap - 待缓存的返回 Map
   */
  private static cacheEnvMap(envMap: Record<string, Object>): void {
    FlutterConfigPlugin.cachedEnv = {};
    let keys: string[] = Object.keys(envMap);
    for (let i = 0; i < keys.length; i++) {
      FlutterConfigPlugin.cachedEnv[keys[i]] = String(envMap[keys[i]]);
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
   *
   * @param result - MethodChannel 调用结果回调
   */
  private loadEnvVariables(result: MethodResult): void {
    // 1. 从 rawfile 读取 env 变量
    let rawEnv: Record<string, Object> | null = this.readRawFileEnv();
    let envLoaded: boolean = rawEnv !== null;
    let envVars: Record<string, Object> = rawEnv ?? {};

    // 2. 获取系统字段
    let sys: SystemFields = this.getSystemFields();

    // 3. 仅当既无env变量又无系统字段时返回空Map
    let hasSystemFields: boolean = sys.versionName !== '' || sys.applicationId !== '';
    if (!envLoaded && !hasSystemFields) {
      result.success({});
      return;
    }

    // 4. 构建返回 Map
    let envMap: Record<string, Object> = this.buildEnvMap(envVars, sys.versionName, sys.applicationId, sys.versionCode, sys.debug);

    // 5. 返回给 Dart
    result.success(envMap);

    // 6. 缓存供原生侧静态方法使用
    FlutterConfigPlugin.cacheEnvMap(envMap);
  }

  /**
   * 供鸿蒙原生代码调用的静态方法
   * 类似 iOS 的 FlutterConfigPlugin.env / envFor:
   * 注意：必须在 loadEnvVariables 被调用后才有数据
   *
   * @returns 包含所有环境变量的 Map，未加载时返回空对象
   */
  static env(): Record<string, string> {
    try {
      return FlutterConfigPlugin.cachedEnv;
    } catch (e) {
      console.error(`[${TAG}] env() failed: ${e}`);
      return {};
    }
  }

  /**
   * 根据 key 获取特定环境变量值
   * 注意：必须在 loadEnvVariables 被调用后才有数据
   *
   * @param key - 环境变量的键名
   * @returns 对应的值，key 不存在或未加载时返回 undefined
   */
  static envFor(key: string): string | undefined {
    try {
      return FlutterConfigPlugin.cachedEnv[key];
    } catch (e) {
      console.error(`[${TAG}] envFor('${key}') failed: ${e}`);
      return undefined;
    }
  }
}
