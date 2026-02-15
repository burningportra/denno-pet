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
        self.ignoresMouseEvents = true // Fully click-through
        self.acceptsMouseMovedEvents = false
    }
}

// MARK: - Click-Through SKView

class PetSKView: SKView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // Always click through
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
    var leftEye: SKShapeNode!
    var rightEye: SKShapeNode!
    var state: CreatureState = .idle
    var stateTimer: TimeInterval = 0
    var nextStateChange: TimeInterval = 3.0
    var glitchTimer: TimeInterval = 0
    var lastMousePosition: CGPoint = .zero
    var mouseVelocity: CGFloat = 0
    
    // Ground level
    let groundY: CGFloat = 60
    
    override func didMove(to view: SKView) {
        backgroundColor = .clear
        setupCreature()
        scheduleNextState()
    }
    
    func setupCreature() {
        creature = SKNode()
        creature.name = "creature"
        creature.position = CGPoint(x: size.width / 2, y: groundY)
        
        // Body — amorphous blob shape (like an Illegal)
        let bodyPath = CGMutablePath()
        bodyPath.move(to: CGPoint(x: -20, y: 0))
        bodyPath.addCurve(to: CGPoint(x: 0, y: 35),
                         control1: CGPoint(x: -25, y: 15),
                         control2: CGPoint(x: -15, y: 35))
        bodyPath.addCurve(to: CGPoint(x: 20, y: 0),
                         control1: CGPoint(x: 15, y: 35),
                         control2: CGPoint(x: 25, y: 15))
        bodyPath.addCurve(to: CGPoint(x: -20, y: 0),
                         control1: CGPoint(x: 15, y: -5),
                         control2: CGPoint(x: -15, y: -5))
        bodyPath.closeSubpath()
        
        body = SKShapeNode(path: bodyPath)
        body.fillColor = NSColor(red: 0.15, green: 0.25, blue: 0.3, alpha: 0.75)
        body.strokeColor = NSColor(red: 0.3, green: 0.5, blue: 0.55, alpha: 0.5)
        body.lineWidth = 1.5
        body.glowWidth = 2
        creature.addChild(body)
        
        // Eyes — slightly glowing
        leftEye = SKShapeNode(circleOfRadius: 3.5)
        leftEye.fillColor = NSColor(red: 0.6, green: 0.9, blue: 0.85, alpha: 0.9)
        leftEye.strokeColor = .clear
        leftEye.position = CGPoint(x: -7, y: 20)
        leftEye.glowWidth = 3
        creature.addChild(leftEye)
        
        rightEye = SKShapeNode(circleOfRadius: 3.5)
        rightEye.fillColor = NSColor(red: 0.6, green: 0.9, blue: 0.85, alpha: 0.9)
        rightEye.strokeColor = .clear
        rightEye.position = CGPoint(x: 7, y: 20)
        rightEye.glowWidth = 3
        creature.addChild(rightEye)
        
        // Subtle idle breathing animation
        let breathe = SKAction.sequence([
            SKAction.scaleY(to: 1.05, duration: 2.0),
            SKAction.scaleY(to: 0.97, duration: 2.0)
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
        
        // Digital dust particles
        if let emitter = createDigitalDust() {
            emitter.position = CGPoint(x: 0, y: 15)
            creature.addChild(emitter)
        }
        
        addChild(creature)
    }
    
    func createDigitalDust() -> SKEmitterNode? {
        let emitter = SKEmitterNode()
        emitter.particleBirthRate = 3
        emitter.particleLifetime = 1.5
        emitter.particleLifetimeRange = 1.0
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi
        emitter.particleSpeed = 5
        emitter.particleSpeedRange = 8
        emitter.particleAlpha = 0.4
        emitter.particleAlphaRange = 0.3
        emitter.particleAlphaSpeed = -0.3
        emitter.particleScale = 0.3
        emitter.particleScaleRange = 0.2
        emitter.particleColor = NSColor(red: 0.4, green: 0.7, blue: 0.65, alpha: 1.0)
        emitter.particleColorBlendFactor = 1.0
        
        // Use a tiny rectangle as particle
        // Create a simple square texture
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
    
    override func update(_ currentTime: TimeInterval) {
        stateTimer += 1.0 / 60.0
        glitchTimer += 1.0 / 60.0
        
        // State transitions
        if stateTimer >= nextStateChange {
            transitionToNextState()
        }
        
        // Random glitch events
        if glitchTimer > Double.random(in: 8.0...20.0) {
            triggerGlitch()
            glitchTimer = 0
        }
        
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
            // Subtle micro-movement
            creature.position.x += CGFloat.random(in: -0.15...0.15)
            creature.position.y = groundY + CGFloat(sin(stateTimer * 1.5)) * 2
        case .startle:
            // Quick hop
            break
        default:
            break
        }
        
        // Floating bob
        let bob = CGFloat(sin(currentTime * 2.0)) * 1.5
        creature.position.y = groundY + bob
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
    
    func triggerGlitch() {
        // Visual glitch — offset, color shift, flicker
        let glitchSequence = SKAction.sequence([
            SKAction.run { [weak self] in
                self?.body.fillColor = NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 0.6)
                self?.creature.position.x += CGFloat.random(in: -5...5)
            },
            SKAction.wait(forDuration: 0.05),
            SKAction.run { [weak self] in
                self?.body.fillColor = NSColor(red: 0.15, green: 0.25, blue: 0.3, alpha: 0.75)
            },
            SKAction.wait(forDuration: 0.03),
            SKAction.run { [weak self] in
                self?.body.alpha = 0.3
            },
            SKAction.wait(forDuration: 0.06),
            SKAction.run { [weak self] in
                self?.body.alpha = 1.0
                self?.body.fillColor = NSColor(red: 0.15, green: 0.25, blue: 0.3, alpha: 0.75)
            },
        ])
        creature.run(glitchSequence)
    }
    
    // MARK: - Mouse Tracking (Global monitors, window is click-through)
    
    func handleGlobalMouse(at location: CGPoint) {
        let dx = location.x - creature.position.x
        let dy = location.y - creature.position.y
        let distance = sqrt(dx * dx + dy * dy)
        
        // Track velocity for startle
        let mouseDelta = sqrt(
            pow(location.x - lastMousePosition.x, 2) +
            pow(location.y - lastMousePosition.y, 2)
        )
        lastMousePosition = location
        
        // Curious — look toward cursor when nearby
        if distance < 200 && distance > 0 {
            let eyeOffset = min(dx / distance * 2, 2)
            leftEye.position.x = -7 + eyeOffset
            rightEye.position.x = 7 + eyeOffset
            
            // Startle if cursor moves fast nearby
            if mouseDelta > 50 && distance < 100 {
                triggerStartle(awayFrom: location)
            }
        } else {
            // Reset eyes
            leftEye.position.x = -7
            rightEye.position.x = 7
        }
    }
    
    func handleGlobalClick(at location: CGPoint) {
        let dx = location.x - creature.position.x
        let dy = location.y - creature.position.y
        let distance = sqrt(dx * dx + dy * dy)
        
        if distance < 40 {
            // Pet the creature — happy reaction
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
        triggerGlitch()
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: PetWindow!
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        
        // Create transparent window
        window = PetWindow(forScreen: screen)
        
        // Create SpriteKit view
        let skView = PetSKView(frame: screen.frame)
        skView.allowsTransparency = true
        skView.preferredFramesPerSecond = 60
        
        // Create scene
        let scene = PetScene(size: screen.frame.size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        skView.presentScene(scene)
        
        window.contentView = skView
        window.makeKeyAndOrderFront(nil)
        
        // Status bar icon for quit
        setupStatusItem()
        
        // Track mouse globally (window is fully click-through)
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
app.setActivationPolicy(.accessory) // No dock icon
app.run()
