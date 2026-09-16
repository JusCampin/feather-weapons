WeaponOwnershipService = {}
local diagnostics = {
    observed = 0,
    failed = 0,
    leaseViolations = 0,
    byType = {},
    last = nil
}

local function CleanText(value, maximum)
    if value == nil then return nil end
    value = tostring(value)
    if value == "" then return nil end
    return value:sub(1, maximum)
end

function WeaponOwnershipService.EvaluateAdministrativeHold(metadata)
    if type(metadata) ~= "table" or type(metadata.flags) ~= "table" then
        return false, "Weapon administrative state could not be verified."
    end
    if metadata.flags.evidence == true then
        return false, "This weapon is held as evidence and cannot be moved or removed."
    end
    if metadata.flags.disabled == true then
        return false, "This weapon is administratively disabled and cannot be moved or removed."
    end
    return true
end

local function CharacterInventoryId(characterId, correlationId)
    if not characterId then return nil end
    local inventory = InventoryAdapter.GetCharacterInventory({
        correlationId = correlationId
    }, characterId)
    return inventory.ok and tonumber(inventory.value.id) or nil
end

local function ActiveCharacterForInventory(inventoryId, correlationId)
    inventoryId = tonumber(inventoryId)
    if not inventoryId then return nil end
    for _, playerId in ipairs(GetPlayers()) do
        local session = CoreAdapter.ResolveSession(tonumber(playerId))
        local characterId = session.ok
            and CoreAdapter.NormalizeCharacterId(session.value.characterId) or nil
        if characterId and CharacterInventoryId(characterId, correlationId) == inventoryId then
            return characterId
        end
    end
    return nil
end

local function ClassifyTransition(payload, actorInventoryId)
    local reason = tostring(payload.reason or "")
    if reason == "ground_drop" then return "drop" end
    if reason == "give" then return "transfer" end
    if reason == "container_recovery" then return "recovery" end

    if actorInventoryId then
        if tonumber(payload.toInventoryId) == actorInventoryId then return "pickup" end
        if tonumber(payload.fromInventoryId) == actorInventoryId then return "deposit" end
    end
    return "inventory_move"
end

local function RecordCommittedFact(fact)
    local persisted = WeaponProvenanceService.Record(fact)
    if not persisted.ok then
        diagnostics.failed = diagnostics.failed + 1
        print(("[feather-weapons] CRITICAL provenance persistence failed item=%s type=%s message=%s"):format(
            tostring(fact.itemInstanceId), tostring(fact.transitionType),
            tostring(persisted.error and persisted.error.message)))
    else
        fact.eventId = persisted.value.eventId
    end
    TriggerEvent("Feather:Weapons:OwnershipTransitionCommitted", fact)
    diagnostics.observed = diagnostics.observed + 1
    diagnostics.byType[fact.transitionType] = (diagnostics.byType[fact.transitionType] or 0) + 1
    diagnostics.last = fact
end

