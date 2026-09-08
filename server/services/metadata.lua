WeaponMetadata = {}

local function NormalizeMaintenance(value)
    value = type(value) == "table" and value or {}
    local function Unit(number)
        return math.max(0.0, math.min(1.0, tonumber(number) or 0.0))
    end
    return {
        degradation = Unit(value.degradation),
        permanentDegradation = Unit(value.permanentDegradation),
        damage = Unit(value.damage),
        dirt = Unit(value.dirt),
        soot = Unit(value.soot)
    }
end

function WeaponMetadata.Build(definition, options)
    options = type(options) == "table" and options or {}
    local metadata = {
        schemaVersion = WeaponConstants.MetadataSchemaVersion,
        weaponDefinitionId = definition.id,
        serialNumber = options.serialNumber,
        condition = tonumber(options.condition) or definition.condition.maximum,
        maintenance = NormalizeMaintenance(options.maintenance),
        quality = tonumber(options.quality) or 100,
        ammo = {
            type = options.ammunitionType or definition.ammunitionType,
            loaded = tonumber(options.loadedAmmo) or 0,
            reserve = tonumber(options.reserveAmmo) or 0,
            chambered = options.chambered == true
        },
        attachments = options.attachments or {},
        cosmetics = options.cosmetics or {},
        flags = {
            stolen = options.stolen == true,
            evidence = options.evidence == true,
            disabled = options.disabled == true
        },
        provenance = options.provenance or {}
    }

    local valid, errors = WeaponValidation.Metadata(metadata, definition)
    if not valid then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID, "Generated weapon metadata is invalid", errors)
    end
    local attachments = DefinitionRegistry.ValidateAttachmentSet(definition.id, metadata.attachments)
    if not attachments.ok then return attachments end
    return WeaponResult.Ok(metadata)
end

function WeaponMetadata.Validate(metadata, definition, correlationId)
    if type(metadata) == "table" and type(metadata.ammo) == "table"
        and metadata.ammo.reserve == nil then
        metadata.ammo.reserve = 0
    end
    if type(metadata) == "table" and metadata.maintenance ~= nil then
        metadata.maintenance = NormalizeMaintenance(metadata.maintenance)
    end
    local valid, errors = WeaponValidation.Metadata(metadata, definition)
    if not valid then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID, "Weapon item metadata is invalid", errors, correlationId)
    end
    local attachments = DefinitionRegistry.ValidateAttachmentSet(definition.id, metadata.attachments)
    if not attachments.ok then
        attachments.correlationId = correlationId
        return attachments
    end
    return WeaponResult.Ok(metadata, correlationId)
end
