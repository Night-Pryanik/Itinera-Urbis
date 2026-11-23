# Nested product groups (headless):
#   godot --headless --path . --script res://tests/test_nested_product_groups.gd
#
# The loader expands "@<group>" members once, so every reader of GameData.product_groups sees a flat
# list. The validator reads the declarations instead: a nested group is a valid member, a missing
# one is a broken reference, and a circle of references must be reported instead of silently
# cutting the recursion short.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

const DataLoader = preload("res://scripts/data_loader.gd")
const DataValidator = preload("res://scripts/data_validator.gd")

func _initialize():
    WATCHDOG.arm(self)
    var state = {"failed": false}
    _test_real_data(state)
    _test_expansion(state)
    _test_validation(state)
    WATCHDOG.report_skipped()
    if state["failed"]:
        print("NESTED GROUPS TEST FAILED")
        quit(1)
    else:
        print("NESTED GROUPS TEST OK")
        quit(0)


func _test_real_data(state: Dictionary):
    var loader = DataLoader.new()
    loader.load_all_data([])

    var declared: Array = loader.product_group_declarations.get("consumer_goods", [])
    check(declared.has("@lamp_oils"),
            "consumer_goods must declare the nested lamp_oils group", state)
    var oils: Array = loader.product_groups.get("lamp_oils", [])
    check(oils.has("vegetable_oil") and oils.has("white_naphtha") and oils.has("shale_oil"),
            "the lamp oils must include the ancient vegetable fuel and both mineral oils", state)
    var members: Array = loader.product_groups.get("consumer_goods", [])
    check(members.has("vegetable_oil") and members.has("white_naphtha") and members.has("shale_oil"),
            "all three lamp oils must be in the expanded basket", state)
    check(not members.has("@lamp_oils"),
            "the expanded basket must hold products, not a group key", state)
    check(members.size() == 8, "the basket must still hold all eight goods", state)

    var problems: Array = DataValidator.new().validate(loader)
    check(_only(problems, "group_cycle").is_empty(),
            "the real data must have no nested groups in a circle", state)
    check(_only(problems, "group_member_group").is_empty(),
            "the real data must have no missing nested group", state)
    loader.free()


func _test_expansion(state: Dictionary):
    var loader = DataLoader.new()
    var declarations := {
        "basket": ["salt", "@oils", "salt"],
        "oils": ["@deep", "lamp_oil"],
        "deep": ["@basket", "tar"],
        "plain": ["salt", "soap"],
        "dup": ["salt", "@plain", "soap"],
    }
    var expanded: Dictionary = loader._expand_product_groups(declarations)

    var basket: Array = expanded.get("basket", [])
    check(basket.has("tar") and basket.has("lamp_oil") and basket.has("salt"),
            "a nested group brings its goods into the parent even through a cycle", state)
    check(basket.size() == 3, "a repeated good must be written once: %s" % str(basket), state)
    var dup: Array = expanded.get("dup", [])
    check(dup.size() == 2, "a good nested and written directly must be written once: %s" % str(dup), state)
    check(expanded.has("deep") and expanded.has("plain"),
            "every declared group must be present after the expansion", state)
    loader.free()


func _test_validation(state: Dictionary):
    var gd = load("res://scripts/GameData.gd").new()
    gd.products = {
        "salt": {"id": "salt", "name": "Salt"},
        "soap": {"id": "soap", "name": "Soap"},
    }
    gd.product_group_names = {
        "basket": "Basket",
        "oils": "Oils",
        "a": "A",
        "b": "B",
        "c": "C",
        "self": "Self",
        "missing": "Missing",
    }
    gd.product_group_declarations = {
        "basket": ["salt", "@oils"],
        "oils": ["@basket", "soap"],
        "a": ["@b"],
        "b": ["@c"],
        "c": ["@a", "salt"],
        "self": ["@self"],
        "missing": ["@ghost_group"],
    }
    # A group of the running data is already expanded; the validator must read the declarations.
    gd.product_groups = {"ignore": ["salt"]}

    var problems: Array = DataValidator.new().validate(gd)
    var cycles: Array = _only(problems, "group_cycle")
    check(cycles.size() == 3, "expected three circles, got %d" % cycles.size(), state)
    var chains := []
    for problem in cycles:
        chains.append(str(problem.get("chain", "")))
        check(problem.has("message") and not str(problem.get("message", "")).is_empty(),
                "a circle must carry a ready-made message", state)
    check(chains.has("basket -> oils -> basket"),
            "the two-group circle must be reported with its chain: %s" % str(chains), state)
    check(chains.has("a -> b -> c -> a"),
            "a circle of three groups must be reported with its chain: %s" % str(chains), state)
    check(chains.has("self -> self"),
            "a group nested in itself must be reported: %s" % str(chains), state)

    var missing: Array = _only(problems, "group_member_group")
    check(missing.size() == 1, "expected one missing nested group, got %d" % missing.size(), state)
    check(not missing.is_empty() and str(missing[0].get("ref_id", "")) == "@ghost_group",
            "the missing nested group must be named by its reference", state)
    check(_only(problems, "group_member").is_empty(),
            "a nested @group must not be checked as a product", state)
    gd.free()


func _only(problems: Array, kind: String) -> Array:
    var out: Array = []
    for problem in problems:
        if str(problem.get("kind", "")) == kind:
            out.append(problem)
    return out


func check(cond: bool, msg: String, state: Dictionary) -> void:
    if not cond:
        push_error("ASSERT: " + msg)
        print("ASSERT FAILED: ", msg)
        state["failed"] = true
