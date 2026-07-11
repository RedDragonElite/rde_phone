-----------------------------------------------------------
-- rde_phone / client / client.lua
-----------------------------------------------------------

local State = {
    isOpen         = false,
    inCamera       = false,
    phoneProp      = nil,
    hasProp        = false,
    animLoopActive = false,
    hudWasHidden   = false,
    radarWasHidden = false,
}

local function Log(msg, level)
    if not Config.Debug and level ~= 'ERROR' then return end
    local prefix = level == 'ERROR' and '^1' or level == 'WARN' and '^3' or '^2'
    print(('%s[RDE_PHONE]^7 %s'):format(prefix, msg))
end

-----------------------------------------------------------
-- PHONE PROP + PULL-OUT / PUT-AWAY ANIMATION
-- Dict/clip names and hand-bone id cross-checked against
-- NPWD's live production build (the most battle-tested phone
-- resource in the ecosystem) — not guessed. Works on foot and
-- inside vehicles via the dedicated in-car anim dict.
-----------------------------------------------------------

local ANIM_DICT_NORMAL  = 'cellphone@'
local ANIM_DICT_VEHICLE = 'anim@cellphone@in_car@ps'
local ANIM_IN           = 'cellphone_text_in'
local ANIM_OUT          = 'cellphone_text_out'

-- Model loading with timeout guard (RDE OX Standard pattern)
local function LoadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    if not IsModelValid(hash) then return false end
    if HasModelLoaded(hash) then return true end
    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(10) end
    return HasModelLoaded(hash)
end

local function LoadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function AttachPhoneProp()
    if not Config.PhonePullOutAnim then return end
    if State.hasProp then return end
    if not LoadModel(Config.PhoneProp) then
        Log('Phone prop model failed to load: ' .. Config.PhoneProp, 'WARN')
        return
    end

    local hash   = joaat(Config.PhoneProp)
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)

    State.phoneProp = CreateObject(hash, coords.x, coords.y, coords.z + 0.2, true, true, true)
    local bone = GetPedBoneIndex(ped, Config.PhonePropBone)
    AttachEntityToEntity(State.phoneProp, ped, bone,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        true, true, false, false, 2, true)

    SetModelAsNoLongerNeeded(hash)
    State.hasProp = true
end

local function DetachPhoneProp()
    if not State.hasProp then return end
    if State.phoneProp and DoesEntityExist(State.phoneProp) then
        DeleteEntity(State.phoneProp)
    end
    State.phoneProp = nil
    State.hasProp   = false
end

local function PlayOpenAnim()
    if not Config.PhonePullOutAnim then return end
    local ped       = PlayerPedId()
    local inVehicle = IsPedInAnyVehicle(ped, true)
    local dict      = inVehicle and ANIM_DICT_VEHICLE or ANIM_DICT_NORMAL
    local blendIn   = inVehicle and 7.0 or 8.0

    if not LoadAnimDict(dict) then return end
    if IsEntityPlayingAnim(ped, dict, ANIM_IN, 3) then return end

    SetCurrentPedWeapon(ped, joaat('weapon_unarmed'), true)
    TaskPlayAnim(ped, dict, ANIM_IN, blendIn, -1.0, -1, 50, 0.0, false, false, false)
end

local function PlayCloseAnim()
    if not Config.PhonePullOutAnim then return end
    local ped       = PlayerPedId()
    local inVehicle = IsPedInAnyVehicle(ped, true)
    local dict      = inVehicle and ANIM_DICT_VEHICLE or ANIM_DICT_NORMAL

    StopAnimTask(ped, dict, ANIM_IN, 1.0)

    if inVehicle then return end -- no distinct in-car "put away" clip, a clean cut reads fine here

    if not LoadAnimDict(dict) then return end
    TaskPlayAnim(ped, dict, ANIM_OUT, 7.0, -1.0, -1, 50, 0.0, false, false, false)
    CreateThread(function()
        Wait(260)
        StopAnimTask(ped, dict, ANIM_OUT, 1.0)
    end)
end

