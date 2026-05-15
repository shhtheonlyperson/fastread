import enRaw from '../../public/_locales/en/messages.json';
import zhRaw from '../../public/_locales/zh_TW/messages.json';

type MessageBundle = Record<string, { message: string }>;
const en = enRaw as MessageBundle;
const zh = zhRaw as MessageBundle;

export type Locale = 'en' | 'zh_TW';

export function resolveLocale(pref: Locale): Locale {
  return pref;
}

export function t(key: string, locale: Locale = 'zh_TW'): string {
  const bundle = locale === 'zh_TW' ? zh : en;
  return bundle[key]?.message ?? en[key]?.message ?? key;
}

export function localeHtmlLang(locale: Locale): string {
  return locale === 'zh_TW' ? 'zh-Hant' : 'en';
}