function WeaponOwnershipService.HandleCommittedMove(payload)
    if type(payload) ~= "table" then return nil end
    if tostring(payload.fromInventoryId) == tostring(payload.toInventoryId) then return nil end
    local definitionId = InventoryAdapter.ResolveWeaponDefinitionId(payload.definitionId)
    if not definitionId then return nil end

    local instance = InventoryAdapter.GetInstance({ correlationId = payload.correlationId }, payload.instanceId)
    if not instance.ok then
        diagnostics.failed = diagnostics.failed + 1
        print(("[feather-weapons] ownership observation failed item=%s code=%s"):format(
            tostring(payload.instanceId), tostring(instance.error and instance.error.code)))
        return instance
    end

    local metadata = instance.value.metadata or {}
    if metadata.weaponDefinitionId ~= definitionId then
        diagnostics.failed = diagnostics.failed + 1
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID,
            "Moved weapon metadata does not match its Inventory definition", {
                itemInstanceId = payload.instanceId,
                expectedDefinitionId = definitionId,
                actualDefinitionId = metadata.weaponDefinitionId
            }, payload.correlationId)
    end

    local actorCharacterId = CoreAdapter.NormalizeCharacterId(payload.actorCharacterId)
    local actorInventoryId = CharacterInventoryId(actorCharacterId, payload.correlationId)
    local fromCharacterId = tonumber(payload.fromInventoryId) == actorInventoryId
        and actorCharacterId or nil
    local toCharacterId = tonumber(payload.toInventoryId) == actorInventoryId
        and actorCharacterId or nil
    if not fromCharacterId then
        fromCharacterId = ActiveCharacterForInventory(payload.fromInventoryId, payload.correlationId)
    end
    if not toCharacterId then
        toCharacterId = ActiveCharacterForInventory(payload.toInventoryId, payload.correlationId)
    end

    local fact = {
        operation = "inventory_move",
        transitionType = ClassifyTransition(payload, actorInventoryId),
        outcome = "committed",
        itemInstanceId = tonumber(payload.instanceId),
        definitionId = definitionId,
        serialNumber = metadata.serialNumber,
        revision = tonumber(payload.revision) or instance.value.metadataRevision,
        fromInventoryId = tonumber(payload.fromInventoryId),
        toInventoryId = tonumber(payload.toInventoryId),
        actorSource = tonumber(payload.actorSource),
        actorCharacterId = actorCharacterId,
        fromCharacterId = fromCharacterId,
        toCharacterId = toCharacterId,
        reason = CleanText(payload.reason or "inventory_move", 64),
        resource = CleanText(payload.resource or "feather-inventory", 64),
        correlationId = CleanText(payload.correlationId, 128),
        occurredAt = tonumber(payload.occurredAt) or os.time()
    }

    local source, slot = WeaponRuntime.FindLeaseByItem(payload.instanceId)
    fact.activeLeaseViolation = source ~= nil
    if source then
        diagnostics.leaseViolations = diagnostics.leaseViolations + 1
        fact.activeSource = source
        fact.activeSlot = slot
        print(("[feather-weapons] CRITICAL equipped weapon moved item=%s source=%s slot=%s from=%s to=%s"):format(
            tostring(payload.instanceId), tostring(source), tostring(slot),
            tostring(payload.fromInventoryId), tostring(payload.toInventoryId)))
        if ReconciliationService then ReconciliationService.Force(source) end
    end

    RecordCommittedFact(fact)
    if Config.DevMode then
        print(("[feather-weapons] ownership transition item=%s serial=%s definition=%s from=%s/%s to=%s/%s type=%s reason=%s"):format(
            tostring(fact.itemInstanceId), tostring(fact.serialNumber), tostring(fact.definitionId),
            tostring(fact.fromInventoryId), tostring(fact.fromCharacterId),
            tostring(fact.toInventoryId), tostring(fact.toCharacterId),
            tostring(fact.transitionType), tostring(fact.reason)))
    end
    return WeaponResult.Ok(fact, payload.correlationId)
end

function WeaponOwnershipService.GetDiagnostics()
    return {
        observed = diagnostics.observed,
        failed = diagnostics.failed,
        leaseViolations = diagnostics.leaseViolations,
        byType = diagnostics.byType,
        last = diagnostics.last
    }
end

local function AuthorizeDestruction(context, item)
    local settings = (Config.Ownership or {}).authorization or {}
    if settings.enabled ~= true then return WeaponResult.Ok(true, context.correlationId) end
    if not context.actorSource or type(settings.destroyAction) ~= "string"
        or settings.destroyAction == "" then
        return WeaponResult.Error(WeaponErrors.AUTHORIZATION_INVALID,
            "Weapon destruction authorization is not configured", nil, context.correlationId)
    end
    local called, decision = pcall(function()
        return exports["feather-core"]:Authorize(settings.destroyAction, {
            source = context.actorSource,
            correlationId = context.correlationId,
            subject = {
                operation = "destroy",
                itemInstanceId = item.id,
                serialNumber = item.metadata and item.metadata.serialNumber
            }
        })
    end)
    if not called or type(decision) ~= "table" or decision.ok ~= true
        or type(decision.value) ~= "table" or decision.value.allowed ~= true then
        return WeaponResult.Error(WeaponErrors.AUTHORIZATION_INVALID,
            "This character is not authorized to destroy weapons", nil, context.correlationId)
    end
    return WeaponResult.Ok(true, context.correlationId)
end

