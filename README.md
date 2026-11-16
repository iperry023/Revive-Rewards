# Revive Rewards

Employee recognition for Revive Health Senior Care Management facilities. Staff give each other shout-outs with photos, likes and comments. Admins add points to shout-outs, and staff trade their points for gift cards.

- **Website:** hosted free on GitHub Pages (this repository)
- **Database, logins and photos:** Supabase (free tier)
- **No email needed:** admins create accounts with a username and temporary password; staff choose their own password the first time they sign in.

## One-time setup

### 1. Set up the database (Supabase)
1. In your Supabase project, open **SQL Editor → New query**.
2. Paste in everything from [`supabase/setup.sql`](supabase/setup.sql) and click **Run**. You should see "Success. No rows returned."
3. Open another new query, paste [`supabase/first-admin.sql`](supabase/first-admin.sql), **change the username, name and temporary password** to yours, and click **Run**.
4. Go to **Authentication → Sign In / Providers** and turn **off** "Allow new users to sign up". (Staff accounts are created by admins inside the site, so this stops strangers from making accounts.)

### 2. Connect the website to the database
1. In Supabase, open **Project Settings → API Keys** (or click **Connect** at the top of the dashboard).
2. Copy the **Project URL** and the **publishable** key (starts with `sb_publishable_`; older projects call it the `anon` `public` key).
3. In this GitHub repository, open `config.js`, click the ✏️ pencil, paste the two values between the quotes, and click **Commit changes**.
   - The publishable key is meant to be public. **Never** paste the `secret` / `service_role` key here.

### 3. Turn on the website (GitHub Pages)
1. In this repository, go to **Settings → Pages**.
2. Under "Build and deployment", set **Source: Deploy from a branch**, **Branch: main**, folder **/ (root)**, and click **Save**.
3. After a minute or two the site is live at `https://<your-github-username>.github.io/revive-rewards/`.

Sign in with the username and temporary password from step 1.3, choose your own password, and you're in.

## Running the program

**Admin → Employees:** add each staff member, with their birthday (month and day only, no year) and hire date if you'd like them to show up in the feed's **Celebrations** card. Birthdays and work anniversaries in the next two weeks appear there, with a **Celebrate** button that starts a shout-out. The site creates a username (like `maria.lopez`) and a temporary password, which you can copy or print to hand out. When someone leaves, edit them and uncheck **Active**. They can't sign in anymore, but their past posts stay.

**Admin → Gift card requests:** when someone redeems, buy the gift card, get them the code, then click **Mark sent**. **Decline** returns their points.

**Giving points (admins only):** every post in the feed has a **★ Add points** button for admins. Choose who on the post gets points and how many. Admins can also include points when they write their own shout-out. To catch up on posts, check **Only posts without points** above the feed. Points show on the post as a gold tag (for example, "+25 pts from Ian"); click the × on the tag to take them back. Admins can't give points to themselves.

**Admin → Settings:** point value (default 100 pts = $10), the values staff can tag, and the list of facilities.

**Admin → Points report:** everyone's balance and the total dollar value of unspent points. Download it as a CSV for Excel.

### Forgotten passwords
Admin → Employees → Edit → **Reset password**. The person gets a new temporary password and picks their own when they sign in.

## How the points are protected
All point rules are enforced by the database, not the web page, so they can't be bypassed:
- Only admins can give points, and never to themselves.
- Once a post has points, only an admin can delete it (so nobody can take back a coworker's points).
- Nobody can redeem more points than they have.
- Only admins can add employees, change rewards or settings, or approve gift card requests.
- Deactivated employees and anyone who isn't signed in can't see anything.
- Photos are private and only visible to signed-in staff.

**Please remind staff:** no resident names, faces or health details in posts or photos.

## Files
| File | What it is |
|---|---|
| `index.html` | The whole website |
| `config.js` | Your Supabase connection settings |
| `assets/` | Revive logo and icons |
| `supabase/setup.sql` | Creates the database tables and security rules (run once) |
| `supabase/first-admin.sql` | Creates the first admin login (run once) |
| `supabase/update-celebrations.sql` | Adds birthdays and anniversaries, only if you ran an older setup.sql |

## Free tier notes
Supabase's free tier includes 500 MB of database and 1 GB of photo storage, which is plenty for several facilities (photos are shrunk before upload). A free project **pauses after 7 days with no activity**. Daily use keeps it awake, and if it does pause, click **Restore** in the Supabase dashboard. The Pro plan ($25/month) removes the pause.
