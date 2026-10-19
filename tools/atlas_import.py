#!/usr/bin/env python3
"""Builds the game's circuits from the F1 Track Environment Atlas (environment_v2 data).

    python3 tools/atlas_import.py /path/to/F1_Track_Atlas_50_Maps

For every one of the 50 circuits this writes data/tracks/<id>.json - a generated base file
that can be rebuilt at any time - and data/tracks/index.json. Hand edits never go in the base
files: they live in data/tracks/overrides/<id>.json, which TrackData merges on top at load,
so re-running the importer never erases manual improvements.

Three layers are kept apart in every file:
  reference  - what the atlas really supplies: centreline, P00-P19 stations, projection,
               Z1-Z8 staging rectangles and the written environment brief
  gameplay   - authored values the atlas does not supply: driving direction, start line,
               pit lane, width, elevation approximations (labelled "authored")
  art        - scenery family, palette and landmark placements (artistic interpretation)

Coordinates: geographic tracks are converted from display units back to metres east /
metres south of the atlas projection centre - a local frame near the circuit, never raw
GPS. In the game, +x is east and +y is south (the 2D world's y points down the screen).
Local-only tracks have no metre scale: they are scaled to their published lap length, and
the file says so ("scale_source").
"""
import json
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "tracks")

# ---------------------------------------------------------------------------- curated table
# id, racing direction (public knowledge, flagged as such), published length for local-only
# tracks, scenery family, extra theme keys, landmarks, elevation range in metres (authored).
CW, ACW = "clockwise", "anticlockwise"
CURATED = {
    "01": ("albert_park", CW, 0, "parkland", {"water": "lake", "buildings": "city", "label": "LAKESIDE PARK"}, ["skyline", "harbour_yachts:lake"], 4),
    "02": ("bahrain", CW, 0, "desert", {"label": "SAKHIR DESERT", "night": True}, ["sakhir_tower", "floodlights"], 8),
    "03": ("shanghai", CW, 0, "airfield", {"water": "lake", "label": "SHANGHAI PLAIN"}, ["shanghai_stands", "skyline"], 4),
    "04": ("barcelona", CW, 0, "scrub", {"label": "MONTMELO HILLS", "extra": "hills"}, ["hill_stands"], 30),
    "05": ("monaco", CW, 0, "street", {"water": "sea", "landmark": "harbour", "label": "MONTE CARLO"}, ["facades", "harbour_yachts:sea", "tunnel", "casino"], 42),
    "06": ("gilles_villeneuve", CW, 0, "parkland", {"water": "lake", "extra": "river", "label": "ILE NOTRE-DAME"}, ["skyline", "rowing_basin"], 3),
    "07": ("paul_ricard", CW, 0, "scrub", {"label": "PROVENCE PLATEAU", "runoff_paint": True}, ["airfield_hangars", "blue_red_runoff"], 10),
    "08": ("spielberg", CW, 0, "forest", {"extra": "hills", "label": "STYRIAN HILLS"}, ["mountains", "bull_sculpture"], 65),
    "09": ("silverstone", CW, 0, "airfield", {"label": "NORTHAMPTONSHIRE AIRFIELD"}, ["wing_building", "airfield_hangars"], 6),
    "10": ("hockenheim", CW, 0, "forest", {"label": "BADEN FOREST"}, ["motodrom_stadium"], 6),
    "11": ("hungaroring", CW, 0, "scrub", {"extra": "hills", "label": "MOGYOROD BOWL"}, ["hill_stands"], 30),
    "12": ("spa", CW, 0, "forest", {"extra": "hills", "label": "ARDENNES FOREST"}, ["valley_forest", "hill_stands"], 100),
    "13": ("monza", CW, 0, "parkland", {"label": "ROYAL PARK OF MONZA"}, ["old_banking", "pedestrian_bridges", "historic_pits", "park_paths"], 6),
    "14": ("marina_bay", ACW, 0, "street", {"water": "sea", "night": True, "label": "MARINA BAY"}, ["skyline", "marina_hotel", "ferris_wheel", "harbour_yachts:sea", "floodlights"], 4),
    "15": ("sochi", CW, 0, "plaza", {"water": "sea", "extra": "hills", "label": "OLYMPIC PARK"}, ["olympic_stadium", "mountains"], 6),
    "16": ("suzuka", CW, 0, "parkland", {"extra": "hills", "label": "SUZUKA HILLS"}, ["ferris_wheel", "crossover_bridge"], 40),
    "17": ("cota", ACW, 0, "scrub", {"label": "TEXAS HILL COUNTRY"}, ["cota_tower", "hill_stands"], 40),
    "18": ("hermanos_rodriguez", CW, 0, "parkland", {"buildings": "city", "label": "MEXICO CITY PARK"}, ["foro_sol_stadium", "skyline"], 4),
    "19": ("interlagos", ACW, 0, "urban_hill", {"water": "lake", "label": "SAO PAULO HILLSIDE"}, ["hill_stands", "favela_housing"], 40),
    "20": ("yas_marina", ACW, 0, "desert", {"water": "sea", "landmark": "harbour", "night": True, "label": "YAS MARINA"}, ["yas_hotel", "harbour_yachts:sea", "floodlights", "turquoise_runoff"], 4),
    "21": ("imola", ACW, 0, "parkland", {"extra": "river", "label": "SANTERNO PARK"}, ["hill_stands"], 40),
    "22": ("nurburgring", CW, 0, "forest", {"extra": "hills", "label": "EIFEL HILLS"}, ["castle_hill", "hill_stands"], 50),
    "23": ("portimao", CW, 0, "scrub", {"extra": "hills", "ground": "a8865a", "label": "ALGARVE HILLS"}, ["hill_stands"], 50),
    "24": ("mugello", CW, 0, "forest", {"extra": "hills", "label": "TUSCAN HILLS"}, ["hill_stands", "mountains"], 40),
    "25": ("sepang", CW, 0, "tropical", {"label": "SEPANG"}, ["umbrella_stands"], 6),
    "26": ("istanbul", ACW, 0, "scrub", {"extra": "hills", "label": "ANATOLIAN HILLS"}, ["hill_stands"], 40),
    "27": ("zandvoort", CW, 0, "dunes", {"water": "sea", "label": "NORTH SEA DUNES"}, ["dunes", "hill_stands"], 20),
    "28": ("magny_cours", CW, 0, "airfield", {"buildings": "villa", "label": "NIVERNAIS FARMLAND"}, ["farmland"], 6),
    "29": ("estoril", CW, 0, "scrub", {"extra": "hills", "label": "ESTORIL HILLS"}, ["hill_stands"], 30),
    "30": ("jeddah", ACW, 0, "street", {"water": "sea", "night": True, "ground": "c9b28a", "label": "JEDDAH CORNICHE"}, ["skyline", "floodlights", "harbour_yachts:sea"], 3),
    "31": ("miami", ACW, 0, "tropical", {"water": "lake", "label": "MIAMI GARDENS"}, ["hard_rock_stadium", "overpass", "harbour_yachts:lake"], 4),
    "32": ("lusail", CW, 0, "desert", {"night": True, "label": "LUSAIL DESERT"}, ["floodlights", "grandstand_large"], 4),
    "33": ("madring", CW, 0, "plaza", {"label": "IFEMA MADRID"}, ["exhibition_halls", "overpass"], 10),
    "34": ("baku", ACW, 0, "street", {"water": "sea", "label": "BAKU OLD CITY"}, ["castle_walls", "flame_towers", "skyline"], 20),
    "35": ("las_vegas", ACW, 0, "street", {"night": True, "ground": "b9a27c", "label": "THE STRIP"}, ["sphere", "casino_towers", "floodlights"], 2),
    "36": ("indianapolis", CW, 0, "airfield", {"label": "SPEEDWAY"}, ["pagoda", "oval_stands"], 3),
    "37": ("buenos_aires", CW, 0, "parkland", {"water": "lake", "label": "BUENOS AIRES PARK"}, ["skyline"], 3),
    "38": ("kyalami", CW, 0, "scrub", {"extra": "hills", "label": "HIGHVELD"}, ["hill_stands"], 30),
    "39": ("watkins_glen", CW, 0, "forest", {"extra": "hills", "label": "FINGER LAKES"}, ["blue_barriers"], 40),
    "40": ("fuji", CW, 4563, "forest", {"extra": "hills", "label": "FUJI FOOTHILLS"}, ["mount_fuji", "grandstand_large"], 40),
    "41": ("jerez", CW, 4428, "scrub", {"label": "JEREZ"}, ["hill_stands"], 10),
    "42": ("aragon", ACW, 5345, "desert", {"extra": "hills", "ground": "b99a6a", "label": "ARAGON SEMI-DESERT"}, ["control_tower"], 40),
    "43": ("buriram", CW, 4554, "tropical", {"label": "BURIRAM"}, ["grandstand_large"], 4),
    "44": ("korea", ACW, 5615, "airfield", {"water": "sea", "label": "YEONGAM"}, ["harbour_yachts:sea"], 4),
    "45": ("brands_hatch", CW, 3916, "forest", {"extra": "hills", "label": "KENT WOODLAND"}, ["hill_stands"], 30),
    "46": ("donington", CW, 4020, "forest", {"label": "DONINGTON PARK"}, ["airfield_hangars"], 25),
    "47": ("zolder", CW, 4011, "forest", {"label": "LIMBURG FOREST"}, [], 15),
    "48": ("dijon", CW, 3801, "forest", {"extra": "hills", "label": "BURGUNDY HILLS"}, [], 30),
    "49": ("okayama", CW, 3703, "forest", {"extra": "hills", "label": "OKAYAMA HILLS"}, [], 30),
    "50": ("le_mans_bugatti", CW, 4185, "airfield", {"label": "LE MANS"}, ["dunlop_bridge", "grandstand_large"], 6),
}
TRACK_TYPE = {"street": "STREET", "forest": "FOREST ROAD", "desert": "HIGH SPEED", "airfield": "FAST SWEEPS",
              "parkland": "HIGH SPEED", "scrub": "TECHNICAL", "urban_hill": "TECHNICAL", "tropical": "FAST SWEEPS",
              "dunes": "TECHNICAL", "plaza": "STREET"}
