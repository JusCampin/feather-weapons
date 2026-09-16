# Feather Weapons — Expansion Master Plan

> Status: Standard firearm/ammunition expansion and ammunition-management UI shipped in 0.10.1; live catalog and distinct-ammo pair validation in progress
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
- release gates passing runtime `5/5`, dual-slot `17/17`, and release `8/8`;
- definitions split into weapon, ammunition, and attachment catalogs;
- 24 standard firearm and 27 ammunition definitions;
- definition-driven ammunition selection and exact-type unloading;
- slot-specific ammunition management for equipped weapons, including
  inventory-aware load choices, exact unload actions, and in-flight activity
  feedback;
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
the release configuration keeps development mode disabled. The fresh female
character equip check passed: two distinct empty sidearms occupied the correct
primary/offhand holsters, dual draw worked, and entitlement provisioning caused
no unexpected visible clothing change. Removing the female character's Mauser
offhand also passed: Cattleman remained as the sole primary weapon and native
entitlement cleanup caused no visible wardrobe change. Removing the final
Cattleman also passed with no visual wardrobe change; `weaponstate` reported
no equipped primary or offhand state. The fresh female-character entitlement
and cleanup gate is closed.

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
- [x] Validate Admin grant, single equip, switching, holster restoration,
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
- [x] Add a slot-specific ammunition menu that displays each equipped weapon,
  its selected ammunition label, loaded/reserve counts, and compatible stock.
- [x] Add explicit Load and Unload actions for one selected weapon slot so a
  player can prepare shoulder and back weapons with different native ammo types
  without temporarily unequipping either weapon.
- [ ] Validate different-ammunition dual-sidearm pairs. Confirm that each
  weapon's persisted total, native pool, clip, and wheel quantity agree after
  restore, firing, reload, menu operations, logout, and resource restart.
- [x] Resolve the current distinct-pool restore discrepancy where RedM may
  count materialized clips differently for the primary and offhand weapon.

### Exit gate

- Ammo switching, firing, reload, refill, unload, reconnect, and restart conserve
  every cartridge by definition and item.
- No client request can convert one ammo type into another or exceed an approved
  budget.

## 8. Phase 4 — Complete modification system

### Work

- [x] Add the Cattleman Wide Sight as the first definition beyond the validated
  Cattleman Long Barrel, backed by a compatibility worksheet and verified native
  component mapping. Its live lifecycle remains pending.
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

Attachment prerequisites are now definition-driven. Startup rejects invalid,
cyclic, conflicting, same-slot, and weapon-incompatible prerequisite graphs;
installation and removal validate the complete resulting set inside the same
Inventory transaction. The two shipped Cattleman components remain independent.
Optional gunsmith job restrictions now use Feather Core's policy-provider
boundary. They remain disabled by default; when enabled, both installation and
removal fail closed unless the configured action authorizes the character for
the specific operation, station, weapon definition, and attachment.
Live validation passed both policy modes. With authorization disabled, existing
Cattleman installation and removal remained available and release smoke passed
`8/8`. With authorization enabled, the active policy denied the character;
the menu could open, but installation/removal failed with an authorization
notice and changed neither weapon metadata nor Inventory. The shipped default
was restored to disabled after the test.
Native component defaults are now explicit presentation metadata on weapon
definitions. The Cattleman labels its unmodified barrel and sight without
turning either baseline into an Inventory item; installed upgrades hide the
corresponding default, and removal reveals it again. Startup rejects defaults
for undeclared slots or empty labels.
The modification menu now remains open after successful mutations, rebuilds
the active weapon page, uses catalog weapon/component labels, and groups slots
in a stable order. Live temporary prerequisite validation passed end to end:
Wide Sight named Long Barrel as its missing requirement, installing Long Barrel
unlocked the sight, installing the sight marked the barrel as required and
withheld its removal action, then removing sight before barrel returned both
items and restored both standard defaults. The temporary dependency was removed
after testing; the shipped Cattleman components remain independent.
`WeaponAttachmentContractSmokeTest` now provides a read-only live gate for the
active four-slot loadout. It validates each complete attachment set, component
mapping, attachment and slot identity, runtime lease scope, and authorization
configuration without changing weapon or Inventory state.
The first live run passed `7/7` with one active weapon carrying both shipped
Cattleman components (`activeSlots=1 attachments=2`).
The corresponding unmodified run passed `7/7` with the same active-slot shape
and zero attachment metadata (`activeSlots=1 attachments=0`), confirming that
presentation defaults remain distinct from installed component instances.
The modified Cattleman also passed `7/7` while holstered. Client state remained
idle with primary/offhand natives cleared, while item `4875` retained both
component identities under its current primary lease.
Offhand isolation passed `7/7` with two active sidearm slots. Primary item
`4888` retained zero attachments while offhand Cattleman item `4875` retained
both components under generation `3`; the shared revolver ammo coordinator
remained conserved at an empty authorized pool.
A second Cattleman instance, item `4889`, then passed `7/7` alone with zero
attachments, demonstrating that item `4875`'s two-component state did not bleed
across matching weapon definitions.
Reselecting original item `4875` completed the identity round trip at generation
`5`: its two component IDs returned and the attachment contract again passed
`7/7`, while item `4889` remained independently unmodified.
After character logout and restoration, item `4875` returned at generation `1`
with both components, valid active-set metadata, and a current runtime lease;
the attachment contract passed `7/7`.
Restarting `feather-weapons` reproduced the same generation `1` state for item
`4875`; both component identities and the current lease remained valid and the
attachment contract passed `7/7`. The Phase 4 live attachment lifecycle matrix
is complete for the shipped Cattleman components.

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

