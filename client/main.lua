FeatherWeaponsClient = {}
local clientContract = 4
local equipped, offhand, pendingToken, pendingNativeWeaponName = nil, nil, nil, nil
local extraSlots = { shoulder = nil, back = nil }
local extraObserved = { shoulder = nil, back = nil }
local extraSyncInFlight = { shoulder = false, back = false }
local longgunReloadInFlight = false
local syncInFlight, desiredAmmo, desiredLoaded = false, nil, nil
local unloadInFlight, unloadQueued = false, false
local inventoryWeaponInFlight = false
local attachmentReconcileUntil = 0
local BeginUnload
local FlushExtraSlot
local FlushPairConsumption
local RegisterCharacterLogoutCheckpoint
local RemoveNativeWeapon
local observerCorrectionPending = false
local singleRestoreSequence = 0
local singleNativeReady = false
local presentationRestoreInFlight = false
local checkpointWaiters = {}
local nativeRemoveReason = joaat('REMOVE_REASON_CLIENT_PURGED')
local pairSyncInFlight = false
local pairCheckpointPending = false
local pairObserved = nil
local pairConsumed = { primary = 0, offhand = 0 }
local pairSingleFallback = nil
local pairFallbackPending = nil
local offhandEntitlements = {}
local offhandRecoveryInFlight = false
local holsterSequence = 0
local maintenanceSyncInFlight = {}
local maintenanceBatchInFlight = false
local inventoryMutationCooldownUntil = 0

local function NativeTrue(value)
    return value == true or value == 1
end

local function RemoveNativePairCopies()
    FeatherNativeWeaponCoordinator.Release('pair_removed')
end

local function PairNativeClips(primary, secondary)
    if type(primary) ~= 'table' or type(primary.nativeWeaponName) ~= 'string'
        or type(secondary) ~= 'table' or type(secondary.nativeWeaponName) ~= 'string' then
        return false, 0, false, 0
    end

    local ped = PlayerPedId()
    local primaryOk, primaryLoaded = GetAmmoInClip(ped, joaat(primary.nativeWeaponName))
    local offhandOk, offhandLoaded = GetAmmoInClip(ped, joaat(secondary.nativeWeaponName))

    return NativeTrue(primaryOk), primaryLoaded, NativeTrue(offhandOk), offhandLoaded
end

local function ObservablePairClips(primary, secondary)
    if type(primary) ~= 'table' or type(primary.nativeWeaponName) ~= 'string'
        or type(secondary) ~= 'table' or type(secondary.nativeWeaponName) ~= 'string' then
        return false, 0, false, 0
    end

    if pairSingleFallback == 'primary' then
        local ok, loaded = GetAmmoInClip(PlayerPedId(), joaat(primary.nativeWeaponName))
        return NativeTrue(ok), loaded, true, 0
    end

    if pairSingleFallback == 'offhand' then
        local ok, loaded = GetAmmoInClip(PlayerPedId(), joaat(secondary.nativeWeaponName))
        return true, 0, NativeTrue(ok), loaded
    end

    return PairNativeClips(primary, secondary)
end

local function PairNativeTotal(primary, secondary)
    if type(primary) ~= 'table' or type(primary.nativeAmmoName) ~= 'string'
        or type(secondary) ~= 'table' or type(secondary.nativeAmmoName) ~= 'string' then
        return 0
    end

    local ped = PlayerPedId()
    local primaryTotal = math.max(0, math.floor(tonumber(GetPedAmmoByType(ped, joaat(primary.nativeAmmoName))) or 0))
    if primary.nativeAmmoName == secondary.nativeAmmoName then return primaryTotal end

    return primaryTotal + math.max(0, math.floor(tonumber(GetPedAmmoByType(ped, joaat(secondary.nativeAmmoName))) or 0))
end

local function IsDualSidearmPair(primary, secondary)
    if type(primary) ~= 'table' or type(primary.definitionId) ~= 'string'
        or type(secondary) ~= 'table' or type(secondary.definitionId) ~= 'string' then
        return false
    end

    local primaryDefinition = WeaponDefinitionCatalog.weapons[primary.definitionId]
    local secondaryDefinition = WeaponDefinitionCatalog.weapons[secondary.definitionId]

    return primaryDefinition and secondaryDefinition
        and primaryDefinition.slot == 'sidearm' and secondaryDefinition.slot == 'sidearm'
end

local function ActivateLoadedPairSlot(ped, slot, state)
    pairSingleFallback = slot
    SetAllowDualWield(ped, false)
    local depleted = slot == 'primary' and offhand or equipped
    if depleted and depleted.nativeWeaponName then
        RemoveNativeWeapon(ped, joaat(depleted.nativeWeaponName))
    end
    -- Once dual wield is disabled, the surviving weapon must become the
    -- primary-hand selection (attach point 0), regardless of which pair slot
    -- owned it. Passing its holster point leaves RedM on the empty primary.
    SetCurrentPedWeapon(ped, joaat(state.nativeWeaponName), true, 0, false, false)
    Wait(0)
    if Config.DevMode then
        local selectedOk, selectedHash = GetCurrentPedWeapon(ped, true, 0, false)
        print(('[feather-weapons] pair depleted; single-weapon fallback slot=%s weapon=%s selected=%s/%s')
            :format(slot, tostring(state.nativeWeaponName), tostring(selectedOk), tostring(selectedHash)))
    end
end

local function AddOffhandEntitlement(itemName, slotId)
    local inventoryId = 1
    local itemHash = joaat(itemName)
    -- InventoryGetInventoryItemCountWithItemid
    local existing = math.max(0,
        math.floor(tonumber(Citizen.InvokeNative(0xE787F05DFC977BDE, inventoryId, itemHash, false)) or 0))
    if existing > 0 then return true end

    local characterGuid = FeatherGuidWeapons.ResolveGuid(inventoryId, nil, joaat('CHARACTER'), 0xA1212100)
    local wardrobeGuid = characterGuid and
        FeatherGuidWeapons.ResolveGuid(inventoryId, characterGuid, joaat('WARDROBE'), 0x3DABBFA7) or nil
    if not wardrobeGuid then return false end

    local itemGuid = FeatherGuidWeapons.NewBuffer(8 * 13)
    local added = Citizen.InvokeNative(0xCB5D11F9508A928D, -- InventoryAddItemWithGuid
        inventoryId,
        itemGuid,
        wardrobeGuid,
        itemHash,
        slotId,
        1,
        joaat('ADD_REASON_DEFAULT')
    )
    if not NativeTrue(added) then return false end

    -- InventoryEquipItemWithGuid
    if not NativeTrue(Citizen.InvokeNative(0x734311E2852760D0, inventoryId, itemGuid, true)) then
        Citizen.InvokeNative(0x3E4E811480B3AE79, inventoryId, itemGuid, 1,
            joaat('REMOVE_REASON_DEFAULT'))
        return false
    end

    offhandEntitlements[#offhandEntitlements + 1] = {
        inventoryId = inventoryId,
        guid = itemGuid,
        itemName = itemName
    }
    return true
end

local function EnsureOffhandEntitlement()
    if not (Config.Offhand and Config.Offhand.provisionNativeEntitlement) then
        return NativeTrue(GetAllowDualWield(PlayerPedId()))
    end

    local provisioned = true
    for _, entitlement in ipairs(Config.Offhand.nativeEntitlements) do
        if not AddOffhandEntitlement(entitlement.itemName, entitlement.slotId) then
            provisioned = false
            break
        end
    end
    SetAllowDualWield(PlayerPedId(), true)

    return provisioned and NativeTrue(GetAllowDualWield(PlayerPedId()))
end

local function RemoveOffhandEntitlements()
    for index = #offhandEntitlements, 1, -1 do
        local value = offhandEntitlements[index]
        Citizen.InvokeNative(0x3E4E811480B3AE79, -- InventoryRemoveInventoryItemWithGuid
            value.inventoryId,
            value.guid,
            1,
            joaat('REMOVE_REASON_DEFAULT')
        )
    end
    offhandEntitlements = {}
end

RemoveNativeWeapon = function(ped, weaponHash)
    RemoveWeaponFromPed(ped, weaponHash, true, nativeRemoveReason)
end

local function ResolveCheckpointWaiters(result)
    local waiters = checkpointWaiters
    checkpointWaiters = {}
    for _, callback in ipairs(waiters) do
        callback(result)
    end
end

local function Notify(message)
    local called, result = pcall(function()
        return exports['feather-notify']:ShowNotification({
            style = 'right',
            message = message,
            duration = 3000
        })
    end)

    if not called then
        result = { ok = false, code = 'provider_unavailable' }
    end

    if (not result or result.ok ~= true) and Config.DevMode then
        print(('[feather-weapons] %s'):format(message))
    end
end

local function SameInstance(left, right)
    return left ~= nil and right ~= nil and tostring(left) == tostring(right)
end

local function SelectNativeAmmoType(ped, nativeWeaponName, nativeAmmoName)
    local weaponHash, ammoHash = joaat(nativeWeaponName), joaat(nativeAmmoName)
    -- Inventory use owns selection. The wheel must not select an unescrowed
    -- pool and turn its zero count into a false consumption checkpoint.
    for _, definition in pairs(WeaponDefinitionCatalog.weapons) do
        if definition.nativeWeaponName == nativeWeaponName then
            for _, id in ipairs(definition.ammunitionTypes) do
                local candidate = joaat(WeaponDefinitionCatalog.ammunition[id].nativeAmmoName)
                if candidate ~= ammoHash then
                    Citizen.InvokeNative(0xF0D728EEA3C99775, ped, weaponHash, candidate)
                end
            end
            break
        end
    end
    Citizen.InvokeNative(0x23FB9FACA28779C1, ped, weaponHash, ammoHash)
    Citizen.InvokeNative(0xCC9C4393523833E2, ped, weaponHash, ammoHash)
end

local function SetNativeAmmo(nativeAmmoName, amount, nativeWeaponName, loaded)
    if not nativeAmmoName then return end

    local ped = PlayerPedId()
    local ammoHash = joaat(nativeAmmoName)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local clipLoaded = loaded ~= nil
        and math.max(0, math.min(amount, math.floor(tonumber(loaded) or 0))) or nil
    local before = GetPedAmmoByType(ped, ammoHash)
    if nativeWeaponName and clipLoaded ~= nil then
        SetAmmoInClip(ped, joaat(nativeWeaponName), clipLoaded)
    end

    -- Apply the clip first and the approved total once. Setting the total
    -- before the clip causes RedM to add the clip a second time.
    Citizen.InvokeNative(0x5FD1E1F011E76D7E, ped, ammoHash, amount) -- SetPedAmmoByType

    if Config.DevMode then
        local afterTotal = GetPedAmmoByType(ped, ammoHash)
        print(('[feather-weapons] native ammo targetTotal=%s beforeTotal=%s afterTotal=%s loaded=%s'):format(
            tostring(amount), tostring(before), tostring(afterTotal), tostring(clipLoaded)))
    end
end

local function ApplyNativeAttachments(nativeWeaponName, attachments)
    local ped = PlayerPedId()
    local weaponHash = joaat(nativeWeaponName)
    for _, attachment in ipairs(attachments or {}) do
        local componentHash = joaat(attachment.nativeComponentName)
        local modelHash = Citizen.InvokeNative(0x59DE03442B6C9598, componentHash) -- GetWeaponComponentTypeModel
        if modelHash and modelHash ~= 0 then
            RequestModel(modelHash, false)
            local attempts = 0
            while not HasModelLoaded(modelHash) and attempts < 100 do
                attempts = attempts + 1
                Wait(0)
            end
        end

        Citizen.InvokeNative(0x74C9090FDD1BB48E, ped, componentHash, weaponHash, true) -- GiveWeaponComponentToEntity

        if modelHash and modelHash ~= 0 then
            SetModelAsNoLongerNeeded(modelHash)
        end
    end
end

local function ScheduleAttachmentReconciliation(nativeWeaponName, attachments)
    if not attachments or #attachments == 0 then return end

    attachmentReconcileUntil = GetGameTimer() + 15000
    for _, delay in ipairs({ 250, 1000 }) do
        SetTimeout(delay, function()
            local expected = (equipped and equipped.nativeWeaponName == nativeWeaponName)
                or pendingNativeWeaponName == nativeWeaponName
            if expected then
                ApplyNativeAttachments(nativeWeaponName, attachments)
            end
        end)
    end
end

local function GiveApprovedNativeWeapon(nativeWeaponName, nativeAmmoName, amount, loaded, attachments, attachPoint)
    local ped = PlayerPedId()
    local ammoHash = nativeAmmoName and joaat(nativeAmmoName) or nil
    local weaponHash = joaat(nativeWeaponName)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local before = ammoHash and GetPedAmmoByType(ped, ammoHash) or nil
    -- RedM retains hidden clip state by weapon hash after removal. Clear that
    -- cache before recreating an Inventory-authorized weapon instance.
    SetPedAmmo(ped, weaponHash, 0)
    GiveWeaponToPed(
        ped,
        weaponHash,
        0,
        false,
        true,
        math.floor(tonumber(attachPoint) or 0),
        false,
        0.5,
        1.0,
        joaat('ADD_REASON_DEFAULT'),
        true,
        0.0,
        false
    )

    if ammoHash then
        SelectNativeAmmoType(ped, nativeWeaponName, nativeAmmoName)
        SetPedAmmoByType(ped, ammoHash, 0)
    end

    loaded = math.max(0, math.min(amount, math.floor(tonumber(loaded) or 0)))
    SetAmmoInClip(ped, weaponHash, loaded)
    if ammoHash then
        SetPedAmmoByType(ped, ammoHash, amount)
    end

    ApplyNativeAttachments(nativeWeaponName, attachments)
    ScheduleAttachmentReconciliation(nativeWeaponName, attachments)

    if Config.DevMode then
        local after = ammoHash and GetPedAmmoByType(ped, ammoHash) or nil
        print(('[feather-weapons] native weapon granted total=%s nativeTotal=%s loaded=%s beforeTotal=%s'):format(
            tostring(amount), tostring(after), tostring(loaded), tostring(before)))
    end
end

