-- Run from the feather-weapons directory: lua tests/ammunition.lua
-- Tests real server services with an in-memory transactional inventory.
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

GetGameTimer = function() return 100 end
vector3 = function(x, y, z) return { x = x, y = y, z = z } end
SetTimeout = function(_delay, _callback) end
AddEventHandler = function(_eventName, _callback) end
TriggerClientEvent = function(_eventName, _target, ...) end
FeatherCore = { RPC = { Register = function(_route, _callback, _options) end } }
for _, file in ipairs({ 'config.lua', 'shared/constants.lua', 'shared/errors.lua',
    'shared/definitions/ammunition.lua', 'shared/definitions/attachments.lua',
    'shared/definitions/weapons.lua', 'shared/validation.lua',
    'server/services/definition_registry.lua', 'server/services/metadata.lua',
    'server/services/runtime.lua', 'server/services/equip.lua', 'server/services/ammo.lua' }) do
    dofile(file)
end
Config.DevMode = false
assert(DefinitionRegistry.Start().ok)
local items, stock, rejectBatch, rejectTransaction
local context = { characterId = 1, sessionId = 'test', correlationId = 'test' }
local TestInventoryAdapter = {}
InventoryAdapter = TestInventoryAdapter
function TestInventoryAdapter.GetItemForCharacter(_, id)
    return items[id] and WeaponResult.Ok(copy(items[id]))
        or WeaponResult.Error('missing', 'Missing item')
end
function TestInventoryAdapter.MutateWeaponMetadataBatch(_, mutations)
    if rejectBatch then return WeaponResult.Error('conflict', 'Injected conflict') end
    for _, mutation in ipairs(mutations) do
        if items[mutation.itemInstanceId].metadataRevision ~= mutation.expectedRevision then
            return WeaponResult.Error('conflict', 'Stale revision')
        end
    end
    for _, mutation in ipairs(mutations) do
        local item = items[mutation.itemInstanceId]
        item.metadata = copy(mutation.metadata)
        item.metadataRevision = item.metadataRevision + 1
    end
    return WeaponResult.Ok(true)
end
function TestInventoryAdapter.Transaction(_, callback)
    local staged, quantities = copy(items), copy(stock)
    local tx = {}
    function tx:GetItemForUpdate(id) return staged[id] end
    function tx:GetQuantity(name) return quantities[name] or 0 end
    function tx:RemoveQuantity(name, amount)
        if self:GetQuantity(name) < amount then return false end
        quantities[name] = self:GetQuantity(name) - amount
        return true
    end
    function tx:AddQuantity(name, amount)
        quantities[name] = self:GetQuantity(name) + amount
        return true
    end
    function tx:SetMetadata(id, metadata, revision)
        if staged[id].metadataRevision ~= revision then return false end
        staged[id].metadata = copy(metadata)
        staged[id].metadataRevision = revision + 1
        return true
    end
    local result = callback(tx)
    if result.ok == false then return result end
    if rejectTransaction then return WeaponResult.Error('conflict', 'Injected conflict') end
    items, stock = staged, quantities
    return WeaponResult.Ok(result)
end
local function reset(weapon, second, shoulder, back)
    items, stock, rejectBatch, rejectTransaction = {}, {}, false, false
    WeaponRuntime.Begin({ source = 1, characterId = 1, sessionId = 'test' })
    local loadoutSlots = { 'primary', 'offhand', 'shoulder', 'back' }
    for index, id in ipairs({ weapon, second, shoulder, back }) do
        local definition = DefinitionRegistry.Get('weapon', id).value
        local metadata = WeaponMetadata.Build(definition, { serialNumber = 'TEST-' .. index })
        assert(metadata.ok)
        items[index] = { id = index, metadata = metadata.value, metadataRevision = 1 }
        assert(WeaponRuntime.RestoreEquipped(1, 'test', items[index], definition,
            'test', loadoutSlots[index]).ok)
    end
