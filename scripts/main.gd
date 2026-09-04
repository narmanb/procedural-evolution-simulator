extends Node2D

const SPEEDS := [1.0, 5.0, 20.0, 100.0]
const SIM_DT := 1.0 / 30.0

var simulation := EvolutionSimulation.new()
var renderer: EvolutionWorldRenderer
var speed_index: int = 0
var paused: bool = false
var accumulator: float = 0.0
var selected_id: int = -1
var last_population: int = -1
var food_paint_mode: bool = false

var stats_label: Label
var event_label: Label
var inspector_panel: PanelContainer
var inspector_label: RichTextLabel
var pause_button: Button
var mutation_button: Button
var vision_button: Button
var food_map_button: Button
var food_paint_button: Button
var boost_button: Button
var breed_button: Button
var remove_button: Button
var drop_food_button: Button
var speed_buttons: Array[Button] = []

func _ready() -> void:
    simulation.reset()

    renderer = EvolutionWorldRenderer.new()
    renderer.simulation = simulation
    add_child(renderer)

    _build_ui()
    _refresh_ui()

func _process(delta: float) -> void:
    if not paused:
        var speed: float = float(SPEEDS[speed_index])
        accumulator += delta * speed
        var steps: int = 0
        while accumulator >= SIM_DT and steps < 220:
            simulation.step(SIM_DT)
            accumulator -= SIM_DT
            steps += 1
        if steps >= 220:
            accumulator = 0.0

    _refresh_ui()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.physical_keycode == KEY_SPACE:
            _toggle_pause()
            get_viewport().set_input_as_handled()
            return
        if event.physical_keycode == KEY_Q:
            _cycle_speed(-1)
            get_viewport().set_input_as_handled()
            return
        if event.physical_keycode == KEY_E:
            _cycle_speed(1)
            get_viewport().set_input_as_handled()
            return

    if event is InputEventJoypadButton and event.pressed:
        if event.button_index == JOY_BUTTON_START:
            _toggle_pause()
            get_viewport().set_input_as_handled()
            return
        if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
            _cycle_speed(-1)
            get_viewport().set_input_as_handled()
            return
        if event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
            _cycle_speed(1)
            get_viewport().set_input_as_handled()
            return

    var screen_pos := Vector2.ZERO
    var pressed: bool = false
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        screen_pos = event.position
        pressed = true
    elif event is InputEventScreenTouch and event.pressed:
        screen_pos = event.position
        pressed = true

    if pressed and screen_pos.y >= 78.0 and screen_pos.y <= EvolutionSimulation.WORLD_SIZE.y:
        if food_paint_mode:
            simulation.add_food_at(screen_pos, 5)
        else:
            var org := simulation.nearest_organism(screen_pos, 54.0)
            selected_id = org.id if org != null else -1
            renderer.select_creature(selected_id)
            _refresh_inspector()
        get_viewport().set_input_as_handled()

