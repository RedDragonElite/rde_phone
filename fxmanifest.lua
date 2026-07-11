fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'rde_phone'
author      'Red Dragon Elite | SerpentsByte'
description 'RDE Phone OS — modular smartphone with own micro-frontend App-SDK, real voice calls, SMS'
version     '0.2.0'

dependencies {
    '/server:7290',
    'oxmysql',
    'ox_lib',
    'ox_core',
    'ox_inventory',     -- used for PhoneItem possession checks (exports.ox_inventory:Search)
    'pma-voice',        -- swap in config if you move to saltychat
    'screenshot-basic',  -- camera capture, no external upload
}

shared_scripts {
    '@ox_lib/init.lua',
    '@ox_core/lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua'
}

client_scripts {
    'data/items.lua',
    'client/client.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
    'web/sdk/*.js',
    'web/theme/*.css',
    'web/theme/*.js',
    'web/vendor/*.js',
    'web/apps/**/*',   -- 3rd-party apps drop their static folder in here (Phase 3: dynamic registry)
}
