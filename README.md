# Yosh blogerlar akademiyasi — contract site (Phase 1)

A static, browser-only contract draft. It renders `shartnoma.md`, collects parent and child data in `sessionStorage` during the current tab session, and produces the signed PDF locally. It does not send form data, passport data, signature strokes, or PDF to a server.

## Before real use

This is Phase 1 only. The `?narx=` amount is editable by anyone who changes the URL and is suitable for demonstration only. Do not use it for real parent signing or payments. Phase 2 must replace it with administrator-issued contract tokens and server-side price checks before real use.

The provided contract is an owner-supplied draft, not legal advice or a legal review. Have an Uzbekistan-qualified lawyer review the refund, termination, dispute venue, personal-data, and child-media clauses before collecting real signatures. Fill the legal/business blanks in `config.js` and `shartnoma.md` only after confirming the details.

## GitHub Pages

Repository: `platform770uz-dev/yba-shartnoma`.

To publish: open **Settings → Pages**, select **Deploy from a branch**, choose **main** and **/(root)**, then save. The public demo link is `https://platform770uz-dev.github.io/yba-shartnoma/?narx=1500000` after Pages finishes deploying.

Edit `config.js` to set the provider details, timetable, session duration, venue, and start date. Keep `shartnoma.md` as the source contract; review legal changes before use. The demo amount in the link is not protected and is not a valid production price mechanism.

## Libraries

- `signature_pad` 5.1.3
- `jsPDF` 4.2.1
- `qrcode` is reserved for the future admin page in Phase 2

Noto Sans Regular and Bold are stored in `fonts/`; the SIL Open Font License is included as `fonts/OFL.txt`.

No analytics or third-party trackers are included. Contract data is not put in URLs. Signature strokes are never saved in browser storage.
