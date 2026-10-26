// UIAbilityContextWrapper：用于在AppStorageV2中存储UIAbilityContext

import { common } from '@kit.AbilityKit';

@ObservedV2
export class UIAbilityContextWrapper {
  private static currentContext: common.UIAbilityContext | undefined = undefined;

  @Trace
  public context: common.UIAbilityContext | undefined;

  constructor(context?: common.UIAbilityContext) {
    this.context = context;
    if (context) {
      UIAbilityContextWrapper.currentContext = context;
    }
  }

  public static create(context: common.UIAbilityContext): UIAbilityContextWrapper {
    return new UIAbilityContextWrapper(context);
  }

  public static empty(): UIAbilityContextWrapper {
    return new UIAbilityContextWrapper();
  }

  public static getCurrentContext(): common.UIAbilityContext | undefined {
    return UIAbilityContextWrapper.currentContext;
  }
}