end
local passed = 0
local function check(value, message)
    assert(value, message)
    passed = passed + 1
end

-- Every catalog combination loads, persists its native type and unloads the
-- exact inventory item. Native rendering/firing still needs in-game testing.
for _, definition in ipairs(DefinitionRegistry.List('weapon').value) do
    for _, ammoId in ipairs(definition.ammunitionTypes) do
        reset(definition.id)
        local ammo = DefinitionRegistry.Get('ammunition', ammoId).value
        stock[ammo.itemName] = 10
        local result = AmmoService.Escrow(1, context, 10, ammoId)
        check(result.ok, definition.id .. '/' .. ammoId .. ' load')
        check(items[1].metadata.ammo.type == ammoId, 'Persist selected type')
        check(WeaponRuntime.Get(1).equipped.nativeAmmoName == ammo.nativeAmmoName, 'Native type')
        local restored = WeaponRuntime.RestoreEquipped(1, 'test', items[1], definition, 'test')
        check(restored.ok and restored.value.ammunitionType == ammoId, 'Restore selected type')
        check(AmmoService.Unload(1, context).ok and stock[ammo.itemName] == 10, 'Exact unload')
    end
end

reset('revolver_cattleman')
stock.ammo_revolver_express = 20
check(AmmoService.Escrow(1, context, 10, 'ammo_revolver_express').ok, 'Express load')
check(not AmmoService.Escrow(1, context, 10, 'ammo_revolver_regular').ok, 'Loaded switch rejected')
check(not AmmoService.Escrow(1, context, 10, 'ammo_pistol_regular').ok, 'Wrong family rejected')
check(stock.ammo_revolver_express == 10 and items[1].metadata.ammo.type == 'ammo_revolver_express',
    'Rejected requests preserve stock and type')
local lease = copy(WeaponRuntime.Get(1).equipped)
check(AmmoService.SyncConsumption(1, context, {
    itemInstanceId = lease.itemInstanceId, generation = lease.generation, total = 9, loaded = 5
}).ok, 'Special ammo shot checkpoint')
check(AmmoService.Unload(1, context).ok and stock.ammo_revolver_express == 19, 'Shot consumes one round')

reset('revolver_cattleman', 'revolver_schofield')
stock.ammo_revolver_regular = 50
stock.ammo_revolver_express = 7
local availability = AmmoService.GetInventoryAvailability(1, context)
check(availability.ok and availability.value.quantities.ammo_revolver_regular == 50
    and availability.value.quantities.ammo_revolver_express == 7
    and availability.value.quantities.ammo_revolver_explosive == nil,
    'Managed ammunition availability returns only owned stacks')
local managedRuntime = WeaponRuntime.Get(1)
local managedOffhand = managedRuntime.slots.offhand
local managedLoad = AmmoService.LoadSlot(1, context, {
    slot = 'offhand', ammunitionType = 'ammo_revolver_regular', amount = 50,
    itemInstanceId = managedOffhand.itemInstanceId, generation = managedOffhand.generation
})
check(managedLoad.ok and items[1].metadata.ammo.loaded == 0
    and items[2].metadata.ammo.loaded == 6 and items[2].metadata.ammo.reserve == 44,
    'Managed load targets only the requested weapon slot')
local managedUnload = AmmoService.Unload(1, context, 10, 'offhand', {
    slot = 'offhand', itemInstanceId = managedOffhand.itemInstanceId,
    generation = managedOffhand.generation
})
check(managedUnload.ok and items[2].metadata.ammo.loaded == 6
    and items[2].metadata.ammo.reserve == 34 and stock.ammo_revolver_regular == 10,
    'Managed unload returns ammunition from only the requested slot')
