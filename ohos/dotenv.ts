/**
 * flutter_config 鸿蒙端构建脚本
 *
 * 功能：编译时读取 .env 文件并写入 rawfile/env
 * 开发者无需手动在 rawfile 下放置 env 文件
 *
 * 使用方式（在 entry/hvigorfile.ts 中添加）：
 *
 *   import { hapTasks } from '@ohos/hvigor-ohos-plugin';
 *   const { createDotenvPlugin } = require('./oh_modules/flutter_config/dotenv');
 *
 *   export default {
 *     system: hapTasks,
 *     plugins: [createDotenvPlugin({ entryDir: __dirname })]
 *   }
 *
 * 配置（可选，支持多环境）：
 *   createDotenvPlugin({
 *     entryDir: __dirname,
 *     envFile: '.env.production',
 *     envConfigFiles: {
 *       develop: '.env.dev',
 *       staging: '.env.staging',
 *       production: '.env',
 *     }
 *   })
 */

interface DotenvPluginOptions {
  entryDir?: string;                           // entry 模块目录（由调用者传入 __dirname）
  envFile?: string;                            // 指定env文件路径
  envConfigFiles?: Record<string, string>;     // 构建target → env文件映射（类似安卓envConfigFiles）
}

/** Node.js fs 模块子集（仅声明本脚本用到的同步方法，替代 ESObject） */
interface FsModule {
  existsSync(path: string): boolean;
  readFileSync(path: string, encoding: string): string;
  writeFileSync(path: string, data: string, encoding: string): void;
  mkdirSync(path: string, options?: { recursive: boolean }): void;
}

/** Node.js path 模块子集（仅声明本脚本用到的方法，替代 ESObject） */
interface PathModule {
  join(...paths: string[]): string;
  resolve(...paths: string[]): string;
}

interface FsPathModules {
  fs: FsModule;
  path: PathModule;
}

/** createDotenvPlugin 返回的 hvigor 插件对象 */
interface DotenvPlugin {
  pluginId: string;
  apply: () => void;
}

/** 解析 KEY=VALUE 的正则（与 Android dotenv.gradle 保持一致） */
const ENV_PATTERN: RegExp = /^\s*(?:export\s+|)([\w\d.\-_]+)\s*=\s*['"]?(.*?)?['"]?\s*$/;

/** 已按固定顺序处理的 key（不重复写入 env 文件） */
const HANDLED_KEYS: string[] = ['APP_NAME', 'FABRIC_ID', 'PRODUCT'];

/**
 * 加载 fs 和 path 模块
 * 加载失败时返回 null
 *
 * @returns 包含 fs 与 path 模块的 FsPathModules，加载失败时返回 null
 */
function loadFsPathModules(): FsPathModules | null {
  try {
    return {
      fs: require('fs') as FsModule,
      path: require('path') as PathModule,
    };
  } catch (e) {
    console.warn('[flutter_config] Cannot load fs/path modules, skipping env generation');
    return null;
  }
}

/**
 * 确定 entry 目录和 Flutter 项目根目录
 *
 * @param options - 插件配置选项（含 entryDir）
 * @param pathModule - Node.js path 模块
 * @returns entryDir 与 projectRoot 组成的对象
 */
function resolveProjectDirs(options: DotenvPluginOptions | undefined, pathModule: PathModule): { entryDir: string; projectRoot: string } {
  const entryDir: string = options?.entryDir || __dirname;
  const projectRoot: string = pathModule.resolve(entryDir, '../..');
  return { entryDir, projectRoot };
}

/**
 * 根据当前 FLAVOR 或 build-profile.json5 中的 target 名称匹配 envConfigFiles
 * 优先使用 hvigor 传入的 FLAVOR 参数匹配，回退到 build-profile 解析
 * 匹配失败时返回 null
 *
 * @param entryDir - entry 模块目录
 * @param envConfigFiles - 构建target → env文件映射
 * @param fsModule - Node.js fs 模块
 * @param pathModule - Node.js path 模块
 * @returns 匹配到的 env 文件路径，未匹配时返回 null
 */
function matchEnvConfigFile(entryDir: string, envConfigFiles: Record<string, string>, fsModule: FsModule, pathModule: PathModule): string | null {

  // 回退：从 build-profile.json5 解析 target name
  try {
    // 优先从 hvigor 命令行获取 FLAVOR
    const flavor: string = getCurrentFlavor();
    if (flavor) {
      const flavorLower: string = flavor.toLowerCase();
      for (const [key, value] of Object.entries(envConfigFiles)) {
        if (flavorLower.startsWith(key.toLowerCase()) || key.toLowerCase().startsWith(flavorLower)) {
          return value;
        }
      }
    }

    const buildProfilePath: string = pathModule.join(entryDir, 'build-profile.json5');
    if (!fsModule.existsSync(buildProfilePath)) {
      return null;
    }
    const content: string = fsModule.readFileSync(buildProfilePath, 'utf-8');
    const targetMatch: RegExpMatchArray | null = content.match(/"name"\s*:\s*"([^"]+)"/);
    if (!targetMatch) {
      return null;
    }
    const targetName: string = targetMatch[1].toLowerCase();
    for (const [key, value] of Object.entries(envConfigFiles)) {
      if (targetName.startsWith(key.toLowerCase()) || key.toLowerCase().startsWith(targetName)) {
        return value;
      }
    }
  } catch (e) {
    // 解析 build-profile 失败时跳过
  }
  return null;
}

