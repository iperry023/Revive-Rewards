-- =====================================================================
--  Create your own admin login (run once, after setup.sql)
--  1. Change the username, name and temporary password below.
--  2. Run it. You'll be asked to pick a new password the first time you sign in.
-- =====================================================================

select public._create_user(
  'ian.perry',                 -- username you'll sign in with (lowercase, no spaces)
  'Ian Perry',                 -- your name as staff will see it
  'Administrator',             -- job title
  'Alpine Skilled Nursing',    -- facility
  'ChangeMe-2026',             -- temporary password (6+ characters)
  true                         -- true = admin
);