The first Phase 5 slice consumes Inventory's existing committed `ItemMoved`
event rather than introducing a duplicate movement API. Cross-container weapon
moves are normalized into `Feather:Weapons:OwnershipTransitionCommitted` facts
containing item, definition, serial, revision, inventories, actor, reason, and
correlation identity. Same-inventory slot rearrangements are ignored. Any move
that somehow retains an active Weapons lease is treated as a critical guard
violation and forces reconciliation.
Live ground-transition validation passed: unequipped Cattleman item `4889`
produced two healthy committed observations across drop and pickup, preserving
the same item and weapon identity with zero failed observations or active-lease
violations. The ownership smoke test passed `6/6` and release smoke remained
`8/8`.
Weapon serials now travel with approved runtime state and appear in ammunition
and modification menus plus `weaponstate`, giving players and testers a stable
firearm identity before and after an ownership transition.
The player-visible identity round trip passed for item `4889`: serial
`FW-REVO-6AA86F32-E89E28-0002` was identical before drop and after pickup and
re-equip. The observer again reported exactly two committed transitions and
passed `6/6` with zero failures or active-lease violations.
Inventory move and destroy guards now fail closed for weapon metadata marked as
evidence or administratively disabled, matching the existing equip rejection.
Ordinary weapons remain movable once unequipped; future confiscation/return
operations must explicitly manage holds rather than bypassing the generic guard.
Committed movement facts are now classified from Inventory's reason plus the
actor's canonical character-inventory identity. Explicit give, drop, recovery,
pickup, and deposit transitions receive stable names; unresolved container
movement remains `inventory_move` rather than being guessed.
Live validation passed `11/11` for item `4889`: one `drop` and one `pickup`
were classified from the committed ground round trip, the final transition was
`pickup`, and failures and active-lease violations remained zero. Release smoke
remained `8/8` with no active slots.
Player-to-player `give` facts now resolve both active character owners from the
committed origin and destination inventory IDs. A dedicated transfer smoke test
requires distinct source/recipient characters, preserved serial identity, and
zero observation or lease failures.
The forward two-player transfer passed `7/7` for item `4889`. Both character
owners resolved, ownership changed once, and the recipient equipped the same
serial `FW-REVO-6AA86F32-E89E28-0002` with its high-velocity ammunition type,
empty ammo state, zero attachments, and condition `100` intact. Release smoke
remained `8/8` for the sender with no active slots.
The recipient then unequipped and returned item `4889`. The transfer observer
passed `7/7` with `count=2`, distinct source and recipient owners, and no failed
observations or lease violations. The original player re-equipped the unchanged
serial with high-velocity ammunition selected, zero rounds, zero attachments,
and condition `100`.
After restarting `feather-weapons`, the returned item restored to the original
owner at generation `1` with the same serial and high-velocity ammunition type.
Release smoke passed `8/8` and the restored primary lease passed `5/5`.
The first explicit terminal transition is now a trusted server-only destruction
operation. It requires exact character ownership, instance ID, expected serial,
valid weapon metadata, no active lease, no administrative hold, an allowlisted
calling resource, and optional Core authorization before Inventory atomically
deletes the instance and emits its committed audit facts.
Live validation uses a development-only, server-console command requiring the
player source, exact instance ID, exact serial, and a literal `DESTROY` token.
Its companion audit smoke test is read-only.
Live destruction validation passed for disposable item `4938`, serial
`FW-REVO-6AA8A2CA-4EF025-0001`. The exact instance was removed, the terminal
audit retained its serial and former character owner, destruction audit smoke
passed `6/6`, and release smoke remained `8/8` with one active slot.
Live validation passed `9/9` after an unequipped drop/pickup round trip for item
`4889`: ordinary movement remained allowed, evidence and disabled policy cases
were rejected, and observation health remained at zero failures and zero lease
violations. Release smoke remained `8/8` with no active slots.
Portable-container validation passed with `bcc-stashes` for item `13`, serial
`FW-REVO-6AA9F510-323164-0001`. An equipped deposit was rejected; after
unequipping, the committed move classified as `deposit` with no observation
failure or active-lease violation. The stored weapon survived both Weapons and
Stashes resource restarts, blocked chest pickup while present, and classified
the return move as `pickup`. Re-equipping restored the same item and serial,
regular ammunition at `50/6/44`, condition `100`, and zero attachments with an
exact native total and clip. The generic ownership smoke remained `10/11` only
because its independent ground-drop prerequisite was not performed after the
resource restart.

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

### Current foundation evidence

- The append-only `feather_weapon_events` ledger passed its `6/6` read-only
  contract smoke test. A live item `13` round trip recorded ordered `deposit`
  and `pickup` facts with serial `FW-REVO-6AA9F510-323164-0001`, exact
  inventory/character endpoints, and a resolvable current instance.
- A trusted evidence hold on that same unequipped item committed without
  changing its identity. Equip and ordinary container movement both failed
  closed while held. Trusted release restored both operations, and the next
  storage deposit succeeded. Inspection returned the complete ordered chain:
  `deposit`, `pickup`, `evidence_hold`, `evidence_release`, `deposit`.
- Confiscation presentation, officer permissions, evidence-locker selection,
  and retention policy remain consumers of these contracts and intentionally
  stay outside Weapons until a law/Admin resource owns those decisions.
- Fresh issuance and terminal history passed with disposable Cattleman item
  `64`, serial `FW-REVO-6AAA063C-0263D4-0001`. Inspection first resolved one
  `issuance` event and the current canonical instance. Trusted exact-item
  destruction then removed the instance and appended a `destruction` event;
  subsequent inspection returned `current=false`, `destroyed=true`, and both
  immutable events with the same item and serial.
- Final regression remained green: destruction audit `6/6`, provenance
  contract `6/6`, evidence contract `6/6`, and release contract `8/8`.

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

### Current foundation evidence

- Cross-resource issuance now derives the caller from the Cfx runtime, requires
  a configured trusted resource and allowlisted purpose, and can route through
  Core action `weapons.issuance.issue` for future license/job/shop policy.
  The read-only issuance contract passed `7/7`, including untrusted and
  incomplete-request rejection.
- The trusted development path issued disposable Cattleman item `65`, serial
  `FW-REVO-6AAA0D42-206177-0001`, with exactly one durable `issuance` event and
  the correct target character/inventory. Exact-item destruction then removed
  the disposable instance, and the release regression remained `8/8`.
- Durable issuance idempotency passed `9/9`. Two trusted `admin_issue` calls
  using request ID `idempotency-test-001` returned the same canonical item
  `66` and serial `FW-REVO-6AAA0FD7-08CED4-0001`; the retry reported
  `replayed=true`, Inventory contained exactly one instance, and exact-item
  cleanup succeeded. Non-development issuance now requires a stable request ID
  and persists pending/committed request state across resource restarts.
- Issuance request keys are now permanently bound to their original character,
  weapon definition, and purpose. Strict request-ID validation rejects
  malformed or oversized keys instead of truncating them; the expanded
  read-only issuance contract passed `13/13`.
- Interrupted issuance recovery passed across a real Weapons restart. Request
  `recovery-restart-001` created Cattleman item `68`, serial
  `FW-REVO-6AAA1951-5DF238-0001`, then stopped before committing its issuance
  reservation. Retrying the same request after restart found exactly one
  canonical metadata match and returned that item with `replayed=true` and
  `recovered=true`; no duplicate was created. Exact-item cleanup then passed.
  Requests created during the current process remain non-recoverable while
  active, preserving concurrent retry rejection, and missing or ambiguous
  recovery matches fail closed.

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
- Distinct sidearm ammo pools preserve each weapon's approved total and display
  the same quantities in runtime diagnostics and the native weapon wheel.
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

### Current distinct-ammo test findings

- Release contract smoke test passed `8/8` again on the test server after the
  native probe was disabled and a primary weapon was equipped. The intervening
  `6/8` result was fully explained by those two test preconditions.
- Dual-slot contract smoke testing exposed a false failure in primary-only
  configurations: the capability check required offhand mode to be enabled
  even though it is an intentional server-owner policy. The check now requires
  the public capability to report a boolean; the separate policy validation
  still verifies the offhand configuration. The live rerun passed `17/17` with
  a primary weapon equipped and offhand mode disabled.
- Runtime lease smoke testing passed `5/5`; the current lease was accepted and
  stale-generation, foreign-item, and foreign-session checks all failed closed.
