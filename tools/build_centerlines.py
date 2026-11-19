"""Build data/centerlines.json from the City of Chicago Street Center Lines CSV
(data.cityofchicago.org/d/6imu-meau -> Export -> CSV).

Keeps all arterial/collector segments (CLASS 1-3) plus every segment of any street
named in KEEP_NAMES, so medians on smaller streets still match.
Usage: python3 tools/build_centerlines.py transportation.csv [extra street names...]
"""
import csv, json, sys, re
csv.field_size_limit(10**9)

KEEP_CLASSES = {'1', '2', '3'}
KEEP_NAMES = {'WACKER', 'OGDEN', 'LAKE SHORE', 'BISHOP', 'BROPHY', 'LORETTO', 'DEARBORN', 'STATE', 'CONGRESS',
              'RANDOLPH', 'MADISON', 'HARRISON', 'CENTRAL', 'FILLMORE', 'ARCHER', 'CORBETT', 'CERMAK', 'GRAND',
              'LA SALLE', 'CLARK', 'NORTH', 'PETERSON', 'LINCOLN', 'IRVING PARK', 'CUMBERLAND', 'HARLEM',
              'VINCENNES', 'EXCHANGE', 'ROOT', 'WENTWORTH', 'FOSTER', 'ARMITAGE', 'ELSTON', 'MICHIGAN', 'COLUMBUS'}

def n(s):
    s = (s or '').replace(',', '').strip()
    return int(float(s)) if s else 0

def simplify(pts, tol=1.5e-5):  # ~1.5 m, Douglas-Peucker
    if len(pts) < 3: return pts
    (x1, y1), (x2, y2) = pts[0], pts[-1]
    dx, dy = x2 - x1, y2 - y1
    L = (dx * dx + dy * dy) ** .5 or 1e-12
    dmax, idx = 0, 0
    for i in range(1, len(pts) - 1):
        d = abs(dy * pts[i][0] - dx * pts[i][1] + x2 * y1 - y2 * x1) / L
        if d > dmax: dmax, idx = d, i
    if dmax <= tol: return [pts[0], pts[-1]]
    return simplify(pts[:idx + 1], tol)[:-1] + simplify(pts[idx:], tol)

def main(path, extra):
    keep_names = KEEP_NAMES | {e.upper() for e in extra}
    names, name_id, segs = [], {}, []
    for r in csv.DictReader(open(path, newline='', encoding='utf-8-sig')):
        nm = r['STREET_NAM'].strip()
        if r['CLASS'] not in KEEP_CLASSES and nm not in keep_names: continue
        vals = [n(r[k]) for k in ('LOGICLF', 'LOGICLT', 'LOGICRF', 'LOGICRT') if n(r[k]) > 0]
        if not vals: continue
        lo, hi = min(vals), max(vals)
        # does the address increase from the first vertex to the last?
        f = [n(r[k]) for k in ('LOGICLF', 'LOGICRF') if n(r[k]) > 0]
        t = [n(r[k]) for k in ('LOGICLT', 'LOGICRT') if n(r[k]) > 0]
        inc = 1 if (min(f) if f else lo) <= (max(t) if t else hi) else 0
        nums = [float(v) for v in re.findall(r'-?\d+\.\d+|-?\d+', r['the_geom'])]
        pts = list(zip(nums[0::2], nums[1::2]))
        if len(pts) < 2: continue
        pts = simplify(pts)
        if nm not in name_id: name_id[nm] = len(names); names.append(nm)
        segs.append([name_id[nm], r['PRE_DIR'].strip(), r['STREET_TYP'].strip(), r['EWNS_DIR'].strip(), n(r['EWNS_COORD']),
                     lo, hi, inc, r['ONEWAY_DIR'].strip(), [round(c, 6) for p in pts for c in p]])
    out = {'source': 'City of Chicago Street Center Lines', 'names': names,
           'fields': ['name', 'preDir', 'type', 'ewnsDir', 'ewnsCoord', 'lo', 'hi', 'inc', 'oneway', 'coords(lng,lat,...)'],
           'segs': segs}
    json.dump(out, open('data/centerlines.json', 'w'), separators=(',', ':'))
    print(len(segs), 'segments,', len(names), 'street names')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2:])
