import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import * as fs from 'fs';
import * as path from 'path';

const REMOVED_SYSCAPS = new Set([
  'SystemCapability.Communication.FusionConnectivity.Core',
  'SystemCapability.Communication.NetManager.Eap',
  'SystemCapability.Communication.NetManager.NetFirewall',
  'SystemCapability.Multimedia.AVSession.AVInputCast',
]);

function pruneRpcidSyscapsPlugin() {
  return {
    pluginId: 'pruneRpcidSyscaps',
    apply(pluginContext) {
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