func _build_ui() -> void:
    var canvas := CanvasLayer.new()
    canvas.layer = 5
    add_child(canvas)

    var ui_root := Control.new()
    ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(ui_root)

    var top_panel := PanelContainer.new()
    top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
    top_panel.offset_left = 10.0
    top_panel.offset_top = 10.0
    top_panel.offset_right = -10.0
    top_panel.offset_bottom = 72.0
    top_panel.add_theme_stylebox_override("panel", _panel_style(Color("10242d"), 14))
    ui_root.add_child(top_panel)

    var top := HBoxContainer.new()
    top.add_theme_constant_override("separation", 12)
    top_panel.add_child(top)

    var title := Label.new()
    title.text = "EVOLUTION LAB"
    title.add_theme_font_size_override("font_size", 20)
    title.custom_minimum_size = Vector2(190.0, 0.0)
    top.add_child(title)

    stats_label = Label.new()
    stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    stats_label.add_theme_font_size_override("font_size", 15)
    top.add_child(stats_label)

    # Contextual selected-creature panel. All individual actions live here.
    inspector_panel = PanelContainer.new()
    inspector_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    inspector_panel.offset_left = 10.0
    inspector_panel.offset_right = -10.0
    inspector_panel.offset_top = -684.0
    inspector_panel.offset_bottom = -408.0
    inspector_panel.add_theme_stylebox_override("panel", _panel_style(Color("10242df2"), 14))
    inspector_panel.visible = false
    ui_root.add_child(inspector_panel)

    var inspector_box := VBoxContainer.new()
    inspector_box.add_theme_constant_override("separation", 6)
    inspector_panel.add_child(inspector_box)

    var inspector_header := HBoxContainer.new()
    inspector_box.add_child(inspector_header)

    var inspector_title := Label.new()
    inspector_title.text = "SELECTED CREATURE"
    inspector_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    inspector_title.add_theme_font_size_override("font_size", 17)
    inspector_header.add_child(inspector_title)

    vision_button = _make_button("VISION", _toggle_vision)
    vision_button.toggle_mode = true
    vision_button.custom_minimum_size = Vector2(108.0, 42.0)
    inspector_header.add_child(vision_button)

    inspector_label = RichTextLabel.new()
    inspector_label.bbcode_enabled = true
    inspector_label.fit_content = false
    inspector_label.scroll_active = false
    inspector_label.custom_minimum_size = Vector2(0.0, 134.0)
    inspector_label.add_theme_font_size_override("normal_font_size", 15)
    inspector_box.add_child(inspector_label)

    var selected_grid := GridContainer.new()
    selected_grid.columns = 4
    selected_grid.add_theme_constant_override("h_separation", 6)
    inspector_box.add_child(selected_grid)

    drop_food_button = _make_button("DROP FOOD", _drop_food_selected)
    drop_food_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    selected_grid.add_child(drop_food_button)

    boost_button = _make_button("ENERGY", _boost_selected)
    boost_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    selected_grid.add_child(boost_button)

    breed_button = _make_button("MONSTER CHILD", _breed_selected)
    breed_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    selected_grid.add_child(breed_button)

    remove_button = _make_button("REMOVE", _remove_selected)
    remove_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    selected_grid.add_child(remove_button)

    var controls_panel := PanelContainer.new()
    controls_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    controls_panel.offset_left = 8.0
    controls_panel.offset_right = -8.0
    controls_panel.offset_top = -398.0
    controls_panel.offset_bottom = -8.0
    controls_panel.add_theme_stylebox_override("panel", _panel_style(Color("0c1c24f7"), 16))
    ui_root.add_child(controls_panel)

    var controls := VBoxContainer.new()
    controls.add_theme_constant_override("separation", 7)
    controls_panel.add_child(controls)

    var control_header := HBoxContainer.new()
    controls.add_child(control_header)

    var control_title := Label.new()
    control_title.text = "LAB CONTROLS"
    control_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    control_title.add_theme_font_size_override("font_size", 19)
    control_header.add_child(control_title)

    var hint := Label.new()
    hint.text = "Food is player-controlled"
    hint.add_theme_color_override("font_color", Color("91aab5"))
    hint.add_theme_font_size_override("font_size", 13)
    control_header.add_child(hint)

    var time_grid := GridContainer.new()
    time_grid.columns = 5
    time_grid.add_theme_constant_override("h_separation", 6)
    controls.add_child(time_grid)

    pause_button = _make_button("Ⅱ PAUSE", _toggle_pause)
    pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    time_grid.add_child(pause_button)

    for i in range(SPEEDS.size()):
        var button := _make_button("%gx" % SPEEDS[i], _set_speed.bind(i))
        button.toggle_mode = true
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        time_grid.add_child(button)
        speed_buttons.append(button)

    var lab_grid := GridContainer.new()
    lab_grid.columns = 3
    lab_grid.add_theme_constant_override("h_separation", 6)
    lab_grid.add_theme_constant_override("v_separation", 6)
    controls.add_child(lab_grid)

    food_paint_button = _make_button("FOOD PAINT", _toggle_food_paint)
    food_paint_button.toggle_mode = true
    food_paint_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lab_grid.add_child(food_paint_button)

    var random_food_button := _make_button("+ RANDOM FOOD", _random_food)
    random_food_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lab_grid.add_child(random_food_button)

    var clear_food_button := _make_button("CLEAR FOOD", _clear_food)
    clear_food_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lab_grid.add_child(clear_food_button)

    mutation_button = _make_button("MUTATION 1x", _cycle_mutation)
    mutation_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lab_grid.add_child(mutation_button)

    var mutants_button := _make_button("+3 MUTANTS", _introduce_mutants)
    mutants_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lab_grid.add_child(mutants_button)

    var cull_button := _make_button("CULL 25%", _cull_population)
    cull_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lab_grid.add_child(cull_button)

    food_map_button = _make_button("FOOD MAP", _toggle_food_map)
    food_map_button.toggle_mode = true
    food_map_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lab_grid.add_child(food_map_button)

    var new_world_button := _make_button("NEW WORLD", _new_world)
    new_world_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lab_grid.add_child(new_world_button)

    event_label = Label.new()
    event_label.custom_minimum_size = Vector2(0.0, 44.0)
    event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    event_label.add_theme_color_override("font_color", Color("9fc3cf"))
    event_label.add_theme_font_size_override("font_size", 14)
    controls.add_child(event_label)

    _update_speed_buttons()
    _update_selected_buttons()

