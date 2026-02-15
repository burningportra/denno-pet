import Cocoa
import SpriteKit

// MARK: - Transparent Pet Window

class PetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    init(forScreen screen: NSScreen) {
        let frame = screen.frame
        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        self.setFrame(frame, display: false)
        self.setFrameOrigin(frame.origin)
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.ignoresMouseEvents = true
        self.acceptsMouseMovedEvents = false
    }
}

// MARK: - Click-Through SKView

class PetSKView: SKView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

// MARK: - Creature State

enum CreatureState {
    case idle
    case wanderLeft
    case wanderRight
    case curious
    case startle
    case glitch
    case sleep
}

// MARK: - Pet Scene

class PetScene: SKScene {
    var creature: SKNode!
    var body: SKShapeNode!
    var bodyGhost1: SKShapeNode! // chromatic aberration red channel
    var bodyGhost2: SKShapeNode! // chromatic aberration blue channel
    var leftEye: SKShapeNode!
    var rightEye: SKShapeNode!
    var noDataLabel: SKLabelNode!
    var noDataLabel2: SKLabelNode! // second line for effect
    var scanLines: SKSpriteNode!
    var trailEmitter: SKEmitterNode?
    var state: CreatureState = .idle
    var stateTimer: TimeInterval = 0
    var nextStateChange: TimeInterval = 3.0
    var glitchTimer: TimeInterval = 0
    var edgeGlitchIntensity: CGFloat = 0
    var lastMousePosition: CGPoint = .zero
    var isMoving: Bool = false
    var lastCreatureX: CGFloat = 0
    
    let groundY: CGFloat = 60
    let edgePanicZone: CGFloat = 80
    
    override func didMove(to view: SKView) {
        backgroundColor = .clear
        setupCreature()
        scheduleNextState()
    }
    
    // MARK: - Body Path
    
    func createBodyPath() -> CGPath {
        let bodyPath = CGMutablePath()
        bodyPath.move(to: CGPoint(x: -22, y: -2))
        // Left side — irregular, ink-bleed feel
        bodyPath.addCurve(to: CGPoint(x: -18, y: 18),
                         control1: CGPoint(x: -28, y: 5),
                         control2: CGPoint(x: -24, y: 16))
        // Top left — asymmetric bump
        bodyPath.addCurve(to: CGPoint(x: -5, y: 34),
                         control1: CGPoint(x: -14, y: 22),
                         control2: CGPoint(x: -10, y: 36))
        // Top — uneven peak
        bodyPath.addCurve(to: CGPoint(x: 8, y: 32),
                         control1: CGPoint(x: 0, y: 37),
                         control2: CGPoint(x: 5, y: 35))
        // Top right — different curve than left
        bodyPath.addCurve(to: CGPoint(x: 20, y: 16),
                         control1: CGPoint(x: 14, y: 30),
                         control2: CGPoint(x: 22, y: 22))
        // Right side — slightly melting
        bodyPath.addCurve(to: CGPoint(x: 18, y: 0),
                         control1: CGPoint(x: 24, y: 10),
                         control2: CGPoint(x: 22, y: 3))
        // Bottom — uneven, like ink pooling
        bodyPath.addCurve(to: CGPoint(x: 5, y: -4),
                         control1: CGPoint(x: 14, y: -3),
                         control2: CGPoint(x: 10, y: -5))
        bodyPath.addCurve(to: CGPoint(x: -8, y: -3),
                         control1: CGPoint(x: 0, y: -6),
                         control2: CGPoint(x: -4, y: -4))
        bodyPath.addCurve(to: CGPoint(x: -22, y: -2),
                         control1: CGPoint(x: -14, y: -4),
                         control2: CGPoint(x: -18, y: -3))
        bodyPath.closeSubpath()
        return bodyPath
    }
    
