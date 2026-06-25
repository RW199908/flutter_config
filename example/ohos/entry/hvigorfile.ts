import { hapTasks } from '@ohos/hvigor-ohos-plugin';
const { createDotenvPlugin } = require('./oh_modules/flutter_config/dotenv');

export default {
  system: hapTasks,
  plugins: [createDotenvPlugin({ entryDir: __dirname, envFile: '.env.dev' })]
}
