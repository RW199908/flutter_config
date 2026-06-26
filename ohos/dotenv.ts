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

function createDotenvPlugin(options?: DotenvPluginOptions) {
  return {
    pluginId: 'flutter_config_dotenv',
    apply: () => {
      let fs: any;
      let path: any;
      try {
        fs = require('fs');
        path = require('path');
      } catch (e) {
        console.warn('[flutter_config] Cannot load fs/path modules, skipping env generation');
        return;
      }

      // 1. 确定 entry 目录
      // 当 dotenv.ts 被 require() 加载时，其 __dirname 指向 oh_modules 中的模块路径，
      // 而非 entry/ 目录。因此需要调用者显式传入 entryDir（即 entry/hvigorfile.ts 的 __dirname）。
      const entryDir = options?.entryDir || __dirname;

      // Flutter 项目根目录（.env 文件所在目录）
      // entry/ → ohos/ → 项目根目录
      const flutterProjectRoot = path.resolve(entryDir, '../..');

      // 2. 选择 .env 文件（优先级与 Android dotenv.gradle 一致）
      let envFile = '.env';

      if (process.env.ENVFILE) {
        envFile = process.env.ENVFILE;
      } else if (options?.envConfigFiles) {
        try {
          const buildProfilePath = path.join(entryDir, 'build-profile.json5');
          if (fs.existsSync(buildProfilePath)) {
            const content = fs.readFileSync(buildProfilePath, 'utf-8');
            const targetMatch = content.match(/"name"\s*:\s*"([^"]+)"/);
            if (targetMatch) {
              const targetName = targetMatch[1].toLowerCase();
              for (const [key, value] of Object.entries(options.envConfigFiles)) {
                if (targetName.startsWith(key.toLowerCase()) || key.toLowerCase().startsWith(targetName)) {
                  envFile = value;
                  break;
                }
              }
            }
          }
        } catch (e) {
          // 解析 build-profile 失败时跳过
        }
      } else if (options?.envFile) {
        envFile = options.envFile;
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

      // 4. 解析 KEY=VALUE
      const pattern = /^\s*(?:export\s+|)([\w\d.\-_]+)\s*=\s*['"]?(.*?)?['"]?\s*$/;
      const lines = content.split('\n');
      const envVars: Record<string, string> = {};

      for (const line of lines) {
        const match = line.match(pattern);
        if (match && match.length >= 3) {
          envVars[match[1]] = match[2].replace(/"/g, '\\"');
        }
      }

      // 5. 写入 rawfile/env
      const rawfileDir = path.join(entryDir, 'src/main/resources/rawfile');
      try {
        if (!fs.existsSync(rawfileDir)) {
          fs.mkdirSync(rawfileDir, { recursive: true });
        }
        let envContent = '';
        for (const key of Object.keys(envVars)) {
          envContent += `${key}=${envVars[key]}\n`;
        }
        // 从 build-profile.json5 读取当前 product 名称，注入 PRODUCT 字段
        // 等价于 Android BuildConfig.FLAVOR
        let product = '';
        try {
          const appBuildProfilePath = path.join(entryDir, '../build-profile.json5');
          if (fs.existsSync(appBuildProfilePath)) {
            const profileContent = fs.readFileSync(appBuildProfilePath, 'utf-8');
            const productsMatch = profileContent.match(/"products"\s*:\s*\[([\s\S]*?)\]/);
            if (productsMatch) {
              const nameMatch = productsMatch[1].match(/"name"\s*:\s*"([^"]+)"/);
              if (nameMatch) {
                product = nameMatch[1];
              }
            }
          }
        } catch (e) {}
        if (product) {
          envContent += `PRODUCT=${product}\n`;
        }
        fs.writeFileSync(path.join(rawfileDir, 'env'), envContent, 'utf-8');
        console.log(`[flutter_config] Wrote ${Object.keys(envVars).length} variables to rawfile/env` +
          (product ? `, PRODUCT=${product}` : ''));
      } catch (e) {
        console.warn('[flutter_config] Failed to write rawfile/env:', e);
      }
    }
  };
}

export { createDotenvPlugin };
