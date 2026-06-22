import FlutterConfigPlugin from './src/main/ets/components/plugin/FlutterConfigPlugin';

// 导出插件类（供 Flutter 引擎注册）
export default FlutterConfigPlugin;

// 导出环境变量访问方法（供鸿蒙原生代码调用）
// 用法：import FlutterConfigPlugin from 'flutter_config';
//       let allEnv = FlutterConfigPlugin.env();
//       let apiKey = FlutterConfigPlugin.envFor("API_KEY");
export { FlutterConfigPlugin };