local switchLease = WeaponRuntime.Get(1).slots.offhand
local managedSwitch = AmmoService.SwitchSlot(1, context, {
    slot = 'offhand', ammunitionType = 'ammo_revolver_express', amount = 50,
    itemInstanceId = switchLease.itemInstanceId, generation = switchLease.generation
})
check(managedSwitch.ok and managedSwitch.reconcile == true
    and managedSwitch.value.moved == 7 and managedSwitch.value.returned == 40
    and items[2].metadata.ammo.type == 'ammo_revolver_express'
    and items[2].metadata.ammo.loaded == 6 and items[2].metadata.ammo.reserve == 1
    and stock.ammo_revolver_regular == 50 and stock.ammo_revolver_express == 0,
    'Managed ammunition switch is atomic and slot scoped')

for _, second in ipairs({ 'revolver_schofield', 'revolver_cattleman' }) do
    reset('revolver_cattleman', second)
    local oldGeneration = WeaponRuntime.Get(1).equipped.generation
    stock.ammo_revolver_express = 30
    check(AmmoService.Escrow(1, context, 10, 'ammo_revolver_express').ok, 'Pair first load')
    check(items[1].metadata.ammo.type == 'ammo_revolver_express'
        and items[2].metadata.ammo.type == 'ammo_revolver_express', 'Atomic pair selection')
    check(not WeaponRuntime.MatchesLease(1, 'test', 1, oldGeneration), 'Old lease invalidated')
    check(AmmoService.Escrow(1, context, 10, 'ammo_revolver_express').ok, 'Pair second load')
    local runtime = WeaponRuntime.Get(1)
    check(AmmoService.SyncPair(1, context, { total = 18, slots = {
        primary = { itemInstanceId = 1, generation = runtime.slots.primary.generation, loaded = 5, consumed = 1 },
        offhand = { itemInstanceId = 2, generation = runtime.slots.offhand.generation, loaded = 5, consumed = 1 }
    } }).ok, 'Special ammo pair firing checkpoint')
    check(not AmmoService.Escrow(1, context, 10, 'ammo_revolver_explosive').ok, 'Loaded pair switch rejected')
    check(AmmoService.Unload(1, context).ok and AmmoService.Unload(1, context).ok
        and stock.ammo_revolver_express == 28, 'Pair unload conserves ammo after two shots')
    stock.ammo_revolver_high_velocity = 10
    check(AmmoService.Escrow(1, context, 10, 'ammo_revolver_high_velocity').ok, 'Empty pair switches')
end

-- Different native ammo pools coexist without requiring both weapons to
-- select or consume the same Inventory ammunition definition.
reset('revolver_cattleman', 'pistol_volcanic')
stock.ammo_revolver_regular = 10
stock.ammo_pistol_regular = 10
check(AmmoService.Escrow(1, context, 10, 'ammo_revolver_regular').ok,
    'Mixed pair loads revolver ammunition')
check(items[1].metadata.ammo.loaded + items[1].metadata.ammo.reserve == 10
    and items[2].metadata.ammo.loaded + items[2].metadata.ammo.reserve == 0,
    'Revolver ammunition changes only compatible slot')
check(AmmoService.Escrow(1, context, 10, 'ammo_pistol_regular').ok,
    'Mixed pair loads pistol ammunition')
check(items[1].metadata.ammo.type == 'ammo_revolver_regular'
    and items[2].metadata.ammo.type == 'ammo_pistol_regular',
    'Mixed pair retains independent ammunition types')
local mixedRuntime = WeaponRuntime.Get(1)
local mixedCheckpoint = AmmoService.SyncPair(1, context, { total = 18, slots = {
    primary = { itemInstanceId = 1, generation = mixedRuntime.slots.primary.generation,
        loaded = 5, consumed = 1 },
    offhand = { itemInstanceId = 2, generation = mixedRuntime.slots.offhand.generation,
        loaded = 7, consumed = 1 }
} })
check(mixedCheckpoint.ok,
    ('Mixed ammo pair checkpoint conserves both pools (%s: %s)'):format(
        tostring(mixedCheckpoint.error and mixedCheckpoint.error.code),
        tostring(mixedCheckpoint.error and mixedCheckpoint.error.message)))
