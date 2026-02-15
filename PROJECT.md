# Dennō Pet — Desktop Creature from the Coil Domain

## Vision
A desktop companion creature inspired by Dennō Coil's digital entities. It lives on your macOS desktop as a transparent overlay, wandering between windows, reacting to cursor movement, and exhibiting the glitchy, half-broken AR aesthetic of the show's cyber-space.

The creature is a **small, lost Illegal** — a dennō creature that escaped from obsolete space into your desktop. Not menacing, more like a stray digital animal. Lonely, curious, slightly broken.

## Repo
- **GitHub**: github.com/burningportra/denno-pet
- **Local**: `/Users/kevtrinh/.openclaw/workspace/denno-pet/`

## Source Material — Dennō Coil Visual Bible

### Creature Types (from the show)

**Illegals (イリーガル)**
- Mysterious black Den-noh creatures. Living shadows.
- True identity: a new kind of computer virus that infects petmatons, grown to huge size
- Can only exist in "old space" (obsolete AR infrastructure) or inside the body of another Den-noh creature
- Leave behind raw "dennō substance" — tangible but evaporating black trails
- Some are lost, isolated, trying to return to "the other side" — they feel lonely, not evil
- Isako hunts special forms to collect Meta-Bugs

**Nulls (ヌル)**
- Humanoid Illegals — pitch-black silhouettes with "NO DATA" on their surface
- Said to be the oldest Illegals
- Exist in countless numbers on "the other side"
- Can induce "dennō coil" — comatose separation of digital self from physical body

**Densuke (デンスケ)**
- Dog-shaped petmaton (legitimate cyber-pet)
- Looks like a normal dog through the glasses
- More "solid" than Illegals — legitimate software vs corrupted data
- Can interact with dennō substance (follows black trails with his nose)

**Searchmaton / Satchii (サッチー)**
- Pink/round antivirus bot with a smiley face drawn by Yasako's father
- Shoots blue beams to format/delete corrupted space
- Says "Me Searchy!" — cute but terrifying to kids
- Deploys spherical drones called Q-chan
- Cannot enter private property (shrines, schools, houses)

**Oyaji**
- Fumie's cyber-pet, resembles a naked gnome/old man
- "Slave" type pet used for investigations

### Visual Effects Language

**Obsolete/Old Space**
- Distorted holes in reality — edges where updated and outdated AR layers don't align
- Visually: warping, tearing, like a texture map misaligned
- "Strange environment" — the children find edge cases in the AR beta
- Old space is where Illegals can survive — it's outdated infrastructure that hasn't been formatted

**The "NO DATA" Phenomenon (dennō coil)**
- When den-noh body separates from real body
- Real body becomes a **pitch-black shadow** through the glasses
- Words **"NO DATA"** displayed on the surface — THE iconic visual of the show
- Unknown cause, triggered under certain conditions

**Dennō Substance**
- Black, tangible, evaporating material
- Raw digital matter made visible
- Left behind by viruses fleeing from Searchmaton
- Densuke can smell/follow it

**Metatags**
- Software tools visualized as physical objects (spray cans, chalk circles)
- Blue beam from forehead (Megane-Beam) — same beam type Satchii uses
- Chalk patterns drawn on ground for encoding/hacking
- Sold by Mega-baa at her candy shop

**AR Glasses Rendering**
- Everything digital is seen through Den-noh Megane (cyber glasses)
- Digital objects exist in the same visual register as physical world — not glowing or screaming "digital"
- The seams between real and digital are deliberately visible (seamful design)
- Holographic monitors and keyboards projected into air for PC use

### Color Palette (derived from show)
- **Illegals/Nulls**: Pure black, dark ink, wet shadow. NOT solid matte — more like dark watercolor bleeding at edges
- **Digital effects**: Blue beams, teal/cyan glows (Searchmaton beams, Megane-Beam)
- **Corruption/Glitch**: Black trails, warped edges, misaligned textures, red artifacts on severe glitch
- **NO DATA text**: White/light text on pitch-black shadow surface
- **Eyes (our creature)**: Teal/cyan glow — the only color on an otherwise dark form. This is what makes it alive vs just corrupted data
- **Background aesthetic**: Muted, everyday Japanese town. The mundanity IS the style.
- **Iso's concept art**: Subdued watercolors, not neon. The show's palette is warm and grounded even when showing digital phenomena.

### Thematic Core
- The "other world" shown through AR glasses is actually **the past** — outdated data that hasn't been updated
- People are drawn to "the other side" because they can't let go of the past (Isako seeking her dead brother, Haraken chasing Kanna's ghost)
- Technology makes memories and feelings tangible — AR as modern folklore/kaidan
- Director Iso: "There will always be a distance between people... one must walk down a long, thin and winding road before they reach one's heart"
- The show is set in **2026** — literally right now

