# Feather Weapons — Expansion Master Plan

> Status: Standard firearm/ammunition expansion implemented; live catalog validation in progress
> Baseline: single weapon plus different-hash dual wield and four-slot loadouts
> Compatibility policy: alpha; backward compatibility is not required  
> Runtime rule: RedM owns weapon gameplay; Feather authorizes, persists, and reconciles it

This plan begins where [`MASTER_PLAN.md`](MASTER_PLAN.md) ends. The previous
plan remains the implementation and validation record for the native-first
runtime. This document governs the next expansion of Feather Weapons.

## 1. Current baseline

The next phase starts with these behaviors treated as signed off:

- unique Inventory-backed weapon instances;
- primary/offhand sidearm slots and shoulder/back long-gun slots;
- different-hash native dual wield; matching hashes fail closed;
- independent slot leases, condition, attachments, and metadata;
- bounded single-weapon and paired ammunition escrow;
- native firing, reload, draw, and holster behavior;
- refill and unload while a pair is equipped;
- persistence through logout, reconnect, character selection, and restarts;
- movement and destruction guards for equipped items;
- server-side issuance, inspection, reconciliation, repair, and attachment APIs;
- Admin integration and two-player isolation;
- release gates passing runtime `5/5`, dual-slot `14/14`, and release `8/8`;
- definitions split into weapon, ammunition, and attachment catalogs;
- 24 standard firearm and 27 ammunition definitions;
- definition-driven ammunition selection and exact-type unloading;
- `gun_oil` repair and `feather-menu-v2` modification/repair menus; and
- recipe seeds, Inventory artwork, migrations, catalog documentation, and
  automated ammunition coverage.

No new phase may weaken these guarantees.

## 2. Product direction

Feather Weapons should become the authoritative weapon domain for the Feather
Framework without becoming a second Inventory or replacing RedM's native
combat behavior.

The expansion should provide:

- complete live validation of the implemented sidearm and long-gun catalog,
  followed by bows, melee weapons, and throwables;
- definition-driven ammunition and modifications;
- safe ownership transfers, storage, confiscation, evidence, and destruction;
- server-owner policies for weapon access, offhand behavior, degradation, and
  economy integration;
- stable contracts for Admin, shops, jobs, crafting, and law systems; and
- recovery tools that preserve unique item identity and audit history.

## 3. Permanent boundaries

### RedM owns

- draw, holster, aim, fire, reload, cycling, and combat animations;
- live weapon entities, native clips, shared native ammo pools, and contextual
  controls; and
- whether an action is possible in the ped's current native state.

### Feather Weapons owns

- weapon definitions and compatibility policy;
- unique weapon identity, metadata normalization, serials, and provenance;
- equipment authorization, runtime leases, checkpoints, and reconciliation;
- ammunition budgets, condition, repair, and modifications;
- weapon-domain operations and audit events; and
- rejection and cleanup of unauthorized native state.

### Feather Inventory owns

- item instances, stacks, containers, equipment slots, and movement guards;
- atomic quantity, metadata, ownership, and container transactions; and
- capacity, weight, access, and revision enforcement.

Other resources must use public Weapons and Inventory contracts. They may not
write weapon metadata, equipment slots, or ammunition quantities directly.

## 4. Cross-cutting rules

- One owned weapon is one unique Inventory item instance.
- Weapon definition IDs use `<family>_<model>`, such as `revolver_cattleman`.
  Inventory item names use `weapon_<family>_<model>`, such as
  `weapon_revolver_cattleman`. Ammunition uses `ammo_<family>_<type>`.
- Client observations may reduce or redistribute an approved budget, never
  create ownership, ammunition, condition, or attachments.
- Every mutation is bound to the current session, character, item, slot, and
  runtime generation.
- Cross-resource callbacks use `IsCallable`; Lua `type(value) == "function"`
  alone is not valid for CFX function references.
- Configuration and definitions fail closed at startup.
- Alpha changes may replace unfinished contracts instead of carrying aliases.
- Development probes remain disabled by default and isolated from production
  leases.
- Documentation is written for server owners; internal implementation detail
  belongs in code comments or developer documentation.

## 5. Phase 1 — Release cleanup and entitlement ownership — VALIDATION

### Work

- Finish the current release review and remove stale comments, diagnostics,
  commands, and roadmap entries.
- Keep native entitlement item names in server-owned configuration.
- Verify the offhand clothing entitlement for male and female character models.
- Determine whether Feather should select an entitlement by character model or
  integrate with the character clothing resource.
- Ensure entitlement cleanup never removes clothing that Feather did not add.
- Document that the tested tint identifier is a native inventory marker when
  tint variants do not visibly restyle the holster.
- Keep the native-name generator overrides aligned with actual CFX callable
  names.

### Exit gate

- Fresh male and female characters can equip, restore, and remove an offhand
  weapon without permanent wardrobe changes.
- Entitlement loss fails closed and reconciliation restores only approved
  state.