local function RestoreApprovedNativePair(primary, secondary)
    if type(primary) ~= 'table' or type(primary.nativeWeaponName) ~= 'string'
        or type(primary.nativeAmmoName) ~= 'string'
        or type(secondary) ~= 'table' or type(secondary.nativeWeaponName) ~= 'string'
        or type(secondary.nativeAmmoName) ~= 'string' then
        return false, 'Approved weapon pair state is incomplete.'
    end

    local primaryAmmo = math.max(0, math.floor(tonumber(primary.ammo) or 0))
    local secondaryAmmo = math.max(0, math.floor(tonumber(secondary.ammo) or 0))
    local primaryLoaded = math.max(0, math.floor(tonumber(primary.loaded) or 0))
    local secondaryLoaded = math.max(0, math.floor(tonumber(secondary.loaded) or 0))
    local primaryReserve = math.max(0, math.floor(tonumber(primary.reserve) or (primaryAmmo - primaryLoaded)))
    local secondaryReserve = math.max(0, math.floor(tonumber(secondary.reserve) or (secondaryAmmo - secondaryLoaded)))
    local dualSidearms = IsDualSidearmPair(primary, secondary)
    if dualSidearms and not EnsureOffhandEntitlement() then
        return false, 'Offhand holster entitlement is unavailable.'
    end

    local ped = PlayerPedId()
    local primaryPoint = math.floor(tonumber(Config.Offhand.primaryAttachPoint) or 2)
    local offhandPoint = math.floor(tonumber(Config.Offhand.offhandAttachPoint) or 3)
    local primaryHash = joaat(primary.nativeWeaponName)
    local secondaryHash = joaat(secondary.nativeWeaponName)
    local identical = primaryHash == secondaryHash
    if identical then
        return false, 'Matching weapon models cannot be equipped together.'
    end

    local sharedAmmo = primary.nativeAmmoName == secondary.nativeAmmoName
    if dualSidearms then
        GiveWeaponToPed(ped, primaryHash, 0, true, false,
            primaryPoint, false, 0.5, 1.0, joaat('ADD_REASON_DEFAULT'), true, 0.0, false)

        GiveWeaponToPed(ped, secondaryHash, 0, true, false,
            offhandPoint, false, 0.5, 1.0, joaat('ADD_REASON_DEFAULT'), true, 0.0, false)
    else
        -- A mixed sidearm/long-gun loadout is not a dual-wield pair. Let RedM
        -- place both ordinary weapons in their native wheel/holster slots.
        GiveApprovedNativeWeapon(primary.nativeWeaponName, primary.nativeAmmoName,
            primaryAmmo, primaryLoaded, primary.attachments)
        GiveApprovedNativeWeapon(secondary.nativeWeaponName, secondary.nativeAmmoName,
            secondaryAmmo, secondaryLoaded, secondary.attachments)
    end

    -- Select the approved type before native reload; identical copies require
    -- GUID addressing because a hash cannot distinguish the two inventories.
    SelectNativeAmmoType(ped, primary.nativeWeaponName, primary.nativeAmmoName)
    SelectNativeAmmoType(ped, secondary.nativeWeaponName, secondary.nativeAmmoName)
    -- Shared pools are seeded as aggregate reserve; distinct pools use the
    -- per-hand conventions documented below.
    if sharedAmmo then
        SetPedAmmoByType(ped, joaat(primary.nativeAmmoName), math.max(0,
            primaryAmmo + secondaryAmmo - primaryLoaded - secondaryLoaded))
    else
        -- Seed both reserve pools before materializing their clips.
        SetPedAmmoByType(ped, joaat(primary.nativeAmmoName), primaryReserve)
        SetPedAmmoByType(ped, joaat(secondary.nativeAmmoName), secondaryReserve)
    end

    local primaryReady, secondaryReady = false, false
    for _ = 1, 40 do
        SetAmmoInClip(ped, primaryHash, primaryLoaded)
        SetAmmoInClip(ped, secondaryHash, secondaryLoaded)
        local primaryOk, observedPrimaryLoaded = GetAmmoInClip(ped, primaryHash)
        local secondaryOk, observedSecondaryLoaded = GetAmmoInClip(ped, secondaryHash)
        primaryReady = NativeTrue(primaryOk)
            and math.max(0, math.floor(tonumber(observedPrimaryLoaded) or 0)) == primaryLoaded
        secondaryReady = NativeTrue(secondaryOk)
            and math.max(0, math.floor(tonumber(observedSecondaryLoaded) or 0)) == secondaryLoaded
        if primaryReady and secondaryReady then break end
        Wait(50)
    end

    if not primaryReady or not secondaryReady then
        return false, 'Native weapon pair did not become ready.'
    end

    if sharedAmmo then
        -- Depending on which hand RedM activates while the GUIDs materialize,
        -- SetAmmoInClip can leave the shared pool counting only one clip. Once
        -- both clips exist, assert the complete authorized aggregate and then
        -- reassert each clip without changing per-item escrow ownership.
        SetPedAmmoByType(ped, joaat(primary.nativeAmmoName),
            math.max(0, primaryAmmo + secondaryAmmo))
        SetAmmoInClip(ped, primaryHash, primaryLoaded)
        SetAmmoInClip(ped, secondaryHash, secondaryLoaded)
        SetPedAmmoByType(ped, joaat(primary.nativeAmmoName),
            math.max(0, primaryAmmo + secondaryAmmo))
    end

    ApplyNativeAttachments(primary.nativeWeaponName, primary.attachments)
    ApplyNativeAttachments(secondary.nativeWeaponName, secondary.attachments)

    if dualSidearms then
        SetCurrentPedWeapon(ped, primaryHash, true, primaryPoint, false, false)
    end

    if not sharedAmmo then
        -- Before the offhand clip exists, RedM may leave that pool at the raw
        -- reserve value. Reapplying reserve after activation makes the native
        -- total include the offhand clip exactly once without mutating the
        -- selected primary weapon.
        Wait(0)
        SetPedAmmoByType(ped, joaat(secondary.nativeAmmoName), secondaryReserve)
    end

    return true
end

local function NativePairAvailable(primary, secondary)
    if IsDualSidearmPair(primary, secondary)
        and not NativeTrue(GetAllowDualWield(PlayerPedId())) then
        return false
    end

    local primaryOk, _, secondaryOk = PairNativeClips(primary, secondary)
    return primaryOk and secondaryOk
end

local function ResetNativeAmmo(reason, nativeAmmoName)
    if not (Config.Runtime and Config.Runtime.authoritativeNativeAmmo) then return end

    local ped = PlayerPedId()
    local before = nativeAmmoName and GetPedAmmoByType(ped, joaat(nativeAmmoName)) or nil
    Citizen.InvokeNative(0x1B83C0DEEBCBB214, ped) -- RemoveAllPedAmmo
    if Config.DevMode then
        local after = nativeAmmoName and GetPedAmmoByType(ped, joaat(nativeAmmoName)) or nil
        print(('[feather-weapons] native ammo reset reason=%s before=%s after=%s'):format(
            tostring(reason), tostring(before), tostring(after)))
    end
end

local function RestoreApprovedNativeWeapon(nativeWeaponName, nativeAmmoName, amount, loaded, attachments)
    RemoveNativeWeapon(PlayerPedId(), joaat(nativeWeaponName))
    ResetNativeAmmo('ammo-restored', nativeAmmoName)
    GiveApprovedNativeWeapon(nativeWeaponName, nativeAmmoName, amount, loaded, attachments)
end

local function ClearNativeWeapon()
    holsterSequence = holsterSequence + 1
    presentationRestoreInFlight = false
    singleRestoreSequence = singleRestoreSequence + 1
    singleNativeReady = false
    local nativeWeaponName = equipped and equipped.nativeWeaponName or pendingNativeWeaponName
    local nativeAmmoName = equipped and equipped.nativeAmmoName or nil
    RemoveNativePairCopies()

    if nativeWeaponName then
        RemoveNativeWeapon(PlayerPedId(), joaat(nativeWeaponName))
    end

    if offhand and offhand.nativeWeaponName then
        RemoveNativeWeapon(PlayerPedId(), joaat(offhand.nativeWeaponName))
    end

    for _, slot in ipairs({ 'shoulder', 'back' }) do
        local state = extraSlots[slot]
        if state and state.nativeWeaponName then
            RemoveNativeWeapon(PlayerPedId(), joaat(state.nativeWeaponName))
        end
    end

    ResetNativeAmmo('weapon-cleared', nativeAmmoName)
    RemoveOffhandEntitlements()

    equipped, offhand, pendingToken, pendingNativeWeaponName, desiredAmmo, desiredLoaded, syncInFlight = nil, nil, nil, nil, nil, nil, false
    extraSlots = { shoulder = nil, back = nil }
    extraObserved = { shoulder = nil, back = nil }
    extraSyncInFlight = { shoulder = false, back = false }
    pairSyncInFlight, pairCheckpointPending, pairObserved = false, false, nil
    pairConsumed = { primary = 0, offhand = 0 }
    pairSingleFallback = nil
    pairFallbackPending = nil
    unloadInFlight, unloadQueued = false, false
    observerCorrectionPending = false
    ResolveCheckpointWaiters({ ok = false, code = 'session_cleared', message = 'Weapon session was cleared.' })
    attachmentReconcileUntil = 0
end

local function SlotState(slot)
    if slot == 'primary' then return equipped end

    if slot == 'offhand' then return offhand end

    return extraSlots[slot]
end

local function SlotLabel(slot)
    return ({ primary = 'Primary', offhand = 'Offhand', shoulder = 'Shoulder', back = 'Back' })[slot] or slot
end

local function RefreshSharedLonggunPools()
    local pools = {}
    for _, slot in ipairs({ 'shoulder', 'back' }) do
        local state = extraSlots[slot]
        if state and type(state.nativeAmmoName) == 'string' then
            local observed = extraObserved[slot]
            local pool = pools[state.nativeAmmoName] or {
                count = 0, authorized = 0, loaded = 0, weapons = {}
            }
            local consumed = math.max(0, math.floor(tonumber(observed and observed.consumed) or 0))
            local loaded = math.max(0, math.floor(tonumber(observed and observed.loaded)
                or tonumber(state.loaded) or 0))
            pool.count = pool.count + 1
            pool.authorized = pool.authorized
                + math.max(0, math.floor(tonumber(state.ammo) or 0) - consumed)
            pool.loaded = pool.loaded + loaded
            pool.weapons[#pool.weapons + 1] = {
                nativeWeaponName = state.nativeWeaponName,
                loaded = loaded
            }
            pools[state.nativeAmmoName] = pool
        end
    end

    local ped = PlayerPedId()
    for nativeAmmoName, pool in pairs(pools) do
        if pool.count > 1 then
            SetPedAmmoByType(ped, joaat(nativeAmmoName), pool.loaded)
            for _, weapon in ipairs(pool.weapons) do
                if type(weapon.nativeWeaponName) == 'string' then
                    SetAmmoInClip(ped, joaat(weapon.nativeWeaponName), weapon.loaded)
                end
            end
            SetPedAmmoByType(ped, joaat(nativeAmmoName), pool.loaded)
            if Config.DevMode then
                print(('[feather-weapons] shared long-gun pool authorized=%d nativeClips=%d')
                    :format(pool.authorized, pool.loaded))
            end
        end
    end
end

local function ClearSidearmsPreservingLongguns()
    RemoveNativePairCopies()
    if equipped and equipped.nativeWeaponName then
        RemoveNativeWeapon(PlayerPedId(), joaat(equipped.nativeWeaponName))
    end

    if offhand and offhand.nativeWeaponName then
        RemoveNativeWeapon(PlayerPedId(), joaat(offhand.nativeWeaponName))
    end

    RemoveOffhandEntitlements()
    equipped, offhand, desiredAmmo, desiredLoaded, syncInFlight = nil, nil, nil, nil, false
    pairSyncInFlight, pairCheckpointPending, pairObserved = false, false, nil
    pairConsumed = { primary = 0, offhand = 0 }
    pairSingleFallback = nil
    pairFallbackPending = nil
end

local function ApprovedState(approved)
    return {
        slot = approved.slot or 'primary',
        itemInstanceId = approved.itemInstanceId,
        definitionId = approved.definitionId,
        nativeWeaponName = approved.nativeWeaponName,
        ammunitionType = approved.ammunitionType,
        nativeAmmoName = approved.nativeAmmoName,
        ammo = tonumber(approved.ammo) or 0,
        condition = tonumber(approved.condition),
        maintenance = type(approved.maintenance) == 'table' and approved.maintenance or {
            degradation = 0.0,
            permanentDegradation = 0.0,
            damage = 0.0,
            dirt = 0.0,
            soot = 0.0
        },
        loaded = tonumber(approved.loaded) or 0,
        reserve = tonumber(approved.reserve) or 0,
        capacity = math.max(0, math.floor(tonumber(approved.capacity) or 0)),
        generation = tonumber(approved.generation),
        sessionId = approved.sessionId,
        attachments = approved.attachments or {}
    }
end

local function AwaitSingleNativeRestore(state)
    singleRestoreSequence = singleRestoreSequence + 1
    local sequence = singleRestoreSequence
    singleNativeReady = false
    CreateThread(function()
        local ped = PlayerPedId()
        local weaponHash = joaat(state.nativeWeaponName)
        local ammoHash = joaat(state.nativeAmmoName)
        for _ = 1, 40 do
            if sequence ~= singleRestoreSequence or not equipped
                or not SameInstance(equipped.itemInstanceId, state.itemInstanceId)
                or equipped.generation ~= state.generation then
                return
            end

            local clipOk = GetAmmoInClip(ped, weaponHash)
            local nativeTotal = math.max(0, math.floor(tonumber(GetPedAmmoByType(ped, ammoHash)) or 0))
            if NativeTrue(clipOk) and nativeTotal == state.ammo then
                singleNativeReady = true
                if Config.DevMode then
                    print(('[feather-weapons] native single weapon ready item=%s total=%s')
                        :format(tostring(state.itemInstanceId), tostring(nativeTotal)))
                end
                return
            end
            Wait(50)
        end

        if Config.DevMode and sequence == singleRestoreSequence then
            print(('[feather-weapons] native single weapon restore deferred item=%s expectedTotal=%s')
                :format(tostring(state.itemInstanceId), tostring(state.ammo)))
        end
    end)
end

local function ApplySlotMaintenance(slot, state)
    if not state then return false end

    return FeatherNativeMaintenance.Apply(PlayerPedId(), slot, state)
end

local function ScheduleMaintenanceRestore()
    for _, delay in ipairs({ 0, 250, 1000 }) do
        SetTimeout(delay, function()
            ApplySlotMaintenance('primary', equipped)
            ApplySlotMaintenance('offhand', offhand)
            ApplySlotMaintenance('shoulder', extraSlots.shoulder)
            ApplySlotMaintenance('back', extraSlots.back)
        end)
    end
end

local function SyncSlotMaintenance(slot, state, callback)
    local cooldown = inventoryMutationCooldownUntil - GetGameTimer()
    if cooldown > 0 then
        SetTimeout(cooldown, function() SyncSlotMaintenance(slot, state, callback) end)
        return
    end

    if not state or maintenanceSyncInFlight[slot] then
        if callback then callback({ ok = true, value = { skipped = true } }) end
        return
    end

    local ammoBusy = (slot == 'primary' and (syncInFlight or pairSyncInFlight))
        or (slot == 'offhand' and pairSyncInFlight)
        or (extraSyncInFlight[slot] == true)
    if ammoBusy then
        if callback then callback({ ok = true, value = { deferred = true } }) end
        return
    end

    local observed = FeatherNativeMaintenance.Read(PlayerPedId(), slot, state)
    if not observed then
        if callback then callback({ ok = true, value = { unavailable = true } }) end
        return
    end

    local saved, changed = state.maintenance or {}, false
    for _, field in ipairs({ 'degradation', 'permanentDegradation', 'damage', 'dirt', 'soot' }) do
        if math.abs((tonumber(observed[field]) or 0.0) - (tonumber(saved[field]) or 0.0)) >= 0.005 then
            changed = true
            break
        end
    end

    if not changed then
        if callback then callback({ ok = true, value = { unchanged = true } }) end
        return
    end

    maintenanceSyncInFlight[slot] = true
    local itemInstanceId, generation = state.itemInstanceId, state.generation
    FeatherCore.RPC.Call('feather-weapons:maintenance:sync', {
        slot = slot,
        itemInstanceId = itemInstanceId,
        generation = generation,
        maintenance = observed
    }, function(result, rpcError)
        inventoryMutationCooldownUntil = GetGameTimer() + 150
        maintenanceSyncInFlight[slot] = nil
        local current = SlotState(slot)
        if current and SameInstance(current.itemInstanceId, itemInstanceId)
            and current.generation == generation and result and result.ok then
            current.maintenance = result.value.maintenance
            current.condition = tonumber(result.value.condition) or current.condition
        elseif result and not result.ok and Config.DevMode then
            local failure = result.error or result
            print(('[feather-weapons] maintenance checkpoint failed slot=%s code=%s'):format(
                slot, tostring(failure.code)))
        end

        if callback then
            callback(result or rpcError or {
                ok = false,
                code = 'maintenance_checkpoint_failed',
                message = 'Native weapon maintenance could not be saved.'
            })
        end
    end)
