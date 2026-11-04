# Dark Seallo

Workspace Settings selects `seallo` or `seallo_dark`. The admin layout exposes that selection on `body[data-admin-theme]`; public storefronts and platform-only pages keep their own styles.

Shared components use the existing `--s-*` palette. `admin_dark.css`, loaded after the component and responsive stylesheets, maps the newer seller pages' explicit light utility colors onto that palette. It also themes floating glass/media surfaces and native menus. Status colors retain their meanings and solid action buttons keep readable foregrounds. The browser theme-color follows the selected workspace theme.

Match full utility tokens with `[class~="..."]` when maintaining these mappings. Substring selectors can accidentally apply a hover-only or translucent color to an element's normal state. Prefer theme variables for new components.

Run `npm run build:test-css`, `npm run test:dark` and `npm run test:responsive`. Dark checks inspect computed colors, text contrast, native controls and hover states at phone/desktop sizes in LTR/RTL, and verify that the added stylesheet leaves light Seallo unchanged. Allow theme transitions to settle before sampling colors. Synthetic component checks supplement Rails theme/settings tests and actual page inspection.