function WeaponOwnershipService.Destroy(context, request, invokingResource)
    context = type(context) == "table" and context or {}
    request = type(request) == "table" and request or {}
    local trusted = (Config.Ownership or {}).trustedResources or {}
    if trusted[invokingResource] ~= true then
        return WeaponResult.Error(WeaponErrors.AUTHORIZATION_INVALID,
            "Calling resource is not trusted for weapon destruction", nil, context.correlationId)
    end

    local characterId = CoreAdapter.NormalizeCharacterId(request.characterId or context.characterId)
    local itemInstanceId = tonumber(request.itemInstanceId)
    local expectedSerial = CleanText(request.serialNumber, 128)
    if not characterId or not itemInstanceId or not expectedSerial then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID,
            "Character, item instance, and expected serial are required", nil, context.correlationId)
    end

    context.characterId = characterId
    context.actorCharacterId = CoreAdapter.NormalizeCharacterId(context.actorCharacterId)
    context.reason = CleanText(context.reason or "weapon_destruction", 64)
    context.resource = invokingResource
    local itemResult = InventoryAdapter.GetItemForCharacter(context, itemInstanceId)
    if not itemResult.ok then return itemResult end
    local item = itemResult.value
    local definitionId = item.metadata and item.metadata.weaponDefinitionId
    local definition = DefinitionRegistry.Get("weapon", definitionId)
    if not definition.ok then return definition end
    local valid = WeaponMetadata.Validate(item.metadata, definition.value, context.correlationId)
    if not valid.ok then return valid end
    if item.metadata.serialNumber ~= expectedSerial then
        return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
            "Weapon serial changed before destruction", {
                expectedSerial = expectedSerial,
                actualSerial = item.metadata.serialNumber
            }, context.correlationId)
    end
    local activeSource, activeSlot = WeaponRuntime.FindLeaseByItem(itemInstanceId)
    if activeSource then
        return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
            "Unequip the weapon before destroying it", {
                source = activeSource,
                slot = activeSlot
            }, context.correlationId)
    end
    local allowed, reason = WeaponOwnershipService.EvaluateAdministrativeHold(item.metadata)
    if not allowed then
        return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT, reason, nil, context.correlationId)
    end
    local authorized = AuthorizeDestruction(context, item)
    if not authorized.ok then return authorized end

    local destroyed = InventoryAdapter.DestroyInstance(context, item)
    if not destroyed.ok then return destroyed end
    local fact = {
        operation = "destroy",
        transitionType = "destruction",
        outcome = "committed",
        itemInstanceId = item.id,
        definitionId = definitionId,
        serialNumber = item.metadata.serialNumber,
        revision = item.metadataRevision,
        fromInventoryId = item.inventoryId,
        fromCharacterId = characterId,
        actorSource = context.actorSource,
        actorCharacterId = context.actorCharacterId,
        reason = context.reason,
        resource = context.resource,
        correlationId = context.correlationId,
        occurredAt = os.time()
    }
    RecordCommittedFact(fact)
    return WeaponResult.Ok(fact, context.correlationId)
end

function WeaponOwnershipService.CheckDestructionContract()
    local trusted = (Config.Ownership or {}).trustedResources or {}
    local authorization = (Config.Ownership or {}).authorization or {}
    local untrusted = WeaponOwnershipService.Destroy({}, {}, "untrusted-smoke-resource")
    local incomplete = WeaponOwnershipService.Destroy({}, {}, "feather-weapons")
    return {
        serviceAvailable = type(WeaponOwnershipService.Destroy) == "function",
        trustedCallerConfigured = trusted["feather-weapons"] == true,
        authorizationConfigured = authorization.enabled ~= true
            or (type(authorization.destroyAction) == "string"
                and authorization.destroyAction ~= ""),
        untrustedRejected = untrusted.ok == false
            and untrusted.error and untrusted.error.code == WeaponErrors.AUTHORIZATION_INVALID,
        incompleteRejected = incomplete.ok == false
            and incomplete.error and incomplete.error.code == WeaponErrors.ITEM_INVALID
    }
end

AddEventHandler("Feather:Inventory:ItemMoved", function(payload)
    WeaponOwnershipService.HandleCommittedMove(payload)
end)
