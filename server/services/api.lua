WeaponAPI = {}

function WeaponAPI.GetCapabilities()
    return {
        contractVersion = WeaponConstants.ContractVersion,
        ready = DefinitionRegistry.IsReady(),
        definitions = DefinitionRegistry.Counts(),
        inventory = InventoryAdapter.GetCapabilities(),
        features = {
            definitions = true,
            metadataValidation = true,
            characterSessions = true,
            reconciliation = true,
            inventoryPersistence = InventoryAdapter.IsReady(),
            equipAuthorization = true,
            equip = InventoryAdapter.IsReady(),
            namedEquipmentSlots = InventoryAdapter.IsReady(),
            offhandPolicy = true,
            offhandEnabled = Config.Offhand and Config.Offhand.enabled == true,
            matchingHashDualWield = false,
            definitionGatedMatchingPairs = false,
            restoredWeaponsHolstered = true,
            slotInspection = InventoryAdapter.IsReady(),
            slotRecovery = InventoryAdapter.IsReady(),
            dualWield = true,
            ammunition = InventoryAdapter.IsReady(),
            ammunitionTypes = true,
            ammunitionSelection = InventoryAdapter.IsReady(),
            ammunitionManagement = InventoryAdapter.IsReady(),
            ammunitionSwitching = InventoryAdapter.IsReady(),
            ammoEscrow = InventoryAdapter.IsReady(),
            pairAmmoEscrow = InventoryAdapter.IsReady(),
            mixedAmmoDualWield = true,
            fourSlotLoadout = true,
            mixedSidearmLongarm = true,
            nativeReload = true,
            unload = InventoryAdapter.IsReady(),
            pairUnload = InventoryAdapter.IsReady(),
            nativeObservation = InventoryAdapter.IsReady(),
            condition = InventoryAdapter.IsReady(),
            repair = InventoryAdapter.IsReady(),
            slotRepair = InventoryAdapter.IsReady(),
            issuance = InventoryAdapter.IsReady(),
            secureIssuance = InventoryAdapter.IsReady(),
            idempotentIssuance = InventoryAdapter.IsReady(),
            issuancePayloadBinding = InventoryAdapter.IsReady(),
            issuanceRecovery = InventoryAdapter.IsReady() and WeaponProvenanceService.IsReady(),
            attachmentDefinitions = true,
            attachmentTransactions = InventoryAdapter.IsReady(),
            slotAttachments = InventoryAdapter.IsReady(),
            ownershipTransitionEvents = InventoryAdapter.IsReady(),
            durableProvenance = WeaponProvenanceService.IsReady(),
            serialInspection = WeaponProvenanceService.IsReady(),
            evidenceHolds = InventoryAdapter.IsReady(),
            administrativeHoldGuards = InventoryAdapter.IsReady(),
            destruction = InventoryAdapter.IsReady()
        }
    }
end

function WeaponAPI.GetDefinition(kind, id)
    return DefinitionRegistry.Get(kind, id)
end

function WeaponAPI.ListDefinitions(kind)
    return DefinitionRegistry.List(kind)
end

function WeaponAPI.ListCompatibleAttachments(weaponId)
    return DefinitionRegistry.ListCompatibleAttachments(weaponId)
end

function WeaponAPI.GetRuntime(source)
    return WeaponRuntime.Get(source)
end

function WeaponAPI.InspectEquippedWeapons(source)
    return ReconciliationService.InspectMetadata(tonumber(source))
end

function WeaponAPI.ReconcileEquippedWeapons(source)
    return ReconciliationService.Force(tonumber(source))
end

function WeaponAPI.IssueWeapon(request, context, invokingResource)
    context = type(context) == "table" and context or {}
    context.resource = invokingResource or GetInvokingResource()
    return IssuanceService.Issue(context, request, context.resource)
end

function WeaponAPI.DestroyWeapon(request, context, invokingResource)
    return WeaponOwnershipService.Destroy(context, request, invokingResource)
end

function WeaponAPI.InspectWeaponHistory(request, context, invokingResource)
    return WeaponProvenanceService.Inspect(request, context, invokingResource)
end

function WeaponAPI.HoldEvidence(request, context, resource)
    return WeaponEvidenceService.Hold(context, request, resource)
end

function WeaponAPI.ReleaseEvidence(request, context, resource)
    return WeaponEvidenceService.Release(context, request, resource)
end

exports("initiate", function()
    return {
        GetCapabilities = WeaponAPI.GetCapabilities,
        Definitions = { Get = WeaponAPI.GetDefinition, List = WeaponAPI.ListDefinitions, ListCompatibleAttachments = WeaponAPI.ListCompatibleAttachments },
        Metadata = { Build = WeaponMetadata.Build, Validate = WeaponMetadata.Validate },
        Runtime = { Get = WeaponAPI.GetRuntime },
        Inspection = {
            Inspect = WeaponAPI.InspectEquippedWeapons,
            Reconcile = WeaponAPI.ReconcileEquippedWeapons,
            History = function(request, context)
                return WeaponAPI.InspectWeaponHistory(request, context, GetInvokingResource())
            end
        },
        Issuance = { Issue = function(request, context)
            return WeaponAPI.IssueWeapon(request, context, GetInvokingResource())
        end },
        Ownership = {
            Destroy = function(request, context)
                local invokingResource = GetInvokingResource()
                return WeaponAPI.DestroyWeapon(request, context, invokingResource)
            end,
            HoldEvidence = function(request, context)
                return WeaponAPI.HoldEvidence(request, context, GetInvokingResource())
            end,
            ReleaseEvidence = function(request, context)
                return WeaponAPI.ReleaseEvidence(request, context, GetInvokingResource())
            end
        },
        Inventory = {
            InstallProvider = InventoryAdapter.InstallProvider,
            GetCapabilities = InventoryAdapter.GetCapabilities
        }
    }
end)

-- Stable cross-resource issuance entry point. Consumers should use this
-- named export instead of relying on nested functions surviving Cfx's API
-- table boundary.
exports("IssueWeapon", function(request, context)
    return WeaponAPI.IssueWeapon(request, context, GetInvokingResource())
end)

exports("DestroyWeapon", function(request, context)
    local invokingResource = GetInvokingResource()
    return WeaponAPI.DestroyWeapon(request, context, invokingResource)
end)

exports("InspectWeaponHistory", function(request, context)
    return WeaponAPI.InspectWeaponHistory(request, context, GetInvokingResource())
end)

exports("HoldWeaponEvidence", function(request, context)
    return WeaponAPI.HoldEvidence(request, context, GetInvokingResource())
end)

exports("ReleaseWeaponEvidence", function(request, context)
    return WeaponAPI.ReleaseEvidence(request, context, GetInvokingResource())
end)

exports("InspectEquippedWeapons", function(source)
    return WeaponAPI.InspectEquippedWeapons(source)
end)

exports("ReconcileEquippedWeapons", function(source)
    return WeaponAPI.ReconcileEquippedWeapons(source)
end)
