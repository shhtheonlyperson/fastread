export type Theme = 'light' | 'dark';
export type FontFamily = 'serif' | 'sans';
export type ChunkSize = 1 | 2 | 3;
export type OrpAccent = 'coral' | 'merlot' | 'teal' | 'amber';
export type LocalePref = 'en' | 'zh_TW';

export const WPM_MIN = 150;
export const WPM_MAX = 1500;
export const WPM_STEP = 25;

export interface Settings {
  theme: Theme;
  font: FontFamily;
  fontSize: number;
  lineHeight: number;
  columnWidth: number;
  wpm: number;
  chunkSize: ChunkSize;
  orpAccent: OrpAccent;
  locale: LocalePref;
}

export const DEFAULTS: Settings = {
  theme: 'light',
  font: 'serif',
  fontSize: 18,
  lineHeight: 1.6,
  columnWidth: 660,
  wpm: 900,
  chunkSize: 1,
  orpAccent: 'coral',
  locale: 'zh_TW',
};

export async function getSettings(): Promise<Settings> {
  const stored = await chrome.storage.sync.get(DEFAULTS);
  return { ...DEFAULTS, ...stored } as Settings;
}

export async function setSettings(patch: Partial<Settings>): Promise<void> {
  await chrome.storage.sync.set(patch);
}

export function onSettingsChange(cb: (s: Settings) => void) {
  const handler = async () => cb(await getSettings());
  chrome.storage.onChanged.addListener(handler);
  return () => chrome.storage.onChanged.removeListener(handler);
}

/* ============================================================
   Recently-read list (stored in local — sync quota too tight)
   ============================================================ */

export interface RecentItem {
  url: string;
  title: string;
  source: string;
  progress: number;     // 0..1
  ts: number;
}

const RECENT_KEY = 'jr_recent_v1';
const RECENT_MAX = 6;

export async function getRecents(): Promise<RecentItem[]> {
  const r = await chrome.storage.local.get(RECENT_KEY);
  return (r[RECENT_KEY] as RecentItem[] | undefined) ?? [];
}

export async function recordRecent(item: Omit<RecentItem, 'ts'>): Promise<void> {
  const list = await getRecents();
  const filtered = list.filter(x => x.url !== item.url);
  filtered.unshift({ ...item, ts: Date.now() });
  const trimmed = filtered.slice(0, RECENT_MAX);
  await chrome.storage.local.set({ [RECENT_KEY]: trimmed });
}
