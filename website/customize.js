/* =============================================
   XT KEYS — Customize Page Logic
   ============================================= */

const SERVER_URL = 'http://localhost:7878';
const DEBOUNCE_MS = 300;

const DEFAULT_BINDINGS = [
  { mod: 'Alt', key: '0', app: 'calc.exe',            label: 'Calculator' },
  { mod: 'Alt', key: 'C', app: 'chrome.exe',           label: 'Chrome' },
  { mod: 'Alt', key: 'E', app: 'outlook.exe',          label: 'Outlook' },
  { mod: 'Alt', key: 'G', app: 'git-bash.exe',         label: 'Git Bash' },
  { mod: 'Alt', key: 'I', app: 'instagram.exe',        label: 'Instagram' },
  { mod: 'Alt', key: 'M', app: 'ms-windows-store:',   label: 'Microsoft Store' },
  { mod: 'Alt', key: 'N', app: 'notepad.exe',          label: 'Notepad' },
  { mod: 'Alt', key: 'P', app: 'powershell.exe',       label: 'PowerShell' },
  { mod: 'Alt', key: 'Q', app: '__close_window',       label: 'Close Window' },
  { mod: 'Alt', key: 'S', app: 'slack.exe',            label: 'Slack' },
  { mod: 'Alt', key: 'T', app: 'telegram.exe',         label: 'Telegram' },
  { mod: 'Alt', key: 'V', app: 'code.exe',             label: 'VS Code' },
  { mod: 'Alt', key: 'W', app: 'whatsapp.exe',         label: 'WhatsApp' },
  { mod: 'Alt', key: 'Y', app: 'https://youtube.com',  label: 'YouTube' },
];

const MODIFIERS = ['Alt','Ctrl','Shift','Ctrl+Shift','Alt+Shift','Ctrl+Alt','Ctrl+Shift+Alt','Win'];

let bindings = structuredClone(DEFAULT_BINDINGS);
let serverOnline = false;
let activeDropdownInput = null;
let searchDebounceTimer = null;

const hkRows        = document.getElementById('hk-rows');
const outputCmd     = document.getElementById('output-cmd');
const copyOutputBtn = document.getElementById('copy-output-btn');
const dropdown      = document.getElementById('app-dropdown');
const dropdownList  = document.getElementById('app-dropdown-list');
const dropdownStatus= document.getElementById('app-dropdown-status');

/* OS Detection */
function detectOS() {
  const ua = navigator.userAgent || '';
  const pl = navigator.platform || '';
  if (/Win/i.test(pl) || /Windows/i.test(ua)) return 'windows';
  if (/Mac/i.test(pl) || /Macintosh/i.test(ua)) return 'mac';
  return 'other';
}
(function initOsWarning() {
  if (detectOS() !== 'windows') {
    const b = document.getElementById('os-warning');
    if (b) b.style.display = 'flex';
  }
  document.getElementById('os-warning-close')?.addEventListener('click', () => {
    document.getElementById('os-warning').style.display = 'none';
  });
})();

/* Server probe */
async function probeServer() {
  try {
    const r = await fetch(`${SERVER_URL}/ping`, { signal: AbortSignal.timeout(1500) });
    return r.ok;
  } catch { return false; }
}
async function updateServerStatus() {
  const ind = document.getElementById('server-indicator');
  const lbl = document.getElementById('server-label');
  if (!ind || !lbl) return;
  ind.className = 'server-indicator checking';
  lbl.textContent = 'CHECKING';
  serverOnline = await probeServer();
  if (serverOnline) { ind.className = 'server-indicator online';  lbl.textContent = 'LIVE'; }
  else              { ind.className = 'server-indicator offline'; lbl.textContent = 'OFFLINE'; }
}
updateServerStatus();
setInterval(updateServerStatus, 5000);