# The 2D/3D scenery vocabulary each family starts from (TrackScenery / Track3D keys).
FAMILY = {
    "parkland": {"ground": "3f7a3a", "stripe": "47863f", "patch": "376f34", "gravel": "c9b58a", "trees": ["round", "round", "hedge"],
                 "tree_count": 1100, "tree_a": "24582a", "tree_b": "357a38", "buildings": "villa", "building_count": 36, "rocks": 0, "landmark": "ponds", "water": ""},
    "forest": {"ground": "3b6e36", "stripe": "42793c", "patch": "33632f", "gravel": "c9b58a", "trees": ["pine", "pine", "pine", "round"],
               "tree_count": 2000, "tree_a": "173d27", "tree_b": "2a6a40", "buildings": "cabin", "building_count": 40, "rocks": 60, "landmark": "", "water": ""},
    "desert": {"ground": "cdae73", "stripe": "c6a66b", "patch": "bb9a5f", "gravel": "e6d3a4", "trees": ["shrub", "palm", "cactus"],
               "tree_count": 260, "tree_a": "4f7a3a", "tree_b": "6b9a48", "buildings": "adobe", "building_count": 30, "rocks": 140, "landmark": "", "water": ""},
    "street": {"ground": "9aa1a8", "stripe": "a1a8af", "patch": "8f969d", "gravel": "d9cba6", "trees": ["palm", "round"],
               "tree_count": 240, "tree_a": "2f7d46", "tree_b": "4fa85e", "buildings": "city", "building_count": 180, "rocks": 0, "landmark": "", "water": "", "walls": True},
    "airfield": {"ground": "5a8a44", "stripe": "62934a", "patch": "527f3f", "gravel": "cfc39c", "trees": ["round", "shrub"],
                 "tree_count": 300, "tree_a": "3f6b34", "tree_b": "5a8a44", "buildings": "hangar", "building_count": 18, "rocks": 0, "landmark": "airfield", "water": ""},
    "scrub": {"ground": "9c9a5e", "stripe": "a4a265", "patch": "8f8c55", "gravel": "d8ccaa", "trees": ["shrub", "round", "pine"],
              "tree_count": 600, "tree_a": "4a6b3a", "tree_b": "62884a", "buildings": "villa", "building_count": 30, "rocks": 90, "landmark": "", "water": ""},
    "urban_hill": {"ground": "6d8a4f", "stripe": "759356", "patch": "647f48", "gravel": "cfc39c", "trees": ["round", "palm"],
                   "tree_count": 420, "tree_a": "2f6b35", "tree_b": "4f9a48", "buildings": "city", "building_count": 160, "rocks": 0, "landmark": "", "water": "", "extra": "hills"},
    "tropical": {"ground": "4f9a45", "stripe": "57a34c", "patch": "468c3e", "gravel": "d8cba0", "trees": ["palm", "palm", "round"],
                 "tree_count": 700, "tree_a": "1f7a3e", "tree_b": "3fae58", "buildings": "city", "building_count": 40, "rocks": 0, "landmark": "", "water": ""},
    "dunes": {"ground": "d8c48e", "stripe": "d0bb85", "patch": "b9b07a", "gravel": "eadcae", "trees": ["shrub", "shrub", "round"],
              "tree_count": 500, "tree_a": "6f8a4a", "tree_b": "93a85e", "buildings": "villa", "building_count": 24, "rocks": 0, "landmark": "", "water": ""},
    "plaza": {"ground": "a7a9a4", "stripe": "aeb0ab", "patch": "9b9d98", "gravel": "d9cba6", "trees": ["round", "shrub"],
              "tree_count": 260, "tree_a": "3f6b34", "tree_b": "5a8a44", "buildings": "city", "building_count": 90, "rocks": 0, "landmark": "", "water": ""},
}
RAIN = {"forest": 0.32, "parkland": 0.18, "desert": 0.03, "street": 0.12, "airfield": 0.3, "scrub": 0.12, "urban_hill": 0.3,
        "tropical": 0.4, "dunes": 0.25, "plaza": 0.12}

