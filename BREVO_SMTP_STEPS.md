# Brevo SMTP for VIBEITY (sign-up and password emails)

1. Create a free account at https://www.brevo.com (the free plan allows about 300 emails a day).
2. Add your sender. Brevo menu -> Senders, domains and dedicated IPs -> Senders -> Add a sender (name "VIBEITY", an email you can open). Click the link Brevo sends to confirm it.
   Best for real users: also add your domain and add the DNS records Brevo shows (SPF/DKIM). Without this, emails may land in spam.
3. Get your SMTP details: click your account name (top right) -> SMTP & API -> SMTP tab.
   - Server: smtp-relay.brevo.com
   - Port: 587
   - Login: the SMTP login shown on that page (usually your Brevo email)
   - Password: click "Generate a new SMTP key", name it "supabase", copy the key straight away (you cannot see it again). This key is your SMTP password. It is NOT your Brevo account password.
4. Supabase dashboard -> project VIBEITY -> Authentication -> Emails -> SMTP Settings (some dashboards: Project Settings -> Authentication -> SMTP). Turn on "Enable custom SMTP" and fill in:
   - Sender email: the sender you verified in step 2
   - Sender name: VIBEITY
   - Host: smtp-relay.brevo.com
   - Port: 587
   - Username: your Brevo SMTP login
   - Password: the SMTP key
   Save.
5. Authentication -> Rate Limits: raise "emails per hour" (the default is low) to something like 100 once your own SMTP is on.
6. Authentication -> URL Configuration: Site URL = your live address; add it to Redirect URLs too.
7. Authentication -> Providers -> Email: turn "Confirm email" ON for launch.
8. Test: create a new account with a real email. The confirmation email should arrive from your sender within a minute. Check spam if not.
Keep the SMTP key secret. Never put it in index.html or on GitHub.
