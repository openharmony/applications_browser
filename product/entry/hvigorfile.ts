import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import * as fs from 'fs';
import * as path from 'path';

const REMOVED_SYSCAPS = new Set([
  'SystemCapability.Communication.FusionConnectivity.Core',
  'SystemCapability.Communication.NetManager.Eap',
  'SystemCapability.Communication.NetManager.NetFirewall',
  'SystemCapability.Multimedia.AVSession.AVInputCast',
]);

function getRequestedProduct(): string | undefined {
  for (let index = 0; index < process.argv.length; index++) {
    const argument = process.argv[index];
    if (argument.startsWith('product=')) {
      return argument.substring('product='.length);
    }
    if (argument.startsWith('--product=')) {
      return argument.substring('--product='.length);
    }
    if (argument === '--product' && index + 1 < process.argv.length) {
      const nextArgument = process.argv[index + 1];
      return nextArgument.startsWith('product=')
        ? nextArgument.substring('product='.length)
        : nextArgument;
    }
  }
  return undefined;
}

function shouldPruneRpcidSyscaps(): boolean {
  const requestedProduct = getRequestedProduct();
  // 清理逻辑只属于现有手机/平板产品流程。
  // PC 产品使用独立的 syscap.json，不能依赖 entry 模块的任务。
  return requestedProduct === undefined || requestedProduct === 'default';
}

function pruneRpcidSyscapsPlugin() {
  return {
    pluginId: 'pruneRpcidSyscaps',
    apply(pluginContext) {
      if (!shouldPruneRpcidSyscaps()) {
        // PC 构建不注册 entry 的 SysCap 任务，避免依赖不存在的任务节点。
        return;
      }
      pluginContext.registerTask({
        name: 'pruneRpcidSyscaps',
        run(taskContext) {
          const rpcidPath = path.join(
            taskContext.modulePath,
            'build/default/intermediates/syscap/default/rpcid.json'
          );
          if (!fs.existsSync(rpcidPath)) {
            return;
          }
          const rpcid = JSON.parse(fs.readFileSync(rpcidPath, 'utf8')) as {
            syscap?: string[];
          };
          if (!Array.isArray(rpcid.syscap)) {
            return;
          }
          rpcid.syscap = rpcid.syscap.filter((cap) => !REMOVED_SYSCAPS.has(cap));
          fs.writeFileSync(rpcidPath, JSON.stringify(rpcid));
        },
        dependencies: ['default@SyscapTransform'],
        postDependencies: ['default@PackageHap'],
      });
    },
  };
}

export default {
  system: hapTasks,
  bundleName: 'com.ohos.browser',
  plugins: [pruneRpcidSyscapsPlugin()],
};
