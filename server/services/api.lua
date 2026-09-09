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
            attachmentDefinitions = true,
            attachmentTransactions = InventoryAdapter.IsReady(),
            slotAttachments = InventoryAdapter.IsReady()
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

function WeaponAPI.IssueWeapon(request, context)
    context = type(context) == "table" and context or {}
    context.resource = context.resource or GetInvokingResource() or "feather-weapons"
    return IssuanceService.Issue(context, request)
end

exports("initiate", function()
    return {
        GetCapabilities = WeaponAPI.GetCapabilities,
        Definitions = { Get = WeaponAPI.GetDefinition, List = WeaponAPI.ListDefinitions, ListCompatibleAttachments = WeaponAPI.ListCompatibleAttachments },
        Metadata = { Build = WeaponMetadata.Build, Validate = WeaponMetadata.Validate },
        Runtime = { Get = WeaponAPI.GetRuntime },
        Inspection = {
            Inspect = WeaponAPI.InspectEquippedWeapons,
            Reconcile = WeaponAPI.ReconcileEquippedWeapons
        },
        Issuance = { Issue = WeaponAPI.IssueWeapon },
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
    return WeaponAPI.IssueWeapon(request, context)
end)

exports("InspectEquippedWeapons", function(source)
    return WeaponAPI.InspectEquippedWeapons(source)
end)

exports("ReconcileEquippedWeapons", function(source)
    return WeaponAPI.ReconcileEquippedWeapons(source)
end)
