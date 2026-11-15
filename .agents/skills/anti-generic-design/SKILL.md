---
name: anti-generic-design
description: Apply one of 22 named visual styles so storefront and marketing UI avoids default AI-template looks. Use when designing, restyling, or theming pages, heroes, landing surfaces, or admin-facing brand moments in this Project.
---

# Anti-generic design styles

When the user names a style below (or asks for a less generic look), read this skill and apply that style as the dominant visual language. Prefer one style per surface. Do not stack several styles unless asked.

Respect existing design-system rules and brand constraints for the active product. For morea-commerce storefront work, still follow the Project frontend rules (expressive fonts, no default Inter/Roboto/system stacks when inventing look, avoid purple-on-white / cream-serif / broadsheet clichés, hero budget, etc.) unless the chosen style intentionally overrides a specific cue.

## How to use

1. Pick exactly one style from the catalog (user-named, or propose 2–3 fits if they ask for “less generic”).
2. Express it in CSS/HTML/assets: color, texture, grain, glass, grid, or image treatment — not only copy that mentions the style name.
3. Keep product photos and commerce UX readable; style the chrome, backgrounds, type, and overlays first.
4. Ship intentional motion only when it reinforces the style (2–3 max on visually led pages).

## Catalog (22)

| Style | Visual cues |
|-------|-------------|
| Thermal gradients | Heat-map palette (cool → hot), soft blending bands, infrared feel |
| Fluted glass | Vertical ribbed refraction, frosted blur, soft light streaks |
| Water caustics | Light ripples / pool-floor patterns, liquid highlights |
| Halftone | Print dots, comic/newsprint screening, spot-color overlays |
| Monochrome landscapes | Single-hue or B&W scenic photography, high contrast |
| Blueprint grids | Technical paper, cyan/white lines, rulers, schematic marks |
| Felt texture | Soft fiber surface, muted matte color, tactile cloth |
| Dithered images | Limited palette dither, retro bitmap / early digital |
| Grainy gradients | Soft color blends with heavy film grain / noise |
| Paper texture | Fiber paper, deckle edges, ink soak, letterpress calm |
| Topographic lines | Contour map strokes, elevation curves, sparse labels |
| Grass texture | Organic turf / meadow surface as field or fill |
| Noise texture | Procedural noise fields, static, soft chaos without grain cliché overload |
| Impressionist paintings | Loose brush dabs, broken color, painterly soft edges |
| Dot matrix | Printer / LED matrix dots, low-res character grids |
| Cloudy sky | Soft cloud fields, atmospheric depth, airy light |
| Pixel mosaic | Large square pixels, mosaic tiling, chunky color blocks |
| Blurred photos | Heavy bokeh / frosted photo backdrops, subject isolation |
| Stippled gradients | Pointillist density fades, ink stipple instead of smooth fills |
| Lens distortion | Barrel/pincushion warp, vignette, optical aberration |
| ASCII art | Characters as image, monospace mosaic, terminal aesthetic |
| Iridescent 3D | Pearlescent / oil-slick 3D surfaces, shifting specular color |

## Prompt shorthand

If the user says only a style name (e.g. “Halftone” or “Fluted glass”), treat that as: restyle the current target surface in that style, keep layout and content unless they ask for a redesign.

## Out of scope

- Do not invent a 23rd named style without asking.
- Do not apply these styles to dense data tables or critical checkout flows unless the user explicitly asks.
- Hosting / CDN / performance work is unrelated; use the speed-kit skills or docs for that.