/**
 * 选择 .env 文件路径（优先级与 Android dotenv.gradle 一致）
 *
 * @param options - 插件配置选项
 * @param entryDir - entry 模块目录
 * @param fsModule - Node.js fs 模块
 * @param pathModule - Node.js path 模块
 * @returns 选中的 env 文件路径
 */
function selectEnvFile(options: DotenvPluginOptions | undefined, entryDir: string, fsModule: FsModule, pathModule: PathModule): string {
  if (process.env.ENVFILE) {
    return process.env.ENVFILE;
  }
  if (options?.envConfigFiles) {
    const matched: string | null = matchEnvConfigFile(entryDir, options.envConfigFiles, fsModule, pathModule);
    if (matched) {
      return matched;
    }
  }
  if (options?.envFile) {
    return options.envFile;
  }
  return '.env';
}

/**
 * 读取 env 文件内容
 * 读取失败时返回空字符串
 *
 * @param envFile - env 文件名/路径
 * @param projectRoot - Flutter 项目根目录
 * @param fsModule - Node.js fs 模块
 * @param pathModule - Node.js path 模块
 * @returns env 文件文本内容，读取失败时返回空字符串
 */
function readEnvContent(envFile: string, projectRoot: string, fsModule: FsModule, pathModule: PathModule): string {
  const envPath: string = pathModule.join(projectRoot, envFile);

  try {
    if (fsModule.existsSync(envPath)) {
      const content: string = fsModule.readFileSync(envPath, 'utf-8');
      console.log(`[flutter_config] Reading env from: ${envPath}`);
      return content;
    }
    if (fsModule.existsSync(envFile)) {
      const content: string = fsModule.readFileSync(envFile, 'utf-8');
      console.log(`[flutter_config] Reading env from: ${envFile}`);
      return content;
    }
  } catch (e) {
    console.warn('[flutter_config] Failed to read .env file: ' + e);
  }

  console.warn('[flutter_config] .env file not found at ' + envPath);
  return '';
}

/**
 * 解析 env 文本内容为 KEY=VALUE 的 Map
 *
 * @param content - env 文件文本内容
 * @returns 解析后的环境变量 Map
 */
