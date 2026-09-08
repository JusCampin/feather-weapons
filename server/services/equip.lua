EquipService = {}

local function BuildContext(source, session, correlationId, reason)
    return {
        actorSource = source,
        actorCharacterId = session.characterId,
        characterId = session.characterId,
        sessionId = session.sessionId,
        correlationId = correlationId,
        reason = reason,
        resource = "feather-weapons"
    }
end

function EquipService.ValidateOwnedItem(context, itemInstanceId)
    local idType = type(itemInstanceId)
    if (idType ~= "string" and idType ~= "number")
        or (idType == "string" and (itemInstanceId == "" or #itemInstanceId > 128))
        or (idType == "number" and (itemInstanceId < 1 or itemInstanceId % 1 ~= 0)) then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID, "Item instance ID is invalid", nil, context.correlationId)
    end

    local itemResult = InventoryAdapter.GetItemForCharacter(context, itemInstanceId)
    if not itemResult.ok then return itemResult end
    local item = itemResult.value
    local metadata = type(item.metadata) == "table" and item.metadata or nil
    if not metadata or type(metadata.weaponDefinitionId) ~= "string" then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID, "Weapon item metadata is invalid", {
            itemInstanceId = itemInstanceId
        }, context.correlationId)
    end

    local definitionResult = DefinitionRegistry.Get("weapon", metadata.weaponDefinitionId)
    if not definitionResult.ok then return definitionResult end
    local definition = definitionResult.value
    if item.itemName ~= definition.itemName then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID, "Item definition does not match weapon metadata", {
            itemName = item.itemName,
            expectedItemName = definition.itemName
        }, context.correlationId)
    end

    local metadataResult = WeaponMetadata.Validate(metadata, definition, context.correlationId)
    if not metadataResult.ok then return metadataResult end
    if metadata.flags.disabled or metadata.flags.evidence then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID, "Weapon item is disabled", {
            itemInstanceId = itemInstanceId
        }, context.correlationId)
    end
    if tonumber(metadata.condition) < definition.condition.equipMinimum then
        return WeaponResult.Error(WeaponErrors.CONDITION_BROKEN, "Weapon condition is too low to equip", {
            condition = metadata.condition,
            minimum = definition.condition.equipMinimum
        }, context.correlationId)
    end
    return WeaponResult.Ok({ item = item, definition = definition }, context.correlationId)
end

local function ValidateSlotEligibility(source, slot, definition, correlationId, metadata)
    local runtime = WeaponRuntime.Get(source)
    local configured = definition.slot == "sidearm"
        and (Config.Loadout and Config.Loadout.sidearmSlots)
        or (definition.slot == "longgun" and Config.Loadout and Config.Loadout.longgunSlots or nil)
    if slot == nil or slot == "auto" then
        for _, candidate in ipairs(configured or {}) do
            if not (runtime and runtime.slots and runtime.slots[candidate]) then
                slot = candidate
                break
            end
        end
        if slot == nil or slot == "auto" then
            return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
                "Every compatible weapon slot is occupied", { weaponSlot = definition.slot }, correlationId)
        end
    end
    slot = WeaponRuntime.NormalizeSlot(slot)
    if not slot then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID,
            "Weapon equipment slot is invalid", nil, correlationId)
    end
    local expectedCategory = WeaponConstants.SidearmSlots[slot] and "sidearm"
        or (WeaponConstants.LonggunSlots[slot] and "longgun" or nil)
    if definition.slot ~= expectedCategory then
        return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
            "That weapon cannot use the requested loadout slot", {
                slot = slot, weaponSlot = definition.slot
            }, correlationId)
    end
    for _, otherSlot in ipairs(WeaponConstants.LoadoutSlots) do
        local other = runtime and runtime.slots and runtime.slots[otherSlot] or nil
        if other and otherSlot ~= slot and other.nativeWeaponName == definition.nativeWeaponName then
            return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
                "Two weapons with the same native model cannot be equipped together", {
                    slot = slot,
                    otherSlot = otherSlot,
                    definitionId = definition.id,
                    nativeWeaponName = definition.nativeWeaponName
                }, correlationId)
        end
    end
    if expectedCategory == "longgun" then
        local ammunitionType = metadata.ammo.type or definition.ammunitionType
        local ammunition = DefinitionRegistry.Get("ammunition", ammunitionType)
        if not ammunition.ok then return ammunition end
        for _, otherSlot in ipairs(Config.Loadout.longgunSlots or {}) do
            local other = runtime and runtime.slots and runtime.slots[otherSlot] or nil
            if other and otherSlot ~= slot
                and other.nativeAmmoName == ammunition.value.nativeAmmoName then
                return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
                    "Shoulder and back weapons must use different ammunition types", {
                        slot = slot,
                        otherSlot = otherSlot,
                        ammunitionType = ammunitionType,
                        nativeAmmoName = ammunition.value.nativeAmmoName
                    }, correlationId)
            end
        end
    end
    if slot ~= "offhand" then return WeaponResult.Ok(slot, correlationId) end

    local settings = Config.Offhand or {}
    if settings.enabled ~= true then
        return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
            "Offhand weapons are disabled on this server", nil, correlationId)
    end
    local primary = runtime and runtime.slots and runtime.slots.primary or nil
    if not primary then
        return WeaponResult.Error(WeaponErrors.NOT_EQUIPPED,
            "Equip a primary weapon before equipping a second weapon", nil, correlationId)
    end
    local primaryDefinition = DefinitionRegistry.Get("weapon", primary.definitionId)
    if not primaryDefinition.ok then return primaryDefinition end

    if type(settings.allowedFamilies) ~= "table"
        or settings.allowedFamilies[definition.family] ~= true then
        return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
            "This weapon family is not allowed in the offhand slot",
            { family = definition.family }, correlationId)
    end
    if type(settings.allowedWeaponSlots) ~= "table"
        or settings.allowedWeaponSlots[definition.slot] ~= true then
        return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
            "This weapon category is not allowed in the offhand slot",
            { weaponSlot = definition.slot }, correlationId)
    end

    return WeaponResult.Ok(slot, correlationId)
