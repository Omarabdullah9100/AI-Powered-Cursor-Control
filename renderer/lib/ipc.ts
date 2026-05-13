import type { AIPointerAPI } from '../../electron/types';

function getApi(): AIPointerAPI {
  if (typeof window === 'undefined' || !window.aipointer) {
    throw new Error('window.aipointer is not available. Preload script did not load.');
  }
  return window.aipointer;
}

export const ipc = new Proxy<AIPointerAPI>({} as AIPointerAPI, {
  get(_t, prop: keyof AIPointerAPI) {
    return getApi()[prop];
  },
});
