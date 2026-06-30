> 文档模板：v0.4.1，[文档规范](./文档规范.md)(删除)
# flutter_config

本项目基于 [flutter_config](https://github.com/ByneappLLC/flutter_config) 开发。

## 简介
flutter_config 是一个环境变量管理插件，它将环境变量暴露给 Flutter 的 Dart 代码以及 iOS、Android 和 OpenHarmony 的原生代码，帮助开发者为 Flutter 应用引入 12-Factor App 的环境配置实践。<br/>

## 下载安装

进入到工程目录并在 pubspec.yaml 中添加以下依赖：

```yaml
dependencies:
  flutter_config:
    git: 
      url: https://gitcode.com/CPF-Flutter/fluttertpc_flutter_config.git
      ref: br_3.35_dev
```

执行命令

```bash
flutter pub get
```

> TAG 命名规则：`原库版本-ohos-版本号-betax`，不同 TAG 之间的变更详见 CHANGELOG.OpenHarmony.md。

| Flutter 框架版本 | TAG 名称                | 分支名 |
| ---------------- | ----------------------- | ---- |
| 3.7             | 2.0.2-ohos-1.0.0 | br_3.35_dev |
| 3.22             | 2.0.2-ohos-1.0.0 | br_3.35_dev |
| 3.27             | 2.0.2-ohos-1.0.0 | br_3.35_dev |
| 3.35             | 2.0.2-ohos-1.0.0 | br_3.35_dev |

## 约束与限制

### 兼容性

在下述版本验证通过：

1. Flutter: 3.7.12-ohos-1.0.6，DevEco Studio: 5.1.1.830，SDK: 5.0.0(12)，ROM: 6.1.0.117 SP37；
2. Flutter: 3.22.1-ohos-1.0.3; DevEco Studio: 5.1.1.830， SDK: 5.0.0(12); ROM: 6.1.0.117 SP37;
3. Flutter: oh-3.27.4-dev; DevEco Studio: 5.1.0.828， SDK: 5.0.0(12); ROM: 6.1.0.117 SP37;
4. Flutter: 3.35.8-ohos-0.0.1; DevEco Studio: 5.1.1.830， SDK: 5.0.0(12); ROM: 6.1.0.117 SP37;

### 权限要求

无

## 使用示例

flutter_config 提供了简洁的 API 来加载和读取环境变量，以下片段展示了最基本的使用方式：<br/>

```dart
import 'package:flutter/material.dart';
import 'package:flutter_config/flutter_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // 确保 Flutter 绑定初始化
  await FlutterConfig.loadEnvVariables(); // 加载环境变量

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter Config Example'),
        ),
        body: Center(
          child: Text('FABRIC_ID: ${FlutterConfig.get('FABRIC_ID')}'), // 读取指定环境变量
        ),
      ),
    );
  }
}
```

## 使用说明

### 1. 创建 .env 文件

在 Flutter 项目根目录下创建 `.env` 文件，定义环境变量：

```
APP_NAME=My App
API_URL=https://myapi.com
FABRIC_ID=abcdefgh
```

> **注意**：不要在 `.env` 文件中存储敏感密钥，移动应用中的密钥本质上无法防止逆向工程。

### 2. 加载环境变量

在 `main.dart` 中调用 `loadEnvVariables()` 加载所有环境变量：

```dart
import 'package:flutter_config/flutter_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterConfig.loadEnvVariables();
  runApp(MyApp());
}
```

### 3. 读取环境变量

使用 `get()` 方法读取指定变量，或使用 `variables` 获取所有已加载的变量：

```dart
// 读取单个变量
String? fabricId = FlutterConfig.get('FABRIC_ID');

// 遍历所有变量
FlutterConfig.variables.forEach((key, value) {
  print('$key: $value');
});
```

### 4. 多环境配置

支持通过不同的 `.env` 文件管理多环境配置，例如 `.env.dev`、`.env.staging`、`.env`（生产环境）。

#### 4.1 指定环境文件

**方式一：使用 `envFile` 参数**

在 `entry/hvigorfile.ts` 中使用 `createDotenvPlugin` 指定环境文件：

```typescript
import { hapTasks } from '@ohos/hvigor-ohos-plugin';
const { createDotenvPlugin } = require('./oh_modules/flutter_config/dotenv');

export default {
  system: hapTasks,
  plugins: [createDotenvPlugin({ entryDir: __dirname, envFile: '.env.dev' })]
}
```

**方式二：使用 `ENVFILE` 环境变量**

```bash
ENVFILE=.env.dev flutter build hap
```

**方式三：使用 `envConfigFiles` 自动匹配（推荐）**

通过 `envConfigFiles` 配置不同构建目标对应的环境文件：

```typescript
createDotenvPlugin({
  entryDir: __dirname,
  envConfigFiles: {
    develop: '.env.dev',
    staging: '.env.staging',
    production: '.env',
  }
})
```

> 优先级：`ENVFILE` 环境变量 > `envConfigFiles` 自动匹配 > `envFile` 参数 > 默认 `.env`

#### 4.2 多构建目标（--flavor）配置

鸿蒙端支持 `flutter build hap --flavor <名称>` 切换不同的构建目标，配合 `envConfigFiles` 实现多环境自动匹配。

**构建命令：**

```bash
# 生产环境（默认）
flutter build hap

# 开发环境
flutter build hap --flavor develop

# 预发布环境
flutter build hap --flavor staging
```

**配置步骤（以添加 `develop` 构建目标为例）：**

**步骤 1**：准备 `.env` 文件

在 Flutter 项目根目录下创建对应环境的文件：`.env`（生产）、`.env.dev`（开发）、`.env.staging`（预发布）。

**步骤 2**：修改 app 级 `build-profile.json5`（`ohos/build-profile.json5`）

在 `app.products` 中添加 `develop` product，在 `modules` 中为 entry 添加对应 target：

```json5
{
  "app": {
    "products": [
      { "name": "default", "signingConfig": "default", "compatibleSdkVersion": "5.0.0(12)", "runtimeOS": "HarmonyOS" },
      { "name": "develop", "signingConfig": "default", "compatibleSdkVersion": "5.0.0(12)", "runtimeOS": "HarmonyOS" }
    ]
  },
  "modules": [
    {
      "name": "entry",
      "srcPath": "./entry",
      "targets": [
        { "name": "default", "applyToProducts": ["default"] },
        { "name": "develop", "applyToProducts": ["develop"] }
      ]
    },
    {
      "name": "flutter_config",
      "srcPath": "../../ohos",
      "targets": [
        { "name": "default", "applyToProducts": ["default", "develop"] }
      ]
    }
  ]
}
```

> **要点**：entry 模块需要为每个 product 创建同名 target，这样 Flutter 工具才能找到正确路径的 HAP 文件；HAR 插件模块只需 `default` target，通过 `applyToProducts` 合并所有 product。

**步骤 3**：修改 entry 级 `build-profile.json5`（`ohos/entry/build-profile.json5`）

在 `targets` 中添加 `develop` target：

```json5
{
  "apiType": 'stageMode',
  "buildOption": {},
  "targets": [
    { "name": "default", "runtimeOS": "HarmonyOS" },
    { "name": "develop", "runtimeOS": "HarmonyOS" },
    { "name": "ohosTest" }
  ]
}
```

**步骤 4**：配置 `entry/hvigorfile.ts`

使用 `envConfigFiles` 实现 `--flavor` 自动匹配：

```typescript
import { hapTasks } from '@ohos/hvigor-ohos-plugin';
const { createDotenvPlugin } = require('./oh_modules/flutter_config/dotenv');

export default {
  system: hapTasks,
  plugins: [createDotenvPlugin({
    entryDir: __dirname,
    envConfigFiles: {
      develop: '.env.dev',
      staging: '.env.staging',
      production: '.env',
    }
  })]
}
```

**构建产物路径：**

| 命令 | HAP 输出路径 |
|---|---|
| `flutter build hap` | `ohos/entry/build/default/outputs/default/entry-default-signed.hap` |
| `flutter build hap --flavor develop` | `ohos/entry/build/develop/outputs/develop/entry-develop-signed.hap` |

**PRODUCT 字段：** `--flavor` 传入的名称会自动注入为 `PRODUCT` 环境变量（等同于 Android 的 `BuildConfig.FLAVOR`），无需在 `.env` 中手动定义。Dart 端可通过 `FlutterConfig.get('PRODUCT')` 获取。

### 5. 系统内置变量

鸿蒙端会自动注入以下系统字段（与 Android `BuildConfig` 行为一致），无需在 `.env` 中手动定义：

| 变量名 | 说明 |
|--------|------|
| VERSION_NAME | 应用版本名称 |
| APPLICATION_ID | 应用包名 |
| VERSION_CODE | 应用版本号 |
| DEBUG | 是否为调试模式（bool） |
| BUILD_TYPE | 构建类型（`'debug'` 或 `'release'`） |
| PRODUCT | 构建产品名称（等同于 Android 的 `BuildConfig.FLAVOR`，从 `build-profile.json5` 的 products 读取） |

> 即使没有 `.env` 文件，系统内置变量仍会正常返回，与 Android 无 `.env` 时 `BuildConfig` 仍可用的行为一致。

### 6. 鸿蒙原生代码调用

在鸿蒙原生（ArkTS）代码中，可通过静态方法读取环境变量：

```typescript
// 获取所有环境变量
let allEnv: Record<string, string> = FlutterConfigPlugin.env();

// 获取指定环境变量
let fabricId: string | undefined = FlutterConfigPlugin.envFor('FABRIC_ID');
```

> **注意**：原生静态方法必须在 `loadEnvVariables` 被调用后才有数据。

### 7. 单元测试

在测试中使用 `loadValueForTesting` 注入模拟环境变量，无需依赖 MethodChannel：

```dart
import 'package:flutter_config/flutter_config.dart';

void main() {
  FlutterConfig.loadValueForTesting({'BASE_URL': 'https://www.mockurl.com'});

  test('mock http client test', () {
    final String baseUrl = FlutterConfig.get('BASE_URL');
    expect(baseUrl, 'https://www.mockurl.com');
  });
}
```

## 接口说明

### API

> [!TIP] "ohos Support"列为 yes 表示 ohos 平台支持该属性，no 则表示不支持。使用方法跨平台一致，效果对标 iOS 或 Android 的效果。

#### FlutterConfig

| 名称 | 描述 | 类型 | 参数类型 | 返回值 | 必填 | OHOS 平台支持 |
|------|------|------|----------|--------|------|--------------|
| loadEnvVariables() | 加载环境变量，需在应用启动时调用 | 方法 | / | Future\<void\> | 是 | yes |
| get() | 根据键名获取环境变量值 | 方法 | String key | dynamic | 是 | yes |
| variables | 获取所有已加载的环境变量 | 属性 | / | Map\<String, dynamic\> | / | yes |

### 以下接口仅用于测试

| loadValueForTesting() | 注入模拟环境变量，仅用于test | 方法 | Map\<String, dynamic\> values | void | 是 | yes |

#### DotenvPluginOptions（鸿蒙构建配置）

| 名称 | 描述 | 参数类型 | 必填 | OHOS 平台支持 |
|------|------|----------|------|--------------|
| entryDir | entry 模块目录，传入 `__dirname` | string | 否 | yes |
| envFile | 指定环境文件路径 | string | 否 | yes |
| envConfigFiles | 构建目标与环境文件的映射 | Record\<string, string\> | 否 | yes |

#### FlutterConfigPlugin（鸿蒙原生 API）

| 名称 | 描述 | 类型 | 参数类型 | 返回值 | OHOS 平台支持 |
|------|------|------|----------|--------|--------------|
| env() | 获取所有环境变量 | 方法 | / | Record\<string, string\> | yes |
| envFor() | 根据键名获取环境变量 | 方法 | string key | string \| undefined | yes |

## 遗留问题
无

## 其他
无

## 目录结构

```
|---- flutter_config
|     |---- android   # android 适配代码
|     |---- doc       # Android 和 iOS 配置指南
|     |---- example   # 多平台的完整示例应用
|           |----lib  # 示例代码
|           |----ohos # 鸿蒙工程
|     |---- ios       # ios 适配代码
|     |---- lib       # 核心代码实现
|           |----flutter_config.dart  # 库的主入口文件
|     |---- ohos      # 鸿蒙适配代码
|           |----dotenv.ts                                    # 构建脚本，读取 .env 写入 rawfile/env
|           |----src/main/ets/components/plugin/
|                 |----FlutterConfigPlugin.ets                # 鸿蒙原生插件实现
|     |---- test      # 单元测试文件
|     |---- CHANGELOG.md              # 更新日志
|     |---- LICENSE                   # 开源协议
|     |---- README.md                 # 英文说明文档
|     |---- pubspec.yaml              # 配置文件
```

## 贡献代码

使用过程中发现任何问题都可以提 [Issue](https://gitcode.com/CPF-Flutter/fluttertpc_flutter_config/issues) ，当然，也非常欢迎发 [PR](https://gitcode.com/CPF-Flutter/fluttertpc_flutter_config/pulls) 共建。

## 开源协议

本项目基于 [BSD 2-Clause](https://github.com/ByneappLLC/flutter_config/blob/master/LICENSE) ，请自由地享受和参与开源。
