WeaponRuntime = {}
local sessions = {}

local function MaintenanceSnapshot(metadata)
    local value = type(metadata.maintenance) == "table" and metadata.maintenance or {}
    return {
        degradation = tonumber(value.degradation) or 0.0,
        permanentDegradation = tonumber(value.permanentDegradation) or 0.0,
        damage = tonumber(value.damage) or 0.0,
        dirt = tonumber(value.dirt) or 0.0,
        soot = tonumber(value.soot) or 0.0
    }
end
local tokenCounter = 0
local validSlots = { primary = true, offhand = true, shoulder = true, back = true }

local function EmptySlots()
    return { primary = nil, offhand = nil, shoulder = nil, back = nil }
end

function WeaponRuntime.NormalizeSlot(slot)
    slot = slot or "primary"
    return validSlots[slot] and slot or nil
end

local function RefreshCompatibility(runtime)
    runtime.equipped = runtime.slots and runtime.slots.primary or nil
    local occupied = runtime.slots
        and (runtime.slots.primary ~= nil or runtime.slots.offhand ~= nil
            or runtime.slots.shoulder ~= nil or runtime.slots.back ~= nil)
    runtime.state = runtime.pending and "equipping" or (occupied and "equipped" or "idle")
end

function WeaponRuntime.GetSlot(source, slot)
    local runtime = sessions[tonumber(source) or source]
    slot = WeaponRuntime.NormalizeSlot(slot)
    return runtime and slot and runtime.slots and runtime.slots[slot] or nil
end

local function NextGeneration(runtime)
    runtime.generation = (tonumber(runtime.generation) or 0) + 1
    return runtime.generation
end

local function NativeAmmoName(definition, metadata)
    local result = DefinitionRegistry.Get("ammunition", metadata.ammo.type or definition.ammunitionType)
    return result.ok and result.value.nativeAmmoName or nil
end

local function InstalledAttachments(metadata)
    local result = {}
    for _, installed in ipairs(metadata.attachments or {}) do
        local definition = DefinitionRegistry.Get("attachment", installed.definitionId)
        if definition.ok then
            result[#result + 1] = {
                definitionId = definition.value.id,
                slot = definition.value.slot,
                nativeComponentName = definition.value.nativeComponentName
            }
        end
    end
    return result
end

local function NextToken(runtime)
    tokenCounter = tokenCounter + 1
    return ("%s:%s:%s:%s"):format(runtime.sessionId, tostring(GetGameTimer()), tostring(tokenCounter),
        tostring(math.random(100000, 999999)))
end

function WeaponRuntime.Get(source)
    return sessions[source]
end

local function AmmoSnapshot(metadata, definition)
    local loaded = math.max(0, math.min(definition.capacity,
        math.floor(tonumber(metadata.ammo and metadata.ammo.loaded) or 0)))
    local reserve = math.max(0, math.floor(tonumber(metadata.ammo and metadata.ammo.reserve) or 0))
    return loaded, reserve, loaded + reserve
end

function WeaponRuntime.MatchesLease(source, sessionId, itemInstanceId, generation, slot)
    local runtime = sessions[tonumber(source) or source]
    slot = WeaponRuntime.NormalizeSlot(slot)
    local equipped = runtime and slot and runtime.slots and runtime.slots[slot]
    return runtime ~= nil and equipped ~= nil
        and tostring(runtime.sessionId or "") == tostring(sessionId or "")
        and tostring(equipped.sessionId or "") == tostring(sessionId or "")
        and tostring(equipped.itemInstanceId or "") == tostring(itemInstanceId or "")
        and tonumber(equipped.generation) == tonumber(generation)
end

function WeaponRuntime.Begin(session)
    sessions[session.source] = {
        source = session.source,
        characterId = session.characterId,
        sessionId = session.sessionId,
        equipped = nil,
        slots = EmptySlots(),
        pending = nil,
        generation = 0,
        state = "idle"
    }
    return sessions[session.source]
end

function WeaponRuntime.Clear(source)
    local previous = sessions[source]
    sessions[source] = nil
    return previous
end