end

function EquipService.ValidateConfiguration()
    local settings = Config.Offhand
    if type(settings) ~= "table" or type(settings.enabled) ~= "boolean"
        or type(settings.provisionNativeEntitlement) ~= "boolean"
        or type(settings.allowedFamilies) ~= "table"
        or type(settings.allowedWeaponSlots) ~= "table" then
        return WeaponResult.Error(WeaponErrors.INVALID_DEFINITION,
            "Offhand configuration is invalid")
    end
    if settings.provisionNativeEntitlement then
        if type(settings.nativeEntitlements) ~= "table"
            or #settings.nativeEntitlements < 1 then
            return WeaponResult.Error(WeaponErrors.INVALID_DEFINITION,
                "Offhand native entitlements are invalid")
        end
        for _, entitlement in ipairs(settings.nativeEntitlements) do
            local slotId = type(entitlement) == "table" and tonumber(entitlement.slotId) or nil
            if type(entitlement) ~= "table" or type(entitlement.itemName) ~= "string"
                or entitlement.itemName == "" or not slotId or slotId % 1 ~= 0 then
                return WeaponResult.Error(WeaponErrors.INVALID_DEFINITION,
                    "Offhand native entitlement entry is invalid")
            end
        end
    end
    local primaryPoint = tonumber(settings.primaryAttachPoint)
    local offhandPoint = tonumber(settings.offhandAttachPoint)
    if not primaryPoint or primaryPoint % 1 ~= 0 or not offhandPoint
        or offhandPoint % 1 ~= 0 or primaryPoint == offhandPoint then
        return WeaponResult.Error(WeaponErrors.INVALID_DEFINITION,
            "Offhand holster attachment points are invalid")
    end
    if settings.enabled ~= true then return WeaponResult.Ok(true) end
    if type(Config.Loadout) ~= "table"
        or type(Config.Loadout.sidearmSlots) ~= "table"
        or type(Config.Loadout.longgunSlots) ~= "table" then
        return WeaponResult.Error(WeaponErrors.INVALID_DEFINITION,
            "Weapon loadout configuration is invalid")
    end
    for _, slot in ipairs(Config.Loadout.sidearmSlots) do
        if not WeaponConstants.SidearmSlots[slot] then
            return WeaponResult.Error(WeaponErrors.INVALID_DEFINITION,
                "Sidearm loadout slot configuration is invalid")
        end
    end
    for _, slot in ipairs(Config.Loadout.longgunSlots) do
        if not WeaponConstants.LonggunSlots[slot] then
            return WeaponResult.Error(WeaponErrors.INVALID_DEFINITION,
                "Long-gun loadout slot configuration is invalid")
        end
    end
    local shoulderPoint = tonumber(Config.Loadout.shoulderAttachPoint)
    local backPoint = tonumber(Config.Loadout.backAttachPoint)
    if not shoulderPoint or shoulderPoint % 1 ~= 0
        or not backPoint or backPoint % 1 ~= 0 or shoulderPoint == backPoint then
        return WeaponResult.Error(WeaponErrors.INVALID_DEFINITION,
            "Long-gun native attachment points are invalid")
    end

    local definitions = DefinitionRegistry.List("weapon")
    if not definitions.ok then return definitions end
    for _, definition in ipairs(definitions.value) do
        if settings.allowedFamilies[definition.family] == true
            and settings.allowedWeaponSlots[definition.slot] == true then
            return WeaponResult.Ok(true)
        end
    end
    return WeaponResult.Error(WeaponErrors.INVALID_DEFINITION,
        "Offhand allowlists do not match any configured weapon definition")
