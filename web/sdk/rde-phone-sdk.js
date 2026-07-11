/**
 * RDE Phone App-SDK — v0.2
 * ---------------------------------------------------------
 * Include this ONE script in your app's index.html. That's it.
 * No React, no bundler, no Module Federation, no NUI knowledge required.
 *
 *   <script src="../../sdk/rde-phone-sdk.js"></script>
 *
 * Your app runs inside a sandboxed <iframe>. It NEVER talks to
 * Lua directly — it only talks to this SDK, which talks to the
 * phone shell (parent window) via postMessage, which is the only
 * thing allowed to call into the resource's NUI callback.
 *
 * API:
 *   RDEPhone.request(action, payload) -> Promise<result>
 *   RDEPhone.on(event, callback)
 *   RDEPhone.notify({ title, body, icon })
 *   RDEPhone.close()
 *   RDEPhone.t(key, ...args) -> localized string (config-driven, see config.lua Config.Locales)
 *   RDEPhone.ready -> Promise, resolves once locale + player language are loaded.
 *                      Await this before your app's first render.
 *   RDEPhone.getLanguage() -> 'en' | 'de' | ...
 */
(function (global) {
    const pending = new Map();
    let reqId = 0;

    const listeners = {};

    window.addEventListener('message', (event) => {
        const msg = event.data;
        if (!msg || msg.source !== 'rde_phone_shell') return;

        if (msg.type === 'response' && pending.has(msg.reqId)) {
            const { resolve, reject } = pending.get(msg.reqId);
            pending.delete(msg.reqId);
            if (msg.result && msg.result.error) reject(msg.result);
            else resolve(msg.result);
            return;
        }

        if (msg.type === 'event' && listeners[msg.event]) {
            listeners[msg.event].forEach((cb) => cb(msg.data));
        }
    });

    const RDEPhone = {
        /** Call any rde_phone:server:* callback registered on the Lua side. */
        request(action, payload) {
            return new Promise((resolve, reject) => {
                const id = ++reqId;
                pending.set(id, { resolve, reject });
                window.parent.postMessage(
                    { source: 'rde_phone_app', type: 'request', reqId: id, action, payload },
                    '*'
                );
                setTimeout(() => {
                    if (pending.has(id)) {
                        pending.delete(id);
                        reject({ error: true, message: 'timeout' });
                    }
                }, 8000);
            });
        },

        /** Subscribe to push events from the shell (sms:received, call:*, phone:stateSync, ...). */
        on(event, callback) {
            (listeners[event] ||= []).push(callback);
        },

        /** Fire a native-looking OS notification (banner + sound) from inside your app. */
        notify({ title, body, icon } = {}) {
            window.parent.postMessage(
                { source: 'rde_phone_app', type: 'notify', data: { title, body, icon } },
                '*'
            );
        },

        /** Ask the shell to close the phone entirely. */
        close() {
            window.parent.postMessage({ source: 'rde_phone_app', type: 'close' }, '*');
        },

        /**
         * Toggle "viewfinder mode" — the shell drops the phone bezel/blur
         * and goes fullscreen-transparent so the actual game world shows
         * through, with your app's own minimal chrome floating on top.
         * Built for the Camera app; any app can use it for a similar
         * full-bleed moment. Always call setViewfinder(false) when your
         * app is done (on close, on tab switch away) — the shell doesn't
         * do this automatically.
         */
        setViewfinder(enabled) {
            window.parent.postMessage({ source: 'rde_phone_app', type: 'viewfinder', enabled: !!enabled }, '*');
        },
    };

    /* -----------------------------------------------------------
     * i18n — config-driven, single source of truth in config.lua's
     * Config.Locales. Loaded once per app instance; apps should
     * `await RDEPhone.ready` before their first render.
     * --------------------------------------------------------- */
    let _locales = null;
    let _lang = 'en';
    let _readyResolve;
    RDEPhone.ready = new Promise((resolve) => { _readyResolve = resolve; });

    RDEPhone.t = function (key, ...args) {
        const table = (_locales && (_locales[_lang] || _locales.en)) || {};
        let str = table[key] || key;
        args.forEach((a) => { str = str.replace('%s', a); });
        return str;
    };
    RDEPhone.getLanguage = () => _lang;

    async function loadLocale() {
        const [localeData, settings] = await Promise.all([
            RDEPhone.request('getLocaleData').catch(() => null),
            RDEPhone.request('getSettings').catch(() => null),
        ]);
        if (localeData && localeData.locales) _locales = localeData.locales;
        _lang = (settings && settings.language)
            || (localeData && localeData.defaultLanguage)
            || 'en';
        _readyResolve();
    }
    loadLocale();

    global.RDEPhone = RDEPhone;
})(window);
