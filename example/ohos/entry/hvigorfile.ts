/**
 * Hvigor 构建脚本：编译时读取 .env 文件并写入 rawfile/env
 *
 * 功能：
 * 从项目根目录读取 .env 文件，解析 KEY=VALUE 并写入 rawfile/env
 * 开发者无需手动在 rawfile 下放置 env 文件
 *
 * env 文件选择优先级（与 Android dotenv.gradle 一致）：
 * 1. ENVFILE 环境变量
 * 2. 默认 .env
 */

import { hapTasks } from '@ohos/hvigor-ohos-plugin';

function generateEnvFile(): void {
  let fs: any;
  let path: any;
  try {
    fs = require('fs');
    path = require('path');
  } catch (e) {
    console.warn('[flutter_config] Cannot load fs/path modules, skipping env generation');
    return;
  }

  // 1. 确定 Flutter 项目根目录（.env 文件所在目录）
  // __dirname 在 Hvigor 运行时指向 entry/ 目录
  // entry/ → ohos/ → example/ (Flutter 项目根目录，.env 在这里)
  const flutterProjectRoot = path.resolve(__dirname, '../..');

  // 2. 选择 .env 文件（与 Android dotenv.gradle 优先级一致）
  let envFile = '.env.dev'; // 默认
  if (process.env.ENVFILE) {
    envFile = process.env.ENVFILE;
  }

  // 3. 读取 env 文件
  let envPath = path.join(flutterProjectRoot, envFile);
  let content = '';

  if (fs.existsSync(envPath)) {
    content = fs.readFileSync(envPath, 'utf-8');
    console.log(`[flutter_config] Reading env from: ${envPath}`);
  } else if (fs.existsSync(envFile)) {
    content = fs.readFileSync(envFile, 'utf-8');
    console.log(`[flutter_config] Reading env from: ${envFile}`);
  } else {
    console.warn('[flutter_config] .env file not found at ' + envPath);
  }

  // 4. 解析 KEY=VALUE（与 FlutterConfigPlugin.ets 和 dotenv.gradle 保持一致的正则）
  const pattern = /^\s*(?:export\s+|)([\w\d.\-_]+)\s*=\s*['"]?(.*?)?['"]?\s*$/;
  const lines = content.split('\n');
  const envVars: Record<string, string> = {};

  for (const line of lines) {
    const match = line.match(pattern);
    if (match && match.length >= 3) {
      envVars[match[1]] = match[2].replace(/"/g, '\\"');
    }
  }

  // 5. 追加构建配置字段（等价于 Android BuildConfig 的系统字段）
  //    PRODUCT_NAME 等价于 Android BuildConfig.FLAVOR
  //    BUILD_TYPE 等价于 Android BuildConfig.BUILD_TYPE
  try {
    const buildProfilePath = path.join(__dirname, 'build-profile.json5');
    if (fs.existsSync(buildProfilePath)) {
      const buildProfileContent = fs.readFileSync(buildProfilePath, 'utf-8');
      // 从 build-profile.json5 中提取 target 名称
      const targetMatch = buildProfileContent.match(/"name"\s*:\s*"([^"]+)"/);
      if (targetMatch && !envVars['PRODUCT_NAME']) {
        envVars['PRODUCT_NAME'] = targetMatch[1];
      }
    }
  } catch (e) {
    // 解析 build-profile 失败时跳过
  }

  // 6. 写入 rawfile/env（供 FlutterConfigPlugin.ets 运行时读取）
  const rawfileDir = path.join(__dirname, 'src/main/resources/rawfile');
  try {
    if (!fs.existsSync(rawfileDir)) {
      fs.mkdirSync(rawfileDir, { recursive: true });
    }
    let envContent = '';
    for (const key of Object.keys(envVars)) {
      envContent += `${key}=${envVars[key]}\n`;
    }
    fs.writeFileSync(path.join(rawfileDir, 'env'), envContent, 'utf-8');
    console.log(`[flutter_config] Wrote ${Object.keys(envVars).length} variables to rawfile/env`);
  } catch (e) {
    console.warn('[flutter_config] Failed to write rawfile/env:', e);
  }
}

export default {
  system: hapTasks,
  plugins: [{
    pluginId: 'flutter_config_env',
    apply: () => {
      try {
        generateEnvFile();
      } catch (e) {
        console.warn('[flutter_config] Failed to generate env file:', e);
      }
    }
  }]
}
