class_name EvolutionWorldRenderer
extends Node2D

var simulation: EvolutionSimulation
var selected_id: int = -1
var selected_trail: PackedVector2Array = PackedVector2Array()
var trail_timer: float = 0.0
var show_vision_overlay: bool = false
var show_food_overlay: bool = false

func _process(delta: float) -> void:
    if simulation == null:
        return

    trail_timer -= delta
    if selected_id != -1 and trail_timer <= 0.0:
        trail_timer = 0.09
        var selected := simulation.get_organism_by_id(selected_id)
        if selected != null:
            selected_trail.append(selected.position)
            if selected_trail.size() > 80:
                selected_trail.remove_at(0)
    queue_redraw()

func select_creature(id: int) -> void:
    if selected_id != id:
        selected_trail.clear()
    selected_id = id

func _draw() -> void:
    if simulation == null:
        return

    _draw_environment()
    _draw_food()

    if selected_trail.size() >= 2:
        for i in range(1, selected_trail.size()):
            var alpha := float(i) / float(selected_trail.size())
            draw_line(selected_trail[i - 1], selected_trail[i], Color(0.72, 0.90, 1.0, 0.05 + alpha * 0.28), 2.0)

    for org in simulation.organisms:
        _draw_creature(org)

    var selected := simulation.get_organism_by_id(selected_id)
    if selected != null:
        var r := selected.genome.radius() * selected.genome.length_multiplier() * 2.4
        draw_arc(selected.position, r + 8.0, 0.0, TAU, 36, Color(0.95, 0.96, 1.0, 0.85), 2.0)
        if show_vision_overlay:
            draw_arc(selected.position, selected.genome.vision_range(), 0.0, TAU, 64, Color(0.55, 0.85, 1.0, 0.22), 1.5)

func _draw_environment() -> void:
    draw_rect(Rect2(Vector2.ZERO, EvolutionSimulation.WORLD_SIZE), Color("0b1821"), true)

    # Layered currents / habitat bands. Purely visual in this first slice.
    for y in range(112, 720, 86):
        var wobble := sin(simulation.elapsed_sim_time * 0.08 + float(y) * 0.03) * 10.0
        draw_line(Vector2(0, y + wobble), Vector2(1280, y - wobble), Color(0.12, 0.34, 0.39, 0.12), 18.0)

    for x in range(30, 1280, 90):
        var shimmer := 0.035 + 0.025 * sin(simulation.elapsed_sim_time * 0.4 + float(x))
        draw_line(Vector2(x, 92), Vector2(x - 80, 720), Color(0.3, 0.7, 0.75, shimmer), 1.0)

func _draw_food() -> void:
    for patch in simulation.food_patches:
        var fullness := patch.biomass / maxf(patch.capacity, 0.001)
        if fullness <= 0.02:
            continue
        var pulse := 1.0 + sin(simulation.elapsed_sim_time * 1.35 + patch.phase) * 0.08
        var radius := lerpf(2.2, 7.5, sqrt(fullness)) * pulse
        var core := Color(0.33, 0.79, 0.45, 0.32 + fullness * 0.48)
        draw_circle(patch.position, radius, core)
        var leaves := 3 + int(round(fullness * 3.0))
        for i in range(leaves):
            var a := patch.phase + TAU * float(i) / float(leaves)
            var tip := patch.position + Vector2.RIGHT.rotated(a) * radius * 1.9
            draw_line(patch.position, tip, Color(0.39, 0.90, 0.54, 0.34 + fullness * 0.35), maxf(1.0, radius * 0.28))

        if show_food_overlay:
            draw_arc(patch.position, 11.0, -PI * 0.5, -PI * 0.5 + TAU * fullness, 18, Color(0.72, 1.0, 0.60, 0.7), 1.2)

