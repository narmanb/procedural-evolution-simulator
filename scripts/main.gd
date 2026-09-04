extends Node2D

const SPEEDS := [0.0, 1.0, 2.0, 5.0, 10.0, 50.0]
const SIM_DT := 1.0 / 30.0

var simulation := EvolutionSimulation.new()
var renderer: EvolutionWorldRenderer
var speed_index: int = 1
var accumulator: float = 0.0
var selected_id: int = -1
var last_population: int = -1

var stats_label: Label
var speed_label: Label
var inspector_label: RichTextLabel
var mutation_button: Button
var vision_button: Button
var food_button: Button
var speed_buttons: Array[Button] = []

func _ready() -> void:
    simulation.reset()

    renderer = EvolutionWorldRenderer.new()
    renderer.simulation = simulation
    add_child(renderer)

    _build_ui()
    _refresh_ui()

func _process(delta: float) -> void:
    var speed := SPEEDS[speed_index]
    if speed > 0.0:
        accumulator += delta * speed
        var steps := 0
        while accumulator >= SIM_DT and steps < 160:
            simulation.step(SIM_DT)
            accumulator -= SIM_DT
            steps += 1
        # Prevent a stalled device from building an enormous simulation debt.
        if steps >= 160:
            accumulator = 0.0

    _refresh_ui()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.physical_keycode == KEY_SPACE:
            speed_index = 0 if speed_index != 0 else 1
            _update_speed_buttons()
            get_viewport().set_input_as_handled()
            return
        if event.physical_keycode == KEY_Q:
            speed_index = maxi(0, speed_index - 1)
            _update_speed_buttons()
            get_viewport().set_input_as_handled()
            return
        if event.physical_keycode == KEY_E:
            speed_index = mini(SPEEDS.size() - 1, speed_index + 1)
            _update_speed_buttons()
            get_viewport().set_input_as_handled()
            return

    if event is InputEventJoypadButton and event.pressed:
        if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
            speed_index = maxi(0, speed_index - 1)
            _update_speed_buttons()
            get_viewport().set_input_as_handled()
            return
        if event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
            speed_index = mini(SPEEDS.size() - 1, speed_index + 1)
            _update_speed_buttons()
            get_viewport().set_input_as_handled()
            return

    var screen_pos := Vector2.ZERO
    var pressed := false
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        screen_pos = event.position
        pressed = true
    elif event is InputEventScreenTouch and event.pressed:
        screen_pos = event.position
        pressed = true

    if pressed and screen_pos.y > 86.0:
        var org := simulation.nearest_organism(screen_pos, 46.0)
        selected_id = org.id if org != null else -1
        renderer.select_creature(selected_id)
        _refresh_inspector()

func _build_ui() -> void:
    var canvas := CanvasLayer.new()
    canvas.layer = 5
    add_child(canvas)

    var top_panel := PanelContainer.new()
    top_panel.position = Vector2(12, 10)
    top_panel.size = Vector2(1256, 68)
    canvas.add_child(top_panel)

    var top := HBoxContainer.new()
    top.add_theme_constant_override("separation", 8)
    top_panel.add_child(top)

    var title := Label.new()
    title.text = "EVOLUTION LAB"
    title.custom_minimum_size = Vector2(138, 0)
    top.add_child(title)

    stats_label = Label.new()
    stats_label.custom_minimum_size = Vector2(330, 0)
    top.add_child(stats_label)

    for i in range(SPEEDS.size()):
        var button := Button.new()
        button.text = "PAUSE" if SPEEDS[i] == 0.0 else "%gx" % SPEEDS[i]
        button.custom_minimum_size = Vector2(66, 46)
        button.toggle_mode = true
        button.pressed.connect(_set_speed.bind(i))
        top.add_child(button)
        speed_buttons.append(button)

    mutation_button = Button.new()
    mutation_button.text = "Mutation 1x"
    mutation_button.custom_minimum_size = Vector2(118, 46)
    mutation_button.pressed.connect(_cycle_mutation)
    top.add_child(mutation_button)

    var new_seed := Button.new()
    new_seed.text = "New World"
    new_seed.custom_minimum_size = Vector2(106, 46)
    new_seed.pressed.connect(_new_world)
    top.add_child(new_seed)

    var inspector_panel := PanelContainer.new()
    inspector_panel.position = Vector2(12, 535)
    inspector_panel.size = Vector2(620, 172)
    canvas.add_child(inspector_panel)

    var inspector_box := VBoxContainer.new()
    inspector_panel.add_child(inspector_box)

    var inspector_title := HBoxContainer.new()
    inspector_box.add_child(inspector_title)
    var select_hint := Label.new()
    select_hint.text = "Tap a creature to pin/inspect it"
    select_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    inspector_title.add_child(select_hint)

    vision_button = Button.new()
    vision_button.text = "Vision"
    vision_button.toggle_mode = true
    vision_button.pressed.connect(_toggle_vision)
    inspector_title.add_child(vision_button)

    food_button = Button.new()
    food_button.text = "Food"
    food_button.toggle_mode = true
    food_button.pressed.connect(_toggle_food)
    inspector_title.add_child(food_button)

    inspector_label = RichTextLabel.new()
    inspector_label.bbcode_enabled = true
    inspector_label.fit_content = false
    inspector_label.custom_minimum_size = Vector2(600, 120)
    inspector_label.scroll_active = false
    inspector_box.add_child(inspector_label)

    speed_label = Label.new()
    speed_label.position = Vector2(650, 665)
    speed_label.size = Vector2(610, 36)
    speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    canvas.add_child(speed_label)

    _update_speed_buttons()