STANDARD_HALF_WIDTH = 6.32         # 6.32 car widths of 2.0 m, halved (see TrackData)
PIT_LANE_M = 300.0                 # TrackData pit lane: 40 m .. 300 m after the line


def length_of(pts):
    return sum(math.dist(pts[i], pts[(i + 1) % len(pts)]) for i in range(len(pts)))


def to_metres(p, env, scale):
    t = env["transform"]
    s = t["display_scale"]
    x = (p[0] - t["display_offset"][0]) / s + t["source_min"][0]
    y = (p[1] - t["display_offset"][1]) / s + t["source_min"][1]
    return (x * scale, y * scale)


def clean(pts):
    """Drops duplicate and nearly duplicate consecutive points and a repeated closing point."""
    out = []
    for p in pts:
        if not out or math.dist(out[-1], p) > 0.5:
            out.append(p)
    while len(out) > 2 and math.dist(out[0], out[-1]) < 0.5:
        out.pop()
    return out


def signed_area(pts):
    # Shoelace in the game frame (+y south / down the screen): positive = clockwise on screen.
    return sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts))) * 0.5


def resample(pts, step):
    """Even spacing along the closed polyline (keeps hairpins: the polyline is followed exactly)."""
    total = length_of(pts)
    n = max(8, int(total / step))
    out, seg, acc = [], 0, 0.0
    lengths = [math.dist(pts[i], pts[(i + 1) % len(pts)]) for i in range(len(pts))]
    for k in range(n):
        target = k * total / n
        while acc + lengths[seg] < target and seg < len(pts) - 1:
            acc += lengths[seg]
            seg += 1
        a, b = pts[seg], pts[(seg + 1) % len(pts)]
        f = (target - acc) / max(lengths[seg], 1e-6)
        out.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
    return out


