# Figma implementation notes

Source: [agent.cy app - FIRST DRAFT](https://www.figma.com/design/aVihG6eh6asojCCEtXXogj/agent.cy-app---FIRST-DRAFT?node-id=1-63)

The shared file is an inspiration and foundation board rather than a set of editable product screens. Its four flattened references establish visual direction, not a locked palette. Product structure, interaction behavior, accessibility, and state handling remain governed by the PRD and native iOS conventions.

## Foundation tokens

| Token | Value | Use |
|---|---:|---|
| Obsidian | `#141414` | Primary text and dark surfaces |
| Bone | `#EDE4D1` | Warm light canvas |
| Terracotta | `#9B3A2E` | Cy, focus, and active guidance only |

The dark appearance uses Obsidian as its base while retaining Bone for high-emphasis content. Terracotta remains rare in both appearances.

Views consume semantic roles such as canvas, surface, primary text, secondary text, border, Cy accent, success, and destructive. No feature view hardcodes these foundation values. This keeps a future palette exploration small and safe while the initial build retains the board's warm editorial character.

Spacing follows a strict four-point scale: `4`, `8`, `12`, `16`, `24`, `32`, `48`, and `64` points.

Corner radii:

- 2 points for artboards, dividers, and structural blocks.
- 8 points for text fields, chips, pills, and tags.
- 16 points for cards, sheets, and modals.
- Full capsules for primary buttons, avatars, and Cy badges.

Elevation is quiet and warm. Default surfaces are flat with a hairline border. Resting and floating shadows are reserved for content that moves above the canvas.

## Typography and iconography

- Use Inter for editorial display and headline hierarchy, with tight tracking and clear scale changes.
- Use IBM Plex Mono for uppercase metadata, identifiers, dates, and small system labels.
- Keep body lines readable and avoid decorative styles.
- Use one-size, one-weight SF Symbols: 20-point glyphs with a rounded visual character inside at least a 32-point icon frame.
- Interactive controls retain a minimum 44 by 44-point hit target regardless of visible glyph size.

## Native adaptation

- Use SwiftUI navigation, safe-area, keyboard, Dynamic Type, VoiceOver, and Reduce Motion behavior.
- Treat the inspiration board's hard grid, hairlines, large type, and generous negative space as the composition language.
- Avoid generic dashboard card grids, excessive corner rounding, gradients, opacity-based text hierarchy, and decorative icon containers.
- Keep selected and proposed Cy changes visually distinct until the creator accepts them.
- A real-device interaction spike must validate the custom bottom navigation before final dimensions are locked.