- Cattleman high velocity restored at 50 approved/native rounds; Schofield
  regular restored at 69 approved but 63 native/wheel rounds.
- One Schofield shot and holster reload conserved its approved budget.
  Unload returned all remaining 68 regular rounds to Inventory.
- After unload, Schofield had zero approved rounds but the regular native pool
  retained six. Empty-hand fallback removed its native weapon; the six remained
  immediately after setting the pool to zero and after selecting Cattleman.
- One Cattleman shot reduced its approved/native total to 49; the regular pool
  stayed at six. Opening the menu failed with `Native pair ammunition state is
  invalid.` The native cleanup attempt has not passed live validation.
- Pair restore now clears both weapon-hash ammo caches before granting either
  hand, matching the existing single-weapon preparation. This change awaits
  live validation. The restart test still produced a residual matching the
  primary's restored clip (five rounds); the cache reset did not resolve it.
- Reloading Cattleman increased its native clip from five to six while the
  regular pool stayed at five and the invalid checkpoint prevented the loaded
  metadata update. Repeating ammo selection immediately before each clip write
  also failed the restart test and has been removed. Development diagnostics
  now capture both pools, actual selected ammo hashes, clip reads, and setter
  results before/after each first-attempt clip write to locate the first divergence.
- Clip-write diagnostics located the divergence: Cattleman's actual selection
  was regular despite its approved high-velocity type; writing its clip added
  five regular rounds. A two-second selection gate failed closed with that
  mismatch. Distinct pools are now seeded from approved totals before selection,
  rather than leaving special ammunition unavailable until afterward. The gate
  remains; this ordering change requires the next live restart test.
- Seeding before selection also failed. Both existing weapon GUIDs resolved and
  the inventory ammo setter was called, but hash-based readback still reported
  regular for Cattleman. Resolution success is not selection success. Added
  immediate GUID-based versus hash-based readback to test whether they disagree;
  the readiness guard remains unchanged pending that evidence.
- GUID readback confirmed high velocity for Cattleman while hash readback stayed
  regular. Activating the existing different-hash weapons by GUID was rejected
  by live testing: both weapons disappeared from the hash-addressable clip
  surface and restore failed closed. Production now leaves their established
  attach points alone after GUID ammo selection.
- Distinct-sidearm readiness now follows the per-weapon GUID that was mutated.
  The misleading hash readback remains diagnostic only for these pairs; it no
  longer rejects a GUID selection already verified as correct. Long-gun pairs
  retain their hash-based readiness check. Native clip, pool, and wheel
  accounting for this change still require live validation.
- With Cattleman high velocity at `49/5` and an empty Schofield regular equipped,
  both GUID ammo selections verified correctly. The attempted GUID activation
  then made both clip reads/writes unavailable; cleanup left both server leases
  intact with zero native totals. Removing that activation awaits restart
  validation.
- The no-activation restart restored both hashes and clips successfully. It also
  confirmed RedM mirrors Cattleman's five-round special clip into the regular
  pool even while the Schofield owns zero rounds. A follow-up showed the native
  per-GUID total getter mirrors the same false value, so it is not an ownership
  authority either. Distinct-pair aggregate observation now uses approved item
  escrow minus confirmed per-weapon clip consumption. Native totals remain
  diagnostic only and cannot invalidate a checkpoint or create ownership. Live
  validation of the bounded aggregate is pending.
- The bounded aggregate restart passed for the empty-offhand case: Cattleman
  high velocity restored at `49/5`, Schofield regular at `0/0`, and the pair
  reported the authorized total `49` despite RedM continuing to display the
  five-round regular-pool mirror. The next checkpoint/menu test is pending.
- The slot-specific ammunition menu then opened successfully with that same
  mirrored pool state, confirming the bounded aggregate no longer triggers
  `Native pair ammunition state is invalid.` before menu availability.
- Loading one regular stack into the empty Schofield succeeded at `50/6/44`;
  Cattleman remained high velocity at `49/5/44`, and the pair reported the
  correct authorized total `99`. RedM's regular pool reported `61`, an excess
  of `11` equal to both materialized clips (`5 + 6`), further confirming that
  native pool totals cannot represent distinct-item ownership. The ammunition
  menu displayed the correct Schofield counts from approved state.
- The following `weaponstate` snapshot agreed with persisted state for both
  items and clips and reported the bounded pair total `99` with `0/0` pending
  consumption. The coordinator continued to expose regular `61` as its native
  ceiling only, not as owned ammunition.
- One Schofield/offhand shot was attributed only to that item: Schofield moved
  from `50/6` to `49/5`, Cattleman remained `49/5`, and the bounded pair total
  moved from `99` to `98`. No cross-type or double consumption was observed.
- One Cattleman/primary shot was likewise isolated: Cattleman moved from `49/5`
  to `48/4`. During the hand transition RedM natively refilled Schofield from
  its own reserve (`49/5/44` to `49/6/43`) without changing its total. The
  bounded pair total correctly moved from `98` to `97`.
- Unloading the Schofield returned its remaining `49` regular cartridges to
  Inventory (`18` to `67`) and left the item at `0/0/0`; Cattleman remained
  `48/4/44`. Pair restoration/fallback reported total `48`, and the ammunition
  menu remained usable despite RedM's four-round mirrored regular pool.
- Reloading one regular stack returned Schofield to `50/6/44`, preserved
  Cattleman at `48/4/44`, and produced the correct bounded pair total `98`.
  The regular pool excess was `10`, exactly the two live clips (`4 + 6`), while
  the slot menu continued to display approved counts.
- A resource restart with both weapons funded restored Cattleman high velocity
  exactly at `48/4/44`, Schofield regular at `50/6/44`, and the bounded pair
  aggregate at `98`. Both clip APIs remained available and no GUID activation
  failure recurred; the expected ten-round native regular-pool mirror remained
  diagnostic only.
- The post-restart `weaponstate` snapshot matched both persisted items and
  readable clips exactly and reported pair total `98` with `0/0` pending
  consumption.
- Logout checkpoint passed at aggregate `98`, and reselecting the same character
  restored both exact clips (`4/6`) and item totals (`48/50`). Schofield was
  unavailable on the first clip write but became readable within the bounded
  retry. Its regular native pool settled at `54` rather than the resource
  restart's `60`, additional evidence that this pool is presentation state and
  not an ownership total.
- The post-reselection `weaponstate` snapshot again matched Cattleman `48/4/44`,
  Schofield `50/6/44`, pair total `98`, and `0/0` pending consumption.
- Native wheel inspection showed Cattleman correctly at `48` high velocity but
  Schofield incorrectly at `54` regular, exactly the Cattleman clip mirror.
  Post-materialization removal did not lower the pool. Restore now clears the
  temporary selection seed while both clips are empty, but live testing showed
  that removal invalidated the weapon surface and cleanup ran before clip writes.
  Restore now avoids removal: immediately after grant it pre-seeds each pool at
  its approved total minus every clip RedM's hash readback says it will credit
  there, then performs GUID selection. In this case regular should begin at
  `40`, receive `4 + 6`, and settle at `50`. Persisted escrow remains independent.
  Live validation passed: regular progressed `40 -> 44 -> 50`, high velocity
  remained `48`, both settled pool deltas were zero, both clips remained `4/6`,
  and the bounded pair aggregate restored at `98`. Native wheel inspection also
  passed exactly: Cattleman displayed `48` high velocity and Schofield displayed
  `50` regular.