end

local function CheckpointMaintenance(callback)
    if maintenanceBatchInFlight then
        callback({ ok = true, value = { deferred = true } })
        return
    end

    local states = {}
    for _, slot in ipairs({ 'primary', 'offhand', 'shoulder', 'back' }) do
        local state = SlotState(slot)
        if state then states[#states + 1] = { slot = slot, state = state } end
    end

    if #states == 0 then
        callback({ ok = true, value = { skipped = true } })
        return
    end

    maintenanceBatchInFlight = true
    local failure
    local function SyncNext(index)
        if index > #states then
            maintenanceBatchInFlight = false
            callback(failure or { ok = true })
            return
        end

        local value = states[index]
        SyncSlotMaintenance(value.slot, value.state, function(result)
            if result and result.ok ~= true then failure = failure or result end
            SyncNext(index + 1)
        end)
    end
    SyncNext(1)
end

local function ApplyApprovedPair(primary, secondary)
    if equipped and offhand
        and SameInstance(equipped.itemInstanceId, primary.itemInstanceId)
        and SameInstance(offhand.itemInstanceId, secondary.itemInstanceId)
        and equipped.generation == tonumber(primary.generation)
        and offhand.generation == tonumber(secondary.generation)
        and NativePairAvailable(primary, secondary) then
        equipped, offhand = ApprovedState(primary), ApprovedState(secondary)
        ScheduleMaintenanceRestore()
        return true
    end

    ClearNativeWeapon()
    equipped, offhand = ApprovedState(primary), ApprovedState(secondary)
    local restored, message = RestoreApprovedNativePair(equipped, offhand)
    if not restored then
        ClearNativeWeapon()
        return false, message
    end

    local primaryOk, primaryLoaded, offhandOk, offhandLoaded = PairNativeClips(equipped, offhand)
    pairObserved = {
        primary = primaryOk and math.max(0, math.floor(tonumber(primaryLoaded) or 0)) or 0,
        offhand = offhandOk and math.max(0, math.floor(tonumber(offhandLoaded) or 0)) or 0,
        total = PairNativeTotal(equipped, offhand)
    }
    FeatherNativeWeaponCoordinator.TrackAmmoWindows(PlayerPedId(), {
        primary = equipped,
        offhand = offhand
    })
    pairConsumed = { primary = 0, offhand = 0 }
    SetTimeout(0, function()
        if equipped and offhand
            and SameInstance(equipped.itemInstanceId, primary.itemInstanceId)
            and SameInstance(offhand.itemInstanceId, secondary.itemInstanceId) then
            local nativeLoaded = pairObserved.primary + pairObserved.offhand
            local approvedLoaded = equipped.loaded + offhand.loaded
            if nativeLoaded > 0 or approvedLoaded == 0 then
                FlushPairConsumption()
            elseif Config.DevMode then
                print('[feather-weapons] initial pair checkpoint deferred: native clips did not materialize')
            end
        end
    end)

    if Config.DevMode then
        print(('[feather-weapons] pair restored primary=%s/%s offhand=%s/%s total=%d loaded=%d/%d')
            :format(tostring(equipped.itemInstanceId), equipped.nativeWeaponName, tostring(offhand.itemInstanceId),
                offhand.nativeWeaponName, pairObserved.total, pairObserved.primary, pairObserved.offhand))
    end
    ScheduleMaintenanceRestore()
    return true
end

local function ApplyApprovedWeapon(approved)
    local alreadyApplied = not offhand
        and ((equipped and SameInstance(equipped.itemInstanceId, approved.itemInstanceId))
            or (pendingNativeWeaponName == approved.nativeWeaponName)
        )
    if not alreadyApplied then
        ClearNativeWeapon()
        GiveApprovedNativeWeapon(approved.nativeWeaponName, approved.nativeAmmoName, approved.ammo, approved.loaded,
            approved.attachments)
    end

    equipped = ApprovedState(approved)
    desiredAmmo = equipped.ammo
    desiredLoaded = equipped.loaded
    if not alreadyApplied then
        AwaitSingleNativeRestore(equipped)
    end

    ScheduleMaintenanceRestore()
end

local function FlushConsumption()
    if maintenanceSyncInFlight.primary then
        SetTimeout(50, FlushConsumption)
        return
    end

    if syncInFlight then return end

    if not equipped then
        ResolveCheckpointWaiters({ ok = true, value = { skipped = true } })
        return
    end

    if desiredAmmo == nil or desiredAmmo > equipped.ammo then
        ResolveCheckpointWaiters({
            ok = false,
            code = 'invalid_native_state',
            message =
            'Native ammunition state is invalid.'
        })
        return
    end

    if desiredAmmo == equipped.ammo and desiredLoaded == equipped.loaded then
        ResolveCheckpointWaiters({
            ok = true,
            value = {
                total = equipped.ammo, loaded = equipped.loaded, reserve = equipped.reserve
            }
        })
        return
    end

    syncInFlight = true
    local submitted = desiredAmmo
    local submittedLoaded = desiredLoaded or (equipped.loaded or 0)
    local leaseItem = equipped.itemInstanceId
    local leaseGeneration = equipped.generation
    FeatherCore.RPC.Call('feather-weapons:ammo:sync', {
        total = submitted,
        loaded = submittedLoaded,
        itemInstanceId = leaseItem,
        generation = leaseGeneration
    }, function(result)
        syncInFlight = false
        if not equipped or not SameInstance(equipped.itemInstanceId, leaseItem)
            or equipped.generation ~= leaseGeneration then
            return
        end

        if result and result.ok then
            equipped.ammo = tonumber(result.value.total) or submitted
            equipped.loaded = tonumber(result.value.loaded) or submittedLoaded
            equipped.reserve = tonumber(result.value.reserve) or (equipped.ammo - equipped.loaded)
            equipped.condition = tonumber(result.value.condition) or equipped.condition
            if Config.DevMode then
                print(('[feather-weapons] checkpoint consumed=%s total=%s loaded=%s condition=%s'):format(
                    tostring(result.value.consumed), tostring(equipped.ammo),
                    tostring(equipped.loaded), tostring(equipped.condition)))
            end

            if result.value.broken then
                print('[feather-weapons] weapon condition is broken')
                ClearNativeWeapon()
                return
            end

            if desiredAmmo > equipped.ammo then
                desiredAmmo = equipped.ammo
            end
        else
            ResolveCheckpointWaiters(result or {
                ok = false,
                code = 'checkpoint_failed',
                message = 'Weapon state could not be saved.'
            })
            FeatherWeaponsClient.Reconcile()
            return
        end

        if desiredAmmo < equipped.ammo or desiredLoaded ~= equipped.loaded then
            FlushConsumption()
        else
            ResolveCheckpointWaiters({
                ok = true,
                value = {
                    total = equipped.ammo, loaded = equipped.loaded, reserve = equipped.reserve
                }
            })
        end

        if unloadQueued then
            unloadQueued = false
            BeginUnload()
        end
    end)
end

local function CaptureNativeState()
    if not equipped then return true end

    local ped = PlayerPedId()
    local clipOk, clipAmount = GetAmmoInClip(ped, joaat(equipped.nativeWeaponName))
    local observedTotal = math.max(0, math.floor(tonumber(
        GetPedAmmoByType(ped, joaat(equipped.nativeAmmoName))) or 0))
    if observedTotal > equipped.ammo then return false end

    desiredAmmo = observedTotal
    if clipOk == true or clipOk == 1 then
        desiredLoaded = math.max(0, math.min(observedTotal, math.floor(tonumber(clipAmount) or 0)))
    end

    return true
end

local function CapturePairNativeState()
    local primary = equipped
    local secondary = offhand
    if not primary or not secondary then return false end

    local primaryOk, primaryLoaded, offhandOk, offhandLoaded = ObservablePairClips(primary, secondary)
    if not primaryOk or not offhandOk then return false end

    local total = PairNativeTotal(primary, secondary)
    primaryLoaded = math.max(0, math.floor(tonumber(primaryLoaded) or 0))
    offhandLoaded = math.max(0, math.floor(tonumber(offhandLoaded) or 0))
    local observed = pairObserved or {
        primary = primaryLoaded,
        offhand = offhandLoaded,
        total = total
    }
    pairObserved = observed
    if primaryLoaded < observed.primary then
        pairConsumed.primary = pairConsumed.primary + (observed.primary - primaryLoaded)
    end

    if offhandLoaded < observed.offhand then
        pairConsumed.offhand = pairConsumed.offhand + (observed.offhand - offhandLoaded)
    end

    observed.primary = primaryLoaded
    observed.offhand = offhandLoaded
    observed.total = total
    return total <= (primary.ammo + secondary.ammo)
end

FlushPairConsumption = function()
    local cooldown = inventoryMutationCooldownUntil - GetGameTimer()
    if cooldown > 0 then
        SetTimeout(cooldown, FlushPairConsumption)
        return
    end

    if maintenanceSyncInFlight.primary or maintenanceSyncInFlight.offhand then
        SetTimeout(50, FlushPairConsumption)
        return
    end

    if pairSyncInFlight then return end

    local captured = CapturePairNativeState()
    local capturedBeforeFallback = pairSingleFallback and pairObserved
        and (pairConsumed.primary > 0 or pairConsumed.offhand > 0)
    if not captured and not capturedBeforeFallback then
        ResolveCheckpointWaiters({
            ok = false,
            code = 'invalid_native_state',
            message = 'Native pair ammunition state is invalid.'
        })
        return
    end

    local observed = pairObserved
    local primary = equipped
    local secondary = offhand
    if not observed or not primary or not secondary then
        ResolveCheckpointWaiters({
            ok = false,
            code = 'pair_state_changed',
            message = 'Weapon pair changed before its ammunition checkpoint.'
        })
        return
    end

    -- RedM may reload both distinct weapon hashes from one shared native ammo
    -- pool even when only one Inventory instance owns reserve. Clamp any clip
    -- increase that the corresponding instance cannot fund before persisting it.
    if primary.nativeAmmoName == secondary.nativeAmmoName then
        local ped = PlayerPedId()
        for slot, state in pairs({ primary = primary, offhand = secondary }) do
            local consumed = pairConsumed[slot]
            local authorizedLoaded = math.max(0,
                (tonumber(state.loaded) or 0) - consumed + (tonumber(state.reserve) or 0))
            if observed[slot] > authorizedLoaded then
                SetAmmoInClip(ped, joaat(state.nativeWeaponName), authorizedLoaded)
                if Config.DevMode then
                    print(('[feather-weapons] blocked shared native reload slot=%s observed=%d restored=%d reserve=%d')
                        :format(slot, observed[slot], authorizedLoaded,
                            math.max(0, math.floor(tonumber(state.reserve) or 0))))
                end
                observed[slot] = authorizedLoaded
            end
        end
    end

    local submitted = {
        -- Native totals are only a bounded runtime window. Inventory-backed
        -- ownership is reduced exclusively by confirmed per-GUID shots.
        total = math.max(0, primary.ammo + secondary.ammo - pairConsumed.primary - pairConsumed.offhand),
        primaryLoaded = observed.primary,
        offhandLoaded = observed.offhand,
        primaryConsumed = pairConsumed.primary,
        offhandConsumed = pairConsumed.offhand,
        primaryItem = primary.itemInstanceId,
        offhandItem = secondary.itemInstanceId,
        primaryGeneration = primary.generation,
        offhandGeneration = secondary.generation
    }
    if submitted.primaryConsumed == 0 and submitted.offhandConsumed == 0
        and submitted.primaryLoaded == primary.loaded
        and submitted.offhandLoaded == secondary.loaded
        and submitted.total == primary.ammo + secondary.ammo then
        ResolveCheckpointWaiters({
            ok = true,
            value = {
                total = submitted.total,
                slots = { primary = primary, offhand = secondary }
            }
        })
        return
    end

    pairSyncInFlight = true
    FeatherCore.RPC.Call('feather-weapons:ammo:pairSync', {
        total = submitted.total,
        slots = {
            primary = {
                itemInstanceId = submitted.primaryItem,
                generation = submitted.primaryGeneration,
                loaded = submitted.primaryLoaded,
                consumed = submitted.primaryConsumed
            },
            offhand = {
                itemInstanceId = submitted.offhandItem,
                generation = submitted.offhandGeneration,
                loaded = submitted.offhandLoaded,
                consumed = submitted.offhandConsumed
            }
        }
    }, function(result)
        inventoryMutationCooldownUntil = GetGameTimer() + 150
        pairSyncInFlight = false
        local currentPrimary = equipped
        local currentOffhand = offhand
        local currentObserved = pairObserved
        if not currentPrimary or not currentOffhand or not currentObserved
            or not SameInstance(currentPrimary.itemInstanceId, submitted.primaryItem)
            or not SameInstance(currentOffhand.itemInstanceId, submitted.offhandItem) then
            return
        end

        if not result or not result.ok then
            ResolveCheckpointWaiters(result or {
                ok = false,
                code = 'checkpoint_failed',
                message = 'Weapon pair state could not be saved.'
            })
            FeatherWeaponsClient.Reconcile()
            return
        end

        for slot, state in pairs({ primary = currentPrimary, offhand = currentOffhand }) do
            local value = result.value.slots[slot]
            state.ammo = tonumber(value.total) or state.ammo
            state.loaded = tonumber(value.loaded) or state.loaded
            state.reserve = tonumber(value.reserve) or state.reserve
            state.condition = tonumber(value.condition) or state.condition
            pairConsumed[slot] = math.max(0, pairConsumed[slot] - (slot == 'primary'
                and submitted.primaryConsumed or submitted.offhandConsumed))
        end

        -- Depletion fallback is a presentation change, so apply it only after
        -- the zero-round observation has been committed to both item records.
        if pairFallbackPending and not pairSingleFallback then
            local fallbackSlot = pairFallbackPending
            local depleted = fallbackSlot == 'primary' and currentOffhand or currentPrimary
            local survivor = fallbackSlot == 'primary' and currentPrimary or currentOffhand
            if (tonumber(depleted.loaded) or 0) == 0
                and (tonumber(survivor.loaded) or 0) > 0 then
                pairFallbackPending = nil
                ActivateLoadedPairSlot(PlayerPedId(), fallbackSlot, survivor)
            end
        end

        if currentPrimary.nativeAmmoName == currentOffhand.nativeAmmoName then
            FeatherNativeWeaponCoordinator.ReplenishAmmoWindows(PlayerPedId(), {
                primary = currentPrimary,
                offhand = currentOffhand
            })
        else
            -- Independent native pools already account for their own clips.
            -- Replenishing them through SetPedAmmoByType can mint a round when
            -- RedM applies selected-weapon reserve semantics.
            FeatherNativeWeaponCoordinator.TrackAmmoWindows(PlayerPedId(), {
                primary = currentPrimary,
                offhand = currentOffhand
            })
        end
        currentObserved.total = PairNativeTotal(currentPrimary, currentOffhand)

        if pairConsumed.primary > 0 or pairConsumed.offhand > 0
            or currentObserved.primary ~= currentPrimary.loaded
            or currentObserved.offhand ~= currentOffhand.loaded then
            FlushPairConsumption()
        else
            ResolveCheckpointWaiters(result)
        end
    end)
end

function FeatherWeaponsClient.Checkpoint(callback, skipExtras)
    callback = type(callback) == 'function' and callback or function(_result) end

    local extras = {}
    for _, slot in ipairs({ 'shoulder', 'back' }) do
        if extraSlots[slot] then extras[#extras + 1] = slot end
    end
    if not skipExtras and #extras > 0 then
        local index
        index = function(position)
            if position > #extras then
                FeatherWeaponsClient.Checkpoint(callback, true)
                return
            end
            local slot = extras[position]
            FlushExtraSlot(slot, function(result)
                if not result or not result.ok then
                    callback(result); return
                end
                index(position + 1)
            end)
        end
        index(1)
        return
    end

    checkpointWaiters[#checkpointWaiters + 1] = callback
    if offhand then
        FlushPairConsumption()
        return
    end

    if not CaptureNativeState() then
        ResolveCheckpointWaiters({
            ok = false,
            code = 'invalid_native_state',
            message = 'Native ammunition exceeded the active weapon lease.'
        })
        return
    end

    FlushConsumption()
end

local function ScheduleRestoredWeaponsHolster()
    holsterSequence = holsterSequence + 1
    local sequence = holsterSequence
    presentationRestoreInFlight = true
    singleRestoreSequence = singleRestoreSequence + 1
    singleNativeReady = false
    local expected = {}
    for _, slot in ipairs(WeaponConstants.LoadoutSlots) do
        local state = SlotState(slot)
        expected[slot] = state and {
            itemInstanceId = state.itemInstanceId,
            generation = state.generation
        } or false
    end

    for _, delay in ipairs({ 0, 250, 750, 1500 }) do
        SetTimeout(delay, function()
            if sequence ~= holsterSequence then return end
            for _, slot in ipairs(WeaponConstants.LoadoutSlots) do
                local state, wanted = SlotState(slot), expected[slot]
                if (wanted == false and state ~= nil)
                    or (wanted ~= false and (not state
                        or not SameInstance(state.itemInstanceId, wanted.itemInstanceId)
                        or tonumber(state.generation) ~= tonumber(wanted.generation))) then
                    return
                end
            end
            if equipped and offhand and (equipped.loaded + offhand.loaded) > 0 then
                local primaryOk, primaryLoaded, offhandOk, offhandLoaded =
                    PairNativeClips(equipped, offhand)
                if not primaryOk or not offhandOk
                    or (math.max(0, tonumber(primaryLoaded) or 0)
                        + math.max(0, tonumber(offhandLoaded) or 0)) == 0 then
                    if Config.DevMode and delay == 1500 then
                        print('[feather-weapons] restored weapons holster deferred: native clips are not ready')
                    end
                    return
                end
            end
            -- Pair creation and native reload can select a hand after the
            -- reconcile callback returns. Reassert unarmed through that short
            -- settle window so character/resource restores finish holstered.
            local ped = PlayerPedId()
            HolsterPedWeapons(ped, true, true, true, true)
            SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true, 0, false, false)

            if delay == 1500 then
                if equipped and not offhand then
                    SetNativeAmmo(equipped.nativeAmmoName, equipped.ammo,
                        equipped.nativeWeaponName, equipped.loaded)
                    AwaitSingleNativeRestore(equipped)
                elseif equipped and offhand then
                    local primaryOk, primaryLoaded, offhandOk, offhandLoaded =
                        PairNativeClips(equipped, offhand)
                    pairObserved = {
                        primary = primaryOk and math.max(0, math.floor(tonumber(primaryLoaded) or 0)) or 0,
                        offhand = offhandOk and math.max(0, math.floor(tonumber(offhandLoaded) or 0)) or 0,
                        total = PairNativeTotal(equipped, offhand)
                    }
                end
                presentationRestoreInFlight = false
            end

            if Config.DevMode and delay == 1500 then
                print(('[feather-weapons] restored weapons holstered=%s'):format(
                    tostring(NativeTrue(Citizen.InvokeNative(0xBDD9C235D8D1052E, ped))))) -- IsPedCurrentWeaponHolstered
            end
        end)
    end
end

function FeatherWeaponsClient.Reconcile(callback, options)
    options = type(options) == 'table' and options or {}
    FeatherCore.RPC.Call('feather-weapons:state:get', {}, function(result, rpcError)
        if not result or not result.ok then
            local failure = result and result.error or rpcError
            Notify(failure and failure.message or 'Weapon state could not be restored.')
            if Config.DevMode then
                print(('[feather-weapons] reconcile failed code=%s message=%s'):format(
                    tostring(failure and failure.code), tostring(failure and failure.message)))
            end
            if callback then
                callback(result, rpcError)
            end
            return
        end

        local slots = type(result.value.slots) == 'table' and result.value.slots or {}
        if slots.primary and slots.offhand then
            local applied, message = ApplyApprovedPair(slots.primary, slots.offhand)
            if not applied then Notify(message or 'Unable to restore the weapon pair.') end
        elseif slots.primary then
            ApplyApprovedWeapon(slots.primary)
        elseif slots.shoulder or slots.back then
            ClearSidearmsPreservingLongguns()
        else
            ClearNativeWeapon()
        end

        for _, slot in ipairs({ 'shoulder', 'back' }) do
            local approved = slots[slot]
            if approved then
                local state = ApprovedState(approved)
                local previous = extraSlots[slot]
                extraSlots[slot] = state
                extraObserved[slot] = { loaded = state.loaded, consumed = 0 }
                if not previous
                    or not SameInstance(previous.itemInstanceId, state.itemInstanceId)
                    or previous.generation ~= state.generation then
                    if previous then
                        RemoveNativeWeapon(PlayerPedId(), joaat(previous.nativeWeaponName))
                    end
                    -- Feather owns the persistent logical slot, but RedM must
                    -- own the physical RIFLE/RIFLE_ALTERNATE placement. Forcing
                    -- point 9 or 10 can leave the alternate long gun visible
                    -- and selectable while unable to aim or fire.
                    GiveApprovedNativeWeapon(state.nativeWeaponName, state.nativeAmmoName,
                        state.ammo, state.loaded, state.attachments)
                end
            else
                local stale = extraSlots[slot]
                if stale then
                    if type(stale.nativeWeaponName) == 'string' then
                        RemoveNativeWeapon(PlayerPedId(), joaat(stale.nativeWeaponName))
                    end
                    extraSlots[slot], extraObserved[slot] = nil, nil
                end
            end
        end

        RefreshSharedLonggunPools()
        ScheduleMaintenanceRestore()
        if options.holster == true and (equipped or offhand or extraSlots.shoulder or extraSlots.back) then
            ScheduleRestoredWeaponsHolster()
        end

        if callback then
            callback(result)
        end
    end)
end

FlushExtraSlot = function(slot, callback)
    if maintenanceSyncInFlight[slot] then
        SetTimeout(50, function() FlushExtraSlot(slot, callback) end)
        return
    end

    local state = extraSlots[slot]
    local observed = extraObserved[slot]
    if not state or not observed or extraSyncInFlight[slot] then
        if callback then callback({ ok = true, value = { skipped = true } }) end
        return
    end

    local total = math.max(0, state.ammo - observed.consumed)
    if observed.consumed == 0 and observed.loaded == state.loaded then
        if callback then callback({ ok = true, value = state }) end
        return
    end

    extraSyncInFlight[slot] = true
    local itemInstanceId, generation = state.itemInstanceId, state.generation
    local submittedConsumed = observed.consumed
    FeatherCore.RPC.Call('feather-weapons:ammo:sync', {
        slot = slot,
        total = total,
        loaded = math.min(total, observed.loaded),
        itemInstanceId = itemInstanceId,
        generation = generation
    }, function(result, rpcError)
        extraSyncInFlight[slot] = false
        local current = extraSlots[slot]
        if not current or not SameInstance(current.itemInstanceId, itemInstanceId)
            or current.generation ~= generation then
            return
        end

        if result and result.ok then
            current.ammo = tonumber(result.value.total) or total
            current.loaded = tonumber(result.value.loaded) or observed.loaded
            current.reserve = tonumber(result.value.reserve) or (current.ammo - current.loaded)
            current.condition = tonumber(result.value.condition) or current.condition
            observed.consumed = math.max(0, observed.consumed - submittedConsumed)
            if result.value.broken then
                ClearNativeWeapon()
                FeatherWeaponsClient.Reconcile()
            end
        else
            FeatherWeaponsClient.Reconcile()
        end

        if callback then callback(result or { ok = false, error = rpcError }) end
    end)
end

local function RecoverLostOffhandEntitlement()
    if offhandRecoveryInFlight or not equipped or not offhand then return end

    offhandRecoveryInFlight = true
    FeatherWeaponsClient.Checkpoint(function(checkpoint)
        if Config.DevMode then
            print(('[feather-weapons] offhand entitlement lost nativeCheckpoint=%s recovery=authoritative')
                :format(checkpoint and checkpoint.ok and 'available' or 'unavailable'))
        end

        ClearNativeWeapon()
        FeatherWeaponsClient.Reconcile(function(result)
            offhandRecoveryInFlight = false
            if not result or not result.ok then
                Notify('Offhand entitlement was lost and the weapon pair could not be restored.')
            end
        end)
    end)
end

function FeatherWeaponsClient.Equip(itemInstanceId, callback, slot)
    slot = slot or 'auto'
    FeatherCore.RPC.Call('feather-weapons:equip:request', { itemInstanceId = itemInstanceId, slot = slot }, function(result, rpcError)
    if not result or not result.ok then
        if callback then callback(result, rpcError) end
        return
    end

    local authorization = result.value
    pendingToken, pendingNativeWeaponName = authorization.token, authorization.nativeWeaponName

    FeatherCore.RPC.Call('feather-weapons:equip:acknowledge', { token = authorization.token },
        function(ack, ackError)
            if not ack or not ack.ok then
                pendingToken, pendingNativeWeaponName = nil, nil
                if callback then
                    callback(ack, ackError)
                end
                return
            end

            pendingToken, pendingNativeWeaponName = nil, nil
            FeatherWeaponsClient.Reconcile(function(reconciled, reconcileError)
                if callback then callback(reconciled, reconcileError) end
            end)
        end)
    end)
end

function FeatherWeaponsClient.Unequip(callback, slot)
    slot = slot or 'primary'
    -- Unequip is a persistence boundary. Save every active clip before any
    -- native weapon is removed so teardown cannot be mistaken for firing.
    FeatherWeaponsClient.Checkpoint(function(checkpoint)
        if not checkpoint or checkpoint.ok ~= true then
            if callback then
                callback(checkpoint or {
                    ok = false,
                    error = { message = 'Weapon state could not be saved before unequipping.' }
                })
            end
            return
        end

        FeatherCore.RPC.Call('feather-weapons:equip:unequip', { slot = slot }, function(result, rpcError)
            if result and result.ok then
                ClearNativeWeapon()
                FeatherWeaponsClient.Reconcile()
            end

            if callback then
                callback(result, rpcError)
            end
        end)
    end)
end

-- Read-only state used by isolated development diagnostics. The probe must not
-- replace or mutate an Inventory-authorized weapon.
function FeatherWeaponsClient.GetDiagnosticState()
    if not equipped and not offhand and not extraSlots.shoulder and not extraSlots.back then
        return { equipped = false }
    end

    return {
        equipped = true,
        itemInstanceId = equipped and equipped.itemInstanceId or nil,
        definitionId = equipped and equipped.definitionId or nil,
        nativeWeaponName = equipped and equipped.nativeWeaponName or nil,
        nativeAmmoName = equipped and equipped.nativeAmmoName or nil,
        generation = equipped and equipped.generation or nil,
        sessionId = equipped and equipped.sessionId or nil,
        offhand = offhand and {
            itemInstanceId = offhand.itemInstanceId,
            definitionId = offhand.definitionId,
            nativeWeaponName = offhand.nativeWeaponName,
            generation = offhand.generation
        } or nil,
        shoulder = extraSlots.shoulder,
        back = extraSlots.back
    }
end

function FeatherWeaponsClient.Unload(amount, callback)
    FeatherCore.RPC.Call('feather-weapons:ammo:unload', { amount = amount }, function(result, rpcError)
        if result and result.ok then
            local slot = result.value.slot or 'primary'
            local state = SlotState(slot)
            if state then
                state.ammo = tonumber(result.value.total) or 0
                state.loaded = tonumber(result.value.loaded) or 0
                state.reserve = tonumber(result.value.reserve) or 0
            end

            -- Rebuild every native ammo pool from authoritative slot metadata.
            ClearNativeWeapon()
            FeatherWeaponsClient.Reconcile()
        end

        if callback then
            callback(result, rpcError)
        end
    end)
end

BeginUnload = function()
    if unloadInFlight then return end

    if not equipped and not offhand and not extraSlots.shoulder and not extraSlots.back then
        Notify('No weapon is equipped.')
        return
    end

    if equipped and (syncInFlight or (desiredAmmo ~= nil and desiredAmmo < equipped.ammo)) then
        unloadQueued = true
        FlushConsumption()
        return
    end

    local function unloadAfterCheckpoint()
        FeatherWeaponsClient.Unload(nil, function(result, rpcError)
            unloadInFlight = false
            if result and result.ok then
                Notify(('Unloaded %s round%s.'):format(
                    tostring(result.value.moved), result.value.moved == 1 and '' or 's'))
                return
            end

            local failure = result and result.error or rpcError
            Notify(failure and failure.message or 'Unable to unload.')
        end)
    end

    unloadInFlight = true
    if offhand then
        FeatherWeaponsClient.Checkpoint(function(checkpoint)
            if not checkpoint or checkpoint.ok ~= true then
                unloadInFlight = false
                local failure = checkpoint and (checkpoint.error or checkpoint)
                Notify(failure and failure.message
                    or 'Unable to checkpoint the weapon pair before unloading.')
                return
            end
            unloadAfterCheckpoint()
        end)
        return
    end
    unloadAfterCheckpoint()
end

function FeatherWeaponsClient.Repair(slot, callback)
    slot = slot or 'primary'
    local state = SlotState(slot)
    if not state then
        if callback then callback({ ok = false, error = { message = 'No weapon is equipped in that slot.' } }) end
        return
    end

    FeatherCore.RPC.Call('feather-weapons:repair', {
        slot = slot,
        itemInstanceId = state.itemInstanceId,
        generation = state.generation
    }, function(result, rpcError)
        if result and result.ok and state and SameInstance(state.itemInstanceId, result.value.itemInstanceId) then
            state.condition = tonumber(result.value.condition) or state.condition
            state.maintenance = result.value.maintenance or state.maintenance
            ScheduleMaintenanceRestore()
        end

        if callback then callback(result, rpcError) end
    end)
end

local function UseInventoryWeaponFromAuthoritativeState(itemInstanceId)
    for _, slot in ipairs({ 'shoulder', 'back' }) do
        local state = extraSlots[slot]
        if state and SameInstance(state.itemInstanceId, itemInstanceId) then
            FeatherWeaponsClient.Unequip(function(result, rpcError)
                inventoryWeaponInFlight = false
                if result and result.ok then
                    Notify('Weapon unequipped.')
                    return
                end
                local failure = result and result.error or rpcError
                Notify(failure and failure.message or 'Unable to unequip this weapon.')
            end, slot)
            return
        end
    end

    if offhand and SameInstance(offhand.itemInstanceId, itemInstanceId) then
        FeatherWeaponsClient.Unequip(function(result, rpcError)
            inventoryWeaponInFlight = false
            if result and result.ok then
                Notify('Offhand weapon unequipped.')
                return
            end

            local failure = result and result.error or rpcError
            Notify(failure and failure.message or 'Unable to unequip this weapon.')
        end, 'offhand')
        return
    end

    if equipped and SameInstance(equipped.itemInstanceId, itemInstanceId) then
        local promoting = offhand ~= nil
        FeatherWeaponsClient.Unequip(function(result, rpcError)
            inventoryWeaponInFlight = false
            if result and result.ok then
                Notify(promoting and 'Primary removed; offhand promoted.' or 'Weapon unequipped.')
                return
            end

            local failure = result and result.error or rpcError
            Notify(failure and failure.message or 'Unable to unequip this weapon.')
        end, 'primary')
        return
    end

    local requestedSlot = 'auto'
    FeatherWeaponsClient.Equip(itemInstanceId, function(result, rpcError)
        inventoryWeaponInFlight = false
        if result and result.ok then
            Notify('Weapon equipped.')
            if Config.DevMode then
                print(('[feather-weapons] inventory equip succeeded item=%s'):format(tostring(itemInstanceId)))
            end
            return
        end

        local failure = result and result.error or rpcError
        Notify(failure and failure.message or 'Unable to equip this weapon.')
        if Config.DevMode then
            print(('[feather-weapons] inventory equip failed item=%s code=%s message=%s'):format(
                tostring(itemInstanceId), tostring(failure and failure.code), tostring(failure and failure.message)))
        end
    end, requestedSlot)
end

RegisterNetEvent('feather-weapons:client:useInventoryWeapon', function(itemInstanceId)
    if inventoryWeaponInFlight then return end

    if Config.DevMode then
        print(('[feather-weapons] inventory weapon requested item=%s'):format(tostring(itemInstanceId)))
    end

    inventoryWeaponInFlight = true
    -- Inventory use is a toggle. Refresh the server-owned slots first so a
    -- resource restart cannot turn an unequip click into a duplicate equip.
    FeatherWeaponsClient.Reconcile(function(result, rpcError)
        if not result or not result.ok then
            inventoryWeaponInFlight = false
            return
        end
        UseInventoryWeaponFromAuthoritativeState(itemInstanceId)
    end)
end)

local function HandleAttachmentResult(result)
    if result and result.ok then
        local slot = result.value.slot or 'primary'
        local state = SlotState(slot)
        if not state or not SameInstance(state.itemInstanceId, result.value.itemInstanceId) then
            Notify('Weapon state changed; reconciling attachments.')
            FeatherWeaponsClient.Reconcile()
            return
        end

        state.attachments = result.value.attachments or {}
        local message = result.value.installed and 'Attachment installed.' or 'Attachment removed.'
        if offhand then
            ClearNativeWeapon()
            FeatherWeaponsClient.Reconcile(function(reconciled)
                Notify(reconciled and reconciled.ok and message
                    or 'Attachment changed, but the weapon pair could not be restored.')
            end)
        else
            RestoreApprovedNativeWeapon(state.nativeWeaponName, state.nativeAmmoName, state.ammo,
                state.loaded, state.attachments)
            Notify(message)
        end
        return
    end

    local failure = result and result.error
    Notify(failure and failure.message or 'Unable to modify this weapon.')
end

local function RequestAttachmentMutation(route, request)
    FeatherWeaponsClient.Checkpoint(function(checkpoint)
        if not checkpoint or not checkpoint.ok then
            local failure = checkpoint and checkpoint.error or nil
            Notify(failure and failure.message
                or 'Unable to checkpoint weapon ammunition before modification.')
            return
        end

        FeatherCore.RPC.Call(route, request, function(result, rpcError)
            HandleAttachmentResult(result or { ok = false, error = rpcError })
        end)
    end)
end

RegisterNetEvent('feather-weapons:client:attachmentResult', HandleAttachmentResult)

local Menu = exports['feather-menu-v2']
local ModificationMenu, RepairMenu, AmmunitionMenu
local AmmunitionActivityPage, ammunitionActivityInFlight = nil, false
local ammunitionActivityReturnPage = nil
local ammunitionActivitySequence = 0
local ModificationPages = {}
local ammunitionInventory = {}
local menuSequence = 0

local function MenuValue(result)
    if type(result) ~= 'table' or result.ok ~= true then
        error(('Weapon menu: %s'):format(type(result) == 'table' and result.message or 'invalid provider response'))
    end

    return result.value
end

local function CloseWeaponMenu(menuId)
    menuSequence = menuSequence + 1
    if menuId then MenuValue(Menu:CloseMenu(menuId)) end
end

local function CreateWeaponMenu(key)
    return MenuValue(Menu:CreateMenu({
        key = key,
        draggable = true,
        closable = true,
        size = { width = '28rem', maxHeight = '85vh' },
        theme = { preset = 'redemption', accent = '#CC9900' }
    })).menuId
end

local function CreateWeaponPage(menuId, key)
    return { menuId = menuId, id = MenuValue(Menu:CreatePage(menuId, { key = key })).pageId, count = 0 }
end

local function AddWeaponElement(page, kind, settings, callback)
    page.count = page.count + 1
    settings.key = ('%s-%d'):format(kind, page.count)

    return MenuValue(Menu:AddElement(page.menuId, page.id, kind, settings, callback))
end

local function OpenWeaponPage(page)
    MenuValue(Menu:OpenMenu(page.menuId, { pageId = page.id }))
end

-- Readiness waits run in a thread; closing or replacing a request cancels stale opens.
local function WithWeaponMenuReady(build)
    menuSequence = menuSequence + 1
    local sequence = menuSequence
    CreateThread(function()
        local success, problem = pcall(function()
            MenuValue(Menu:AwaitReady(5000))
            if sequence ~= menuSequence then return end
            build()
        end)

        if not success then
            print(('[feather-weapons] %s'):format(tostring(problem)))
            Notify('Unable to open the weapon menu. Check feather-menu-v2 readiness.')
        end
    end)
end

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= 'feather-menu-v2' then return end

    menuSequence = menuSequence + 1
    ModificationMenu, RepairMenu, AmmunitionMenu = nil, nil, nil
    AmmunitionActivityPage, ammunitionActivityInFlight = nil, false
    ammunitionActivityReturnPage = nil
    ammunitionActivitySequence = ammunitionActivitySequence + 1
    ModificationPages = {}
end)

local function ResetModificationPages()
    if ModificationMenu then MenuValue(Menu:DestroyMenu(ModificationMenu)) end

    ModificationMenu = CreateWeaponMenu('modifications')
    ModificationPages = {}
end

local function NearGunsmithStation()
    local settings = Config.Attachments or {}
    if settings.requireStation ~= true then return true end

    local position = GetEntityCoords(PlayerPedId(), false, true)
    local distance = tonumber(settings.interactionDistance) or 2.0
    for _, station in pairs(settings.stations or {}) do
        local coords = station.coords
        if coords then
            local dx, dy, dz = position.x - coords.x, position.y - coords.y, position.z - coords.z
            if math.sqrt(dx * dx + dy * dy + dz * dz) <= distance then return true end
        end
    end
    return false
end

local BuildModificationPage

local function BuildModificationMenu()
    if not equipped and not offhand and not extraSlots.shoulder and not extraSlots.back then
        Notify('Equip a weapon before modifying it.')
        return
    end

    if not NearGunsmithStation() then
        Notify('Visit a gunsmith bench to modify this weapon.')
        return
    end

    ResetModificationPages()
    local occupied = 0
    for _, slot in ipairs(WeaponConstants.LoadoutSlots) do
        if SlotState(slot) then
            ModificationPages[slot] = BuildModificationPage(slot)
            occupied = occupied + 1
        end
    end

    if occupied > 1 then
        local selector = CreateWeaponPage(ModificationMenu, 'feather-weapons:select-weapon-slot')
        ModificationPages.selector = selector

        AddWeaponElement(selector, 'header', { value = 'Weapon Modifications', slot = 'header' })

        AddWeaponElement(selector, 'subheader', { value = 'Choose a weapon', slot = 'header' })

        for _, slot in ipairs(WeaponConstants.LoadoutSlots) do
            local selected = SlotState(slot)
            if selected then
                AddWeaponElement(selector, 'button', {
                    label = ('%s: %s'):format(SlotLabel(slot), selected.definitionId or 'Equipped weapon'),
                    slot = 'content'
                }, function()
                    MenuValue(Menu:NavigateToPage(ModificationMenu, ModificationPages[slot].id))
                end)
            end
        end

        OpenWeaponPage(selector)
        return
    end

    for _, slot in ipairs(WeaponConstants.LoadoutSlots) do
        if ModificationPages[slot] then
            OpenWeaponPage(ModificationPages[slot]); return
        end
    end
end

BuildModificationPage = function(slot)
    local selected = SlotState(slot)
    if not selected then return nil end

    local page = CreateWeaponPage(ModificationMenu, ('feather-weapons:installed-attachments:%s'):format(slot))

    AddWeaponElement(page, 'header', { value = 'Weapon Modifications', slot = 'header' })

    AddWeaponElement(page, 'subheader', {
        value = ('%s: %s'):format(SlotLabel(slot), selected.definitionId or 'Equipped weapon'),
        slot = 'header'
    })

    AddWeaponElement(page, 'line', { slot = 'header' })

    local installedIds = {}
    for _, installed in ipairs(selected.attachments or {}) do
        installedIds[installed.definitionId] = true
    end

    local weaponDefinition = WeaponDefinitionCatalog.weapons[selected.definitionId]
    local compatibleIds = {}
    for _, attachmentIds in pairs(weaponDefinition and weaponDefinition.attachmentSlots or {}) do
        for _, attachmentId in ipairs(attachmentIds) do compatibleIds[attachmentId] = true end
    end

    for attachmentId in pairs(compatibleIds) do
        if not installedIds[attachmentId] then
            local definition = WeaponDefinitionCatalog.attachments[attachmentId]
            AddWeaponElement(page, 'button', {
                label = ('Install %s'):format(definition and definition.label or attachmentId:gsub('_', ' ')),
                slot = 'content'
            }, function()
                CloseWeaponMenu(ModificationMenu)
                RequestAttachmentMutation('feather-weapons:attachment:install', {
                    attachmentId = attachmentId,
                    slot = slot,
                    itemInstanceId = selected.itemInstanceId,
                    generation = selected.generation
                })
            end)
        end
    end

    if not selected.attachments or #selected.attachments == 0 then
        AddWeaponElement(page, 'textdisplay', { value = 'No attachments are installed.', slot = 'content' })
    else
        for _, installed in ipairs(selected.attachments) do
            local attachmentId = installed.definitionId
            AddWeaponElement(page, 'button', {
                label = ('Remove %s'):format(attachmentId:gsub('_', ' ')),
                slot = 'content'
            }, function()
                CloseWeaponMenu(ModificationMenu)
                RequestAttachmentMutation('feather-weapons:attachment:remove', {
                    attachmentId = attachmentId,
                    slot = slot,
                    itemInstanceId = selected.itemInstanceId,
                    generation = selected.generation
                })
            end)
        end
    end

    if ModificationPages.selector then
        AddWeaponElement(page, 'button', { label = 'Back to weapons', slot = 'footer' }, function()
            local selector = ModificationPages.selector
            if selector then MenuValue(Menu:NavigateToPage(ModificationMenu, selector.id)) end
        end)
    end

    return page
end

local function HandleRepairResult(result)
    if result and result.ok then
        local slot = result.value.slot or 'primary'
        local state = SlotState(slot)
        if state and SameInstance(state.itemInstanceId, result.value.itemInstanceId) then
            state.condition = tonumber(result.value.condition) or state.condition
            state.maintenance = result.value.maintenance or state.maintenance
            ScheduleMaintenanceRestore()
        end

        Notify(('Weapon repaired by %s%%.'):format(tostring(result.value.restored)))
        if result.value.reconcile then FeatherWeaponsClient.Reconcile() end
        return
    end

    local failure = result and result.error
    Notify(failure and failure.message or 'Unable to repair this weapon.')
end

RegisterNetEvent('feather-weapons:client:inventoryRepairResult', HandleRepairResult)

local function OpenModificationMenu()
    WithWeaponMenuReady(BuildModificationMenu)
end

local OpenAmmunitionMenu

local function StopAmmunitionActivity(returnPage)
    returnPage = returnPage or ammunitionActivityReturnPage
    ammunitionActivityInFlight = false
    ammunitionActivityReturnPage = nil
    ammunitionActivitySequence = ammunitionActivitySequence + 1
    if returnPage and AmmunitionMenu then
        MenuValue(Menu:NavigateToPage(AmmunitionMenu, returnPage.id))
    end
end

local function StartAmmunitionActivity(returnPage, operation)
    if ammunitionActivityInFlight or not AmmunitionActivityPage then return false end

    ammunitionActivityInFlight = true
    ammunitionActivityReturnPage = returnPage
    ammunitionActivitySequence = ammunitionActivitySequence + 1
    local sequence = ammunitionActivitySequence
    MenuValue(Menu:SetElementValue(AmmunitionMenu, AmmunitionActivityPage.id,
        AmmunitionActivityPage.statusElementId, operation .. '...'))
    MenuValue(Menu:NavigateToPage(AmmunitionMenu, AmmunitionActivityPage.id))
    CreateThread(function()
        local step = 0
        while ammunitionActivityInFlight and sequence == ammunitionActivitySequence do
            Wait(350)
            if not ammunitionActivityInFlight or sequence ~= ammunitionActivitySequence then return end

            step = (step % 3) + 1
            local result = Menu:SetElementValue(AmmunitionMenu, AmmunitionActivityPage.id,
                AmmunitionActivityPage.statusElementId, operation .. string.rep('.', step))
            if type(result) ~= 'table' or result.ok ~= true then
                StopAmmunitionActivity(returnPage)
                return
            end
        end
    end)
    return true
end

local function AmmunitionVariantLabel(definition, ammunitionId)
    local label = definition and definition.label or ammunitionId or 'Unknown'

    return label:match('%s%-%s(.+)$') or label
end

local function RequestManagedAmmunition(route, request, action)
    FeatherWeaponsClient.Checkpoint(function(checkpoint)
        if not checkpoint or not checkpoint.ok then
            local failure = checkpoint and checkpoint.error or nil
            Notify(failure and failure.message or 'Unable to save the weapon before changing ammunition.')
            StopAmmunitionActivity(action and action.returnPage)
            return
        end

        FeatherCore.RPC.Call(route, request, function(result, rpcError)
            result = result or { ok = false, error = rpcError }
            if not result.ok then
                local failure = result.error or rpcError
                Notify(failure and failure.message or 'Unable to change weapon ammunition.')
                StopAmmunitionActivity(action and action.returnPage)
                return
            end

            local moved = tonumber(result.value and result.value.moved) or 0
            local weaponLabel = action and action.weaponLabel or SlotLabel(request.slot)
            local ammunitionLabel = action and action.ammunitionLabel or 'cartridges'
            if action and action.kind == 'unload' then
                Notify(('Unloaded %d %s cartridge%s from %s.'):format(
                    moved, ammunitionLabel, moved == 1 and '' or 's', weaponLabel))
            elseif action and action.kind == 'switch' then
                Notify(('Switched %s to %s; loaded %d cartridge%s.'):format(
                    weaponLabel, ammunitionLabel, moved, moved == 1 and '' or 's'))
            else
                Notify(('Loaded %d %s cartridge%s into %s.'):format(
                    moved, ammunitionLabel, moved == 1 and '' or 's', weaponLabel))
            end

            ClearNativeWeapon()
            FeatherWeaponsClient.Reconcile(function(reconciled)
                if reconciled and reconciled.ok then
                    OpenAmmunitionMenu(request.slot)
                else
                    StopAmmunitionActivity(action and action.returnPage)
                end
            end)
        end)
    end)
end

local function LoadedContainerLabel(weapon)
    if weapon.family == 'revolver' then return 'Cylinder' end

    if weapon.family == 'shotgun' then return 'Chamber/tube' end

    return 'Magazine'
end

local function AmmunitionCapacityRemaining(slot, selected, ammunitionId, definition)
    local maximum = math.max(tonumber(selected.capacity) or 1,
        math.floor(tonumber(Config.Escrow and Config.Escrow.maxTotal)
            or tonumber(selected.capacity) or 1))
    local definitionMaximum = definition and tonumber(definition.maxTotal) or nil
    if definitionMaximum then
        maximum = math.min(maximum, math.floor(definitionMaximum))
    end

    local occupied = selected.ammunitionType == ammunitionId and (tonumber(selected.ammo) or 0) or 0
    for _, candidate in ipairs(WeaponConstants.LoadoutSlots) do
        local other = candidate ~= slot and SlotState(candidate) or nil
        if other and definition and other.nativeAmmoName == definition.nativeAmmoName then
            occupied = occupied + (tonumber(other.ammo) or 0)
        end
    end

    return math.max(0, maximum - occupied)
end

local function BuildAmmunitionPage(slot)
    local selected = SlotState(slot)
    if not selected then return nil end

    local page = CreateWeaponPage(AmmunitionMenu, ('feather-weapons:ammunition:%s'):format(slot))
    local weapon = WeaponDefinitionCatalog.weapons[selected.definitionId] or {}
    local current = WeaponDefinitionCatalog.ammunition[selected.ammunitionType] or {}

    AddWeaponElement(page, 'header', { value = 'Ammunition Management', slot = 'header' })

    AddWeaponElement(page, 'subheader', {
        value = ('%s: %s'):format(SlotLabel(slot), weapon.label or selected.definitionId),
        slot = 'header'
    })

    AddWeaponElement(page, 'textdisplay', {
        value = ('Loaded type: %s'):format(current.label or selected.ammunitionType or 'Unknown'),
        slot = 'content'
    })

    AddWeaponElement(page, 'textdisplay', {
        value = ('%s: %d  |  Reserve: %d  |  Total: %d'):format(
            LoadedContainerLabel(weapon),
            tonumber(selected.loaded) or 0,
            tonumber(selected.reserve) or 0,
            tonumber(selected.ammo) or 0),
        slot = 'content'
    })

    AddWeaponElement(page, 'line', { slot = 'content' })

    if (tonumber(selected.ammo) or 0) > 0 then
        local unloadAmount = math.min(10, tonumber(selected.ammo) or 0)
        AddWeaponElement(page, 'button', {
            label = ('Unload %d cartridge%s'):format(
                unloadAmount, unloadAmount == 1 and '' or 's'),
            slot = 'content'
        }, function()
            if not StartAmmunitionActivity(page, 'Unloading ammunition') then return end
            RequestManagedAmmunition('feather-weapons:ammo:unload', {
                slot = slot,
                amount = unloadAmount,
                itemInstanceId = selected.itemInstanceId,
                generation = selected.generation
            }, {
                kind = 'unload',
                weaponLabel = weapon.label or selected.definitionId,
                ammunitionLabel = AmmunitionVariantLabel(current, selected.ammunitionType),
                returnPage = page
            })
        end)

        AddWeaponElement(page, 'button', {
            label = 'Unload all cartridges', slot = 'content'
        }, function()
            if not StartAmmunitionActivity(page, 'Unloading ammunition') then return end
            RequestManagedAmmunition('feather-weapons:ammo:unload', {
                slot = slot,
                itemInstanceId = selected.itemInstanceId,
                generation = selected.generation
            }, {
                kind = 'unload',
                weaponLabel = weapon.label or selected.definitionId,
                ammunitionLabel = AmmunitionVariantLabel(current, selected.ammunitionType),
                returnPage = page
            })
        end)
    end

    local availableChoices = 0
    for _, id in ipairs(weapon.ammunitionTypes or {}) do
        local ammunitionId = id
        local definition = WeaponDefinitionCatalog.ammunition[ammunitionId]
        local available = math.max(0, math.floor(tonumber(ammunitionInventory[ammunitionId]) or 0))
        if definition and available > 0 then
            local loadLimit = tonumber(Config.Escrow and Config.Escrow.refillAmount) or 50
            local remaining = AmmunitionCapacityRemaining(slot, selected, ammunitionId, definition)
            local loadAmount = math.min(loadLimit, available, remaining)
            if loadAmount > 0 then
                local switching = (tonumber(selected.ammo) or 0) > 0 and selected.ammunitionType ~= ammunitionId
                availableChoices = availableChoices + 1
                AddWeaponElement(page, 'button', {
                    label = switching
                        and ('Switch to %s (owned: %d; load: %d)'):format(definition.label or ammunitionId, available, loadAmount)
                        or ('Load up to %d: %s (owned: %d)'):format(loadAmount, definition.label or ammunitionId, available),
                    slot = 'content'
                }, function()
                    if not StartAmmunitionActivity(page,
                            switching and 'Switching ammunition' or 'Loading ammunition') then
                        return
                    end

                    RequestManagedAmmunition(switching
                        and 'feather-weapons:ammo:switchSlot'
                        or 'feather-weapons:ammo:loadSlot', {
                            slot = slot,
                            amount = loadAmount,
                            ammunitionType = ammunitionId,
                            itemInstanceId = selected.itemInstanceId,
                            generation = selected.generation
                        }, {
                            kind = switching and 'switch' or 'load',
                            weaponLabel = weapon.label or selected.definitionId,
                            ammunitionLabel = AmmunitionVariantLabel(definition, ammunitionId),
                            returnPage = page
                        })
                end)
            end
        end
    end

    if availableChoices == 0 then
        AddWeaponElement(page, 'textdisplay', {
            value = 'No compatible ammunition can currently be loaded from Inventory.',
            slot = 'content'
        })
    end

    return page
end

local function BuildAmmunitionMenu(initialSlot)
    local occupied = {}
    for _, slot in ipairs(WeaponConstants.LoadoutSlots) do
        if SlotState(slot) then occupied[#occupied + 1] = slot end
    end

    if #occupied == 0 then
        Notify('Equip a weapon before managing ammunition.')
        return
    end

    ammunitionActivityInFlight = false
    ammunitionActivityReturnPage = nil
    ammunitionActivitySequence = ammunitionActivitySequence + 1
    if AmmunitionMenu then MenuValue(Menu:DestroyMenu(AmmunitionMenu)) end

    AmmunitionMenu = CreateWeaponMenu('ammunition-management')
    AmmunitionActivityPage = CreateWeaponPage(AmmunitionMenu, 'feather-weapons:ammunition-activity')
    AddWeaponElement(AmmunitionActivityPage, 'header', {
        value = 'Ammunition Management', slot = 'header'
    })

    AddWeaponElement(AmmunitionActivityPage, 'subheader', {
        value = 'Updating weapon', slot = 'header'
    })

    AmmunitionActivityPage.statusElementId = AddWeaponElement(
        AmmunitionActivityPage, 'textdisplay', {
            value = 'Working...', slot = 'content'
        }).elementId
    AddWeaponElement(AmmunitionActivityPage, 'textdisplay', {
        value = 'Please wait. Inventory and weapon state are being synchronized.',
        slot = 'content'
    })

    local pages = {}
    for _, slot in ipairs(occupied) do pages[slot] = BuildAmmunitionPage(slot) end

    if #occupied == 1 then
        local onlyPage = pages[occupied[1]]
        if onlyPage then OpenWeaponPage(onlyPage) end
        return
    end

    local selector = CreateWeaponPage(AmmunitionMenu, 'feather-weapons:ammunition-select-slot')
    AddWeaponElement(selector, 'header', { value = 'Ammunition Management', slot = 'header' })
    AddWeaponElement(selector, 'subheader', { value = 'Choose a weapon', slot = 'header' })
    for _, slot in ipairs(occupied) do
        local selectedSlot = slot
        local selected = SlotState(selectedSlot)
        local targetPage = pages[selectedSlot]
        if selected and targetPage then
            local weapon = WeaponDefinitionCatalog.weapons[selected.definitionId] or {}
            AddWeaponElement(selector, 'button', {
                label = ('%s: %s (%d/%d)'):format(SlotLabel(selectedSlot),
                    weapon.label or selected.definitionId,
                    tonumber(selected.loaded) or 0, tonumber(selected.ammo) or 0),
                slot = 'content'
            }, function()
                MenuValue(Menu:NavigateToPage(AmmunitionMenu, targetPage.id))
            end)
        end
    end

    for _, slot in ipairs(occupied) do
        local page = pages[slot]
        if page then
            AddWeaponElement(page, 'button', { label = 'Back to weapons', slot = 'footer' }, function()
                MenuValue(Menu:NavigateToPage(AmmunitionMenu, selector.id))
            end)
        end
    end

    local initialPage = initialSlot and pages[initialSlot] or nil
    OpenWeaponPage(initialPage or selector)
end

OpenAmmunitionMenu = function(initialSlot)
    FeatherWeaponsClient.Checkpoint(function(result)
        if not result or not result.ok then
            local failure = result and result.error or nil
            Notify(failure and failure.message
                or 'Unable to save weapon ammunition before opening the menu.')
            StopAmmunitionActivity()
            return
        end

        FeatherCore.RPC.Call('feather-weapons:ammo:availability', {}, function(availability, rpcError)
            if not availability or not availability.ok then
                local failure = availability and availability.error or rpcError
                Notify(failure and failure.message or 'Unable to read Inventory ammunition.')
                StopAmmunitionActivity()
                return
            end

            ammunitionInventory = availability.value.quantities or {}
            WithWeaponMenuReady(function() BuildAmmunitionMenu(initialSlot) end)
        end)
    end)
end

local function BuildRepairMenu(selectionSlots)
    local choices = {}
    if type(selectionSlots) == 'table' and #selectionSlots > 0 then
        choices = selectionSlots
    else
        for _, slot in ipairs(WeaponConstants.LoadoutSlots) do
            local state = SlotState(slot)
            if state then
                choices[#choices + 1] = {
                    key = 'slot:' .. slot,
                    location = slot,
                    definitionId = state.definitionId,
                    condition = state.condition
                }
            end
        end
    end

    if #choices < 1 then
        Notify('The equipped weapons changed before repair selection.')
        return
    end

    if RepairMenu then MenuValue(Menu:DestroyMenu(RepairMenu)) end

    RepairMenu = CreateWeaponMenu('repair-selection')
    local RepairPage = CreateWeaponPage(RepairMenu, 'repair-slot')
    AddWeaponElement(RepairPage, 'header', { value = 'Repair Weapon', slot = 'header' })
    AddWeaponElement(RepairPage, 'subheader', { value = 'Choose a weapon', slot = 'header' })

    for _, choice in ipairs(choices) do
        local selected = choice
        local location = ({ primary = true, offhand = true, shoulder = true, back = true })[choice.location]
            and SlotLabel(choice.location) or tostring(choice.location or 'Inventory')
        AddWeaponElement(RepairPage, 'button', { label = ('%s: %s (%s%%)'):format(location,
                choice.definitionId or 'Weapon', tostring(choice.condition or 0)),
            slot = 'content'
        }, function()
            CloseWeaponMenu(RepairMenu)
            FeatherCore.RPC.Call('feather-weapons:repair:select', { key = selected.key }, function(result, rpcError)
                HandleRepairResult(result or { ok = false, error = rpcError })
            end)
        end)
    end

    OpenWeaponPage(RepairPage)
end

RegisterNetEvent('feather-weapons:client:repairSlotRequested', function(selectionSlots)
    WithWeaponMenuReady(function() BuildRepairMenu(selectionSlots) end)
end)

RegisterNetEvent('feather-weapons:client:clearAuthorization', function(token)
    if pendingToken == token then
        ClearNativeWeapon()
    end
end)

RegisterNetEvent('feather-weapons:client:inventoryAmmoResult', function(result)
    if result and result.reconcile then
        ClearNativeWeapon()
        FeatherWeaponsClient.Reconcile()
        Notify(result.ok and ('Escrowed %s cartridges.'):format(tostring(result.value.moved))
            or (result.error and result.error.message or 'Unable to escrow ammunition.'))
        return
    end

    if result and result.ok and (equipped or offhand or extraSlots.shoulder or extraSlots.back) then
        local slot = result.value.slot or 'primary'
        local state = SlotState(slot)
        if not state then
            Notify('The selected weapon slot is no longer equipped.')
            return
        end

        state.ammo = tonumber(result.value.total) or state.ammo
        state.loaded = tonumber(result.value.loaded) or state.loaded
        state.reserve = tonumber(result.value.reserve) or (state.ammo - state.loaded)
        if slot == 'primary' or slot == 'offhand' then
            local primary = equipped
            local secondary = offhand
            if not primary then
                Notify('Primary weapon state changed while updating ammunition.')
                FeatherWeaponsClient.Reconcile()
                return
            end

            if secondary then
                if pairSingleFallback and primary.loaded > 0 and secondary.loaded > 0 then
                    local restored, message = RestoreApprovedNativePair(primary, secondary)
                    if not restored then
                        Notify(message or 'Unable to restore the reloaded weapon pair.')
                        FeatherWeaponsClient.Reconcile()
                        return
                    end

                    pairSingleFallback, pairFallbackPending = nil, nil
                    local primaryOk, primaryLoaded, offhandOk, offhandLoaded = PairNativeClips(primary, secondary)
                    pairObserved = {
                        primary = primaryOk and math.max(0, math.floor(tonumber(primaryLoaded) or 0)) or 0,
                        offhand = offhandOk and math.max(0, math.floor(tonumber(offhandLoaded) or 0)) or 0,
                        total = PairNativeTotal(primary, secondary)
                    }
                    FeatherNativeWeaponCoordinator.TrackAmmoWindows(PlayerPedId(), {
                        primary = primary,
                        offhand = secondary
                    })
                    if Config.DevMode then
                        print(('[feather-weapons] funded pair restored slot=%s loaded=%d/%d')
                            :format(slot, pairObserved.primary, pairObserved.offhand))
                    end
                end

                local pairTotal = primary.ammo + secondary.ammo
                if primary.nativeAmmoName == secondary.nativeAmmoName then
                    SetPedAmmoByType(PlayerPedId(), joaat(primary.nativeAmmoName), pairTotal)
                else
                    SetPedAmmoByType(PlayerPedId(), joaat(state.nativeAmmoName), state.ammo)
                end

                pairObserved = pairObserved or {}
                pairObserved.total = PairNativeTotal(primary, secondary)
                FeatherNativeWeaponCoordinator.TrackAmmoWindows(PlayerPedId(), {
                    primary = primary,
                    offhand = secondary
                })
            else
                desiredAmmo, desiredLoaded = primary.ammo, primary.loaded
                SetNativeAmmo(result.value.nativeAmmoName or primary.nativeAmmoName,
                    primary.ammo, primary.nativeWeaponName, primary.loaded)
            end
        else
            extraObserved[slot] = { loaded = state.loaded, consumed = 0 }
            SetNativeAmmo(state.nativeAmmoName, state.ammo,
                state.nativeWeaponName, state.loaded)
        end

        Notify(('Escrowed %s cartridge%s.'):format(
            tostring(result.value.moved), result.value.moved == 1 and '' or 's'))
        return
    end

    local failure = result and result.error
    Notify(failure and failure.message or 'Unable to escrow ammunition.')
end)

RegisterNetEvent('feather-weapons:client:clear', ClearNativeWeapon)

RegisterNetEvent('feather-weapons:client:reconcile', function()
    FeatherWeaponsClient.Reconcile()
end)

RegisterNetEvent('feather-weapons:client:forceReconcile', function()
    ClearNativeWeapon()
    FeatherWeaponsClient.Reconcile()
end)

if Config.Controls and Config.Controls.unload and Config.Controls.unload.enabled then
    local unloadControl = Config.Controls.unload
    RegisterCommand(unloadControl.command, BeginUnload, false)
    RegisterKeyMapping(unloadControl.command, 'Unload equipped weapon', 'keyboard', unloadControl.defaultKey or 'U')
end

if Config.Controls and Config.Controls.modify and Config.Controls.modify.enabled then
    local modifyControl = Config.Controls.modify
    RegisterCommand(modifyControl.command, OpenModificationMenu, false)
    RegisterKeyMapping(modifyControl.command, 'Modify equipped weapon', 'keyboard', modifyControl.defaultKey or 'F6')
end

if Config.Controls and Config.Controls.ammunition and Config.Controls.ammunition.enabled then
    local ammunitionControl = Config.Controls.ammunition
    RegisterCommand(ammunitionControl.command, function() OpenAmmunitionMenu() end, false)
    RegisterKeyMapping(ammunitionControl.command, 'Manage equipped weapon ammunition', 'keyboard', ammunitionControl.defaultKey or 'F7')
end

CreateThread(function()
    local interval = math.max(1000, math.floor(tonumber(Config.Runtime and Config.Runtime.maintenanceCheckpointMs) or 5000))
    while true do
        Wait(interval)
        CheckpointMaintenance(function() end)
    end
end)

CreateThread(function()
    local runtimeConfig = Config.Runtime or {}
    local observationInterval = math.max(25, math.floor(tonumber(runtimeConfig.observationIntervalMs) or 50))
    local checkpointDebounce = math.max(0, math.floor(tonumber(runtimeConfig.checkpointDebounceMs) or 250))
    local wasDead = false
    local fireWindowUntil = 0

    while true do
        if equipped and not offhand and desiredAmmo ~= nil and singleNativeReady
            and not presentationRestoreInFlight then
            local ped = PlayerPedId()
            if NativeTrue(IsPedShooting(ped)) then fireWindowUntil = GetGameTimer() + 250 end

            local itemInstanceId = equipped.itemInstanceId
            local generation = equipped.generation
            local ammoHash = equipped.nativeAmmoName and joaat(equipped.nativeAmmoName) or nil
            if ammoHash then
                local clipOk, clipAmount = GetAmmoInClip(ped, joaat(equipped.nativeWeaponName))
                local clipChanged = false
                local previousLoaded = desiredLoaded
                local observedLoaded = previousLoaded or 0
                if clipOk == true or clipOk == 1 then
                    observedLoaded = math.max(0, math.floor(tonumber(clipAmount) or 0))
                    clipChanged = desiredLoaded ~= nil and observedLoaded ~= desiredLoaded
                    desiredLoaded = observedLoaded
                end

                local observed = math.max(0,
                    math.floor(tonumber(GetPedAmmoByType(ped, ammoHash)) or 0))
                local firing = GetGameTimer() <= fireWindowUntil
                local clipConsumed = firing and previousLoaded ~= nil
                    and math.max(0, previousLoaded - observedLoaded) or 0
                -- A lower native total is an authoritative consumption signal
                -- even if IsPedShooting was missed or the wheel auto-reloaded
                -- before this observer sampled the clip. This also recovers a
                -- pending shot after a read-only reconcile refreshed local
                -- state from the slightly older server snapshot.
                if observed < desiredAmmo or (firing and clipConsumed > 0) then
                    desiredAmmo = math.max(0, math.min(observed,
                        desiredAmmo - clipConsumed))
                    SetTimeout(checkpointDebounce, function()
                        if equipped and SameInstance(equipped.itemInstanceId, itemInstanceId)
                            and equipped.generation == generation then
                            FlushConsumption()
                        end
                    end)
                elseif clipChanged then
                    SetTimeout(checkpointDebounce, function()
                        if equipped and SameInstance(equipped.itemInstanceId, itemInstanceId)
                            and equipped.generation == generation then
                            FlushConsumption()
                        end
                    end)
                elseif observed > equipped.ammo and not observerCorrectionPending then
                    observerCorrectionPending = true
                    if Config.DevMode then
                        print(('[feather-weapons] native ammo exceeded lease observed=%d approved=%d generation=%s')
                            :format(observed, equipped.ammo, tostring(generation)))
                    end
                    FeatherWeaponsClient.Reconcile()
                elseif observed <= equipped.ammo then
                    observerCorrectionPending = false
                end
            end

            local deadState = IsEntityDead(PlayerPedId())
            local dead = deadState == true or deadState == 1
            if dead and not wasDead then
                -- Death is a persistence boundary. Capture and submit immediately;
                -- ordinary firing/reload observations remain debounced.
                CaptureNativeState()
                FlushConsumption()
            end

            wasDead = dead
            Wait(observationInterval)
        else
            wasDead = false
            Wait(500)
        end
    end
end)

CreateThread(function()
    local runtimeConfig = Config.Runtime or {}
    local observationInterval = math.max(25, math.floor(tonumber(runtimeConfig.observationIntervalMs) or 50))
    local checkpointDebounce = math.max(0, math.floor(tonumber(runtimeConfig.checkpointDebounceMs) or 250))

    while true do
        if equipped and offhand and pairObserved and not presentationRestoreInFlight then
            local ped = PlayerPedId()
            if IsDualSidearmPair(equipped, offhand) and not pairSingleFallback
                and not NativeTrue(GetAllowDualWield(ped)) then
                RecoverLostOffhandEntitlement()
                Wait(500)
            else
                local primaryOk, primaryLoaded, offhandOk, offhandLoaded =
                    ObservablePairClips(equipped, offhand)
                if primaryOk and offhandOk then
                    primaryLoaded = math.max(0, math.floor(tonumber(primaryLoaded) or 0))
                    offhandLoaded = math.max(0, math.floor(tonumber(offhandLoaded) or 0))
                    local total = PairNativeTotal(equipped, offhand)
                    if pairSingleFallback then
                        if primaryLoaded > 0 and offhandLoaded > 0 then
                            pairSingleFallback = nil
                            pairFallbackPending = nil
                            EnsureOffhandEntitlement()
                            if Config.DevMode then
                                print('[feather-weapons] pair reloaded; dual-wield restored')
                            end
                        end
                    elseif primaryLoaded == 0 and offhandLoaded > 0 then
                        local newlyConsumed = math.max(0, pairObserved.primary - primaryLoaded)
                        local remaining = (tonumber(equipped.ammo) or 0)
                            - pairConsumed.primary - newlyConsumed
                        pairFallbackPending = remaining <= 0 and 'offhand' or nil
                    elseif offhandLoaded == 0 and primaryLoaded > 0 then
                        local newlyConsumed = math.max(0, pairObserved.offhand - offhandLoaded)
                        local remaining = (tonumber(offhand.ammo) or 0)
                            - pairConsumed.offhand - newlyConsumed
                        pairFallbackPending = remaining <= 0 and 'primary' or nil
                    else
                        pairFallbackPending = nil
                    end

                    if primaryLoaded < pairObserved.primary then
                        pairConsumed.primary = pairConsumed.primary + (pairObserved.primary - primaryLoaded)
                    end

                    if offhandLoaded < pairObserved.offhand then
                        pairConsumed.offhand = pairConsumed.offhand + (pairObserved.offhand - offhandLoaded)
                    end

                    local changed = primaryLoaded ~= pairObserved.primary
                        or offhandLoaded ~= pairObserved.offhand or total ~= pairObserved.total
                    pairObserved.primary, pairObserved.offhand, pairObserved.total = primaryLoaded, offhandLoaded, total
                    if changed and not pairCheckpointPending then
                        pairCheckpointPending = true
                        SetTimeout(checkpointDebounce, function()
                            pairCheckpointPending = false
                            if equipped and offhand then
                                FlushPairConsumption()
                            end
                        end)
                    elseif not changed and pairFallbackPending and not pairSingleFallback then
                        -- On restore, an empty clip is already authoritative and
                        -- needs no checkpoint before entering single-weapon mode.
                        local fallbackSlot = pairFallbackPending
                        local survivor = fallbackSlot == 'primary' and equipped or offhand
                        pairFallbackPending = nil
                        ActivateLoadedPairSlot(ped, fallbackSlot, survivor)
                    end
                end
                Wait(observationInterval)
            end
        else
            Wait(500)
        end
    end
end)

CreateThread(function()
    local runtimeConfig = Config.Runtime or {}
    local observationInterval = math.max(25, math.floor(tonumber(runtimeConfig.observationIntervalMs) or 50))
    local checkpointDebounce = math.max(0, math.floor(tonumber(runtimeConfig.checkpointDebounceMs) or 250))
    local fireWindowUntil = 0
    while true do
        local active = false
        local ped = PlayerPedId()
        if NativeTrue(IsPedShooting(ped)) then fireWindowUntil = GetGameTimer() + 250 end

        local selectedOk, selectedWeapon = GetCurrentPedWeapon(ped, true, 0, false)
        for _, slot in ipairs({ 'shoulder', 'back' }) do
            local state = extraSlots[slot]
            local observed = extraObserved[slot]
            if state and observed then
                active = true
                local weaponHash = joaat(state.nativeWeaponName)
                local clipOk, clipAmount = GetAmmoInClip(ped, weaponHash)
                if NativeTrue(clipOk) then
                    local loaded = math.max(0, math.floor(tonumber(clipAmount) or 0))
                    if loaded < observed.loaded and GetGameTimer() <= fireWindowUntil
                        and NativeTrue(selectedOk)
                        and selectedWeapon == weaponHash then
                        observed.consumed = observed.consumed + (observed.loaded - loaded)
                    end

                    local changed = loaded ~= observed.loaded
                    observed.loaded = loaded
                    if changed then
                        local itemInstanceId, generation = state.itemInstanceId, state.generation
                        SetTimeout(checkpointDebounce, function()
                            local current = extraSlots[slot]
                            if current and SameInstance(current.itemInstanceId, itemInstanceId)
                                and current.generation == generation then
                                FlushExtraSlot(slot)
                            end
                        end)
                    end
                end
            end
        end
        Wait(active and observationInterval or 500)
    end
end)

-- RedM cannot keep a reserve visible for two different long-gun hashes that
-- share an ammunition type. Expose only the selected weapon's reload amount,
-- then return the native pool to the combined clips when the animation ends.
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local selectedOk, selectedWeapon = GetCurrentPedWeapon(ped, true, 0, false)
        local selectedSlot, selectedState
        if NativeTrue(selectedOk) then
            for _, slot in ipairs({ 'shoulder', 'back' }) do
                local state = extraSlots[slot]
                local other = extraSlots[slot == 'shoulder' and 'back' or 'shoulder']
                if state and other and type(state.nativeAmmoName) == 'string'
                    and type(state.nativeWeaponName) == 'string'
                    and state.nativeAmmoName == other.nativeAmmoName
                    and joaat(state.nativeWeaponName) == selectedWeapon then
                    selectedSlot, selectedState = slot, state
                    break
                end
            end
        end

        if selectedState and selectedSlot then
            DisableControlAction(0, joaat('INPUT_RELOAD'), true)
            if IsDisabledControlJustPressed(0, joaat('INPUT_RELOAD'))
                and not longgunReloadInFlight then
                local nativeAmmoName = selectedState.nativeAmmoName
                local loadedTotal = 0
                local selectedLoaded = math.max(0,
                    math.floor(tonumber(selectedState.loaded) or 0))
                local authorized = 0
                local intendedClips = {}
                for _, slot in ipairs({ 'shoulder', 'back' }) do
                    local state = extraSlots[slot]
                    if state and state.nativeAmmoName == nativeAmmoName then
                        local clipOk, loaded = GetAmmoInClip(ped, joaat(state.nativeWeaponName))
                        loaded = NativeTrue(clipOk) and math.max(0, math.floor(tonumber(loaded) or 0)) or state.loaded
                        local observed = extraObserved[slot]
                        intendedClips[slot] = math.max(0, math.floor(tonumber(observed and observed.loaded) or state.loaded or loaded))
                        loadedTotal = loadedTotal + intendedClips[slot]
                        authorized = authorized + math.max(0,
                            math.floor(tonumber(state.ammo) or 0)
                                - math.floor(tonumber(observed and observed.consumed) or 0))
                        if slot == selectedSlot then selectedLoaded = loaded end
                    end
                end

                local capacity = math.max(selectedLoaded, math.floor(tonumber(selectedState.capacity) or 0))
                local amount = math.min(math.max(0, capacity - selectedLoaded), math.max(0, authorized - loadedTotal))
                if amount > 0 then
                    intendedClips[selectedSlot] = selectedLoaded + amount
                    longgunReloadInFlight = true
                    if Config.DevMode then
                        print(('[feather-weapons] shared long-gun reload requested slot=%s loaded=%d amount=%d authorized=%d clips=%d')
                            :format(selectedSlot, selectedLoaded, amount, authorized, loadedTotal))
                    end
                    Citizen.InvokeNative(0x106A811C6D3035F3, ped, joaat(nativeAmmoName), amount, joaat('ADD_REASON_DEFAULT')) -- AddAmmoToPedByType
                    MakePedReload(ped)
                    CreateThread(function()
                        local deadline = GetGameTimer() + 2000
                        repeat
                            Wait(25)
                        until NativeTrue(IsPedReloading(ped))
                            or GetGameTimer() >= deadline
                        if not NativeTrue(IsPedReloading(ped)) then
                            TaskReloadWeapon(ped, false)
                            deadline = GetGameTimer() + 3000
                            repeat
                                Wait(25)
                            until NativeTrue(IsPedReloading(ped))
                                or GetGameTimer() >= deadline
                        end

                        local started = NativeTrue(IsPedReloading(ped))
                        if NativeTrue(IsPedReloading(ped)) then
                            deadline = GetGameTimer() + 5000
                            repeat
                                Wait(25)
                            until not NativeTrue(IsPedReloading(ped))
                                or GetGameTimer() >= deadline
                        end

                        local clipTotal = 0
                        for _, slot in ipairs({ 'shoulder', 'back' }) do
                            local state = extraSlots[slot]
                            if state and state.nativeAmmoName == nativeAmmoName then
                                local loaded = math.max(0, math.floor(tonumber(intendedClips[slot]) or state.loaded or 0))
                                SetAmmoInClip(ped, joaat(state.nativeWeaponName), loaded)
                                extraObserved[slot] = { loaded = loaded, consumed = 0 }
                                clipTotal = clipTotal + loaded
                            end
                        end

                        SetPedAmmoByType(ped, joaat(nativeAmmoName), clipTotal)
                        longgunReloadInFlight = false
                        FlushExtraSlot(selectedSlot)
                        if Config.DevMode then
                            print(('[feather-weapons] shared long-gun reload %s slot=%s nativeClips=%d')
                                :format(started and 'complete' or 'failed', selectedSlot, clipTotal))
                        end
                    end)
                end
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

CreateThread(function()
    while true do
        if equipped and equipped.attachments and #equipped.attachments > 0 and GetGameTimer() < attachmentReconcileUntil then
            ApplyNativeAttachments(equipped.nativeWeaponName, equipped.attachments)
            Wait(500)
        else
            Wait(1000)
        end
    end
end)

AddEventHandler('Feather:Character:Spawned', function()
    RegisterCharacterLogoutCheckpoint()
end)

local function RestoreRuntimeWeapons()
    CreateThread(function()
        -- Native inventory preparation may discard weapon instances. Block
        -- observation and invalidate any earlier restore before invoking it.
        singleRestoreSequence = singleRestoreSequence + 1
        singleNativeReady = false
        local prepared = FeatherNativeWeaponCoordinator.PrepareCharacterRestore(
            PlayerPedId(), 5000)
        if not prepared.ok then
            Notify(prepared.message or 'The native carried-weapon inventory did not become ready.')
            if Config.DevMode then
                print(('[feather-weapons] restore deferred code=%s message=%s'):format(tostring(prepared.code), tostring(prepared.message)))
            end
            return
        end

        if Config.DevMode then
            print('[feather-weapons] native character weapon inventory prepared')
        end
        -- Reconciliation must recreate every approved instance after native
        -- preparation; stale local state must never suppress that grant.
        ClearNativeWeapon()
        FeatherWeaponsClient.Reconcile(nil, { holster = true })
    end)
end

AddEventHandler('feather-character:client:runtime-ready.v1', function()
    RestoreRuntimeWeapons()
end)

RegisterNetEvent('feather-weapons:client:runtime-ready', RestoreRuntimeWeapons)

AddEventHandler('Feather:Character:Logout', function()
    inventoryWeaponInFlight = false
    ClearNativeWeapon()
end)

RegisterCharacterLogoutCheckpoint = function()
    if GetResourceState('feather-character') ~= 'started' then return end

    local called, result = pcall(function()
        return exports['feather-character']:RegisterLogoutCheckpoint('feather-weapons:runtime', 'CheckpointBeforeLogout')
    end)

    if Config.DevMode then
        local passed = called and result and result.ok == true
        local failure = type(result) == 'table' and (result.error or result) or nil
        print(('[feather-weapons] character logout checkpoint registration %s code=%s message=%s'):format(
            passed and 'PASS' or 'FAIL',
            tostring(passed and 'none' or (failure and failure.code) or 'export_error'),
            tostring(passed and 'none' or (failure and failure.message) or result)))
    end
end

exports('CheckpointBeforeLogout', function()
    local deadline = GetGameTimer() + 2000
    while (longgunReloadInFlight or syncInFlight or pairSyncInFlight
            or extraSyncInFlight.shoulder or extraSyncInFlight.back
            or maintenanceSyncInFlight.primary or maintenanceSyncInFlight.offhand
            or maintenanceSyncInFlight.shoulder or maintenanceSyncInFlight.back)
        and GetGameTimer() < deadline do
        Wait(25)
    end

    local maintenancePending = promise.new()
    CheckpointMaintenance(function(result)
        maintenancePending:resolve(result)
    end)

    local maintenance = Citizen.Await(maintenancePending)
    if not maintenance or maintenance.ok ~= true then return maintenance end

    local pending = promise.new()
    FeatherWeaponsClient.Checkpoint(function(checkpoint)
        pending:resolve(checkpoint)
    end)

    local checkpoint = Citizen.Await(pending)
    if Config.DevMode then
        print(('[feather-weapons] logout checkpoint %s total=%s loaded=%s'):format(
            checkpoint and checkpoint.ok and 'PASS' or 'FAIL',
            tostring(checkpoint and checkpoint.value and checkpoint.value.total),
            tostring(checkpoint and checkpoint.value and checkpoint.value.loaded)))
    end
    return checkpoint
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        RegisterCharacterLogoutCheckpoint()
        TriggerServerEvent('feather-weapons:server:client-ready')
    elseif resourceName == 'feather-character' then
        RegisterCharacterLogoutCheckpoint()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        ClearNativeWeapon()
    end
end)

if Config.DevMode then
    print(('[feather-weapons] client contract=%d dualSlots=true primaryPromotion=true'):format(clientContract))

    RegisterCommand('weaponmaintenance', function()
        local ped = PlayerPedId()
        for _, slot in ipairs({ 'primary', 'offhand', 'shoulder', 'back' }) do
            local state = SlotState(slot)
            if state then
                local saved = state.maintenance or {}
                local native = FeatherNativeMaintenance.Read(ped, slot, state)
                print(('[feather-weapons] maintenance slot=%s item=%s condition=%s saved=%.3f/%.3f/%.3f/%.3f/%.3f native=%s')
                    :format(slot, tostring(state.itemInstanceId), tostring(state.condition),
                        tonumber(saved.degradation) or 0.0,
                        tonumber(saved.permanentDegradation) or 0.0,
                        tonumber(saved.damage) or 0.0,
                        tonumber(saved.dirt) or 0.0,
                        tonumber(saved.soot) or 0.0,
                        native and ('%.3f/%.3f/%.3f/%.3f/%.3f@%s'):format(
                            native.degradation, native.permanentDegradation,
                            native.damage, native.dirt, native.soot,
                            tostring(native.attachPoint)) or 'unavailable'))
            end
        end
    end, false)

    -- Read-only native snapshot that can capture a broken wheel/holster
    -- presentation without repairing or replacing coordinator-owned GUIDs.
    RegisterCommand('weaponruntime', function()
        local ped = PlayerPedId()
        local coordinator = FeatherNativeWeaponCoordinator.GetStatus()
        local selectedOk, selected = GetCurrentPedWeapon(ped, true, 0, false)
        print(('[feather-weapons] runtime state=%s epoch=%s reason=%s selected=%s/%s dual=%s')
            :format(tostring(coordinator.state), tostring(coordinator.epoch),
                tostring(coordinator.reason), tostring(selectedOk), tostring(selected),
                tostring(NativeTrue(GetAllowDualWield(ped)))))

        print(('[feather-weapons] runtime checkpoint pair=%s inFlight=%s pending=%s consumed=%s/%s observed=%s/%s/%s')
            :format(tostring(equipped ~= nil and offhand ~= nil),
                tostring(pairSyncInFlight), tostring(pairCheckpointPending),
                tostring(pairConsumed.primary), tostring(pairConsumed.offhand),
                tostring(pairObserved and pairObserved.primary),
                tostring(pairObserved and pairObserved.offhand),
                tostring(pairObserved and pairObserved.total)))
        print(('[feather-weapons] runtime checkpoint longguns inFlight=%s/%s consumed=%s/%s observed=%s/%s')
            :format(tostring(extraSyncInFlight.shoulder), tostring(extraSyncInFlight.back),
                tostring(extraObserved.shoulder and rawget(extraObserved.shoulder, 'consumed')),
                tostring(extraObserved.back and rawget(extraObserved.back, 'consumed')),
                tostring(extraObserved.shoulder and rawget(extraObserved.shoulder, 'loaded')),
                tostring(extraObserved.back and rawget(extraObserved.back, 'loaded'))))
        for _, slot in ipairs(WeaponConstants.LoadoutSlots) do
            local state = SlotState(slot)
            if state then
                local clipOk, loaded
                if (slot == 'primary' or slot == 'offhand') and equipped and offhand then
                    local primaryOk, primaryLoaded, offhandOk, offhandLoaded = PairNativeClips(equipped, offhand)
                    if slot == 'primary' then
                        clipOk, loaded = primaryOk, primaryLoaded
                    else
                        clipOk, loaded = offhandOk, offhandLoaded
                    end
                else
                    clipOk, loaded = GetAmmoInClip(ped, joaat(state.nativeWeaponName))
                end

                print(('[feather-weapons] runtime local %s item=%s generation=%s total=%s loaded=%s reserve=%s nativeLoaded=%s clipOk=%s')
                    :format(slot, tostring(state.itemInstanceId), tostring(state.generation),
                        tostring(state.ammo), tostring(state.loaded), tostring(state.reserve),
                        tostring(loaded), tostring(clipOk)))
            end
        end

        local reportedPools = {}
        for _, slot in ipairs(WeaponConstants.LoadoutSlots) do
            local state = SlotState(slot)
            if state and state.nativeAmmoName and not reportedPools[state.nativeAmmoName] then
                reportedPools[state.nativeAmmoName] = true
                print(('[feather-weapons] runtime ammo %s nativeTotal=%s')
                    :format(state.nativeAmmoName, tostring(GetPedAmmoByType(ped, joaat(state.nativeAmmoName)))))
            end
        end

        for _, slot in ipairs({ 'primary', 'offhand' }) do
            local state = coordinator.slots[slot]
            if state then
                local clipOk, loaded = FeatherGuidWeapons.ReadClip(ped, state.guidRecord)
                local total = FeatherGuidWeapons.ReadTotal(ped, state.guidRecord)
                print(('[feather-weapons] runtime %s item=%s weapon=%s nativeSlot=%s clip=%s/%s total=%s')
                    :format(slot, tostring(state.itemInstanceId),
                        tostring(state.nativeWeaponName),
                        tostring(state.guidRecord and state.guidRecord.slot),
                        tostring(clipOk), tostring(loaded), tostring(total)))
            end
        end

        local points = {}
        for _, attachPoint in ipairs({ 0, 1, 2, 3,
            Config.Loadout.shoulderAttachPoint, Config.Loadout.backAttachPoint }) do
            local present, weaponHash = GetCurrentPedWeapon(ped, true, attachPoint, true)
            points[#points + 1] = ('%d=%s/%s/%s'):format(attachPoint, tostring(present), tostring(weaponHash),
                tostring(GetCurrentPedWeaponEntityIndex(ped, attachPoint)))
        end
        print(('[feather-weapons] runtime points [%s]'):format(table.concat(points, ', ')))
    end, false)

    RegisterCommand('weaponstate', function()
        -- Diagnostics must not rebuild native weapons or disturb a depletion
        -- fallback. Query server authority directly and only print the result.
        FeatherCore.RPC.Call('feather-weapons:state:get', {}, function(result, rpcError)
            if result and result.ok then
                local coordinator = FeatherNativeWeaponCoordinator.GetStatus()
                local coordinatorPrimary = coordinator.slots.primary
                local coordinatorOffhand = coordinator.slots.offhand
                print(('[feather-weapons] coordinator state=%s epoch=%s reason=%s primary=%s offhand=%s')
                    :format(tostring(coordinator.state), tostring(coordinator.epoch),
                        tostring(coordinator.reason),
                        tostring(coordinatorPrimary and coordinatorPrimary.itemInstanceId),
                        tostring(coordinatorOffhand and coordinatorOffhand.itemInstanceId)))
                for nativeAmmoName, window in pairs(coordinator.ammoWindows or {}) do
                    print(('[feather-weapons] coordinator ammo=%s authorized=%s ceiling=%s observed=%s')
                        :format(tostring(nativeAmmoName), tostring(window.authorized),
                            tostring(window.ceiling), tostring(window.observed)))
                end

                local state = result.value.equipped
                local slots = result.value.slots or {}
                local secondary = slots.offhand
                print(('[feather-weapons] state equipped=%s primaryEquipped=%s item=%s generation=%s total=%s loaded=%s reserve=%s condition=%s')
                    :format(
                        tostring(next(slots) ~= nil), tostring(state ~= nil),
                        tostring(state and state.itemInstanceId),
                        tostring(state and state.generation),
                        tostring(state and state.ammo), tostring(state and state.loaded),
                        tostring(state and state.reserve), tostring(state and state.condition)))
                if state then
                    print(('[feather-weapons] ammo type=%s native=%s'):format(tostring(state.ammunitionType), tostring(state.nativeAmmoName)))
                    local attachmentIds = {}
                    for _, attachment in ipairs(state.attachments or {}) do
                        attachmentIds[#attachmentIds + 1] = tostring(attachment.definitionId)
                    end

                    print(('[feather-weapons] attachments count=%s ids=%s'):format(
                        tostring(#attachmentIds), #attachmentIds > 0 and table.concat(attachmentIds, ',') or 'none'))

                    local ped = PlayerPedId()
                    local clipOk, nativeLoaded
                    if secondary then
                        clipOk, nativeLoaded = PairNativeClips(state, secondary)
                    else
                        clipOk, nativeLoaded = GetAmmoInClip(ped, joaat(state.nativeWeaponName))
                    end

                    local nativeTotal = GetPedAmmoByType(ped, joaat(state.nativeAmmoName))
                    print(('[feather-weapons] native total=%s loaded=%s clipOk=%s'):format(
                        tostring(nativeTotal), tostring(nativeLoaded), tostring(clipOk)))
                end

                if secondary then
                    print(('[feather-weapons] offhand ammo type=%s native=%s'):format(
                        tostring(secondary.ammunitionType), tostring(secondary.nativeAmmoName)))
                    local _, _, clipOk, nativeLoaded = PairNativeClips(state, secondary)
                    print(('[feather-weapons] offhand item=%s generation=%s total=%s loaded=%s reserve=%s condition=%s attachments=%s nativeLoaded=%s clipOk=%s')
                    :format(
                        tostring(secondary.itemInstanceId), tostring(secondary.generation),
                        tostring(secondary.ammo), tostring(secondary.loaded),
                        tostring(secondary.reserve), tostring(secondary.condition),
                        tostring(#(secondary.attachments or {})),
                        tostring(nativeLoaded), tostring(clipOk)
                    ))

                    print(('[feather-weapons] pair nativeTotal=%s consumed=%s/%s'):format(
                        tostring(PairNativeTotal(state, secondary)),
                        tostring(pairConsumed.primary), tostring(pairConsumed.offhand)
                    ))
                end

                for _, slot in ipairs({ 'shoulder', 'back' }) do
                    local longgun = result.value.slots and result.value.slots[slot] or nil
                    if longgun then
                        local clipOk, nativeLoaded = GetAmmoInClip(
                            PlayerPedId(), joaat(longgun.nativeWeaponName))
                        local attachPoint = slot == 'shoulder'
                            and Config.Loadout.shoulderAttachPoint or Config.Loadout.backAttachPoint
                        local attachOk, attachedWeapon = GetCurrentPedWeapon(
                            PlayerPedId(), true, attachPoint, true)
                        print(('[feather-weapons] %s item=%s definition=%s generation=%s total=%s loaded=%s reserve=%s condition=%s ammoType=%s nativeAmmo=%s nativeLoaded=%s clipOk=%s attachPoint=%s attached=%s/%s')
                            :format(slot, tostring(longgun.itemInstanceId),
                                tostring(longgun.definitionId), tostring(longgun.generation),
                                tostring(longgun.ammo), tostring(longgun.loaded),
                                tostring(longgun.reserve), tostring(longgun.condition),
                                tostring(longgun.ammunitionType), tostring(longgun.nativeAmmoName),
                                tostring(nativeLoaded), tostring(clipOk), tostring(attachPoint),
                                tostring(attachOk), tostring(attachedWeapon)))
                    end
                end
                return
            end

            local failure = result and result.error or rpcError
            print(('[feather-weapons] state failed: %s'):format(failure and
            (tostring(failure.code) .. ' - ' .. tostring(failure.message)) or 'no response'))
        end)
    end, false)

    RegisterCommand('WeaponDualEntitlementRemove', function()
        if not offhand then
            print('[feather-weapons] offhand entitlement remove skipped: no offhand equipped')
            return
        end

        RemoveOffhandEntitlements()
        SetAllowDualWield(PlayerPedId(), false)
        print('[feather-weapons] offhand entitlement removed; awaiting fail-closed recovery')
    end, false)
end

exports('initiate', function() return FeatherWeaponsClient end)

FeatherWeaponsClientReady = true
