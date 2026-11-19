// Fill these in from your Supabase project: Settings -> API.
// The anon key is meant to be public; Row Level Security in schema.sql keeps the data behind login.
window.APP_CONFIG = {
  SUPABASE_URL: 'https://ktkbvehrfzforxndzvtv.supabase.co',
  SUPABASE_ANON_KEY: 'sb_publishable_0LkYdtvM1pq_f2YCt4A5lg_PhXdTqot',   // publishable key (safe to be public)

  // Regions and their landscape contractors
  REGIONS: [
    { id: 'north',     name: 'North',     contractor: 'Christy Webber' },
    { id: 'southwest', name: 'Southwest', contractor: 'Christy Webber' },
    { id: 'central',   name: 'Central',   contractor: 'A Safe Haven' },
    { id: 'southeast', name: 'Southeast', contractor: 'A Safe Haven' },
  ],
};
