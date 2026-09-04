# Procedural Evolution Simulator

Godot 4 procedural evolution simulation targeting Android landscape play first, with touchscreen and gamepad support.

The initial vertical slice proves the complete loop:

`genome -> phenotype -> visible creature -> behavior -> reproduction -> mutation -> selection -> visibly changed descendants`

## Current vertical slice

- Procedurally generated creature morphology rather than fixed sprites
- Inherited genome and derived phenotype
- Persistent producer/food field with depletion and regrowth
- Hunger-driven food seeking and exploration
- Movement costs, metabolism, aging and starvation
- Reproduction with inherited mutation
- Parent IDs and lineage history foundation
- Time controls from pause through accelerated simulation
- Creature selection/inspection
- Movement trails, vision overlay and food biomass overlay
- Landscape Android configuration
- Initial gamepad time controls

## Android builds

GitHub Actions builds an ARM64 debug APK from the `Android` Godot export preset. Build artifacts are intended for direct installation/testing on Android phones and Retroid Pocket-class handhelds.

## Architecture

Simulation state is intentionally separated from rendering. Organisms are lightweight simulation data rather than one large Godot scene subtree per creature. See `docs/ARCHITECTURE.md` and `docs/ROADMAP.md` for the staged design.
