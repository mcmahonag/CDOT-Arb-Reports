/* Arborist report parser
 * Turns a monthly arborist workbook (one tab per site) into normalized tree records.
 * Input: { sheetName: [[cell, cell, ...], ...] } (array-of-arrays per sheet, as from
 * SheetJS sheet_to_json(ws, {header:1, raw:true}) with cellDates:true).
 * Works in the browser (window.ArbParser) and in Node (module.exports).
 */
(function (root) {
  const SKIP_SHEET = /^(summary|sortsheet|sheet\d*|chart\d*|data|lists?)$/i;
  const MONTHS = ['january','february','march','april','may','june','july','august','september','october','november','december'];

  const norm = s => String(s == null ? '' : s).toLowerCase().replace(/[^a-z0-9]/g, '');

  // header text (normalized) -> field name
  const HEADER_MAP = [
    [/^address$/, 'address'],
    [/^fromto$/, 'cross'],
    [/^planter$/, 'planter'],
    [/^no$/, 'treeNo'],
    [/^direction$/, 'side'],
    [/^genus$/, 'genus'],
    [/^species$/, 'species'],
    [/^variety.*cultivar|^cultivar/, 'cultivar'],
    [/^dbh$|^approxcal|^caliper/, 'dbh'],
    [/^speciescode$/, 'code'],
    [/^pruning$/, 'pruned'],
    [/^deadwood/, 'deadwood'],
    [/^trunkwounds/, 'wounds'],
    [/^pests?disease/, 'pests'],
    [/^pesttreatment/, 'treated'],
    [/^productused$/, 'product'],
    [/^treeremoved$/, 'removed'],
    [/^reason$/, 'reason'],
    [/^treeplanted$/, 'planted'],
    [/^lean$/, 'lean'],
    [/^isahazard/, 'hazard'],
    [/^comments?$/, 'comments'],
    [/^treeprunecategory$/, 'pruneCat'],
    [/^treeremovalcategory$/, 'removalCat'],
    [/^idcode$|^id$/, 'id'],
  ];

  function clean(v) {
    if (v == null) return '';
    if (v instanceof Date) return v;
    if (typeof v === 'number') return v === 0 ? '' : v;
    const s = String(v).replace(/\s+/g, ' ').trim();
    return s === '0' ? '' : s;
  }
  // "6-12 INCH", "1- 6 Inch", ">26 Inch" -> '6-12"', '>26"'
  function sizeClass(v) {
    const s = String(v || '').trim();
    if (!s || /#ref/i.test(s)) return '';
    const m = s.replace(/\s+/g, '').match(/^(>?)(\d+)(?:-(\d+))?/);
    return m ? (m[1] + m[2] + (m[3] ? '-' + m[3] : '') + '"') : s;
  }
  const str = v => (v instanceof Date ? fmtDate(v) : String(v == null ? '' : v));

  function fmtDate(d) {
    return d.getUTCFullYear() + ' ' + MONTHS[d.getUTCMonth()].replace(/^./, c => c.toUpperCase());
  }

  // "2021 October", "June 22 7D", "2015  Oct", Date, "2020-05-01" -> "YYYY-MM" (or "YYYY")
  function sortableDate(v) {
    if (v instanceof Date) return v.getUTCFullYear() + '-' + String(v.getUTCMonth() + 1).padStart(2, '0');
    const s = String(v || '').toLowerCase();
    if (!s) return '';
    let m = s.match(/(\d{4})-(\d{2})-\d{2}/);
    if (m) return m[1] + '-' + m[2];
    let month = 0;
    for (let i = 0; i < 12; i++) if (s.includes(MONTHS[i].slice(0, 3))) { month = i + 1; break; }
    let year = (s.match(/\b(19|20)\d{2}\b/) || [])[0];
    if (!year) { const y2 = s.match(/\b(\d{2})\b/); if (y2 && month) year = '20' + y2[1]; }
    if (!year) return '';
    return month ? year + '-' + String(month).padStart(2, '0') : year;
  }

  function num(v) {
    if (v instanceof Date || v === '' || v == null) return null;
    const n = parseFloat(String(v).replace(/[^0-9.\-]/g, ''));
    return isFinite(n) ? n : null;
  }

  // Chicago address grid -> approximate lat/lng. Origin State & Madison.
  // North and east/west: 800 address units per mile. South side runs faster near downtown:
  // Roosevelt (1200 S) = 1 mi, Cermak (2200 S) = 2 mi, 31st (3100 S) = 3 mi, Pershing (3900 S) = 4 mi,
  // then 800 per mile.
  const ORIGIN = { lat: 41.88194, lng: -87.62780 };
  const SOUTH = [[0, 0], [1200, 1], [2200, 2], [3100, 3], [3900, 4]];
  function southMiles(u) {
    for (let i = 1; i < SOUTH.length; i++) {
      const [u0, m0] = SOUTH[i - 1], [u1, m1] = SOUTH[i];
      if (u <= u1) return m0 + (u - u0) / (u1 - u0) * (m1 - m0);
    }
    return 4 + (u - 3900) / 800;
  }
  function gridToLatLng(x, y) {
    const miN = y >= 0 ? y / 800 : -southMiles(-y);
    const lat = ORIGIN.lat + miN * 0.0144927;
    const lngPerMile = 1 / (69.172 * Math.cos(lat * Math.PI / 180));
    // N-S streets tilt slightly east going south (~30 m per mile); west side miles run ~1.7% long
    const miE = (x / 800) * 1.017 - miN * (30 / 1609.344);
    return { lat: +lat.toFixed(6), lng: +(ORIGIN.lng + miE * lngPerMile).toFixed(6) };
  }
  function signed(n, dir) {
    const d = String(dir || '').trim().toUpperCase()[0];
    if (d === 'N' || d === 'E') return { axis: d === 'N' ? 'y' : 'x', v: n };
    if (d === 'S' || d === 'W') return { axis: d === 'S' ? 'y' : 'x', v: -n };
    return null;
  }

  function findHeader(rows) {
    for (let i = 0; i < Math.min(rows.length, 20); i++) {
      const r = (rows[i] || []).map(norm);
      if (r.includes('genus') && r.includes('address')) return i;
    }
    return -1;
  }

  function streetName(sheetName, titleLines, typeLabel) {
    // "MEDIAN: Ashland: Lake to Augusta" / sheet "Ashland-Roos to Lake" / title "N Ashland Ave"
    const t = (titleLines[0] || '').replace(/^[NSEW]\s+/, '');
    return t || sheetName;
  }

  function parseSheet(name, rows, warnings, region) {
    const h = findHeader(rows);
    if (h < 0) return null;
    const header = rows[h] || [];
    const cols = {};
    let dirSeen = 0;
    header.forEach((cell, j) => {
      const n = norm(cell);
      if (j === 0) { cols.grid = 0; return; }
      if (n === 'dir') {
        const k = ['gridDir', 'addrDir', 'side'][dirSeen++];
        if (k && cols[k] == null) cols[k] = j;
        return;
      }
      for (const [re, key] of HEADER_MAP) if (re.test(n) && cols[key] == null) { cols[key] = j; break; }
    });
    const lastHeader = header.reduce((a, c, j) => (c != null && String(c).trim() ? j : a), 0);
    // Address direction sometimes sits in an unlabeled column right after Address
    if (cols.addrDir == null && cols.address != null && !norm(header[cols.address + 1])) cols.addrDir = cols.address + 1;

    // Title block above the header
    const titleLines = [];
    let inspection = '';
    for (let i = 0; i < h; i++) {
      for (const c of rows[i] || []) {
        const s = str(clean(c));
        if (!s) continue;
        if (/^dire?s?ction of inspection/i.test(s)) inspection = s.replace(/^dire?s?ction of inspection\s*:?\s*/i, '').trim();
        else if (s.length > 1) titleLines.push(s);
      }
    }
    const label = str(header[0]).trim();
    const prefix = (label.match(/^([A-Za-z. ]+?)\s*:/) || [])[1] || '';
    const siteType = /median/i.test(prefix) ? 'Median' : /triang/i.test(prefix) ? 'Triangle'
      : /scape/i.test(prefix) ? 'Streetscape' : /plaza/i.test(prefix) ? 'Plaza' : /mall/i.test(prefix) ? 'Mall'
      : /triang/i.test(name) ? 'Triangle' : /corner/i.test(name) ? 'Corner' : 'Median';
    // "W Irving Park Road" -> addresses run West when the Dir. column is blank
    const titleDir = ((titleLines[0] || '').match(/^([NSEW])\s/) || [])[1] || '';
    // Street name for display: "N Ashland Ave" -> "Ashland Ave", "67th and Dan Ryan" -> "67th"
    const street = (titleLines[0] || name).split(/\s+-\s+|:|\//)[0].split(/\s+(?:and|&|@)\s+/i)[0]
      .replace(/^[NSEW]\.?\s+/, '').trim()
      .replace(/^.*(?:\bto\b|triang|\().*$/i, () => name.trim().split(/[-\s(]/)[0]);

    const trees = [];
    let carry = { grid: '', gridDir: '', addrDir: '', planter: '' };
    for (let i = h + 1; i < rows.length; i++) {
      const r = rows[i];
      if (!r || !r.length) continue;
      const g = k => (cols[k] == null ? '' : clean(r[cols[k]]));
      const genus = str(g('genus'));
      const code = str(g('code'));
      const treeNo = g('treeNo');
      const address = g('address');
      if (norm(genus) === 'genus') continue; // repeated header
      if (address === '' || treeNo === '') { if (!genus && !code) continue; }
      if (!genus && !code && num(g('dbh')) == null && !str(g('comments'))) continue;
      if (num(address) == null && num(treeNo) == null) continue; // stray notes / tallies

      for (const k of ['grid', 'gridDir', 'addrDir', 'planter']) {
        const v = g(k);
        if (v !== '') carry[k] = v;
      }
      let id = g('id');
      if (id === '' && cols.id == null) {
        // ID code sometimes sits in an unlabeled column past the last header
        for (let j = lastHeader + 1; j < r.length; j++) {
          if (typeof r[j] === 'number' && Number.isInteger(r[j]) && r[j] > 0) { id = r[j]; break; }
        }
      }

      const vacant = /^no ?tree$/i.test(genus.replace(/\s+/g, ' '));
      const removed = g('removed');
      const t = {
        site: name.trim(),
        id: id === '' ? '' : String(id),
        treeNo: str(treeNo),
        planter: str(carry.planter),
        side: str(g('side')),
        address: address === '' ? '' : String(address),
        addrDir: str(carry.addrDir),
        street,
        cross: str(g('cross')),
        genus: vacant ? '' : genus.trim(),
        species: str(g('species')).trim().replace(/^sp\.?$/i, 'sp.'),
        cultivar: str(g('cultivar')),
        code,
        dbh: num(g('dbh')),
        pruned: str(g('pruned')),
        prunedYM: sortableDate(g('pruned')),
        deadwood: (d => (d != null && d > 0 && d <= 1 ? Math.round(d * 100) : d))(num(g('deadwood'))),
        wounds: str(g('wounds')),
        pests: str(g('pests')),
        treated: str(g('treated')),
        product: str(g('product')),
        removed: str(removed),
        reason: str(g('reason')),
        planted: str(g('planted')),
        plantedYM: sortableDate(g('planted')),
        lean: str(g('lean')),
        hazard: num(g('hazard')),
        comments: str(g('comments')),
        pruneCat: sizeClass(str(g('pruneCat'))),
        removalCat: sizeClass(str(g('removalCat'))),
        status: vacant ? (removed ? 'removed' : 'vacant') : genus ? 'tree' : 'unknown',
        lat: null, lng: null, gx: null, gy: null,
      };
      // Approximate location from the Chicago grid
      const gnum = num(carry.grid), anum = num(address);
      const a = gnum != null ? signed(gnum, carry.gridDir) : null;
      let b = anum != null ? signed(anum, carry.addrDir || titleDir) : null;
      // Fallbacks when a tab leaves out the address direction (approximate)
      if (a && !b && anum != null) {
        if (a.axis === 'y') b = signed(anum, 'W');                         // E-W street: most addresses are West
        else if (region === 'north') b = signed(anum, 'N');
        else if (region === 'southwest' || region === 'southeast') b = signed(anum, 'S');
      }
      // Both directions on the same axis (e.g. Roosevelt "1200 W"): treat the street number as N/S
      let aa = a;
      if (a && b && a.axis === b.axis) aa = { axis: a.axis === 'x' ? 'y' : 'x', v: (region === 'north' ? 1 : -1) * Math.abs(a.v) };
      if (aa && b && aa.axis !== b.axis) {
        const a = aa;
        const x = a.axis === 'x' ? a.v : b.v, y = a.axis === 'y' ? a.v : b.v;
        Object.assign(t, gridToLatLng(x, y), { gx: x, gy: y });
      }
      trees.push(t);
    }
    return {
      site: name.trim(),
      title: titleLines.join(' · '),
      siteType,
      inspection,
      trees,
    };
  }

  /**
   * @param {Object<string, any[][]>} sheets
   * @param {{region:string, contractor?:string, month?:string, fileName?:string}} meta
   */
  function parseWorkbook(sheets, meta) {
    const warnings = [];
    const sites = [];
    for (const [name, rows] of Object.entries(sheets)) {
      if (SKIP_SHEET.test(name.trim())) continue;
      if (/old\s*$/i.test(name.trim())) { warnings.push(`Skipped tab "${name}" (marked OLD)`); continue; }
      const s = parseSheet(name, rows || [], warnings, meta.region);
      if (!s) { warnings.push(`Skipped tab "${name}" (no tree table found)`); continue; }
      if (!s.trees.length) { warnings.push(`Tab "${name}" has no tree rows`); continue; }
      sites.push(s);
    }
    // Unique key per tree within the region: ID code when present, else site + tree number
    const seen = new Map();
    for (const s of sites) for (const t of s.trees) {
      // Location-based identity so the same tree lines up across monthly reports
      let key = `${meta.region}|${s.site}|${t.planter}|${t.treeNo}|${t.address}`.toLowerCase();
      if (seen.has(key)) { const n = seen.get(key) + 1; seen.set(key, n); key += `#${n}`; }
      else seen.set(key, 1);
      t.key = key;
      t.region = meta.region;
      t.siteType = s.siteType;
    }
    const noLoc = sites.reduce((a, s) => a + s.trees.filter(t => t.lat == null).length, 0);
    if (noLoc) warnings.push(`${noLoc} rows could not be placed on the map (address grid incomplete)`);
    return { ...meta, month: meta.month || guessMonth(meta.fileName), sites, warnings };
  }

  function guessMonth(fileName) {
    const s = String(fileName || '').toLowerCase().replace(/_/g, ' ');
    const y = (s.match(/\b(20\d{2})\b/) || [])[1];
    let m = 0;
    for (let i = 0; i < 12; i++) if (s.includes(MONTHS[i])) { m = i + 1; break; }
    return y && m ? `${y}-${String(m).padStart(2, '0')}` : '';
  }

  function guessRegion(fileName) {
    const s = String(fileName || '').toLowerCase();
    if (/\bsw\b|south ?west/.test(s.replace(/[_\-]/g, ' '))) return 'southwest';
    if (/\bse\b|south ?east/.test(s.replace(/[_\-]/g, ' '))) return 'southeast';
    if (/central/.test(s)) return 'central';
    if (/north/.test(s)) return 'north';
    return '';
  }

  const api = { parseWorkbook, guessMonth, guessRegion, sortableDate, gridToLatLng };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ArbParser = api;
})(typeof window !== 'undefined' ? window : globalThis);
