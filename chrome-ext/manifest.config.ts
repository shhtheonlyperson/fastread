import { defineManifest } from '@crxjs/vite-plugin';
import pkg from './package.json' with { type: 'json' };

export default defineManifest({
  manifest_version: 3,
  name: '__MSG_extName__',
  description: '__MSG_extDescription__',
  default_locale: 'en',
  version: pkg.version,
  action: {
    default_popup: 'src/popup/index.html',
    default_title: 'JustRead',
  },
  options_page: 'src/options/index.html',
  background: {
    service_worker: 'src/background/index.ts',
    type: 'module',
  },
  content_scripts: [
    {
      matches: ['<all_urls>'],
      js: ['src/content/index.tsx'],
      run_at: 'document_idle',
    },
  ],
  permissions: ['storage', 'activeTab', 'scripting'],
  host_permissions: ['<all_urls>'],
  commands: {
    'toggle-reader': {
      suggested_key: { default: 'Alt+R', mac: 'Alt+R' },
      description: 'Toggle Reader View',
    },
    'toggle-fastread': {
      suggested_key: { default: 'Alt+Shift+R', mac: 'Alt+Shift+R' },
      description: 'Toggle Fast Read',
    },
  },
  icons: {
    '16': 'icons/icon-16.png',
    '48': 'icons/icon-48.png',
    '128': 'icons/icon-128.png',
  },
  web_accessible_resources: [
    {
      resources: ['src/content/*', 'icons/*'],
      matches: ['<all_urls>'],
    },
  ],
});
