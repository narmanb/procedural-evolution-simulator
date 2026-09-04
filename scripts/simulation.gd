class_name EvolutionSimulation
extends RefCounted

const WORLD_SIZE := Vector2(1280.0, 720.0)
const INITIAL_CREATURES := 58
const INITIAL_FOOD_PATCHES := 105
const MAX_CREATURES := 650

var rng := RandomNumberGenerator.new()
var seed_value: int = 1
var organisms: Array[Organism] = []
var food_patches: Array[FoodPatch] = []
var lineage_archive: Dictionary = {}
var event_log: Array[Dictionary] = []

var elapsed_sim_time: float = 0.0
var next_organism_id: int = 1
var births: int = 0
var deaths: int = 0
var max_generation: int = 0
var mutation_multiplier: float = 1.0

func reset(p_seed: int = 0) -> void:
    organisms.clear()
    food_patches.clear()
    lineage_archive.clear()
    event_log.clear()
    elapsed_sim_time = 0.0
    next_organism_id = 1
    births = 0
    deaths = 0
    max_generation = 0

    if p_seed == 0:
        rng.randomize()
        seed_value = rng.seed
    else:
        seed_value = p_seed
        rng.seed = p_seed

    _create_food_field()
    _create_ancestral_population()
    _record_event("origin", "Ancestral population established")

func _create_food_field() -> void:
    # Plants are persistent producers with local carrying capacity. Food is not
    # spawned under hungry creatures; overgrazing can genuinely deplete areas.
    for i in range(INITIAL_FOOD_PATCHES):
        var margin := 48.0
        var p := Vector2(
            rng.randf_range(margin, WORLD_SIZE.x - margin),
            rng.randf_range(100.0, WORLD_SIZE.y - margin)
        )
        var capacity := rng.randf_range(18.0, 55.0)
        var regrowth := rng.randf_range(0.45, 1.15)
        food_patches.append(FoodPatch.new(p, capacity, regrowth, rng.randf_range(0.0, TAU)))

func _create_ancestral_population() -> void:
    var founder := Genome.ancestral(rng)
    for i in range(INITIAL_CREATURES):
        var genome := founder.mutated_copy(rng, 0.85)
        var p := Vector2(
            rng.randf_range(110.0, WORLD_SIZE.x - 110.0),
            rng.randf_range(140.0, WORLD_SIZE.y - 80.0)
        )
        var org := _new_organism(genome, p, 0, -1)
        org.energy = genome.max_energy() * rng.randf_range(0.48, 0.82)
        organisms.append(org)

func _new_organism(genome: Genome, p: Vector2, generation: int, parent_id: int) -> Organism:
    var org := Organism.new(next_organism_id, genome, p, generation, parent_id)
    next_organism_id += 1
    org.birth_time = elapsed_sim_time
    lineage_archive[org.id] = {
        "id": org.id,
        "parent_id": parent_id,
        "generation": generation,
        "birth_time": elapsed_sim_time,
        "death_time": -1.0,
        "children": [],
        "genome": _genome_snapshot(genome)
    }
    if parent_id != -1 and lineage_archive.has(parent_id):
        lineage_archive[parent_id]["children"].append(org.id)
    return org

func step(dt: float) -> void:
    elapsed_sim_time += dt

    for patch in food_patches:
        patch.step(dt)

    var newborns: Array[Organism] = []

    for org in organisms:
        if not org.alive:
            continue

        org.age += dt
        org.reproduction_cooldown = maxf(0.0, org.reproduction_cooldown - dt)
        org.think_timer -= dt
        org.wander_timer -= dt

        if org.energy <= 0.0 or org.age >= org.genome.lifespan():
            _kill(org, "starvation" if org.energy <= 0.0 else "old age")
            continue

        _update_behavior(org)
        _move_organism(org, dt)
        _feed_if_possible(org, dt)

        org.energy -= org.genome.basal_energy_cost() * dt
        org.energy -= org.velocity.length() * org.genome.movement_cost_per_unit() * dt

        if _can_reproduce(org) and organisms.size() + newborns.size() < MAX_CREATURES:
            var child := _reproduce(org)
            newborns.append(child)

    if not newborns.is_empty():
        organisms.append_array(newborns)

    for i in range(organisms.size() - 1, -1, -1):
        if not organisms[i].alive:
            organisms.remove_at(i)

    _detect_population_events()

