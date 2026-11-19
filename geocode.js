/* Place report trees on street centerlines (City of Chicago Street Center Lines).
 * Each report row gives the median's street as a grid number (e.g. 1600 W = Ashland) and an
 * address along it (e.g. 1608 N). We find the centerline block holding that address and
 * interpolate, so the point sits in the middle of the road rather than at a building.
 * Divided roads drawn as two one-way lines are averaged, which lands in the median.
 */
(function (root) {
  const OPP = { N: 'S', S: 'N', E: 'W', W: 'E' };
  const ALIASES = { LSD: 'LAKE SHORE', 'LAKE SHORE DRIVE': 'LAKE SHORE', MICH: 'MICHIGAN', ROOS: 'ROOSEVELT', CONG: 'CONGRESS',
    LASALLE: 'LA SALLE', 'IRVING PK': 'IRVING PARK', 'IRVING': 'IRVING PARK', MLK: 'DR MARTIN LUTHER KING JR', 'KING': 'DR MARTIN LUTHER KING JR', 'KING DR': 'DR MARTIN LUTHER KING JR',
    'US 41': 'SOUTH SHORE', US41: 'SOUTH SHORE', INDY: 'INDIANAPOLIS', STONY: 'STONY ISLAND' };
  const TYPES = /\b(AVENUE|AVE|STREET|ST|ROAD|RD|DRIVE|DR|BOULEVARD|BLVD|PARKWAY|PKWY|PLACE|PL|COURT|CT|HIGHWAY|HWY)\b\.?/g;

  function normName(s) {
    let n = String(s || '').toUpperCase().replace(/[.,']/g, ' ').replace(/\s+/g, ' ').trim();
    n = n.replace(/^(NORTH|SOUTH|EAST|WEST|UPPER|LOWER|N|S|E|W)\s+/, '');
    if (ALIASES[n]) return ALIASES[n];
    const lettered = n.match(/^AVE(?:NUE)?\.?\s+([A-O])$/);
    if (lettered) return 'AVENUE ' + lettered[1];
    n = n.replace(TYPES, '').replace(/\s+/g, ' ').trim();
    const av = n.match(/^AVE(?:NUE)?\s+([A-O])$/) || n.match(/^AVENUE\s+([A-O])$/);
    if (av) return 'AVENUE ' + av[1];
    return ALIASES[n] || n;
  }

  // meters between two lng/lat points (equirectangular, fine at city scale)
  function dist(a, b) {
    const k = Math.cos((a[1] + b[1]) / 2 * Math.PI / 180);
    return Math.hypot((a[0] - b[0]) * 111320 * k, (a[1] - b[1]) * 110574);
  }

  function build(data) {
    const segs = data.segs.map(s => {
      const c = s[9], pts = [];
      for (let i = 0; i < c.length; i += 2) pts.push([c[i], c[i + 1]]);
      const lens = [0];
      for (let i = 1; i < pts.length; i++) lens.push(lens[i - 1] + dist(pts[i - 1], pts[i]));
      return { name: data.names[s[0]], pre: s[1], type: s[2], ed: s[3], ec: s[4], lo: s[5], hi: s[6], inc: s[7], oneway: s[8], pts, lens };
    });
    const byGrid = new Map(), byName = new Map();
    const add = (m, k, v) => { if (!m.has(k)) m.set(k, []); m.get(k).push(v); };
    for (const s of segs) {
      if (s.ed && s.ec) add(byGrid, s.ed + s.ec, s);
      add(byName, s.name, s);
    }
    return { segs, byGrid, byName, size: segs.length };
  }

  function pointAt(s, addr) {
    let f = s.hi > s.lo ? (addr - s.lo) / (s.hi - s.lo) : 0.5;
    f = Math.min(1, Math.max(0, f));
    if (!s.inc) f = 1 - f;
    const total = s.lens[s.lens.length - 1], d = f * total;
    for (let i = 1; i < s.pts.length; i++) {
      if (s.lens[i] >= d) {
        const a = s.pts[i - 1], b = s.pts[i], seg = s.lens[i] - s.lens[i - 1] || 1, t = (d - s.lens[i - 1]) / seg;
        return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
      }
    }
    return s.pts[s.pts.length - 1];
  }

  // nearest point on a segment's line to p
  function nearestOn(s, p) {
    let best = null, bd = Infinity;
    const k = Math.cos(p[1] * Math.PI / 180);
    for (let i = 1; i < s.pts.length; i++) {
      const a = s.pts[i - 1], b = s.pts[i];
      const ax = (a[0] - p[0]) * k, ay = a[1] - p[1], bx = (b[0] - p[0]) * k, by = b[1] - p[1];
      const dx = bx - ax, dy = by - ay, L = dx * dx + dy * dy || 1e-18;
      const t = Math.min(1, Math.max(0, -(ax * dx + ay * dy) / L));
      const q = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
      const d = dist(q, p);
      if (d < bd) { bd = d; best = q; }
    }
    return { q: best, d: bd };
  }

  // Average the hits when they are the two sides of one divided road; otherwise prefer the named street
  function combine(hits, street) {
    if (!hits.length) return null;
    const want = normName(street);
    const ranked = [...hits].sort((a, b) => (b.s.name === want) - (a.s.name === want));
    const first = ranked[0].p;
    const near = ranked.filter(h => dist(h.p, first) < 90);
    const lng = near.reduce((a, h) => a + h.p[0], 0) / near.length, lat = near.reduce((a, h) => a + h.p[1], 0) / near.length;
    return [lng, lat];
  }

  function inRange(s, n, slack = 0) { return n >= s.lo - slack && n <= s.hi + slack; }

  /**
   * @param t tree record with gNum/gDir (median street) and aNum/aDir (address along it)
   * @param approx {lat,lng} grid estimate to fall back on / snap from
   * @returns {lat, lng, how} how = 'centerline' | 'snapped' | 'approx'
   */
  // Anything outside the city is a typo in the report, not a real spot
  const inChicago = p => p && p.lat > 41.62 && p.lat < 42.05 && p.lng > -87.96 && p.lng < -87.50;

  function locate(idx, t, approx) {
    if (approx && !inChicago(approx)) approx = null;
    const r = locateRaw(idx, t, approx);
    return r && inChicago(r) ? r : null;
  }

  function locateRaw(idx, t, approx) {
    if (!idx || !t || t.gNum == null || t.aNum == null) return approx ? { ...approx, how: 'approx' } : null;
    const dirs = t.dirGuess ? [t.aDir, OPP[t.aDir]] : [t.aDir];
    // 1) Street by grid number (spelling doesn't matter), address within the block
    for (const slack of [0, 30]) {
      for (const ad of dirs) {
        const cands = [];
        for (const c of slack ? [t.gNum - 25, t.gNum, t.gNum + 25] : [t.gNum]) for (const s of idx.byGrid.get(t.gDir + c) || []) cands.push(s);
        const hits = cands.filter(s => s.pre === ad && inRange(s, t.aNum, slack)).map(s => ({ s, p: pointAt(s, t.aNum) }));
        const p = combine(hits, t.street);
        if (p) return { lng: +p[0].toFixed(6), lat: +p[1].toFixed(6), how: 'centerline' };
      }
    }
    // 2) Street by name with the address range (for streets the file has no grid number for)
    const nm = normName(t.street);
    for (const ad of dirs) {
      const hits = (idx.byName.get(nm) || []).filter(s => s.pre === ad && inRange(s, t.aNum, 30)).map(s => ({ s, p: pointAt(s, t.aNum) }));
      const p = combine(hits, t.street);
      if (p && (!approx || dist(p, [approx.lng, approx.lat]) < 1500)) return { lng: +p[0].toFixed(6), lat: +p[1].toFixed(6), how: 'centerline' };
    }
    // 3) Diagonal / non-grid streets (Archer, Ogden, Wacker...): snap the grid estimate onto the named street
    if (approx) {
      const ap = [approx.lng, approx.lat];
      let pool = idx.byName.get(nm) || [];
      if (!pool.length) pool = idx.byGrid.get(t.gDir + t.gNum) || [];
      const near = pool.map(s => nearestOn(s, ap)).filter(r => r.d < 450).sort((a, b) => a.d - b.d);
      if (near.length) {
        const first = near[0].q, pair = near.filter(r => dist(r.q, first) < 90);
        const lng = pair.reduce((a, r) => a + r.q[0], 0) / pair.length, lat = pair.reduce((a, r) => a + r.q[1], 0) / pair.length;
        return { lng: +lng.toFixed(6), lat: +lat.toFixed(6), how: 'snapped' };
      }
      return { ...approx, how: 'approx' };
    }
    return null;
  }

  const api = { build, locate, normName };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ArbGeo = api;
})(typeof window !== 'undefined' ? window : globalThis);