/* Built-in offline app list */
const COMMON_APPS = [
  { name: 'Google Chrome',      path: 'chrome.exe' },
  { name: 'Mozilla Firefox',    path: 'firefox.exe' },
  { name: 'Microsoft Edge',     path: 'msedge.exe' },
  { name: 'VS Code',            path: 'code.exe' },
  { name: 'Cursor',             path: 'cursor.exe' },
  { name: 'Notepad',            path: 'notepad.exe' },
  { name: 'Notepad++',          path: 'notepad++.exe' },
  { name: 'PowerShell',         path: 'powershell.exe' },
  { name: 'Windows Terminal',   path: 'wt.exe' },
  { name: 'CMD',                path: 'cmd.exe' },
  { name: 'File Explorer',      path: 'explorer.exe' },
  { name: 'Calculator',         path: 'calc.exe' },
  { name: 'Paint',              path: 'mspaint.exe' },
  { name: 'Slack',              path: 'slack.exe' },
  { name: 'Discord',            path: 'discord.exe' },
  { name: 'Telegram',           path: 'telegram.exe' },
  { name: 'WhatsApp',           path: 'whatsapp.exe' },
  { name: 'Spotify',            path: 'spotify.exe' },
  { name: 'Zoom',               path: 'zoom.exe' },
  { name: 'Microsoft Teams',    path: 'teams.exe' },
  { name: 'Outlook',            path: 'outlook.exe' },
  { name: 'Word',               path: 'winword.exe' },
  { name: 'Excel',              path: 'excel.exe' },
  { name: 'PowerPoint',         path: 'powerpnt.exe' },
  { name: 'Git Bash',           path: 'git-bash.exe' },
  { name: 'Sublime Text',       path: 'sublime_text.exe' },
  { name: 'Photoshop',          path: 'photoshop.exe' },
  { name: 'VLC',                path: 'vlc.exe' },
  { name: 'Steam',              path: 'steam.exe' },
  { name: '7-Zip',              path: '7zFM.exe' },
  { name: 'OBS Studio',         path: 'obs64.exe' },
  { name: 'Figma',              path: 'figma.exe' },
  { name: 'Postman',            path: 'postman.exe' },
  { name: 'Docker Desktop',     path: 'docker desktop.exe' },
  { name: 'IntelliJ IDEA',      path: 'idea64.exe' },
  { name: 'PyCharm',            path: 'pycharm64.exe' },
  { name: 'WebStorm',           path: 'webstorm64.exe' },
  { name: 'Ubuntu WSL',         path: 'ubuntu.exe' },
  { name: 'YouTube (URL)',       path: 'https://youtube.com' },
  { name: 'GitHub (URL)',        path: 'https://github.com' },
  { name: 'Gmail (URL)',         path: 'https://mail.google.com' },
];

async function fetchApps(query) {
  if (serverOnline) {
    try {
      const r = await fetch(`${SERVER_URL}/apps?q=${encodeURIComponent(query)}`, { signal: AbortSignal.timeout(2000) });
      if (r.ok) {
        const data = await r.json();
        return { source: 'live', items: data.apps || [] };
      }
    } catch {}
  }
  const q = query.toLowerCase();
  return {
    source: 'offline',
    items: COMMON_APPS.filter(a => a.name.toLowerCase().includes(q) || a.path.toLowerCase().includes(q))
  };
}

/* Dropdown */
function escHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function positionDropdown(el) {
  const r = el.getBoundingClientRect();
  dropdown.style.left  = r.left + 'px';
  dropdown.style.top   = (r.bottom + window.scrollY) + 'px';
  dropdown.style.width = Math.max(320, r.width) + 'px';
}
function hideDropdown() {
  dropdown.style.display = 'none';
  activeDropdownInput = null;
}
function showDropdown(inputEl, results) {
  activeDropdownInput = inputEl;
  dropdownList.innerHTML = '';
  if (results.items.length === 0) {
    dropdownStatus.textContent = 'No matches — type a full path or URL';
    dropdown.style.display = 'flex';
    positionDropdown(inputEl);
    return;
  }
  results.items.slice(0, 20).forEach(item => {
    const div = document.createElement('div');
    div.className = 'app-dropdown-item';
    div.innerHTML = `<div><div class="app-item-name">${escHtml(item.name)}</div><div class="app-item-path">${escHtml(item.path)}</div></div>`;
    div.addEventListener('mousedown', (e) => {
      e.preventDefault();
      inputEl.value = item.path;
      const badge = inputEl.closest('.hk-app-wrap')?.querySelector('.hk-detected-badge');
      if (badge) badge.classList.add('visible');
      hideDropdown();
      syncFromDOM();
    });
    dropdownList.appendChild(div);
  });
  dropdownStatus.textContent = results.source === 'live'
    ? ('LIVE  ' + results.items.length + ' results from your system')
    : ('OFFLINE  ' + results.items.length + ' common apps shown');
  dropdown.style.display = 'flex';
  positionDropdown(inputEl);
}
document.addEventListener('click', (e) => {
  if (!dropdown.contains(e.target) && e.target !== activeDropdownInput) hideDropdown();
});
window.addEventListener('scroll', () => {
  if (activeDropdownInput) positionDropdown(activeDropdownInput);
}, true);

