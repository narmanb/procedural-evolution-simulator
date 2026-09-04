class_name EvolutionSimulation
extends RefCounted

const WORLD_SIZE := Vector2(720.0, 1130.0)
const INITIAL_CREATURES := 14
const MAX_CREATURES := 450
const MAX_FOOD_PATCHES := 700

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
var food_regrowth_multiplier: float = 1.0
var drought_timer: float = 0.0

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
    mutation_multiplier = 1.0
    food_regrowth_multiplier = 1.0
    drought_timer = 0.0

    if p_seed == 0:
        rng.randomize()
        seed_value = rng.seed
    else:
        seed_value = p_seed
        rng.seed = p_seed

    # Deliberately no automatic food. The player creates the initial ecology.
    _create_ancestral_population()
    _record_event("origin", "Ancestral population established — no food has been introduced")

func _create_ancestral_population() -> void:
    var founder := Genome.ancestral(rng)
    for i in range(INITIAL_CREATURES):
        var genome := founder.mutated_copy(rng, 1.35)
        var p := Vector2(
            rng.randf_range(80.0, WORLD_SIZE.x - 80.0),
            rng.randf_range(135.0, WORLD_SIZE.y - 90.0)
        )
        var org := _new_organism(genome, p, 0, -1)
        # Give the player time to observe founders before introducing resources.
        org.energy = genome.max_energy() * rng.randf_range(0.82, 0.98)
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
    drought_timer = maxf(0.0, drought_timer - dt)

    var effective_regrowth: float = food_regrowth_multiplier
    if drought_timer > 0.0:
        effective_regrowth *= 0.035

    for patch in food_patches:
        patch.step(dt, effective_regrowth)

    var newborns: Array[Organism] = []

    for org in organisms:
        if not org.alive:
            continue

        org.age += dt
        org.reproduction_cooldown = maxf(0.0, org.reproduction_cooldown - dt)
        org.think_timer -= dt
        org.wander_timer -= dt
        org.feeding_flash_timer = maxf(0.0, org.feeding_flash_timer - dt)

        if org.energy <= 0.0 or org.age >= org.genome.lifespan():
            _kill(org, "starvation" if org.energy <= 0.0 else "old age")
            continue

        _update_behavior(org)
        _move_organism(org, dt)
        _feed_if_possible(org, dt)

        org.energy -= org.genome.basal_energy_cost() * dt
        org.energy -= org.velocity.length() * org.genome.movement_cost_per_unit() * dt

        if _can_reproduce(org) and organisms.size() + newborns.size() < MAX_CREATURES:
            newborns.append(_reproduce(org))

    if not newborns.is_empty():
        organisms.append_array(newborns)

    for i in range(organisms.size() - 1, -1, -1):
        if not organisms[i].alive:
            organisms.remove_at(i)

    _detect_population_events()

func _update_behavior(org: Organism) -> void:
    if org.think_timer > 0.0:
        return
    org.think_timer = rng.randf_range(0.12, 0.30)

    var hunger: float = 1.0 - org.energy_ratio()
    var food_index: int = _find_food(org.position, org.genome.vision_range())

    if hunger > 0.18 and food_index != -1:
        org.target_food_index = food_index
        var target: Vector2 = food_patches[food_index].position
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
    var angle_delta: float = wrapf(org.desired_heading - org.heading, -PI, PI)
    var max_turn: float = org.genome.turn_rate() * dt
    org.heading += clampf(angle_delta, -max_turn, max_turn)

    var target_speed: float = org.genome.max_speed()
    if org.behavior == "exploring":
        target_speed *= 0.55
    elif org.energy_ratio() < 0.18:
        target_speed *= 0.62

    # Arrival steering: brake as food approaches instead of blasting through it.
    if org.target_food_index >= 0 and org.target_food_index < food_patches.size():
        var target_patch: FoodPatch = food_patches[org.target_food_index]
        if target_patch.biomass > 0.05:
            var eat_radius: float = 14.0 + org.genome.radius() * 2.1
            var distance: float = org.position.distance_to(target_patch.position)
            if distance < eat_radius * 3.0:
                var arrival: float = clampf((distance - eat_radius * 0.35) / (eat_radius * 2.65), 0.04, 1.0)
                target_speed *= arrival
            if distance <= eat_radius:
                target_speed = 0.0

    var desired_velocity: Vector2 = Vector2.RIGHT.rotated(org.heading) * target_speed
    org.velocity = org.velocity.move_toward(desired_velocity, org.genome.acceleration() * dt)

    var before: Vector2 = org.position
    org.position += org.velocity * dt
    org.distance_traveled += before.distance_to(org.position)

    var radius: float = org.genome.radius() * 1.8
    if org.position.x < radius:
        org.position.x = radius
        org.heading = rng.randf_range(-0.35, 0.35)
        org.desired_heading = org.heading
    elif org.position.x > WORLD_SIZE.x - radius:
        org.position.x = WORLD_SIZE.x - radius
        org.heading = PI + rng.randf_range(-0.35, 0.35)
        org.desired_heading = org.heading

    if org.position.y < 82.0 + radius:
        org.position.y = 82.0 + radius
        org.heading = PI * 0.5 + rng.randf_range(-0.35, 0.35)
        org.desired_heading = org.heading
    elif org.position.y > WORLD_SIZE.y - radius:
        org.position.y = WORLD_SIZE.y - radius
        org.heading = -PI * 0.5 + rng.randf_range(-0.35, 0.35)
        org.desired_heading = org.heading

