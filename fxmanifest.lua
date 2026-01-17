fx_version 'cerulean'
game 'gta5'

name 'nekot-bombgame'
author 'nekot'
description '1v1 Bomb mini-game'
version '0.1.2'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

server_scripts {
    'server/main.lua'
}

client_scripts {
    'client/main.lua',
    'client/ui.lua',
    'client/nui.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

dependencies {
    'ox_lib',
    'oxmysql'
}


