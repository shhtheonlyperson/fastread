import { describe, it, expect, beforeEach } from 'vitest';
import { resetChromeMock, getChromeMock } from '../test/setup';
import {
  getSettings,
  setSettings,
  onSettingsChange,
  DEFAULTS,
  getRecents,
  recordRecent,
} from './storage';

beforeEach(() => { resetChromeMock(); });

describe('getSettings / setSettings', () => {
  it('returns defaults when nothing is stored', async () => {
    const s = await getSettings();
    expect(s).toEqual(DEFAULTS);
  });

  it('overlays stored values onto defaults', async () => {
    await setSettings({ wpm: 700, theme: 'dark' });
    const s = await getSettings();
    expect(s.wpm).toBe(700);
    expect(s.theme).toBe('dark');
    expect(s.font).toBe(DEFAULTS.font); // untouched fields fall back to default
  });

  it('partial updates do not clobber other fields', async () => {
    await setSettings({ wpm: 500 });
    await setSettings({ fontSize: 22 });
    const s = await getSettings();
    expect(s.wpm).toBe(500);
    expect(s.fontSize).toBe(22);
  });
});

describe('onSettingsChange', () => {
  it('fires the callback on storage changes and returns an unsubscriber', async () => {
    const fires: number[] = [];
    const off = onSettingsChange(s => { fires.push(s.wpm); });
    await setSettings({ wpm: 333 });
    // The handler is async; let microtasks drain.
    await new Promise(r => setTimeout(r, 0));
    expect(fires).toContain(333);
    off();
    await setSettings({ wpm: 444 });
    await new Promise(r => setTimeout(r, 0));
    expect(fires).not.toContain(444);
  });
});

describe('recents (local storage)', () => {
  it('starts empty', async () => {
    expect(await getRecents()).toEqual([]);
  });

  it('records and de-dupes by URL, keeping newest first', async () => {
    await recordRecent({ url: 'a', title: 'A', source: 'x', progress: 0 });
    await recordRecent({ url: 'b', title: 'B', source: 'x', progress: 0 });
    await recordRecent({ url: 'a', title: 'A2', source: 'x', progress: 0.5 });
    const list = await getRecents();
    expect(list.map(x => x.url)).toEqual(['a', 'b']);
    expect(list[0]!.title).toBe('A2');
    expect(list[0]!.progress).toBe(0.5);
  });

  it('trims to max 6 entries', async () => {
    for (let i = 0; i < 10; i++) {
      await recordRecent({ url: `u${i}`, title: `T${i}`, source: 's', progress: 0 });
    }
    const list = await getRecents();
    expect(list.length).toBe(6);
    // Most-recent first: u9 then u8…
    expect(list[0]!.url).toBe('u9');
  });

  it('writes to local, not sync', async () => {
    await recordRecent({ url: 'x', title: 't', source: 's', progress: 0 });
    const chrome = getChromeMock();
    expect(Object.keys(chrome.storage.local.data).length).toBeGreaterThan(0);
    expect(Object.keys(chrome.storage.sync.data).length).toBe(0);
  });
});
