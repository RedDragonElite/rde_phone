-----------------------------------------------------------
-- rde_phone / server / server.lua
-- Core: identity, numbers, contacts, sms, call state machine
-----------------------------------------------------------

local State = {
    numbers      = {},   -- [identifier] = '555-1234'
    onlineByNum  = {},   -- ['555-1234'] = source
    calls        = {},   -- [callId] = { caller, callee, channel, status, startedAt }
    freeChannels = {},
}
local PlayerLanguage = {}   -- [identifier] = 'en' | 'de' — cheap in-memory cache, populated by getSettings/setSettings

local NextChannel = Config.CallChannelBase

local function Log(msg, level)
    if not Config.Debug and level ~= 'ERROR' then return end
    local prefix = level == 'ERROR' and '^1' or level == 'WARN' and '^3' or '^2'
    print(('%s[RDE_PHONE %s]^7 %s'):format(prefix, level or 'INFO', msg))
end

local function GetIdentifier(source)
    local player = Ox.GetPlayer(source)
    if not player then return nil end
    if player.stateId then return player.stateId end
    if player.charId  then return tostring(player.charId) end
    return nil
end

local function AllocateChannel()
    if #State.freeChannels > 0 then
        return table.remove(State.freeChannels)
    end
    NextChannel = NextChannel + 1
    return NextChannel
end

