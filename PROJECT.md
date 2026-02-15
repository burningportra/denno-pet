# Dennō Pet — Desktop Creature from the Coil Domain

## Vision
A desktop companion creature inspired by Dennō Coil's digital entities. It lives on your macOS desktop as a transparent overlay, wandering between windows, reacting to cursor movement, and exhibiting the glitchy, half-broken AR aesthetic of the show's cyber-space.

## Design References
- **Dennō Coil creatures**: Illegals (dark, amorphous, glitchy), Densuke (cyber-pet dog), Satchii (enforcement bot), Oyaji (old bearded helper)
- **Visual language**: Translucent, watercolor-ish edges, scan-line artifacts, occasional NO DATA flicker, slight chromatic aberration
- **Behavior model**: Wildlife, not Tamagotchi. Wanders autonomously. Reacts to environment. Has idle states that feel alive (Iso's "every frame is key" philosophy — no looping idle cycles, organic micro-movements)
- **Art direction source**: Iso Mitsuo's original watercolor concept sketches (subdued, not neon)

## Tech Stack
- **Language**: Swift
- **Framework**: SpriteKit for sprite animation + effects
- **Window**: Transparent NSWindow, always-on-top, click-through except on creature
- **Target**: macOS (Kevin's Mac Studio, Apple Silicon)
- **Build**: Xcode project, can run via `swift build` or Xcode

## Architecture
```
denno-pet/
├── PROJECT.md          # This file
├── DennoPet/
│   ├── App.swift       # Entry point, NSApplication setup
│   ├── PetWindow.swift # Transparent overlay window
│   ├── PetScene.swift  # SpriteKit scene (creature logic)
│   ├── Creature.swift  # Creature state machine + behaviors
│   ├── Effects.swift   # Glitch, scanline, chromatic aberration shaders
│   └── Assets/         # Sprite sheets, shaders
├── DennoPet.xcodeproj
└── README.md
```

## Creature Behaviors (State Machine)
1. **Idle** — subtle breathing/floating micro-movements, occasional head turn
2. **Wander** — walks/floats along bottom of screen or between windows
3. **Curious** — notices cursor approaching, turns to look
4. **Startle** — cursor moves too fast nearby, jumps/glitches
5. **Glitch** — random corruption events (sprite tears, NO DATA flash, color shift)
6. **Sleep** — after long inactivity, settles down with fading opacity
7. **Edge panic** — near screen boundaries, acts like it's at the edge of cyber-space

## Phase Plan
### Phase 1: Walking Sprite ✦ CURRENT
- Transparent window covering full screen
- Simple creature sprite (placeholder circle/blob with eyes)
- Walks back and forth along bottom of screen
- Basic SpriteKit physics for ground collision

### Phase 2: Cursor Awareness
- Track mouse position globally
- Creature turns toward/away from cursor
- Startle reaction on fast cursor movement
- Follow behavior if cursor is slow and close

### Phase 3: Dennō Coil Visual Treatment
- Custom SpriteKit shaders for:
  - Translucency with slight noise
  - Scan-line overlay
  - Chromatic aberration on glitch events
  - NO DATA text flash
- Particle effects for "digital dust"

### Phase 4: Personality & Polish
- Full state machine with transitions
- Window-awareness (walk on top of other windows?)
- Multi-monitor support
- Sound effects (subtle digital chirps)
- Menu bar icon for settings/quit

## Design Notes
- Creature should feel like it ESCAPED from Dennō Coil into your desktop
- Not cute-polished — slightly broken, slightly wrong, like buggy AR
- Color palette: muted greens, blues, occasional red glitch artifacts
- Movement should feel organic but slightly floaty (it's digital, not physical)
- Inspired by Iso's "full-limited" technique: fewer keyframes but each one intentional

## Kevin's Preferences
- Velocity-first: get something on screen fast, iterate
- macOS native: no Electron bloat
- The vibe matters as much as the tech
