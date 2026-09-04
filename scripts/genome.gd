class_name Genome
extends RefCounted

# Genes are normalized to 0..1. Phenotype and survival traits are derived from
# combinations of genes rather than treating each gene as an isolated slider.
var body_size: float = 0.45
var body_length: float = 0.50
var segment_gene: float = 0.35
var head_ratio: float = 0.45
var appendage_gene: float = 0.45
var appendage_length: float = 0.45
var tail_gene: float = 0.50
var eye_gene: float = 0.45
var hue_gene: float = 0.52
var pattern_gene: float = 0.35

var speed_gene: float = 0.50
var turn_gene: float = 0.50
var metabolism_gene: float = 0.45
var vision_gene: float = 0.50
var offspring_investment_gene: float = 0.45

const GENE_NAMES := [
    "body_size", "body_length", "segment_gene", "head_ratio",
    "appendage_gene", "appendage_length", "tail_gene", "eye_gene",
    "hue_gene", "pattern_gene", "speed_gene", "turn_gene",
    "metabolism_gene", "vision_gene", "offspring_investment_gene"
]

static func ancestral(rng: RandomNumberGenerator) -> Genome:
    var g := Genome.new()
    for gene_name in GENE_NAMES:
        var base_value: float = g.get(gene_name)
        g.set(gene_name, clampf(base_value + rng.randfn(0.0, 0.035), 0.02, 0.98))
    return g

func mutated_copy(rng: RandomNumberGenerator, mutation_multiplier: float = 1.0) -> Genome:
    var child := Genome.new()
    for gene_name in GENE_NAMES:
        var value: float = get(gene_name)
        # Most mutations are tiny; occasional mutations are larger. This makes
        # visible evolution drift rather than snap between discrete sprites.
        if rng.randf() < minf(0.92, 0.34 * mutation_multiplier):
            var sigma := 0.018 * mutation_multiplier
            if rng.randf() < 0.055 * mutation_multiplier:
                sigma *= 4.0
            value += rng.randfn(0.0, sigma)
        child.set(gene_name, clampf(value, 0.01, 0.99))
    return child

func mutation_summary(parent: Genome) -> Array[String]:
    var changes: Array[String] = []
    for gene_name in GENE_NAMES:
        var delta: float = get(gene_name) - parent.get(gene_name)
        if absf(delta) >= 0.025:
            var direction := "+" if delta > 0.0 else "-"
            changes.append("%s %s%.2f" % [gene_name, direction, absf(delta)])
    if changes.is_empty():
        changes.append("minor drift")
    return changes

# ---------- Derived phenotype ----------

func radius() -> float:
    return lerpf(5.5, 13.5, body_size)

func length_multiplier() -> float:
    return lerpf(0.75, 1.75, body_length)

func segment_count() -> int:
    return clampi(3 + int(round(segment_gene * 6.0)), 3, 9)

func appendage_pairs() -> int:
    return clampi(1 + int(round(appendage_gene * 3.0)), 1, 4)

func appendage_reach() -> float:
    return radius() * lerpf(0.65, 2.1, appendage_length)

func tail_length() -> float:
    return radius() * lerpf(0.6, 2.8, tail_gene)

func head_scale() -> float:
    return lerpf(0.72, 1.38, head_ratio)

func eye_scale() -> float:
    return lerpf(0.7, 1.6, eye_gene) * lerpf(0.85, 1.20, vision_gene)

func body_color() -> Color:
    return Color.from_hsv(fposmod(hue_gene, 1.0), 0.62, 0.92)

# ---------- Derived survival traits / tradeoffs ----------

func mass() -> float:
    var segmentation_cost := 1.0 + float(segment_count() - 3) * 0.035
    return (0.55 + body_size * body_size * 2.4) * length_multiplier() * segmentation_cost

func max_speed() -> float:
    # Speed gene helps, but large bodies and long appendages increase drag.
    var propulsion := lerpf(42.0, 118.0, speed_gene)
    var drag := 0.72 + sqrt(mass()) * 0.42 + appendage_length * 0.18
    return propulsion / drag

func acceleration() -> float:
    return lerpf(55.0, 155.0, speed_gene) / (0.75 + mass() * 0.32)

func turn_rate() -> float:
    return lerpf(1.2, 5.2, turn_gene) / (0.82 + body_length * 0.45 + body_size * 0.25)

func vision_range() -> float:
    # Better eyes/vision are useful but paid for in metabolism below.
    return lerpf(55.0, 245.0, vision_gene) * lerpf(0.9, 1.08, eye_gene)

func max_energy() -> float:
    return 45.0 + mass() * 42.0

func basal_energy_cost() -> float:
    var brain_and_senses := 0.10 + vision_gene * 0.18 + eye_gene * 0.05
    var tissue := 0.18 + mass() * 0.12
    var metabolism := lerpf(0.68, 1.55, metabolism_gene)
    return (tissue + brain_and_senses) * metabolism

func movement_cost_per_unit() -> float:
    return (0.0014 + mass() * 0.0010) * lerpf(0.8, 1.35, speed_gene)

func bite_rate() -> float:
    # Bigger creatures can process more food, but must also support more mass.
    return lerpf(3.5, 11.0, body_size) * lerpf(0.82, 1.18, metabolism_gene)

func maturity_age() -> float:
    return 9.0 + mass() * 2.4 + offspring_investment_gene * 3.0

func lifespan() -> float:
    # High metabolism buys activity at the cost of some longevity.
    return lerpf(70.0, 145.0, 1.0 - metabolism_gene) + mass() * 4.0

func offspring_energy_fraction() -> float:
    # High-investment offspring start stronger, but each birth costs the parent more.
    return lerpf(0.16, 0.34, offspring_investment_gene)

func reproduction_threshold() -> float:
    return lerpf(0.72, 0.91, offspring_investment_gene)

func compact_description() -> String:
    return "size %.2f | seg %d | limbs %d | speed %.0f | vision %.0f" % [
        body_size, segment_count(), appendage_pairs(), max_speed(), vision_range()
    ]
