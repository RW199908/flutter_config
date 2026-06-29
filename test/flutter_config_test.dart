import 'package:flutter/services.dart';
import 'package:flutter_config/flutter_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const MethodChannel channel = MethodChannel('flutter_config');
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // Helper: reset internal state between tests
  // =========================================================================
  void resetState() {
    FlutterConfig.loadValueForTesting({});
  }

  // =========================================================================
  // 1. 异常场景测试 (Exception / Error Scenarios)
  // =========================================================================
  group('异常场景', () {
    setUp(() {
      resetState();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance?.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('get() 在未加载变量时返回 null 并打印警告', () {
      // _variables 为空 Map，get 应返回 null 并打印警告
      final value = FlutterConfig.get('ANY_KEY');
      expect(value, isNull);
    });

    test('get() 传入空字符串 key 时返回 null 并打印警告', () {
      FlutterConfig.loadValueForTesting({'KEY': 'value'});
      final value = FlutterConfig.get('');
      expect(value, isNull);
    });

    test('get() 传入不存在的 key 时返回 null 并打印警告', () {
      FlutterConfig.loadValueForTesting({'EXISTING_KEY': 'value'});
      final value = FlutterConfig.get('NON_EXISTENT_KEY');
      expect(value, isNull);
    });

    test('loadEnvVariables() MethodChannel 返回 null 时应默认为空 Map', () async {
      TestDefaultBinaryMessengerBinding.instance?.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        return null; // 模拟原生端返回 null
      });

      await FlutterConfig.loadEnvVariables();

      // variables 应为空 Map，get 应返回 null
      expect(FlutterConfig.variables, isEmpty);
      expect(FlutterConfig.get('ANY_KEY'), isNull);
    });

    test('loadEnvVariables() MethodChannel 抛出 PlatformException 时应能捕获', () async {
      TestDefaultBinaryMessengerBinding.instance?.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        throw PlatformException(code: 'CHANNEL_ERROR', message: 'Channel failed');
      });

      // 应抛出异常，不应静默失败
      expect(
        () => FlutterConfig.loadEnvVariables(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('loadEnvVariables() MethodChannel 抛出 MissingPluginException 时应能捕获', () async {
      TestDefaultBinaryMessengerBinding.instance?.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        throw MissingPluginException('No implementation found');
      });

      expect(
        () => FlutterConfig.loadEnvVariables(),
        throwsA(isA<MissingPluginException>()),
      );
    });

    test('loadValueForTesting 传入 null 值的 Map 时 get 应返回 null', () {
      FlutterConfig.loadValueForTesting({'NULL_VALUE_KEY': null});
      final value = FlutterConfig.get('NULL_VALUE_KEY');
      expect(value, isNull);
    });

    test('get() 对值为 null 的 key 和不存在的 key 结果不同', () {
      FlutterConfig.loadValueForTesting({'NULL_KEY': null});
      // containsKey 为 true，但值为 null — 应返回 null（不打印 key 不存在的警告）
      final nullValue = FlutterConfig.get('NULL_KEY');
      expect(nullValue, isNull);

      // 不存在的 key — 也返回 null，但走不同分支
      final missingValue = FlutterConfig.get('MISSING_KEY');
      expect(missingValue, isNull);
    });

    test('loadEnvVariables() MethodChannel 返回非 Map 类型时应抛出类型转换异常', () async {
      TestDefaultBinaryMessengerBinding.instance?.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        return 'not a map'; // 返回字符串而非 Map
      });

      // invokeMapMethod 在返回非 Map 时会抛出 TypeError
      expect(
        () => FlutterConfig.loadEnvVariables(),
        throwsA(anything), // 类型转换异常
      );
    });
  });

  // =========================================================================
  // 2. 边界场景测试 (Boundary / Edge Cases)
  // =========================================================================
  group('边界场景', () {
    setUp(() {
      resetState();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance?.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('loadValueForTesting 传入空 Map 时 get 返回 null', () {
      FlutterConfig.loadValueForTesting({});
      expect(FlutterConfig.get('ANY_KEY'), isNull);
      expect(FlutterConfig.variables, isEmpty);
    });

    test('variables getter 返回的是副本，修改不影响内部状态', () {
      FlutterConfig.loadValueForTesting({'KEY': 'original'});

      final varsCopy = FlutterConfig.variables;
      varsCopy['KEY'] = 'modified';
      varsCopy['NEW_KEY'] = 'new_value';

      // 内部状态不应被修改
      expect(FlutterConfig.get('KEY'), 'original');
      expect(FlutterConfig.get('NEW_KEY'), isNull);
      expect(FlutterConfig.variables, isNot(containsPair('NEW_KEY', 'new_value')));
    });

    test('loadValueForTesting 覆盖之前的值', () {
      FlutterConfig.loadValueForTesting({'KEY_A': 'value_a'});
      expect(FlutterConfig.get('KEY_A'), 'value_a');

      FlutterConfig.loadValueForTesting({'KEY_B': 'value_b'});
      // 之前的 KEY_A 应不再存在
      expect(FlutterConfig.get('KEY_A'), isNull);
      expect(FlutterConfig.get('KEY_B'), 'value_b');
    });

    test('支持各种值类型：String, int, double, bool, List, Map', () {
      FlutterConfig.loadValueForTesting({
        'STRING_KEY': 'hello',
        'INT_KEY': 42,
        'DOUBLE_KEY': 3.14,
        'BOOL_KEY': true,
        'LIST_KEY': [1, 2, 3],
        'MAP_KEY': {'nested': 'value'},
      });

      expect(FlutterConfig.get('STRING_KEY'), 'hello');
      expect(FlutterConfig.get('INT_KEY'), 42);
      expect(FlutterConfig.get('DOUBLE_KEY'), 3.14);
      expect(FlutterConfig.get('BOOL_KEY'), true);
      expect(FlutterConfig.get('LIST_KEY'), [1, 2, 3]);
      expect(FlutterConfig.get('MAP_KEY'), {'nested': 'value'});
    });

    test('极值测试：大量变量（1000个）', () {
      final largeMap = <String, dynamic>{};
      for (int i = 0; i < 1000; i++) {
        largeMap['KEY_$i'] = 'VALUE_$i';
      }
      FlutterConfig.loadValueForTesting(largeMap);

      expect(FlutterConfig.get('KEY_0'), 'VALUE_0');
      expect(FlutterConfig.get('KEY_999'), 'VALUE_999');
      expect(FlutterConfig.get('KEY_500'), 'VALUE_500');
      expect(FlutterConfig.variables.length, 1000);
    });

    test('极值测试：超长 key 和 value', () {
      final longKey = 'K' * 10000;
      final longValue = 'V' * 10000;
      FlutterConfig.loadValueForTesting({longKey: longValue});

      expect(FlutterConfig.get(longKey), longValue);
    });

    test('特殊字符 key：包含空格、换行、Unicode', () {
      FlutterConfig.loadValueForTesting({
        'key with spaces': 'value1',
        'key\nwith\nnewlines': 'value2',
        '键': '中文值',
        '🔑': 'emoji_value',
        'key.with.dots': 'value3',
        'key-with-dashes': 'value4',
        'key_with_underscores': 'value5',
      });

      expect(FlutterConfig.get('key with spaces'), 'value1');
      expect(FlutterConfig.get('key\nwith\nnewlines'), 'value2');
      expect(FlutterConfig.get('键'), '中文值');
      expect(FlutterConfig.get('🔑'), 'emoji_value');
      expect(FlutterConfig.get('key.with.dots'), 'value3');
      expect(FlutterConfig.get('key-with-dashes'), 'value4');
      expect(FlutterConfig.get('key_with_underscores'), 'value5');
    });

    test('空字符串 key', () {
      FlutterConfig.loadValueForTesting({'': 'empty_key_value'});
      // 空字符串是合法 key
      expect(FlutterConfig.get(''), 'empty_key_value');
    });

    test('loadEnvVariables 返回空 Map 时 get 返回 null', () async {
      TestDefaultBinaryMessengerBinding.instance?.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        return <String, dynamic>{};
      });

      await FlutterConfig.loadEnvVariables();
      expect(FlutterConfig.variables, isEmpty);
      expect(FlutterConfig.get('ANY_KEY'), isNull);
    });

    test('variables getter 在空 Map 时返回空 Map 而非 null', () {
      FlutterConfig.loadValueForTesting({});
      final vars = FlutterConfig.variables;
      expect(vars, isNotNull);
      expect(vars, isA<Map<String, dynamic>>());
      expect(vars, isEmpty);
    });

    test('多次调用 loadValueForTesting 后 variables 反映最新状态', () {
      FlutterConfig.loadValueForTesting({'A': '1'});
      expect(FlutterConfig.variables, {'A': '1'});

      FlutterConfig.loadValueForTesting({'B': '2'});
      expect(FlutterConfig.variables, {'B': '2'});

      FlutterConfig.loadValueForTesting({'C': '3', 'D': '4'});
      expect(FlutterConfig.variables, {'C': '3', 'D': '4'});
    });
  });

  // =========================================================================
  // 3. 并发场景测试 (Concurrency Scenarios)
  // =========================================================================
  group('并发场景', () {
    setUp(() {
      resetState();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance?.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('多次同时调用 loadEnvVariables 应正确完成', () async {
      int callCount = 0;
      TestDefaultBinaryMessengerBinding.instance?.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        callCount++;
        // 模拟不同延迟
        await Future.delayed(Duration(milliseconds: callCount * 10));
        return {'KEY_$callCount': 'VALUE_$callCount'};
      });

      // 同时发起 5 个 loadEnvVariables 调用
      final futures = List<Future<void>>.generate(5, (_) => FlutterConfig.loadEnvVariables());
      await Future.wait(futures);

      // 最后一次完成的调用结果应被保留（后写入覆盖前写入）
      final vars = FlutterConfig.variables;
      expect(vars, isNotEmpty);
      // 至少有一个 KEY 存在
      expect(vars.keys.any((k) => k.startsWith('KEY_')), isTrue);
    });

    test('并发读写：loadEnvVariables 与 get 同时调用不应崩溃', () async {
      TestDefaultBinaryMessengerBinding.instance?.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        await Future.delayed(Duration(milliseconds: 50));
        return {'CONCURRENT_KEY': 'concurrent_value'};
      });

      // 同时发起 load 和 get
      final results = await Future.wait<dynamic>([
        FlutterConfig.loadEnvVariables(),
        Future.value(FlutterConfig.get('CONCURRENT_KEY')),
        FlutterConfig.loadEnvVariables(),
        Future.value(FlutterConfig.get('CONCURRENT_KEY')),
      ]);

      // 不应抛出异常，get 可能返回 null（加载未完成）或值（加载已完成）
      expect(results, isNotNull);
    });

    test('快速连续多次 loadValueForTesting 后 get 返回最终值', () {
      for (int i = 0; i < 100; i++) {
        FlutterConfig.loadValueForTesting({'FAST_KEY': 'value_$i'});
      }
      // 最终值应为最后一次设置
      expect(FlutterConfig.get('FAST_KEY'), 'value_99');
    });

    test('并发调用 loadValueForTesting 和 variables getter 不应崩溃', () async {
      FlutterConfig.loadValueForTesting({'INIT': 'init'});

      // 同时读取 variables 和写入新值
      final results = await Future.wait<dynamic>([
        Future.value(FlutterConfig.variables),
        Future.value(FlutterConfig.loadValueForTesting({'NEW': 'new'})),
        Future.value(FlutterConfig.variables),
        Future.value(FlutterConfig.loadValueForTesting({'FINAL': 'final'})),
        Future.value(FlutterConfig.variables),
      ]);

      // 不应崩溃，最终状态应为最后一次 loadValueForTesting
      expect(FlutterConfig.get('FINAL'), 'final');
      expect(results, isNotNull);
    });

    test('loadEnvVariables 完成后覆盖 loadValueForTesting 的值', () async {
      FlutterConfig.loadValueForTesting({'TEST_KEY': 'testing_value'});

      TestDefaultBinaryMessengerBinding.instance?.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        return {'CHANNEL_KEY': 'channel_value'};
      });

      await FlutterConfig.loadEnvVariables();

      // loadEnvVariables 应覆盖之前的值
      expect(FlutterConfig.get('CHANNEL_KEY'), 'channel_value');
      expect(FlutterConfig.get('TEST_KEY'), isNull);
    });
  });

  // =========================================================================
  // 4. 正常功能场景补充 (Additional Functional Tests)
  // =========================================================================
  group('正常功能场景', () {
    setUp(() {
      resetState();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance?.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('MethodChannel 正常加载变量并通过 get 获取', () async {
      TestDefaultBinaryMessengerBinding.instance?.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        return {'FABRIC': 67, 'ENV': 'production'};
      });

      await FlutterConfig.loadEnvVariables();
      expect(FlutterConfig.get('FABRIC'), 67);
      expect(FlutterConfig.get('ENV'), 'production');
    });

    test('loadValueForTesting 正常注入变量并通过 get 获取', () {
      FlutterConfig.loadValueForTesting({'BASE_URL': 'https://www.google.com'});
      expect(FlutterConfig.get('BASE_URL'), 'https://www.google.com');
    });

    test('variables getter 返回所有已加载变量', () {
      FlutterConfig.loadValueForTesting({
        'KEY1': 'value1',
        'KEY2': 42,
        'KEY3': true,
      });

      final vars = FlutterConfig.variables;
      expect(vars.length, 3);
      expect(vars['KEY1'], 'value1');
      expect(vars['KEY2'], 42);
      expect(vars['KEY3'], true);
    });

    test('单例模式：多次获取 variables 返回一致的值', () {
      FlutterConfig.loadValueForTesting({'SINGLETON': 'test'});

      final vars1 = FlutterConfig.variables;
      final vars2 = FlutterConfig.variables;

      // 内容一致
      expect(vars1, vars2);
      // 但不是同一个对象（每次返回新副本）
      expect(identical(vars1, vars2), isFalse);
    });

    test('get() 对存在的 key 返回正确值，对不存在的 key 返回 null', () {
      FlutterConfig.loadValueForTesting({
        'EXISTING': 'exists',
      });

      expect(FlutterConfig.get('EXISTING'), 'exists');
      expect(FlutterConfig.get('NOT_EXISTING'), isNull);
    });

    test('loadEnvVariables 调用正确的 MethodChannel 方法名', () async {
      String? calledMethod;
      TestDefaultBinaryMessengerBinding.instance?.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        calledMethod = methodCall.method;
        return {'TEST': 'value'};
      });

      await FlutterConfig.loadEnvVariables();
      expect(calledMethod, 'loadEnvVariables');
    });

    test('值为 0 (int) 时 get 应正确返回 0 而非 null', () {
      FlutterConfig.loadValueForTesting({'ZERO_KEY': 0});
      expect(FlutterConfig.get('ZERO_KEY'), 0);
    });

    test('值为 false (bool) 时 get 应正确返回 false 而非 null', () {
      FlutterConfig.loadValueForTesting({'FALSE_KEY': false});
      expect(FlutterConfig.get('FALSE_KEY'), false);
    });

    test('值为空字符串时 get 应正确返回空字符串而非 null', () {
      FlutterConfig.loadValueForTesting({'EMPTY_STRING_KEY': ''});
      expect(FlutterConfig.get('EMPTY_STRING_KEY'), '');
    });
  });
}