func _feed_if_possible(org: Organism, dt: float) -> void:
    if org.target_food_index < 0 or org.target_food_index >= food_patches.size():
        return
    var patch: FoodPatch = food_patches[org.target_food_index]
    if patch.biomass <= 0.05:
        org.target_food_index = -1
        return

    var eat_radius: float = 14.0 + org.genome.radius() * 2.1
    if org.position.distance_squared_to(patch.position) <= eat_radius * eat_radius:
        org.behavior = "feeding"
        # Fast enough that a food clump visibly shrinks over a few seconds.
        var requested: float = org.genome.bite_rate() * dt * 3.2
        var eaten: float = patch.consume(requested)
        if eaten > 0.0:
            var efficiency: float = lerpf(1.15, 0.88, org.genome.body_size)
            org.energy = minf(org.genome.max_energy(), org.energy + eaten * 3.0 * efficiency)
            org.food_consumed += eaten
            org.last_bite_amount = eaten
            org.feeding_flash_timer = 0.24
            org.velocity *= maxf(0.0, 1.0 - 9.0 * dt)
        if patch.biomass <= 0.05:
            org.target_food_index = -1

func _find_food(position: Vector2, vision_range: float) -> int:
    var best_index: int = -1
    var best_d2: float = vision_range * vision_range
    for i in range(food_patches.size()):
        var patch: FoodPatch = food_patches[i]
        if patch.biomass < 0.8:
            continue
        var d2: float = position.distance_squared_to(patch.position)
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
    var offset: Vector2 = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(10.0, 24.0)
    var child := _new_organism(child_genome, _clamp_world(parent.position + offset), parent.generation + 1, parent.id)
    child.recent_mutations = child_genome.mutation_summary(parent.genome)

    var investment: float = parent.genome.max_energy() * parent.genome.offspring_energy_fraction()
    parent.energy -= investment
    child.energy = minf(child.genome.max_energy(), investment * lerpf(0.80, 1.12, parent.genome.offspring_investment_gene))
    parent.offspring_count += 1
    parent.reproduction_cooldown = lerpf(6.5, 13.0, parent.genome.offspring_investment_gene)

    births += 1
    max_generation = maxi(max_generation, child.generation)

    if child.generation > 0 and child.generation % 25 == 0 and child.generation > max_generation - 2:
        _record_event("generation", "Generation %d reached" % child.generation)

    return child

# ---------------- Player laboratory interventions ----------------

func add_food_at(p: Vector2, cluster_size: int = 4) -> void:
    var amount: int = clampi(cluster_size, 1, 12)
    for i in range(amount):
        if food_patches.size() >= MAX_FOOD_PATCHES:
            break
        var spread: float = 0.0 if amount == 1 else rng.randf_range(4.0, 24.0)
        var offset: Vector2 = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * spread
        var position: Vector2 = _clamp_world(p + offset)
        var capacity: float = rng.randf_range(9.0, 22.0)
        # Manual food is finite. Auto-feeding/producers can be layered on later.
        food_patches.append(FoodPatch.new(position, capacity, 0.0, rng.randf_range(0.0, TAU)))

func scatter_food(count: int = 18) -> void:
    var amount: int = clampi(count, 1, 80)
    for i in range(amount):
        if food_patches.size() >= MAX_FOOD_PATCHES:
            break
        var p := Vector2(
            rng.randf_range(40.0, WORLD_SIZE.x - 40.0),
            rng.randf_range(105.0, WORLD_SIZE.y - 40.0)
        )
        add_food_at(p, 1)
    _record_event("intervention", "Player scattered %d food clumps" % amount)

func clear_food() -> void:
    food_patches.clear()
    for org in organisms:
        org.target_food_index = -1
    _record_event("intervention", "All food was removed")

