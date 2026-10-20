# VIBEITY: deploy + backend status

## Files that go on GitHub / Vercel (upload ALL of these, keep the same folder layout)
```
index.html
manifest.webmanifest
icons/
  apple-touch-icon.png
  favicon-32.png
  icon-192.png
  icon-512.png
  icon-maskable-512.png
  icon-1024.png
.gitignore
supabase/schema.sql      (optional, for your records)
BACKEND_SETUP.md         (optional)
```
Do NOT upload `.env` (it is in `.gitignore`). `index.html` already contains the public Supabase URL and anon key, so the site works without it.

## Deploy steps
1. Unzip `vibeity-site.zip`.
2. GitHub: open your repository -> **Add file -> Upload files** -> drag in everything inside the unzipped folder (including the `icons` and `supabase` folders) -> **Commit changes**.
3. Vercel: **Add New -> Project -> Import** your GitHub repository -> Framework: **Other** -> leave Build Command empty and Output Directory as `./` -> **Deploy**.
4. Copy your live address (for example `https://vibeity.vercel.app`).
5. Supabase dashboard -> project VIBEITY -> **Authentication -> URL Configuration**:
   - **Site URL** = your live address.
   - **Redirect URLs** = add the same address (and your custom domain later).
6. Supabase dashboard -> **Authentication -> Providers -> Email**: for testing you can turn **Confirm email** OFF so sign-up logs in immediately. Turn it back ON before launch.

## What works on the real database now (Phase 2)
- Create account, log in, log out, forgot password
- All 11 sign-up steps saved (relationship/friendship, gender, profession, location, username, bio, photo)
- Profile photo uploaded to Supabase Storage
- Username must be unique (checked live)
- Public / private switch, "I'm here for" and notification choices saved
- "Online" status updates every minute
- Refreshing the page keeps you logged in

## Still in your browser only (next phases)
Posts, reels, likes, comments, saves, shares (Phase 3), swipes/matches/friends (Phase 4), chats (Phase 5), groups (Phase 6). Demo mode shows how all of these will look and never touches the database.

## Test checklist
1. Open the live site, create an account.
2. Finish the 11 steps (add a photo and username).
3. Supabase -> Table Editor -> `profiles`: your row shows name, username, photo_url, onboarded = true.
4. Supabase -> Storage -> `avatars`: a folder with your user id and `avatar.jpg`.
5. Refresh the site: you stay logged in. Log out and log in again: you go straight to the app.

## Added in the chat/groups update
- Database already updated live (see `supabase/migration-06-chat-media-groups.sql`): image comments, chat media + view once, mute/clear/block, group photo, admins, who-can-add-members, group personal settings.
- Chat photos, videos, files and voice notes are stored in the browser (IndexedDB) for now. They move to Supabase Storage in the chat phase.
- Voice calls are a demo screen for now (ringing tone, mute, timer). Real calling needs WebRTC and is planned with the chat phase.
- Legal text lives in `legal/` (Terms, Data Policy, Community Guidelines) and is also built into the app (Settings -> Info and Terms).
- Support email is set in two places in `index.html`: the `SUPPORT_EMAIL` constant (Help sheet) and the legal text. Change it there if you want a different address.
