# consumption_ui.gd
# A common view of OCCUPATIONAL CONSUMPTION (data/consumption.json)
# in the interface: it turns the GameData.get_profession_consumption() entries into
# ready-made display rows of the kind "Feathers: 2 units/sec (+25% to production)".
#
# A single source of truth for all the places where the player sees the expense
# of a profession:
#   * scripts/map_tooltip.gd    — the extended hex tooltip and the left column
#                                 of the control panel (map improvements);
#   * scripts/buildings_tab.gd  — the building details tooltip (the "Buildings" tab);
#   * scripts/building_panel.gd — the building details window.
# The row format used to live inside map_tooltip.gd, which is why each new
# place would have copy-pasted the rate calculation and the labels.
#
# The consumption itself is not stored here: only the occupational entries
# (see docs.md, the section "Professions and resource consumption"). Food, pasture
# feed and the recipe demand of buildings are DIFFERENT consumption, and it is not
# shown in these rows.
#
# Public API:
#   - format_rate(value)                        : String  — "2" / "0.5"
#   - build_rows(prof_id, workers := 1)         : Array   — the display rows
#   - build_rows_for_building(building_id, w := 1) : Array — the same by the building profession
class_name ConsumptionUi


# Formats the rate (units/sec): integer values without a fractional part,
# fractional ones with a single digit ("1.5").
static func format_rate(value: float) -> String:
    if value == floor(value):
        return str(int(value))
    return "%.1f" % value


# The rate together with the unit of measure: "2 units/sec". The unit is a single
# msgid of its own ("units/sec"), and not a part of a sentence with the number
# baked in: the number is already formatted by format_rate, and a translator needs
# the unit, not a dozen phrases that each repeat it. This is the only place where the
# unit is attached to the rate — the callers format the value and the unit through
# here, so the two can never drift apart.
static func format_rate_with_unit(value: float) -> String:
    return "%s %s" % [format_rate(value), TranslationServer.translate("units/sec")]


# Range form for tiered groups whose members wear out at different speeds: "0.3–0.5 units/sec",
# collapsing to a single number when both rounded endpoints coincide.
static func format_rate_range_with_unit(min_value: float, max_value: float) -> String:
    var lo := format_rate(minf(min_value, max_value))
    var hi := format_rate(maxf(min_value, max_value))
    if lo == hi:
        return "%s %s" % [lo, TranslationServer.translate("units/sec")]
    return "%s–%s %s" % [lo, hi, TranslationServer.translate("units/sec")]


# Formats the production-bonus suffix: " (+20% to production)" or " (+10–20% to production)".
static func format_bonus_suffix(min_bonus: float, max_bonus: float) -> String:
    var hi_pct := int(round(maxf(min_bonus, max_bonus) * 100.0))
    if hi_pct <= 0:
        return ""
    var lo_pct := maxi(0, int(round(minf(min_bonus, max_bonus) * 100.0)))
    if lo_pct == hi_pct or lo_pct <= 0:
        return TranslationServer.translate(" (+%d%% to production)") % hi_pct
    return TranslationServer.translate(" (+%d–%d%% to production)") % [lo_pct, hi_pct]


# The form of the numeral for a count of working buildings. The rule of the language
# lives in its catalog ("Plural-Forms"), so no language is preferred here: English needs
# "1 building / 2 buildings", Russian and Polish add a case for 2-4 that 5+ does not
# share, and a language with a single form needs nothing at all.
#
# tr_n() is not available in a static function, so the plural call goes through
# TranslationServer, which takes the same plural rule the catalog declared.
static func _buildings_plural(count: int) -> String:
    return str(TranslationServer.translate_plural(
            "building", "buildings", count, "consumption_buildings"))


