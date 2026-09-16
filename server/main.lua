local function FailStartup(message, details)
    print(("[feather-weapons] startup failed: %s"):format(message))
    if details and Config.DevMode then print(json.encode(details)) end
    error(message)
end

local coreResult = CoreAdapter.CheckCapabilities()
if not coreResult.ok then
    FailStartup(coreResult.error.message, coreResult.error.details)
    return
end

local definitionResult = DefinitionRegistry.Start()
if not definitionResult.ok then
    FailStartup(definitionResult.error.message, definitionResult.error.details)
    return
end

local provenanceResult = WeaponProvenanceService.Start()
if not provenanceResult.ok then
    FailStartup(provenanceResult.error.message, provenanceResult.error.details)
    return
end

local offhandConfigResult = EquipService.ValidateConfiguration()
if not offhandConfigResult.ok then
    FailStartup(offhandConfigResult.error.message, offhandConfigResult.error.details)
    return
end

local inventoryProviderResult = InstallFeatherInventoryProvider()
if not inventoryProviderResult.ok then
    FailStartup(inventoryProviderResult.error.message, inventoryProviderResult.error.details)
    return
end

ReconciliationService.BootstrapActiveSessions()

local counts = definitionResult.value
print(("[feather-weapons] foundation ready: %d weapon, %d ammunition, %d attachment definitions")
    :format(counts.weapon, counts.ammunition, counts.attachment))

if InventoryAdapter.IsReady() then
    local capabilities = InventoryAdapter.GetCapabilities()
    print(("[feather-weapons] inventory provider active: %s")
        :format(tostring(capabilities.provider or "unknown")))
end
