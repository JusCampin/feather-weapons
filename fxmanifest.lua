fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

description 'The official weapon system for Feather framework.'
author 'Feather Framework'
name 'feather-weapons'
version '0.9.0'

shared_scripts {
    'config.lua',
    '/shared/constants.lua',
    '/shared/errors.lua',
    '/shared/definitions/ammunition.lua',
    '/shared/definitions/attachments.lua',
    '/shared/definitions/weapons.lua',
    '/shared/validation.lua'
}

server_scripts {
    '/server/imports.lua',
    '/server/adapters/core.lua',
    '/server/adapters/inventory.lua',
    '/server/adapters/feather_inventory.lua',
    '/server/services/definition_registry.lua',
    '/server/services/metadata.lua',
    '/server/services/runtime.lua',
    '/server/services/equip.lua',
    '/server/services/ammo.lua',
    '/server/services/maintenance.lua',
    '/server/services/repair.lua',
    '/server/services/attachments.lua',
    '/server/services/issuance.lua',
    '/server/services/commands.lua',
    '/server/services/reconciliation.lua',
    '/server/services/api.lua',
    '/server/main.lua'
}

client_scripts {
    '/client/imports.lua',
    '/client/guid_weapons.lua',
    '/client/native_maintenance.lua',
    '/client/native_weapon_coordinator.lua',
    '/client/main.lua',
    '/client/native_probe.lua'
}

files {
    '/data/weapon_holsters.meta'
}

data_file 'WEAPONINFO_FILE_PATCH' '/data/weapon_holsters.meta'

dependencies {
    'feather-core',
    'feather-character',
    'feather-inventory',
    'feather-menu-v2'
}