check(AmmoService.Unload(1, context).ok and AmmoService.Unload(1, context).ok
    and stock.ammo_revolver_regular == 9 and stock.ammo_pistol_regular == 9,
    'Mixed pair unload returns exact ammunition families')

reset('revolver_cattleman', 'pistol_volcanic', 'rifle_springfield', 'shotgun_pump')
check(EquipService.ValidateConfiguration().ok, 'Mixed loadout configuration valid')
local fullRuntime = WeaponRuntime.Get(1)
check(fullRuntime.slots.primary ~= nil and fullRuntime.slots.offhand ~= nil
    and fullRuntime.slots.shoulder ~= nil and fullRuntime.slots.back ~= nil,
    'Four sidearm and long-gun runtime slots coexist')
reset('revolver_cattleman', 'pistol_volcanic', 'repeater_carbine', 'repeater_evans')
assert(WeaponRuntime.Unequip(1, 'test', 'test', 'back').ok)
local conflictingLonggun = EquipService.Request(1, context, 4, 'back')
check(not conflictingLonggun.ok
    and conflictingLonggun.error.code == WeaponErrors.OPERATION_CONFLICT,
    'Second long gun rejects a duplicate native ammunition type')
assert(WeaponRuntime.RestoreEquipped(1, 'test', items[4],
    DefinitionRegistry.Get('weapon', 'repeater_evans').value, 'test', 'back').ok)
stock.ammo_repeater_express = 10
local ambiguousLonggunAmmo = AmmoService.Escrow(1, context, 10, 'ammo_repeater_express')
check(not ambiguousLonggunAmmo.ok
    and ambiguousLonggunAmmo.error.code == WeaponErrors.OPERATION_CONFLICT,
    'Generic ammunition loading rejects two compatible long guns')
reset('revolver_cattleman', 'pistol_volcanic', 'repeater_carbine', 'repeater_evans')
for index, values in pairs({ [3] = { loaded = 7, reserve = 100 },
        [4] = { loaded = 26, reserve = 70 } }) do
    items[index].metadata.ammo.type = 'ammo_repeater_express'
    items[index].metadata.ammo.loaded = values.loaded
    items[index].metadata.ammo.reserve = values.reserve
    WeaponRuntime.SetSlotAmmunitionType(1, 'test', index == 3 and 'shoulder' or 'back',
        'ammo_repeater_express')
    WeaponRuntime.SetSlotAmmo(1, 'test', index == 3 and 'shoulder' or 'back',
        values.loaded + values.reserve, values.loaded, 'test')
end
stock.ammo_repeater_express = 0
check(AmmoService.NormalizeSharedPools(1, context).ok
    and items[3].metadata.ammo.loaded + items[3].metadata.ammo.reserve
        + items[4].metadata.ammo.loaded + items[4].metadata.ammo.reserve == 200
    and stock.ammo_repeater_express == 3,
    'Shared loaded overflow returns to Inventory during recovery')
local longgunRuntime = WeaponRuntime.Get(1)
local longgunReload = AmmoService.SyncPair(1, context, {
    total = 200,
    slotNames = { 'shoulder', 'back' },
    slots = {
        shoulder = { itemInstanceId = 3, generation = longgunRuntime.slots.shoulder.generation,
            loaded = 26, consumed = 0 },
        back = { itemInstanceId = 4, generation = longgunRuntime.slots.back.generation,
            loaded = 14, consumed = 0 }
    }
})
check(not longgunReload.ok
    and items[3].metadata.ammo.loaded == 7
    and items[3].metadata.ammo.reserve == 100
    and items[4].metadata.ammo.loaded == 26
    and items[4].metadata.ammo.reserve == 67,
    'Distinct long guns reject native reload redistribution across escrow')
