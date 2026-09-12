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

### Next steps

1. Keep `WeaponReleaseContractSmokeTest` at `8/8` and
   `WeaponDualSlotContractSmokeTest` at `17/17` on the target server build.
2. Extend distinct-ammunition dual-sidearm validation beyond the completed
   Cattleman-high-velocity/Schofield-regular case: reverse the equip/type order,
   exercise partial and empty clips, and repeat with representative pistol and
   revolver combinations. Per-item GUID readiness, adjusted native-pool seeding,
   and the repeatable checklist in `docs/ammunition-types.md` are available.
3. Complete the fresh female-character offhand entitlement and cleanup check.
4. Complete the per-model live matrix: Admin grant, equip, fire, native reload,
   unload, gun-oil repair, logout/reselection, and resource restart.
5. Verify clip capacity, holster placement, wheel behavior, and special-ammo
   effects for each firearm family, with focused checks for LeMat, Sawed-Off,
   Varmint, Elephant Rifle, and long guns.
6. Repeat representative family checks with two simultaneous players and
   supported different-hash sidearm pairs, covering both shared and distinct
   native ammunition types.
7. Complete shared-ammunition shoulder/back restoration, independent firing and
   reload, escrow conservation, wheel/holster presentation, logout, client
   quit, and full-restart validation.
8. After the catalog is accepted, build the attachment compatibility worksheet
   and add one fully tested component vertical slice beyond the Cattleman Long
   Barrel.