function WeaponRuntime.RestoreEquipped(source, sessionId, item, definition, correlationId, slot)
    local runtime = sessions[source]
    if not runtime or runtime.sessionId ~= sessionId or runtime.state == "leaving" then
        return WeaponResult.Error(WeaponErrors.SESSION_EXPIRED, "Character session is no longer active", nil,
            correlationId)
    end
    slot = WeaponRuntime.NormalizeSlot(slot)
    if not slot then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID, "Weapon equipment slot is invalid", nil, correlationId)
    end
    runtime.pending = nil
    runtime.slots = runtime.slots or EmptySlots()
    local generation = NextGeneration(runtime)
    local loaded, reserve, total = AmmoSnapshot(item.metadata, definition)
    runtime.slots[slot] = {
        slot = slot,
        itemInstanceId = item.id,
        definitionId = definition.id,
        nativeWeaponName = definition.nativeWeaponName,
        ammunitionType = item.metadata.ammo.type or definition.ammunitionType,
        nativeAmmoName = NativeAmmoName(definition, item.metadata),
        ammo = total,
        loaded = loaded,
        reserve = reserve,
        capacity = definition.capacity,
        condition = tonumber(item.metadata.condition) or definition.condition.maximum,
        maintenance = MaintenanceSnapshot(item.metadata),
        attachments = InstalledAttachments(item.metadata),
        generation = generation,
        sessionId = runtime.sessionId,
        equippedAt = os.time()
    }
    RefreshCompatibility(runtime)
    return WeaponResult.Ok(runtime.slots[slot], correlationId)
end

function WeaponRuntime.BeginEquip(source, sessionId, item, definition, correlationId, slot)
    local runtime = sessions[source]
    if not runtime or runtime.sessionId ~= sessionId or runtime.state == "leaving" then
        return WeaponResult.Error(WeaponErrors.SESSION_EXPIRED, "Character session is no longer active", nil,
            correlationId)
    end
    slot = WeaponRuntime.NormalizeSlot(slot)
    if not slot then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID, "Weapon equipment slot is invalid", nil, correlationId)
    end
    runtime.slots = runtime.slots or EmptySlots()
    if runtime.pending then
        return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT, "Another weapon operation is pending", nil,
            correlationId)
    end
    ---@type table|nil
    local occupiedSlot = runtime.slots[slot]
    if occupiedSlot then
        return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT, "Unequip the current weapon slot before equipping another",
            {
                slot = slot,
                itemInstanceId = occupiedSlot.itemInstanceId
            }, correlationId)
    end
    local token = NextToken(runtime)
    local loaded, reserve, total = AmmoSnapshot(item.metadata, definition)
    runtime.pending = {
        slot = slot,
        token = token,
        itemInstanceId = item.id,
        definitionId = definition.id,
        nativeWeaponName = definition.nativeWeaponName,
        ammunitionType = item.metadata.ammo.type or definition.ammunitionType,
        nativeAmmoName = NativeAmmoName(definition, item.metadata),
        ammo = total,
        loaded = loaded,
        reserve = reserve,
        capacity = definition.capacity,
        condition = tonumber(item.metadata.condition) or definition.condition.maximum,
        maintenance = MaintenanceSnapshot(item.metadata),
        attachments = InstalledAttachments(item.metadata),
        expiresAt = GetGameTimer() + Config.Runtime.authorizationTtlMs,
        correlationId = correlationId
    }
    runtime.state = "equipping"

    SetTimeout(Config.Runtime.authorizationTtlMs, function()
        local current = sessions[source]
        if not current or not current.pending or current.pending.token ~= token then return end
        current.pending = nil
        RefreshCompatibility(current)
        TriggerClientEvent("feather-weapons:client:clearAuthorization", source, token)
    end)

    return WeaponResult.Ok({
        token = token,
        slot = slot,
        itemInstanceId = item.id,
        definitionId = definition.id,
        nativeWeaponName = definition.nativeWeaponName,
        ammunitionType = item.metadata.ammo.type or definition.ammunitionType,
        nativeAmmoName = NativeAmmoName(definition, item.metadata),
        ammo = total,
        loaded = loaded,
        reserve = reserve,
        capacity = definition.capacity,
        condition = tonumber(item.metadata.condition) or definition.condition.maximum,
        maintenance = MaintenanceSnapshot(item.metadata),
        attachments = InstalledAttachments(item.metadata),
        expiresInMs = Config.Runtime.authorizationTtlMs
    }, correlationId)
end