func _draw_creature(org: Organism) -> void:
    var g := org.genome
    var base_radius := g.radius()
    var segment_count := g.segment_count()
    var gap := base_radius * 1.22 * g.length_multiplier()
    var speed_ratio := clampf(org.velocity.length() / maxf(g.max_speed(), 1.0), 0.0, 1.0)
    var swim := simulation.elapsed_sim_time * (2.0 + speed_ratio * 5.0) + org.animation_phase
    var wave_amp := base_radius * (0.10 + 0.18 * speed_ratio)
    var base_color := g.body_color()
    var outline := base_color.darkened(0.48)
    var highlight := base_color.lightened(0.18)

    draw_set_transform(org.position, org.heading, Vector2.ONE)

    # Tail: continuous size/length change from genes.
    var tail_x := -gap * float(segment_count - 1) - g.tail_length()
    var tail_width := base_radius * lerpf(0.45, 1.25, g.tail_gene)
    var tail_poly := PackedVector2Array([
        Vector2(-gap * float(segment_count - 1), 0.0),
        Vector2(tail_x, -tail_width),
        Vector2(tail_x * 0.97, 0.0),
        Vector2(tail_x, tail_width)
    ])
    draw_colored_polygon(tail_poly, base_color.darkened(0.08))
    draw_polyline(tail_poly, outline, 1.4)

    # Appendages are distributed along the inherited body plan. Their length
    # and swing both derive from morphology and movement.
    var pairs := g.appendage_pairs()
    for i in range(pairs):
        var t := float(i + 1) / float(pairs + 1)
        var segment_index := int(round(t * float(segment_count - 1)))
        var x := -gap * float(segment_index)
        var y_wave := sin(swim - float(segment_index) * 0.72) * wave_amp
        var swing := sin(swim * 1.35 + float(i) * 1.7) * 0.48
        var reach := g.appendage_reach() * (0.90 + 0.12 * speed_ratio)
        for side_value in [-1.0, 1.0]:
            var side: float = float(side_value)
            var root := Vector2(x, y_wave + side * base_radius * 0.50)
            var angle: float = side * (PI * 0.47 + swing * 0.35)
            var tip := root + Vector2.RIGHT.rotated(angle) * reach
            draw_line(root, tip, outline, maxf(1.4, base_radius * 0.18), true)
            draw_circle(tip, maxf(1.2, base_radius * 0.16), highlight)

    # Segmented procedural body. Segment count is discrete phenotype generated
    # from a continuous gene, so nearby descendants usually differ subtly.
    for i in range(segment_count - 1, -1, -1):
        var taper := lerpf(0.58, 1.0, 1.0 - float(i) / maxf(float(segment_count), 1.0))
        var r := base_radius * taper
        var x := -gap * float(i)
        var y := sin(swim - float(i) * 0.72) * wave_amp
        var seg_color := base_color
        if i % 2 == 1:
            seg_color = base_color.darkened(0.05 + g.pattern_gene * 0.10)
        draw_circle(Vector2(x, y), r + 1.2, outline)
        draw_circle(Vector2(x, y), r, seg_color)

        if g.pattern_gene > 0.38:
            var mark := Color(1.0, 1.0, 1.0, 0.10 + g.pattern_gene * 0.22)
            draw_circle(Vector2(x, y - r * 0.25), r * lerpf(0.12, 0.33, g.pattern_gene), mark)

    # Head, eyes and mouth.
    var head_r := base_radius * g.head_scale()
    var head_pos := Vector2(gap * 0.42, sin(swim + 0.55) * wave_amp * 0.45)
    draw_circle(head_pos, head_r + 1.4, outline)
    draw_circle(head_pos, head_r, base_color.lightened(0.05))

    var eye_r := maxf(1.1, base_radius * 0.13 * g.eye_scale())
    var eye_forward := head_r * 0.48
    var eye_side := head_r * 0.38
    draw_circle(head_pos + Vector2(eye_forward, -eye_side), eye_r, Color("dffcff"))
    draw_circle(head_pos + Vector2(eye_forward, eye_side), eye_r, Color("dffcff"))
    draw_circle(head_pos + Vector2(eye_forward + eye_r * 0.30, -eye_side), eye_r * 0.45, Color("071016"))
    draw_circle(head_pos + Vector2(eye_forward + eye_r * 0.30, eye_side), eye_r * 0.45, Color("071016"))

    var mouth_x := head_pos.x + head_r * 0.74
    var mouth_open := 0.10 + (0.20 if org.behavior == "feeding" else 0.0)
    draw_line(Vector2(mouth_x - head_r * 0.18, -head_r * mouth_open), Vector2(mouth_x + head_r * 0.18, 0.0), outline, 1.5)
    draw_line(Vector2(mouth_x - head_r * 0.18, head_r * mouth_open), Vector2(mouth_x + head_r * 0.18, 0.0), outline, 1.5)

    # Energy indicator appears only when stressed to keep normal view organic.
    if org.energy_ratio() < 0.28:
        var bar_w := base_radius * 3.0
        var p := Vector2(-bar_w * 0.5, -base_radius * 2.25)
        draw_rect(Rect2(p, Vector2(bar_w, 2.5)), Color(0.08, 0.10, 0.12, 0.75), true)
        draw_rect(Rect2(p, Vector2(bar_w * org.energy_ratio(), 2.5)), Color(0.95, 0.55, 0.30, 0.90), true)

    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
