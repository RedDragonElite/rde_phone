-- Deliberately global, not local: config.lua runs as its own chunk under
-- shared_scripts. A `local Config` here would only exist inside THIS file —
-- server.lua and client.lua run as separate chunks and would see a nil
-- global. `return Config` at the bottom does nothing for shared_scripts
-- (that's require() semantics, not how FXServer loads them) — omitted here
-- on purpose so nobody mistakes this for a module system.
Config = {}

Config.Debug          = true
Config.StatebagPrefix = 'rde_phone_'   -- rde_phone_<citizenid> for per-player phone state
Config.OpenKey         = 'F1'          -- keybind, only opens if PhoneItem check passes
Config.PhoneItem       = 'phone'       -- ox_inventory item required to open the phone
Config.VoiceSystem    = 'pma-voice'    -- 'pma-voice' | 'saltychat' (only pma-voice wired in v0.1)

Config.CallChannelBase = 1000          -- pma-voice call channels allocated from here up
Config.RingTimeoutMs   = 30000         -- unanswered call -> auto "missed"

Config.PhoneNumber = {
    prefix = '555',
    length = 4,                        -- 555-XXXX
}

Config.PhonePullOutAnim = true             -- pull phone from pocket on open / put away on close
Config.PhoneProp        = 'prop_amb_phone' -- vanilla GTA model, zero extra dependency
Config.PhonePropBone    = 28422            -- hand grip point (verified in production phone resources)

Config.HexColors = {
    primary = '#8b5cf6',
    success = '#22c55e',
    error   = '#ef4444',
    warning = '#f59e0b',
    info    = '#3b82f6',
}

Config.Photos = {
    maxImageBytes = 1200 * 1024,  -- ~1.2MB base64 string cap per photo (rde_crew's graffiti uses 500KB for a much simpler canvas)
    maxPerPlayer  = 60,           -- oldest photo is dropped once this is exceeded
    jpegQuality   = 0.82,         -- passed to screenshot-basic; webp/jpg only, never raw png
}

Config.Ringtones = {
    { id = 'classic', label = 'Classic' },
    { id = 'pulse',   label = 'Pulse' },
    { id = 'alert',   label = 'Alert' },
    { id = 'chime',   label = 'Chime' },
}

Config.SmsTones = {
    { id = 'ping', label = 'Ping' },
    { id = 'pop',  label = 'Pop' },
    { id = 'blip', label = 'Blip' },
    { id = 'note', label = 'Note' },
}

Config.DefaultLanguage = 'en'   -- English is the default everywhere; German is opt-in via Settings
Config.Locales = {
    en = {
        -- Lua-side (server messages, notifications)
        incoming_call    = 'Incoming call: %s',
        call_ended       = 'Call ended',
        call_missed      = 'Missed call from %s',
        no_number        = 'No player with that number',
        already_in_call  = 'You are already in a call',
        sms_sent         = 'Message sent',
        contact_added    = 'Contact added: %s',
        no_phone_item    = 'You don\'t have a phone on you',

        -- Shell / OS chrome
        os_boot_sub          = 'RED DRAGON ELITE // PHONE KERNEL',
        lock_swipe_hint      = 'Swipe up to unlock',
        notif_center_title   = 'Notifications',
        notif_center_empty   = 'No notifications',
        notif_center_clear   = 'Clear',
        call_status_ringing  = 'Calling...',
        call_status_incoming = 'Incoming call...',
        call_status_connected = 'Connected',

        -- App titles (built-ins, shown on the homescreen grid)
        app_sms_title      = 'Messages',
        app_calls_title    = 'Calls',
        app_contacts_title = 'Contacts',
        app_settings_title = 'Settings',
        app_camera_title   = 'Camera',
        app_gallery_title  = 'Gallery',
        photo_saved        = 'Photo saved',
        photo_deleted      = 'Photo deleted',
        photo_too_large    = 'Photo too large — try again',
        gallery_empty      = 'No photos yet',
        gallery_limit_note = 'Oldest photo removed to make room',
        set_as_wallpaper   = 'Set as Wallpaper',
        wallpaper_set      = 'Wallpaper updated',

        -- SMS app
        sms_empty_threads   = 'No messages yet',
        sms_load_error      = 'Couldn\'t load — wait a moment and reopen',
        sms_you_prefix      = 'You: ',
        sms_new_message     = 'New Message',
        sms_placeholder_num = '555-0000',
        sms_placeholder_msg = 'Message...',
        sms_cancel          = 'Cancel',
        sms_continue        = 'Continue',

        -- Calls app
        calls_empty_log     = 'No calls yet',
        calls_load_error    = 'Couldn\'t load — wait a moment and reopen',
        calls_your_number   = 'Your number: %s',
        calls_calling       = 'Calling...',
        calls_ringing       = 'Ringing...',
        calls_error         = 'Error',
        calls_outgoing      = 'Outgoing',
        calls_incoming      = 'Incoming',
        calls_answered      = 'Answered',
        calls_missed        = 'Missed',
        calls_declined      = 'Declined',

        -- Contacts app
        contacts_empty       = 'No contacts yet',
        contacts_add_title   = 'Add Contact',
        contacts_name        = 'Name',
        contacts_cancel      = 'Cancel',
        contacts_save        = 'Save',
        contacts_open_sms    = 'Open the Messages app for this chat',
        contacts_open_sms_title = 'Messages',

        -- Settings app
        settings_wallpaper       = 'Wallpaper',
        settings_wallpaper_custom = 'Custom (Image URL)',
        settings_wallpaper_url_placeholder = 'https://...',
        settings_wallpaper_apply = 'Apply',
        settings_sound_section   = 'Sound & Vibration',
        settings_ringtone        = 'Ringtone',
        settings_sms_tone        = 'Message Tone',
        settings_vibration       = 'Vibration',
        settings_language        = 'Language',
        settings_saved           = 'Saved',
        settings_preview         = 'Preview',
    },
    de = {
        incoming_call    = 'Anruf von: %s',
        call_ended       = 'Anruf beendet',
        call_missed      = 'Verpasster Anruf von %s',
        no_number        = 'Keine Person mit dieser Nummer',
        already_in_call  = 'Du bist bereits in einem Anruf',
        sms_sent         = 'Nachricht gesendet',
        contact_added    = 'Kontakt hinzugefügt: %s',
        no_phone_item    = 'Du hast kein Handy dabei',

        os_boot_sub          = 'RED DRAGON ELITE // PHONE KERNEL',
        lock_swipe_hint      = 'Nach oben wischen zum Entsperren',
        notif_center_title   = 'Benachrichtigungen',
        notif_center_empty   = 'Keine Benachrichtigungen',
        notif_center_clear   = 'Leeren',
        call_status_ringing  = 'Anruf...',
        call_status_incoming = 'Eingehender Anruf...',
        call_status_connected = 'Verbunden',

        app_sms_title      = 'Nachrichten',
        app_calls_title    = 'Anrufe',
        app_contacts_title = 'Kontakte',
        app_settings_title = 'Einstellungen',
        app_camera_title   = 'Kamera',
        app_gallery_title  = 'Galerie',
        photo_saved        = 'Foto gespeichert',
        photo_deleted      = 'Foto gelöscht',
        photo_too_large    = 'Foto zu groß — nochmal versuchen',
        gallery_empty      = 'Noch keine Fotos',
        gallery_limit_note = 'Ältestes Foto entfernt, um Platz zu schaffen',
        set_as_wallpaper   = 'Als Hintergrund festlegen',
        wallpaper_set      = 'Hintergrund aktualisiert',

        sms_empty_threads   = 'Noch keine Nachrichten',
        sms_load_error      = 'Konnte nicht laden — kurz warten und nochmal öffnen',
        sms_you_prefix      = 'Du: ',
        sms_new_message     = 'Neue Nachricht',
        sms_placeholder_num = '555-0000',
        sms_placeholder_msg = 'Nachricht...',
        sms_cancel          = 'Abbrechen',
        sms_continue        = 'Weiter',

        calls_empty_log     = 'Keine Anrufe bisher',
        calls_load_error    = 'Konnte nicht laden — kurz warten und nochmal öffnen',
        calls_your_number   = 'Deine Nummer: %s',
        calls_calling       = 'Rufe an...',
        calls_ringing       = 'Klingelt...',
        calls_error         = 'Fehler',
        calls_outgoing      = 'Ausgehend',
        calls_incoming      = 'Eingehend',
        calls_answered      = 'Angenommen',
        calls_missed        = 'Verpasst',
        calls_declined      = 'Abgelehnt',

        contacts_empty       = 'Noch keine Kontakte',
        contacts_add_title   = 'Kontakt hinzufügen',
        contacts_name        = 'Name',
        contacts_cancel      = 'Abbrechen',
        contacts_save        = 'Speichern',
        contacts_open_sms    = 'Öffne die Nachrichten-App für den Chat',
        contacts_open_sms_title = 'Nachrichten',

        settings_wallpaper       = 'Wallpaper',
        settings_wallpaper_custom = 'Eigenes (Bild-URL)',
        settings_wallpaper_url_placeholder = 'https://...',
        settings_wallpaper_apply = 'Übernehmen',
        settings_sound_section   = 'Ton & Vibration',
        settings_ringtone        = 'Klingelton',
        settings_sms_tone        = 'Nachrichtenton',
        settings_vibration       = 'Vibration',
        settings_language        = 'Sprache',
        settings_saved           = 'Gespeichert',
        settings_preview         = 'Vorhören',
    },
}

function Config.GetString(key, ...)
    local lang = Config.Locales[Config.DefaultLanguage] or Config.Locales['en']
    local str  = lang[key] or key
    if ... then return string.format(str, ...) end
    return str
end
