# Headless regression test for the wire drawing technology.
#
# Wire drawing is a medieval technology (prerequisite: metallurgy) that speeds up
# the two metalworking professions that work wire into goods: the blacksmith (in
# the forge and its smithing workshop upgrade) and the jeweler (in the jeweler's
# house). The test checks the technology, its prerequisite, the modifier record
# and the resulting +10% production multiplier on every building these professions
# work in.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

const BUILDINGS := [
    { "id": "forge", "profession": "blacksmith" },
    { "id": "smithing_workshop", "profession": "blacksmith" },
    { "id": "jeweler_house", "profession": "jeweler" },
]

var _failed := false

func _initialize() -> void:
    WATCHDOG.arm(self)
    call_deferred("_run")

func _run() -> void:
    var gd = root.get_node("GameData")
    gd.load_all_data()
    var city = root.get_node("CityData")
    city.setup()

    _test_technology(gd)
    _test_professions(gd)
    _test_modifier(gd)
    _test_multiplier(city)

    WATCHDOG.report_skipped()
    print("WIRE DRAWING TEST FAILED" if _failed else "WIRE DRAWING TEST OK")
    quit(1 if _failed else 0)

func _test_technology(gd: Node) -> void:
    var tech := _record(gd.technologies, "wire_drawing")
    _check(not tech.is_empty(), "wire drawing is a technology")
    if tech.is_empty():
        return
    _check(str(tech.get("era", "")) == "medieval", "wire drawing belongs to the medieval era")
    _check(float(tech.get("science_cost", 0)) > 0, "wire drawing has a science cost")
    _check(_option_has(tech, ["metallurgy"]), "wire drawing needs metallurgy")
    _check(str(tech.get("icon", "")) != "", "wire drawing names an icon")

func _test_professions(gd: Node) -> void:
    # The bonus is expressed per building; these are exactly the buildings the two
    # professions work in, so the modifier below reaches both trades.
    for b in BUILDINGS:
        var building: Dictionary = _record(gd.buildings, str(b["id"]))
        _check(not building.is_empty(), "building exists: " + str(b["id"]))
        if building.is_empty():
            continue
        _check(str(building.get("profession", "")) == str(b["profession"]),
            str(b["id"]) + " is worked by the " + str(b["profession"]))

func _test_modifier(gd: Node) -> void:
    var record: Dictionary = {}
    for entry in gd.modifiers.get("tech_modifiers", []):
        if str(entry.get("tech_id", "")) == "wire_drawing":
            record = entry
            break
    _check(not record.is_empty(), "wire drawing has a tech modifier")
    if record.is_empty():
        return
    var mult: Dictionary = record.get("building_production_multiplier", {})
    for b in BUILDINGS:
        _check(absf(float(mult.get(str(b["id"]), 1.0)) - 1.1) < 0.0001,
            "wire drawing raises " + str(b["id"]) + " output by 10%")

func _test_multiplier(city: Node) -> void:
    var saved_techs: Array = city.unlocked_technologies.duplicate()
    city.unlocked_technologies = []
    for b in BUILDINGS:
        _check(absf(city.get_building_production_multiplier(str(b["id"]), false) - 1.0) < 0.0001,
            "wire drawing gives no bonus before it is researched: " + str(b["id"]))
    city.unlocked_technologies.append("wire_drawing")
    for b in BUILDINGS:
        _check(absf(city.get_building_production_multiplier(str(b["id"]), false) - 1.1) < 0.0001,
            "wire drawing raises " + str(b["id"]) + " production by 10% after research")
    city.unlocked_technologies = saved_techs

func _option_has(tech: Dictionary, ids: Array) -> bool:
    for option in tech.get("prerequisites", []):
        if not option is Array:
            continue
        var matches := true
        for id in ids:
            if not option.has(id):
                matches = false
        if matches:
            return true
    return false

func _record(records: Array, id: String) -> Dictionary:
    for record in records:
        if str(record.get("id", "")) == id:
            return record
    return {}

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failed = true
        push_error("ASSERT: " + message)
        print("ASSERT FAILED: ", message)