- After normalization, one Schofield shot again affected only that item:
  Schofield moved to `49/5/44`, Cattleman stayed `48/4/44`, the pair total became
  `97`, and the regular native pool observed `49` without recreating an excess.
- Native wheel quantities after that shot remained synchronized at Cattleman
  `48` and Schofield `49`.
- A following Cattleman shot moved only Cattleman to `47/3/44`. RedM refilled
  Schofield from its own reserve to `49/6/43` without changing that item's total;
  pair total became `96` and the regular pool remained correctly bounded at `49`.
- Native wheel quantities remained synchronized after that transition at
  Cattleman `47` and Schofield `49`.
- A subsequent resource restart conserved both totals and restored zero pool
  deltas at Cattleman `47` and Schofield `49`, pair total `96`. RedM refilled
  the Cattleman cylinder from `3` to `6` during the resource-stop checkpoint,
  so restore correctly used `6/6`; this redistributed its own reserve without
  changing either item's total or ammunition type.
- The post-restart state snapshot confirmed Cattleman `47/6/41`, Schofield
  `49/6/43`, exact native pools `47/49`, pair total `96`, and `0/0` pending
  consumption.
- The release contract regression gate passed `8/8` with the funded
  distinct-ammo pair active.
- The dual-slot regression gate passed `17/17` with primary item `1` and
  offhand item `299` active and independently lease-scoped.
- The final runtime lease regression gate passed `5/5`; all baseline release
  gates therefore remained green after the distinct-ammo fix: runtime `5/5`,
  dual-slot `17/17`, and release `8/8`.
- Reverse-order setup also passed: after unloading both items, Schofield was
  equipped primary with `50/6` regular and Cattleman offhand with `50/6` high
  velocity. The ammunition menu and native wheel both displayed exact totals
  and types for each weapon.
- One reverse-order Schofield/primary shot was attributed only to that item:
  Schofield moved to `49/5/44`, Cattleman remained `50/6/44`, both native pools
  matched their approved totals, and pair total became `99`.
- One reverse-order Cattleman/offhand shot moved only Cattleman to `49/5/44`.
  Schofield natively refilled from its own reserve to `49/6/43`; both pools
  remained at `49`, with no cross-type transfer, and pair total became `98`.
- The native wheel remained synchronized after both reverse-order shots at
  Schofield `49` and Cattleman `49`.
- Reverse-order resource restart passed: Schofield regular and Cattleman high
  velocity each restored at `49/6`, both native pools settled at `49` with zero
  delta, and pair total remained `98`. This closes both equip orders for the
  focused Cattleman/Schofield distinct-ammo case.
- Unloading both reverse-order weapons back-to-back exposed a transient restore
  failure: after the first unload/fallback, Cattleman's GUID briefly reverted to
  regular during the second restore and the ammunition activity page remained
  waiting. The bounded readiness loop now reapplies the approved ammo type to
  any mismatched GUID on each retry, without activating or moving the weapon.
  Live retry validation is pending.
- The retry still could not select Cattleman high velocity after both unloads
  had completed because its approved special-ammo pool was correctly empty.
  Zero-round weapons now bypass native type readiness: their persisted selected
  definition remains authoritative, no clip or ammunition can be converted,
  and normal GUID readiness resumes when a later load makes the type available.
  Empty-pair restart validation is pending.
- Empty-pair restart validation passed: Schofield retained regular and Cattleman
  retained high velocity, both restored with zero pools and clips, all deltas
  were zero, and the pair aggregate was `0`.
- The ammunition menu opened normally after that restore and displayed both
  reverse-order weapons at `0/0`; the prior indefinitely waiting activity page
  did not recur.
- The representative pistol setup equipped an empty Volcanic primary and Mauser
  offhand. Loading Volcanic high velocity produced exact approved/native counts
  `50/8`; GUID readback matched high velocity while hash readback remained
  regular, consistent with the revolver behavior. The native wheel displayed
  `50` but omitted the ammunition-type label, so pistol wheel labeling remains
  a presentation check rather than evidence of selection failure.
- `weaponstate` confirmed Volcanic high velocity at `50/8/42`, empty Mauser
  regular at `0/0/0`, and authoritative pair total `50`. The observed eight-round
  regular pool was the Volcanic clip mirror only and did not affect ownership.
- Loading Mauser regular produced approved `50/10/40`, but its native pool and
  wheel showed `40`; after one shot they showed `39` while the item correctly
  became `49/9/40`. Unlike the revolvers, Mauser's readable clip was not credited
  to its pool. Restore now adds only a measured post-materialization deficit by
  ammo type and requires both pools to equal their approved totals before
  succeeding. Persisted ownership is unchanged.
- Pistol resource-restart validation passed at Volcanic high velocity `50/8`
  and Mauser regular `49/10`, with both pool deltas zero and pair total `99`.
  On this restore Mauser's clip credited normally, so the bounded deficit path
  made no unnecessary adjustment. Initial-load deficit validation remains.
- Post-restart native wheel quantities matched persisted pistol totals exactly:
  Volcanic `50` and Mauser `49`.
- Unloading Mauser to zero exposed an empty-counterpart edge: Volcanic's funded
  eight-round clip was mirrored into the empty regular pool, so the exact
  funded-pool guard rejected restore. Empty pools now tolerate this
  presentation-only excess while retaining zero ownership; funded pools still
  require exact equality. Pair-restore failure is also propagated to
  reconciliation callers so ammunition-menu activity always terminates. The
  ammunition menu subsequently reopened normally, closing the callback-hang
  regression.
- Empty Mauser restart then showed that RedM may omit the clip handle entirely
  for an authorized `0/0` pistol. Pair readiness now accepts an absent clip only
  when that item's approved total and loaded count are both zero. Every funded
  or nonzero-loaded weapon still requires an exact readable clip. Live restart
  validation passed: the pair restored at Volcanic `50/8` and Mauser `0/0`, the
  empty regular pool's mirrored eight rounds were treated as presentation-only,
  and fallback completed with Volcanic high velocity selected. The restart no
  longer stalls on the empty Mauser clip handle.
- Reloading Mauser regular from `0/0` passed: its clip materialized at `10`, the
  regular pool reached the approved `50` with zero delta, Volcanic high velocity
  remained exactly `50/8`, the slot menu showed `10/50`, the native wheel showed
  `50`, and pair total settled at `100`. RedM credited the delayed clip during
  this run, so no measured deficit adjustment was needed.
- One Mauser shot was attributed only to the regular-ammo item: Mauser moved to
  `49/9/40`, its native pool and wheel both showed `49`, Volcanic remained high
  velocity at `50/8/42`, and pair total became `99`.