func _update_behavior(org: Organism) -> void:
    if org.think_timer > 0.0:
        return
    org.think_timer = rng.randf_range(0.16, 0.38)

    var hunger := 1.0 - org.energy_ratio()
    var food_index := _find_food(org.position, org.genome.vision_range())

    if hunger > 0.26 and food_index != -1:
        org.target_food_index = food_index
        var target := food_patches[food_index].position
        org.desired_heading = org.position.angle_to_point(target)
        org.behavior = "foraging"
        return

    if org.energy_ratio() >= org.genome.reproduction_threshold() and org.age >= org.genome.maturity_age():
        org.behavior = "seeking breeding energy"
        if food_index != -1:
            org.target_food_index = food_index
            org.desired_heading = org.position.angle_to_point(food_patches[food_index].position)
        return

    org.target_food_index = -1
    org.behavior = "exploring"
    if org.wander_timer <= 0.0:
        org.wander_timer = rng.randf_range(0.45, 1.35)
        org.desired_heading += rng.randf_range(-1.15, 1.15)

func _move_organism(org: Organism, dt: float) -> void:
    var angle_delta := wrapf(org.desired_heading - org.heading, -PI, PI)
    var max_turn := org.genome.turn_rate() * dt
    org.heading += clampf(angle_delta, -max_turn, max_turn)

    var target_speed := org.genome.max_speed()
    if org.behavior == "exploring":
        target_speed *= 0.55
    elif org.energy_ratio() < 0.18:
        target_speed *= 0.62

    var desired_velocity := Vector2.RIGHT.rotated(org.heading) * target_speed
    org.velocity = org.velocity.move_toward(desired_velocity, org.genome.acceleration() * dt)

    var before := org.position
    org.position += org.velocity * dt
    org.distance_traveled += before.distance_to(org.position)

    var radius := org.genome.radius() * 1.8
    if org.position.x < radius:
        org.position.x = radius
        org.heading = 0.0 + rng.randf_range(-0.35, 0.35)
        org.desired_heading = org.heading
    elif org.position.x > WORLD_SIZE.x - radius:
        org.position.x = WORLD_SIZE.x - radius
        org.heading = PI + rng.randf_range(-0.35, 0.35)
        org.desired_heading = org.heading

    if org.position.y < 92.0 + radius:
        org.position.y = 92.0 + radius
        org.heading = PI * 0.5 + rng.randf_range(-0.35, 0.35)
        org.desired_heading = org.heading
    elif org.position.y > WORLD_SIZE.y - radius:
        org.position.y = WORLD_SIZE.y - radius
        org.heading = -PI * 0.5 + rng.randf_range(-0.35, 0.35)
        org.desired_heading = org.heading

func _feed_if_possible(org: Organism, dt: float) -> void:
    if org.target_food_index < 0 or org.target_food_index >= food_patches.size():
        return
    var patch := food_patches[org.target_food_index]
    if patch.biomass <= 0.05:
        org.target_food_index = -1
        return

    var eat_radius := 10.0 + org.genome.radius() * 1.6
    if org.position.distance_squared_to(patch.position) <= eat_radius * eat_radius:
        org.behavior = "feeding"
        var requested := org.genome.bite_rate() * dt
        var eaten := patch.consume(requested)
        # Larger bodies digest more total food but are less efficient per unit mass.
        var efficiency := lerpf(1.15, 0.88, org.genome.body_size)
        org.energy = minf(org.genome.max_energy(), org.energy + eaten * 2.6 * efficiency)
        org.food_consumed += eaten
        org.velocity *= maxf(0.0, 1.0 - 3.0 * dt)