/* Row rendering */
function renderRows() {
  hkRows.innerHTML = '';
  bindings.forEach((b, idx) => {
    const row = document.createElement('div');
    row.className = 'hk-row';
    row.dataset.idx = idx;

    const modOpts = MODIFIERS.map(m => `<option value="${m}" ${m===b.mod?'selected':''}>${m}</option>`).join('');
    const modWrap = document.createElement('div');
    modWrap.className = 'hk-mod-wrap';
    modWrap.innerHTML = `<select class="hk-select" data-field="mod">${modOpts}</select>`;

    const keyWrap = document.createElement('div');
    keyWrap.className = 'hk-key-wrap';
    keyWrap.innerHTML = `<input class="hk-key-input" type="text" maxlength="5" placeholder="A" data-field="key" value="${escHtml(b.key)}">`;

    const appWrap = document.createElement('div');
    appWrap.className = 'hk-app-wrap';
    appWrap.innerHTML = `<input class="hk-app-input" type="text" placeholder="App name or full path / URL..." data-field="app" value="${escHtml(b.app)}"><span class="hk-detected-badge">DETECTED</span>`;

    const labelInput = document.createElement('input');
    labelInput.type = 'text';
    labelInput.className = 'hk-label-input';
    labelInput.placeholder = 'Label...';
    labelInput.dataset.field = 'label';
    labelInput.value = b.label || '';

    const delBtn = document.createElement('button');
    delBtn.className = 'hk-del-btn';
    delBtn.title = 'Remove row';
    delBtn.innerHTML = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>`;

    row.appendChild(modWrap);
    row.appendChild(keyWrap);
    row.appendChild(appWrap);
    row.appendChild(labelInput);
    row.appendChild(delBtn);
    hkRows.appendChild(row);

    modWrap.querySelector('select').addEventListener('change', () => syncFromDOM());

    keyWrap.querySelector('input').addEventListener('input', (e) => {
      e.target.value = e.target.value.toUpperCase().slice(0,5);
      syncFromDOM();
    });

    const appInput = appWrap.querySelector('.hk-app-input');
    appInput.addEventListener('input', () => {
      const badge = appWrap.querySelector('.hk-detected-badge');
      if (badge) badge.classList.remove('visible');
      clearTimeout(searchDebounceTimer);
      const q = appInput.value.trim();
      if (q.length < 1) { hideDropdown(); syncFromDOM(); return; }
      searchDebounceTimer = setTimeout(async () => {
        const results = await fetchApps(q);
        showDropdown(appInput, results);
      }, DEBOUNCE_MS);
      syncFromDOM();
    });
    appInput.addEventListener('focus', () => {
      const q = appInput.value.trim();
      if (q.length > 0) {
        clearTimeout(searchDebounceTimer);
        searchDebounceTimer = setTimeout(async () => {
          showDropdown(appInput, await fetchApps(q));
        }, 80);
      }
    });
    appInput.addEventListener('keydown', (e) => { if (e.key === 'Escape') hideDropdown(); });
    appInput.addEventListener('change', () => syncFromDOM());
    labelInput.addEventListener('input', () => syncFromDOM());
    delBtn.addEventListener('click', () => {
      bindings.splice(idx, 1);
      renderRows();
    });
  });
}

/* Sync DOM to bindings */
function syncFromDOM() {
  hkRows.querySelectorAll('.hk-row').forEach(row => {
    const idx = parseInt(row.dataset.idx, 10);
    if (isNaN(idx) || idx >= bindings.length) return;
    bindings[idx].mod   = row.querySelector('[data-field="mod"]')?.value || 'Alt';
    bindings[idx].key   = row.querySelector('[data-field="key"]')?.value || '';
    bindings[idx].app   = row.querySelector('[data-field="app"]')?.value || '';
    bindings[idx].label = row.querySelector('[data-field="label"]')?.value || '';
  });
}

/* AHK script generator */
function modToAhk(mod) {
  return mod
    .replace('Ctrl+Shift+Alt', '^+!')
    .replace('Ctrl+Alt',       '^!')
    .replace('Alt+Shift',      '!+')
    .replace('Ctrl+Shift',     '^+')
    .replace('Ctrl',           '^')
    .replace('Shift',          '+')
    .replace('Alt',            '!')
    .replace('Win',            '#');
}
function generateAhkScript(binds) {
  const d = new Date().toISOString().slice(0,10);
  const lines = [
    '; ==================[ XT KEYS - Custom Configuration ]==================',
    '; Generated by XT KEYS Configurator',
    `; Date: ${d}`,
    '',
    '#Requires AutoHotkey v2.0',
    '#SingleInstance Force',
    'Persistent()',
    'SendMode "Input"',
    'SetWorkingDir A_ScriptDir',
    '',
    '; ====================[ Custom Hotkeys ]====================',
    '',
  ];
  binds.forEach(b => {
    if (!b.key || !b.app) return;
    const combo = modToAhk(b.mod) + b.key;
    const comment = b.label ? `  ; ${b.label}` : '';
    if (b.app === '__close_window') {
      lines.push(`${combo}:: WinClose("A")${comment}`);
    } else {
      lines.push(`${combo}:: Run("${b.app}")${comment}`);
    }
  });
  lines.push('');
  return lines.join('\n');
}

/* PowerShell install command — Option A:
   1. Run install.ps1  (sets up AHK, PATH, startup shortcut)
   2. Overwrite hotkeys.ahk with user's custom script (base64-encoded inline)
   3. Restart xtkeys so changes take effect immediately                        */
function generateInstallCmd(binds) {
  const valid = binds.filter(b => b.key && b.app);
  if (valid.length === 0) return null;

  // Generate the full AHK content
  const ahkContent = generateAhkScript(binds);

  // Base64-encode it so it survives PowerShell quoting safely
  // btoa works on UTF-8 via TextEncoder → Uint8Array → base64
  const bytes = new TextEncoder().encode(ahkContent);
  let binary = '';
  bytes.forEach(b => binary += String.fromCharCode(b));
  const b64 = btoa(binary);

  const installUrl = 'https://github.com/RameshXT/hotkeys/releases/latest/download/install.ps1';

  // Full one-liner:
  // Step 1 – install (downloads AHK, sets PATH & startup, writes the default hotkeys.ahk)
  // Step 2 – immediately overwrite hotkeys.ahk with the custom content
  // Step 3 – restart so the custom bindings go live
  return (
    `irm ${installUrl} | iex; ` +
    `[System.IO.File]::WriteAllBytes("$env:LOCALAPPDATA\\xtkeys\\hotkeys.ahk", [System.Convert]::FromBase64String('${b64}')); ` +
    `xtkeys restart`
  );
}

/* Generate output */
function generateOutput() {
  const cmd = generateInstallCmd(bindings);
  if (cmd) {
    outputCmd.textContent = cmd;
    outputCmd.classList.add('ready');
    copyOutputBtn.disabled = false;
  } else {
    outputCmd.textContent = 'No valid bindings — add at least one key + app.';
    outputCmd.classList.remove('ready');
    copyOutputBtn.disabled = true;
  }
}

/* Collapsible sections */
function initCollapsible(toggleId, bodyId, openByDefault) {
  const toggle = document.getElementById(toggleId);
  const body   = document.getElementById(bodyId);
  if (!toggle || !body) return;
  const chevron = toggle.querySelector('.explainer-chevron');
  function setOpen(open) {
    body.classList.toggle('open', open);
    if (chevron) chevron.style.transform = open ? 'rotate(180deg)' : '';
  }
  setOpen(openByDefault);
  toggle.addEventListener('click', () => setOpen(!body.classList.contains('open')));
}
initCollapsible('explainer-toggle', 'explainer-body', false);

/* Copy helper */
function copyText(text, btn) {
  navigator.clipboard.writeText(text).then(() => {
    const orig = btn.textContent;
    btn.textContent = 'COPIED';
    btn.classList.add('copied');
    setTimeout(() => { btn.textContent = orig; btn.classList.remove('copied'); }, 2000);
  }).catch(console.error);
}

/* Buttons */
document.getElementById('copy-serve-btn')?.addEventListener('click', e => copyText('xtkeys serve', e.currentTarget));
document.getElementById('copy-output-btn')?.addEventListener('click', e => {
  const cmd = outputCmd.textContent;
  if (cmd) copyText(cmd, e.currentTarget);
});
document.getElementById('generate-btn')?.addEventListener('click', () => {
  syncFromDOM();
  generateOutput();
  document.getElementById('output-block')?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
});
document.getElementById('reset-btn')?.addEventListener('click', () => {
  if (confirm('Reset all bindings to defaults?')) {
    bindings = structuredClone(DEFAULT_BINDINGS);
    renderRows();
    outputCmd.textContent = 'Click GENERATE to build your install command.';
    outputCmd.classList.remove('ready');
    copyOutputBtn.disabled = true;
  }
});
document.getElementById('clear-btn')?.addEventListener('click', () => {
  if (confirm('Clear all bindings? You can add new ones with + ADD ROW.')) {
    bindings = [];
    renderRows();
    outputCmd.textContent = 'Click GENERATE to build your install command.';
    outputCmd.classList.remove('ready');
    copyOutputBtn.disabled = true;
  }
});
document.getElementById('add-row-btn')?.addEventListener('click', () => {
  bindings.push({ mod: 'Alt', key: '', app: '', label: '' });
  renderRows();
  hkRows.lastElementChild?.scrollIntoView({ behavior: 'smooth', block: 'center' });
});

/* Download .AHK */
document.getElementById('download-ahk-btn')?.addEventListener('click', () => {
  const blob = new Blob([generateAhkScript(bindings)], { type: 'text/plain' });
  const a = Object.assign(document.createElement('a'), { href: URL.createObjectURL(blob), download: 'hotkeys-custom.ahk' });
  a.click(); URL.revokeObjectURL(a.href);
});

/* Download JSON */
document.getElementById('download-json-btn')?.addEventListener('click', () => {
  const payload = { version: 1, generated: new Date().toISOString(), bindings: bindings.map(({mod,key,app,label})=>({mod,key,app,label})) };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
  const a = Object.assign(document.createElement('a'), { href: URL.createObjectURL(blob), download: 'hotkeys-config.json' });
  a.click(); URL.revokeObjectURL(a.href);
});

/* Import JSON */
document.getElementById('import-json-btn')?.addEventListener('click', () => {
  document.getElementById('import-file-input')?.click();
});
document.getElementById('import-file-input')?.addEventListener('change', (e) => {
  const file = e.target.files[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = ev => {
    try {
      const data = JSON.parse(ev.target.result);
      if (Array.isArray(data.bindings)) {
        bindings = data.bindings;
        renderRows();
        outputCmd.textContent = 'Click GENERATE to build your install command.';
        outputCmd.classList.remove('ready');
        copyOutputBtn.disabled = true;
      } else { alert('Invalid config file.'); }
    } catch { alert('Could not parse JSON file.'); }
  };
  reader.readAsText(file);
  e.target.value = '';
});

/* Init */
renderRows();
