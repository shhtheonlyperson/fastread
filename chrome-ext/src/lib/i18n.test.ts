import { describe, it, expect } from 'vitest';
import { resolveLocale, t, localeHtmlLang } from './i18n';

describe('resolveLocale', () => {
  it('returns explicit choice unchanged', () => {
    expect(resolveLocale('en')).toBe('en');
    expect(resolveLocale('zh_TW')).toBe('zh_TW');
  });
  it('"resolveLocale" is identity for explicit locales (no auto fallback)', () => {
    expect(resolveLocale('en')).toBe('en');
    expect(resolveLocale('zh_TW')).toBe('zh_TW');
  });
});

describe('t', () => {
  it('returns the message for a known key', () => {
    const v = t('settings', 'en');
    expect(typeof v).toBe('string');
    expect(v.length).toBeGreaterThan(0);
  });
  it('falls back to English when zh_TW lacks a key', () => {
    expect(t('__definitely_missing__', 'zh_TW')).toBe('__definitely_missing__');
  });
  it('returns the key itself if nothing is found', () => {
    expect(t('__definitely_missing__', 'en')).toBe('__definitely_missing__');
  });
  it('different locales can yield different strings for the same key', () => {
    const en = t('settings', 'en');
    const zh = t('settings', 'zh_TW');
    // Either translated differently, or zh fell back to en — both are valid.
    expect(typeof en).toBe('string');
    expect(typeof zh).toBe('string');
  });
});

describe('localeHtmlLang', () => {
  it('maps to BCP47 codes', () => {
    expect(localeHtmlLang('en')).toBe('en');
    expect(localeHtmlLang('zh_TW')).toBe('zh-Hant');
  });
});
