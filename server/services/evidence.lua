WeaponEvidenceService = {}

local function Trusted(resource)
    return type(resource) == 'string'
        and ((Config.Ownership or {}).trustedResources or {})[resource] == true
end

local function Authorize(context, operation, item)
    local settings = (Config.Ownership or {}).authorization or {}
    if settings.enabled ~= true then return WeaponResult.Ok(true, context.correlationId) end
    local action = operation == 'hold' and settings.holdAction or settings.releaseAction
    if not context.actorSource or type(action) ~= 'string' or action == '' then
        return WeaponResult.Error(WeaponErrors.AUTHORIZATION_INVALID,
            'Evidence authorization is not configured', nil, context.correlationId)
    end
    local ok, result = pcall(function()
        return exports['feather-core']:Authorize(action, {
            source = context.actorSource, correlationId = context.correlationId,
            subject = { operation = operation, itemInstanceId = item.id,
                serialNumber = item.metadata.serialNumber }
        })
    end)
    if not ok or type(result) ~= 'table' or not result.ok
        or type(result.value) ~= 'table' or result.value.allowed ~= true then
        return WeaponResult.Error(WeaponErrors.AUTHORIZATION_INVALID,
            'This character is not authorized for evidence operations', nil, context.correlationId)
    end
    return WeaponResult.Ok(true, context.correlationId)
end

function WeaponEvidenceService.SetHold(context, request, invokingResource, held)
    context = type(context) == 'table' and context or {}
    request = type(request) == 'table' and request or {}
    if not Trusted(invokingResource) then
        return WeaponResult.Error(WeaponErrors.AUTHORIZATION_INVALID,
            'Calling resource is not trusted for evidence operations', nil, context.correlationId)
    end
    local characterId = CoreAdapter.NormalizeCharacterId(request.characterId or context.characterId)
    local itemId, serial = tonumber(request.itemInstanceId), tostring(request.serialNumber or '')
    if not characterId or not itemId or serial == '' then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID,
            'Character, item instance, and expected serial are required', nil, context.correlationId)
    end
    if WeaponRuntime.FindLeaseByItem(itemId) then
        return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
            'Unequip the weapon before changing its evidence state', nil, context.correlationId)
    end
    context.characterId, context.resource = characterId, invokingResource
    context.reason = held and 'evidence_hold' or 'evidence_release'
    local committed = InventoryAdapter.Transaction(context, function(tx)
        local item = tx:GetItemForUpdate(itemId)
        if not item then return WeaponResult.Error(WeaponErrors.ITEM_NOT_OWNED,
            'Weapon is not owned by the target character', nil, context.correlationId) end
        local definition = DefinitionRegistry.Get('weapon', item.metadata and item.metadata.weaponDefinitionId)
        if not definition.ok then return definition end
        local valid = WeaponMetadata.Validate(item.metadata, definition.value, context.correlationId)
        if not valid.ok then return valid end
        if item.metadata.serialNumber ~= serial then
            return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
                'Weapon serial changed before evidence mutation', nil, context.correlationId)
        end
        if item.metadata.flags.evidence == held then
            return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
                held and 'Weapon is already held as evidence' or 'Weapon is not held as evidence',
                nil, context.correlationId)
        end
        local authorized = Authorize(context, held and 'hold' or 'release', item)
        if not authorized.ok then return authorized end
        local metadata = json.decode(json.encode(item.metadata))
        metadata.flags.evidence = held
        if not tx:SetMetadata(item.id, metadata, item.metadataRevision) then
            return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
                'Weapon metadata changed during evidence mutation', nil, context.correlationId)
        end
        return { item = item, metadata = metadata, definitionId = definition.value.id }
    end)
    if not committed.ok then return committed end
    local value = committed.value
    local fact = {
        operation = held and 'evidence_hold' or 'evidence_release',
        transitionType = held and 'evidence_hold' or 'evidence_release', outcome = 'committed',
        itemInstanceId = itemId, definitionId = value.definitionId, serialNumber = serial,
        revision = tonumber(value.item.metadataRevision) + 1,
        fromInventoryId = value.item.inventoryId, toInventoryId = value.item.inventoryId,
        fromCharacterId = characterId, toCharacterId = characterId,
        actorSource = context.actorSource, actorCharacterId = context.actorCharacterId,
        reason = context.reason, resource = invokingResource,
        correlationId = context.correlationId, occurredAt = os.time(), metadata = value.metadata
    }
    local recorded = WeaponProvenanceService.Record(fact)
    if not recorded.ok then return recorded end
    fact.eventId = recorded.value.eventId
    TriggerEvent('Feather:Weapons:EvidenceStateCommitted', fact)
    return WeaponResult.Ok(fact, context.correlationId)
end

function WeaponEvidenceService.Hold(context, request, resource)
    return WeaponEvidenceService.SetHold(context, request, resource, true)
end

function WeaponEvidenceService.Release(context, request, resource)
    return WeaponEvidenceService.SetHold(context, request, resource, false)
end

function WeaponEvidenceService.CheckContract()
    local untrusted = WeaponEvidenceService.Hold({}, {}, 'untrusted-smoke-resource')
    local incomplete = WeaponEvidenceService.Hold({}, {}, 'feather-weapons')
    local authorization = (Config.Ownership or {}).authorization or {}
    return {
        serviceAvailable = type(WeaponEvidenceService.Hold) == 'function'
            and type(WeaponEvidenceService.Release) == 'function',
        trustedCallerConfigured = ((Config.Ownership or {}).trustedResources or {})['feather-weapons'] == true,
        authorizationConfigured = authorization.enabled ~= true
            or (type(authorization.holdAction) == 'string' and authorization.holdAction ~= ''
                and type(authorization.releaseAction) == 'string' and authorization.releaseAction ~= ''),
        untrustedRejected = not untrusted.ok and untrusted.error
            and untrusted.error.code == WeaponErrors.AUTHORIZATION_INVALID,
        incompleteRejected = not incomplete.ok and incomplete.error
            and incomplete.error.code == WeaponErrors.ITEM_INVALID
    }
end
