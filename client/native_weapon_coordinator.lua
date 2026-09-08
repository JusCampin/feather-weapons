-- Owns native restore preparation and shared ammunition windows. Matching-hash
-- weapon instances are intentionally unsupported by the production runtime.
FeatherNativeWeaponCoordinator = {}

local lifecycle = {
    epoch = 0,
    state = 'idle',
    reason = 'initial',
    slots = {},
    ammoWindows = {}
}

local function CopySlots()
    local result = {}
    for slot, value in pairs(lifecycle.slots) do
        result[slot] = {
            itemInstanceId = value.itemInstanceId,
            nativeWeaponName = value.nativeWeaponName,
            guidRecord = value.guidRecord
        }
    end
    return result
end

local function CopyAmmoWindows()
    local result = {}
    for nativeAmmoName, value in pairs(lifecycle.ammoWindows) do
        result[nativeAmmoName] = {
            ceiling = value.ceiling,
            authorized = value.authorized,
            observed = value.observed
        }
    end
    return result
end

local function Transition(state, reason)
    lifecycle.state = state
    lifecycle.reason = reason
end

local function Failure(code, message)
    Transition('failed', code)
    return { ok = false, code = code, message = message }
end

function FeatherNativeWeaponCoordinator.GetStatus()
    return {
        epoch = lifecycle.epoch,
        state = lifecycle.state,
        reason = lifecycle.reason,
        slots = CopySlots(),
        ammoWindows = CopyAmmoWindows()
    }
end

function FeatherNativeWeaponCoordinator.Release(reason)
    lifecycle.epoch = lifecycle.epoch + 1
    Transition('releasing', reason or 'released')
    lifecycle.slots = {}
    lifecycle.ammoWindows = {}
    Transition('idle', reason or 'released')
    return {}
end

-- Character transitions can leave RedM-owned weapon entries in the new ped's
-- carried inventory even though Feather's client state is empty. Building a
-- matching pair on top of those entries makes the wheel collapse one copy by
-- hash. Start a character restore from an empty native inventory, then wait
-- for RedM to expose a stable carried-weapons container before reconciliation.
function FeatherNativeWeaponCoordinator.PrepareCharacterRestore(ped, timeoutMs)
    if not ped or ped == 0 then
        return Failure('invalid_ped', 'A player ped is required for character restore.')
    end

    FeatherNativeWeaponCoordinator.Release('character_restore')
    Transition('preparing', 'character_restore')
    RemoveAllPedWeapons(ped, true, true)
    Wait(1000)

    if not FeatherGuidWeapons.AwaitInventoryReady(timeoutMs or 5000) then
        return Failure('inventory_unavailable',
            'Carried weapon inventory did not stabilize after the native reset.')
    end

    Transition('idle', 'character_restore_prepared')
    return { ok = true, epoch = lifecycle.epoch }
end

local function GroupAmmunition(slots)
    local groups = {}
    for _, state in pairs(slots or {}) do
        if state and state.nativeAmmoName then
            local group = groups[state.nativeAmmoName] or { authorized = 0 }
            group.authorized = group.authorized + math.max(0, math.floor(tonumber(state.ammo) or 0))
            groups[state.nativeAmmoName] = group
        end
    end
    return groups
end

-- RedM may expose less ammunition than Feather's equipped item instances own.
-- Remember the largest observed native window separately from authoritative
-- ownership so a capped pool is never mistaken for lost Inventory ammunition.
function FeatherNativeWeaponCoordinator.TrackAmmoWindows(ped, slots)
    local groups = GroupAmmunition(slots)
    for nativeAmmoName, group in pairs(groups) do
        local observed = math.max(0, math.floor(tonumber(
            GetPedAmmoByType(ped, joaat(nativeAmmoName))) or 0))
        local window = lifecycle.ammoWindows[nativeAmmoName] or { ceiling = 0 }
        window.ceiling = math.max(window.ceiling, observed)
        window.authorized = group.authorized
        window.observed = observed
        lifecycle.ammoWindows[nativeAmmoName] = window
    end
    return lifecycle.ammoWindows
end

function FeatherNativeWeaponCoordinator.ReplenishAmmoWindows(ped, slots)
    local groups = GroupAmmunition(slots)
    FeatherNativeWeaponCoordinator.TrackAmmoWindows(ped, slots)
    local results = {}
    for nativeAmmoName, group in pairs(groups) do
        local window = lifecycle.ammoWindows[nativeAmmoName]
        local current = math.max(0, math.floor(tonumber(
            GetPedAmmoByType(ped, joaat(nativeAmmoName))) or 0))
        local target = math.min(group.authorized, math.max(current, window.ceiling))
        -- Feather ownership is authoritative in both directions. RedM can
        -- leave the native pool one round above the committed pair after a
        -- GUID checkpoint; treating replenishment as increase-only preserves
        -- that free round indefinitely.
        if current ~= target then
            SetPedAmmoByType(ped, joaat(nativeAmmoName), target)
        end
        window.authorized = group.authorized
        window.observed = math.max(0, math.floor(tonumber(
            GetPedAmmoByType(ped, joaat(nativeAmmoName))) or 0))
        results[nativeAmmoName] = window.observed
    end
    return results
end