- Runtime, dual-slot, and release smoke tests remain fully passing.

### Result

The release cleanup, native entitlement ownership, holstered restoration, and
server-owner offhand policy are implemented. Matching-hash production support
was retired because RedM cannot preserve it reliably across every wheel,
holster, and restoration boundary. Feather
tracks and removes only native entitlement items it created. Entitlement loss
fails closed and restores the approved pair. The native probe remains gated and
the release configuration keeps development mode disabled. The tested character
path passed; a fresh female-character entitlement pass remains required before
closing the complete model matrix.

## 6. Phase 2 — Standard firearm catalog — VALIDATION

### Work

- [x] Define supported standard-firearm families and native groups.
- [x] Add four pistols, five revolvers, four repeaters, six rifles, and five
  shotguns without adding a weapon-specific runtime state machine.
- [x] Record capacity, ammunition type, weapon slot, handedness, degradation,
  condition thresholds, component categories, and native hashes per definition.
- [x] Define explicit offhand eligibility instead of assuming all one-handed
  weapons are safe.
- [x] Add startup cross-reference validation, installation SQL, recipe seeds,
  alpha item-name migration, Inventory artwork, and catalog documentation.
- [ ] Validate Admin grant, single equip, switching, holster restoration,
  firing, reload, unload, repair, logout/reselection, and restart for every
  shipped model.
- [ ] Test representative shared native ammo pools and two-player isolation in
  every compatible family.
- [ ] Add bows and other ammo-using special weapons only after the standard
  firearm matrix passes. Melee weapons and throwables remain later slices.

### Exit gate

- Every shipped definition passes a catalog validation matrix.
- Unsupported pairings are rejected before native state changes.
- Adding a definition requires no new weapon-specific runtime branch unless a
  documented native exception is unavoidable.

## 7. Phase 3 — Ammunition families and load types — VALIDATION

### Work

- [x] Add 27 ammunition definitions with explicit weapon compatibility.
- [x] Support weapon-specific selection among regular, express, high velocity,
  split point, explosive, incendiary, slug, Varmint, tranquilizer, and Nitro
  Express types as appropriate to the implemented firearm catalog. Arrow and
  throwable definitions remain future work.
- [x] Persist selected ammo type in both weapon metadata and active runtime
  state.
- [x] Require an empty weapon or pair before changing types and preserve each
  item's approved budget.
- [x] Prevent shared native pools from moving cartridges between incompatible
  persistent items.
- [x] Fail closed when shoulder and back weapons resolve to the same native
  ammunition type; verified RedM hash-based clip APIs cannot preserve reliable
  identity, firing, and reload behavior for that combination.
- [x] Return the exact selected ammunition definition during unload.
- [x] Add automated coverage for selection, restore, firing, refill, unload,
  pair conservation, stale leases, incompatible requests, and Inventory
  failures.
- [ ] Confirm native special-ammunition effects and clip behavior for every
  family on the target RedM build.
- [ ] Specifically validate Varmint tranquilizer and Elephant Rifle Nitro
  Express ammunition.
- [ ] Add a slot-specific ammunition menu that displays each equipped weapon,
  its selected ammunition label, loaded/reserve counts, and compatible stock.
- [ ] Add explicit Load and Unload actions for one selected weapon slot so a
  player can prepare shoulder and back weapons with different native ammo types
  without temporarily unequipping either weapon.

### Exit gate

- Ammo switching, firing, reload, refill, unload, reconnect, and restart conserve
  every cartridge by definition and item.
- No client request can convert one ammo type into another or exceed an approved
  budget.

## 8. Phase 4 — Complete modification system

### Work

- Expand attachment definitions beyond the Cattleman Long Barrel.
- Model component slots, compatibility, conflicts, prerequisites, and defaults.
- Preserve independent modifications on every supported equipped weapon instance.
- Apply components by approved item identity and reconcile failed native
  application without consuming the component.
- Add server-owner gunsmith stations and optional job restrictions.
- Separate functional components from cosmetic customization.
- Decide how engravings, metals, varnishes, wraps, and tints are represented
  without hard-coding another framework's catalog.

This is the next implementation phase after the Phase 2/3 live acceptance
matrix. Only the Cattleman Long Barrel is currently shipped; do not bulk-add
component definitions without verified native mappings and lifecycle tests.

### Exit gate

- Install and removal are atomic for equipped, holstered, stored, primary, and
  offhand weapons.
- Matching weapons retain distinct modifications through every lifecycle path.
- Failed application cannot lose or duplicate a component item.

## 9. Phase 5 — Ownership, transfer, and storage

### Work

- Define explicit Weapons operations for transfer, storage, pickup, surrender,
  confiscation, return, destruction, and recovery.
- Preserve serial number and provenance across every ownership transition.
- Require checkpoint and unequip before a weapon leaves an active character.
- Integrate character inventory, player-to-player transfer, storage containers,
  and dropped-world-item flows through Inventory transactions.