    func setupCreature() {
        creature = SKNode()
        creature.name = "creature"
        creature.position = CGPoint(x: size.width / 2, y: groundY)
        lastCreatureX = creature.position.x
        
        let bodyPath = createBodyPath()
        
        // Chromatic aberration ghost layers (hidden by default)
        bodyGhost1 = SKShapeNode(path: bodyPath)
        bodyGhost1.fillColor = NSColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 0.3)
        bodyGhost1.strokeColor = .clear
        bodyGhost1.position = CGPoint(x: -3, y: 0)
        bodyGhost1.alpha = 0
        bodyGhost1.zPosition = -1
        creature.addChild(bodyGhost1)
        
        bodyGhost2 = SKShapeNode(path: bodyPath)
        bodyGhost2.fillColor = NSColor(red: 0.1, green: 0.1, blue: 0.9, alpha: 0.3)
        bodyGhost2.strokeColor = .clear
        bodyGhost2.position = CGPoint(x: 3, y: 0)
        bodyGhost2.alpha = 0
        bodyGhost2.zPosition = -1
        creature.addChild(bodyGhost2)
        
        // Main body — dark ink
        body = SKShapeNode(path: bodyPath)
        body.fillColor = NSColor(red: 0.08, green: 0.12, blue: 0.15, alpha: 0.82)
        body.strokeColor = NSColor(red: 0.2, green: 0.35, blue: 0.4, alpha: 0.35)
        body.lineWidth = 1.0
        body.glowWidth = 3
        creature.addChild(body)
        
        // Scan-line overlay
        scanLines = createScanLineSprite()
        scanLines.position = CGPoint(x: 0, y: 16)
        scanLines.zPosition = 10
        scanLines.alpha = 0.25
        creature.addChild(scanLines)
        
        // Eyes — teal glow, the only color
        leftEye = SKShapeNode(circleOfRadius: 3.5)
        leftEye.fillColor = NSColor(red: 0.4, green: 0.85, blue: 0.8, alpha: 0.95)
        leftEye.strokeColor = .clear
        leftEye.position = CGPoint(x: -7, y: 20)
        leftEye.glowWidth = 4
        leftEye.zPosition = 20
        creature.addChild(leftEye)
        
        rightEye = SKShapeNode(circleOfRadius: 3.5)
        rightEye.fillColor = NSColor(red: 0.4, green: 0.85, blue: 0.8, alpha: 0.95)
        rightEye.strokeColor = .clear
        rightEye.position = CGPoint(x: 7, y: 20)
        rightEye.glowWidth = 4
        rightEye.zPosition = 20
        creature.addChild(rightEye)
        
        // NO DATA labels (hidden by default)
        noDataLabel = SKLabelNode(text: "NO DATA")
        noDataLabel.fontName = "Menlo-Bold"
        noDataLabel.fontSize = 8
        noDataLabel.fontColor = NSColor(red: 0.9, green: 0.95, blue: 0.9, alpha: 0.9)
        noDataLabel.position = CGPoint(x: 0, y: 18)
        noDataLabel.alpha = 0
        noDataLabel.zPosition = 30
        creature.addChild(noDataLabel)
        
        noDataLabel2 = SKLabelNode(text: "NO DATA")
        noDataLabel2.fontName = "Menlo-Bold"
        noDataLabel2.fontSize = 6
        noDataLabel2.fontColor = NSColor(red: 0.9, green: 0.95, blue: 0.9, alpha: 0.7)
        noDataLabel2.position = CGPoint(x: 2, y: 8)
        noDataLabel2.alpha = 0
        noDataLabel2.zPosition = 30
        creature.addChild(noDataLabel2)
        
        // Subtle idle breathing animation
        let breathe = SKAction.sequence([
            SKAction.scaleY(to: 1.04, duration: 2.5),
            SKAction.scaleY(to: 0.97, duration: 2.5)
        ])
        body.run(SKAction.repeatForever(breathe))
        
        // Eye blink
        let blinkSequence = SKAction.sequence([
            SKAction.wait(forDuration: 3.0, withRange: 4.0),
            SKAction.scaleY(to: 0.1, duration: 0.08),
            SKAction.scaleY(to: 1.0, duration: 0.12),
        ])
        leftEye.run(SKAction.repeatForever(blinkSequence))
        rightEye.run(SKAction.repeatForever(blinkSequence))
        
