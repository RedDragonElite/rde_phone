/**
 * WYRM OS — shared tone generator.
 * No audio files, generated live via Web Audio API — zero dependencies.
 * Shared between web/js/phone.js (actual playback) and the settings app
 * (preview button), so "what you hear when picking a tone" always matches
 * "what actually plays" exactly — one definition, not two.
 */
(function (global) {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    let actx = null;

    function ensureAudio() {
        if (!actx) actx = new AudioCtx();
        // Chromium (and FiveM's CEF NUI) creates every AudioContext in a
        // 'suspended' state until a real user gesture (click/keydown) resumes
        // it. An incoming call auto-opens the phone via a server event —
        // that's not a gesture, so if the player hadn't clicked inside the
        // NUI yet this session, the context just sat suspended and every
        // osc.start() queued into dead air: no error, no sound. resume() is
        // a cheap no-op once already running, so it's safe to call every time.
        if (actx.state === 'suspended') actx.resume().catch(() => {});
        return actx;
    }

    // Belt-and-braces: grab the very first real interaction anywhere in the
    // NUI (unlocking the lockscreen, tapping an app icon, etc.) and use it
    // to resume the context immediately, instead of waiting for the next
    // beep() call to discover it's suspended.
    function unlockOnFirstGesture() {
        ensureAudio();
        document.removeEventListener('pointerdown', unlockOnFirstGesture);
        document.removeEventListener('keydown', unlockOnFirstGesture);
    }
    document.addEventListener('pointerdown', unlockOnFirstGesture);
    document.addEventListener('keydown', unlockOnFirstGesture);

    function beep(freq, duration, delay = 0, gain = 0.15) {
        const ctx = ensureAudio();
        const osc = ctx.createOscillator();
        const g = ctx.createGain();
        osc.type = 'sine';
        osc.frequency.value = freq;
        g.gain.value = gain;
        osc.connect(g).connect(ctx.destination);
        const t0 = ctx.currentTime + delay;
        osc.start(t0);
        g.gain.setValueAtTime(gain, t0);
        g.gain.exponentialRampToValueAtTime(0.0001, t0 + duration);
        osc.stop(t0 + duration + 0.02);
    }

    const RINGTONES = {
        classic: () => { beep(880, 0.35, 0); beep(660, 0.35, 0.4); },
        pulse:   () => { beep(740, 0.15, 0); beep(740, 0.15, 0.2); beep(740, 0.15, 0.4); },
        alert:   () => { beep(1200, 0.12, 0); beep(900, 0.12, 0.15); beep(1200, 0.12, 0.3); beep(900, 0.12, 0.45); },
        chime:   () => { beep(523, 0.3, 0); beep(659, 0.3, 0.15); beep(784, 0.4, 0.3); },
    };

    const SMS_TONES = {
        ping: () => { beep(1046, 0.09, 0); beep(1568, 0.12, 0.1); },
        pop:  () => { beep(600, 0.06, 0); beep(900, 0.08, 0.05); },
        blip: () => { beep(1800, 0.05, 0); },
        note: () => { beep(784, 0.1, 0); beep(988, 0.14, 0.1); },
    };

    global.RDEAudio = {
        beep,
        playRingtonePattern(id) { (RINGTONES[id] || RINGTONES.classic)(); },
        playSmsTonePattern(id) { (SMS_TONES[id] || SMS_TONES.ping)(); },
        ringtoneIds: Object.keys(RINGTONES),
        smsToneIds: Object.keys(SMS_TONES),
    };
})(window);
