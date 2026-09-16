IssuanceService = {}

local serialCounter = 0
local reservedSerials = {}

local function CleanText(value, maximum)
    if value == nil then return nil end
    value = tostring(value)
    if value == "" then return nil end
    return value:sub(1, maximum)
end

local function ValidateRequestId(value)
    if type(value) ~= "string" or #value < 1 or #value > 128 then return nil end
    if not value:match("^[A-Za-z0-9][A-Za-z0-9._:%-]*$") then return nil end
    return value
end

local function NextSerial(definition)
    local family = tostring(definition.family or "weapon"):upper():gsub("[^A-Z0-9]", ""):sub(1, 4)
    if family == "" then family = "WPN" end
    for _ = 1, 16 do
        serialCounter = (serialCounter + 1) % 0x10000
        local serial = ("FW-%s-%08X-%06X-%04X"):format(
            family, os.time(), math.random(0, 0xFFFFFF), serialCounter)
        if not reservedSerials[serial] then
            reservedSerials[serial] = true
            return serial
        end
    end
    return nil
end

local function BuildProvenance(context, request)
    local supplied = type(request.provenance) == "table" and request.provenance or {}
    return {
        type = CleanText(supplied.type or context.reason or "issued", 48),
        reference = CleanText(supplied.reference, 128),
        resource = CleanText(context.resource or "feather-weapons", 64),
        issuedBySource = tonumber(context.actorSource),
        issuedByCharacterId = CoreAdapter.NormalizeCharacterId(context.actorCharacterId),
        issuedToCharacterId = CoreAdapter.NormalizeCharacterId(context.characterId),
        createdAt = os.time()
    }
end

local function Authorize(context, definitionId, purpose)
    local settings = Config.Issuance or {}
    if (settings.trustedResources or {})[context.resource] ~= true then
        return WeaponResult.Error(WeaponErrors.AUTHORIZATION_INVALID,
            "Calling resource is not trusted for weapon issuance", nil, context.correlationId)
    end
    if (settings.allowedPurposes or {})[purpose] ~= true then
        return WeaponResult.Error(WeaponErrors.AUTHORIZATION_INVALID,
            "Weapon issuance purpose is not allowed", { purpose = purpose }, context.correlationId)
    end
    local authorization = settings.authorization or {}
    if authorization.enabled ~= true then return WeaponResult.Ok(true, context.correlationId) end
    if not context.actorSource or type(authorization.action) ~= "string" or authorization.action == "" then
        return WeaponResult.Error(WeaponErrors.AUTHORIZATION_INVALID,
            "Weapon issuance authorization is not configured", nil, context.correlationId)
    end
    local called, decision = pcall(function()
        return exports["feather-core"]:Authorize(authorization.action, {
            source = context.actorSource, correlationId = context.correlationId,
            subject = { operation = "issue", purpose = purpose,
                definitionId = definitionId, characterId = context.characterId }
        })
    end)
    if not called or type(decision) ~= "table" or not decision.ok
        or type(decision.value) ~= "table" or decision.value.allowed ~= true then
        return WeaponResult.Error(WeaponErrors.AUTHORIZATION_INVALID,
            "This character is not authorized to issue weapons", nil, context.correlationId)
    end
    return WeaponResult.Ok(true, context.correlationId)
end

local function BuildIssuedValue(item, definition, characterId)
    return {
        itemInstanceId = tonumber(item.id),
        inventoryId = tonumber(item.inventoryId),
        revision = tonumber(item.metadataRevision),
        characterId = characterId,
        definitionId = definition.id,
        itemName = definition.itemName,
        serialNumber = item.metadata.serialNumber,
        metadata = item.metadata
    }
end

local function RecordIssuance(value, context, recovered)
    local existing = WeaponProvenanceService.FindIssuanceEvent(
        value.itemInstanceId, context.correlationId)
    if existing.ok and existing.value.eventId then
        value.provenanceEventId = existing.value.eventId
        return existing
    end
    local recorded = WeaponProvenanceService.Record({
        operation = 'issue', transitionType = 'issuance', outcome = 'committed',
        itemInstanceId = value.itemInstanceId, definitionId = value.definitionId,
        serialNumber = value.serialNumber, revision = value.revision,
        toInventoryId = value.inventoryId, toCharacterId = value.characterId,
        actorSource = context.actorSource, actorCharacterId = context.actorCharacterId,
        reason = context.reason, resource = context.resource,
        correlationId = context.correlationId, occurredAt = os.time(),
        metadata = value.metadata, recovered = recovered == true
    })
    value.provenanceEventId = recorded.ok and recorded.value.eventId or nil
    return recorded
