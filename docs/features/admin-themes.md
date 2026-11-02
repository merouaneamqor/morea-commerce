# Admin themes

Each workspace has an `admin_theme`: **seallo** (default) or **seallo_dark**. New sign-ups choose one on the signup form (seallo is preselected); it is stored on the registration and copied to the workspace when the email is confirmed. Staff can change it later under **Settings → Choose your theme**. Platform-owner pages without a workspace use seallo.

The theme is applied as `data-admin-theme` on the admin `<body>`. The "Seallo looks" layer at the end of `app/assets/tailwind/application.css` holds all admin styling for both themes: one shared set of rules (cream canvas, floating light sidebar, rounded cards, pill tabs, rust accent) driven by `--s-*` variables, with `seallo_dark` overriding only the variables plus a few inline-utility colors. Dashboard charts read the `--chart-*` variables, so they follow the theme.

## History

The earlier blue, dark, light and current themes were removed. Migration `20261102190100_reduce_admin_themes_to_seallo` maps existing workspaces and registrations: `dark` becomes `seallo_dark`; `blue`, `light` and `current` become `seallo`. Rolling it back restores `dark` for dark seallo and `current` (workspaces) or `blue` (registrations) for the rest, so an earlier explicit blue or light choice is not recovered.

## Adding a theme

Add its name to `Store::ADMIN_THEMES`, a check-constraint migration for `stores` and `registrations`, locale names and descriptions in `config/locales/admin_theme.yml`, a `.theme-swatch--<name>` preview and a `[data-admin-theme="<name>"]` variable block.