func _find_food(position: Vector2, vision_range: float) -> int:
    var best_index := -1
    var best_d2 := vision_range * vision_range
    for i in range(food_patches.size()):
        var patch := food_patches[i]
        if patch.biomass < 0.8:
            continue
        var d2 := position.distance_squared_to(patch.position)
        if d2 < best_d2:
            best_d2 = d2
            best_index = i
    return best_index

func _can_reproduce(org: Organism) -> bool:
    if org.reproduction_cooldown > 0.0:
        return false
    if org.age < org.genome.maturity_age():
        return false
    if org.energy_ratio() < org.genome.reproduction_threshold():
        return false
    return true

func _reproduce(parent: Organism) -> Organism:
    var child_genome := parent.genome.mutated_copy(rng, mutation_multiplier)
    var offset := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(10.0, 24.0)
    var child := _new_organism(child_genome, parent.position + offset, parent.generation + 1, parent.id)
    child.recent_mutations = child_genome.mutation_summary(parent.genome)

    var investment := parent.genome.max_energy() * parent.genome.offspring_energy_fraction()
    parent.energy -= investment
    child.energy = minf(child.genome.max_energy(), investment * lerpf(0.80, 1.12, parent.genome.offspring_investment_gene))
    parent.offspring_count += 1
    parent.reproduction_cooldown = lerpf(6.5, 13.0, parent.genome.offspring_investment_gene)

    births += 1
    max_generation = maxi(max_generation, child.generation)

    if child.generation > 0 and child.generation % 25 == 0 and child.generation > max_generation - 2:
        _record_event("generation", "Generation %d reached" % child.generation)

    return child

func _kill(org: Organism, cause: String) -> void:
    if not org.alive:
        return
    org.alive = false
    org.death_time = elapsed_sim_time
    deaths += 1
    if lineage_archive.has(org.id):
        lineage_archive[org.id]["death_time"] = elapsed_sim_time
        lineage_archive[org.id]["death_cause"] = cause

func _detect_population_events() -> void:
    if organisms.size() == 0:
        if event_log.is_empty() or event_log.back().get("type", "") != "extinction":
            _record_event("extinction", "The founding ecosystem collapsed")
        return

    # Sparse automatic milestones prove the event-history plumbing without
    # prematurely implementing the full speciation system.
    if organisms.size() >= 180 and not _event_exists("population_180"):
        _record_event("population_180", "Population boom: 180 living organisms")
    if max_generation >= 50 and not _event_exists("generation_50"):
        _record_event("generation_50", "Fifty generations of descent recorded")

func _event_exists(event_type: String) -> bool:
    for event in event_log:
        if event.get("type", "") == event_type:
            return true
    return false

func _record_event(event_type: String, text: String) -> void:
    event_log.append({"time": elapsed_sim_time, "type": event_type, "text": text})

func get_organism_by_id(id: int) -> Organism:
    for org in organisms:
        if org.id == id:
            return org
    return null

func nearest_organism(point: Vector2, max_distance: float = 38.0) -> Organism:
    var best: Organism = null
    var best_d2 := max_distance * max_distance
    for org in organisms:
        var d2 := org.position.distance_squared_to(point)
        if d2 <= best_d2:
            best_d2 = d2
            best = org
    return best

func population_mean_gene(gene_name: String) -> float:
    if organisms.is_empty():
        return 0.0
    var total := 0.0
    for org in organisms:
        total += float(org.genome.get(gene_name))
    return total / float(organisms.size())

func total_food_biomass() -> float:
    var total := 0.0
    for patch in food_patches:
        total += patch.biomass
    return total

func _genome_snapshot(genome: Genome) -> Dictionary:
    var snapshot := {}
    for gene_name in Genome.GENE_NAMES:
        snapshot[gene_name] = genome.get(gene_name)
    return snapshot
