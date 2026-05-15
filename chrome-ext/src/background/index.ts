import { sendToTab } from '../lib/ensureContent';

chrome.commands.onCommand.addListener(async (command) => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) return;
  const type =
    command === 'toggle-reader' ? 'toggle-reader'
    : command === 'toggle-fastread' ? 'toggle-fastread'
    : null;
  if (!type) return;
  try { await sendToTab(tab.id, { type }); } catch (e) { console.warn('[JustRead]', e); }
});

chrome.action.onClicked.addListener(async (tab) => {
  if (!tab.id) return;
  try { await sendToTab(tab.id, { type: 'toggle-reader' }); } catch (e) { console.warn('[JustRead]', e); }
});
