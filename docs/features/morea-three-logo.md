# Morea homepage logo

The Morea campaign hero uses a titlecase 3D wordmark with a sans-serif M and serif orea. Vendored Three.js and subset typefaces load after the page finishes loading, when the logo is visible and the visitor permits motion and data use. The default ivory material suits dark campaign photography. The controller's optional `tone` value accepts `ink` for a black mark on white.

The logo occupies its own slot before the campaign copy. It ignores pointer events, so it cannot block shopping controls. Ordinary text remains visible until a successful WebGL frame. Reduced motion, data saving, unavailable WebGL and rendering failure retain static text. The canvas is decorative; the header retains the accessible store name.

Animation pauses outside the viewport and while the document is hidden. Turbo caching and controller disconnection release the scene, geometries, material, renderer and listeners. Preference changes can dispose and recreate the scene. A generation guard prevents a completed asynchronous import from creating a renderer after disconnection.

Run the component browser checks with:

```sh
npm ci
CHROMIUM_PATH=/usr/bin/chromium node script/morea_logo_test.mjs
```

The script uses the current logo partial, responsive stylesheet, controller and real vendored Three.js through a local fixture server. Its minimal Stimulus base supplies dynamic target getters and the tone value manually. It tests 320, 375, 768 and 1440 pixel layouts in LTR and RTL, actual WebGL pixels, shopping-button clicks, static fallbacks, visibility and preference changes, disposal and pending-import cancellation. Phone widths use Chromium touch emulation. Results and settled hero/studio screenshots are written to ignored `tmp/morea-logo/`.

These checks exercise components. They do not prove Rails route rendering, Stimulus registration, tenant routing, translated copy, cart or checkout behavior. For runtime preference transitions, the harness changes the emulated preference and explicitly dispatches the media-query change event because headless Chromium can omit that notification. Physical iOS/Android and real GPU performance remain separate checks.

## Integration and validation

The partial is enabled only for the first image-backed hero of the `morea` workspace. Other tenants and image-free heroes keep their ordinary branding. The former decorative uppercase watermark is omitted where the new logo appears. No merchant setup, routing or storefront publication behavior changes.

Three.js r180 is self-hosted, with module preloading disabled. The font module contains only the M, o, r, e and a glyphs needed for the mark. The reference supplied the titlecase direction; the meshes use a Helvetiker M and Optimer lowercase letters rather than an exact tracing of the reference image. License notices are retained in `vendor/javascript`. The module entry's relative core import is rewritten to the pinned `three/core` specifier for fingerprinted Rails assets.

Rendering is capped at 30 fps and device pixel ratio 1.5. The small transparent canvas uses two text geometries, a shared material and lights, with no textures or model downloads. Three.js loads after the page load event and an idle callback, only while the logo is in view. This work does not add a server-side rendering process or alter the Render deployment.

Validation completed in an isolated test environment:

- 11 Rails request examples passed, including FR/EN/AR logo markup, localized collection links, tenant isolation, disabled storefront gating and existing cart behavior.
- 16 browser component checks passed, including the ink fallback in reduced-motion RTL.
- 228 responsive component geometry checks passed. A full-bleed catalog collection row was added after live checks found its old negative margins exceeded catalog-section padding; the scoped margin correction preserves full bleed without document overflow.
- Three actual Rails/Stimulus homepage checks passed at 320px Arabic, 375px French and 1440px English. They verified a registered controller, WebGL draw calls, no document overflow, no logo/title overlap and no JavaScript errors. The French mobile menu opened and closed. These previews used synthetic data and a plain synthetic hero image.
- Rails autoloading, changed Ruby spec lint, JavaScript syntax and whitespace checks passed. Assets built successfully.

The full Rails suite and full CI were not run locally. Chromium used software WebGL; physical iOS/Android behavior and real GPU performance remain unverified. The new logo browser harness is included in the existing responsive CI job.
