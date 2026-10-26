# Admin themes

Each workspace has an `admin_theme`: **blue**, **dark**, **light** or **current**. New sign-ups choose one on the signup form (blue is preselected); it is stored on the registration and copied to the workspace when the email is confirmed. Staff can change it later under **Settings → Choose your theme**. Existing workspaces and platform-owner pages keep **current**, the original grey interface, which receives no theme styling.

The theme is applied as `data-admin-theme` on the admin `<body>`. `application.css` ends with an "Admin themes" layer: one set of variables per theme (`--t-*` for surfaces, text, sidebar and accent; `--chart-*` for the dashboard charts) and a shared SaaS structure (rounded corners, soft shadows, the blue accent from the Seallo home page). Chart colors are read from those variables, so the charts follow the theme; **current** falls back to the original palette.

Dark mode overrides the shared admin components and a few inline utility colors (`bg-white`, `text-[#303030]`, …). Views that use other hard-coded colors may need a follow-up override in the dark block.
