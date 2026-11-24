# Headless test of the HUD fitting its contents:
#   godot --headless --path . --script res://tests/test_hud_fit.gd
#
# The HUD panel is sized from the minimum size of its VBoxContainer. A row can reflow a frame
# after its text is set; when that happens the panel must grow in the same frame. Otherwise a
# container with GROW_DIRECTION_BOTH grows around its centre and pushes its first row above
# the top of the screen before the panel catches up.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

func _initialize():
    WATCHDOG.arm(self)
    _run()

func _check(condition: bool, label: String, state: Dictionary) -> void:
    if not condition:
        state["failed"] = true
        print("FAIL: " + label)

func _run() -> void:
    var state := {"failed": false}

    var hud = load("res://scripts/hud_message.gd").new()
    var vbox := VBoxContainer.new()
    vbox.name = "VBoxContainer"
    vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
    var message_label := Label.new()
    message_label.name = "MapMessageLabel"
    vbox.add_child(message_label)
    hud.add_child(vbox)
    get_root().add_child(hud)
    await process_frame

    var initial_size: Vector2 = hud.size
    var tall := Label.new()
    tall.custom_minimum_size = Vector2(0, 120)
    vbox.add_child(tall)
    await process_frame

    _check(hud.size.y >= initial_size.y + 100.0,
        "the panel grows in the same frame as the content (got %s, was %s)"
            % [str(hud.size), str(initial_size)], state)
    _check(vbox.position.y >= 0.0,
        "the content stays below the top of the panel (got %.1f)" % vbox.position.y, state)

    hud.queue_free()
    if state["failed"]:
        print("HUD FIT TEST FAILED")
        quit(1)
    else:
        print("HUD FIT TEST OK")
        quit(0)