- Define recovery for disconnects and resource failure during a transition.
- Prevent transfers of equipped, stale, invalid, or administratively held
  weapons.

### Exit gate

- Every ownership transition is atomic, idempotent, and auditable.
- A weapon cannot exist in two owners or containers after retry, timeout,
  disconnect, or restart.

## 10. Phase 6 — Evidence, provenance, and law workflows

### Work

- Expand provenance into append-only issuance and ownership events.
- Add evidence holds without copying or rewriting the weapon item.
- Expose read-only serial, owner-history, condition, ammo, and modification
  inspection to authorized resources.
- Define confiscation, evidence intake, release, forfeiture, and destruction
  operations.
- Keep staff permissions and presentation in Feather Admin.
- Establish retention and privacy policy for ownership history.

### Exit gate

- Law and Admin workflows cannot bypass Inventory ownership or Weapons metadata
  validation.
- Evidence operations retain a single canonical item identity and complete
  audit chain.

## 11. Phase 7 — Shops, licenses, jobs, and crafting

### Work

- Publish purchase and issuance contracts for shop resources.
- Define license and job policy hooks without embedding a specific economy or
  permissions system in Weapons.
- Add crafting inputs and outputs through Inventory transactions.
- Generate serials and provenance only through trusted server issuance.
- Define pricing, stock, recipes, and locations outside the core weapon runtime.
- Add server-owner examples for legal shops, job armories, and restricted
  weapons.

### Exit gate

- Buying, crafting, and job issuance cannot bypass unique-item creation,
  licensing policy, or audit provenance.
- Removing any optional economy resource does not break the weapon runtime.

## 12. Phase 8 — Security and operational hardening

### Work

- Threat-model every new network route and cross-resource callable.
- Bound payloads, rates, retries, lock duration, and transaction scope.
- Add multiplayer contention tests for transfers, storage, shops, and Admin
  recovery.
- Add clean-install, restart, reconnect, resource-stop, and failure-injection
  tests for every supported family.
- Add read-only release smoke tests that remain available with development mode
  disabled.
- Review configuration defaults and recovery documentation with a server-owner
  perspective.
- Remove experimental probes and temporary compatibility code before release.

### Exit gate

- The complete release matrix passes for at least two simultaneous players.
- No known operation duplicates or loses a weapon, cartridge, attachment, or
  repair material under retry or interruption.
- Operations documentation covers installation, configuration, inspection,
  reconciliation, backup, and failure recovery.

## 13. Required test matrix for every phase

### Identity and authorization

- Correct character, item, slot, session, and generation are required.
- Foreign, stale, duplicated, malformed, and missing data fail closed.
- Cross-player and cross-resource attempts cannot mutate another lease.

### Inventory conservation

- Success changes exactly the intended items and quantities.
- Failure changes nothing.
- Retry is idempotent.
- Concurrent operations produce one deterministic winner or a safe conflict.

### Native reconciliation

- Draw, holster, fire, reload, switch, death, revive, and movement remain native.
- Reconnect and resource/server restart restore the accepted state.
- Unauthorized native weapons or ammo are removed without creating Inventory
  ownership.

### Dual-slot behavior

- Primary only and different-hash pairs remain supported; matching hashes are rejected.
- Equip, remove, and promote work in both orders.
- Each slot retains its own condition, loaded state, attachments, and lease.
- Shared ammo pools conserve the combined approved total.
- Shoulder and back fail closed when their selected definitions map to the same
  native ammunition type.

### Operations

- Inspection is read-only.
- Reconciliation renews leases without changing accepted metadata.
- Admin and optional integrations use public contracts only.
- Two-player isolation passes.

## 14. Definition of done

A phase is complete only when:

- its public behavior and ownership boundary are documented;
- configuration and definitions validate at startup;
- normal, failure, retry, concurrent, lifecycle, and multiplayer paths pass;
- all item and ammunition conservation checks pass;
- recovery output identifies the affected character, item, slot, and operation;
- development diagnostics are disabled by default;
- server-owner documentation describes only shipped functionality; and
- all earlier release smoke tests remain green.

## 15. Immediate next work

1. Run `WeaponReleaseContractSmokeTest` and confirm `weapon=24`,
   `ammunition=27`, and `attachment=1` on the target server build.
2. Complete the fresh female-character offhand entitlement and cleanup check.
3. Complete the per-model live matrix: Admin grant, equip, fire, native reload,
   unload, gun-oil repair, logout/reselection, and resource restart.
4. Verify clip capacity, holster placement, wheel behavior, and special-ammo
   effects for each firearm family, with focused checks for LeMat, Sawed-Off,
   Varmint, Elephant Rifle, and long guns.
5. Repeat representative family checks with two simultaneous players and
   matching/distinct sidearm pairs.
6. After the catalog is accepted, build the attachment compatibility worksheet
7. Build the slot-specific ammunition status/load/unload menu before expanding
   long-gun inventory UX.
   and add one fully tested component vertical slice beyond the Cattleman Long
   Barrel.