function parseEnvContent(content: string): Record<string, string> {
  const envVars: Record<string, string> = {};
  const lines: string[] = content.split('\n');

  try {
    for (const line of lines) {
      const match: RegExpMatchArray | null = line.match(ENV_PATTERN);
      if (match && match.length >= 3) {
        envVars[match[1]] = match[2].replace(/"/g, '\\"');
      }
    }
  } catch (e) {
    console.warn('[flutter_config] Failed to parse .env content: ' + e);
  }

  return envVars;
}

/**
 * 从 hvigor 命令行参数中获取当前 FLAVOR/product 名称
 * flutter build hap --flavor develop 会传递 -p FLAVOR=develop
 * 读取失败时返回空字符串
 *
 * @returns 当前 FLAVOR/product 名称，未识别时返回空字符串
 */
function getCurrentFlavor(): string {
  try {
    const args: string[] = process.argv || [];
    for (let i = 0; i < args.length; i++) {
      const arg: string = args[i];
      // 格式1: FLAVOR=develop (作为 -p 的值传递)
      const flavorMatch: RegExpMatchArray | null = arg.match(/^FLAVOR=(.+)$/);
      if (flavorMatch) {
        return flavorMatch[1];
      }
      // 格式2: module=xxx@develop 从 module 参数中提取 flavor
      const moduleMatch: RegExpMatchArray | null = arg.match(/^module=[^@]+@(\w+)/);
      if (moduleMatch && moduleMatch[1] !== 'default') {
        return moduleMatch[1];
      }
      // 格式3: product=develop (非 default 时)
      const productMatch: RegExpMatchArray | null = arg.match(/^product=(.+)$/);
      if (productMatch && productMatch[1] !== 'default') {
        return productMatch[1];
      }
    }
    // 也检查环境变量
    if (process.env.FLAVOR) {
      return process.env.FLAVOR;
    }
  } catch (e) {
    // 解析失败时跳过
  }
  return '';
}

/**
 * 从 build-profile.json5 读取当前 product 名称
 * 优先使用 hvigor 传入的 FLAVOR 参数，回退到 build-profile 的第一个 product
 * 读取失败时返回空字符串
 *
 * @param entryDir - entry 模块目录
 * @param fsModule - Node.js fs 模块
 * @param pathModule - Node.js path 模块
 * @returns 当前 product 名称，未识别时返回空字符串
 */
function readProductName(entryDir: string, fsModule: FsModule, pathModule: PathModule): string {
  // 优先从 hvigor 命令行获取当前 FLAVOR
  const flavor: string = getCurrentFlavor();
  if (flavor) {
    return flavor;
  }

  // 回退：从 build-profile.json5 读取第一个 product name
  try {
    const appBuildProfilePath: string = pathModule.join(entryDir, '../build-profile.json5');
    if (!fsModule.existsSync(appBuildProfilePath)) {
      return '';
    }
    const profileContent: string = fsModule.readFileSync(appBuildProfilePath, 'utf-8');
    const productsMatch: RegExpMatchArray | null = profileContent.match(/"products"\s*:\s*\[([\s\S]*?)\]/);
    if (productsMatch) {
      const nameMatch: RegExpMatchArray | null = productsMatch[1].match(/"name"\s*:\s*"([^"]+)"/);
      if (nameMatch) {
        return nameMatch[1];
      }
    }
  } catch (e) {
    // 读取失败时跳过
  }
  return '';
}

/**
 * 将 env 变量写入 rawfile/env
 *
 * @param entryDir - entry 模块目录
 * @param envVars - 待写入的环境变量 Map
 * @param fsModule - Node.js fs 模块
 * @param pathModule - Node.js path 模块
 */
function writeRawfileEnv(entryDir: string, envVars: Record<string, string>, fsModule: FsModule, pathModule: PathModule): void {
  const rawfileDir: string = pathModule.join(entryDir, 'src/main/resources/rawfile');

  try {
    if (!fsModule.existsSync(rawfileDir)) {
      fsModule.mkdirSync(rawfileDir, { recursive: true });
    }

    let envContent: string = '';
    for (const key of Object.keys(envVars)) {
      envContent += `${key}=${envVars[key]}\n`;
    }

    const product: string = readProductName(entryDir, fsModule, pathModule);
    if (product) {
      envContent += `PRODUCT=${product}\n`;
    }

    fsModule.writeFileSync(pathModule.join(rawfileDir, 'env'), envContent, 'utf-8');
    console.log(`[flutter_config] Wrote ${Object.keys(envVars).length} variables to rawfile/env` +
      (product ? `, PRODUCT=${product}` : ''));
  } catch (e) {
    console.warn('[flutter_config] Failed to write rawfile/env:', e);
  }
}

/**
 * 创建 Hvigor dotenv 构建插件
 *
 * 插件在构建时读取 .env 文件，解析后写入 rawfile/env，
 * 供运行时 FlutterConfigPlugin 读取。
 *
 * @param options - 插件配置选项（可选）
 *   - entryDir: entry 模块目录
 *   - envFile: 指定 env 文件路径
 *   - envConfigFiles: 构建目标与 env 文件的映射
 * @returns DotenvPlugin 插件对象，包含 pluginId 和 apply 方法
 */
function createDotenvPlugin(options?: DotenvPluginOptions): DotenvPlugin {
  return {
    pluginId: 'flutter_config_dotenv',
    apply: () => {
      const modules = loadFsPathModules();
      if (!modules) {
        return;
      }

      const { entryDir, projectRoot } = resolveProjectDirs(options, modules.path);
      const envFile = selectEnvFile(options, entryDir, modules.fs, modules.path);
      const content = readEnvContent(envFile, projectRoot, modules.fs, modules.path);
      const envVars = parseEnvContent(content);
      writeRawfileEnv(entryDir, envVars, modules.fs, modules.path);
    }
  };
}

export { createDotenvPlugin };