- A native Mauser reload occurred while the weapon was holstered and conserved
  ownership: Mauser remained total `49` while moving to `10/39`, its wheel
  count stayed `49`, and Volcanic remained unchanged at `50/8/42`.
- One Volcanic/primary shot was independently attributed to its high-velocity
  item: Volcanic moved to `49/7/42`, Mauser remained regular at `49/10/39`,
  both native wheel counts were `49`, and pair total became `98`.
- A native Volcanic reload conserved its total while moving to `49/8/41`;
  Mauser remained `49/10/39`, both type pools remained exactly `49`, and pair
  total remained `98`.
- Unloading all Volcanic ammunition completed without an activity-page hang.
  Its high-velocity pool settled at `0/0/0`; Mauser remained `49/10/39` regular
  and was promoted natively from offhand to the primary holster. Persisted slot
  identities remained Volcanic primary and Mauser offhand, as intended, while
  the authoritative pair total became `49`.
- Reloading the depleted Volcanic immediately after Mauser had been promoted
  exposed a native slot-transition race. Volcanic's `50/8` clip materialized,
  but the still-promoted Mauser had no readable offhand clip, so reconciliation
  safely rolled back and the menu returned without hanging. Pair rebuilds from
  single-weapon fallback now wait one bounded native transition after removal
  before recreating the persisted primary/offhand layout. Live retry validation
  is pending.
- A subsequent cold resource restart reproduced the missing Mauser offhand clip
  without an active fallback marker, proving the race is general native clip
  materialization rather than only removal timing. Bounded pair readiness now
  selects any unready weapon at its persisted attach point before retrying the
  clip write. Server authority retained Volcanic `50` and Mauser `49`; the failed
  presentation restore cleared only native weapons.
- Cold-restart retry passed with both pistols in their persisted holsters.
  Mauser initially had no hash-addressable clip and exposed only its `39`
  reserve rounds; the new attach-point activation materialized its `10`-round
  clip, then the bounded measured-deficit path brought only the regular pool
  to its approved `49`. Volcanic remained high velocity `50/8`, both pool
  deltas settled at zero, and pair total restored at `99`.
- Post-restart `weaponstate` and native wheel verification passed exactly:
  Volcanic high velocity was `50/8/42`, Mauser regular was `49/10/39`, their
  wheel totals were `50` and `49`, and the authoritative pair total was `99`.
- Final post-fix contract gate passed on the target server: release `8/8`,
  dual-slot `17/17` with Volcanic primary/Mauser offhand, and runtime lease
  `5/5`. The distinct-ammunition revolver and representative pistol regression
  slices are closed.
- Post-LeMat contract gates also remained fully passing after the single-clip
  readiness and mode-transition fixes: release `8/8`, dual-slot `17/17`, and
  runtime lease `5/5`.
- Sawed-Off per-model validation began successfully: an empty
  `shotgun_sawedoff` occupied the primary sidearm holster, appeared under its
  correct native wheel name at zero ammunition, and reached native readiness.
- Loading Sawed-Off with regular shells passed: the ammunition activity closed,
  menu state was `2/48/50`, the wheel showed `50`, and native readiness matched
  the configured two-shell capacity.
- One Sawed-Off shot checkpointed exactly one shell: authoritative/native state
  became `49/1/48`, and condition decreased from `100` to `99`.
- Native Sawed-Off reload conserved total and restored the chamber to
  `49/2/47`; condition remained `99` and native state matched authority.
- Gun-oil repair at Sawed-Off condition `99` consumed exactly one kit, returned
  condition to `100`, and preserved ammunition at `49/2/47`.
- Switching Sawed-Off to slugs passed at `50/2/48`: the menu displayed the Slug
  type, native readiness was exact, and the wheel showed total `50`. As with
  other single sidearms, the native wheel omitted the ammo-type label.
- One Sawed-Off slug shot checkpointed one round; stable state became
  `49/1/48`, the slug type remained selected, native total/clip matched, and
  condition settled at `99`.
- Sawed-Off slug resource restart and logout/reselection both passed. Logout
  checkpointed `49/1`; reselection restored the primary holster, native total
  `49`, and one-shell clip exactly.
- Sawed-Off unload-all completed without a menu hang and settled the selected
  slug state at `0/0/0` across menu, wheel, native state, and authority. Its
  focused equip/capacity/fire/reload/repair/type/restart/logout/unload matrix is
  complete.
- Varmint per-model validation began successfully: the empty rifle occupied the
  shoulder longarm slot and appeared correctly on the wheel. Loading regular
  Varmint ammunition closed normally and produced exact `14/36/50` menu/native
  state with wheel total `50`. No tranquilizer option was offered because none
  was owned; the single-weapon wheel omitted the ammunition-type label.
- The first Varmint shot reduced the native clip from `14` to `13`, but no
  checkpoint ran and client authority still reported total `50`. The long-gun
  observer had required sampling both `IsPedShooting` and the selected hash.
  For a shoulder/back weapon whose ammo type is not shared by the other slot,
  it now also derives missed consumption from a lower native ammo-type total.
  Shared-ammo long-gun pairs retain their existing selected-shot attribution.
  Live retry passed after restart: although extra-slot sync does not emit the
  sidearm-style checkpoint line, authoritative `weaponstate` became
  `49/13/36` with native clip `13`, proving exactly one round was persisted.
- Native Varmint reload conserved total at `49` and restored the magazine and
  reserve to `14/35`, with an exact native clip and shoulder attachment.
- Switching Varmint to tranquilizer ammunition passed: the activity closed,
  menu state was `14/36/50` with the correct Tranquilizer label, native grant
  was `50/14`, and the wheel showed total `50` without a type label.
- One tranquilizer shot persisted exactly as `49/13/36`; the wheel showed `49`,
  native type remained `AMMO_22_TRANQUILIZER`, the clip matched at `13`, and
  shoulder attachment remained correct. The animal tranquilizer effect has not
  yet been observed live.
- Native effect validation passed against white-tailed deer. Five tranquilizer
  hits incapacitated the animal and produced a revive prompt; five regular
  Varmint hits on a second deer caused lethal bleeding, no revive prompt, and a
  corpse pickup prompt after death. Final tranquilizer state remained internally
  exact at wheel/total `36`, loaded `9`, reserve `27`, condition `94`, with the
  correct shoulder attachment.
- Varmint resource restart passed with total `36` and tranquilizer type intact.
  RedM had auto-reloaded the holstered rifle to its full fourteen-round magazine,
  so the stable conserved state was `36/14/22` rather than the earlier partial
  `36/9/27`; native and authoritative state matched. Gun-oil repair at condition
  `94` consumed one kit, restored condition `100`, preserved `36/14/22`, and
  retained the shoulder position.
- Varmint logout/reselection passed: the rifle returned on the shoulder with
  tranquilizer total `36` and loaded `14`. The logout diagnostic printed
  `total=nil loaded=nil` because that legacy summary reports only the primary
  sidearm; the checkpoint itself passed and long-gun restoration was exact.
