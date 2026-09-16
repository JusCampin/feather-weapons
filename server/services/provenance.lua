WeaponProvenanceService = {}

local ready = false
local recoverableIssuanceIds = {}

local function Clean(value, maximum)
    if value == nil then return nil end
    value = tostring(value)
    if value == '' then return nil end
    return value:sub(1, maximum)
end

local function Trusted(resource)
    return type(resource) == 'string'
        and ((Config.Ownership or {}).trustedResources or {})[resource] == true
end

function WeaponProvenanceService.Start()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `feather_weapon_events` (
          `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `item_instance_id` BIGINT UNSIGNED NOT NULL,
          `serial_number` VARCHAR(128) NOT NULL,
          `definition_id` VARCHAR(64) NOT NULL,
          `event_type` VARCHAR(48) NOT NULL,
          `operation` VARCHAR(48) NOT NULL,
          `actor_character_id` CHAR(36) NULL,
          `from_character_id` CHAR(36) NULL,
          `to_character_id` CHAR(36) NULL,
          `from_inventory_id` BIGINT UNSIGNED NULL,
          `to_inventory_id` BIGINT UNSIGNED NULL,
          `reason` VARCHAR(64) NULL,
          `resource` VARCHAR(64) NOT NULL,
          `correlation_id` VARCHAR(128) NULL,
          `snapshot` LONGTEXT NOT NULL,
          `occurred_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          KEY `idx_weapon_events_item` (`item_instance_id`,`id`),
          KEY `idx_weapon_events_serial` (`serial_number`,`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `feather_weapon_issuance_requests` (
          `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `resource` VARCHAR(64) NOT NULL,
          `request_id` VARCHAR(128) NOT NULL,
          `purpose` VARCHAR(48) NOT NULL,
          `character_id` CHAR(36) NULL,
          `definition_id` VARCHAR(64) NULL,
          `status` VARCHAR(16) NOT NULL,
          `item_instance_id` BIGINT UNSIGNED NULL,
          `serial_number` VARCHAR(128) NULL,
          `result_json` LONGTEXT NULL,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `uq_weapon_issuance_request` (`resource`,`request_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    for _, column in ipairs({
        { name = 'character_id', sql = 'ADD COLUMN `character_id` CHAR(36) NULL AFTER `purpose`' },
        { name = 'definition_id', sql = 'ADD COLUMN `definition_id` VARCHAR(64) NULL AFTER `character_id`' }
    }) do
        local found = MySQL.query.await('SHOW COLUMNS FROM `feather_weapon_issuance_requests` LIKE ?',
            { column.name }) or {}
        if not found[1] then
            MySQL.query.await(('ALTER TABLE `feather_weapon_issuance_requests` %s'):format(column.sql))
        end
    end
    recoverableIssuanceIds = {}
    local pending = MySQL.query.await([[SELECT `id` FROM `feather_weapon_issuance_requests`
        WHERE `status`='pending']]) or {}
    for _, row in ipairs(pending) do
        local id = tonumber(row.id)
        if id then recoverableIssuanceIds[id] = true end
    end
    ready = true
    return WeaponResult.Ok(true)
end

function WeaponProvenanceService.Record(fact)
    if not ready or type(fact) ~= 'table' then
        return WeaponResult.Error(WeaponErrors.DEPENDENCY_UNAVAILABLE,
            'Weapon provenance ledger is unavailable', nil, fact and fact.correlationId)
    end
    local itemId = tonumber(fact.itemInstanceId)
    local serial = Clean(fact.serialNumber, 128)
    local definitionId = Clean(fact.definitionId, 64)
    local eventType = Clean(fact.transitionType or fact.eventType, 48)
    local operation = Clean(fact.operation, 48)
    if not itemId or not serial or not definitionId or not eventType or not operation then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID,
            'Weapon provenance fact is incomplete', nil, fact.correlationId)
    end
    local id = MySQL.insert.await([[
        INSERT INTO `feather_weapon_events`
        (`item_instance_id`,`serial_number`,`definition_id`,`event_type`,`operation`,
         `actor_character_id`,`from_character_id`,`to_character_id`,
         `from_inventory_id`,`to_inventory_id`,`reason`,`resource`,`correlation_id`,`snapshot`,`occurred_at`)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,FROM_UNIXTIME(?))
    ]], {
        itemId, serial, definitionId, eventType, operation,
        CoreAdapter.NormalizeCharacterId(fact.actorCharacterId),
        CoreAdapter.NormalizeCharacterId(fact.fromCharacterId),
        CoreAdapter.NormalizeCharacterId(fact.toCharacterId),
        tonumber(fact.fromInventoryId), tonumber(fact.toInventoryId),
        Clean(fact.reason, 64), Clean(fact.resource or 'feather-weapons', 64),
        Clean(fact.correlationId, 128), json.encode(fact), tonumber(fact.occurredAt) or os.time()
    })
    if not id then
        return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
            'Weapon provenance event could not be persisted', nil, fact.correlationId)
    end
    return WeaponResult.Ok({ eventId = id }, fact.correlationId)
end

function WeaponProvenanceService.Inspect(request, context, invokingResource)
    request = type(request) == 'table' and request or {}
    context = type(context) == 'table' and context or {}
    if not Trusted(invokingResource) then
        return WeaponResult.Error(WeaponErrors.AUTHORIZATION_INVALID,
            'Calling resource is not trusted for weapon inspection', nil, context.correlationId)
    end
    local itemId = tonumber(request.itemInstanceId)
    local serial = Clean(request.serialNumber, 128)
    if not itemId and not serial then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID,
            'Item instance ID or serial number is required', nil, context.correlationId)
    end
    local maximum = math.max(1, math.min(500,
        math.floor(tonumber((Config.Provenance or {}).maxInspectionEvents) or 100)))
    local limit = math.max(1, math.min(maximum, math.floor(tonumber(request.limit) or 50)))
    local rows
    if itemId then
        rows = MySQL.query.await([[SELECT * FROM `feather_weapon_events`
            WHERE `item_instance_id`=? ORDER BY `id` DESC LIMIT ?]], { itemId, limit }) or {}
    else
        rows = MySQL.query.await([[SELECT * FROM `feather_weapon_events`
            WHERE `serial_number`=? ORDER BY `id` DESC LIMIT ?]], { serial, limit }) or {}
        itemId = rows[1] and tonumber(rows[1].item_instance_id) or nil
    end
    local current = itemId and InventoryAdapter.GetInstance(context, itemId) or nil
    return WeaponResult.Ok({
        itemInstanceId = itemId,
        serialNumber = serial or (rows[1] and rows[1].serial_number),
        current = current and current.ok and current.value or nil,
        destroyed = #rows > 0 and rows[1].event_type == 'destruction',
        events = rows
    }, context.correlationId)
end

function WeaponProvenanceService.IsReady() return ready end

function WeaponProvenanceService.BeginIssuance(resource, requestId, purpose, characterId, definitionId, correlationId)
    resource, requestId = Clean(resource, 64), Clean(requestId, 128)
    purpose = Clean(purpose, 48) or 'issued'
    characterId = CoreAdapter.NormalizeCharacterId(characterId)
    definitionId = Clean(definitionId, 64)
    if not ready or not resource or not requestId or not characterId or not definitionId then
        return WeaponResult.Error(WeaponErrors.ITEM_INVALID,
            'A durable issuance request identity is required', nil, correlationId)
    end
    local inserted = MySQL.insert.await([[INSERT IGNORE INTO `feather_weapon_issuance_requests`
        (`resource`,`request_id`,`purpose`,`character_id`,`definition_id`,`status`)
        VALUES (?,?,?,?,?,'pending')]],
        { resource, requestId, purpose, characterId, definitionId })
    if inserted and tonumber(inserted) and tonumber(inserted) > 0 then
        return WeaponResult.Ok({ reservationId = tonumber(inserted), replayed = false }, correlationId)
    end
    local rows = MySQL.query.await([[SELECT * FROM `feather_weapon_issuance_requests`
        WHERE `resource`=? AND `request_id`=? LIMIT 1]], { resource, requestId }) or {}
    local row = rows[1]
    if row and (row.purpose ~= purpose or row.character_id ~= characterId
        or row.definition_id ~= definitionId) then
        return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
            'Issuance request ID was already used for a different payload', {
                resource = resource, requestId = requestId
            }, correlationId)
    end
    if row and row.status == 'committed' and row.result_json then
        local ok, value = pcall(json.decode, row.result_json)
        if ok and type(value) == 'table' then
            value.replayed = true
            return WeaponResult.Ok(value, correlationId)
        end
    end
    if row and row.status == 'pending' then
        local reservationId = tonumber(row.id)
        if not recoverableIssuanceIds[reservationId] then
            return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
                'Weapon issuance request is already pending', {
                    resource = resource, requestId = requestId
                }, correlationId)
        end
        return WeaponResult.Ok({
            reservationId = reservationId,
            replayed = false,
            pending = true
        }, correlationId)
    end
    return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
        'Weapon issuance request could not be resumed',
        { resource = resource, requestId = requestId, status = row and row.status or nil }, correlationId)
end

function WeaponProvenanceService.MarkIssuanceInterrupted(reservationId)
    if Config.DevMode and tonumber(reservationId) then
        recoverableIssuanceIds[tonumber(reservationId)] = true
    end
end

function WeaponProvenanceService.FindIssuanceEvent(itemInstanceId, correlationId)
    local rows = MySQL.query.await([[SELECT `id` FROM `feather_weapon_events`
        WHERE `item_instance_id`=? AND `event_type`='issuance'
        ORDER BY `id` ASC LIMIT 1]], { tonumber(itemInstanceId) }) or {}
    return WeaponResult.Ok({ eventId = rows[1] and tonumber(rows[1].id) or nil }, correlationId)
end

function WeaponProvenanceService.CommitIssuance(reservationId, value, correlationId)
    local changed = MySQL.update.await([[UPDATE `feather_weapon_issuance_requests`
        SET `status`='committed',`item_instance_id`=?,`serial_number`=?,`result_json`=?
        WHERE `id`=? AND `status`='pending']],
        { value.itemInstanceId, value.serialNumber, json.encode(value), tonumber(reservationId) })
    if tonumber(changed) ~= 1 then
        return WeaponResult.Error(WeaponErrors.OPERATION_CONFLICT,
            'Issuance request could not be committed', nil, correlationId)
    end
    recoverableIssuanceIds[tonumber(reservationId)] = nil
    return WeaponResult.Ok(true, correlationId)
end

function WeaponProvenanceService.CancelIssuance(reservationId)
    if reservationId then
        recoverableIssuanceIds[tonumber(reservationId)] = nil
        MySQL.update.await([[DELETE FROM `feather_weapon_issuance_requests`
            WHERE `id`=? AND `status`='pending']], { tonumber(reservationId) })
    end
end

function WeaponProvenanceService.CheckContract()
    local untrusted = WeaponProvenanceService.Inspect({ itemInstanceId = 1 }, {}, 'untrusted-smoke-resource')
    local incomplete = WeaponProvenanceService.Inspect({}, {}, 'feather-weapons')
    return {
        ready = ready,
        trustedResourceConfigured = Trusted('feather-weapons'),
        untrustedRejected = untrusted.ok == false and untrusted.error
            and untrusted.error.code == WeaponErrors.AUTHORIZATION_INVALID,
        incompleteRejected = incomplete.ok == false and incomplete.error
            and incomplete.error.code == WeaponErrors.ITEM_INVALID,
        boundedInspection = tonumber((Config.Provenance or {}).maxInspectionEvents) ~= nil
            and tonumber(Config.Provenance.maxInspectionEvents) >= 1
            and tonumber(Config.Provenance.maxInspectionEvents) <= 500,
        retentionConfigured = tonumber((Config.Provenance or {}).retentionDays) ~= nil
            and tonumber(Config.Provenance.retentionDays) >= 0
    }
end
