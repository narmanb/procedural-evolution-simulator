extends Node

# The portrait UI is built at runtime. Its full-screen transparent root Control
# must not consume pointer events, or taps on the ecosystem never reach
# Main._unhandled_input(). Visible child panels/buttons retain their normal
# mouse filters and remain fully interactive.
func _ready() -> void:
    get_tree().node_added.connect(_on_node_added)
    call_deferred("_fix_existing_ui_roots")

func _on_node_added(node: Node) -> void:
    _fix_if_canvas_ui_root(node)

func _fix_existing_ui_roots() -> void:
    var scene := get_tree().current_scene
    if scene != null:
        _walk(scene)

func _walk(node: Node) -> void:
    _fix_if_canvas_ui_root(node)
    for child in node.get_children():
        _walk(child)

func _fix_if_canvas_ui_root(node: Node) -> void:
    if node is Control and node.get_parent() is CanvasLayer:
        var control := node as Control
        control.mouse_filter = Control.MOUSE_FILTER_IGNORE