-- Refreshes the idle "texting" pose every 250ms while the phone is open.
-- Without this the anim gets cancelled by sprinting, ducking, weapon
-- switches etc. — a throttled loop, never Wait(0), self-terminating the
-- moment State.isOpen flips false.
local function StartAnimLoop()
    if State.animLoopActive then return end
    State.animLoopActive = true
    CreateThread(function()
        while State.animLoopActive and State.isOpen do
            Wait(250)
            if State.isOpen and not State.inCamera then
                PlayOpenAnim()
            end
        end
        State.animLoopActive = false
    end)
end

local function StopAnimLoop()
    State.animLoopActive = false
end

-----------------------------------------------------------
-- OPEN / CLOSE
-----------------------------------------------------------

local function OpenPhone()
    if State.isOpen then return end
    State.isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'phone:open' })

    CreateThread(function()
        AttachPhoneProp()
        PlayOpenAnim()
        StartAnimLoop()
    end)
end

local function ClosePhone()
    if not State.isOpen then return end
    State.isOpen = false
    StopAnimLoop()

    if State.inCamera then
        State.inCamera = false
        SetNuiFocusKeepInput(false)
        CellCamActivate(false, false)
        DestroyMobilePhone()
        if not State.hudWasHidden   then DisplayHud(true) end
        if not State.radarWasHidden then DisplayRadar(true) end
    end

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'phone:close' })

    CreateThread(function()
        PlayCloseAnim()
        Wait(280) -- let the put-away clip read before the prop vanishes
        DetachPhoneProp()
    end)
end

-- Server is the source of truth for "does this player actually have a phone".
-- Never trust a client-side inventory check for this.
local function TryOpenPhone()
    if State.isOpen then
        ClosePhone()
        return
    end
    CreateThread(function()
        local result = lib.callback.await('rde_phone:server:canOpen', false)
        if result and result.ok then
            OpenPhone()
        else
            lib.notify({ title = Config.GetString('no_phone_item'), type = 'error', icon = 'mobile-screen' })
        end
    end)
end

RegisterCommand('phone', TryOpenPhone, false)
RegisterKeyMapping('phone', 'Open/Close Phone', 'keyboard', Config.OpenKey)

-- Fired by data/items.lua when the 'phone' ox_inventory item is used
AddEventHandler('rde_phone:client:tryOpen', TryOpenPhone)

RegisterNUICallback('close', function(_, cb)
    ClosePhone()
    cb('ok')
end)

-- Real controller/phone vibration, callable from the shell for calls & notifications
RegisterNUICallback('vibrate', function(data, cb)
    SetPadShake(0, data and data.duration or 300, data and data.frequency or 80)
    cb('ok')
end)

-----------------------------------------------------------
-- THE single SDK bridge.
-- Every app running inside an iframe posts a message to the
-- shell (web/js/phone.js), the shell forwards it here as ONE
-- NUI callback shape: { action, payload }. We resolve it against
-- an ox_lib server callback and hand the result straight back.
-- No per-app Lua code needed on the client side, ever.
-----------------------------------------------------------

RegisterNUICallback('sdk:request', function(data, cb)
    if not data or not data.action then cb({ error = true }) return end

    local ok, result = pcall(function()
        return lib.callback.await('rde_phone:server:' .. data.action, false, data.payload)
    end)

    if ok then
        cb(result)
    else
        cb({ error = true, message = tostring(result) })
    end
end)

-----------------------------------------------------------
-- Call events pushed from server -> NUI
-----------------------------------------------------------

RegisterNetEvent('rde_phone:client:incomingCall', function(callId, fromNumber)
    if not State.isOpen then OpenPhone() end
    SendNUIMessage({ action = 'call:incoming', callId = callId, from = fromNumber })
end)

-- Caller-side counterpart to incomingCall above — was missing entirely,
-- which is why the caller's phone never left the static "ringing" text.
RegisterNetEvent('rde_phone:client:outgoingCall', function(callId, toNumber)
    if not State.isOpen then OpenPhone() end
    SendNUIMessage({ action = 'call:outgoing', callId = callId, to = toNumber })
end)

RegisterNetEvent('rde_phone:client:callAccepted', function(callId)
    SendNUIMessage({ action = 'call:accepted', callId = callId })
end)

RegisterNetEvent('rde_phone:client:callEnded', function(status)
    SendNUIMessage({ action = 'call:ended', status = status })
end)

