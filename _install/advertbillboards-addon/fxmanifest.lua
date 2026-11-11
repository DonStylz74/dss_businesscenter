fx_version 'cerulean'
game 'gta5'

lua54 'yes'

author 'Don Stylz Skriptz'
description 'ESX Legacy Business Centre - ownership, resale, admin creator, certificates and inactivity management'
version '1.0.2'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/assets/*.svg',
    'html/assets/*.png',
    'html/assets/businesses/*',
	'stream/zero_advertisement.ytyp'
}

data_file 'DLC_ITYP_REQUEST' 'stream/zero_advertisement.ytyp'

dependencies {
    'es_extended',
    'ox_lib',
    'oxmysql',
    'ox_inventory',
    'ox_target'
}