def turn(pts, i):
    n = len(pts)
    a, b, c = pts[(i - 1) % n], pts[i], pts[(i + 1) % n]
    h1 = math.atan2(b[1] - a[1], b[0] - a[0])
    h2 = math.atan2(c[1] - b[1], c[0] - b[0])
    return (h2 - h1 + math.pi) % (2 * math.pi) - math.pi


def find_start(pts, step):
    """Authored start line: on the longest straight, leaving room for the 300 m pit lane after it
    and the grid behind it. The atlas does not certify a start line, so this is gameplay data."""
    n = len(pts)
    straight = [abs(turn(pts, i)) < 0.035 for i in range(n)]
    best, best_len, i = (0, 0), 0, 0
    # Walk twice round so a straight that crosses the seam is measured whole.
    run_start, run = None, 0
    for k in range(2 * n):
        if straight[k % n]:
            if run_start is None:
                run_start = k
            run += 1
            if run > best_len and run <= n:
                best_len, best = run, (run_start, k)
        else:
            run_start, run = None, 0
    s0, s1 = best
    length = (s1 - s0) * step
    # Keep up to 330 m of straight after the line for the pit lane, and at least 60 m behind it.
    after = max(min(PIT_LANE_M + 30.0, length - 60.0), length * 0.6)
    start = int(s1 - after / step) % n
    return start, length, after


