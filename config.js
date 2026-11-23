// Fill these in from your Supabase project: Settings -> API.
// The anon key is meant to be public; Row Level Security in schema.sql keeps the data behind login.
window.APP_CONFIG = {
  SUPABASE_URL: 'https://ktkbvehrfzforxndzvtv.supabase.co',
  SUPABASE_ANON_KEY: 'sb_publishable_0LkYdtvM1pq_f2YCt4A5lg_PhXdTqot',   // publishable key (safe to be public)

  // Shown at the bottom of the Help page, e.g. 'Mike — CDOT Horticulture, 312-555-0100, mike@example.gov'
  HELP_CONTACT: '',

  // Regions and their landscape contractors
  REGIONS: [
    { id: 'north',     name: 'North',     contractor: 'Christy Webber' },
    { id: 'southwest', name: 'Southwest', contractor: 'Christy Webber' },
    { id: 'central',   name: 'Central',   contractor: 'A Safe Haven' },
    { id: 'southeast', name: 'Southeast', contractor: 'A Safe Haven' },
    // Lake Shore Drive — add when the contract is set up (run supabase/009 first), e.g.:
    // { id: 'lsd_north', name: 'LSD North', contractor: '' },
    // { id: 'lsd_south', name: 'LSD South', contractor: '' },
  ],
};