func _make_button(text: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.custom_minimum_size = Vector2(0.0, 52.0)
    button.add_theme_font_size_override("font_size", 14)
    button.add_theme_stylebox_override("normal", _button_style(Color("18333d"), 10))
    button.add_theme_stylebox_override("hover", _button_style(Color("214552"), 10))
    button.add_theme_stylebox_override("pressed", _button_style(Color("286577"), 10))
    button.add_theme_stylebox_override("disabled", _button_style(Color("17242a"), 10))
    button.pressed.connect(callback)
    return button

func _panel_style(color: Color, radius: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.corner_radius_top_left = radius
    style.corner_radius_top_right = radius
    style.corner_radius_bottom_left = radius
    style.corner_radius_bottom_right = radius
    style.content_margin_left = 12.0
    style.content_margin_right = 12.0
    style.content_margin_top = 10.0
    style.content_margin_bottom = 10.0
    return style

func _button_style(color: Color, radius: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.corner_radius_top_left = radius
    style.corner_radius_top_right = radius
    style.corner_radius_bottom_left = radius
    style.corner_radius_bottom_right = radius
    return style

func _toggle_pause() -> void:
    paused = not paused
    accumulator = 0.0
    _update_speed_buttons()

func _set_speed(index: int) -> void:
    speed_index = clampi(index, 0, SPEEDS.size() - 1)
    paused = false
    accumulator = 0.0
    _update_speed_buttons()

func _cycle_speed(direction: int) -> void:
    speed_index = clampi(speed_index + direction, 0, SPEEDS.size() - 1)
    paused = false
    accumulator = 0.0
    _update_speed_buttons()

func _update_speed_buttons() -> void:
    if pause_button != null:
        pause_button.text = "▶ RESUME" if paused else "Ⅱ PAUSE"
    for i in range(speed_buttons.size()):
        speed_buttons[i].button_pressed = not paused and i == speed_index

func _cycle_mutation() -> void:
    var levels := [0.5, 1.0, 3.0, 8.0, 20.0]
    var current: int = levels.find(simulation.mutation_multiplier)
    if current < 0:
        current = 1
    current = (current + 1) % levels.size()
    simulation.mutation_multiplier = float(levels[current])
    mutation_button.text = "MUTATION %gx" % simulation.mutation_multiplier

func _toggle_food_paint() -> void:
    food_paint_mode = food_paint_button.button_pressed
    renderer.food_paint_mode = food_paint_mode
    if food_paint_mode:
        food_paint_button.text = "FOOD PAINT: ON"
    else:
        food_paint_button.text = "FOOD PAINT"

func _random_food() -> void:
    simulation.scatter_food(18)

func _clear_food() -> void:
    simulation.clear_food()

func _introduce_mutants() -> void:
    simulation.introduce_mutants(3)

func _cull_population() -> void:
    simulation.cull_fraction(0.25)
    if simulation.get_organism_by_id(selected_id) == null:
        selected_id = -1
        renderer.select_creature(-1)
    _refresh_inspector()

func _toggle_vision() -> void:
    renderer.show_vision_overlay = vision_button.button_pressed

func _toggle_food_map() -> void:
    renderer.show_food_overlay = food_map_button.button_pressed

func _drop_food_selected() -> void:
    simulation.drop_food_for_organism(selected_id)
    _refresh_inspector()

func _boost_selected() -> void:
    simulation.boost_organism(selected_id)
    _refresh_inspector()

func _breed_selected() -> void:
    var child_id: int = simulation.force_mutated_offspring(selected_id)
    if child_id != -1:
        selected_id = child_id
        renderer.select_creature(selected_id)
    _refresh_inspector()

func _remove_selected() -> void:
    if simulation.remove_organism(selected_id):
        selected_id = -1
        renderer.select_creature(-1)
    _refresh_inspector()

func _new_world() -> void:
    simulation.reset()
    selected_id = -1
    renderer.select_creature(-1)
    speed_index = 0
    paused = false
    accumulator = 0.0
    food_paint_mode = false
    mutation_button.text = "MUTATION 1x"
    food_paint_button.text = "FOOD PAINT"
    food_paint_button.button_pressed = false
    food_map_button.button_pressed = false
    vision_button.button_pressed = false
    renderer.food_paint_mode = false
    renderer.show_food_overlay = false
    renderer.show_vision_overlay = false
    _update_speed_buttons()
    _refresh_ui()

func _refresh_ui() -> void:
    if stats_label == null:
        return

    var pop: int = simulation.organisms.size()
    var state: String = "PAUSED" if paused else "%gx" % SPEEDS[speed_index]
    stats_label.text = "Pop %d   Gen %d   Births %d   %s" % [pop, simulation.max_generation, simulation.births, state]

    if simulation.event_log.is_empty():
        event_label.text = "No food yet. Use RANDOM FOOD or FOOD PAINT, then watch who reaches it first."
    else:
        var last_event: Dictionary = simulation.event_log.back()
        var paint_text: String = "   •   FOOD PAINT ON" if food_paint_mode else ""
        event_label.text = "Food %.0f   •   %s   •   Sim %s%s" % [
            simulation.total_food_biomass(),
            str(last_event.get("text", "")),
            _format_time(simulation.elapsed_sim_time),
            paint_text
        ]

    if selected_id != -1 and simulation.get_organism_by_id(selected_id) == null:
        selected_id = -1
        renderer.select_creature(-1)

    if pop != last_population or selected_id != -1:
        last_population = pop
        _refresh_inspector()

    _update_selected_buttons()

func _refresh_inspector() -> void:
    if inspector_label == null:
        return

    var org := simulation.get_organism_by_id(selected_id)
    inspector_panel.visible = org != null
    if org == null:
        return

    var parent_text: String = "founder" if org.parent_id == -1 else "#%d" % org.parent_id
    var mutation_text: String = ", ".join(org.recent_mutations) if not org.recent_mutations.is_empty() else "founder variation"
    var feeding_text: String = " [color=#75ff8c][b]EATING NOW[/b][/color]" if org.feeding_flash_timer > 0.0 else ""
    inspector_label.text = (
        "[b]Creature #%d[/b]   Gen %d   Parent %s   Energy %.0f%%%s\n" +
        "Age %.1f / %.1f   Behavior: [color=#8ee8d8]%s[/color]   Offspring %d\n" +
        "Food eaten %.1f   •   %s\n" +
        "[color=#9bb7c2]Mutation: %s[/color]"
    ) % [
        org.id, org.generation, parent_text, org.energy_ratio() * 100.0, feeding_text,
        org.age, org.genome.lifespan(), org.behavior, org.offspring_count,
        org.food_consumed, org.genome.compact_description(), mutation_text
    ]

func _update_selected_buttons() -> void:
    var has_selection: bool = simulation.get_organism_by_id(selected_id) != null
    if drop_food_button != null:
        drop_food_button.disabled = not has_selection
    if boost_button != null:
        boost_button.disabled = not has_selection
    if breed_button != null:
        breed_button.disabled = not has_selection
    if remove_button != null:
        remove_button.disabled = not has_selection
    if vision_button != null:
        vision_button.disabled = not has_selection

func _format_time(seconds: float) -> String:
    var total: int = int(seconds)
    var minutes: int = total / 60
    var secs: int = total % 60
    return "%02d:%02d" % [minutes, secs]