-- Client-side pma-voice hook — mirrors pma-voice's own client/module/phone.lua
-- exports (addPlayerToCall/removePlayerFromCall), which is the pairing it
-- documents for third-party phone scripts. Runs alongside the server export
-- in server.lua as a second, independent path onto the same call channel.
RegisterNetEvent('rde_phone:client:pmaVoiceCallStart', function(channel)
    exports['pma-voice']:addPlayerToCall(channel)
end)

RegisterNetEvent('rde_phone:client:pmaVoiceCallEnd', function()
    exports['pma-voice']:removePlayerFromCall()
end)

RegisterNetEvent('rde_phone:client:smsReceived', function(payload)
    SendNUIMessage({ action = 'sms:received', payload = payload })
end)

RegisterNetEvent('rde_phone:client:pushNotification', function(data)
    SendNUIMessage({ action = 'notify:push', data = data })
end)

RegisterNetEvent('rde_phone:client:appsUpdated', function()
    SendNUIMessage({ action = 'apps:updated' })
end)

-----------------------------------------------------------
-- Statebag reaction — live call/status sync per player
-----------------------------------------------------------

AddStateBagChangeHandler(Config.StatebagPrefix, ('player:%d'):format(cache and cache.serverId or 0), function(bagName, key, value)
    if not value or value._deleted then return end
    SendNUIMessage({ action = 'phone:stateSync', state = value })
end)

-----------------------------------------------------------
-- CAMERA — native GTA phone-camera engine.
--
-- CellCamActivate + CreateMobilePhone is the exact mechanism the
-- base game's own "Take a Selfie" feature — and NPWD's production
-- camera — both run on. Swapped out our old hand-rolled
-- CreateCamWithParams/RenderScriptCams setup for this: no manual
-- FOV/position math to get wrong, and it can't hit the black-screen
-- class of bug a custom scripted cam is exposed to. HUD/radar get
-- hidden for the duration so they never bleed into the shot.
-----------------------------------------------------------

-- Toggles CellCam's front/back facing while active. Undocumented on the
-- official native DB but verified against NPWD's live production build —
-- battle-tested across thousands of servers.
local function SetCellcamFacing(front)
    Citizen.InvokeNative(0x2491A93618B7D838, front)
end

RegisterNUICallback('phone_cam_start', function(data, cb)
    State.inCamera = true
    local mode = (data and data.mode) or 'standard'

    State.hudWasHidden   = IsHudHidden()
    State.radarWasHidden = IsRadarHidden()
    DisplayHud(false)
    DisplayRadar(false)

    CreateMobilePhone(1)
    CellCamActivate(true, true)
    SetCellcamFacing(mode == 'selfie')

    -- Without this, SetNuiFocus(true, true) from OpenPhone() eats all mouse
    -- movement into the NUI cursor and the player can never aim the shot —
    -- this lets mouse-look/movement pass through to the game while the
    -- shutter/flip buttons stay clickable.
    SetNuiFocusKeepInput(true)

    cb('ok')
end)

RegisterNUICallback('phone_cam_setMode', function(data, cb)
    if not State.inCamera then cb('ok') return end
    SetCellcamFacing(((data and data.mode) or 'standard') == 'selfie')
    cb('ok')
end)

RegisterNUICallback('phone_cam_stop', function(_, cb)
    if State.inCamera then
        State.inCamera = false
        SetNuiFocusKeepInput(false)
        CellCamActivate(false, false)
        DestroyMobilePhone()
        if not State.hudWasHidden   then DisplayHud(true) end
        if not State.radarWasHidden then DisplayRadar(true) end
    end
    cb('ok')
end)

-- The actual capture — screenshot-basic's plain requestScreenshot() (not
-- requestScreenshotUpload) hands back a base64 data URI directly, no
-- external host involved at any point.
RegisterNUICallback('phone_cam_capture', function(_, cb)
    exports['screenshot-basic']:requestScreenshot(function(data)
        cb({ imageData = data })
    end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if State.inCamera then
        SetNuiFocusKeepInput(false)
        CellCamActivate(false, false)
        DestroyMobilePhone()
    end
    StopAnimLoop()
    DetachPhoneProp()
    ClearPedTasks(PlayerPedId())
end)
