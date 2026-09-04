class_name EvolutionWorldRenderer
extends Node2D

var simulation: EvolutionSimulation
var selected_id: int = -1
var selected_trail: PackedVector2Array = PackedVector2Array()
var trail_timer: float = 0.0
var show_vision_overlay: bool = false
var show_food_overlay: bool = false
var food_paint_mode: bool = false

func _process(delta: float) -> void:
    if simulation == null:
        return

    trail_timer -= delta
    if selected_id != -1 and trail_timer <= 0.0:
        trail_timer = 0.09
        var selected: Organism = simulation.get_organism_by_id(selected_id)
        if selected != null:
            selected_trail.append(selected.position)
            if selected_trail.size() > 90:
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
            var alpha: float = float(i) / float(selected_trail.size())
            draw_line(selected_trail[i - 1], selected_trail[i], Color(0.72, 0.93, 1.0, 0.04 + alpha * 0.34), 2.0)

    for org in simulation.organisms:
        _draw_creature(org)

    var selected: Organism = simulation.get_organism_by_id(selected_id)
    if selected != null:
        var r: float = selected.genome.radius() * selected.genome.length_multiplier() * 2.8
        var pulse: float = 1.0 + sin(simulation.elapsed_sim_time * 4.0) * 0.05
        draw_arc(selected.position, (r + 10.0) * pulse, 0.0, TAU, 42, Color(0.90, 0.98, 1.0, 0.88), 2.5)
        if show_vision_overlay:
            draw_circle(selected.position, selected.genome.vision_range(), Color(0.30, 0.73, 0.90, 0.055))
            draw_arc(selected.position, selected.genome.vision_range(), 0.0, TAU, 72, Color(0.55, 0.88, 1.0, 0.30), 1.5)

func _draw_environment() -> void:
    var world_size: Vector2 = EvolutionSimulation.WORLD_SIZE
    draw_rect(Rect2(Vector2.ZERO, world_size), Color("07161e"), true)

    for y in range(105, int(world_size.y), 104):
        var wobble: float = sin(simulation.elapsed_sim_time * 0.12 + float(y) * 0.025) * 13.0
        draw_line(Vector2(0.0, float(y) + wobble), Vector2(world_size.x, float(y) - wobble), Color(0.08, 0.30, 0.34, 0.15), 24.0)

    for x in range(24, int(world_size.x), 82):
        var shimmer: float = 0.028 + 0.022 * sin(simulation.elapsed_sim_time * 0.45 + float(x) * 0.08)
        draw_line(Vector2(float(x), 82.0), Vector2(float(x) - 95.0, world_size.y), Color(0.26, 0.67, 0.72, shimmer), 1.0)

    if simulation.drought_timer > 0.0:
        var intensity: float = clampf(simulation.drought_timer / 28.0, 0.0, 1.0)
        draw_rect(Rect2(Vector2.ZERO, world_size), Color(0.30, 0.13, 0.035, 0.07 + intensity * 0.07), true)

    if food_paint_mode:
        draw_rect(Rect2(Vector2(5.0, 82.0), Vector2(world_size.x - 10.0, world_size.y - 87.0)), Color(0.18, 0.80, 0.38, 0.018), true)

func _draw_food() -> void:
    for patch in simulation.food_patches:
        var fullness: float = patch.biomass / maxf(patch.capacity, 0.001)
        if fullness <= 0.02:
            continue

        # Compact finite food clumps. Their radius collapses visibly as eaten.
        var pulse: float = 1.0 + sin(simulation.elapsed_sim_time * 1.6 + patch.phase) * 0.06
        var radius: float = lerpf(2.4, 7.8, sqrt(fullness)) * pulse
        var center: Vector2 = patch.position
        var dark := Color(0.12, 0.42, 0.23, 0.90)
        var green := Color(0.28, 0.88, 0.43, 0.92)
        var bright := Color(0.63, 1.0, 0.69, 0.96)

        draw_circle(center, radius + 1.5, dark)
        draw_circle(center, radius, green)
        draw_circle(center + Vector2(-radius * 0.22, -radius * 0.25), maxf(1.0, radius * 0.28), bright)

        var leaves: int = 3 + int(round(fullness * 2.0))
        for i in range(leaves):
            var a: float = patch.phase + TAU * float(i) / float(leaves)
            var root: Vector2 = center + Vector2.RIGHT.rotated(a) * radius * 0.55
            var tip: Vector2 = center + Vector2.RIGHT.rotated(a) * radius * 1.75
            var side: Vector2 = Vector2.RIGHT.rotated(a + PI * 0.5) * radius * 0.38
            var leaf := PackedVector2Array([root, tip + side, tip - side])
            draw_colored_polygon(leaf, Color(green.r, green.g, green.b, 0.72))

        if show_food_overlay:
            var overlay_radius: float = 10.0 + fullness * 10.0
            draw_circle(center, overlay_radius, Color(0.35, 1.0, 0.50, 0.045 + fullness * 0.07))
            draw_arc(center, overlay_radius, -PI * 0.5, -PI * 0.5 + TAU * fullness, 22, Color(0.65, 1.0, 0.65, 0.78), 1.4)

