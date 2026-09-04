class_name FoodPatch
extends RefCounted

var position: Vector2
var biomass: float
var capacity: float
var regrowth_rate: float
var phase: float

func _init(p_position: Vector2, p_capacity: float, p_regrowth_rate: float, p_phase: float) -> void:
    position = p_position
    capacity = p_capacity
    biomass = p_capacity
    regrowth_rate = p_regrowth_rate
    phase = p_phase

func step(dt: float) -> void:
    # Logistic-style regrowth: depleted patches recover, but cannot exceed
    # their local carrying capacity.
    var fullness := biomass / maxf(capacity, 0.001)
    biomass = minf(capacity, biomass + regrowth_rate * (0.20 + 0.80 * (1.0 - fullness)) * dt)

func consume(amount: float) -> float:
    var taken := minf(amount, biomass)
    biomass -= taken
    return taken
