# Single-weapon special ammunition baseline

Development-server experiment; no production support is implied by its output.
Keep `Config.NativeProbe.enabled = false` for ordinary operation.

1. Unequip every Inventory weapon slot, including shoulder and back. A failed
   native restore does not release the server equipment state.
2. Enable `Config.DevMode` and `Config.NativeProbe.enabled` on the development
   server. Keep the probe's Cattleman and regular ammunition defaults. Restart
   the resource after deploying the updated probe.
3. Run `WeaponNativeProbeSpecial` in F8. It refuses if server state is unavailable
   or any server/local weapon slot is occupied.
4. Send all `[WeaponNativeProbe] special` lines before doing anything else.
   Do not fire or use Inventory weapon actions while the probe is active.
5. Run `WeaponNativeProbeClear` before returning to Inventory weapons. Disable
   the probe after the investigation.

The fixed sequence creates one Cattleman, seeds 12 high-velocity rounds, enables
and requests that type, and activates the weapon without writing a clip.
Draw/reload normally, then run `WeaponNativeProbeStatus` to capture both pools
and the clip after native reload. Do not fire until that baseline is reviewed.
Each immediate snapshot reports the selected type, regular and high-velocity
pools, and clip validity/count. Counts are observations, not acceptance criteria:
this experiment intentionally does not apply production pool compensation.
It does not issue Inventory items or persist test ammunition. Cleanup removes
the test pools and weapon, including on resource stop while no local production
weapon is active. Live behavior and delayed native transitions remain unverified.

The earlier clip-write experiment added three regular rounds despite the wheel
showing 12. One shot reduced the wheel to 11 while the regular/hash totals stayed
at three. Therefore the hash ammo-type readback is not sufficient to conclude
that special selection failed. Production integration remains paused pending
the no-clip-write baseline and direct special-pool conservation checks.