function WeaponRuntime.CompleteEquip(source, sessionId, token, correlationId)
    local runtime = sessions[source]
    local pending = runtime and runtime.pending
    if not runtime or runtime.sessionId ~= sessionId or not pending or pending.token ~= token then
        return WeaponResult.Error(WeaponErrors.AUTHORIZATION_INVALID, "Equip authorization is invalid or expired", nil,
            correlationId)
    end
    if GetGameTimer() > pending.expiresAt then
        runtime.pending = nil
        RefreshCompatibility(runtime)
        return WeaponResult.Error(WeaponErrors.AUTHORIZATION_INVALID, "Equip authorization expired", nil, correlationId)
    end

    local slot = WeaponRuntime.NormalizeSlot(pending.slot)
    runtime.slots = runtime.slots or EmptySlots()
    runtime.slots[slot] = {
        slot = slot,
        itemInstanceId = pending.itemInstanceId,
        definitionId = pending.definitionId,
        nativeWeaponName = pending.nativeWeaponName,
        ammunitionType = pending.ammunitionType,
        nativeAmmoName = pending.nativeAmmoName,
        ammo = pending.ammo,
        loaded = pending.loaded,
        reserve = pending.reserve,
        capacity = pending.capacity,
        condition = pending.condition,
        maintenance = pending.maintenance,
        attachments = pending.attachments,
        generation = NextGeneration(runtime),
        sessionId = runtime.sessionId,
        equippedAt = os.time()
    }
    runtime.pending = nil
    RefreshCompatibility(runtime)
    return WeaponResult.Ok(runtime.slots[slot], correlationId)
end

function WeaponRuntime.SetSlotAmmunitionType(source, sessionId, slot, ammunitionType)
    local runtime = sessions[source]
    local equipped = runtime and runtime.sessionId == sessionId and runtime.slots[slot]
    if not equipped then return false end
    local ammunition = DefinitionRegistry.Get("ammunition", ammunitionType)
    if not ammunition.ok then return false end
    equipped.ammunitionType = ammunitionType
    equipped.nativeAmmoName = ammunition.value.nativeAmmoName
    equipped.generation = NextGeneration(runtime)
    return true
end

function WeaponRuntime.SetSlotAmmo(source, sessionId, slot, total, loaded, correlationId)
    local runtime = sessions[source]
    slot = WeaponRuntime.NormalizeSlot(slot)
    local equipped = runtime and slot and runtime.slots and runtime.slots[slot]
    if not runtime or runtime.sessionId ~= sessionId then
        return WeaponResult.Error(WeaponErrors.SESSION_EXPIRED,
            "Character session is no longer active", nil, correlationId)
    end
    if not equipped then
        return WeaponResult.Error(WeaponErrors.NOT_EQUIPPED,
            "No weapon is equipped in that slot", { slot = slot }, correlationId)
    end
    local definitionResult = DefinitionRegistry.Get("weapon", equipped.definitionId)
    if not definitionResult.ok then return definitionResult end
    total = math.floor(tonumber(total) or -1)
    loaded = math.floor(tonumber(loaded) or -1)
    local maxTotal = WeaponValidation.EscrowMaximum(
        definitionResult.value, equipped.ammunitionType)
    if total < 0 or total > maxTotal or loaded < 0
        or loaded > definitionResult.value.capacity or loaded > total then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID,
            "Ammunition is outside weapon capacity", { slot = slot }, correlationId)
    end
    equipped.ammo = total
    equipped.loaded = loaded
    equipped.reserve = total - loaded
    return WeaponResult.Ok({ slot = slot, total = total, loaded = loaded,
        reserve = total - loaded }, correlationId)
end

function WeaponRuntime.SetSlotCondition(source, sessionId, slot, condition, correlationId)
    local equipped = WeaponRuntime.GetSlot(source, slot)
    local runtime = sessions[source]
    if not runtime or runtime.sessionId ~= sessionId then
        return WeaponResult.Error(WeaponErrors.SESSION_EXPIRED,
            "Character session is no longer active", nil, correlationId)
    end
    if not equipped then
        return WeaponResult.Error(WeaponErrors.NOT_EQUIPPED,
            "No weapon is equipped in that slot", { slot = slot }, correlationId)
    end
    equipped.condition = tonumber(condition)
    return WeaponResult.Ok({ slot = slot, condition = equipped.condition }, correlationId)
end

function WeaponRuntime.SetSlotMaintenance(source, sessionId, slot, maintenance, condition, correlationId)
    local runtime = sessions[source]
    slot = WeaponRuntime.NormalizeSlot(slot)
    local equipped = runtime and runtime.sessionId == sessionId and slot
        and runtime.slots and runtime.slots[slot] or nil
    if not equipped then
        return WeaponResult.Error(WeaponErrors.NOT_EQUIPPED,
            "No weapon is equipped in that slot", nil, correlationId)
    end
    equipped.maintenance = maintenance
    equipped.condition = tonumber(condition) or equipped.condition
    return WeaponResult.Ok({ slot = slot, maintenance = maintenance,
        condition = equipped.condition }, correlationId)
