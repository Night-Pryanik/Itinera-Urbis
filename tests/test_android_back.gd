# Headless test of the Android Back button:
#   godot --headless --path . --script res://tests/test_android_back.gd
#
# Android sends Back as a window request; the engine would quit immediately. The
# scene roots disable that auto-quit and forward the request as Escape, so the
# existing cancel chain answers it. A probe node counts the injected key events.

extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
const AndroidBack = preload("res://scripts/android_back.gd")

class EscapeProbe extends Node:
    var presses: int = 0
    var releases: int = 0
    func _input(event: InputEvent) -> void:
        if event is InputEventKey and event.keycode == KEY_ESCAPE:
            if event.pressed:
                presses += 1
            else:
                releases += 1

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state := {"failed": false}
    await process_frame

    AndroidBack.disable_auto_quit()
    check(not quit_on_go_back, "1: the engine does not quit on Back", state)

    var probe := EscapeProbe.new()
    get_root().add_child(probe)
    var menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
    get_root().add_child(menu)
    await process_frame

    menu.notification(Window.NOTIFICATION_WM_GO_BACK_REQUEST)
    await process_frame
    check(probe.presses == 1 and probe.releases == 1,
            "2: the Back request reached the input chain as a complete Escape press", state)

    menu.notification(Window.NOTIFICATION_WM_GO_BACK_REQUEST)
    await process_frame
    check(probe.presses == 1, "3: a repeated request in the same frame is ignored", state)

    await create_timer(0.3).timeout
    menu.notification(Window.NOTIFICATION_WM_GO_BACK_REQUEST)
    await process_frame
    check(probe.presses == 2, "4: a later Back request is forwarded", state)

    menu.queue_free()
    probe.queue_free()
    await process_frame

    if state["failed"]:
        print("ANDROID BACK TEST FAILED")
        quit(1)
        return
    print("ANDROID BACK TEST OK")
    quit(0)

func check(cond: bool, msg: String, state: Dictionary) -> void:
    if cond:
        print("OK: ", msg)
    else:
        state["failed"] = true
        push_error("ASSERT FAILED: " + msg)
