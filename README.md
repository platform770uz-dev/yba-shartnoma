# Yosh blogerlar akademiyasi — contract site

The permanent public QR points to the root of the GitHub Pages site. Each fresh visit to that root asks the server to create a separate parent contract draft at the fixed introductory price of 400,000 soʻm, then redirects the parent to a private `?c=<uuid>` link. That individual link expires after 24 hours. Reopening an individual link continues the same draft; scanning the permanent QR again creates a new draft. The public start endpoint limits each source IP to five new drafts per hour and stores only an HMAC hash of the IP for rate limiting.

For a valid `?c=<uuid>` link, the app uploads the signed PDF to a private Supabase Storage bucket and submits the contract once through an RPC. The `?narx=` route remains only as a clearly labeled local demo. The separate administrator page can still create individual links for special cases.

## Current service setup

- Repository: `platform770uz-dev/yba-shartnoma`
- Public page: `https://platform770uz-dev.github.io/yba-shartnoma/`
- Admin page: `https://platform770uz-dev.github.io/yba-shartnoma/admin.html`
- Supabase project: `zamonaviy-kasblar` (`uzivivmrixstxjvzkksz`)
- The browser config contains only the Supabase URL and publishable key. Never put a service-role key or other secret in this repository.
- New objects are isolated under `yba_contract_documents`, `yba_contract_admins`, and the private `shartnomalar` bucket. Existing CRM tables and functions are not used by this contract flow.

## Admin account setup (one account only)

1. In Supabase **Authentication → Users**, create the one admin account with email and password. The admin page has sign-in only and no sign-up control.
2. Copy that Auth user's UUID and, in SQL Editor, run: `insert into public.yba_contract_admins(user_id) values ('AUTH_USER_UUID');` The database index prevents a second allowlisted account.
3. Open `admin.html`, sign in, enter the monthly price in soʻm, and choose **Havola va QR yaratish** to create an individual link when needed. For normal walk-in use, print the permanent QR for the public root link above.
4. Signed contracts appear in the list. The PDF button generates an admin-only signed URL that expires after five minutes.

The Storage bucket is private, accepts only PDF files up to 10 MB, and has no anonymous read policy. Parent data is written only when the parent finishes signing on an admin-issued `?c=` link. If PDF upload fails, the parent still gets the local PDF and the page asks them to send it to the administrator. Direct table reads by `anon` and `authenticated` are revoked; RPCs expose only the intended fields.

The provided contract is an owner-supplied draft, not a legal review. Have an Uzbekistan-qualified lawyer review the refund, termination, dispute venue, personal-data, and child-media clauses before collecting real signatures. The contract includes an unreviewed no-refund clause. No data-retention purge policy has been configured; decide and implement one before production use.

## GitHub Pages

Repository: `platform770uz-dev/yba-shartnoma`.

To publish: open **Settings → Pages**, select **Deploy from a branch**, choose **main** and **/(root)**, then save. The permanent parent QR link is `https://platform770uz-dev.github.io/yba-shartnoma/`. After deployment, verify the root redirects to a new `?c=<uuid>` draft at 400,000 soʻm.

Edit `config.js` to set the provider details, timetable, session duration, venue, and start date. Keep `shartnoma.md` as the source contract; review legal changes before use. The public key in `config.js` is designed for browser use; no service-role key belongs in the site.

## Libraries

- `signature_pad` 5.1.3
- `jsPDF` 4.2.1
- `@supabase/supabase-js` 2.118.0
- `qrcode` 1.5.4

Noto Sans Regular and Bold are stored in `fonts/`; the SIL Open Font License is included as `fonts/OFL.txt`.

No analytics or third-party trackers are included. Parent and child details and the signature are not put in URLs. Form fields are temporarily kept in `sessionStorage`; signature strokes are never saved in browser storage.