end

local function RecoverPending(context, requestId, definition, characterId, reservationId)
    local listed = InventoryAdapter.ListWeaponsForCharacter({
        characterId = characterId, correlationId = context.correlationId
    })
    if not listed.ok then return listed end
    local matches = {}
    for _, item in ipairs(listed.value or {}) do
        local metadata = type(item.metadata) == 'table' and item.metadata or {}
        local provenance = type(metadata.provenance) == 'table' and metadata.provenance or {}
        if metadata.weaponDefinitionId == definition.id
            and provenance.resource == context.resource
            and provenance.reference == requestId
            and CoreAdapter.NormalizeCharacterId(provenance.issuedToCharacterId) == characterId then
            matches[#matches + 1] = item
        end
    end
    if #matches ~= 1 then
        return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
            'Pending issuance could not be recovered unambiguously', {
                requestId = requestId, matches = #matches
            }, context.correlationId)
    end
    local valid = WeaponMetadata.Validate(matches[1].metadata, definition, context.correlationId)
    if not valid.ok then return valid end
    local value = BuildIssuedValue(matches[1], definition, characterId)
    local recorded = RecordIssuance(value, context, true)
    if not recorded.ok then return recorded end
    local committed = WeaponProvenanceService.CommitIssuance(
        reservationId, value, context.correlationId)
    if not committed.ok then
        local replay = WeaponProvenanceService.BeginIssuance(context.resource, requestId,
            context.reason, characterId, definition.id, context.correlationId)
        if replay.ok and replay.value.replayed == true then
            replay.value.recovered = true
            return WeaponResult.Ok(replay.value, context.correlationId)
        end
        return committed
    end
    value.replayed = true
    value.recovered = true
    return WeaponResult.Ok(value, context.correlationId)
end

function IssuanceService.Issue(context, request, invokingResource)
    context = type(context) == "table" and context or {}
    request = type(request) == "table" and request or {}
    local characterId = CoreAdapter.NormalizeCharacterId(request.characterId or context.characterId)
    local definitionId = CleanText(request.definitionId, 64)
    local purpose = CleanText(request.purpose or context.reason or "issued", 48)
    if not characterId or not definitionId then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID,
            "A target character and weapon definition are required", nil, context.correlationId)
    end

    local definitionResult = DefinitionRegistry.Get("weapon", definitionId)
    if not definitionResult.ok then return definitionResult end
    local definition = definitionResult.value
    context.characterId = characterId
    context.reason = purpose
    context.resource = CleanText(invokingResource or context.resource, 64)
    local authorized = Authorize(context, definitionId, purpose)
    if not authorized.ok then return authorized end
    local requestId = ValidateRequestId(request.requestId)
    if request.requestId ~= nil and not requestId then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID,
            "requestId must be 1-128 characters using letters, numbers, dot, underscore, colon, or hyphen",
            nil, context.correlationId)
    end
    if purpose ~= "development_grant" and not requestId then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID,
            "A stable requestId is required for this issuance purpose", nil, context.correlationId)
    end
    local reservationId
    if requestId then
        local begun = WeaponProvenanceService.BeginIssuance(context.resource, requestId, purpose,
            characterId, definitionId, context.correlationId)
        if not begun.ok then return begun end
        if begun.value.replayed == true then return WeaponResult.Ok(begun.value, context.correlationId) end
        reservationId = begun.value.reservationId
        if begun.value.pending == true then
            return RecoverPending(context, requestId, definition, characterId, reservationId)
        end
    end
    local function CancelReservation()
        if reservationId then WeaponProvenanceService.CancelIssuance(reservationId) end
    end
    local serialNumber = NextSerial(definition)
    if not serialNumber then
        CancelReservation()
        return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
            "A unique weapon serial could not be generated", nil, context.correlationId)
    end

    context.correlationId = context.correlationId
        or ("issue:%s:%s:%s"):format(tostring(characterId), tostring(GetGameTimer()), tostring(serialCounter))

    local metadataResult = WeaponMetadata.Build(definition, {
        serialNumber = serialNumber,
        condition = request.condition,
        quality = request.quality,
        loadedAmmo = 0,
        chambered = false,
        provenance = BuildProvenance(context, request)
    })
    if not metadataResult.ok then
        reservedSerials[serialNumber] = nil
        CancelReservation()
        return metadataResult
    end

    local created = InventoryAdapter.CreateWeapon(context, definition, metadataResult.value)
    if not created.ok then
        reservedSerials[serialNumber] = nil
        CancelReservation()
        return created
    end

    local value = BuildIssuedValue({
        id = created.value.instanceId, inventoryId = created.value.inventoryId,
        metadataRevision = created.value.revision, metadata = metadataResult.value
    }, definition, characterId)
    local recorded = RecordIssuance(value, context, false)
    if not recorded.ok then
        print(('[feather-weapons] CRITICAL issuance provenance failed item=%s serial=%s'):format(
            tostring(value.itemInstanceId), tostring(serialNumber)))
    end
    if Config.DevMode and context.resource == 'feather-weapons'
        and context.failureInjection == 'after_create' then
        WeaponProvenanceService.MarkIssuanceInterrupted(reservationId)
        return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
            'Injected failure after weapon creation', {
                itemInstanceId = value.itemInstanceId, serialNumber = value.serialNumber
            }, context.correlationId)
    end
    if reservationId then
        local committed = WeaponProvenanceService.CommitIssuance(reservationId, value, context.correlationId)
        if not committed.ok then return committed end
    end
    return WeaponResult.Ok(value, context.correlationId)
