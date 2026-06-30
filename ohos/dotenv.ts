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

interface FsPathModules {
  fs: ESObject;
  path: ESObject;
}

/** 解析 KEY=VALUE 的正则（与 Android dotenv.gradle 保持一致） */
const ENV_PATTERN: RegExp = /^\s*(?:export\s+|)([\w\d.\-_]+)\s*=\s*['"]?(.*?)?['"]?\s*$/;

/** 已按固定顺序处理的 key（不重复写入 env 文件） */
const HANDLED_KEYS: string[] = ['APP_NAME', 'FABRIC_ID', 'PRODUCT'];

/**
 * 加载 fs 和 path 模块
 * 加载失败时返回 null
 */
function loadFsPathModules(): FsPathModules | null {
  try {
    return {
      fs: require('fs'),
      path: require('path'),
    };
  } catch (e) {
    console.warn('[flutter_config] Cannot load fs/path modules, skipping env generation');
    return null;
  }
}

/**
 * 确定 entry 目录和 Flutter 项目根目录
 */
function resolveProjectDirs(options: DotenvPluginOptions | undefined, pathModule: ESObject): { entryDir: string; projectRoot: string } {
  const entryDir = options?.entryDir || __dirname;
  const projectRoot = pathModule.resolve(entryDir, '../..');
  return { entryDir, projectRoot };
}

/**
 * 根据当前 FLAVOR 或 build-profile.json5 中的 target 名称匹配 envConfigFiles
 * 优先使用 hvigor 传入的 FLAVOR 参数匹配，回退到 build-profile 解析
 * 匹配失败时返回 null
 */
function matchEnvConfigFile(entryDir: string, envConfigFiles: Record<string, string>, fsModule: ESObject, pathModule: ESObject): string | null {
  // 优先从 hvigor 命令行获取 FLAVOR
  const flavor = getCurrentFlavor();
  if (flavor) {
    const flavorLower = flavor.toLowerCase();
    for (const [key, value] of Object.entries(envConfigFiles)) {
      if (flavorLower.startsWith(key.toLowerCase()) || key.toLowerCase().startsWith(flavorLower)) {
        return value;
      }
    }
  }

  // 回退：从 build-profile.json5 解析 target name
  try {
    const buildProfilePath = pathModule.join(entryDir, 'build-profile.json5');
    if (!fsModule.existsSync(buildProfilePath)) {
      return null;
    }
    const content = fsModule.readFileSync(buildProfilePath, 'utf-8');
    const targetMatch = content.match(/"name"\s*:\s*"([^"]+)"/);
    if (!targetMatch) {
      return null;
    }
    const targetName = targetMatch[1].toLowerCase();
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
 */
function selectEnvFile(options: DotenvPluginOptions | undefined, entryDir: string, fsModule: ESObject, pathModule: ESObject): string {
  if (process.env.ENVFILE) {
    return process.env.ENVFILE;
  }
  if (options?.envConfigFiles) {
    const matched = matchEnvConfigFile(entryDir, options.envConfigFiles, fsModule, pathModule);
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
 */
function readEnvContent(envFile: string, projectRoot: string, fsModule: ESObject, pathModule: ESObject): string {
  const envPath = pathModule.join(projectRoot, envFile);

  try {
    if (fsModule.existsSync(envPath)) {
      const content = fsModule.readFileSync(envPath, 'utf-8');
      console.log(`[flutter_config] Reading env from: ${envPath}`);
      return content;
    }
    if (fsModule.existsSync(envFile)) {
      const content = fsModule.readFileSync(envFile, 'utf-8');
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
 */
function parseEnvContent(content: string): Record<string, string> {
  const envVars: Record<string, string> = {};
  const lines = content.split('\n');

  try {
    for (const line of lines) {
      const match = line.match(ENV_PATTERN);
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
 */
function getCurrentFlavor(): string {
  try {
    const args = process.argv || [];
    for (let i = 0; i < args.length; i++) {
      const arg = args[i];
      // 格式1: FLAVOR=develop (作为 -p 的值传递)
      const flavorMatch = arg.match(/^FLAVOR=(.+)$/);
      if (flavorMatch) {
        return flavorMatch[1];
      }
      // 格式2: module=xxx@develop 从 module 参数中提取 flavor
      const moduleMatch = arg.match(/^module=[^@]+@(\w+)/);
      if (moduleMatch && moduleMatch[1] !== 'default') {
        return moduleMatch[1];
      }
      // 格式3: product=develop (非 default 时)
      const productMatch = arg.match(/^product=(.+)$/);
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
 */
function readProductName(entryDir: string, fsModule: ESObject, pathModule: ESObject): string {
  // 优先从 hvigor 命令行获取当前 FLAVOR
  const flavor = getCurrentFlavor();
  if (flavor) {
    return flavor;
  }

  // 回退：从 build-profile.json5 读取第一个 product name
  try {
    const appBuildProfilePath = pathModule.join(entryDir, '../build-profile.json5');
    if (!fsModule.existsSync(appBuildProfilePath)) {
      return '';
    }
    const profileContent = fsModule.readFileSync(appBuildProfilePath, 'utf-8');
    const productsMatch = profileContent.match(/"products"\s*:\s*\[([\s\S]*?)\]/);
    if (productsMatch) {
      const nameMatch = productsMatch[1].match(/"name"\s*:\s*"([^"]+)"/);
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
 */
function writeRawfileEnv(entryDir: string, envVars: Record<string, string>, fsModule: ESObject, pathModule: ESObject): void {
  const rawfileDir = pathModule.join(entryDir, 'src/main/resources/rawfile');

  try {
    if (!fsModule.existsSync(rawfileDir)) {
      fsModule.mkdirSync(rawfileDir, { recursive: true });
    }

    let envContent = '';
    for (const key of Object.keys(envVars)) {
      envContent += `${key}=${envVars[key]}\n`;
    }

    const product = readProductName(entryDir, fsModule, pathModule);
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

function createDotenvPlugin(options?: DotenvPluginOptions) {
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