def crossings(pts):
    """Pairs of segments that cross in 2D (a figure-eight, e.g. Suzuka): (i, j) with i < j."""
    out = []
    n = len(pts)

    def inter(p1, p2, p3, p4):
        d = (p2[0] - p1[0]) * (p4[1] - p3[1]) - (p2[1] - p1[1]) * (p4[0] - p3[0])
        if abs(d) < 1e-9:
            return False
        u = ((p3[0] - p1[0]) * (p4[1] - p3[1]) - (p3[1] - p1[1]) * (p4[0] - p3[0])) / d
        v = ((p3[0] - p1[0]) * (p2[1] - p1[1]) - (p3[1] - p1[1]) * (p2[0] - p1[0])) / d
        return 0 < u < 1 and 0 < v < 1
    for i in range(n):
        for j in range(i + 3, n):
            if i == 0 and j == n - 1:
                continue
            if inter(pts[i], pts[(i + 1) % n], pts[j], pts[(j + 1) % n]):
                out.append((i, j))
    return out


def elevation(track_id, amplitude, n, cross):
    """Authored elevation approximation: a smooth, deterministic profile with the circuit's
    rough height range, plus an 8 m bridge where the lap crosses itself. Not survey data."""
    import random
    rng = random.Random(track_id)
    keys = []
    phases = [rng.uniform(0, math.tau) for _ in range(3)]
    for k in range(24):
        f = k / 24.0
        h = sum(math.sin(f * math.tau * (m + 1) + phases[m]) / (m + 1) for m in range(3))
        keys.append([round(f, 4), h])
    lo = min(h for _, h in keys)
    hi = max(h for _, h in keys)
    keys = [[f, round((h - lo) / max(hi - lo, 1e-6) * amplitude, 2)] for f, h in keys]
    bridges = []
    for i, j in cross:
        bridges.append({"over": round(j / n, 4), "under": round(i / n, 4), "height_m": 8.0})
    return {"source": "authored approximation - no elevation data in the atlas", "range_m": amplitude,
            "points": keys, "bridges": bridges}