end

function IssuanceService.CheckContract()
    local untrusted = IssuanceService.Issue({ reason = "development_grant" }, {
        characterId = "00000000-0000-0000-0000-000000000001",
        definitionId = "revolver_cattleman", purpose = "development_grant"
    }, "untrusted-smoke-resource")
    local incomplete = IssuanceService.Issue({ reason = "development_grant" }, {}, "feather-weapons")
    local missingRequestId = IssuanceService.Issue({ reason = "purchase" }, {
        characterId = "00000000-0000-0000-0000-000000000001",
        definitionId = "revolver_cattleman", purpose = "purchase"
    }, "feather-weapons")
    local oversizedRequestId = IssuanceService.Issue({ reason = "purchase" }, {
        characterId = "00000000-0000-0000-0000-000000000001",
        definitionId = "revolver_cattleman", purpose = "purchase",
        requestId = string.rep("a", 129)
    }, "feather-weapons")
    local malformedRequestId = IssuanceService.Issue({ reason = "purchase" }, {
        characterId = "00000000-0000-0000-0000-000000000001",
        definitionId = "revolver_cattleman", purpose = "purchase",
        requestId = "invalid request id"
    }, "feather-weapons")
    local settings, authorization = Config.Issuance or {}, (Config.Issuance or {}).authorization or {}
    return {
        serviceAvailable = type(IssuanceService.Issue) == "function",
        trustedCallerConfigured = (settings.trustedResources or {})["feather-weapons"] == true,
        purposeConfigured = (settings.allowedPurposes or {}).development_grant == true,
        authorizationConfigured = authorization.enabled ~= true
            or (type(authorization.action) == "string" and authorization.action ~= ""),
        untrustedRejected = not untrusted.ok and untrusted.error
            and untrusted.error.code == WeaponErrors.AUTHORIZATION_INVALID,
        incompleteRejected = not incomplete.ok and incomplete.error
            and incomplete.error.code == WeaponErrors.ITEM_INVALID,
        requestIdRequired = not missingRequestId.ok and missingRequestId.error
            and missingRequestId.error.code == WeaponErrors.ITEM_INVALID,
        oversizedRequestIdRejected = not oversizedRequestId.ok and oversizedRequestId.error
            and oversizedRequestId.error.code == WeaponErrors.ITEM_INVALID,
        malformedRequestIdRejected = not malformedRequestId.ok and malformedRequestId.error
            and malformedRequestId.error.code == WeaponErrors.ITEM_INVALID
    }
end
