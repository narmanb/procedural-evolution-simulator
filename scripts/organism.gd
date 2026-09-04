class_name Organism
extends RefCounted

var id: int
var parent_id: int = -1
var generation: int = 0
var genome: Genome

var position: Vector2
var velocity: Vector2 = Vector2.ZERO
var heading: float = 0.0
var desired_heading: float = 0.0

var age: float = 0.0
var energy: float = 0.0
var alive: bool = true
var behavior: String = "exploring"
var reproduction_cooldown: float = 0.0
var think_timer: float = 0.0
var wander_timer: float = 0.0
var target_food_index: int = -1

var food_consumed: float = 0.0
var offspring_count: int = 0
var distance_traveled: float = 0.0
var birth_time: float = 0.0
var death_time: float = -1.0
var recent_mutations: Array[String] = []
var animation_phase: float = 0.0

# Short-lived visual state set whenever a real bite removes biomass.
var feeding_flash_timer: float = 0.0
var last_bite_amount: float = 0.0

func _init(p_id: int, p_genome: Genome, p_position: Vector2, p_generation: int = 0, p_parent_id: int = -1) -> void:
    id = p_id
    genome = p_genome
    position = p_position
    generation = p_generation
    parent_id = p_parent_id
    energy = genome.max_energy() * 0.62
    animation_phase = fmod(float(id) * 1.61803398875, TAU)

func energy_ratio() -> float:
    return energy / maxf(genome.max_energy(), 0.001)

func age_ratio() -> float:
    return age / maxf(genome.lifespan(), 0.001)
