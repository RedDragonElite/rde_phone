const resourceName = (window.GetParentResourceName && GetParentResourceName()) || 'rde_phone';

const el = (sel) => document.querySelector(sel);
const els = (sel) => document.querySelectorAll(sel);

let currentCallId = null;
let callTimerHandle = null;
let settings = { wallpaper: 'crimson', wallpaperUrl: null, ringtone: true, ringtoneId: 'classic', smsToneId: 'ping', vibration: true, language: 'en' };
let notifications = [];
let badges = {};

/* -----------------------------------------------------------
 * i18n — config-driven (Config.Locales in config.lua). The shell
 * talks to Lua directly (not through the app SDK's postMessage),
 * so it keeps its own small loader/translator instead of using
 * RDEPhone.t() from the SDK, which is for iframe apps only.
 * --------------------------------------------------------- */
let locales = null;
let lang = 'en';

function t(key, ...args) {
    const table = (locales && (locales[lang] || locales.en)) || {};
    let str = table[key] || key;
    args.forEach((a) => { str = str.replace('%s', a); });
    return str;
}

function intlTag() {
    return lang === 'de' ? 'de-DE' : 'en-US';
}

async function loadLocale() {
    const data = await callLua('sdk:request', { action: 'getLocaleData' });
    if (data && data.locales) locales = data.locales;
    lang = settings.language || (data && data.defaultLanguage) || 'en';
}

function refreshIcons() {
    if (window.lucide) lucide.createIcons();
}

/* -----------------------------------------------------------
 * Ringtone / notification sound — generated via the shared
 * RDEAudio module (web/theme/rdui-audio.js), tone selectable
 * per player in Settings.
 * --------------------------------------------------------- */
function playNotificationSound() {
    if (!settings.ringtone) return;
    window.RDEAudio && RDEAudio.playSmsTonePattern(settings.smsToneId || 'ping');
}

let ringLoopHandle = null;

function startRingtone() {
    if (!settings.ringtone) return;
    stopRingtone();
    const pattern = () => { window.RDEAudio && RDEAudio.playRingtonePattern(settings.ringtoneId || 'classic'); };
    pattern();
    ringLoopHandle = setInterval(pattern, 1600);
}

function stopRingtone() {
    if (ringLoopHandle) clearInterval(ringLoopHandle);
    ringLoopHandle = null;
}

function vibrate(duration = 300, frequency = 80) {
    if (!settings.vibration) return;
    callLua('vibrate', { duration, frequency });
}

/* -----------------------------------------------------------
 * The ONE bridge between iframe apps and Lua.
 * Apps -> SDK -> postMessage -> here -> fetch NUI callback -> Lua
 * Lua's return value goes straight back through the same chain.
 * --------------------------------------------------------- */
window.addEventListener('message', async (event) => {
    const msg = event.data;
    if (!msg || msg.source !== 'rde_phone_app') return;

    if (msg.type === 'request') {
        const result = await callLua('sdk:request', { action: msg.action, payload: msg.payload });
        event.source.postMessage(
            { source: 'rde_phone_shell', type: 'response', reqId: msg.reqId, result },
            '*'
        );
    }

    if (msg.type === 'notify') {
        showNotification(msg.data);
    }

    if (msg.type === 'settingsChanged') {
        const languageChanged = settings.language !== msg.data.language;
        settings = msg.data;
        applyWallpaper();
        if (languageChanged) {
            loadLocale().then(() => {
                applyStaticTranslations();
                renderNotifCenter();
                renderLockNotifs();
                loadApps(); // built-in app titles are translated server-side per request
            });
        }
    }

    if (msg.type === 'close') {
        closePhone();
    }

    if (msg.type === 'viewfinder') {
        setViewfinderMode(!!msg.enabled);
    }
});

function setViewfinderMode(enabled) {
    const frame = el('#phone-frame');
    const screen = el('#phone-screen');
    if (!frame || !screen) return;
    frame.classList.toggle('viewfinder-mode', enabled);
    screen.classList.toggle('viewfinder-mode', enabled);
}

function broadcastToApp(event, data) {
    const frame = el('#app-frame');
    if (frame && frame.contentWindow) {
        frame.contentWindow.postMessage({ source: 'rde_phone_shell', type: 'event', event, data }, '*');
    }
}

