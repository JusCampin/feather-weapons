Config = {
    DevMode = true,
    RequiredCoreContract = 1,
    Inventory = {
        requiredContract = 4,
        -- Stable Inventory equipment keys. Do not rename these after launch.
        equipmentSlot = "weapon", -- Legacy alias for the primary slot.
        equipmentSlots = {
            primary = "weapon",
            offhand = "weapon_offhand",
            shoulder = "weapon_shoulder",
            back = "weapon_back"
        }
    },
    Runtime = {
        authorizationTtlMs = 5000,
        authoritativeNativeAmmo = true,
        observationIntervalMs = 50,
        checkpointDebounceMs = 250,
        maintenanceCheckpointMs = 5000
    },
    Escrow = {
        -- Maximum cartridges authorized across every equipped weapon sharing
        -- an ammunition type. Feather keeps reserve virtual when two different
        -- long-gun hashes share that type; RedM sees only their loaded clips.
        -- Ammunition definitions may impose a smaller native-pool maximum.
        maxTotal = 200,
        -- Cartridges moved by one Inventory ammunition use.
        refillAmount = 30
    },
    Offhand = {
        -- Disable to run this server in primary-weapon-only mode.
        enabled = true,
        -- Only definition families/slots set to true may use the offhand.
        allowedFamilies = { revolver = true, pistol = true },
        allowedWeaponSlots = { sidearm = true },
        -- Automatically provide RedM's offhand holster entitlement when needed.
        provisionNativeEntitlement = true,
        -- RedM requires both an offhand clothing entitlement and its upgrade.
        -- Tested tint variants did not visibly restyle the equipped holster.
        nativeEntitlements = {
            -- RedM uses this exact wardrobe inventory item to back the working
            -- offhand-holster state. Other tints may look identical but are
            -- distinct native inventory entries.
            { itemName = "CLOTHING_ITEM_M_OFFHAND_000_TINT_004", slotId = 0xF20B6B4A },
            { itemName = "UPGRADE_OFFHAND_HOLSTER", slotId = 0x39E57B01 }
        },
        -- Native holster points; change only for a tested clothing setup.
        primaryAttachPoint = 2,
        offhandAttachPoint = 3
    },
    Loadout = {
        -- Four independent persistent positions: two sidearms and two long guns.
        -- Inventory uses these names when a weapon is equipped without an
        -- explicit slot; definitions marked sidearm fill primary/offhand and
        -- definitions marked longgun fill shoulder/back.
        sidearmSlots = { "primary", "offhand" },
        longgunSlots = { "shoulder", "back" },
        -- RedM's two weapon-wheel long-gun positions. These are the native
        -- RIFLE and RIFLE_ALTERNATE attach points, not cosmetic body bones.
        -- In-game layout: point 10 is the shoulder carry and point 9 is the
        -- back carry. Keep the logical slot names aligned with that layout.
        shoulderAttachPoint = 10,
        backAttachPoint = 9
    },
    NativeProbe = {
        -- Isolated Phase 1 diagnostic. Enable only on a development server.
        enabled = false,
        weapon = "WEAPON_REVOLVER_CATTLEMAN",
        -- Second native used only by the Phase 7 offhand/dual-wield probe.
        offhandWeapon = "WEAPON_REVOLVER_SCHOFIELD",
        ammo = "AMMO_REVOLVER",
        capacity = 6,
        primaryAttachPoint = 2,
        offhandAttachPoint = 3,
        observationIntervalMs = 50
    },
    Attachments = {
        requireStation = true,
        interactionDistance = 2.0,
        serverTolerance = 3.0,
        stations = {
            valentine = {
                label = "Valentine Gunsmith Bench",
                coords = vector3(-277.455, 779.197, 119.504)
            }
        }
    },
    Controls = {
        unload = {
            enabled = true,
            defaultKey = "U",
            command = "feather_weapon_unload"
        },
        modify = {
            enabled = true,
            defaultKey = "F6",
            command = "weaponmods"
        }
    }
}