func _draw_creature(org: Organism) -> void:
    var g: Genome = org.genome
    var base_radius: float = g.radius()
    var segment_count: int = g.segment_count()
    var gap: float = base_radius * lerpf(0.80, 1.30, g.body_length)
    var speed_ratio: float = clampf(org.velocity.length() / maxf(g.max_speed(), 1.0), 0.0, 1.0)
    var swim: float = simulation.elapsed_sim_time * (1.8 + speed_ratio * 4.8) + org.animation_phase
    var wave_amp: float = base_radius * (0.06 + 0.20 * speed_ratio) * lerpf(0.75, 1.25, g.body_length)
    var base_color: Color = g.body_color()
    var outline: Color = base_color.darkened(0.62)
    var highlight: Color = base_color.lightened(0.22)
    var fin_color := Color(highlight.r, highlight.g, highlight.b, 0.44)

    draw_set_transform(org.position, org.heading, Vector2.ONE)

    var spine := PackedVector2Array()
    var widths := PackedFloat32Array()
    for i in range(segment_count):
        var taper: float = lerpf(1.0, 0.46, float(i) / maxf(float(segment_count - 1), 1.0))
        var x: float = -gap * float(i)
        var y: float = sin(swim - float(i) * 0.78) * wave_amp
        spine.append(Vector2(x, y))
        widths.append(base_radius * taper * lerpf(0.82, 1.12, g.body_size))

    var tail_root: Vector2 = spine[segment_count - 1]
    var tail_reach: float = g.tail_length()
    var tail_tip := tail_root + Vector2(-tail_reach, sin(swim - float(segment_count) * 0.78) * wave_amp * 0.45)
    var tail_half_width: float = base_radius * lerpf(0.45, 1.55, g.tail_gene)
    var tail_poly := PackedVector2Array([
        tail_root,
        tail_tip + Vector2(0.0, -tail_half_width),
        tail_tip + Vector2(-tail_reach * 0.13, 0.0),
        tail_tip + Vector2(0.0, tail_half_width)
    ])
    draw_colored_polygon(tail_poly, fin_color)
    var tail_outline := PackedVector2Array([tail_poly[0], tail_poly[1], tail_poly[2], tail_poly[3], tail_poly[0]])
    draw_polyline(tail_outline, outline, 1.3, true)

    var pairs: int = g.appendage_pairs()
    for i in range(pairs):
        var t: float = float(i + 1) / float(pairs + 1)
        var segment_index: int = clampi(int(round(t * float(segment_count - 1))), 0, segment_count - 1)
        var center: Vector2 = spine[segment_index]
        var body_width: float = widths[segment_index]
        var swing: float = sin(swim * 1.25 + float(i) * 1.9) * 0.34
        var reach: float = g.appendage_reach() * (0.90 + speed_ratio * 0.14)
        for side_value in [-1.0, 1.0]:
            var side: float = float(side_value)
            var root := center + Vector2(0.0, side * body_width * 0.58)
            var angle: float = side * (PI * 0.48 + swing)
            var tip := root + Vector2.RIGHT.rotated(angle) * reach
            var rear := root + Vector2(-base_radius * lerpf(0.25, 0.75, g.appendage_length), side * body_width * 0.18)
            var fin_poly := PackedVector2Array([root, tip, rear])
            draw_colored_polygon(fin_poly, fin_color)
            draw_polyline(PackedVector2Array([root, tip, rear, root]), outline, 1.1, true)

    var upper := PackedVector2Array()
    var lower := PackedVector2Array()
    for i in range(segment_count):
        upper.append(spine[i] + Vector2(0.0, -widths[i]))
        lower.append(spine[i] + Vector2(0.0, widths[i]))

    var body_poly := PackedVector2Array()
    for i in range(segment_count):
        body_poly.append(upper[i])
    for i in range(segment_count - 1, -1, -1):
        body_poly.append(lower[i])

    draw_colored_polygon(body_poly, base_color)
    var body_outline := PackedVector2Array()
    for point in body_poly:
        body_outline.append(point)
    if body_outline.size() > 0:
        body_outline.append(body_outline[0])
    draw_polyline(body_outline, outline, 1.6, true)

    if g.pattern_gene > 0.22:
        for i in range(1, segment_count):
            if i % 2 == 0:
                var stripe_alpha: float = 0.08 + g.pattern_gene * 0.20
                var stripe_color := Color(1.0, 1.0, 1.0, stripe_alpha)
                draw_line(upper[i].lerp(spine[i], 0.18), lower[i].lerp(spine[i], 0.18), stripe_color, maxf(1.0, base_radius * 0.18))
        if g.pattern_gene > 0.56:
            for i in range(1, segment_count, 2):
                draw_circle(spine[i] + Vector2(0.0, -widths[i] * 0.32), maxf(1.2, widths[i] * 0.19), Color(0.05, 0.12, 0.14, 0.26))

    var head_r: float = base_radius * g.head_scale()
    var head_pos := spine[0] + Vector2(head_r * 0.58, sin(swim + 0.45) * wave_amp * 0.18)
    var head_poly: PackedVector2Array = _ellipse_points(head_pos, head_r * lerpf(1.05, 1.42, g.head_ratio), head_r, 18)
    draw_colored_polygon(head_poly, base_color.lightened(0.06))
    var head_outline := PackedVector2Array()
    for point in head_poly:
        head_outline.append(point)
    head_outline.append(head_poly[0])
    draw_polyline(head_outline, outline, 1.6, true)

    var eye_r: float = maxf(1.5, base_radius * 0.14 * g.eye_scale())
    var eye_forward: float = head_r * 0.82
    var eye_side: float = head_r * 0.40
    for side_value in [-1.0, 1.0]:
        var side: float = float(side_value)
        var eye_pos := head_pos + Vector2(eye_forward, side * eye_side)
        draw_circle(eye_pos, eye_r + 0.8, outline)
        draw_circle(eye_pos, eye_r, Color("e9feff"))
        draw_circle(eye_pos + Vector2(eye_r * 0.28, 0.0), eye_r * 0.46, Color("051015"))

    var mouth_x: float = head_pos.x + head_r * lerpf(1.0, 1.25, g.head_ratio)
    var is_eating: bool = org.feeding_flash_timer > 0.0
    var mouth_open: float = 0.12 + (0.36 if is_eating else 0.0)
    draw_line(Vector2(mouth_x - head_r * 0.20, head_pos.y - head_r * mouth_open), Vector2(mouth_x + head_r * 0.14, head_pos.y), outline, 1.6)
    draw_line(Vector2(mouth_x - head_r * 0.20, head_pos.y + head_r * mouth_open), Vector2(mouth_x + head_r * 0.14, head_pos.y), outline, 1.6)

    # Visible food fragments move toward the mouth only after biomass was consumed.
    if is_eating:
        for i in range(4):
            var phase: float = fposmod(simulation.elapsed_sim_time * 9.0 + float(i) * 0.23 + float(org.id) * 0.07, 1.0)
            var incoming_x: float = mouth_x + lerpf(16.0, 2.0, phase)
            var incoming_y: float = head_pos.y + sin(float(i) * 2.1 + simulation.elapsed_sim_time * 14.0) * 4.0 * (1.0 - phase)
            draw_circle(Vector2(incoming_x, incoming_y), 1.6 + (1.0 - phase) * 1.1, Color(0.48, 1.0, 0.55, 0.95))

    if org.energy_ratio() < 0.28:
        var bar_w: float = base_radius * 3.4
        var p := Vector2(-bar_w * 0.5, -base_radius * 2.45)
        draw_rect(Rect2(p, Vector2(bar_w, 3.2)), Color(0.04, 0.08, 0.10, 0.82), true)
        draw_rect(Rect2(p, Vector2(bar_w * org.energy_ratio(), 3.2)), Color(0.98, 0.54, 0.27, 0.95), true)

    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _ellipse_points(center: Vector2, radius_x: float, radius_y: float, count: int) -> PackedVector2Array:
    var points := PackedVector2Array()
    for i in range(count):
        var angle: float = TAU * float(i) / float(count)
        points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
    return points