        // Ambient digital dust (teal particles floating up)
        if let emitter = createDigitalDust() {
            emitter.position = CGPoint(x: 0, y: 15)
            emitter.zPosition = 5
            creature.addChild(emitter)
        }
        
        // Dennō substance trail emitter (black particles behind when moving)
        trailEmitter = createDennoTrail()
        if let trail = trailEmitter {
            trail.position = CGPoint(x: 0, y: 0)
            trail.zPosition = -2
            trail.particleBirthRate = 0 // off by default, turned on when moving
            creature.addChild(trail)
        }
        
        addChild(creature)
    }
    
    // MARK: - Scan Lines
    
    func createScanLineSprite() -> SKSpriteNode {
        let w = 50
        let h = 44
        let image = NSImage(size: NSSize(width: w, height: h))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: NSSize(width: w, height: h)).fill()
        
        // Draw horizontal scan lines
        for y in stride(from: 0, to: h, by: 3) {
            let lineColor = NSColor(white: 1.0, alpha: 0.4)
            lineColor.setFill()
            NSRect(x: 0, y: y, width: w, height: 1).fill()
        }
        image.unlockFocus()
        
        let texture = SKTexture(image: image)
        let sprite = SKSpriteNode(texture: texture)
        sprite.blendMode = .alpha
        return sprite
    }
    
    // MARK: - Digital Dust (teal ambient particles)
    
    func createDigitalDust() -> SKEmitterNode? {
        let emitter = SKEmitterNode()
        emitter.particleBirthRate = 2.5
        emitter.particleLifetime = 1.8
        emitter.particleLifetimeRange = 1.0
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi * 0.6
        emitter.particleSpeed = 4
        emitter.particleSpeedRange = 6
        emitter.particleAlpha = 0.35
        emitter.particleAlphaRange = 0.2
        emitter.particleAlphaSpeed = -0.2
        emitter.particleScale = 0.25
        emitter.particleScaleRange = 0.15
        emitter.particleColor = NSColor(red: 0.3, green: 0.7, blue: 0.65, alpha: 1.0)
        emitter.particleColorBlendFactor = 1.0
        
        let size = CGSize(width: 3, height: 3)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        emitter.particleTexture = SKTexture(image: image)
        
        return emitter
    }
    
    // MARK: - Dennō Substance Trail (black evaporating particles)
    
    func createDennoTrail() -> SKEmitterNode? {
        let emitter = SKEmitterNode()
        emitter.particleBirthRate = 12
        emitter.particleLifetime = 0.8
        emitter.particleLifetimeRange = 0.4
        emitter.emissionAngle = -.pi / 2 // downward
        emitter.emissionAngleRange = .pi * 0.4
        emitter.particleSpeed = 3
        emitter.particleSpeedRange = 5
        emitter.particleAlpha = 0.5
        emitter.particleAlphaRange = 0.2
        emitter.particleAlphaSpeed = -0.6
        emitter.particleScale = 0.4
        emitter.particleScaleRange = 0.3
        emitter.particleScaleSpeed = -0.2
        emitter.particleColor = NSColor(red: 0.05, green: 0.08, blue: 0.1, alpha: 1.0)
        emitter.particleColorBlendFactor = 1.0
        
        let size = CGSize(width: 4, height: 4)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        emitter.particleTexture = SKTexture(image: image)
        
        return emitter
    }
    
    func scheduleNextState() {
        nextStateChange = Double.random(in: 2.0...6.0)
        stateTimer = 0
    }
    
    // MARK: - Update Loop
    
    override func update(_ currentTime: TimeInterval) {
        stateTimer += 1.0 / 60.0
        glitchTimer += 1.0 / 60.0
        
        // State transitions
        if stateTimer >= nextStateChange {
            transitionToNextState()
        }
        
        // Calculate edge proximity for panic effect
        let leftDist = creature.position.x
        let rightDist = size.width - creature.position.x
        let edgeDist = min(leftDist, rightDist)
        
        if edgeDist < edgePanicZone {
            edgeGlitchIntensity = 1.0 - (edgeDist / edgePanicZone)
            
            // Intensify scan lines near edges
            scanLines.alpha = 0.25 + edgeGlitchIntensity * 0.5
            
            // More frequent glitches near edges
            if glitchTimer > Double(2.0 - edgeGlitchIntensity * 1.5) {
                triggerGlitch(withNoData: edgeGlitchIntensity > 0.5)
                glitchTimer = 0
            }
        } else {
            edgeGlitchIntensity = 0
            scanLines.alpha = 0.25
            
            // Normal random glitch events
            if glitchTimer > Double.random(in: 8.0...20.0) {
                triggerGlitch(withNoData: Bool.random() && Bool.random()) // ~25% chance
                glitchTimer = 0
            }
        }
        
        // Track if creature is moving for trail
        let dx = abs(creature.position.x - lastCreatureX)
        isMoving = dx > 0.3
        lastCreatureX = creature.position.x
        trailEmitter?.particleBirthRate = isMoving ? 12 : 0
        
        // Apply movement based on state
        switch state {
        case .wanderLeft:
            creature.position.x -= 0.5
            creature.xScale = -1
            if creature.position.x < 50 {
                state = .wanderRight
            }
        case .wanderRight:
            creature.position.x += 0.5
            creature.xScale = 1
            if creature.position.x > size.width - 50 {
                state = .wanderLeft
            }
        case .idle:
            creature.position.x += CGFloat.random(in: -0.15...0.15)
        default:
            break
        }
        
        // Floating bob
        let bob = CGFloat(sin(currentTime * 2.0)) * 1.5
        creature.position.y = groundY + bob
        
        // Scan line scroll effect (subtle)
        scanLines.position.y = 16 + CGFloat(sin(currentTime * 3.0)) * 0.5
    }
    
    func transitionToNextState() {
        let roll = Double.random(in: 0...1)
        switch roll {
        case 0..<0.3:
            state = .idle
        case 0.3..<0.55:
            state = .wanderLeft
        case 0.55..<0.8:
            state = .wanderRight
        default:
            state = .idle
        }
        scheduleNextState()
    }
    
    // MARK: - Glitch Effects
    
    func triggerGlitch(withNoData: Bool = false) {
        // Chromatic aberration — show RGB ghost layers offset
        let chromaIn = SKAction.run { [weak self] in
            guard let self = self else { return }
            let offsetX = CGFloat.random(in: 2...5)
            self.bodyGhost1.position = CGPoint(x: -offsetX, y: CGFloat.random(in: -1...1))
            self.bodyGhost2.position = CGPoint(x: offsetX, y: CGFloat.random(in: -1...1))
            self.bodyGhost1.alpha = 0.5
            self.bodyGhost2.alpha = 0.5
        }
        let chromaOut = SKAction.run { [weak self] in
            self?.bodyGhost1.alpha = 0
            self?.bodyGhost2.alpha = 0
        }
        
        // Body goes pitch black during glitch
        let bodyBlack = SKAction.run { [weak self] in
            self?.body.fillColor = NSColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 0.95)
            self?.body.glowWidth = 0
            self?.creature.position.x += CGFloat.random(in: -4...4)
        }
        let bodyFlicker = SKAction.run { [weak self] in
            self?.body.alpha = CGFloat.random(in: 0.2...0.5)
        }
        let bodyRestore = SKAction.run { [weak self] in
            self?.body.fillColor = NSColor(red: 0.08, green: 0.12, blue: 0.15, alpha: 0.82)
            self?.body.alpha = 1.0
            self?.body.glowWidth = 3
        }
        
        // Scan line intensify
        let scanFlare = SKAction.run { [weak self] in
            self?.scanLines.alpha = 0.7
        }
        let scanRestore = SKAction.run { [weak self] in
            self?.scanLines.alpha = 0.25 + (self?.edgeGlitchIntensity ?? 0) * 0.5
        }
        
        // NO DATA flash
        let noDataShow = SKAction.run { [weak self] in
            guard let self = self, withNoData else { return }
            self.noDataLabel.alpha = 0.9
            self.noDataLabel2.alpha = 0.7
            // Hide eyes during NO DATA
            self.leftEye.alpha = 0
            self.rightEye.alpha = 0
        }
        let noDataHide = SKAction.run { [weak self] in
            self?.noDataLabel.alpha = 0
            self?.noDataLabel2.alpha = 0
            self?.leftEye.alpha = 1.0
            self?.rightEye.alpha = 1.0
        }
        
        let glitchSequence = SKAction.sequence([
            chromaIn,
            bodyBlack,
            scanFlare,
            noDataShow,
            SKAction.wait(forDuration: 0.04),
            bodyFlicker,
            SKAction.wait(forDuration: 0.03),
            bodyRestore,
            SKAction.wait(forDuration: 0.02),
            bodyBlack,
            SKAction.wait(forDuration: 0.05),
            bodyFlicker,
            SKAction.wait(forDuration: 0.03),
            bodyRestore,
            chromaOut,
            scanRestore,
            noDataHide,
        ])
        creature.run(glitchSequence)
    }
    
    // MARK: - Mouse Tracking
    
    func handleGlobalMouse(at location: CGPoint) {
        let dx = location.x - creature.position.x
        let dy = location.y - creature.position.y
        let distance = sqrt(dx * dx + dy * dy)
        
        let mouseDelta = sqrt(
            pow(location.x - lastMousePosition.x, 2) +
            pow(location.y - lastMousePosition.y, 2)
        )
        lastMousePosition = location
        
        if distance < 200 && distance > 0 {
            let eyeOffset = min(dx / distance * 2, 2)
            leftEye.position.x = -7 + eyeOffset
            rightEye.position.x = 7 + eyeOffset
            
            if mouseDelta > 50 && distance < 100 {
                triggerStartle(awayFrom: location)
            }
        } else {
            leftEye.position.x = -7
            rightEye.position.x = 7
        }
    }
    
    func handleGlobalClick(at location: CGPoint) {
        let dx = location.x - creature.position.x
        let dy = location.y - creature.position.y
        let distance = sqrt(dx * dx + dy * dy)
        
        if distance < 40 {
            let happyPulse = SKAction.sequence([
                SKAction.scale(to: 1.15, duration: 0.1),
                SKAction.scale(to: 1.0, duration: 0.2),
            ])
            creature.run(happyPulse)
            leftEye.run(SKAction.sequence([
                SKAction.scaleY(to: 0.5, duration: 0.1),
                SKAction.scaleY(to: 1.0, duration: 0.3),
            ]))
            rightEye.run(SKAction.sequence([
                SKAction.scaleY(to: 0.5, duration: 0.1),
                SKAction.scaleY(to: 1.0, duration: 0.3),
            ]))
        }
    }
    
    func triggerStartle(awayFrom point: CGPoint) {
        let jumpDir: CGFloat = point.x > creature.position.x ? -1 : 1
        let jumpAction = SKAction.sequence([
            SKAction.moveBy(x: jumpDir * 30, y: 20, duration: 0.15),
            SKAction.moveBy(x: jumpDir * 10, y: -20, duration: 0.2),
        ])
        jumpAction.timingMode = .easeOut
        creature.run(jumpAction)
        triggerGlitch(withNoData: true)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: PetWindow!
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        
        window = PetWindow(forScreen: screen)
        
        let skView = PetSKView(frame: screen.frame)
        skView.allowsTransparency = true
        skView.preferredFramesPerSecond = 60
        
        let scene = PetScene(size: screen.frame.size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        skView.presentScene(scene)
        
        window.contentView = skView
        window.makeKeyAndOrderFront(nil)
        
        setupStatusItem()
        
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
            let screenPoint = NSEvent.mouseLocation
            let windowPoint = self.window.convertPoint(fromScreen: screenPoint)
            let scenePoint = skView.convert(windowPoint, to: scene)
            scene.handleGlobalMouse(at: scenePoint)
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            let screenPoint = NSEvent.mouseLocation
            let windowPoint = self.window.convertPoint(fromScreen: screenPoint)
            let scenePoint = skView.convert(windowPoint, to: scene)
            scene.handleGlobalClick(at: scenePoint)
        }
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "👾"
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Dennō Pet", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
