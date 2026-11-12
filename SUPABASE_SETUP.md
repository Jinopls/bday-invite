# BDAY & GAMES — connect the free RSVP database

This is a static GitHub Pages site. The lobby is **not live** until you finish these steps.

## 1. Create your Supabase project

1. Visit https://supabase.com/dashboard and sign in or create a free account.
2. Create a new project. Choose the free tier and a European region (for example West Europe).
3. Set a strong **database password** and keep it private.

## 2. Create the private RSVP table and safe public functions

1. Open your Supabase project, then **SQL Editor**.
2. Open [supabase-setup.sql](./supabase-setup.sql) in this repository.
3. Copy the **entire file** into the SQL Editor and select **Run**.

The SQL creates a private `bday_rsvps` table, enables row-level security, revokes public table access, and grants guest access to only two functions:

- `bday_submit`: save or update an RSVP identified by a private random browser token.
- `bday_lobby`: return attendance totals, confirmed-guest equipment quantities, game votes, and only *opted-in* player names.

**Public visitors cannot read raw RSVP rows, private notes, or the hidden names.** Only the project owner has access to the full response table from the Supabase dashboard.

## 3. Connect the website

1. In your Supabase project, open **Connect** or **Project Settings → API Keys**.
2. Copy the **Project URL**, such as `https://example.supabase.co`.
3. Copy the **publishable key**, starting with `sb_publishable_`.
4. Open `index.html` in the GitHub repository and find:

```javascript
const RSVP_BACKEND = {
  url: '',
  publishableKey: ''
};
```

Paste in the project URL and publishable key. Commit the change.

**NEVER enter or publish the database password or an `sb_secret_` / `service_role` key.** The publishable key is specifically intended to be embedded in a public website.

You may also give the project URL and **publishable-only** key to ChatGPT to connect the site for you through GitHub.

## 4. Test

1. Visit your GitHub Pages site and check that the lobby says **SERVER ONLINE**.
2. Send a test RSVP with **Stay anonymous** checked. The stealthed-player count should increase, but no name appears.
3. Untick **Stay anonymous**, submit again in the **same browser**, and check that the name appears. The confirmed total should **not** double.
4. Try values for PCs, consoles, monitors, and TVs. Only confirmed guests contribute to those totals.
5. Go to Supabase **Table Editor → bday_rsvps** to see the complete private responses, including notes.

## LibreOffice export

In Supabase Table Editor, export the `bday_rsvps` table as CSV. Open that CSV in LibreOffice Calc. The CSV is a downloadable snapshot, not a continuously synchronized .ods file.


## Optional upgrade: structured console types and console breakdown

If you already ran the original setup script, **do not rerun it**.

1. Open the [console upgrade SQL](./supabase-console-upgrade.sql).
2. Copy the **entire file** into the Supabase **SQL Editor** and click **Run**.
3. Reload the birthday website and submit an RSVP with a console selected.
4. The public RSVP Live Stats shows a breakdown of **how many confirmed guests selected each model** (Switch 1, Switch 2, Xbox, PS4, PS5 or Other). The public view never shows the free-text "Other" details.

This migration preserves existing RSVPs. Before you run it, the site still saves console choices inside private notes using the original \`bday_submit\` function. After you run it, the site uses \`bday_submit_v2\` and stores them in separate private fields \`console_types\` and \`other_console\`. Existing test RSVPs saved before the upgrade will not appear in the new model breakdown until submitted again from the same browser.

The migration keeps the original database functions intact, so older cached site versions keep working. The website automatically falls back when the upgrade hasn't been run yet.

## Free-tier availability

Supabase Free projects can pause after about a week of low database activity. Before sending invitations and before the event, check your Supabase dashboard and resume the project if necessary. Supabase emails the project owner when a project is paused. A paused project cannot accept RSVPs until resumed. The website will show a connection error rather than pretending it saved a submission.

## Maintenance

- Guests returning on the **same browser** update their previous RSVP. Guests using another browser/device may create an additional entry.
- The public form is anonymous (no sign-in), so a publicly shared link may attract duplicate or spam responses. Moderate the records in Supabase if needed. A CAPTCHA or protected invite flow can be added later.
- The site refreshes lobby counts approximately every 30 seconds while open.
- Until the project URL and publishable key are configured, the form produces a message to copy/share rather than claiming to save it.