local function ReleaseChannel(ch)
    State.freeChannels[#State.freeChannels + 1] = ch
end

-----------------------------------------------------------
-- App Registry — Phase 3
-- Any resource (including this one, for its own built-in apps)
-- registers a phone app through ONE export. No special-casing
-- between "core" and "third-party" apps — same path for both.
-----------------------------------------------------------

local AppRegistry = {}   -- [slug] = { slug, title, icon, url, order }

--- Register (or update) a phone app.
--- @param def table { slug, title, icon (lucide name), url (full https://cfx-nui-... URL), order? }
local function RegisterPhoneApp(def)
    if not def or not def.slug or not (def.title or def.titleKey) or not def.icon or not def.url then
        Log(('RegisterPhoneApp: rejected invalid app definition (%s)'):format(json.encode(def or {})), 'ERROR')
        return false
    end
    AppRegistry[def.slug] = {
        slug          = def.slug,
        title         = def.title,      -- literal, for 3rd-party apps
        titleKey      = def.titleKey,   -- translation key, for built-ins (resolved per-player in GetSortedApps)
        icon          = def.icon,
        color         = def.color,      -- optional hex, e.g. '#3b82f6' — developer-set icon tint, not user-configurable
        url           = def.url,
        order         = def.order or 100,
        ownerResource = GetInvokingResource() or GetCurrentResourceName(),
    }
    Log(('App registered: %s -> %s'):format(def.slug, def.url))
    TriggerClientEvent('rde_phone:client:appsUpdated', -1)
    return true
end
exports('RegisterPhoneApp', RegisterPhoneApp)

local function UnregisterPhoneApp(slug)
    if not AppRegistry[slug] then return end
    AppRegistry[slug] = nil
    TriggerClientEvent('rde_phone:client:appsUpdated', -1)
end
exports('UnregisterPhoneApp', UnregisterPhoneApp)

--- Sorted app list with titles resolved for the requesting player's language.
--- `source` is optional — omit it to get literal titles/keys unresolved.
local function GetSortedApps(source)
    local lang = Config.DefaultLanguage
    if source then
        local identifier = GetIdentifier(source)
        if identifier and PlayerLanguage[identifier] then
            lang = PlayerLanguage[identifier]
        end
    end

    local list = {}
    for _, app in pairs(AppRegistry) do
        local title = app.title
        if not title and app.titleKey then
            local strings = Config.Locales[lang] or Config.Locales[Config.DefaultLanguage]
            title = (strings and strings[app.titleKey]) or app.titleKey
        end
        list[#list + 1] = { slug = app.slug, title = title, icon = app.icon, color = app.color, url = app.url, order = app.order }
    end
    table.sort(list, function(a, b)
        if a.order == b.order then return a.slug < b.slug end
        return a.order < b.order
    end)
    return list
end

local function SelfUrl(path)
    return ('https://cfx-nui-%s/%s'):format(GetCurrentResourceName(), path)
end

--- The 4 built-in apps go through the EXACT same registration path a
--- third-party resource would use. This is the proof the architecture
--- holds — no special treatment for "ours" vs "theirs". They use titleKey
--- instead of title so their homescreen label follows Settings > Language.
local function RegisterBuiltInApps()
    RegisterPhoneApp({ slug = 'calls',    titleKey = 'app_calls_title',    icon = 'phone',           color = '#00ff00', url = SelfUrl('web/apps/calls/index.html'),    order = 10 })
    RegisterPhoneApp({ slug = 'sms',      titleKey = 'app_sms_title',      icon = 'message-circle', color = '#0096ff', url = SelfUrl('web/apps/sms/index.html'),      order = 20 })
    RegisterPhoneApp({ slug = 'contacts', titleKey = 'app_contacts_title', icon = 'users',           color = '#8b5cf6', url = SelfUrl('web/apps/contacts/index.html'), order = 30 })
    RegisterPhoneApp({ slug = 'camera',   titleKey = 'app_camera_title',   icon = 'camera',          color = '#ec4899', url = SelfUrl('web/apps/camera/index.html'),   order = 35 })
    RegisterPhoneApp({ slug = 'gallery',  titleKey = 'app_gallery_title',  icon = 'image',           color = '#14b8a6', url = SelfUrl('web/apps/gallery/index.html'),  order = 36 })
    RegisterPhoneApp({ slug = 'settings', titleKey = 'app_settings_title', icon = 'settings',        color = '#f59e0b', url = SelfUrl('web/apps/settings/index.html'), order = 90 })
end

-- A third-party resource calling exports.rde_phone:RegisterPhoneApp(...) during
-- its OWN onResourceStart will fail if rde_phone hasn't started yet (export
-- doesn't exist). This event covers that ordering race: any resource can
-- listen for it and (re)register whenever rde_phone comes up.
AddEventHandler('onResourceStart', function(name)
    if name ~= GetCurrentResourceName() then return end
    RegisterBuiltInApps()
    TriggerEvent('rde_phone:ready')
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then return end
    -- Third-party app resource stopped — pull its app out of the grid
    -- rather than leaving a dead icon pointing at a 404.
    local changed = false
    for slug, app in pairs(AppRegistry) do
        if app.ownerResource == name then
            AppRegistry[slug] = nil
            changed = true
        end
    end
    if changed then TriggerClientEvent('rde_phone:client:appsUpdated', -1) end
end)

-----------------------------------------------------------
-- Database
-----------------------------------------------------------

local DatabaseReady = false

-- Any callback that touches the DB calls this first. Normally a no-op
-- (SetupDatabase already finished by the time a player can act), but it's
-- a correct safety net instead of hoping the timing always works out.
local function WaitForDatabase()
    local attempts = 0
    while not DatabaseReady and attempts < 100 do Wait(50); attempts = attempts + 1 end
    return DatabaseReady
end

local function SetupDatabase()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `rde_phone_numbers` (
            `identifier` VARCHAR(64)  NOT NULL PRIMARY KEY,
            `number`     VARCHAR(16)  NOT NULL UNIQUE,
            `created_at` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `rde_phone_contacts` (
            `id`         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            `owner`      VARCHAR(64)  NOT NULL,
            `number`     VARCHAR(16)  NOT NULL,
            `name`       VARCHAR(64)  NOT NULL,
            `avatar`     VARCHAR(255) DEFAULT NULL,
            `created_at` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_owner` (`owner`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `rde_phone_sms` (
            `id`         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            `from_num`   VARCHAR(16)  NOT NULL,
            `to_num`     VARCHAR(16)  NOT NULL,
            `body`       TEXT         NOT NULL,
            `read_at`    TIMESTAMP    NULL DEFAULT NULL,
            `created_at` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_thread` (`from_num`, `to_num`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `rde_phone_settings` (
            `owner`        VARCHAR(64)  NOT NULL PRIMARY KEY,
            `wallpaper`    VARCHAR(32)  NOT NULL DEFAULT 'crimson',
            `wallpaper_url` LONGTEXT      NULL DEFAULT NULL,
            `ringtone`     TINYINT(1)   NOT NULL DEFAULT 1,
            `ringtone_id`  VARCHAR(32)  NOT NULL DEFAULT 'classic',
            `sms_tone_id`  VARCHAR(32)  NOT NULL DEFAULT 'ping',
            `vibration`    TINYINT(1)   NOT NULL DEFAULT 1,
            `language`     VARCHAR(8)   NOT NULL DEFAULT 'en'
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    -- Migration for installs that already had the old 3-column settings table —
    -- CREATE TABLE IF NOT EXISTS is a no-op once the table exists, so new
    -- columns need to be added explicitly. MariaDB/MySQL 8+ both support
    -- ADD COLUMN IF NOT EXISTS; each runs independently so one failing
    -- (e.g. on very old MySQL without the IF NOT EXISTS clause) won't
    -- block the others.
    for _, stmt in ipairs({
        "ALTER TABLE `rde_phone_settings` ADD COLUMN IF NOT EXISTS `wallpaper_url` LONGTEXT NULL DEFAULT NULL",
        "ALTER TABLE `rde_phone_settings` MODIFY COLUMN `wallpaper_url` LONGTEXT NULL DEFAULT NULL", -- widen if it already existed as VARCHAR(512)
        "ALTER TABLE `rde_phone_settings` ADD COLUMN IF NOT EXISTS `ringtone_id` VARCHAR(32) NOT NULL DEFAULT 'classic'",
        "ALTER TABLE `rde_phone_settings` ADD COLUMN IF NOT EXISTS `sms_tone_id` VARCHAR(32) NOT NULL DEFAULT 'ping'",
        "ALTER TABLE `rde_phone_settings` ADD COLUMN IF NOT EXISTS `language` VARCHAR(8) NOT NULL DEFAULT 'en'",
    }) do
        pcall(function() MySQL.query.await(stmt) end)
    end
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `rde_phone_calls` (
            `id`         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            `caller_num` VARCHAR(16)  NOT NULL,
            `callee_num` VARCHAR(16)  NOT NULL,
            `status`     VARCHAR(16)  NOT NULL,   -- answered | missed | declined
            `duration`   INT UNSIGNED DEFAULT 0,
            `created_at` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    -- Photos — same pattern proven in rde_crew's graffiti storage: base64
    -- image data URI straight in a LONGTEXT column, no file storage, no
    -- external host. Captured via screenshot-basic, never uploaded anywhere.
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `rde_phone_photos` (
            `id`         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            `owner`      VARCHAR(64)  NOT NULL,
            `image_data` LONGTEXT     NOT NULL,
            `created_at` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_owner` (`owner`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    DatabaseReady = true
end

local function GenerateNumber()
    local num
    repeat
        num = ('%s-%0' .. Config.PhoneNumber.length .. 'd'):format(
            Config.PhoneNumber.prefix, math.random(0, 10 ^ Config.PhoneNumber.length - 1))
        local existing = MySQL.scalar.await('SELECT 1 FROM rde_phone_numbers WHERE number = ?', { num })
    until not existing
    return num
end

--- Resolve (or create) a player's phone number.
--- @param identifier string  ox_core stateId/charId
--- @param source? number  if given, also (re)registers State.onlineByNum so
---                        calls can route to this player right away. This
---                        makes the online map self-healing on every phone
---                        touch (getIdentity, startCall, ...) instead of
---                        relying on a single connect-time event — which
---                        also survives a mid-session /restart rde_phone.
local function GetOrCreateNumber(identifier, source)
    local number = State.numbers[identifier]
    if not number then
        local row = MySQL.single.await('SELECT number FROM rde_phone_numbers WHERE identifier = ?', { identifier })
        number = row and row.number
        if not number then
            number = GenerateNumber()
            MySQL.insert.await('INSERT INTO rde_phone_numbers (identifier, number) VALUES (?, ?)', { identifier, number })
        end
        State.numbers[identifier] = number
    end
    if source then State.onlineByNum[number] = source end
    return number
end

-----------------------------------------------------------
-- Statebag helper — Golden Rule: one sync path per change
-----------------------------------------------------------

local function UpdatePhoneState(identifier, data)
    local key = Config.StatebagPrefix .. identifier
    if data then
        GlobalState[key] = data
    else
        GlobalState[key] = { _deleted = true }
        SetTimeout(1000, function() GlobalState[key] = nil end)
    end
end

-----------------------------------------------------------
-- Call state machine (pma-voice)
-----------------------------------------------------------

local function EndCall(callId, status)
    local call = State.calls[callId]
    if not call then return end
    State.calls[callId] = nil
    ReleaseChannel(call.channel)

    -- npwd (proven, was working) only ever calls the CLIENT-side pma-voice
    -- export, from each participant's own client — never a server export.
    -- Dropped exports['pma-voice']:setPlayerCall(source, 0) here to match
    -- that exactly instead of running two parallel paths to the same state.
    TriggerClientEvent('rde_phone:client:pmaVoiceCallEnd', call.callerSrc)
    if call.calleeSrc then TriggerClientEvent('rde_phone:client:pmaVoiceCallEnd', call.calleeSrc) end

    local duration = call.startedAt and (os.time() - call.startedAt) or 0
    MySQL.insert.await('INSERT INTO rde_phone_calls (caller_num, callee_num, status, duration) VALUES (?, ?, ?, ?)',
        { call.callerNum, call.calleeNum, status, duration })

    UpdatePhoneState(call.callerIdentifier, nil)
    if call.calleeIdentifier then UpdatePhoneState(call.calleeIdentifier, nil) end

    if call.callerSrc then TriggerClientEvent('rde_phone:client:callEnded', call.callerSrc, status) end
    if call.calleeSrc then TriggerClientEvent('rde_phone:client:callEnded', call.calleeSrc, status) end
end

lib.callback.register('rde_phone:server:startCall', function(source, targetNumber)
    local identifier = GetIdentifier(source)
    if not identifier then return { error = true } end

    for _, call in pairs(State.calls) do
        if call.callerSrc == source or call.calleeSrc == source then
            return { error = true, message = Config.GetString('already_in_call') }
        end
    end

    local calleeSrc = State.onlineByNum[targetNumber]
    if not calleeSrc then
        return { error = true, message = Config.GetString('no_number') }
    end
    if (exports.ox_inventory:Search(calleeSrc, 'count', Config.PhoneItem) or 0) <= 0 then
        return { error = true, message = Config.GetString('no_number') }
    end

    local callerNum = GetOrCreateNumber(identifier, source)
    local calleeIdentifier = GetIdentifier(calleeSrc)
    local channel = AllocateChannel()
    local callId  = ('call_%x%x'):format(os.time(), math.random(100000, 999999))

    State.calls[callId] = {
        callId = callId,
        callerSrc = source, callerIdentifier = identifier, callerNum = callerNum,
        calleeSrc = calleeSrc, calleeIdentifier = calleeIdentifier, calleeNum = targetNumber,
        channel = channel, status = 'ringing', startedAt = nil,
    }

    UpdatePhoneState(identifier, { callId = callId, role = 'caller', peer = targetNumber, status = 'ringing' })
    UpdatePhoneState(calleeIdentifier, { callId = callId, role = 'callee', peer = callerNum, status = 'ringing' })

    TriggerClientEvent('rde_phone:client:incomingCall', calleeSrc, callId, callerNum)
    -- npwd opens its call modal on BOTH sides in handleStartCall — caller gets
    -- it locally, callee gets it via the broadcast. We only ever wired the
    -- callee (incomingCall above); the caller had no overlay at all and was
    -- stuck showing the static "ringing" text in the dialer forever, with no
    -- way to see when the call connected. This closes that gap.
    TriggerClientEvent('rde_phone:client:outgoingCall', source, callId, targetNumber)

    SetTimeout(Config.RingTimeoutMs, function()
        local call = State.calls[callId]
        if call and call.status == 'ringing' then
            EndCall(callId, 'missed')
        end
    end)

    return { ok = true, callId = callId }
end)

lib.callback.register('rde_phone:server:acceptCall', function(source, callId)
    local call = State.calls[callId]
    if not call or call.calleeSrc ~= source then return { error = true } end

    call.status    = 'active'
    call.startedAt = os.time()

    -- Client-only path (see EndCall comment above) — no server-side export here.
    TriggerClientEvent('rde_phone:client:pmaVoiceCallStart', call.callerSrc, call.channel)
    TriggerClientEvent('rde_phone:client:pmaVoiceCallStart', call.calleeSrc, call.channel)
    -- Caller's overlay is sitting in the "outgoing" state (see startCall) —
    -- flip it to connected now, same as the callee's #call-accept click does locally.
    TriggerClientEvent('rde_phone:client:callAccepted', call.callerSrc, callId)

    UpdatePhoneState(call.callerIdentifier, { callId = callId, role = 'caller', peer = call.calleeNum, status = 'active', startedAt = call.startedAt })
    UpdatePhoneState(call.calleeIdentifier, { callId = callId, role = 'callee', peer = call.callerNum, status = 'active', startedAt = call.startedAt })

    return { ok = true }
end)

lib.callback.register('rde_phone:server:declineCall', function(source, callId)
    local call = State.calls[callId]
    if not call then return { error = true } end
    EndCall(callId, 'declined')
    return { ok = true }
end)

lib.callback.register('rde_phone:server:hangup', function(source, callId)
    local call = State.calls[callId]
    if not call then return { error = true } end
    EndCall(callId, call.status == 'active' and 'answered' or 'missed')
    return { ok = true }
end)

-----------------------------------------------------------
-- SDK-facing callbacks: identity / contacts / sms
-- Every 3rd-party app talks to the phone through THESE, never
-- directly to another resource's server events.
-----------------------------------------------------------

lib.callback.register('rde_phone:server:getApps', function(source)
    return GetSortedApps(source)
end)

lib.callback.register('rde_phone:server:canOpen', function(source)
    local count = exports.ox_inventory:Search(source, 'count', Config.PhoneItem)
    return { ok = (count or 0) > 0 }
end)

lib.callback.register('rde_phone:server:getIdentity', function(source)
    if not WaitForDatabase() then return { error = true } end
    local identifier = GetIdentifier(source)
    if not identifier then return { error = true } end
    return { number = GetOrCreateNumber(identifier, source) }
end)

lib.callback.register('rde_phone:server:getContacts', function(source)
    if not WaitForDatabase() then return {} end
    local identifier = GetIdentifier(source)
    if not identifier then return {} end
    return MySQL.query.await('SELECT id, number, name, avatar FROM rde_phone_contacts WHERE owner = ?', { identifier }) or {}
end)

lib.callback.register('rde_phone:server:addContact', function(source, payload)
    if not WaitForDatabase() then return { error = true } end
    local identifier = GetIdentifier(source)
    if not identifier or not payload or not payload.number or not payload.name then return { error = true } end
    MySQL.insert.await('INSERT INTO rde_phone_contacts (owner, number, name, avatar) VALUES (?, ?, ?, ?)',
        { identifier, payload.number, payload.name, payload.avatar })
    return { ok = true }
end)

-----------------------------------------------------------
-- Generic push-notification API — lets ANY resource show a
-- native phone toast for a player, even if that resource's own
-- app isn't currently open (or the phone itself is closed —
-- silently no-ops then, same as a real phone not vibrating in
-- a drawer). Gated by phone possession, same as SMS delivery.
--
--   exports.rde_phone:PushNotification(source, {
--       title = 'Bank', body = 'Wire received: $500', icon = 'landmark', app = 'banking'
--   })
-----------------------------------------------------------
local function PushNotification(source, data)
    if not source or not data or not data.title then return false end
    if (exports.ox_inventory:Search(source, 'count', Config.PhoneItem) or 0) <= 0 then return false end
    TriggerClientEvent('rde_phone:client:pushNotification', source, {
        title = data.title,
        body  = data.body,
        icon  = data.icon or 'bell',
        app   = data.app,
    })
    return true
end
exports('PushNotification', PushNotification)

lib.callback.register('rde_phone:server:sendSms', function(source, payload)
    if not WaitForDatabase() then return { error = true } end
    local identifier = GetIdentifier(source)
    if not identifier or not payload or not payload.to or not payload.body then return { error = true } end
    local fromNum = GetOrCreateNumber(identifier)
    MySQL.insert.await('INSERT INTO rde_phone_sms (from_num, to_num, body) VALUES (?, ?, ?)',
        { fromNum, payload.to, payload.body })

    local targetSrc = State.onlineByNum[payload.to]
    if targetSrc and (exports.ox_inventory:Search(targetSrc, 'count', Config.PhoneItem) or 0) > 0 then
        TriggerClientEvent('rde_phone:client:smsReceived', targetSrc, { from = fromNum, body = payload.body })
    end
    return { ok = true }
end)

local DefaultSettings = {
    wallpaper    = 'crimson',
    wallpaperUrl = nil,
    ringtone     = true,
    ringtoneId   = 'classic',
    smsToneId    = 'ping',
    vibration    = true,
    language     = Config.DefaultLanguage,
}

lib.callback.register('rde_phone:server:getLocaleData', function(source)
    return {
        defaultLanguage = Config.DefaultLanguage,
        locales         = Config.Locales,
        ringtones       = Config.Ringtones,
        smsTones        = Config.SmsTones,
    }
end)

lib.callback.register('rde_phone:server:getSettings', function(source)
    if not WaitForDatabase() then return DefaultSettings end
    local identifier = GetIdentifier(source)
    if not identifier then return DefaultSettings end
    local row = MySQL.single.await(
        'SELECT wallpaper, wallpaper_url, ringtone, ringtone_id, sms_tone_id, vibration, language FROM rde_phone_settings WHERE owner = ?',
        { identifier })
    if not row then
        MySQL.insert.await('INSERT INTO rde_phone_settings (owner) VALUES (?)', { identifier })
        PlayerLanguage[identifier] = DefaultSettings.language
        return DefaultSettings
    end
    PlayerLanguage[identifier] = row.language
    return {
        wallpaper    = row.wallpaper,
        wallpaperUrl = row.wallpaper_url,
        ringtone     = row.ringtone == 1,
        ringtoneId   = row.ringtone_id,
        smsToneId    = row.sms_tone_id,
        vibration    = row.vibration == 1,
        language     = row.language,
    }
end)

lib.callback.register('rde_phone:server:setSettings', function(source, payload)
    if not WaitForDatabase() then return { error = true } end
    local identifier = GetIdentifier(source)
    if not identifier or not payload then return { error = true } end
    MySQL.query.await([[
        INSERT INTO rde_phone_settings (owner, wallpaper, wallpaper_url, ringtone, ringtone_id, sms_tone_id, vibration, language)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            wallpaper = VALUES(wallpaper), wallpaper_url = VALUES(wallpaper_url),
            ringtone = VALUES(ringtone), ringtone_id = VALUES(ringtone_id),
            sms_tone_id = VALUES(sms_tone_id), vibration = VALUES(vibration),
            language = VALUES(language)
    ]], {
        identifier,
        payload.wallpaper or 'crimson',
        payload.wallpaperUrl,
        payload.ringtone and 1 or 0,
        payload.ringtoneId or 'classic',
        payload.smsToneId or 'ping',
        payload.vibration and 1 or 0,
        payload.language or Config.DefaultLanguage,
    })
    PlayerLanguage[identifier] = payload.language or Config.DefaultLanguage
    -- Language change affects built-in app titles too — push a refreshed grid.
    TriggerClientEvent('rde_phone:client:appsUpdated', source)
    return { ok = true }
end)

lib.callback.register('rde_phone:server:getThreads', function(source)
    if not WaitForDatabase() then return {} end
    local identifier = GetIdentifier(source)
    if not identifier then return {} end
    local myNum = GetOrCreateNumber(identifier)
    return MySQL.query.await([[
        SELECT other_num, body, created_at, from_num FROM (
            SELECT
                CASE WHEN from_num = ? THEN to_num ELSE from_num END AS other_num,
                body, created_at, from_num,
                ROW_NUMBER() OVER (
                    PARTITION BY (CASE WHEN from_num = ? THEN to_num ELSE from_num END)
                    ORDER BY created_at DESC
                ) AS rn
            FROM rde_phone_sms WHERE from_num = ? OR to_num = ?
        ) t WHERE rn = 1 ORDER BY created_at DESC
    ]], { myNum, myNum, myNum, myNum }) or {}
end)

lib.callback.register('rde_phone:server:getCallLog', function(source)
    if not WaitForDatabase() then return {} end
    local identifier = GetIdentifier(source)
    if not identifier then return {} end
    local myNum = GetOrCreateNumber(identifier)
    return MySQL.query.await([[
        SELECT caller_num, callee_num, status, duration, created_at FROM rde_phone_calls
        WHERE caller_num = ? OR callee_num = ?
        ORDER BY created_at DESC LIMIT 50
    ]], { myNum, myNum }) or {}
end)

lib.callback.register('rde_phone:server:getThread', function(source, otherNumber)
    if not WaitForDatabase() then return {} end
    local identifier = GetIdentifier(source)
    if not identifier then return {} end
    local myNum = GetOrCreateNumber(identifier)
    return MySQL.query.await(
        'SELECT * FROM rde_phone_sms WHERE (from_num = ? AND to_num = ?) OR (from_num = ? AND to_num = ?) ORDER BY created_at ASC',
        { myNum, otherNumber, otherNumber, myNum }) or {}
end)

-----------------------------------------------------------
-- PHOTOS — camera/gallery. Same validation shape as rde_crew's
-- graffiti save path: format check + hard size cap server-side,
-- client input is never trusted just because it "looks" like base64.
-----------------------------------------------------------

lib.callback.register('rde_phone:server:getPhotos', function(source)
    if not WaitForDatabase() then return {} end
    local identifier = GetIdentifier(source)
    if not identifier then return {} end
    return MySQL.query.await(
        'SELECT id, image_data, created_at FROM rde_phone_photos WHERE owner = ? ORDER BY created_at DESC',
        { identifier }) or {}
end)

lib.callback.register('rde_phone:server:savePhoto', function(source, payload)
    if not WaitForDatabase() then return { error = true } end
    local identifier = GetIdentifier(source)
    if not identifier then return { error = true } end

    local imageData = payload and payload.imageData
    if type(imageData) ~= 'string' or imageData == '' then
        return { error = true, message = 'empty_photo' }
    end
    -- Accept whatever image type screenshot-basic actually hands back (jpg by
    -- convention, but not asserting an unconfirmed options/encoding param on
    -- requestScreenshot() here — verify in testing whether it exposes one).
    -- Format is a light sanity check; the real guardrail is the size cap below.
    if not imageData:match('^data:image/[%w]+;base64,') then
        return { error = true, message = 'bad_image_format' }
    end
    if #imageData > Config.Photos.maxImageBytes then
        return { error = true, message = Config.GetString('photo_too_large') }
    end

    MySQL.insert.await('INSERT INTO rde_phone_photos (owner, image_data) VALUES (?, ?)', { identifier, imageData })

    -- Enforce the per-player cap by dropping the oldest overflow, not by
    -- blocking new photos — matches how a real phone gallery behaves.
    local count = tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM rde_phone_photos WHERE owner = ?', { identifier })) or 0
    local trimmed = false
    if count > Config.Photos.maxPerPlayer then
        MySQL.query.await([[
            DELETE FROM rde_phone_photos WHERE owner = ? AND id NOT IN (
                SELECT id FROM (
                    SELECT id FROM rde_phone_photos WHERE owner = ? ORDER BY created_at DESC LIMIT ?
                ) keep
            )
        ]], { identifier, identifier, Config.Photos.maxPerPlayer })
        trimmed = true
    end

    return { ok = true, message = Config.GetString('photo_saved'), trimmed = trimmed }
end)

lib.callback.register('rde_phone:server:deletePhoto', function(source, payload)
    if not WaitForDatabase() then return { error = true } end
    local identifier = GetIdentifier(source)
    if not identifier or not payload or not payload.id then return { error = true } end
    local affected = MySQL.update.await(
        'DELETE FROM rde_phone_photos WHERE id = ? AND owner = ?', { payload.id, identifier })
    return { ok = affected > 0 }
end)

-----------------------------------------------------------
-- Lifecycle
-----------------------------------------------------------

AddEventHandler('onResourceStart', function(name)
    if name ~= GetCurrentResourceName() then return end
    local attempts = 0
    while not Ox and attempts < 100 do Wait(100); attempts = attempts + 1 end
    if not Ox then Log('ox_core not found!', 'ERROR'); return end
    SetupDatabase()

    -- Re-register already-connected players. Covers /restart rde_phone mid-session:
    -- ox:playerLoaded already fired for these players before the restart wiped State,
    -- so without this, onlineByNum stays empty until they reconnect.
    for _, src in ipairs(GetPlayers()) do
        local source = tonumber(src)
        CreateThread(function()
            local identifier = GetIdentifier(source)
            if not identifier then return end
            GetOrCreateNumber(identifier, source)
        end)
    end
end)

-- ❌ Was: AddEventHandler('playerJoining', ...). playerJoining fires the
-- instant a client connects — BEFORE character selection, so Ox.GetPlayer(source)
-- is still nil inside GetIdentifier() at that point. identifier came back nil,
-- GetOrCreateNumber() never ran, and State.onlineByNum was never populated for
-- ANY player all session. That's the entire "no player with that number" bug —
-- every callee lookup at line ~316 failed even for players who were 100% online.
-- ✅ ox:playerLoaded fires only once the character is fully loaded server-side.
AddEventHandler('ox:playerLoaded', function(playerId)
    CreateThread(function()
        local identifier = GetIdentifier(playerId)
        if not identifier then return end
        GetOrCreateNumber(identifier, playerId)
    end)
end)

AddEventHandler('playerDropped', function()
    local source = source
    local identifier = GetIdentifier(source)
    if identifier and State.numbers[identifier] then
        State.onlineByNum[State.numbers[identifier]] = nil
    end
    for callId, call in pairs(State.calls) do
        if call.callerSrc == source or call.calleeSrc == source then
            EndCall(callId, call.status == 'active' and 'answered' or 'missed')
        end
    end
end)
