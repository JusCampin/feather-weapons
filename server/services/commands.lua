local function Notify(source, message, duration)
    local result = exports["feather-core"]:SendNotification({
        source = source,
        style = "right",
        message = message,
        duration = duration
    })
    if not result or result.ok ~= true then
        print(("[feather-weapons] notification failed source=%s code=%s")
            :format(tostring(source), tostring(result and result.code or "invalid_result")))
    end
end

RegisterCommand("WeaponCharacterIdentitySmokeTest", function(source, args)
        if source ~= 0 then return end
        local targetSource = tonumber(args and args[1])
        if not targetSource then
            local players = GetPlayers()
            targetSource = players[1] and tonumber(players[1]) or nil
        end

        local coreCapabilities = CoreAdapter.CheckCapabilities()
        local session = targetSource and CoreAdapter.ResolveSession(targetSource)
            or WeaponResult.Error(WeaponErrors.CHARACTER_REQUIRED, "No connected player is available")
        local inventoryCapabilities = InventoryAdapter.GetCapabilities()
        local expectedMode = "uuid"
        local tests = {
            { name = "core session capability", passed = coreCapabilities.ok == true },
            {
                name = "current session resolved",
                passed = session.ok == true,
                detail = targetSource and ("source=" .. tostring(targetSource)) or "no player"
            },
            {
                name = "character id accepted",
                passed = session.ok == true
                    and CoreAdapter.NormalizeCharacterId(session.value.characterId) == session.value.characterId
            },
            {
                name = "session is current",
                passed = session.ok == true
                    and CoreAdapter.IsSessionCurrent(targetSource, session.value.sessionId, session.value.characterId)
            },
            {
                name = "inventory identity mode",
                passed = type(inventoryCapabilities) == "table"
                    and type(inventoryCapabilities.characterIdentity) == "table"
                    and inventoryCapabilities.characterIdentity.uuid == true
                    and inventoryCapabilities.characterIdentity.mode == expectedMode,
                detail = "mode=" .. tostring(expectedMode)
            }
        }

        local passed = 0
        for _, test in ipairs(tests) do
            if test.passed then passed = passed + 1 end
            print(("[WeaponCharacterIdentitySmokeTest] %-27s %s%s"):format(
                test.name, test.passed and "PASS" or "FAIL",
                test.detail and ("  -- " .. test.detail) or ""))
        end
        print(("[WeaponCharacterIdentitySmokeTest] done %d/%d passed"):format(passed, #tests))
    end, true)

RegisterCommand("WeaponRuntimeLeaseSmokeTest", function(source, args)
        if source ~= 0 then return end
        local targetSource = tonumber(args and args[1])
        if not targetSource then
            local players = GetPlayers()
            targetSource = players[1] and tonumber(players[1]) or nil
        end
        local runtime = targetSource and WeaponRuntime.Get(targetSource) or nil
        local activeSlot, equipped = nil, nil
        for _, slot in ipairs({ "primary", "offhand", "shoulder", "back" }) do
            local candidate = runtime and runtime.slots and runtime.slots[slot] or nil
            if candidate then
                activeSlot, equipped = slot, candidate
                break
            end
        end
        local sessionId = runtime and runtime.sessionId or nil
        local tests = {
            { name = "active equipped lease", passed = equipped ~= nil },
            {
                name = "current lease accepted",
                passed = equipped ~= nil and WeaponRuntime.MatchesLease(
                    targetSource, sessionId, equipped.itemInstanceId, equipped.generation, activeSlot)
            },
            {
                name = "stale generation rejected",
                passed = equipped ~= nil and not WeaponRuntime.MatchesLease(
                    targetSource, sessionId, equipped.itemInstanceId,
                    (equipped.generation or 0) - 1, activeSlot)
            },
            {
                name = "foreign item rejected",
                passed = equipped ~= nil and not WeaponRuntime.MatchesLease(
                    targetSource, sessionId, "foreign-item", equipped.generation, activeSlot)
            },
            {
                name = "foreign session rejected",
                passed = equipped ~= nil and not WeaponRuntime.MatchesLease(
                    targetSource, "foreign-session", equipped.itemInstanceId,
                    equipped.generation, activeSlot)
            }
        }
        local passed = 0
        for _, test in ipairs(tests) do
            if test.passed then passed = passed + 1 end
            print(("[WeaponRuntimeLeaseSmokeTest] %-27s %s"):format(
                test.name, test.passed and "PASS" or "FAIL"))
        end
        print(("[WeaponRuntimeLeaseSmokeTest] done %d/%d passed source=%s slot=%s generation=%s"):format(
            passed, #tests, tostring(targetSource), tostring(activeSlot),
            tostring(equipped and equipped.generation)))
    end, true)

RegisterCommand("WeaponAttachmentContractSmokeTest", function(source, args)
        if source ~= 0 then return end
        local targetSource = tonumber(args and args[1])
        if not targetSource then
            local players = GetPlayers()
            targetSource = players[1] and tonumber(players[1]) or nil
        end

        local runtime = targetSource and WeaponRuntime.Get(targetSource) or nil
        local sessionId = runtime and runtime.sessionId or nil
        local activeSlots, attachmentCount = 0, 0
        local catalogValid, setsValid, identitiesValid, leasesValid = true, true, true, true

        local attachmentCatalog = DefinitionRegistry.List("attachment")
        if not attachmentCatalog.ok or #attachmentCatalog.value == 0 then
            catalogValid = false
        else
            for _, definition in ipairs(attachmentCatalog.value) do
                if type(definition.nativeComponentName) ~= "string"
                    or definition.nativeComponentName == ""
                    or type(definition.slot) ~= "string" or definition.slot == "" then
                    catalogValid = false
                end
            end
        end

        for _, slot in ipairs({ "primary", "offhand", "shoulder", "back" }) do
            local equipped = runtime and runtime.slots and runtime.slots[slot] or nil
            if equipped then
                activeSlots = activeSlots + 1
                local seenIds, seenSlots = {}, {}
                local installed = equipped.attachments or {}
                local setResult = DefinitionRegistry.ValidateAttachmentSet(equipped.definitionId, installed)
                if not setResult.ok then setsValid = false end

                for _, entry in ipairs(installed) do
                    attachmentCount = attachmentCount + 1
                    local attachmentId = entry.definitionId
                    local definitionResult = DefinitionRegistry.Get("attachment", attachmentId)
                    local definition = definitionResult.ok and definitionResult.value or nil
                    if not definition or type(definition.nativeComponentName) ~= "string"
                        or definition.nativeComponentName == "" then
                        catalogValid = false
                    end
                    if not attachmentId or seenIds[attachmentId]
                        or not entry.slot or seenSlots[entry.slot]
                        or (definition and entry.slot ~= definition.slot) then
                        identitiesValid = false
                    end
                    if attachmentId then seenIds[attachmentId] = true end
                    if entry.slot then seenSlots[entry.slot] = true end
                end

                if not targetSource or not sessionId or not WeaponRuntime.MatchesLease(
                    targetSource, sessionId, equipped.itemInstanceId, equipped.generation, slot) then
                    leasesValid = false
                end
            end
        end

        local authorization = (Config.Attachments or {}).authorization or {}
        local tests = {
            {
                name = "attachment catalog ready",
                passed = attachmentCatalog.ok == true
                    and #attachmentCatalog.value == DefinitionRegistry.Counts().attachment
                    and #attachmentCatalog.value > 0
            },
            {
                name = "runtime initialized",
                passed = runtime ~= nil and type(runtime.slots) == "table"
            },
            {
                name = "active sets valid",
                passed = setsValid
            },
            {
                name = "component mappings valid",
                passed = catalogValid
            },
            {
                name = "attachment identities valid",
                passed = identitiesValid
            },
            {
                name = "attachment leases scoped",
                passed = leasesValid
            },
            {
                name = "authorization configured",
                passed = authorization.enabled ~= true
                    or (type(authorization.action) == "string" and authorization.action ~= "")
            }
        }

        local passed = 0
        for _, test in ipairs(tests) do
            if test.passed then passed = passed + 1 end
            print(("[WeaponAttachmentContractSmokeTest] %-29s %s"):format(
                test.name, test.passed and "PASS" or "FAIL"))
        end
        print(("[WeaponAttachmentContractSmokeTest] done %d/%d passed source=%s activeSlots=%d attachments=%d")
            :format(passed, #tests, tostring(targetSource), activeSlots, attachmentCount))
    end, true)

RegisterCommand("WeaponOwnershipTransitionSmokeTest", function(source, args)
        if source ~= 0 then return end
        local expectedItem = tonumber(args and args[1])
        local diagnostics = WeaponOwnershipService.GetDiagnostics()
        local last = diagnostics.last
        local ordinaryAllowed = WeaponOwnershipService.EvaluateAdministrativeHold({
            flags = { evidence = false, disabled = false }
        })
        local evidenceAllowed = WeaponOwnershipService.EvaluateAdministrativeHold({
            flags = { evidence = true, disabled = false }
        })
        local disabledAllowed = WeaponOwnershipService.EvaluateAdministrativeHold({
            flags = { evidence = false, disabled = true }
        })
        local tests = {
            {
                name = "observer available",
                passed = type(WeaponOwnershipService.HandleCommittedMove) == "function"
            },
            {
                name = "transition observed",
                passed = diagnostics.observed > 0,
                detail = "count=" .. tostring(diagnostics.observed)
            },
            {
                name = "weapon identity present",
                passed = last ~= nil and last.itemInstanceId ~= nil
                    and type(last.definitionId) == "string"
                    and type(last.serialNumber) == "string" and last.serialNumber ~= ""
            },
            {
                name = "committed inventory move",
                passed = last ~= nil and last.outcome == "committed"
                    and last.fromInventoryId ~= nil and last.toInventoryId ~= nil
                    and last.fromInventoryId ~= last.toInventoryId
            },
            {
                name = "transition classified",
                passed = last ~= nil and last.transitionType ~= nil
                    and last.transitionType ~= "inventory_move",
                detail = last and ("type=" .. tostring(last.transitionType)) or nil
            },
            {
                name = "ground round trip classified",
                passed = (diagnostics.byType.drop or 0) > 0
                    and (diagnostics.byType.pickup or 0) > 0,
                detail = ("drop=%s pickup=%s"):format(
                    tostring(diagnostics.byType.drop or 0),
                    tostring(diagnostics.byType.pickup or 0))
            },
            {
                name = "expected item observed",
                passed = not expectedItem or (last ~= nil
                    and tonumber(last.itemInstanceId) == expectedItem),
                detail = expectedItem and ("item=" .. tostring(expectedItem)) or "not specified"
            },
            {
                name = "observations healthy",
                passed = diagnostics.failed == 0 and diagnostics.leaseViolations == 0,
                detail = ("failed=%s leaseViolations=%s"):format(
                    tostring(diagnostics.failed), tostring(diagnostics.leaseViolations))
            },
            {
                name = "ordinary movement allowed",
                passed = ordinaryAllowed == true
            },
            {
                name = "evidence movement blocked",
                passed = evidenceAllowed == false
            },
            {
                name = "disabled movement blocked",
                passed = disabledAllowed == false
            }
        }
        local passed = 0
        for _, test in ipairs(tests) do
            if test.passed then passed = passed + 1 end
            print(("[WeaponOwnershipTransitionSmokeTest] %-27s %s%s"):format(
                test.name, test.passed and "PASS" or "FAIL",
                test.detail and ("  -- " .. test.detail) or ""))
        end
        print(("[WeaponOwnershipTransitionSmokeTest] done %d/%d passed"):format(passed, #tests))
    end, true)

RegisterCommand("WeaponPlayerTransferSmokeTest", function(source, args)
        if source ~= 0 then return end
        local expectedItem = tonumber(args and args[1])
        local diagnostics = WeaponOwnershipService.GetDiagnostics()
        local last = diagnostics.last
        local tests = {
            {
                name = "transfer observed",
                passed = last ~= nil and last.transitionType == "transfer"
                    and (diagnostics.byType.transfer or 0) > 0,
                detail = "count=" .. tostring(diagnostics.byType.transfer or 0)
            },
            {
                name = "expected item transferred",
                passed = not expectedItem or (last ~= nil
                    and tonumber(last.itemInstanceId) == expectedItem),
                detail = expectedItem and ("item=" .. tostring(expectedItem)) or "not specified"
            },
            {
                name = "serial identity present",
                passed = last ~= nil and type(last.serialNumber) == "string"
                    and last.serialNumber ~= ""
            },
            {
                name = "source character resolved",
                passed = last ~= nil and last.fromCharacterId ~= nil
            },
            {
                name = "recipient character resolved",
                passed = last ~= nil and last.toCharacterId ~= nil
            },
            {
                name = "ownership changed",
                passed = last ~= nil and last.fromCharacterId ~= nil
                    and last.toCharacterId ~= nil
                    and last.fromCharacterId ~= last.toCharacterId
            },
            {
                name = "transfer observations healthy",
                passed = diagnostics.failed == 0 and diagnostics.leaseViolations == 0,
                detail = ("failed=%s leaseViolations=%s"):format(
                    tostring(diagnostics.failed), tostring(diagnostics.leaseViolations))
            }
        }
        local passed = 0
        for _, test in ipairs(tests) do
            if test.passed then passed = passed + 1 end
            print(("[WeaponPlayerTransferSmokeTest] %-29s %s%s"):format(
                test.name, test.passed and "PASS" or "FAIL",
                test.detail and ("  -- " .. test.detail) or ""))
        end
        print(("[WeaponPlayerTransferSmokeTest] done %d/%d passed"):format(passed, #tests))
    end, true)

RegisterCommand("WeaponDestructionContractSmokeTest", function(source)
        if source ~= 0 then return end
        local contract = WeaponOwnershipService.CheckDestructionContract()
        local capabilities = WeaponAPI.GetCapabilities()
        local tests = {
            { name = "destruction service available", passed = contract.serviceAvailable == true },
            { name = "trusted caller configured", passed = contract.trustedCallerConfigured == true },
            { name = "authorization configured", passed = contract.authorizationConfigured == true },
            { name = "untrusted caller rejected", passed = contract.untrustedRejected == true },
            { name = "incomplete request rejected", passed = contract.incompleteRejected == true },
            {
                name = "destruction capability ready",
                passed = capabilities.features.destruction == true
            }
        }
        local passed = 0
        for _, test in ipairs(tests) do
            if test.passed then passed = passed + 1 end
            print(("[WeaponDestructionContractSmokeTest] %-29s %s"):format(
                test.name, test.passed and "PASS" or "FAIL"))
        end
        print(("[WeaponDestructionContractSmokeTest] done %d/%d passed (read-only)")
            :format(passed, #tests))
    end, true)

RegisterCommand("WeaponDestroyTest", function(source, args)
        if source ~= 0 or Config.DevMode ~= true then return end
        local targetSource = tonumber(args and args[1])
        local itemInstanceId = tonumber(args and args[2])
        local serialNumber = args and args[3]
        local confirmation = args and args[4]
        if not targetSource or not itemInstanceId or type(serialNumber) ~= "string"
            or serialNumber == "" or confirmation ~= "DESTROY" then
            print("[WeaponDestroyTest] usage: WeaponDestroyTest <source> <itemInstanceId> <serialNumber> DESTROY")
            return
        end

        local session = CoreAdapter.ResolveSession(targetSource)
        if not session.ok then
            print(("[WeaponDestroyTest] FAIL source=%s code=%s message=%s"):format(
                tostring(targetSource), tostring(session.error and session.error.code),
                tostring(session.error and session.error.message)))
            return
        end

        local result = WeaponOwnershipService.Destroy({
            actorSource = targetSource,
            actorCharacterId = session.value.characterId,
            characterId = session.value.characterId,
            correlationId = ("destroy-smoke:%s:%s:%s"):format(
                tostring(targetSource), tostring(itemInstanceId), tostring(GetGameTimer())),
            reason = "live_destruction_smoke_test"
        }, {
            characterId = session.value.characterId,
            itemInstanceId = itemInstanceId,
            serialNumber = serialNumber
        }, "feather-weapons")
        if not result.ok then
            print(("[WeaponDestroyTest] FAIL item=%s serial=%s code=%s message=%s"):format(
                tostring(itemInstanceId), tostring(serialNumber),
                tostring(result.error and result.error.code),
                tostring(result.error and result.error.message)))
            return
        end
        print(("[WeaponDestroyTest] PASS destroyed item=%s serial=%s character=%s"):format(
            tostring(result.value.itemInstanceId), tostring(result.value.serialNumber),
            tostring(result.value.fromCharacterId)))
    end, true)

RegisterCommand("WeaponDestructionAuditSmokeTest", function(source, args)
        if source ~= 0 then return end
        local expectedItem = tonumber(args and args[1])
        local expectedSerial = args and args[2]
        local diagnostics = WeaponOwnershipService.GetDiagnostics()
        local last = diagnostics.last
        local tests = {
            {
                name = "destruction observed",
                passed = last ~= nil and last.transitionType == "destruction"
                    and (diagnostics.byType.destruction or 0) > 0
            },
            {
                name = "expected item destroyed",
                passed = expectedItem ~= nil and last ~= nil
                    and tonumber(last.itemInstanceId) == expectedItem
            },
            {
                name = "serial identity preserved",
                passed = type(expectedSerial) == "string" and expectedSerial ~= ""
                    and last ~= nil and last.serialNumber == expectedSerial
            },
            {
                name = "owner character recorded",
                passed = last ~= nil and last.fromCharacterId ~= nil
            },
            {
                name = "terminal transition committed",
                passed = last ~= nil and last.operation == "destroy"
                    and last.outcome == "committed" and last.toInventoryId == nil
            },
            {
                name = "observations healthy",
                passed = diagnostics.failed == 0 and diagnostics.leaseViolations == 0
            }
        }
        local passed = 0
        for _, test in ipairs(tests) do
            if test.passed then passed = passed + 1 end
            print(("[WeaponDestructionAuditSmokeTest] %-29s %s"):format(
                test.name, test.passed and "PASS" or "FAIL"))
        end
        print(("[WeaponDestructionAuditSmokeTest] done %d/%d passed item=%s serial=%s (read-only)")
            :format(passed, #tests, tostring(expectedItem), tostring(expectedSerial)))
    end, true)

RegisterCommand("WeaponDualSlotContractSmokeTest", function(source, args)
        if source ~= 0 then return end
        local targetSource = tonumber(args and args[1])
        if not targetSource then
            local players = GetPlayers()
            targetSource = players[1] and tonumber(players[1]) or nil
        end
        local runtime = targetSource and WeaponRuntime.Get(targetSource) or nil
        local primary = runtime and runtime.slots and runtime.slots.primary or nil
        local offhand = runtime and runtime.slots and runtime.slots.offhand or nil
        local shoulder = runtime and runtime.slots and runtime.slots.shoulder or nil
        local back = runtime and runtime.slots and runtime.slots.back or nil
        local sessionId = runtime and runtime.sessionId or nil
        local capabilities = WeaponAPI.GetCapabilities()
        local tests = {
            {
                name = "named slot persistence",
                passed = Config.Inventory.equipmentSlots
                    and Config.Inventory.equipmentSlots.primary == Config.Inventory.equipmentSlot
                    and Config.Inventory.equipmentSlots.offhand ~= Config.Inventory.equipmentSlots.primary
                    and Config.Inventory.equipmentSlots.shoulder ~= Config.Inventory.equipmentSlots.primary
                    and Config.Inventory.equipmentSlots.back ~= Config.Inventory.equipmentSlots.shoulder
            },
            {
                name = "slot runtime initialized",
                passed = runtime ~= nil and type(runtime.slots) == "table"
            },
            {
                name = "primary compatibility alias",
                passed = runtime ~= nil and runtime.equipped == primary
            },
            {
                name = "slot capability reported",
                passed = capabilities.features.namedEquipmentSlots == true
                    and capabilities.features.dualWield == true
                    and type(capabilities.features.offhandEnabled) == "boolean"
                    and capabilities.features.matchingHashDualWield == false
                    and capabilities.features.definitionGatedMatchingPairs == false
                    and capabilities.features.fourSlotLoadout == true
                    and capabilities.features.mixedAmmoDualWield == true
            },
            {
                name = "pair ammo capability",
                passed = capabilities.features.pairAmmoEscrow == true
                    and capabilities.features.pairUnload == true
            },
            {
                name = "restore holster capability",
                passed = capabilities.features.restoredWeaponsHolstered == true
            },
            {
                name = "offhand policy configured",
                passed = capabilities.features.offhandPolicy == true
                    and EquipService.ValidateConfiguration().ok == true
            },
            {
                name = "slot repair capability",
                passed = capabilities.features.slotRepair == true
            },
            {
                name = "slot attachment capability",
                passed = capabilities.features.slotAttachments == true
            },
            {
                name = "atomic pair persistence",
                passed = capabilities.inventory.contractVersion >= 4
                    and capabilities.inventory.features
                    and capabilities.inventory.features.atomicBatchMetadata == true
                    and capabilities.inventory.features.atomicEquipmentPromotion == true
            },
            {
                name = "distinct weapon catalog",
                passed = capabilities.definitions.weapon >= 2
                    and DefinitionRegistry.Get("weapon", "revolver_cattleman").ok == true
                    and DefinitionRegistry.Get("weapon", "revolver_schofield").ok == true
            },
            {
                name = "matching hash rejection policy",
                passed = DefinitionRegistry.Get("weapon", "revolver_cattleman").value.matchingPairSupported == nil
                    and DefinitionRegistry.Get("weapon", "pistol_m1899").value.matchingPairSupported == nil
                    and DefinitionRegistry.Get("weapon", "pistol_mauser").value.matchingPairSupported == nil
            },
            {
                name = "slot item identities distinct",
                passed = not offhand or (primary ~= nil
                    and tostring(primary.itemInstanceId) ~= tostring(offhand.itemInstanceId))
            },
            {
                name = "primary lease scoped",
                passed = not primary or (targetSource ~= nil and sessionId ~= nil
                    and WeaponRuntime.MatchesLease(targetSource, sessionId,
                        primary.itemInstanceId, primary.generation, "primary"))
            },
            {
                name = "offhand lease scoped",
                passed = not offhand or (targetSource ~= nil and sessionId ~= nil
                    and WeaponRuntime.MatchesLease(targetSource, sessionId,
                        offhand.itemInstanceId, offhand.generation, "offhand"))
            },
            {
                name = "shoulder lease scoped",
                passed = not shoulder or (targetSource ~= nil and sessionId ~= nil
                    and WeaponRuntime.MatchesLease(targetSource, sessionId,
                        shoulder.itemInstanceId, shoulder.generation, "shoulder"))
            },
            {
                name = "back lease scoped",
                passed = not back or (targetSource ~= nil and sessionId ~= nil
                    and WeaponRuntime.MatchesLease(targetSource, sessionId,
                        back.itemInstanceId, back.generation, "back"))
            }
        }
        local passed = 0
        for _, test in ipairs(tests) do
            if test.passed then passed = passed + 1 end
            print(("[WeaponDualSlotContractSmokeTest] %-29s %s"):format(
                test.name, test.passed and "PASS" or "FAIL"))
        end
        print(("[WeaponDualSlotContractSmokeTest] done %d/%d passed source=%s primary=%s offhand=%s shoulder=%s back=%s")
            :format(passed, #tests, tostring(targetSource),
                tostring(primary and primary.itemInstanceId), tostring(offhand and offhand.itemInstanceId),
                tostring(shoulder and shoulder.itemInstanceId), tostring(back and back.itemInstanceId)))
    end, true)

if Config.DevMode then
    RegisterCommand("grantweapon", function(source, args)
        local definitionId = args[1] or "revolver_cattleman"
        local targetSource = tonumber(args[2]) or (source > 0 and source or nil)
        if not targetSource then
            print("[feather-weapons] usage: grantweapon [definitionId] [targetServerId]")
            return
        end

        local targetSession = CoreAdapter.ResolveSession(targetSource)
        if not targetSession.ok then
            print(("[feather-weapons] grant failed: %s"):format(targetSession.error.message))
            return
        end

        local actorCharacterId = nil
        if source > 0 then
            local actorSession = CoreAdapter.ResolveSession(source)
            actorCharacterId = actorSession.ok and actorSession.value.characterId or nil
        end

        local result = IssuanceService.Issue({
            actorSource = source == targetSource and source or nil,
            actorCharacterId = actorCharacterId,
            characterId = targetSession.value.characterId,
            sessionId = targetSession.value.sessionId,
            correlationId = ("dev-grant:%s:%s"):format(tostring(targetSource), tostring(GetGameTimer())),
            reason = "development_grant",
            resource = "feather-weapons"
        }, {
            characterId = targetSession.value.characterId,
            definitionId = definitionId,
            purpose = "development_grant",
            provenance = { type = "development_grant" }
        }, "feather-weapons")

        if not result.ok then
            local message = ("Weapon grant failed: %s"):format(result.error.message)
            print(("[feather-weapons] %s"):format(message))
            if source > 0 then Notify(source, message, 4000) end
            return
        end

        print(("[feather-weapons] granted definition=%s item=%s serial=%s character=%s")
            :format(result.value.definitionId, tostring(result.value.itemInstanceId),
                result.value.serialNumber, tostring(result.value.characterId)))
        Notify(targetSource,
            ("Received %s (%s)"):format(result.value.definitionId, result.value.serialNumber), 4000)
        TriggerClientEvent("Feather:Inventory:OpenInventory", targetSource, nil, "player")
    end, true)
end

RegisterCommand("WeaponMetadataInspect", function(source, args)
    if source ~= 0 then return end
    local targetSource = tonumber(args and args[1])
    if not targetSource then
        print("[WeaponMetadataInspect] usage: WeaponMetadataInspect [serverId]")
        return
    end
    local result = ReconciliationService.InspectMetadata(targetSource)
    if not result.ok then
        print(("[WeaponMetadataInspect] FAIL code=%s message=%s"):format(
            tostring(result.error and result.error.code), tostring(result.error and result.error.message)))
        return
    end
    local value = result.value
    if not value.equipped then
        print(("[WeaponMetadataInspect] PASS source=%s equipped=false character=%s"):format(
            tostring(targetSource), tostring(value.characterId)))
        return
    end
    for _, slot in ipairs(WeaponConstants.LoadoutSlots) do
        local item = value.slots and value.slots[slot] or nil
        print(("[WeaponMetadataInspect] PASS source=%s slot=%s equipped=%s item=%s definition=%s serial=%s generation=%s total=%s loaded=%s reserve=%s condition=%s attachments=%s runtimeMatch=%s")
        :format(
            tostring(targetSource), slot, tostring(item ~= nil),
            tostring(item and item.itemInstanceId), tostring(item and item.definitionId),
            tostring(item and item.serialNumber), tostring(item and item.generation),
            tostring(item and ((tonumber(item.loaded) or 0) + (tonumber(item.reserve) or 0))),
            tostring(item and item.loaded), tostring(item and item.reserve),
            tostring(item and item.condition), tostring(item and #(item.attachments or {})),
            tostring(item and item.runtimeMatches or false)))
    end
end, true)

RegisterCommand("WeaponProvenanceContractSmokeTest", function(source)
        if source ~= 0 then return end
        local contract = WeaponProvenanceService.CheckContract()
        local capabilities = WeaponAPI.GetCapabilities()
        local tests = {
            { name = "ledger ready", passed = contract.ready == true },
            { name = "trusted caller configured", passed = contract.trustedResourceConfigured == true },
            { name = "untrusted inspection rejected", passed = contract.untrustedRejected == true },
            { name = "incomplete inspection rejected", passed = contract.incompleteRejected == true },
            { name = "provenance capability ready", passed = capabilities.features.durableProvenance == true },
            { name = "serial inspection ready", passed = capabilities.features.serialInspection == true },
            { name = "inspection bounded", passed = contract.boundedInspection == true },
            { name = "retention configured", passed = contract.retentionConfigured == true }
        }
        local passed = 0
        for _, test in ipairs(tests) do
            if test.passed then passed = passed + 1 end
            print(("[WeaponProvenanceContractSmokeTest] %-31s %s"):format(
                test.name, test.passed and "PASS" or "FAIL"))
        end
        print(("[WeaponProvenanceContractSmokeTest] done %d/%d passed (read-only)")
            :format(passed, #tests))
    end, true)

RegisterCommand("WeaponIssuanceContractSmokeTest", function(source)
        if source ~= 0 then return end
        local contract, capabilities = IssuanceService.CheckContract(), WeaponAPI.GetCapabilities()
        local tests = {
            { 'service available', contract.serviceAvailable },
            { 'trusted caller configured', contract.trustedCallerConfigured },
            { 'issuance purpose configured', contract.purposeConfigured },
            { 'authorization configured', contract.authorizationConfigured },
            { 'untrusted caller rejected', contract.untrustedRejected },
            { 'incomplete request rejected', contract.incompleteRejected },
            { 'secure issuance ready', capabilities.features.secureIssuance == true },
            { 'stable request id required', contract.requestIdRequired },
            { 'oversized request id rejected', contract.oversizedRequestIdRejected },
            { 'malformed request id rejected', contract.malformedRequestIdRejected },
            { 'idempotent issuance ready', capabilities.features.idempotentIssuance == true },
            { 'issuance payload binding ready', capabilities.features.issuancePayloadBinding == true },
            { 'interrupted issuance recovery ready', capabilities.features.issuanceRecovery == true }
        }
        local passed = 0
        for _, test in ipairs(tests) do
            if test[2] then passed = passed + 1 end
            print(("[WeaponIssuanceContractSmokeTest] %-29s %s"):format(
                test[1], test[2] and 'PASS' or 'FAIL'))
        end
        print(("[WeaponIssuanceContractSmokeTest] done %d/%d passed (read-only)"):format(passed, #tests))
    end, true)

if Config.DevMode then
    RegisterCommand("WeaponIssuanceIdempotencyTest", function(source, args)
        if source ~= 0 then return end
        local targetSource = tonumber(args and args[1])
        local definitionId = args and args[2] or 'revolver_cattleman'
        local requestId = args and args[3]
        if not targetSource or type(requestId) ~= 'string' or requestId == '' then
            print('[WeaponIssuanceIdempotencyTest] usage: WeaponIssuanceIdempotencyTest <source> <definitionId> <requestId>')
            return
        end
        local session = CoreAdapter.ResolveSession(targetSource)
        if not session.ok then print('[WeaponIssuanceIdempotencyTest] FAIL session unavailable'); return end
        local request = { characterId = session.value.characterId, definitionId = definitionId,
            purpose = 'admin_issue', requestId = requestId,
            provenance = { type = 'admin_issue', reference = requestId } }
        local function Issue(suffix)
            return IssuanceService.Issue({ characterId = session.value.characterId,
                correlationId = ('idempotency-test:%s:%s'):format(requestId, suffix),
                reason = 'admin_issue', resource = 'feather-weapons' }, request, 'feather-weapons')
        end
        local first, second = Issue('first'), Issue('retry')
        local otherDefinition = definitionId == 'revolver_schofield'
            and 'revolver_cattleman' or 'revolver_schofield'
        local mismatchRequest = { characterId = session.value.characterId, definitionId = otherDefinition,
            purpose = 'admin_issue', requestId = requestId,
            provenance = { type = 'admin_issue', reference = requestId } }
        local mismatch = IssuanceService.Issue({ characterId = session.value.characterId,
            correlationId = ('idempotency-test:%s:mismatch'):format(requestId),
            reason = 'admin_issue', resource = 'feather-weapons' }, mismatchRequest, 'feather-weapons')
        local mismatchRejected = not mismatch.ok and mismatch.error
            and mismatch.error.code == WeaponErrors.OPERATION_CONFLICT
        local passed = first.ok and second.ok
            and tonumber(first.value.itemInstanceId) == tonumber(second.value.itemInstanceId)
            and first.value.serialNumber == second.value.serialNumber and second.value.replayed == true
            and mismatchRejected
        print(('[WeaponIssuanceIdempotencyTest] %s item=%s serial=%s replayed=%s mismatchRejected=%s'):format(
            passed and 'PASS' or 'FAIL', tostring(first.ok and first.value.itemInstanceId),
            tostring(first.ok and first.value.serialNumber), tostring(second.ok and second.value.replayed),
            tostring(mismatchRejected)))
    end, true)

    RegisterCommand("WeaponIssuanceRecoveryTest", function(source, args)
        if source ~= 0 then return end
        local targetSource = tonumber(args and args[1])
        local definitionId = args and args[2] or 'revolver_cattleman'
        local requestId = args and args[3]
        local phase = args and args[4] or 'combined'
        if not targetSource or type(requestId) ~= 'string' or requestId == '' then
            print('[WeaponIssuanceRecoveryTest] usage: WeaponIssuanceRecoveryTest <source> <definitionId> <requestId> [prepare|retry]')
            return
        end
        local session = CoreAdapter.ResolveSession(targetSource)
        if not session.ok then print('[WeaponIssuanceRecoveryTest] FAIL session unavailable'); return end
        local request = { characterId = session.value.characterId, definitionId = definitionId,
            purpose = 'admin_issue', requestId = requestId,
            provenance = { type = 'admin_issue', reference = requestId } }
        local base = { characterId = session.value.characterId, reason = 'admin_issue',
            resource = 'feather-weapons' }
        local interruptedContext = {
            characterId = base.characterId, reason = base.reason, resource = base.resource,
            correlationId = ('issuance-recovery:%s:interrupted'):format(requestId),
            failureInjection = 'after_create'
        }
        local interrupted
        if phase ~= 'retry' then
            interrupted = IssuanceService.Issue(
                interruptedContext, request, 'feather-weapons')
        end
        local interruptedAsExpected = interrupted and not interrupted.ok and interrupted.error
            and interrupted.error.code == WeaponErrors.OPERATION_CONFLICT
            and tonumber(interrupted.error.details and interrupted.error.details.itemInstanceId) ~= nil
        if phase == 'prepare' then
            print(('[WeaponIssuanceRecoveryTest] %s prepared item=%s serial=%s; restart feather-weapons then rerun with retry'):format(
                interruptedAsExpected and 'PASS' or 'FAIL',
                tostring(interruptedAsExpected and interrupted.error.details.itemInstanceId),
                tostring(interruptedAsExpected and interrupted.error.details.serialNumber)))
            return
        end
        local recovered = IssuanceService.Issue({
            characterId = base.characterId, reason = base.reason, resource = base.resource,
            correlationId = ('issuance-recovery:%s:retry'):format(requestId)
        }, request, 'feather-weapons')
        local expectedItemId = interruptedAsExpected
            and tonumber(interrupted.error.details.itemInstanceId) or nil
        local passed = (phase == 'retry' or interruptedAsExpected) and recovered.ok
            and recovered.value.replayed == true and recovered.value.recovered == true
            and (not expectedItemId or tonumber(recovered.value.itemInstanceId) == expectedItemId)
        print(('[WeaponIssuanceRecoveryTest] %s item=%s serial=%s interrupted=%s replayed=%s recovered=%s'):format(
            passed and 'PASS' or 'FAIL',
            tostring(recovered.ok and recovered.value.itemInstanceId),
            tostring(recovered.ok and recovered.value.serialNumber),
            tostring(interruptedAsExpected == true),
            tostring(recovered.ok and recovered.value.replayed),
            tostring(recovered.ok and recovered.value.recovered)))
    end, true)
end

RegisterCommand("WeaponProvenanceInspect", function(source, args)
        if source ~= 0 then return end
        local key = args and args[1]
        local request = { limit = tonumber(args and args[2]) or 10 }
        if tonumber(key) then request.itemInstanceId = tonumber(key) else request.serialNumber = key end
        local result = WeaponProvenanceService.Inspect(request,
            { correlationId = "provenance-inspect:" .. tostring(os.time()) }, "feather-weapons")
        if not result.ok then
            print(("[WeaponProvenanceInspect] FAIL code=%s message=%s"):format(
                tostring(result.error and result.error.code), tostring(result.error and result.error.message)))
            return
        end
        local value = result.value
        print(("[WeaponProvenanceInspect] item=%s serial=%s current=%s destroyed=%s events=%d"):format(
            tostring(value.itemInstanceId), tostring(value.serialNumber), tostring(value.current ~= nil),
            tostring(value.destroyed), #(value.events or {})))
        for _, event in ipairs(value.events or {}) do
            print(("[WeaponProvenanceInspect] event=%s type=%s operation=%s from=%s/%s to=%s/%s reason=%s at=%s"):format(
                tostring(event.id), tostring(event.event_type), tostring(event.operation),
                tostring(event.from_inventory_id), tostring(event.from_character_id),
                tostring(event.to_inventory_id), tostring(event.to_character_id),
                tostring(event.reason), tostring(event.occurred_at)))
        end
    end, true)

RegisterCommand("WeaponEvidenceTest", function(source, args)
        if source ~= 0 or Config.DevMode ~= true then return end
        local targetSource, itemId = tonumber(args and args[1]), tonumber(args and args[2])
        local serial, operation = args and args[3], args and args[4]
        if not targetSource or not itemId or type(serial) ~= 'string'
            or (operation ~= 'hold' and operation ~= 'release') then
            print('[WeaponEvidenceTest] usage: WeaponEvidenceTest <source> <itemId> <serial> <hold|release>')
            return
        end
        local session = CoreAdapter.ResolveSession(targetSource)
        if not session.ok then print('[WeaponEvidenceTest] FAIL session unavailable'); return end
        local context = { actorSource = targetSource, actorCharacterId = session.value.characterId,
            characterId = session.value.characterId,
            correlationId = ('evidence-test:%s:%s'):format(itemId, GetGameTimer()) }
        local request = { characterId = session.value.characterId,
            itemInstanceId = itemId, serialNumber = serial }
        local result = operation == 'hold'
            and WeaponEvidenceService.Hold(context, request, 'feather-weapons')
            or WeaponEvidenceService.Release(context, request, 'feather-weapons')
        print(('[WeaponEvidenceTest] %s operation=%s item=%s serial=%s%s'):format(
            result.ok and 'PASS' or 'FAIL', operation, itemId, serial,
            result.ok and '' or (' message=' .. tostring(result.error and result.error.message))))
    end, true)

RegisterCommand("WeaponEvidenceContractSmokeTest", function(source)
        if source ~= 0 then return end
        local contract, capabilities = WeaponEvidenceService.CheckContract(), WeaponAPI.GetCapabilities()
        local tests = {
            { 'service available', contract.serviceAvailable },
            { 'trusted caller configured', contract.trustedCallerConfigured },
            { 'authorization configured', contract.authorizationConfigured },
            { 'untrusted caller rejected', contract.untrustedRejected },
            { 'incomplete request rejected', contract.incompleteRejected },
            { 'evidence capability ready', capabilities.features.evidenceHolds == true }
        }
        local passed = 0
        for _, test in ipairs(tests) do
            if test[2] then passed = passed + 1 end
            print(("[WeaponEvidenceContractSmokeTest] %-30s %s"):format(
                test[1], test[2] and 'PASS' or 'FAIL'))
        end
        print(("[WeaponEvidenceContractSmokeTest] done %d/%d passed (read-only)"):format(passed, #tests))
    end, true)

RegisterCommand("WeaponReconcile", function(source, args)
    if source ~= 0 then return end
    local targetSource = tonumber(args and args[1])
    if not targetSource then
        print("[WeaponReconcile] usage: WeaponReconcile [serverId]")
        return
    end
    local result = ReconciliationService.Force(targetSource)
    if not result.ok then
        print(("[WeaponReconcile] FAIL code=%s message=%s"):format(
            tostring(result.error and result.error.code), tostring(result.error and result.error.message)))
        return
    end
    for _, slot in ipairs(WeaponConstants.LoadoutSlots) do
        local equipped = result.value.slots and result.value.slots[slot] or nil
        print(("[WeaponReconcile] PASS source=%s slot=%s equipped=%s item=%s generation=%s total=%s loaded=%s reserve=%s condition=%s"):format(
            tostring(targetSource), slot, tostring(equipped ~= nil),
            tostring(equipped and equipped.itemInstanceId),
            tostring(equipped and equipped.generation), tostring(equipped and equipped.ammo),
            tostring(equipped and equipped.loaded), tostring(equipped and equipped.reserve),
            tostring(equipped and equipped.condition)))
    end
end, true)

RegisterCommand("WeaponReleaseContractSmokeTest", function(source, args)
        if source ~= 0 then return end
        local targetSource = tonumber(args and args[1])
        if not targetSource then
            local players = GetPlayers()
            targetSource = players[1] and tonumber(players[1]) or nil
        end
        local capabilities = WeaponAPI.GetCapabilities()
        local routesResult = exports["feather-core"]:GetRpcRoutes()
        local routes = {}
        if type(routesResult) == "table" and routesResult.ok == true then
            for _, route in ipairs(routesResult.value or {}) do routes[route.route] = true end
        end
        local metadata = targetSource and ReconciliationService.InspectMetadata(targetSource) or nil
        local activeMetadataValid = type(metadata) == "table" and metadata.ok == true
            and type(metadata.value) == "table" and type(metadata.value.slots) == "table"
        local activeSlotCount = 0
        if activeMetadataValid then
            for _, slot in ipairs({ "primary", "offhand", "shoulder", "back" }) do
                local entry = metadata.value.slots[slot]
                if entry ~= nil then
                    activeSlotCount = activeSlotCount + 1
                    if entry.runtimeMatches ~= true then activeMetadataValid = false end
                end
            end
            activeMetadataValid = activeMetadataValid
                and ((metadata.value.equipped == true and activeSlotCount > 0)
                    or (metadata.value.equipped == false and activeSlotCount == 0))
        end
        local tests = {
            {
                name = "definitions ready",
                passed = capabilities.ready == true
                    and capabilities.definitions.weapon == 24
                    and capabilities.definitions.ammunition == 27
                    and capabilities.definitions.attachment == 2,
                detail = ("weapon=%s ammunition=%s attachment=%s"):format(
                    tostring(capabilities.definitions.weapon),
                    tostring(capabilities.definitions.ammunition),
                    tostring(capabilities.definitions.attachment))
            },
            { name = "inventory ready",      passed = capabilities.inventory.ready == true },
            {
                name = "native reload surface",
                passed = capabilities.features.nativeReload == true
                    and capabilities.features.ammunitionTypes == true
                    and capabilities.features.ammunitionSelection == true
                    and capabilities.features.ammunitionManagement == true
                    and capabilities.features.ammunitionSwitching == true
                    and capabilities.features.ammoEscrow == true
                    and capabilities.features.pairAmmoEscrow == true
                    and capabilities.features.pairUnload == true
                    and capabilities.features.reload == nil
            },
            {
                name = "runtime routes present",
                passed = routes["feather-weapons:equip:request"] == true
                    and routes["feather-weapons:ammo:sync"] == true
                    and routes["feather-weapons:ammo:pairSync"] == true
                    and routes["feather-weapons:ammo:unload"] == true
                    and routes["feather-weapons:ammo:loadSlot"] == true
                    and routes["feather-weapons:ammo:switchSlot"] == true
                    and routes["feather-weapons:ammo:availability"] == true
                    and routes["feather-weapons:repair:select"] == true
            },
            {
                name = "attachment routes present",
                passed = routes["feather-weapons:attachment:install"] == true
                    and routes["feather-weapons:attachment:remove"] == true
            },
            { name = "legacy reload absent", passed = routes["feather-weapons:ammo:reload"] ~= true },
            {
                name = "native probe disabled",
                passed = Config.NativeProbe
                    and Config.NativeProbe.enabled ~= true
            },
            {
                name = "active metadata valid",
                passed = activeMetadataValid,
                detail = targetSource and ("source=" .. tostring(targetSource)
                    .. " activeSlots=" .. tostring(activeSlotCount)) or "no player"
            }
        }
        local passed = 0
        for _, test in ipairs(tests) do
            if test.passed then passed = passed + 1 end
            print(("[WeaponReleaseContractSmokeTest] %-27s %s%s"):format(
                test.name, test.passed and "PASS" or "FAIL",
                test.detail and ("  -- " .. test.detail) or ""))
        end
        print(("[WeaponReleaseContractSmokeTest] done %d/%d passed"):format(passed, #tests))
end, true)