func drop_food_for_organism(id: int) -> bool:
    var org := get_organism_by_id(id)
    if org == null:
        return false
    var drop_position: Vector2 = _clamp_world(org.position + Vector2.RIGHT.rotated(org.heading) * 24.0)
    add_food_at(drop_position, 5)
    org.think_timer = 0.0
    _record_event("intervention", "Food dropped beside creature #%d" % id)
    return true

func trigger_food_bloom() -> void:
    for patch in food_patches:
        patch.bloom(0.62)
    _record_event("intervention", "Player replenished existing food")

func trigger_drought(duration: float = 28.0) -> void:
    drought_timer = maxf(drought_timer, duration)
    _record_event("intervention", "Player triggered a drought")

func introduce_mutants(count: int = 3) -> void:
    for i in range(count):
        if organisms.size() >= MAX_CREATURES:
            break
        var base_genome: Genome
        if organisms.is_empty():
            base_genome = Genome.ancestral(rng)
        else:
            var source_index: int = rng.randi_range(0, organisms.size() - 1)
            base_genome = organisms[source_index].genome
        var genome := base_genome.mutated_copy(rng, 5.0)
        var p := Vector2(
            rng.randf_range(70.0, WORLD_SIZE.x - 70.0),
            rng.randf_range(120.0, WORLD_SIZE.y - 75.0)
        )
        var org := _new_organism(genome, p, 0, -1)
        org.energy = genome.max_energy() * 0.88
        org.recent_mutations = genome.mutation_summary(base_genome)
        organisms.append(org)
    _record_event("intervention", "Player introduced %d mutant founders" % count)

func cull_fraction(fraction: float = 0.25) -> void:
    var target: int = mini(organisms.size(), maxi(1, int(round(float(organisms.size()) * fraction))))
    for i in range(target):
        if organisms.is_empty():
            break
        var index: int = rng.randi_range(0, organisms.size() - 1)
        var org: Organism = organisms[index]
        _kill(org, "player cull")
        organisms.remove_at(index)
    _record_event("intervention", "Player culled %d organisms" % target)

func boost_organism(id: int) -> bool:
    var org := get_organism_by_id(id)
    if org == null:
        return false
    org.energy = org.genome.max_energy()
    _record_event("intervention", "Creature #%d received an energy boost" % id)
    return true

func force_mutated_offspring(id: int) -> int:
    var parent := get_organism_by_id(id)
    if parent == null or organisms.size() >= MAX_CREATURES:
        return -1
    var lab_multiplier: float = maxf(8.0, mutation_multiplier * 1.5)
    var genome := parent.genome.mutated_copy(rng, lab_multiplier)
    var offset: Vector2 = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * 30.0
    var child := _new_organism(genome, _clamp_world(parent.position + offset), parent.generation + 1, parent.id)
    child.energy = child.genome.max_energy() * 0.78
    child.recent_mutations = genome.mutation_summary(parent.genome)
    organisms.append(child)
    parent.offspring_count += 1
    births += 1
    max_generation = maxi(max_generation, child.generation)
    _record_event("intervention", "Creature #%d produced an extreme lab mutant" % id)
    return child.id

func remove_organism(id: int) -> bool:
    var org := get_organism_by_id(id)
    if org == null:
        return false
    _kill(org, "player removal")
    organisms.erase(org)
    _record_event("intervention", "Creature #%d was removed" % id)
    return true

func _clamp_world(p: Vector2) -> Vector2:
    return Vector2(clampf(p.x, 30.0, WORLD_SIZE.x - 30.0), clampf(p.y, 92.0, WORLD_SIZE.y - 30.0))

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

    if organisms.size() >= 120 and not _event_exists("population_120"):
        _record_event("population_120", "Population boom: 120 living organisms")
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

func nearest_organism(point: Vector2, max_distance: float = 42.0) -> Organism:
    var best: Organism = null
    var best_d2: float = max_distance * max_distance
    for org in organisms:
        var d2: float = org.position.distance_squared_to(point)
        if d2 <= best_d2:
            best_d2 = d2
            best = org
    return best

func population_mean_gene(gene_name: String) -> float:
    if organisms.is_empty():
        return 0.0
    var total: float = 0.0
    for org in organisms:
        total += float(org.genome.get(gene_name))
    return total / float(organisms.size())

func total_food_biomass() -> float:
    var total: float = 0.0
    for patch in food_patches:
        total += patch.biomass
    return total

func _genome_snapshot(genome: Genome) -> Dictionary:
    var snapshot := {}
    for gene_name in Genome.GENE_NAMES:
        snapshot[gene_name] = genome.get(gene_name)
    return snapshot