## What This Means For Our Creature

Our pet is a **small, lost Illegal that escaped from old space into your desktop**.

### Visual Spec
1. **Body**: Dark, semi-transparent, ink-like. Not solid black — dark watercolor bleeding at edges. Amorphous but with a vaguely animal-like silhouette
2. **Surface texture**: Occasional "NO DATA" text fragments flickering across body. Raw dennō substance appearance.
3. **Edges**: Unstable, slightly dissolving/reforming — held together by weak code. Like ink in water.
4. **Trail**: Faint black evaporating particles behind it as it moves (dennō substance trail)
5. **Glitch events**: Full pitch-black with "NO DATA" text — the dennō coil moment. RGB channel split (chromatic aberration).
6. **Screen edges = boundary of old space**: Creature gets anxious, glitchy near them. This is where its safe habitat ends.
7. **Eyes**: Teal/cyan glow — the only color on dark form. What makes it feel alive vs corrupted data.
8. **Scan-lines**: Horizontal line artifacts across the creature — it's being rendered through imperfect AR glasses
9. **Movement**: Organic but slightly floaty — it's digital, not physical. Iso's full-limited philosophy: fewer frames but each one intentional, no redundant motion.

### Behavior Mapping to Show Lore
- **Wandering** = trying to find its way back to old space / "the other side"
- **Cursor reaction** = reacting to Searchmaton-like threat (cursor = enforcement)
- **Glitch near edges** = the boundary between old and new space is unstable
- **Settling down** = finding a comfortable spot in your desktop's "old space"
- **Happy when clicked** = rare positive interaction with a human (like kids befriending Illegals)

## Tech Stack
- **Language**: Swift
- **Framework**: SpriteKit for sprite animation + effects
- **Window**: Transparent NSWindow, always-on-top, fully click-through (global event monitors for interaction)
- **Target**: macOS (Kevin's Mac Studio, Apple Silicon)
- **Build**: `swiftc -o denno-pet -framework Cocoa -framework SpriteKit DennoPet/main.swift`

## Architecture (Current — Single File)
```
denno-pet/
├── PROJECT.md          # This file (visual bible + project spec)
├── DennoPet/
│   └── main.swift      # Everything (window, scene, creature, effects)
└── README.md
```

Future refactor into separate files when complexity warrants it.

## Phase Plan

### Phase 1: Walking Sprite ✅ DONE
- Transparent click-through window covering full screen
- Blob creature with teal glowing eyes
- Wanders left/right along bottom of screen
- Breathing animation, eye blinking
- Global mouse tracking — eyes follow cursor
- Startle reaction on fast cursor movement (jump + glitch)
- Click-on-creature happy pulse reaction
- Random glitch events (color flash, transparency flicker)
- Digital dust particle emitter
- Menu bar icon (👾) for quit
- **Key fix**: Window fully click-through via `ignoresMouseEvents = true`, interaction via global NSEvent monitors

### Phase 2: Cursor Awareness ✅ DONE (merged into Phase 1)
- Eyes track cursor position
- Startle on fast nearby movement
- Distance-based click detection

### Phase 3: Dennō Coil Visual Treatment ✦ NEXT
- SpriteKit fragment shader for scan-line effect across creature
- Chromatic aberration (RGB channel split) on glitch events
- "NO DATA" text label that flashes on creature during glitch/edge events
- Improved body shape — more ink-like, bleeding edges (custom shader or path animation)
- Dennō substance trail particles (black, evaporating) behind creature when moving
- Screen edge = old space boundary — creature glitches harder near edges

### Phase 4: Personality & Polish
- Full state machine with proper transitions and timing
- Sleep state after long inactivity (opacity fade, settling animation)
- Edge panic behavior (screen boundary anxiety)
- Window-walking (creature walks on top of other window title bars?)
- Multi-monitor support
- Sound effects (subtle digital chirps, glitch sounds)
- Settings panel (creature speed, glitch frequency, etc.)

### Phase 5: Advanced
- Multiple creature variants (different Illegal types)
- Interaction with other desktop elements
- LaunchAgent for auto-start on login
- App icon + proper .app bundle
- Possible: creature reacts to system events (low battery = more glitchy, night = sleepy)

## Kevin's Preferences
- Velocity-first: get something on screen fast, iterate
- macOS native: no Electron bloat
- The vibe matters as much as the tech
- Research before coding — get the visual details right from source material
- Fun fact: the show is set in 2026, which is literally right now
