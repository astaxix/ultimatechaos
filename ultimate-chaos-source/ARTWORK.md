# Eigene Spielgrafiken

Erstellt mit dem eingebauten Bildgenerator, anschließend ohne Motivänderungen als WebP optimiert. Native Originale sind 1774 × 887 (Atlas) und 1672 × 941 (Arena). Die Figuren werden über CSS-Koordinaten aus einem gemeinsamen Atlas dargestellt; es gibt keine externen Bilderquellen.

- `public/art/fighters-atlas.webp`: sieben Fantasy-Figuren und ein Coin-Motiv.
- `public/art/celestial-arena.webp`: kosmische Fantasy-Arena.
- `src/Artwork.tsx`: eigenes Logo-Emblem, Avatar-Ornamente und Coin-Darstellung.
- `src/styles.css`: figurenspezifische Kampf-/Zielreaktionen und Animationen.

## Bildprompts

### Figurenatlas

Use case: stylized-concept. Asset type: a SINGLE production game-art sprite atlas for the browser fantasy meme game Ultimate Chaos. Create a landscape canvas of EXACTLY 4 columns by 2 rows equal rectangular cells, no gutters, no text, no typography, no UI, no frame. Each cell is an independent centered full object on uniform deep navy-purple #141020 background, well-contained with 12 percent empty margin, no overlap across cells. Upper row left to right: 1 massive ornate silver magical scissors with violet magical cutting aura, 2 rugged floating obsidian boulder with violet rune cracks and gold mineral veins, 3 floating cream enchanted scroll with golden sealing wax and paper storm, 4 mystical round medieval stone wishing well with bright turquoise dimensional portal. Bottom row left to right: 5 Archangel Michael as heroic helmeted gold-armored adult angel with broad golden feather wings and a divine luminous sword, 6 ornate golden fantasy revolver with engraved wings and halo, 7 stylized fantasy atomic bomb with yellow radiation emblem green energy and warm explosion light, 8 a lavish golden coin stack with an engraved star emblem surrounded by violet crystal shards. Art direction: premium detailed 3D cinematic fantasy collectible game assets, realistic metals and stone, dramatic rim light, rich indigo shadows, violet and gold brand palette, exceptional sculptural depth and ornate craftsmanship. The seven selected game fighters must each be visually distinct and legible as small icons. No words, letters, numbers, watermarks, real weapon branding, contact-sheet borders. Not flat vector, not emoji. Precisely aligned 4x2 grid with each subject wholly inside its own cell.

### Arena

Use case: stylized-concept. Asset type: wide landscape environmental key art for a fantasy multiplayer browser game background. A breathtaking ruined celestial arena floating above clouds in a violet night sky, enormous ancient gold-trimmed gothic arches on left and right, cracked circular obsidian duel platform in the lower foreground, glowing golden runes and subtle violet lightning, distant cosmic nebula, sparse floating stone and glowing embers. Center area with generous atmospheric negative space for readable menu UI, most architectural detail toward the edges and upper third. Cinematic premium game concept art, detailed stone and engraved gold, photoreal stylized 3D lighting, deep purple and midnight navy with restrained golden highlights. No text, no logo, no characters, no weapons, no interface. Wide 16:9 landscape composition, atmospheric and sophisticated, no bright distracting center.

Die Assets sind detaillierte, generierte 2D-Illustrationen. Die Kämpfe animieren diese Illustrationen mit CSS/Framer Motion und eigenen Effekten; es ist keine voll geriggte 3D-Engine oder Motion-Capture-Produktion.
