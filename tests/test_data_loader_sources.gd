# Source index of the data loader (headless):
#   godot --headless --path . --script res://tests/test_data_loader_sources.gd
#
# A validator problem points at a file and a line, and that line is found by scanning
# the JSON text. An example record inside a comment may carry a real identifier: such an
# example must never be reported as the declaration. The cleaner keeps the line breaks,
# so the numbers still refer to the file the author sees in the editor.
extends SceneTree

# Hang watchdog: an aborted _initialize() would otherwise look like eternal silence.
const WATCHDOG = preload("res://tests/watchdog.gd")

const JsonUtils = preload("res://scripts/json_utils.gd")

func _initialize():
    WATCHDOG.arm(self)
    var state = {"failed": false}
    _test_commented_examples(state)
    WATCHDOG.report_skipped()
    if state["failed"]:
        print("DATA LOADER SOURCES TEST FAILED")
        quit(1)
    else:
        print("DATA LOADER SOURCES TEST OK")
        quit(0)

func _test_commented_examples(state: Dictionary) -> void:
    var text := """{
  // Example: { "id": "salt", "type": "raw" }
  "resources": [
    { "id": "salt", "type": "raw" },
    /* An example of a multi-line record:
       { "id": "pepper", "type": "raw" }
    */
    { "id": "pepper", "type": "raw" }
  ],
  // A commented-out rule: { "resource": "@boats", "profession": ["sailor"] }
  "consumption": [
    { "resource": "@boats", "profession": ["sailor"], "amount": 1 }
  ],
  // Example of a top-level key: "game_balance": {}
  "game_balance": {
    "city": { "tax": 1 }
  }
}
"""
    var data = JsonUtils.parse(text)
    check(data is Dictionary, "the synthetic data parses", state)
    if not (data is Dictionary):
        return

    var loader = load("res://scripts/data_loader.gd").new()
    loader._remember_sources("res://data/test.json", text, data)
    # Every number is the line of the real declaration, not of the example above it.
    var expected := {
        "resources:salt": 4,
        "resources:pepper": 8,
        "consumption:@boats": 12,
        "@key:game_balance": 15,
    }
    for key in expected.keys():
        check(loader.entity_sources.has(key), "the source index has %s" % key, state)
        if loader.entity_sources.has(key):
            var actual := int(loader.entity_sources[key]["line"])
            check(actual == int(expected[key]),
                    "%s points at line %d, expected %d" % [key, actual, int(expected[key])], state)
    loader.free()

func check(cond: bool, msg: String, state: Dictionary) -> void:
    if not cond:
        push_error("ASSERT: " + msg)
        print("ASSERT FAILED: ", msg)
        state["failed"] = true