func _set_speed(index: int) -> void:
    speed_index = index
    accumulator = 0.0
    _update_speed_buttons()

func _update_speed_buttons() -> void:
    for i in range(speed_buttons.size()):
        speed_buttons[i].button_pressed = i == speed_index

func _cycle_mutation() -> void:
    var levels := [0.5, 1.0, 2.0, 5.0]
    var current := levels.find(simulation.mutation_multiplier)
    current = (current + 1) % levels.size()
    simulation.mutation_multiplier = levels[current]
    mutation_button.text = "Mutation %gx" % simulation.mutation_multiplier

func _toggle_vision() -> void:
    renderer.show_vision_overlay = vision_button.button_pressed

func _toggle_food() -> void:
    renderer.show_food_overlay = food_button.button_pressed

func _new_world() -> void:
    simulation.reset()
    selected_id = -1
    renderer.select_creature(-1)
    speed_index = 1
    accumulator = 0.0
    _update_speed_buttons()
    _refresh_ui()

func _refresh_ui() -> void:
    if stats_label == null:
        return
    var pop := simulation.organisms.size()
    stats_label.text = "Pop %d   Gen %d   Births %d   Food %.0f" % [
        pop, simulation.max_generation, simulation.births, simulation.total_food_biomass()
    ]
    speed_label.text = "Seed %d   Sim time %s   Q/E or shoulders: speed   Space: pause" % [
        simulation.seed_value, _format_time(simulation.elapsed_sim_time)
    ]

    if pop != last_population or selected_id != -1:
        last_population = pop
        _refresh_inspector()

func _refresh_inspector() -> void:
    if inspector_label == null:
        return
    var org := simulation.get_organism_by_id(selected_id)
    if org == null:
        inspector_label.text = "[color=#9ab0bc]No creature selected.[/color]\nWatch the body plans drift as descendants inherit small mutations. High speed is intended for evolutionary sweeps."
        return

    var parent_text := "founder" if org.parent_id == -1 else str(org.parent_id)
    var mutation_text := ", ".join(org.recent_mutations) if not org.recent_mutations.is_empty() else "founder variation"
    inspector_label.text = (
        "[b]Creature #%d[/b]   Generation %d   Parent %s\n" +
        "Age %.1f / %.1f   Energy %.0f%%   Behavior: %s   Offspring: %d\n" +
        "%s\n" +
        "Recent mutation: %s"
    ) % [
        org.id, org.generation, parent_text,
        org.age, org.genome.lifespan(), org.energy_ratio() * 100.0, org.behavior, org.offspring_count,
        org.genome.compact_description(), mutation_text
    ]

func _format_time(seconds: float) -> String:
    var total := int(seconds)
    var minutes := total / 60
    var secs := total % 60
    return "%02d:%02d" % [minutes, secs]
