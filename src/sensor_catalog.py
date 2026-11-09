"""Temperature zone keys cross-checked against Stats' model-specific catalog.

https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift
Zone numbers identify sensors, not physical CPU/GPU core numbers.
"""
import re

ZONES = {
    1: [
        ("CPU", "高能效", "Tp09 Tp0T"),
        ("CPU", "高性能", "Tp01 Tp05 Tp0D Tp0H Tp0L Tp0P Tp0X Tp0b"),
        ("GPU", "", "Tg05 Tg0D Tg0L Tg0T"),
    ],
    2: [
        ("CPU", "高能效", "Tp1h Tp1t Tp1p Tp1l"),
        ("CPU", "高性能", "Tp01 Tp05 Tp09 Tp0D Tp0X Tp0b Tp0f Tp0j"),
        ("GPU", "", "Tg0f Tg0j"),
    ],
    3: [
        ("CPU", "高能效", "Te05 Te0L Te0P Te0S"),
        ("CPU", "高性能", "Tf04 Tf09 Tf0A Tf0B Tf0D Tf0E Tf44 Tf49 Tf4A Tf4B Tf4D Tf4E"),
        ("GPU", "", "Tf14 Tf18 Tf19 Tf1A Tf24 Tf28 Tf29 Tf2A"),
    ],
    4: [
        ("CPU", "高能效", "Te05 Te0S Te09 Te0H"),
        ("CPU", "高性能", "Tp01 Tp05 Tp09 Tp0D Tp0V Tp0Y Tp0b Tp0e"),
        ("GPU", "", "Tg0K Tg0L Tg0d Tg0e Tg0j Tg0k"),
    ],
}


def sensor_catalog(chip):
    match = re.search(r"Apple M([1-4])\b", chip)
    if not match:
        return {}
    generation = int(match[1])
    zones = list(ZONES[generation])
    if generation == 4:
        gpu_keys = "Tg1U Tg1k" if "Pro" in chip or "Max" in chip else "Tg0G Tg0H"
        zones.insert(2, ("GPU", "", gpu_keys))
    catalog = {}
    for group, zone, keys in zones:
        for index, key in enumerate(keys.split(), 1):
            catalog[key] = {"group": group, "label": f"{group} {zone}温区 {index}"}
    return catalog
