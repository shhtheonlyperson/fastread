/**
 * Test setup: provide a stub `chrome.*` global that mirrors the
 * subset of MV3 APIs the extension touches. Each suite gets a fresh
 * store via `resetChromeMock()` (called in a `beforeEach`).
 */

interface Listener<T = unknown> { (arg: T): unknown }

class EventStub<T = unknown> {
  private listeners = new Set<Listener<T>>();
  addListener = (cb: Listener<T>) => this.listeners.add(cb);
  removeListener = (cb: Listener<T>) => this.listeners.delete(cb);
  hasListener = (cb: Listener<T>) => this.listeners.has(cb);
  dispatch(arg: T) { for (const l of this.listeners) l(arg); }
  size() { return this.listeners.size; }
}

interface StorageArea {
  data: Record<string, unknown>;
  get(keys?: string | string[] | Record<string, unknown>): Promise<Record<string, unknown>>;
  set(items: Record<string, unknown>): Promise<void>;
  remove(keys: string | string[]): Promise<void>;
  clear(): Promise<void>;
}

function makeArea(onChanged: EventStub<Record<string, { newValue: unknown; oldValue: unknown }>>): StorageArea {
  const area: StorageArea = {
    data: {},
    async get(keys) {
      if (keys === undefined || keys === null) return { ...area.data };
      if (typeof keys === 'string') {
        return keys in area.data ? { [keys]: area.data[keys] } : {};
      }
      if (Array.isArray(keys)) {
        const out: Record<string, unknown> = {};
        for (const k of keys) if (k in area.data) out[k] = area.data[k];
        return out;
      }
      // Default-shaped object: return defaults overlaid by stored values.
      const out: Record<string, unknown> = { ...keys };
      for (const k of Object.keys(keys)) if (k in area.data) out[k] = area.data[k];
      return out;
    },
    async set(items) {
      const changes: Record<string, { newValue: unknown; oldValue: unknown }> = {};
      for (const [k, v] of Object.entries(items)) {
        changes[k] = { newValue: v, oldValue: area.data[k] };
        area.data[k] = v;
      }
      onChanged.dispatch(changes);
    },
    async remove(keys) {
      const list = Array.isArray(keys) ? keys : [keys];
      for (const k of list) delete area.data[k];
    },
    async clear() { area.data = {}; },
  };
  return area;
}

export interface ChromeMock {
  storage: {
    sync: StorageArea;
    local: StorageArea;
    onChanged: EventStub<Record<string, { newValue: unknown; oldValue: unknown }>>;
  };
  runtime: {
    onMessage: EventStub;
    sendMessage: ReturnType<typeof makeFn>;
    getManifest: () => unknown;
    getURL: (p: string) => string;
    openOptionsPage?: () => void;
  };
  tabs: {
    sendMessage: ReturnType<typeof makeFn>;
    query: ReturnType<typeof makeFn>;
  };
  scripting: {
    executeScript: ReturnType<typeof makeFn>;
    insertCSS: ReturnType<typeof makeFn>;
  };
  commands: { onCommand: EventStub<string> };
  action: { onClicked: EventStub<{ id?: number; url?: string }> };
}

function makeFn() {
  const impl: { handler: (...args: unknown[]) => unknown } = { handler: () => undefined };
  const fn = ((...args: unknown[]) => impl.handler(...args)) as ((...a: unknown[]) => unknown) & {
    setImpl: (h: (...args: unknown[]) => unknown) => void;
  };
  fn.setImpl = (h) => { impl.handler = h; };
  return fn;
}

let mock: ChromeMock | null = null;

export function resetChromeMock(): ChromeMock {
  const onChanged = new EventStub<Record<string, { newValue: unknown; oldValue: unknown }>>();
  const next: ChromeMock = {
    storage: {
      sync: makeArea(onChanged),
      local: makeArea(onChanged),
      onChanged,
    },
    runtime: {
      onMessage: new EventStub(),
      sendMessage: makeFn(),
      getManifest: () => ({ content_scripts: [{ js: ['assets/content.js'] }] }),
      getURL: (p: string) => `chrome-extension://abc/${p}`,
    },
    tabs: {
      sendMessage: makeFn(),
      query: makeFn(),
    },
    scripting: {
      executeScript: makeFn(),
      insertCSS: makeFn(),
    },
    commands: { onCommand: new EventStub() },
    action: { onClicked: new EventStub() },
  };
  mock = next;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (globalThis as any).chrome = next;
  return next;
}

export function getChromeMock(): ChromeMock {
  if (!mock) return resetChromeMock();
  return mock;
}

// Install once at module load so even files that read `chrome` at
// import-time (none currently, but cheap insurance) see something.
resetChromeMock();
