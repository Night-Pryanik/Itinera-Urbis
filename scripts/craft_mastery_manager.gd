# craft_mastery_manager.gd
# The mastery of the city in the making of a particular good (see docs.md, "Production mastery").
#
# A good earns a rank for every threshold of units made by the CITY'S BUILDINGS. The counter counts
# the releases of recipes, not the goods bought from towns or gathered on the map: the masters of
# the city grow skilled by working, not by trading. The counter is cumulative and belongs to the
# good alone, so the skill in brandy does nothing for the rum of the same distillery.
#
# A good made with an additional ingredient is booked to its base good: the mastery of the garment
# is the mastery of the garment, whatever dye went into it.
extends Node

signal rank_gained(product_id: String, rank: int)

const DEFAULT_THRESHOLDS := [1000, 3000]

# product id -> cumulative units made by the buildings of the city.
var produced := {}
# product id -> the rank earned by those units.
var ranks := {}


func _ready() -> void:
    set_process(false)
    rank_gained.connect(_on_rank_gained)


# A rank is a surprise the player did not have to look for, so it is said out loud: the important
# line of the HUD goes into the journal of the game (hud_message.gd).
func _on_rank_gained(pid: String, rank: int) -> void:
    var map = get_node_or_null("/root/MainMap")
    if map == null or map.hud == null:
        return
    map.hud.show_message(tr("Production mastery of %s: rank %d, +%s to quality")
            % [GameData.get_product_name(pid), rank, rank_stars(rank)],
            GameData.HUD_MESSAGE_IMPORTANT)


# The cumulative units the city must make for each rank, ascending. The thresholds live in the
# balance data; the code keeps a default for a data file that does not declare them yet.
func thresholds() -> Array:
    var raw = GameData.game_balance.get("mastery_thresholds", DEFAULT_THRESHOLDS)
    var out: Array = []
    if raw is Array:
        for value in raw:
            var threshold := int(value)
            if threshold > 0:
                out.append(threshold)
    if out.is_empty():
        return DEFAULT_THRESHOLDS.duplicate()
    out.sort()
    return out


func rank_for_units(units: int) -> int:
    var rank := 0
    for threshold in thresholds():
        if units >= int(threshold):
            rank += 1
    return rank


# The id a rank is measured against. A generated id names a good with an additional ingredient;
# the base is the good the masters have learned to make.
func mastery_product_id(pid: String) -> String:
    var base := str(GameData.parse_generated_id(pid).get("base", ""))
    return base if not base.is_empty() else pid


func rank_of(pid: String) -> int:
    return int(ranks.get(mastery_product_id(pid), 0))


func units_of(pid: String) -> int:
    return int(produced.get(mastery_product_id(pid), 0))


# Books one release of a building's recipe. A release that crosses more than one threshold at
# once pays every rank it has earned, in order.
func record_production(pid: String, amount: int) -> void:
    if amount <= 0:
        return
    var key := mastery_product_id(pid)
    if key.is_empty() or not GameData.products.has(key) or GameData.is_virtual_product(key):
        return
    var old_rank := rank_of(key)
    produced[key] = units_of(key) + amount
    var new_rank := rank_for_units(units_of(key))
    if new_rank <= old_rank:
        return
    ranks[key] = new_rank
    emit_signal("rank_gained", key, new_rank)


# The stars of a rank. The glyphs come from the quality scale, so the first rank adds one star
# and the second adds two.
func rank_stars(rank: int) -> String:
    var levels := GameData.get_quality_levels()
    if rank <= 0 or levels.is_empty():
        return ""
    return GameData.get_quality_stars(str(levels[0])).repeat(rank)


# The ranks the Effects tab lists: one row per good the city has mastered.
func mastery_records() -> Array:
    var out: Array = []
    for pid in ranks:
        var rank := int(ranks[pid])
        if rank <= 0:
            continue
        out.append({
            "product_id": str(pid),
            "product_name": GameData.get_product_name(str(pid)),
            "rank": rank,
            "stars": rank_stars(rank),
        })
    out.sort_custom(func(a, b):
        return str(a.get("product_name", "")) < str(b.get("product_name", "")))
    return out


# --- THE SAVE ------------------------------------------------------------------

# The counters are copied: the caller writes the record to disk while the city goes on making
# goods, and a snapshot that aliases the live counters is not a snapshot.
func serialize() -> Dictionary:
    return {
        "produced": produced.duplicate(true),
        "ranks": ranks.duplicate(true),
    }


# JSON reads every number as a float, so the units and the ranks are coerced on the way back in.
func deserialize(state: Dictionary) -> void:
    if not (state is Dictionary) or state.is_empty():
        return
    produced = _coerce_counters(state.get("produced", {}))
    ranks = _coerce_counters(state.get("ranks", {}))


func _coerce_counters(raw) -> Dictionary:
    var out := {}
    if not (raw is Dictionary):
        return out
    for pid in raw:
        var value := int(raw[pid])
        if value > 0:
            out[str(pid)] = value
    return out