async function callLua(name, data) {
    try {
        const resp = await fetch(`https://${resourceName}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        });
        return await resp.json();
    } catch (e) {
        return { error: true, message: 'nui-unreachable' };
    }
}

/* ----------------------------------------------------------- Clock / status bar */
function tickClock() {
    const now = new Date();
    const timeStr = now.toLocaleTimeString(intlTag(), { hour: '2-digit', minute: '2-digit' });
    els('.status-time').forEach((n) => (n.textContent = timeStr));
}
setInterval(tickClock, 1000);
tickClock();

function updateLockDate() {
    const lockDate = el('#lock-date');
    if (lockDate) {
        lockDate.textContent = new Date().toLocaleDateString(intlTag(), { weekday: 'long', day: 'numeric', month: 'long' });
    }
}
updateLockDate();

/* ----------------------------------------------------------- Lock / unlock (swipe-up) */
(function setupSwipeToUnlock() {
    const lock = el('#lockscreen');
    let startY = null;
    let dragging = false;

    const onStart = (y) => { startY = y; dragging = true; lock.classList.add('dragging'); };
    const onMove = (y) => {
        if (!dragging || startY === null) return;
        const dy = Math.max(0, startY - y);
        lock.style.transform = `translateY(-${Math.min(dy, 400)}px)`;
        lock.style.opacity = String(Math.max(0, 1 - dy / 300));
    };
    const onEnd = (y) => {
        if (!dragging || startY === null) return;
        dragging = false;
        lock.classList.remove('dragging');
        const dy = startY - y;
        lock.style.transform = '';
        lock.style.opacity = '';
        if (dy > 90) unlockPhone();
        startY = null;
    };

    lock.addEventListener('mousedown', (e) => onStart(e.clientY));
    window.addEventListener('mousemove', (e) => onMove(e.clientY));
    window.addEventListener('mouseup', (e) => onEnd(e.clientY));
    lock.addEventListener('touchstart', (e) => onStart(e.touches[0].clientY), { passive: true });
    lock.addEventListener('touchmove', (e) => onMove(e.touches[0].clientY), { passive: true });
    lock.addEventListener('touchend', (e) => onEnd(e.changedTouches[0].clientY));
})();

function unlockPhone() {
    el('#lockscreen').classList.add('unlocking');
    setTimeout(() => {
        el('#lockscreen').classList.add('hidden');
        el('#homescreen').classList.remove('hidden');
    }, 280);
}

function lockPhone() {
    const lock = el('#lockscreen');
    lock.classList.remove('hidden', 'unlocking');
    lock.style.transform = '';
    lock.style.opacity = '';
    el('#homescreen').classList.add('hidden');
    el('#app-view').classList.add('hidden');
    el('#notif-center').classList.add('hidden');
}

/* ----------------------------------------------------------- App launcher (dynamic registry) */
let apps = [];

async function loadApps() {
    const result = await callLua('sdk:request', { action: 'getApps' });
    apps = Array.isArray(result) ? result : [];
    renderAppGrid();
}

function hexToRgbTriplet(hex) {
    if (!hex) return null;
    const m = hex.replace('#', '').match(/^([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i);
    if (!m) return null;
    return `${parseInt(m[1], 16)},${parseInt(m[2], 16)},${parseInt(m[3], 16)}`;
}

function renderAppGrid() {
    const grid = el('#app-grid');
    if (!grid) return;
    grid.innerHTML = apps.map((app) => `
        <div class="app-icon" data-app="${app.slug}" data-title="${app.title}" data-url="${app.url}">
            <div class="glyph rdui-glass"><i data-lucide="${app.icon}"></i></div>
            <span>${app.title}</span>
        </div>
    `).join('');
    refreshIcons();
    renderBadges();

    // Per-app icon color — set by the developer at registration time
    // (RegisterPhoneApp's `color` field), not a user-facing setting.
    apps.forEach((app) => {
        if (!app.color) return;
        const rgb = hexToRgbTriplet(app.color);
        if (!rgb) return;
        const glyph = grid.querySelector(`.app-icon[data-app="${app.slug}"] .glyph`);
        if (!glyph) return;
        glyph.style.setProperty('--glass-c1', rgb.split(',').map((v) => Math.min(255, +v + 20)).join(','));
        glyph.style.setProperty('--glass-c2', rgb.split(',').map((v) => Math.round(+v * 0.3)).join(','));
        glyph.style.setProperty('--glass-glow', rgb);
        glyph.style.setProperty('--glyph-color', app.color);
    });

    els('.app-icon').forEach((icon) => {
        icon.addEventListener('click', () => {
            badges[icon.dataset.app] = 0;
            renderBadges();
            openApp(icon.dataset.url, icon.dataset.title);
        });
    });
}

function openApp(url, title) {
    el('#app-view').classList.remove('hidden');
    el('#homescreen').classList.add('hidden');
    el('#app-title').textContent = title || '';
    el('#app-frame').src = url;
}

el('#app-back').addEventListener('click', () => {
    el('#app-frame').src = 'about:blank';
    el('#app-view').classList.add('hidden');
    el('#homescreen').classList.remove('hidden');
});

/* ----------------------------------------------------------- Notifications */
function showNotification({ title, body, icon, app }) {
    const bar = document.createElement('div');
    bar.className = 'notif-banner';
    bar.innerHTML = `<div class="notif-icon"><i data-lucide="${icon || 'bell'}"></i></div><div><div class="notif-title">${title || ''}</div><div class="notif-body">${body || ''}</div></div>`;
    el('#notif-stack').appendChild(bar);
    refreshIcons();
    requestAnimationFrame(() => bar.classList.add('show'));
    setTimeout(() => {
        bar.classList.remove('show');
        setTimeout(() => bar.remove(), 300);
    }, 4500);

    playNotificationSound();
    vibrate(120, 60);

    notifications.unshift({ title, body, icon, app, time: Date.now() });
    if (notifications.length > 30) notifications.pop();
    if (app) badges[app] = (badges[app] || 0) + 1;
    renderBadges();
    renderNotifCenter();
    renderLockNotifs();
}

function renderBadges() {
    els('.app-icon').forEach((icon) => {
        const slug = icon.dataset.app;
        let dot = icon.querySelector('.badge');
        const count = badges[slug] || 0;
        if (count > 0) {
            if (!dot) {
                dot = document.createElement('div');
                dot.className = 'badge';
                icon.querySelector('.glyph').appendChild(dot);
            }
            dot.textContent = count > 9 ? '9+' : String(count);
        } else if (dot) {
            dot.remove();
        }
    });
}

function renderNotifCenter() {
    const list = el('#notif-center-list');
    if (!list) return;
    if (!notifications.length) {
        list.innerHTML = `<div class="rdui-empty">${t('notif_center_empty')}</div>`;
        return;
    }
    list.innerHTML = notifications.map((n) => `
        <div class="notif-item">
            <div class="notif-icon"><i data-lucide="${n.icon || 'bell'}"></i></div>
            <div>
                <div class="notif-title">${n.title || ''}</div>
                <div class="notif-body">${n.body || ''}</div>
            </div>
        </div>
    `).join('');
    refreshIcons();
}

function renderLockNotifs() {
    const box = el('#lock-notifs');
    if (!box) return;
    box.innerHTML = notifications.slice(0, 3).map((n) => `
        <div class="lock-notif-item">
            <i data-lucide="${n.icon || 'bell'}"></i>
            <span>${n.title || ''}</span>
        </div>
    `).join('');
    refreshIcons();
}

function toggleNotifCenter() {
    el('#notif-center').classList.toggle('hidden');
}

const statusBar = el('.status-bar');
if (statusBar) statusBar.addEventListener('click', toggleNotifCenter);

const clearBtn = el('#notif-clear');
if (clearBtn) clearBtn.addEventListener('click', () => {
    notifications = [];
    badges = {};
    renderBadges();
    renderNotifCenter();
    renderLockNotifs();
});

/* ----------------------------------------------------------- Wallpaper */
function applyWallpaper() {
    const classes = ['wp-crimson', 'wp-void', 'wp-cartel', 'wp-terminal'];
    [el('#lockscreen'), el('#homescreen')].forEach((node) => {
        if (!node) return;
        classes.forEach((c) => node.classList.remove(c));
        if (settings.wallpaper === 'custom' && settings.wallpaperUrl) {
            node.style.backgroundImage = `url("${settings.wallpaperUrl}")`;
            node.style.backgroundSize = 'cover';
            node.style.backgroundPosition = 'center';
        } else {
            node.style.backgroundImage = '';
            node.classList.add('wp-' + (settings.wallpaper || 'crimson'));
        }
    });
}

/* ----------------------------------------------------------- Calls */
function showIncomingCall(callId, fromNumber) {
    currentCallId = callId;
    el('#call-number').textContent = fromNumber;
    el('#call-status-label').textContent = t('call_status_incoming');
    el('#call-overlay').classList.remove('hidden');
    el('#call-overlay').classList.remove('active-call', 'outgoing-call');
    startRingtone();
    vibrate(400, 100);
}

// Caller-side counterpart — the phone had no UI at all for the person placing
// the call, just a static "ringing" string in the dialer app that never
// updated. This puts them on the same overlay, in a distinct 'outgoing-call'
// state (no accept button — they can't accept their own call).
function showOutgoingCall(callId, toNumber) {
    currentCallId = callId;
    el('#call-number').textContent = toNumber;
    el('#call-status-label').textContent = t('call_status_ringing');
    el('#call-overlay').classList.remove('hidden');
    el('#call-overlay').classList.remove('active-call');
    el('#call-overlay').classList.add('outgoing-call');
}

el('#call-accept').addEventListener('click', async () => {
    if (!currentCallId) return;
    stopRingtone();
    await callLua('sdk:request', { action: 'acceptCall', payload: currentCallId });
    el('#call-overlay').classList.add('active-call');
    el('#call-status-label').textContent = t('call_status_connected');
    startCallTimer();
});

el('#call-decline').addEventListener('click', async () => {
    if (!currentCallId) return;
    stopRingtone();
    await callLua('sdk:request', { action: 'declineCall', payload: currentCallId });
    endCallUI();
});

el('#call-hangup').addEventListener('click', async () => {
    if (!currentCallId) return;
    await callLua('sdk:request', { action: 'hangup', payload: currentCallId });
    endCallUI();
});

function startCallTimer() {
    let seconds = 0;
    callTimerHandle = setInterval(() => {
        seconds++;
        const m = String(Math.floor(seconds / 60)).padStart(2, '0');
        const s = String(seconds % 60).padStart(2, '0');
        el('#call-duration').textContent = `${m}:${s}`;
    }, 1000);
}

function endCallUI() {
    stopRingtone();
    clearInterval(callTimerHandle);
    el('#call-overlay').classList.add('hidden');
    el('#call-overlay').classList.remove('active-call', 'outgoing-call');
    el('#call-duration').textContent = '00:00';
    currentCallId = null;
}

function closePhone() {
    callLua('close', {});
}

// ESC closes the phone — SetNuiFocus grabs keyboard input, so without this
// there is no way out of the NUI once it's open besides the same open-key,
// which toggles too (see client.lua), but ESC is the expected universal escape hatch.
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !document.body.classList.contains('hidden')) {
        closePhone();
    }
});

/* ----------------------------------------------------------- NUI messages from Lua */
window.addEventListener('message', (event) => {
    const msg = event.data;
    if (!msg || !msg.action) return;

    switch (msg.action) {
        case 'phone:open':
            document.body.classList.remove('hidden');
            initPhone();
            break;
        case 'phone:close':
            lockPhone();
            setViewfinderMode(false);
            document.body.classList.add('hidden');
            break;
        case 'call:incoming':
            showIncomingCall(msg.callId, msg.from);
            break;
        case 'call:outgoing':
            showOutgoingCall(msg.callId, msg.to);
            break;
        case 'call:accepted':
            el('#call-overlay').classList.remove('outgoing-call');
            el('#call-overlay').classList.add('active-call');
            el('#call-status-label').textContent = t('call_status_connected');
            startCallTimer();
            break;
        case 'call:ended':
            endCallUI();
            broadcastToApp('call:logUpdated', {});
            break;
        case 'sms:received':
            showNotification({ title: `SMS — ${msg.payload.from}`, body: msg.payload.body, icon: 'message-circle', app: 'sms' });
            broadcastToApp('sms:received', msg.payload);
            break;
        case 'notify:push':
            showNotification(msg.data);
            break;
        case 'phone:stateSync':
            broadcastToApp('phone:stateSync', msg.state);
            break;
        case 'apps:updated':
            loadApps();
            break;
    }
});

let initialized = false;
async function initPhone() {
    if (initialized) return;
    initialized = true;
    const s = await callLua('sdk:request', { action: 'getSettings' });
    if (s && !s.error) settings = s;
    await loadLocale();
    applyStaticTranslations();
    applyWallpaper();
    updateLockDate();
    renderNotifCenter();
    renderLockNotifs();
    await loadApps();
    refreshIcons();
}

function applyStaticTranslations() {
    const swipeHint = el('#swipe-hint-text');
    if (swipeHint) swipeHint.textContent = t('lock_swipe_hint');
    const notifTitle = el('#notif-center-title');
    if (notifTitle) notifTitle.textContent = t('notif_center_title');
    const notifClear = el('#notif-clear');
    if (notifClear) notifClear.textContent = t('notif_center_clear');
}

// Static markup (status bar, lockscreen, homescreen grid, call overlay) needs one pass —
// Lucide's UMD build doesn't auto-run, createIcons() must be called explicitly.
refreshIcons();
