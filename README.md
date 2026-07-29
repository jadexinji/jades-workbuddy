# Jade's Workbuddy

Static public-site package for Jade's Workbuddy.

## GitHub Pages deployment

Fast path:

```bash
gh auth login -h github.com
./deploy-github-pages.sh jades-workbuddy
```

Manual path:

1. Create a GitHub repository, for example `jades-workbuddy`.
2. Upload everything in this `public-site` folder to the repository root.
3. In GitHub, open `Settings` -> `Pages`.
4. Set `Source` to `Deploy from a branch`.
5. Choose the `main` branch and `/root`, then save.
6. GitHub will provide an HTTPS URL after it finishes publishing.

## Important

The app currently stores records in the browser's `localStorage`. A public URL lets the phone open it anywhere, including mobile data, but records are still saved in the browser on that device. Cross-device sync needs a backend or an online data source.

## Supabase setup

Open Supabase SQL Editor and run `supabase-schema.sql`.

The current cloud sync uses a private sync key that Jade enters in the app. The public anon key is safe to put in the browser, while the sync key should be kept private. OpenAI API keys and Supabase service-role keys must not be put in this static site.