end

function EquipService.Request(source, rpcContext, itemInstanceId, slot)
    local context = BuildContext(source, rpcContext, rpcContext.correlationId, "equip")
    local validationResult = EquipService.ValidateOwnedItem(context, itemInstanceId)
    if not validationResult.ok then return validationResult end
    local eligibility = ValidateSlotEligibility(
        source, slot, validationResult.value.definition, context.correlationId, validationResult.value.item.metadata)
    if not eligibility.ok then return eligibility end
    return WeaponRuntime.BeginEquip(source, context.sessionId, validationResult.value.item,
        validationResult.value.definition, context.correlationId, eligibility.value)
end

function EquipService.Acknowledge(source, rpcContext, token)
    if type(token) ~= "string" or #token > 256 then
        return WeaponResult.Error(WeaponErrors.AUTHORIZATION_INVALID, "Equip authorization is invalid", nil,
            rpcContext.correlationId)
    end

    local result = WeaponRuntime.CompleteEquip(source, rpcContext.sessionId, token, rpcContext.correlationId)
    if not result.ok then return result end

    local context = BuildContext(source, rpcContext, rpcContext.correlationId, "equip_commit")
    local persistResult = InventoryAdapter.SetEquippedSlotForCharacter(
        context, result.value.slot, result.value.itemInstanceId)
    if not persistResult.ok then
        WeaponRuntime.Unequip(source, rpcContext.sessionId, rpcContext.correlationId, result.value.slot)
        return persistResult
    end
    return result
end

function EquipService.Restore(source, session, itemInstanceId, correlationId, slot)
    local context = BuildContext(source, session, correlationId, "reconcile")
    local validationResult = EquipService.ValidateOwnedItem(context, itemInstanceId)
    if not validationResult.ok then return validationResult end
    local eligibility = ValidateSlotEligibility(
        source, slot, validationResult.value.definition, correlationId, validationResult.value.item.metadata)
    if not eligibility.ok then return eligibility end
    return WeaponRuntime.RestoreEquipped(source, session.sessionId, validationResult.value.item,
        validationResult.value.definition, correlationId, eligibility.value)
end

function EquipService.Unequip(source, rpcContext, slot)
    local runtime = WeaponRuntime.Get(source)
    if not runtime or runtime.sessionId ~= rpcContext.sessionId then
        return WeaponResult.Error(WeaponErrors.SESSION_EXPIRED, "Character session is no longer active", nil,
            rpcContext.correlationId)
    end

    local context = BuildContext(source, rpcContext, rpcContext.correlationId, "unequip")
    slot = WeaponRuntime.NormalizeSlot(slot)
    if not slot then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID, "Weapon equipment slot is invalid", nil,
            rpcContext.correlationId)
    end
    if slot == "primary" and runtime.slots and runtime.slots.offhand then
        local persisted = InventoryAdapter.PromoteOffhandToPrimary(context)
        if not persisted.ok then return persisted end
        local promoted = WeaponRuntime.PromoteOffhand(
            source, rpcContext.sessionId, rpcContext.correlationId)
        if not promoted.ok then
            TriggerClientEvent("feather-weapons:client:forceReconcile", source)
            return promoted
        end
        return promoted
    end
    local persistResult = InventoryAdapter.SetEquippedSlotForCharacter(context, slot, nil)
    if not persistResult.ok then return persistResult end

    local result = WeaponRuntime.Unequip(source, rpcContext.sessionId, rpcContext.correlationId, slot)
    return result
end

FeatherCore.RPC.Register("feather-weapons:equip:request", function(params, respond, source, context)
    respond(EquipService.Request(source, context, params and params.itemInstanceId, params and params.slot))
end, { requireCharacter = true, windowMs = 1000, maxCalls = 4, maxPayloadBytes = 256 })

FeatherCore.RPC.Register("feather-weapons:equip:acknowledge", function(params, respond, source, context)
    respond(EquipService.Acknowledge(source, context, params and params.token))
end, { requireCharacter = true, windowMs = 1000, maxCalls = 6, maxPayloadBytes = 512 })

FeatherCore.RPC.Register("feather-weapons:equip:unequip", function(params, respond, source, context)
    respond(EquipService.Unequip(source, context, params and params.slot))
end, { requireCharacter = true, windowMs = 1000, maxCalls = 4, maxPayloadBytes = 64 })