end

function WeaponRuntime.SetSlotAttachments(source, sessionId, slot, attachments, correlationId)
    local equipped = WeaponRuntime.GetSlot(source, slot)
    local runtime = sessions[source]
    if not runtime or runtime.sessionId ~= sessionId then
        return WeaponResult.Error(WeaponErrors.SESSION_EXPIRED,
            "Character session is no longer active", nil, correlationId)
    end
    if not equipped then
        return WeaponResult.Error(WeaponErrors.NOT_EQUIPPED,
            "No weapon is equipped in that slot", { slot = slot }, correlationId)
    end
    equipped.attachments = attachments or {}
    return WeaponResult.Ok({ slot = slot, attachments = equipped.attachments }, correlationId)
end

function WeaponRuntime.ResetForReconcile(source, sessionId, correlationId)
    local runtime = sessions[source]
    if not runtime or runtime.sessionId ~= sessionId or runtime.state == "leaving" then
        return WeaponResult.Error(WeaponErrors.SESSION_EXPIRED,
            "Character session is no longer active", nil, correlationId)
    end
    runtime.pending = nil
    runtime.equipped = nil
    runtime.slots = EmptySlots()
    RefreshCompatibility(runtime)
    return WeaponResult.Ok({ generation = runtime.generation }, correlationId)
end

function WeaponRuntime.Unequip(source, sessionId, correlationId, slot)
    local runtime = sessions[source]
    if not runtime or runtime.sessionId ~= sessionId then
        return WeaponResult.Error(WeaponErrors.SESSION_EXPIRED, "Character session is no longer active", nil,
            correlationId)
    end
    slot = WeaponRuntime.NormalizeSlot(slot)
    if not slot then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID, "Weapon equipment slot is invalid", nil, correlationId)
    end
    runtime.slots = runtime.slots or EmptySlots()
    local pendingForSlot = runtime.pending and runtime.pending.slot == slot
    if not runtime.slots[slot] and not pendingForSlot then
        return WeaponResult.Error(WeaponErrors.NOT_EQUIPPED, "No weapon is equipped", nil, correlationId)
    end

    local previous = runtime.slots[slot]
    runtime.slots[slot] = nil
    if pendingForSlot then runtime.pending = nil end
    RefreshCompatibility(runtime)
    return WeaponResult.Ok(previous, correlationId)
end

function WeaponRuntime.PromoteOffhand(source, sessionId, correlationId)
    local runtime = sessions[source]
    if not runtime or runtime.sessionId ~= sessionId then
        return WeaponResult.Error(WeaponErrors.SESSION_EXPIRED,
            "Character session is no longer active", nil, correlationId)
    end
    runtime.slots = runtime.slots or EmptySlots()
    local promoted = runtime.slots.offhand
    if not promoted then
        return WeaponResult.Error(WeaponErrors.NOT_EQUIPPED,
            "No offhand weapon is available for promotion", nil, correlationId)
    end
    local removed = runtime.slots.primary
    promoted.slot = "primary"
    promoted.generation = NextGeneration(runtime)
    promoted.equippedAt = os.time()
    runtime.slots.primary = promoted
    runtime.slots.offhand = nil
    runtime.pending = nil
    RefreshCompatibility(runtime)
    return WeaponResult.Ok({ removed = removed, promoted = promoted }, correlationId)
end

AddEventHandler("core.session.ready.v1", function(session)
    local characterId = session and CoreAdapter.NormalizeCharacterId(session.characterId)
    if not characterId then return end
    session.characterId = characterId
    WeaponRuntime.Begin(session)
    if ReconciliationService then ReconciliationService.RehydrateSession(session) end
end)

AddEventHandler("core.session.leaving.v1", function(session)
    local runtime = sessions[session.source]
    if runtime and runtime.sessionId == session.sessionId then
        runtime.state = "leaving"
        runtime.pending = nil
        runtime.equipped = nil
        runtime.slots = EmptySlots()
        TriggerClientEvent("feather-weapons:client:clear", session.source)
    end
end)

AddEventHandler("core.session.left.v1", function(session)
    local runtime = sessions[session.source]
    if runtime and runtime.sessionId == session.sessionId then WeaponRuntime.Clear(session.source) end
end)

AddEventHandler("playerDropped", function()
    WeaponRuntime.Clear(source)
end)
