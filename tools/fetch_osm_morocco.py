import json
import math
import os
import urllib.request
import urllib.parse

os.makedirs("data", exist_ok=True)

print("=== [10%] Téléchargement des données OpenStreetMap (Casablanca - Autoroute A1 - Rabat) ===")

# 1. Fetch real driving route geometry between Casablanca (Maarif / Rond-Point d'Europe) and Rabat (Agdal / Hassan)
# via OSRM (OpenStreetMap Routing Machine) + Overpass API for landmarks & roundabouts
osrm_url = (
    "https://router.project-osrm.org/route/v1/driving/"
    "-7.6324,33.5883;"  # Casablanca (Bd Zerktouni / Rond-point d'Europe)
    "-7.5898,33.5952;"  # Casablanca (Ain Sebaa / Entrée Autoroute A1)
    "-7.3849,33.6835;"  # Mohammedia (Autoroute A1)
    "-7.1597,33.7894;"  # Bouznika (Péage & Aire de repos A1)
    "-7.0370,33.8510;"  # Skhirat (Autoroute A1)
    "-6.8685,33.9716;"  # Rabat (Entrée Hay Riad / Agdal)
    "-6.8361,34.0181"   # Rabat (Avenue Mohammed V / Hassan)
    "?overview=full&geometries=geojson&steps=true"
)

osm_data = {
    "source": "OpenStreetMap (OSRM + Overpass Morocco)",
    "cities": {
        "casablanca": {"lat": 33.5883, "lon": -7.6324, "name_ar": "الدار البيضاء - شارع الزرقطوني وأنفا"},
        "mohammedia": {"lat": 33.6835, "lon": -7.3849, "name_ar": "المحمدية - الطريق السيار A1"},
        "bouznika": {"lat": 33.7894, "lon": -7.1597, "name_ar": "بوزنيقة - محطة الأداء والاستراحة"},
        "skhirat": {"lat": 33.8510, "lon": -7.0370, "name_ar": "الصخيرات - الطريق السيار A1"},
        "rabat": {"lat": 34.0181, "lon": -6.8361, "name_ar": "الرباط - أكدال وشارع محمد الخامس"}
    },
    "raw_coordinates": [],
    "osm_elements": [],
    "routes_3d": {}
}

try:
    req = urllib.request.Request(osrm_url, headers={"User-Agent": "Siya9aMaroc3D/1.0"})
    with urllib.request.urlopen(req, timeout=12) as resp:
        route_json = json.loads(resp.read().decode("utf-8"))
        if route_json.get("routes"):
            coords = route_json["routes"][0]["geometry"]["coordinates"]
            osm_data["raw_coordinates"] = coords
            osm_data["distance_km"] = round(route_json["routes"][0]["distance"] / 1000.0, 1)
            print(f"[OSM] Route Casa -> Rabat téléchargée avec succès : {len(coords)} points GPS ({osm_data['distance_km']} km)")
except Exception as e:
    print(f"[OSM] Fallback sur coordonnées GPS OSM pré-échantillonnées : {e}")

# Also query Overpass API for real junctions/roundabouts in Casa & Rabat
overpass_query = """
[out:json][timeout:10];
(
  node["highway"="motorway_junction"](33.55,-7.65,34.03,-6.80);
  way["junction"="roundabout"](33.57,-7.65,33.60,-7.61);
);
out body 40;
"""
try:
    overpass_url = "https://overpass-api.de/api/interpreter?data=" + urllib.parse.quote(overpass_query)
    req2 = urllib.request.Request(overpass_url, headers={"User-Agent": "Siya9aMaroc3D/1.0"})
    with urllib.request.urlopen(req2, timeout=10) as resp2:
        ov_json = json.loads(resp2.read().decode("utf-8"))
        elements = ov_json.get("elements", [])
        for el in elements[:30]:
            osm_data["osm_elements"].append({
                "id": el.get("id"),
                "type": el.get("type"),
                "lat": el.get("lat"),
                "lon": el.get("lon"),
                "tags": el.get("tags", {})
            })
        print(f"[OSM Overpass] {len(osm_data['osm_elements'])} échangeurs / ronds-points marocains extraits.")
except Exception as e:
    print(f"[OSM Overpass] Info: {e}")

# Ensure we have rich, downsampled 3D road splines derived from the OSM GPS coordinates
raw_coords = osm_data.get("raw_coordinates", [])
if len(raw_coords) < 20:
    # Accurate GPS waypoints along Casa -> A1 -> Rabat
    raw_coords = [
        [-7.6324, 33.5883], [-7.6250, 33.5910], [-7.6120, 33.5935], [-7.5898, 33.5952],
        [-7.5500, 33.6050], [-7.5000, 33.6280], [-7.4400, 33.6550], [-7.3849, 33.6835],
        [-7.3100, 33.7200], [-7.2300, 33.7550], [-7.1597, 33.7894], [-7.0900, 33.8200],
        [-7.0370, 33.8510], [-6.9700, 33.8950], [-6.9100, 33.9400], [-6.8685, 33.9716],
        [-6.8500, 33.9950], [-6.8361, 34.0181]
    ]

# Sample 80 points from Casa to Rabat and map them into a compressed 3D playable corridor
# (So the player can experience Casa -> Autoroute A1 -> Péage Bouznika -> Rabat in ~3.2 km of dense 3D road!)
step = max(1, len(raw_coords) // 80)
sampled = raw_coords[::step]
if sampled[-1] != raw_coords[-1]:
    sampled.append(raw_coords[-1])

# Project GPS (lon, lat) relative to start point and compress scale so it's playable & curvy
lon0, lat0 = sampled[0]
autoroute_3d_points = []
accum_z = 0.0
prev_x = 0.0
for i, (lon, lat) in enumerate(sampled):
    # Normalized progress 0..1 from Casa to Rabat
    t = i / max(1, len(sampled) - 1)
    # Use real lateral deviation from the straight Casa-Rabat azimuth for authentic curves
    expected_lon = sampled[0][0] + t * (sampled[-1][0] - sampled[0][0])
    expected_lat = sampled[0][1] + t * (sampled[-1][1] - sampled[0][1])
    dev_lon = (lon - expected_lon) * 85000.0
    dev_lat = (lat - expected_lat) * 111000.0
    lateral_offset = max(-140.0, min(140.0, (dev_lon - dev_lat) * 0.025))
    z_pos = -t * 2400.0  # 2.4 km playable 3D highway + urban ends
    autoroute_3d_points.append({
        "index": i,
        "t": round(t, 4),
        "lon": round(lon, 5),
        "lat": round(lat, 5),
        "x": round(lateral_offset, 2),
        "y": 0.0,
        "z": round(z_pos, 2)
    })

osm_data["routes_3d"]["casa_rabat_a1"] = autoroute_3d_points

with open("data/morocco_osm_roads.json", "w", encoding="utf-8") as f:
    json.dump(osm_data, f, ensure_ascii=False, indent=2)

print(f"=== [10% OK] Fichier data/morocco_osm_roads.json généré ({len(autoroute_3d_points)} points 3D) ===")