# Assembles the display rows of the occupational consumption of a profession.
#
# workers — how many WORKING objects share the same profession:
#   1 (by default) — one improvement on the map or one building: the rate
#     is the same as in the extended hex tooltip;
#   0 — there are no working objects: the rate remains "per one object", but
#     "(no working buildings)" is added to the label — so that the building details window
#     explains why there is no expense with working slots;
#   N > 1 — the rate is multiplied by N, and "(N buildings)" appears in the label
#     (the building details window shows the total over the working buildings).
#
# Each row:
#   { "display_key": String   — the product id or "@group" (the UI key),
#     "name": String,          — the product/group name,
#     "icon": String,          — the icon file name ("" — there is no icon),
#     "is_group": bool,        — a group entry (any member is written off),
#     "per_sec": float,        — the total rate of expense, units/sec,
#     "production_bonus": float, — 0.5 = +50% to production; 0 = no bonus,
#     "workers": int,
#     "rate_label": String,    — "2 units/sec (+25% to production)",
#     "label": String }        — "Feathers: 2 units/sec (+25% to production)"
static func build_rows(prof_id: String, workers: int = 1, building_id: String = "") -> Array:
    var rows: Array = []
    if prof_id.is_empty():
        return rows
    # workers = 0 does not zero the rate: the expense per one object stays visible,
    # the absence of workers is reflected only in the label.
    var count := maxi(workers, 0)
    var multiplier := float(maxi(count, 1))
    for entry in GameData.get_profession_consumption(prof_id, building_id):
        var amount := int(entry.get("amount", 0))
        var interval := float(entry.get("interval", 0.0))
        var bonus := float(entry.get("production_bonus", 0.0))
        var bounds: Dictionary = GameData.get_entry_rate_bonus_bounds(entry)
        var active_pid := ""
        if not bounds.is_empty() and not bool(entry.get("consume_all", false)):
            active_pid = _active_tier_member_in_storage(entry, amount)
            if not active_pid.is_empty():
                interval = GameData.get_entry_member_interval(entry, active_pid)
                bonus = GameData.get_entry_member_bonus(entry, active_pid)
        # The display is per second: the amount of the entry divided by its interval.
        # interval = 0 means "per tick", and the simulation tick equals a second —
        # there is nothing to divide by, the rate equals amount.
        var per_sec := float(amount) if interval <= 0.0 else float(amount) / interval
        per_sec *= multiplier
        var rate_label := ""
        if not bounds.is_empty() and active_pid.is_empty():
            rate_label = _format_range_rate_label(
                float(bounds["rate_min"]) * multiplier,
                float(bounds["rate_max"]) * multiplier,
                float(bounds["bonus_min"]),
                float(bounds["bonus_max"]),
                count)
        else:
            rate_label = _format_rate_label(per_sec, bonus, count)
        rows.append({
            "display_key": str(entry.get("display_key", entry.get("product_id", ""))),
            "name": str(entry.get("product_name", entry.get("product_id", ""))),
            # GameData puts the icon in both cases: a product has its own,
            # a group has the first of its members that has an icon set.
            "icon": str(entry.get("icon", "")),
            "is_group": bool(entry.get("is_group", false)),
            "per_sec": per_sec,
            "production_bonus": bonus,
            "workers": count,
            "rate_label": rate_label,
        })
    for row in rows:
        # The product name is added here, and not in _format_rate_label(): the places
        # where the name is drawn by the helper with an icon (the "Buildings" tab,
        # the building window) take name/display_key and append it to the
        # "rate_label" row.
        row["label"] = "%s: %s" % [row["name"], row["rate_label"]]
    return rows


# The same as build_rows, scoped to building_id so both profession-wide rules and
# rules restricted to that building via "buildings" are shown. For a building
# without a profession — an empty array.
static func build_rows_for_building(building_id: String, workers: int = 1) -> Array:
    if building_id.is_empty():
        return []
    return build_rows(GameData.get_profession_for_building(building_id), workers, building_id)


# The part of the row after the product name: "2 units/sec (+25% to production)".
# production_bonus is displayed so that the player sees why a profession needs
# this supply: while the resource is enough, production goes with a bonus, and when
# there is not enough — it rolls back to the base multiplier (the production itself
# does not stop).
static func _format_rate_label(per_sec: float, bonus: float, workers: int) -> String:
    var text := format_rate_with_unit(per_sec)
    if workers > 1:
        # Several working objects of one type share the expense — we show
        # the total and how much it gives (the building details window).
        text += " (%d %s)" % [workers, _buildings_plural(workers)]
    elif workers == 0:
        text += TranslationServer.translate(" (no working buildings)")
    if bonus > 0.0:
        text += TranslationServer.translate(" (+%d%% to production)") % int(round(bonus * 100.0))
    return text


static func _format_range_rate_label(rate_min: float, rate_max: float, bonus_min: float, bonus_max: float, workers: int) -> String:
    var text := format_rate_range_with_unit(rate_min, rate_max)
    if workers > 1:
        text += " (%d %s)" % [workers, _buildings_plural(workers)]
    elif workers == 0:
        text += TranslationServer.translate(" (no working buildings)")
    text += format_bonus_suffix(bonus_min, bonus_max)
    return text


# Highest-tier member of a tiered group with a full pack of `amount` in storage, or
# the highest-tier member with any positive stock when none has a full pack yet.
static func _active_tier_member_in_storage(entry: Dictionary, amount: int) -> String:
    var ordered: Array = GameData.get_entry_members_ordered_by_tier(entry)
    if amount > 0:
        for raw_pid in ordered:
            var pid := str(raw_pid)
            if not pid.is_empty() and CityData.get_storage_amount(pid) >= amount:
                return pid
    for raw_pid in ordered:
        var pid := str(raw_pid)
        if not pid.is_empty() and CityData.get_storage_amount(pid) > 0:
            return pid
    return ""