def build(atlas, stem, env, catalog_entry):
    number = stem[:2]
    tid, direction, published, family, extra, landmarks, amp = CURATED[number]
    geo = bool(env["georeferenced"])
    raw = [to_metres(p, env, 1.0) for p in env["route_points"]]
    scale, scale_source = 1.0, "geographic projection (environment_v2, ~metres)"
    if not geo:
        scale = published / length_of(raw)
        scale_source = "authored: local-only source scaled to the published lap length (%d m, unverified)" % published
    pts = clean([(x * scale, y * scale) for x, y in raw])
    # Racing direction: the atlas order is not certified, so it is set from public knowledge.
    clockwise_now = signed_area(pts) > 0
    if clockwise_now != (direction == CW):
        pts.reverse()
    step = 4.0
    fine = resample(pts, step)
    start, straight_len, after = find_start(fine, step)
    # The pit lane runs along the straight after the line, as long as the straight allows.
    pit_end = int(max(140.0, min(PIT_LANE_M, after - 20.0)))
    pit = {"start": 40, "end": pit_end, "box": int((40 + pit_end) / 2)}
    fine = fine[start:] + fine[:start]
    # Control points for the game's spline: every ~12 m, which keeps hairpins and chicanes.
    ctrl = fine[::3]
    cross = crossings(ctrl)
    length = length_of(ctrl)
    theme = dict(FAMILY[family])
    theme.update({k: v for k, v in extra.items() if k not in ("night",)})
    theme.setdefault("label", catalog_entry["name"].upper())
    theme["rain"] = RAIN[family]
    t = env["transform"]

    def station_xy(x, y):
        return [round(v, 1) for v in to_metres((x, y), env, scale)]
    stations = [{"id": s["station"], "xy": station_xy(s["x"], s["y"]), "lat": s.get("latitude"), "lon": s.get("longitude"),
                 "source_fraction": s["source_order_fraction"]} for s in env["stations"]]
    zones = []
    for z in env["staging_zones"]:
        x0, y0, x1, y1 = z["bounds_xy"]
        a, b = station_xy(x0, y0), station_xy(x1, y1)
        zones.append({"id": z["zone"], "purpose": z["purpose"], "rect_m": [min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])],
                      "reference_station": z["reference_station"], "evidence": z["evidence"], "instruction": z["instruction"]})
    return tid, {
        "id": tid,
        "name": catalog_entry["name"].split(",")[0],
        "display_name": catalog_entry["name"],
        "number": int(number),
        "status": catalog_entry.get("status", ""),
        "source": {"atlas_slug": stem, "dataset": catalog_entry.get("source", ""), "coordinate_system": env["coordinate_system"],
                   "georeferenced": geo, "projection_center": env.get("projection_center"), "orientation": env["orientation"],
                   "scale_source": scale_source, "note": "Community reference centreline, not an FIA engineering map."},
        "gameplay": {"direction": direction, "direction_source": "public knowledge of the race direction; atlas station order is not certified",
                     "start": "authored: on the longest straight (%.0f m), room for the pit lane and a 20-car grid" % straight_len,
                     "width": "6.32 car widths everywhere, narrow sections chosen automatically (authored)"},
        "length_m": round(length),
        "half_width": STANDARD_HALF_WIDTH,
        "curb_width": 1.6,
        "runoff": 10.0 if family == "street" else 13.0,
        "start_offset_m": 0.0,
        "scale": 1.0,
        "sector_fractions": [0.33, 0.66],
        "checkpoint_count": 16,
        "pit": pit,
        "type": TRACK_TYPE[family],
        "family": family,
        "night": bool(extra.get("night", False)),
        "theme": theme,
        "landmarks": landmarks,
        "elevation": elevation(tid, amp, len(ctrl), cross),
        "stations": stations,
        "zones": zones,
        "environment": {k: env.get(k, "") for k in ("identity", "terrain", "vegetation", "water", "architecture", "landmarks", "palette", "craft", "limitations")},
        "control_points": [[round(x, 2), round(y, 2)] for x, y in ctrl],
    }


def main():
    atlas = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Downloads/F1_Track_Atlas_50_Maps")
    catalog = {c["slug"]: c for c in json.load(open(os.path.join(atlas, "catalog.json")))}
    index = json.load(open(os.path.join(atlas, "coordinate_data", "index.json")))
    os.makedirs(os.path.join(OUT, "overrides"), exist_ok=True)
    roster = []
    for entry in index:
        stem = os.path.basename(entry["file"]).replace("_environment.json", "")
        env = json.load(open(os.path.join(atlas, entry["file"])))
        tid, data = build(atlas, stem, env, catalog[stem])
        with open(os.path.join(OUT, tid + ".json"), "w") as f:
            json.dump(data, f, separators=(",", ":"))
        roster.append({"id": tid, "name": data["name"], "display_name": data["display_name"], "number": data["number"],
                       "family": data["family"], "type": data["type"], "length_m": data["length_m"], "night": data["night"],
                       "georeferenced": data["source"]["georeferenced"], "status": "imported"})
        print("%-20s %5d m  %-13s %s  cross %d" % (tid, data["length_m"], data["gameplay"]["direction"], data["family"], len(data["elevation"]["bridges"])))
    with open(os.path.join(OUT, "index.json"), "w") as f:
        json.dump(roster, f, indent=1)
    print("%d circuits written to %s" % (len(roster), OUT))


if __name__ == "__main__":
    main()