- Varmint unload-all completed without a menu hang and settled the retained
  tranquilizer selection at `0/0/0` with correct shoulder attachment. Its
  focused regular/tranquilizer effects, firing, reload, repair, restart,
  logout, and unload matrix is complete.
- Elephant Rifle validation began successfully: an empty `rifle_elephant`
  occupied the shoulder slot, appeared under the correct wheel name, and showed
  zero ammunition.
- Initial Elephant loading exposed RedM's Nitro Express native ceiling: Feather
  accepted `50/2/48`, while the native wheel/pool held only `20`. The isolated
  long-gun observer then treated the missing 30 as consumption before the cap
  fix, so the test inventory was manually restored by 30 rounds. Nitro Express
  now defines `maxTotal = 20`; live retry loaded exactly `20/2/18`, left 30 of
  50 rounds in Inventory, showed wheel `20`, and closed the activity normally.
- One Elephant Rifle shot persisted exactly as `19/1/18`, with matching native
  clip and correct shoulder attachment.
- After logout/reselection restored `19/2/17`, a second Elephant shot persisted
  `18/1/17` and lowered condition to `99`, enabling the live repair check.
- Elephant gun-oil repair consumed exactly one kit, restored condition `100`,
  and preserved `18/1/17` in the shoulder slot. Unload-all then closed normally,
  returned all 18 remaining rounds (Inventory `30 -> 48`), and settled the
  weapon/menu/wheel at `0/0/0`. The focused Elephant matrix is complete.
- The post-Elephant release smoke test exposed a test-only assumption: active
  metadata required `slots.primary`, so a valid shoulder-only loadout failed.
  The assertion now accepts a consistent empty state or any nonempty combination
  of primary/offhand/shoulder/back slots, requiring `runtimeMatches=true` for
  every active slot. Live retry passed at release `8/8` with one shoulder slot.
- The runtime lease smoke test likewise used only the legacy primary alias, so
  a shoulder-only Elephant loadout produced `0/5` with no generation. It now
  selects the first active named slot and passes that slot into every lease
  acceptance/rejection check. Live retry passed `5/5` with
  `slot=shoulder generation=1`; dual-slot remained `17/17` with the Elephant
  recorded only in the shoulder slot.
- Elephant resource restart passed on the shoulder at exact `19/2/17`.
- Native Elephant reload conserved total and restored `19/2/17`, with the
  two-round native clip and shoulder attachment exact.
- Initial Nitro Express loading exposed RedM's native `20`-round ceiling:
  Feather accepted and displayed `50/2/48`, while the wheel and native pool
  contained only `20`. The ammunition definition now declares `maxTotal = 20`,
  using the existing escrow-maximum validation so future loads, metadata, menu
  limits, and native state share the same cap. Live recovery/reload is pending.
- A subsequent tranquilizer hit on a fox produced no immediate visible effect.
  Ammo accounting remained correct at total `48`; RedM auto-fed the magazine
  back to `13` and reserve became `35`, while condition decreased to `99`.
  A controlled whitetail-deer comparison then confirmed the native special-
  ammo effect: five tranquilizer hits incapacitated the deer and exposed a
  revive prompt, while five regular Varmint hits caused bleeding, rapid death,
  no revive prompt, and then a corpse pickup prompt. Tranquilizer-effect
  validation is closed.
- Sawed-Off resource restart restored the slug state in the primary holster
  with native total `49` and loaded clip `1`, matching persisted `49/1/48`.
- Fresh female-character entitlement validation passed: two different empty
  sidearms equipped in the correct primary/offhand holsters and dual-drew
  without visible wardrobe changes. Removing offhand retained the primary;
  removing primary left authoritative `equipped=false`, with no persistent
  clothing or holster change.
- LeMat per-model validation began successfully: an empty `revolver_lemat`
  equipped in the primary sidearm holster, appeared correctly on the native
  wheel at zero rounds, and reached native single-weapon readiness.
- Loading LeMat with regular revolver ammunition passed: the activity returned,
  the menu showed cylinder/reserve/total `9/41/50`, the native wheel showed
  `50`, and single-weapon readiness reported the expected nine-round cylinder.
- One LeMat revolver shot checkpointed exactly one round: persisted and native
  state became `49/8/41`, the wheel showed `49`, and condition remained `100`.
- LeMat's native reload occurred while holstered and conserved ownership:
  checkpoint and `weaponstate` both showed `49/9/40`, with native total `49`
  and an exact readable nine-round cylinder.
- Switching LeMat from regular to high velocity exposed a transient single-clip
  readiness bug. The menu and wheel initially showed `9/41/50`, but the native
  clip immediately reported zero and the observer persisted `50/0/50`. Single
  restore readiness previously accepted any readable clip; it now requires the
  exact approved loaded count and reasserts that count during bounded retries
  before enabling observation. Live retry passed after resetting the item:
  high velocity remained stable at `50/9/41`, with exact native total and clip
  after observation began.
- One high-velocity LeMat shot and native reload passed: the shot moved the item
  to `49/8/41`, and reload conserved total while restoring `49/9/40`; the high-
  velocity type, native total, and nine-round clip remained exact.
- LeMat resource restart and logout/reselection both restored high velocity at
  `49/9/40` in the correct primary holster. A full-condition gun-oil attempt was
  rejected without consuming the kit or changing weapon state.
- LeMat visually switched between revolver and shotgun-barrel modes while the
  wheel remained at total `49`. RedM exposed the mode animation as transient
  cylinder reads `9 -> 0 -> 1 ... -> 9`, causing redundant loaded-count
  checkpoints even though no ammunition was consumed. The single observer now
  ignores lower LeMat clip reads while its ammo-type total is unchanged; real
  shots still lower total and native reloads may still increase the cylinder.
  Live mode-switch retry passed after restart: no transient checkpoints were
  emitted and the final state remained high velocity `49/9/40`. Single-sidearm
  wheel presentation also continued to omit the ammo-type label; paired
  sidearms display it.
- LeMat resource restart and logout/reselection both passed at high velocity
  `49/9/40`. Logout checkpointed `49/9`, and reselection restored native total
  `49`, loaded `9`, and the correct holstered presentation. Two unrelated
  `feather-menu` network errors appeared during character selection but did not
  interrupt Weapons restoration.
- One revolver-mode LeMat high-velocity shot checkpointed exactly one round:
  authoritative and native state became `49/8/41`, with the selected special
  ammunition type unchanged.
- Shared-ammunition shoulder/back validation began with an empty Springfield in
  the shoulder slot and an attempted empty Bolt Action in back. The server still
  rejected matching native ammo types despite the existing client coordinator,
  atomic pair sync, and explicit validation milestone. That stale equip guard
  was removed. Live validation then equipped Springfield shoulder and Bolt
  Action back with correct names, holsters, and independent empty records.
- Loading both shared-pool rifles produced independent authoritative balances of
  `50/1/49` and `50/5/45`. RedM's wheel displayed `50` beside both weapons
  because they share `AMMO_RIFLE`, but `weaponstate` and server leases retained
  distinct ownership. The shared-pool observer was extended to attribute a
  firing transition even when RedM refilled a single-shot clip before it could
  be sampled, and to treat a selected shared weapon's clip decrease as shot
  evidence when the firing pulse is missed.
