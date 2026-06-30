> Document template: v0.4.1, [Documentation specification](./文档规范.md)(delete)
# flutter_config

This project is developed based on [flutter_config](https://github.com/ByneappLLC/flutter_config).

## Introduction
flutter_config is an environment variable management plugin that exposes environment variables to Flutter's Dart code as well as to native code on iOS, Android, and OpenHarmony, helping developers bring 12-Factor App environment configuration practices to Flutter applications.<br/>

## Download and Install

Navigate to the project directory and add the following dependency in pubspec.yaml:

```yaml
dependencies:
  flutter_config:
    git: 
      url: https://gitcode.com/CPF-Flutter/fluttertpc_flutter_config.git
      ref: br_3.35_dev
```

Run the command

```bash
flutter pub get
```

> TAG naming convention: `original-version-ohos-version-betax`, see CHANGELOG.OpenHarmony.md for changes between different TAGs.

| Flutter Framework Version | TAG Name                | Branch |
| ---------------- | ----------------------- | ---- |
| 3.7             | 2.0.2-ohos-1.0.0 | br_3.35_dev |
| 3.22             | 2.0.2-ohos-1.0.0 | br_3.35_dev |
| 3.27             | 2.0.2-ohos-1.0.0 | br_3.35_dev |
| 3.35             | 2.0.2-ohos-1.0.0 | br_3.35_dev |

## Constraints and Limitations

### Compatibility

Verified on the following versions:

1. Flutter: 3.7.12-ohos-1.0.6, DevEco Studio: 5.1.1.830, SDK: 5.0.0(12), ROM: 6.1.0.117 SP37;
2. Flutter: 3.22.1-ohos-1.0.3; DevEco Studio: 5.1.1.830, SDK: 5.0.0(12); ROM: 6.1.0.117 SP37;
3. Flutter: oh-3.27.4-dev; DevEco Studio: 5.1.0.828, SDK: 5.0.0(12); ROM: 6.1.0.117 SP37;
4. Flutter: 3.35.8-ohos-0.0.1; DevEco Studio: 5.1.1.830, SDK: 5.0.0(12); ROM: 6.1.0.117 SP37;

### Permission Requirements

None

## Usage Example

flutter_config provides a concise API to load and read environment variables. The following snippet demonstrates the most basic usage:<br/>

```dart
import 'package:flutter/material.dart';
import 'package:flutter_config/flutter_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure Flutter binding is initialized
  await FlutterConfig.loadEnvVariables(); // Load environment variables

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
          child: Text('FABRIC_ID: ${FlutterConfig.get('FABRIC_ID')}'), // Read a specific environment variable
        ),
      ),
    );
  }
}
```

## Usage Guide

### 1. Create .env File

Create a `.env` file in the root directory of your Flutter project to define environment variables:

```
APP_NAME=My App
API_URL=https://myapi.com
FABRIC_ID=abcdefgh
```

> **Note**: Do not store sensitive keys in the `.env` file. Secrets in mobile apps are inherently vulnerable to reverse engineering.

### 2. Load Environment Variables

Call `loadEnvVariables()` in `main.dart` to load all environment variables:

```dart
import 'package:flutter_config/flutter_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterConfig.loadEnvVariables();
  runApp(MyApp());
}
```

### 3. Read Environment Variables

Use the `get()` method to read a specific variable, or use `variables` to get all loaded variables:

```dart
// Read a single variable
String? fabricId = FlutterConfig.get('FABRIC_ID');

// Iterate over all variables
FlutterConfig.variables.forEach((key, value) {
  print('$key: $value');
});
```

### 4. Multi-Environment Configuration

Support managing multiple environments through different `.env` files, such as `.env.dev`, `.env.staging`, and `.env` (production).

#### 4.1 Specifying Environment Files

**Option 1: Use `envFile` parameter**

Use `createDotenvPlugin` in `entry/hvigorfile.ts` to specify the environment file:

```typescript
import { hapTasks } from '@ohos/hvigor-ohos-plugin';
const { createDotenvPlugin } = require('./oh_modules/flutter_config/dotenv');

export default {
  system: hapTasks,
  plugins: [createDotenvPlugin({ entryDir: __dirname, envFile: '.env.dev' })]
}
```

**Option 2: Use `ENVFILE` environment variable**

```bash
ENVFILE=.env.dev flutter build hap
```

**Option 3: Use `envConfigFiles` auto-matching (Recommended)**

Configure different environment files for different build targets via `envConfigFiles`:

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

> Priority: `ENVFILE` environment variable > `envConfigFiles` auto-matching > `envFile` parameter > default `.env`

#### 4.2 Multi-Build Target (--flavor) Configuration

The OpenHarmony side supports `flutter build hap --flavor <name>` to switch between different build targets, combined with `envConfigFiles` for automatic multi-environment matching.

**Build Commands:**

```bash
# Production (default)
flutter build hap

# Development
flutter build hap --flavor develop

# Staging
flutter build hap --flavor staging
```

**Configuration Steps (adding `develop` build target as an example):**

**Step 1:** Prepare `.env` files

Create corresponding environment files in the Flutter project root directory: `.env` (production), `.env.dev` (development), `.env.staging` (staging).

**Step 2:** Modify app-level `build-profile.json5` (`ohos/build-profile.json5`)

Add the `develop` product in `app.products`, and add the corresponding target for entry in `modules`:

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

> **Key Points**: The entry module needs a target with the same name as each product so that the Flutter tool can locate the HAP file at the correct path. HAR plugin modules only need the `default` target, using `applyToProducts` to cover all products.

**Step 3:** Modify entry-level `build-profile.json5` (`ohos/entry/build-profile.json5`)

Add the `develop` target in `targets`:

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

**Step 4:** Configure `entry/hvigorfile.ts`

Use `envConfigFiles` for automatic `--flavor` matching:

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

**Build Output Paths:**

| Command | HAP Output Path |
|---|---|
| `flutter build hap` | `ohos/entry/build/default/outputs/default/entry-default-signed.hap` |
| `flutter build hap --flavor develop` | `ohos/entry/build/develop/outputs/develop/entry-develop-signed.hap` |

**PRODUCT Field:** The `--flavor` name is automatically injected as the `PRODUCT` environment variable (equivalent to Android's `BuildConfig.FLAVOR`), no manual definition in `.env` is required. Access it in Dart via `FlutterConfig.get('PRODUCT')`.

### 5. Built-in System Variables

The OpenHarmony side automatically injects the following system fields (consistent with Android `BuildConfig` behavior), no manual definition in `.env` is required:

| Variable Name | Description |
|---------------|-------------|
| VERSION_NAME | Application version name |
| APPLICATION_ID | Application bundle name |
| VERSION_CODE | Application version code |
| DEBUG | Whether in debug mode (bool) |
| BUILD_TYPE | Build type (`'debug'` or `'release'`) |
| PRODUCT | Build product name (equivalent to Android `BuildConfig.FLAVOR`, read from `build-profile.json5` products) |

> Even without a `.env` file, built-in system variables are still returned normally, consistent with Android's behavior where `BuildConfig` is available without `.env`.

### 6. OpenHarmony Native Code Usage

In OpenHarmony native (ArkTS) code, environment variables can be read through static methods:

```typescript
// Get all environment variables
let allEnv: Record<string, string> = FlutterConfigPlugin.env();

// Get a specific environment variable
let fabricId: string | undefined = FlutterConfigPlugin.envFor('FABRIC_ID');
```

> **Note**: Native static methods only have data after `loadEnvVariables` has been called.

### 7. Unit Testing

Use `loadValueForTesting` in tests to inject mock environment variables without relying on the MethodChannel:

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

## Interface Description

### API

> [!TIP] "ohos Support" column with "yes" indicates the property is supported on the ohos platform, "no" indicates not supported. Usage is consistent across platforms, with results matching iOS or Android behavior.

#### FlutterConfig

| Name | Description | Type | Parameter Type | Return Value | Required | OHOS Support |
|------|-------------|------|----------------|--------------|----------|-------------|
| loadEnvVariables() | Load environment variables, must be called at app startup | Method | / | Future\<void\> | Yes | yes |
| get() | Get environment variable value by key | Method | String key | dynamic | Yes | yes |
| variables | Get all loaded environment variables | Property | / | Map\<String, dynamic\> | / | yes |

### The following interfaces are for testing only

| loadValueForTesting() | Inject mock environment variables for testing only | Method | Map\<String, dynamic\> values | void | Yes | yes |

#### DotenvPluginOptions (OpenHarmony Build Configuration)

| Name | Description | Parameter Type | Required | OHOS Support |
|------|-------------|----------------|----------|-------------|
| entryDir | Entry module directory, pass `__dirname` | string | No | yes |
| envFile | Specify environment file path | string | No | yes |
| envConfigFiles | Mapping of build targets to environment files | Record\<string, string\> | No | yes |

#### FlutterConfigPlugin (OpenHarmony Native API)

| Name | Description | Type | Parameter Type | Return Value | OHOS Support |
|------|-------------|------|----------------|--------------|-------------|
| env() | Get all environment variables | Method | / | Record\<string, string\> | yes |
| envFor() | Get environment variable by key | Method | string key | string \| undefined | yes |

## Known Issues
None

## Others
None

## Directory Structure

```
|---- flutter_config
|     |---- android   # Android adaptation code
|     |---- doc       # Android and iOS setup guides
|     |---- example   # Multi-platform example application
|           |----lib  # Example code
|           |----ohos # OpenHarmony project
|     |---- ios       # iOS adaptation code
|     |---- lib       # Core code implementation
|           |----flutter_config.dart  # Main entry file of the library
|     |---- ohos      # OpenHarmony adaptation code
|           |----dotenv.ts                                    # Build script, reads .env and writes rawfile/env
|           |----src/main/ets/components/plugin/
|                 |----FlutterConfigPlugin.ets                # OpenHarmony native plugin implementation
|     |---- test      # Unit test files
|     |---- CHANGELOG.md              # Change log
|     |---- LICENSE                   # Open source license
|     |---- README.md                 # English documentation
|     |---- pubspec.yaml              # Configuration file
```

## Contributing

If you encounter any issues while using this project, feel free to open an [Issue](https://gitcode.com/CPF-Flutter/fluttertpc_flutter_config/issues). Contributions via [PR](https://gitcode.com/CPF-Flutter/fluttertpc_flutter_config/pulls) are also very welcome.

## License

This project is based on [BSD 2-Clause](https://github.com/ByneappLLC/flutter_config/blob/master/LICENSE). Feel free to enjoy and contribute to open source.
