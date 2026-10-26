export interface WebNavigationLifecycleState {
  generation: number;
  beganGeneration: number;
  completedGeneration: number;
  suppressPageCallbacks: boolean;
  expectedStartUrl: string;
}

export function createWebNavigationLifecycleState(): WebNavigationLifecycleState {
  return {
    generation: 0,
    beganGeneration: -1,
    completedGeneration: -1,
    suppressPageCallbacks: false,
    expectedStartUrl: '',
  };
}

export function startWebNavigation(state: WebNavigationLifecycleState, expectedStartUrl: string = ''): void {
  state.generation += 1;
  state.beganGeneration = -1;
  state.completedGeneration = -1;
  state.suppressPageCallbacks = false;
  state.expectedStartUrl = expectedStartUrl.trim();
}

export function enterWebNavigationHome(state: WebNavigationLifecycleState): void {
  state.generation += 1;
  state.beganGeneration = -1;
  state.completedGeneration = -1;
  state.suppressPageCallbacks = true;
  state.expectedStartUrl = '';
}

export function acceptWebPageBegin(state: WebNavigationLifecycleState, url: string = ''): boolean {
  if (state.suppressPageCallbacks) {
    return false;
  }
  if (state.beganGeneration === state.generation && state.completedGeneration === state.generation) {
    startWebNavigation(state);
  }
  const normalizedUrl = url.trim().toLowerCase();
  if (state.beganGeneration !== state.generation && state.expectedStartUrl.length > 0 &&
    (normalizedUrl === 'about:blank' || normalizedUrl.startsWith('about:blank?') ||
      normalizedUrl.startsWith('about:blank#'))) {
    return false;
  }
  state.beganGeneration = state.generation;
  state.expectedStartUrl = '';
  return true;
}

export function canCompleteWebNavigation(state: WebNavigationLifecycleState): boolean {
  return !state.suppressPageCallbacks &&
    state.beganGeneration === state.generation &&
    state.completedGeneration !== state.generation;
}

export function canFailWebNavigation(state: WebNavigationLifecycleState): boolean {
  return !state.suppressPageCallbacks && state.completedGeneration !== state.generation;
}

export function completeWebNavigation(state: WebNavigationLifecycleState): void {
  state.completedGeneration = state.generation;
}

export function failWebNavigation(state: WebNavigationLifecycleState): void {
  state.completedGeneration = state.generation;
}

export function stopWebNavigation(state: WebNavigationLifecycleState): void {
  state.completedGeneration = state.generation;
  state.suppressPageCallbacks = true;
  state.expectedStartUrl = '';
}