- Independent shared-pool firing passed after those observer fixes. Springfield
  consumed one and auto-reloaded to `49/1/48` without changing Bolt Action;
  Bolt Action consumed one to `49/3/46` in the retest without changing
  Springfield. Native controlled reload restored Bolt Action to `49/5/44`.
  Resource restart and logout/reselection preserved both exact records and
  holster positions. Unloading each weapon independently returned all remaining
  ammunition, ending at `0/0/0` for both and exactly `98` regular rifle rounds
  in Inventory. Release, dual-slot, and runtime-lease smoke tests subsequently
  passed `8/8`, `17/17`, and `5/5` with both long-gun slots active. A full client
  quit/reconnect restored Springfield shoulder and Bolt Action back with exact
  empty balances, condition `99`, readable zero clips, and correct visuals.
  A subsequent full server restart produced the same exact shoulder/back state
  and logged a zero-authority shared pool. Shared-ammunition conservation, slot
  isolation, and persistence pass.
- Two-player isolation passed on separate PCs and game accounts. Player 1 used
  a shared-`AMMO_RIFLE` Springfield/Bolt Action shoulder/back pair while Player
  2 used distinct regular-revolver/high-velocity-pistol sidearms. Individual
  and approximately simultaneous shots changed only the firing item; simultaneous
  reloads conserved each total and changed only the selected clip/reserve.
  Player 2 logout/re-entry left Player 1 exact, and the reciprocal Player 1
  logout/re-entry left Player 2 exact. All four leases, ammunition types,
  balances, conditions, and slot positions remained isolated.
- The Cattleman Wide Sight is the first attachment definition beyond the Long
  Barrel. Its verified model-specific component applied visibly and consumed one
  item while preserving weapon identity, lease, `50/6/44` ammunition, and
  condition `100`. Wide Sight and Long Barrel coexisted as separate sight/barrel
  slots through resource restart, logout/re-entry, full server restart, and a
  primary-to-offhand role change. Removal returned one item while retaining the
  Long Barrel; offhand reinstallation consumed it again. Duplicate installation
  was unavailable without consuming an extra item, and the incompatible Mauser
  exposed no install action. The compatibility worksheet records the mapping
  and completed lifecycle. Post-change regression passed release `8/8`,
  dual-slot `17/17`, and runtime lease `5/5` with the modified Cattleman in the
  offhand slot.
- Carbine Repeater focused validation passed in the shoulder slot. Empty equip
  showed the correct name and `0/0/0`; regular ammunition loaded to `50/7/43`,
  fired to `49/6/43`, and reloaded to `49/7/42`. Switching to high velocity
  produced `50/7/43`; firing and reload conserved it at `49/7/42`. Resource
  observation, logout/re-entry, and native clips remained exact. Five further
  shots produced `44/2/42` and condition `99`; one gun oil was consumed,
  restored condition `100`, and RedM auto-reloaded to conserved `44/7/37`.
  Unload-all returned all 44 high-velocity rounds and settled at `0/0/0` while
  retaining the selected ammunition type. The Carbine matrix is complete.
- Lancaster Repeater focused validation passed in the shoulder slot. Empty equip
  was correct; regular ammunition loaded to `49/14/35`. High velocity loaded to
  `43/14/29` after firing and reload, with exact total and clip behavior. The
  first logout exposed a transient native zero clip that was persisted as an
  empty magazine. Long-gun observation now rejects unexplained isolated-pool
  clip decreases when neither firing nor native-total reduction occurred, and
  the final holster settle reasserts approved long-gun clips. Live retry restored
  authoritative and native state exactly at `43/14/29` without a draw reload.
  Unload-all returned all 43 rounds and settled at `0/0/0`. The Lancaster matrix
  is complete.
- Litchfield Repeater focused validation passed in the shoulder slot. Empty equip
  and wheel presentation were correct. Regular ammunition loaded to `48/16/35`,
  fired to `47/15/32`, and high velocity later conserved through fire/reload at
  `42/16/26`. Resource restart restored the exact clip. Five additional shots
  produced `37/11/26` and condition `99`; one gun oil restored condition
  `100` without changing ammunition. Logout/re-entry restored authoritative and
  native state exactly at `37/11/26`. Unload-all returned all 37 rounds and
  settled at `0/0/0`. The Litchfield matrix is complete.
- Evans Repeater focused validation passed in the shoulder slot. Regular
  ammunition loaded to `47/15/32` after one shot and reloaded to `46/26/20`.
  High velocity loaded to `37/26/11`; five shots produced `32/21/11` and
  condition `99`. One gun oil restored condition `100` without changing ammo.
  Resource restart and logout restored `32/21/11` exactly. Unload-all returned
  all 32 rounds and settled at `0/0/0`. The Evans matrix is complete.
- Double-Barreled Shotgun focused validation passed in the shoulder slot,
  including its logout/reselection lifecycle. The final slug unload-all began
  at `48/2/46`, returned all 48 remaining slugs to Inventory, retained the slug
  selection, and settled the menu, authoritative state, and readable native
  clip at `0/0/0` with the correct shoulder attachment. The Double-Barreled
  Shotgun matrix is complete.
- Pump-Action Shotgun focused validation passed in the shoulder slot. Regular
  ammunition loaded to `48/5/43`, fired to `47/4/43`, and reloaded to
  `47/5/42`; gun oil restored condition from `99` to `100` without changing
  ammunition. Switching to slugs produced `48/5/43`, and slug firing/reload
  conserved the item at `47/5/42` with condition `99`. Resource restart and
  logout/reselection restored the exact authoritative and native total, clip,
  ammo type, and shoulder placement. The wheel briefly displayed only the
  five-shell clip after restore, then converged to the full native total `47`
  without intervention. Unload-all returned all 47 slugs and settled menu,
  authority, native total, clip, and wheel at `0/0/0`. The Pump-Action matrix
  is complete.
- Semi-Auto Shotgun focused validation passed in the shoulder slot. Regular
  ammunition loaded to `47/5/42`, fired to `46/4/42`, and reloaded to
  `46/5/41`; gun oil restored condition from `99` to `100` without changing
  ammunition. Slugs loaded to `47/5/42`, then firing and reload conserved the
  item at `46/5/41` with condition `99`. Resource restart restored every field
  exactly. Initial logout/reselection retained the authoritative and native
  total `46` and clip `5`, but RedM's wheel exposed only the clip until a
  resource restart recreated the weapon. Isolated long guns are now recreated
  during the delayed character-restore settle; live logout retry restored the
  wheel directly at `46` with exact authority, native pool, clip, ammo type,
  and shoulder placement. Unload-all returned all 46 slugs and settled at
  `0/0/0`. The Semi-Auto matrix is complete.