local longgunShot = AmmoService.SyncPair(1, context, {
    total = 199,
    slotNames = { 'shoulder', 'back' },
    slots = {
        shoulder = { itemInstanceId = 3, generation = longgunRuntime.slots.shoulder.generation,
            loaded = 6, consumed = 1 },
        back = { itemInstanceId = 4, generation = longgunRuntime.slots.back.generation,
            loaded = 26, consumed = 0 }
    }
})
check(longgunShot.ok
    and items[3].metadata.ammo.loaded == 6
    and items[3].metadata.ammo.reserve == 100
    and items[4].metadata.ammo.loaded == 26
    and items[4].metadata.ammo.reserve == 67,
    'Distinct long-gun shared pool preserves per-item reserve ownership')

-- A capped RedM pistol pool is only a runtime window. Pair checkpoints use
-- Feather ownership minus confirmed shots, not the smaller native pool total.
reset('pistol_m1899', 'pistol_m1899')
for index, values in ipairs({ { loaded = 0, reserve = 99 }, { loaded = 8, reserve = 93 } }) do
    items[index].metadata.ammo.type = 'ammo_pistol_express'
    items[index].metadata.ammo.loaded = values.loaded
    items[index].metadata.ammo.reserve = values.reserve
    local slot = index == 1 and 'primary' or 'offhand'
    WeaponRuntime.SetSlotAmmunitionType(1, 'test', slot, 'ammo_pistol_express')
    assert(WeaponRuntime.SetSlotAmmo(1, 'test', slot,
        values.loaded + values.reserve, values.loaded, 'test').ok)
end
local pistolRuntime = WeaponRuntime.Get(1)
local pistolReload = AmmoService.SyncPair(1, context, { total = 200, slots = {
    primary = { itemInstanceId = 1, generation = pistolRuntime.slots.primary.generation,
        loaded = 8, consumed = 0 },
    offhand = { itemInstanceId = 2, generation = pistolRuntime.slots.offhand.generation,
        loaded = 8, consumed = 0 }
} })
check(pistolReload.ok
    and items[1].metadata.ammo.loaded == 8
    and items[2].metadata.ammo.loaded == 8,
    'Capped pistol window persists native reload without reducing ownership')
local pistolShot = AmmoService.SyncPair(1, context, { total = 199, slots = {
    primary = { itemInstanceId = 1, generation = pistolRuntime.slots.primary.generation,
        loaded = 7, consumed = 1 },
    offhand = { itemInstanceId = 2, generation = pistolRuntime.slots.offhand.generation,
        loaded = 8, consumed = 0 }
} })
check(pistolShot.ok
    and items[1].metadata.ammo.loaded + items[1].metadata.ammo.reserve
        + items[2].metadata.ammo.loaded + items[2].metadata.ammo.reserve == 199,
    'Capped pistol window subtracts only confirmed GUID shots')

reset('revolver_cattleman', 'revolver_schofield')
rejectBatch = true
stock.ammo_revolver_express = 10
check(not AmmoService.Escrow(1, context, 10, 'ammo_revolver_express').ok, 'Failed batch rejected')
check(items[1].metadata.ammo.type == 'ammo_revolver_regular'
    and items[2].metadata.ammo.type == 'ammo_revolver_regular'
    and stock.ammo_revolver_express == 10, 'Failed batch changes nothing')
rejectBatch, rejectTransaction = false, true
local failed = AmmoService.Escrow(1, context, 10, 'ammo_revolver_express')
check(not failed.ok and failed.reconcile, 'Failed refill still refreshes committed selection')
check(stock.ammo_revolver_express == 10 and items[1].metadata.ammo.loaded == 0, 'Failed refill preserves stock')
local definition = DefinitionRegistry.Get('weapon', 'rifle_elephant').value
check(not WeaponValidation.AcceptsAmmunition(definition, 'ammo_rifle_regular'), 'Elephant rejects regular rifle ammo')
definition.ammunitionTypes = 'invalid'
check(not WeaponValidation.Definition(definition, 'weapon'), 'Malformed allowlist returns validation failure')
print(('Ammunition regression checks: %d passed'):format(passed))
