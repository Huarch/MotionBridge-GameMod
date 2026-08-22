# Runtime profile v2

Runtime profiles contain only the semantic geometry needed to compute a motion
snapshot. They never contain an animation phase or a sampled device curve.

Resolution order is: temporary UI override, exact `montage_asset_key` and
optional Section profile, catalog-constrained automatic contact selection, then
`unmapped`. The `roles` in a profile are local to that profile; names such as
MaleA, MaleB, or Alet are not global runtime rules.

`reference` defines an origin and tip bone plus radius/lateral scaling.
`target` defines the sampled effector or contact bone. `axes.invert` is applied
only after the canonical geometric axes have been calculated. Profile changes
must be validated in simulation before they can ever be used by a device layer.