- Repeating Shotgun focused validation passed in the shoulder slot. Regular
  ammunition loaded to `46/6/40`, fired to `45/5/40`, and auto-reloaded while
  holstered to `45/6/39`; gun oil restored condition from `99` to `100`
  without changing ammunition. Slugs loaded to `46/6/40`, fired to
  `45/5/40`, and auto-reloaded to `45/6/39` with condition `99`. Resource
  restart and logout/reselection restored the exact authoritative and native
  total, six-shell clip, ammo type, wheel quantity, and shoulder placement.
  Unload-all returned all 45 slugs and settled at `0/0/0`. The Repeating
  Shotgun matrix is complete, and all five shipped shotgun models have now
  completed focused validation.
- M1899 Pistol focused validation passed in the primary slot. Regular
  ammunition loaded to `50/8/42`, fired to `49/7/42`, and reloaded to
  `49/8/41`; four further shots reached `45/4/41` and condition `98`, then one
  gun oil restored condition `100` without changing ammunition. Switching to
  high velocity produced `50/8/42`, and firing/reload conserved it at
  `49/8/41`. Resource restart and logout/reselection restored the exact ammo
  type, total, clip, condition, and primary holster. Unload-all returned all
  49 high-velocity rounds and settled at `0/0/0`. The M1899 matrix is complete.
- Semi-Automatic Pistol focused validation passed in the primary slot. Regular
  ammunition loaded to `45/8/37`, fired to `44/7/37`, and reloaded to
  `44/8/36`; four further shots reached `40/4/36` and condition `98`, then one
  gun oil restored condition `100` without changing ammunition. High velocity
  loaded to `49/8/41`, fired to `48/7/41`, and reloaded to `48/8/40`.
  Resource restart and logout/reselection restored the exact ammo type, total,
  clip, condition, and primary holster. Unload-all returned all 48
  high-velocity rounds and settled at `0/0/0`. The Semi-Automatic Pistol matrix
  is complete.
- Double-Action Revolver focused validation passed in the primary slot. Regular
  ammunition loaded to `50/6/44`, fired to `49/5/44`, and reloaded to
  `49/6/43`; four further shots reached `45/2/43` and condition `98`, then one
  gun oil restored condition `100` without changing ammunition. High velocity
  loaded to `50/6/44`, fired to `49/5/44`, and reloaded to `49/6/43`.
  Resource restart restored exactly. Initial logout/reselection retained the
  authoritative and native total but exposed only the six-round clip on the
  wheel. The delayed character-restore recreation was extended from isolated
  long guns to single sidearms; live retry restored wheel `49` directly with
  exact ammo, clip, condition, type, and holster placement. Unload-all returned
  all 49 high-velocity rounds and settled at `0/0/0`. The Double-Action matrix
  is complete.
- Navy Revolver focused validation passed in the primary slot. Regular
  ammunition loaded to `45/6/39`, fired to `44/5/39`, and reloaded to
  `44/6/38`; four further shots reached `40/2/38` and condition `98`, then gun
  oil restored condition `100` without changing ammunition. High velocity
  loaded to `49/6/43`, fired to `48/5/43`, and reloaded to `48/6/42`.
  Resource restart and logout/reselection restored the exact ammo type, total,
  clip, condition, wheel quantity, and primary holster. Unload-all returned all
  48 high-velocity rounds and settled at `0/0/0`. The Navy matrix is complete.
- Rolling Block Rifle focused validation passed in the shoulder slot. Regular
  ammunition loaded to `50/1/49`; five fired rounds auto-reloaded correctly to
  `45/1/44` and reduced condition to `98`, then gun oil restored condition
  `100` without changing ammunition. High velocity loaded to `50/1/49`, fired,
  and auto-reloaded to `49/1/48`. Resource restart and logout/reselection
  restored the exact ammo type, total, single-round chamber, condition, wheel
  quantity, and shoulder placement. Unload-all returned all 49 high-velocity
  rounds and settled at `0/0/0`. The Rolling Block matrix is complete.
- Carcano Rifle focused validation passed in the shoulder slot. Regular
  ammunition loaded to `50/6/44`, fired to `49/5/44`, and reloaded to
  `49/6/43`; four further shots reached `45/2/43` and condition `98`, then gun
  oil restored condition `100` without changing ammunition. High velocity
  loaded to `49/6/43`, fired to `48/5/43`, and reloaded to `48/6/42`.
  Resource restart and logout/reselection restored exact authority, native
  total, clip, ammo type, condition, wheel quantity, and shoulder placement.
  Unload-all returned all 48 high-velocity rounds and settled at `0/0/0`. The
  Carcano matrix is complete.
- Post-catalog and post-wheel-cache-fix regression gates passed on the target
  server with an empty Carcano active in the shoulder slot: release `8/8`,
  dual-slot `17/17`, and runtime lease `5/5`. The lease gate selected
  `slot=shoulder generation=1`; every stale-generation, foreign-item, and
  foreign-session attempt failed closed.
- The remaining per-model repair gaps passed. Gun oil restored Volcanic
  `96 -> 100` while preserving `32/8/24`, Mauser `97 -> 100` at `25/10/15`,
  modified Cattleman `98 -> 100` at `34/6/28` while retaining both Long Barrel
  and Wide Sight, Schofield `98 -> 100` at `28/6/22`, and Springfield
  `96 -> 100` at `46/1/45` with its shoulder placement intact. Bolt Action
  repair restored `99 -> 100` while conserving its empty `0/0/0` state and
  shoulder placement. Each repair consumed exactly one gun oil. Successful
  repair coverage is now complete across the shipped firearm catalog.
- Final post-fix regression passed with the repaired empty Bolt Action active
  in the shoulder slot: release `8/8`, dual-slot `17/17`, and runtime lease
  `5/5` at `slot=shoulder generation=8`. This run includes both delayed
  character-restore recreation paths: isolated long guns and single sidearms.

### Next steps

1. Keep `WeaponReleaseContractSmokeTest` at `8/8` and
   `WeaponDualSlotContractSmokeTest` at `17/17` on the target server build.
2. [x] Complete distinct-ammunition dual-sidearm validation in both equip
   orders with representative revolver and pistol pairs, including partial and
   empty clips, fallback/re-pair, firing, reload, logout, and resource restart.
3. [x] Complete the fresh female-character offhand entitlement and cleanup check.
4. [x] Complete the per-model live matrix: Admin grant, equip, fire, native reload,
   unload, gun-oil repair, logout/reselection, and resource restart.
5. [x] Verify clip capacity, holster placement, wheel behavior, and special-ammo
   effects for each firearm family, with focused checks for LeMat, Sawed-Off,
   Varmint, Elephant Rifle, and long guns.
6. [x] Repeat representative family checks with two simultaneous players and
   supported different-hash sidearm pairs, covering both shared and distinct
   native ammunition types.
7. [x] Complete shared-ammunition shoulder/back restoration, independent firing
   and reload, escrow conservation, wheel/holster presentation, logout, client
   quit, resource restart, and full-server-restart validation.
8. [x] Build the attachment compatibility worksheet and add one fully tested
   component vertical slice beyond the Cattleman Long Barrel.
9. [x] Run `WeaponAttachmentContractSmokeTest` against unmodified, modified,
   holstered, offhand, distinct-instance, logout, and resource-restart states.
