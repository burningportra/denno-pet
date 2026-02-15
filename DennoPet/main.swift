import Cocoa
import SpriteKit
import AVFoundation
import IOKit.ps

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

enum CreatureState: String {
    case idle
    case wanderLeft
    case wanderRight
    case curious
    case startle
    case glitch
    case sleep
    case windowWalk    // walking on top of a window title bar
    case windowHop     // jumping between windows
    case wakeUp        // transitioning from sleep
}

// MARK: - Window Ledge (title bar surfaces to walk on)

struct WindowLedge {
    let x: CGFloat      // left edge
    let y: CGFloat      // top of window (where creature walks)
    let width: CGFloat
    let windowName: String
}

// MARK: - Sound Generator

class SoundGenerator {
    static let shared = SoundGenerator()
    private var audioEngine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    
    private init() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        audioEngine.attach(playerNode)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
        audioEngine.mainMixerNode.outputVolume = 0.15
        
        try? audioEngine.start()
    }
    
    func playChirp(frequency: Float = 1200, duration: Float = 0.06) {
        let sampleRate: Float = 44100
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Float(i) / sampleRate
            let envelope = 1.0 - (t / duration) // linear decay
            // Digital chirp: mix of sine + slight noise
            let sine = sin(2.0 * .pi * frequency * t)
            let harmonic = sin(2.0 * .pi * frequency * 2.3 * t) * 0.3
            data[i] = (sine + harmonic) * envelope * 0.3
        }
        
        playerNode.stop()
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        playerNode.play()
    }
    
    func playGlitchSound() {
        let sampleRate: Float = 44100
        let duration: Float = 0.12
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Float(i) / sampleRate
            let envelope = max(0, 1.0 - (t / duration))
            // Harsh digital noise burst
            let noise = Float.random(in: -1...1)
            let buzz = sin(2.0 * .pi * 180 * t) * 0.5
            let crackle = (i % Int.random(in: 30...60) == 0) ? Float.random(in: -0.8...0.8) : 0
            data[i] = (noise * 0.3 + buzz + crackle) * envelope * 0.25
        }
        
        playerNode.stop()
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        playerNode.play()
    }
    
    func playHappyChirp() {
        // Rising two-tone chirp
        let sampleRate: Float = 44100
        let duration: Float = 0.15
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Float(i) / sampleRate
            let envelope = max(0, 1.0 - (t / duration) * 0.5)
            let freq = 800 + (t / duration) * 600 // rising pitch
            let sine = sin(2.0 * .pi * freq * t)
            data[i] = sine * envelope * 0.25
        }
        
        playerNode.stop()
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        playerNode.play()
    }
    
    func playSleepSound() {
        // Soft descending tone
        let sampleRate: Float = 44100
        let duration: Float = 0.3
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Float(i) / sampleRate
            let envelope = max(0, 1.0 - (t / duration))
            let freq: Float = 600 - (t / duration) * 300 // descending
            let sine = sin(2.0 * .pi * freq * t)
            data[i] = sine * envelope * envelope * 0.15 // quadratic decay = softer
        }
        
        playerNode.stop()
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        playerNode.play()
    }
}

// MARK: - System State Monitor

class SystemMonitor {
    static let shared = SystemMonitor()
    
    var batteryLevel: Float = 1.0
    var isOnBattery: Bool = false
    var isDarkMode: Bool = false
    var hour: Int = 12
    
    func update() {
        // Battery
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
           let first = sources.first,
           let desc = IOPSGetPowerSourceDescription(snapshot, first as CFTypeRef)?.takeUnretainedValue() as? [String: Any] {
            if let capacity = desc[kIOPSCurrentCapacityKey] as? Int,
               let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                batteryLevel = Float(capacity) / Float(max)
            }
            if let source = desc[kIOPSPowerSourceStateKey] as? String {
                isOnBattery = (source == kIOPSBatteryPowerValue)
            }
        }
        
        // Dark mode
        let appearance = NSApp.effectiveAppearance.name
        isDarkMode = appearance == .darkAqua || appearance == .vibrantDark ||
                     appearance == .accessibilityHighContrastDarkAqua ||
                     appearance == .accessibilityHighContrastVibrantDark
        
        // Hour
        hour = Calendar.current.component(.hour, from: Date())
    }
    
    var isNightTime: Bool { hour >= 22 || hour < 7 }
    var isLowBattery: Bool { isOnBattery && batteryLevel < 0.2 }
}

// MARK: - Pet Scene

class PetScene: SKScene {
    var creature: SKNode!
    var body: SKShapeNode!
    var bodyGhost1: SKShapeNode!
    var bodyGhost2: SKShapeNode!
    var leftEye: SKShapeNode!
    var rightEye: SKShapeNode!
    var noDataLabel: SKLabelNode!
    var noDataLabel2: SKLabelNode!
    var scanLines: SKSpriteNode!
    var trailEmitter: SKEmitterNode?
    var dustEmitter: SKEmitterNode?
    var sleepZzz: SKLabelNode?
    
    var state: CreatureState = .idle
    var stateTimer: TimeInterval = 0
    var nextStateChange: TimeInterval = 3.0
    var glitchTimer: TimeInterval = 0
    var edgeGlitchIntensity: CGFloat = 0
    var lastMousePosition: CGPoint = .zero
    var lastMouseTime: TimeInterval = 0
    var isMoving: Bool = false
    var lastCreatureX: CGFloat = 0
    var inactivityTimer: TimeInterval = 0
    var lastInteractionTime: TimeInterval = 0
    var systemCheckTimer: TimeInterval = 0
    var soundEnabled: Bool = true
    var windowLedges: [WindowLedge] = []
    var currentLedge: WindowLedge? = nil
    var targetLedgeY: CGFloat? = nil
    var windowScanTimer: TimeInterval = 0
    
    let groundY: CGFloat = 60
    let edgePanicZone: CGFloat = 80
    let sleepAfterSeconds: TimeInterval = 180 // 3 min inactivity → sleep
    
    override func didMove(to view: SKView) {
        backgroundColor = .clear
        setupCreature()
        scheduleNextState()
        lastInteractionTime = CACurrentMediaTime()
    }
    
    // MARK: - Body Path
    
    func createBodyPath() -> CGPath {
        let bodyPath = CGMutablePath()
        bodyPath.move(to: CGPoint(x: -22, y: -2))
        bodyPath.addCurve(to: CGPoint(x: -18, y: 18),
                         control1: CGPoint(x: -28, y: 5),
                         control2: CGPoint(x: -24, y: 16))
        bodyPath.addCurve(to: CGPoint(x: -5, y: 34),
                         control1: CGPoint(x: -14, y: 22),
                         control2: CGPoint(x: -10, y: 36))
        bodyPath.addCurve(to: CGPoint(x: 8, y: 32),
                         control1: CGPoint(x: 0, y: 37),
                         control2: CGPoint(x: 5, y: 35))
        bodyPath.addCurve(to: CGPoint(x: 20, y: 16),
                         control1: CGPoint(x: 14, y: 30),
                         control2: CGPoint(x: 22, y: 22))
        bodyPath.addCurve(to: CGPoint(x: 18, y: 0),
                         control1: CGPoint(x: 24, y: 10),
                         control2: CGPoint(x: 22, y: 3))
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
        
        // Chromatic aberration ghost layers
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
        
        // Main body
        body = SKShapeNode(path: bodyPath)
        body.fillColor = NSColor(red: 0.08, green: 0.12, blue: 0.15, alpha: 0.82)
        body.strokeColor = NSColor(red: 0.2, green: 0.35, blue: 0.4, alpha: 0.35)
        body.lineWidth = 1.0
        body.glowWidth = 3
        creature.addChild(body)
        
        // Scan-line overlay clipped to body
        let scanCrop = SKCropNode()
        let maskShape = SKShapeNode(path: bodyPath)
        maskShape.fillColor = .white
        maskShape.strokeColor = .clear
        scanCrop.maskNode = maskShape
        scanLines = createScanLineSprite()
        scanLines.position = CGPoint(x: 0, y: 16)
        scanLines.alpha = 0.25
        scanCrop.addChild(scanLines)
        scanCrop.zPosition = 10
        creature.addChild(scanCrop)
        
        // Eyes
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
        
        // NO DATA labels
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
        
        // Sleep Zzz indicator (hidden)
        sleepZzz = SKLabelNode(text: "z")
        sleepZzz?.fontName = "Menlo"
        sleepZzz?.fontSize = 10
        sleepZzz?.fontColor = NSColor(red: 0.4, green: 0.7, blue: 0.65, alpha: 0.6)
        sleepZzz?.position = CGPoint(x: 15, y: 30)
        sleepZzz?.alpha = 0
        sleepZzz?.zPosition = 25
        creature.addChild(sleepZzz!)
        
        // Breathing
        let breathe = SKAction.sequence([
            SKAction.scaleY(to: 1.04, duration: 2.5),
            SKAction.scaleY(to: 0.97, duration: 2.5)
        ])
        body.run(SKAction.repeatForever(breathe), withKey: "breathe")
        
        // Eye blink
        let blinkSequence = SKAction.sequence([
            SKAction.wait(forDuration: 3.0, withRange: 4.0),
            SKAction.scaleY(to: 0.1, duration: 0.08),
            SKAction.scaleY(to: 1.0, duration: 0.12),
        ])
        leftEye.run(SKAction.repeatForever(blinkSequence), withKey: "blink")
        rightEye.run(SKAction.repeatForever(blinkSequence), withKey: "blink")
        
        // Ambient dust
        dustEmitter = createDigitalDust()
        if let dust = dustEmitter {
            dust.position = CGPoint(x: 0, y: 15)
            dust.zPosition = 5
            creature.addChild(dust)
        }
        
        // Trail
        trailEmitter = createDennoTrail()
        if let trail = trailEmitter {
            trail.position = CGPoint(x: 0, y: 0)
            trail.zPosition = -2
            trail.particleBirthRate = 0
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
        for y in stride(from: 0, to: h, by: 3) {
            NSColor(white: 1.0, alpha: 0.4).setFill()
            NSRect(x: 0, y: y, width: w, height: 1).fill()
        }
        image.unlockFocus()
        let sprite = SKSpriteNode(texture: SKTexture(image: image))
        sprite.blendMode = .alpha
        return sprite
    }
    
    // MARK: - Particle Emitters
    
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
    
    func createDennoTrail() -> SKEmitterNode? {
        let emitter = SKEmitterNode()
        emitter.particleBirthRate = 12
        emitter.particleLifetime = 0.8
        emitter.particleLifetimeRange = 0.4
        emitter.emissionAngle = -.pi / 2
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
    
    // MARK: - Window Scanning (for window-walking)
    
    func scanWindowLedges() {
        windowLedges.removeAll()
        guard let screen = NSScreen.main else { return }
        let screenH = screen.frame.height
        
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        
        for w in windowList {
            guard let bounds = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = w[kCGWindowLayer as String] as? Int,
                  let ownerName = w[kCGWindowOwnerName as String] as? String else { continue }
            
            // Only normal windows (layer 0), skip our own window, menubar, dock
            guard layer == 0 else { continue }
            if ownerName == "denno-pet" || ownerName == "Dock" || ownerName == "Window Server" { continue }
            
            let x = bounds["X"] ?? 0
            let y = bounds["Y"] ?? 0
            let width = bounds["Width"] ?? 0
            let height = bounds["Height"] ?? 0
            
            // Skip tiny windows
            guard width > 100 && height > 50 else { continue }
            
            // Convert from CG coords (top-left origin) to SpriteKit coords (bottom-left)
            let topInSK = screenH - y
            
            let ledge = WindowLedge(x: x, y: topInSK, width: width, windowName: ownerName)
            windowLedges.append(ledge)
        }
        
        // Sort by height (prefer higher windows for variety)
        windowLedges.sort { $0.y > $1.y }
    }
    
    // MARK: - Sleep
    
    func enterSleep() {
        guard state != .sleep else { return }
        state = .sleep
        
        if soundEnabled { SoundGenerator.shared.playSleepSound() }
        
        // Fade creature
        creature.run(SKAction.fadeAlpha(to: 0.4, duration: 2.0))
        
        // Eyes close
        leftEye.run(SKAction.scaleY(to: 0.05, duration: 0.5))
        rightEye.run(SKAction.scaleY(to: 0.05, duration: 0.5))
        
        // Slow down breathing
        body.removeAction(forKey: "breathe")
        let sleepBreathe = SKAction.sequence([
            SKAction.scaleY(to: 1.02, duration: 4.0),
            SKAction.scaleY(to: 0.98, duration: 4.0)
        ])
        body.run(SKAction.repeatForever(sleepBreathe), withKey: "breathe")
        
        // Reduce particles
        dustEmitter?.particleBirthRate = 0.5
        
        // Show Zzz animation
        animateZzz()
    }
    
    func animateZzz() {
        guard state == .sleep, let zzz = sleepZzz else { return }
        zzz.text = ["z", "zz", "zzz"].randomElement()!
        zzz.position = CGPoint(x: CGFloat.random(in: 12...18), y: 30)
        
        let float = SKAction.sequence([
            SKAction.group([
                SKAction.fadeAlpha(to: 0.6, duration: 0.3),
                SKAction.moveBy(x: CGFloat.random(in: -3...5), y: 15, duration: 2.0),
            ]),
            SKAction.fadeAlpha(to: 0, duration: 0.5),
            SKAction.wait(forDuration: Double.random(in: 1.0...3.0)),
            SKAction.run { [weak self] in self?.animateZzz() }
        ])
        zzz.run(float, withKey: "zzz")
    }
    
    func wakeUp() {
        guard state == .sleep else { return }
        state = .wakeUp
        
        if soundEnabled { SoundGenerator.shared.playChirp(frequency: 900, duration: 0.08) }
        
        sleepZzz?.removeAction(forKey: "zzz")
        sleepZzz?.alpha = 0
        
        creature.run(SKAction.fadeAlpha(to: 1.0, duration: 0.5))
        leftEye.run(SKAction.scaleY(to: 1.0, duration: 0.3))
        rightEye.run(SKAction.scaleY(to: 1.0, duration: 0.3))
        
        // Restore normal breathing
        body.removeAction(forKey: "breathe")
        let breathe = SKAction.sequence([
            SKAction.scaleY(to: 1.04, duration: 2.5),
            SKAction.scaleY(to: 0.97, duration: 2.5)
        ])
        body.run(SKAction.repeatForever(breathe), withKey: "breathe")
        
        dustEmitter?.particleBirthRate = 2.5
        
        // Brief startle glitch on wake
        triggerGlitch(withNoData: false)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.state = .idle
            self?.scheduleNextState()
        }
    }
    
    // MARK: - Window Walking
    
    func tryWindowHop() {
        guard !windowLedges.isEmpty else { return }
        
        // Pick a random ledge
        let ledge = windowLedges.randomElement()!
        currentLedge = ledge
        
        // Hop up to the window's title bar
        let targetX = ledge.x + CGFloat.random(in: 20...(max(ledge.width - 20, 30)))
        let targetY = ledge.y
        
        state = .windowHop
        
        if soundEnabled { SoundGenerator.shared.playChirp(frequency: 1400, duration: 0.04) }
        
        // Jump arc
        let midY = max(creature.position.y, targetY) + 40
        let jumpUp = SKAction.moveTo(y: midY, duration: 0.2)
        jumpUp.timingMode = .easeOut
        let moveOver = SKAction.moveTo(x: targetX, duration: 0.25)
        moveOver.timingMode = .easeInEaseOut
        let land = SKAction.moveTo(y: targetY, duration: 0.15)
        land.timingMode = .easeIn
        
        let hop = SKAction.sequence([
            SKAction.group([jumpUp, moveOver]),
            land,
            SKAction.run { [weak self] in
                self?.state = .windowWalk
                self?.targetLedgeY = targetY
                self?.scheduleNextState()
            }
        ])
        creature.run(hop)
    }
    
    func returnToGround() {
        currentLedge = nil
        targetLedgeY = nil
        
        if soundEnabled { SoundGenerator.shared.playChirp(frequency: 600, duration: 0.05) }
        
        let fall = SKAction.moveTo(y: groundY, duration: 0.3)
        fall.timingMode = .easeIn
        creature.run(SKAction.sequence([
            fall,
            SKAction.run { [weak self] in
                self?.state = .idle
                self?.scheduleNextState()
            }
        ]))
    }
    
    // MARK: - Update Loop
    
    override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval = 1.0 / 60.0
        stateTimer += dt
        glitchTimer += dt
        inactivityTimer += dt
        systemCheckTimer += dt
        windowScanTimer += dt
        
        // Periodic system state check
        if systemCheckTimer > 30 {
            SystemMonitor.shared.update()
            systemCheckTimer = 0
            applySystemEffects()
        }
        
        // Periodic window scan for ledges
        if windowScanTimer > 10 {
            scanWindowLedges()
            windowScanTimer = 0
        }
        
        // Sleep check
        if state != .sleep && state != .wakeUp && inactivityTimer > sleepAfterSeconds {
            enterSleep()
            return
        }
        
        // If sleeping, just bob gently
        if state == .sleep {
            let sleepBob = CGFloat(sin(currentTime * 0.8)) * 0.5
            let baseY = targetLedgeY ?? groundY
            creature.position.y = baseY + sleepBob
            return
        }
        
        if state == .wakeUp || state == .windowHop { return }
        
        // State transitions
        if stateTimer >= nextStateChange {
            transitionToNextState()
        }
        
        // Edge panic
        let leftDist = creature.position.x
        let rightDist = size.width - creature.position.x
        let edgeDist = min(leftDist, rightDist)
        
        if edgeDist < edgePanicZone {
            edgeGlitchIntensity = 1.0 - (edgeDist / edgePanicZone)
            scanLines.alpha = 0.25 + edgeGlitchIntensity * 0.5
            if glitchTimer > Double(2.0 - edgeGlitchIntensity * 1.5) {
                triggerGlitch(withNoData: edgeGlitchIntensity > 0.5)
                glitchTimer = 0
            }
        } else {
            edgeGlitchIntensity = 0
            scanLines.alpha = 0.25
            if glitchTimer > Double.random(in: 8.0...20.0) {
                triggerGlitch(withNoData: Bool.random() && Bool.random())
                glitchTimer = 0
            }
        }
        
        // Trail
        let dx = abs(creature.position.x - lastCreatureX)
        isMoving = dx > 0.3
        lastCreatureX = creature.position.x
        trailEmitter?.particleBirthRate = isMoving ? 12 : 0
        
        // Movement
        let baseY = targetLedgeY ?? groundY
        
        switch state {
        case .wanderLeft:
            creature.position.x -= 0.5
            creature.xScale = -1
            // Boundary: screen edge or ledge edge
            let leftBound: CGFloat = currentLedge?.x ?? 50
            if creature.position.x < leftBound + 10 {
                if currentLedge != nil {
                    returnToGround()
                } else {
                    state = .wanderRight
                }
            }
        case .wanderRight:
            creature.position.x += 0.5
            creature.xScale = 1
            let rightBound: CGFloat = currentLedge.map { $0.x + $0.width } ?? (size.width - 50)
            if creature.position.x > rightBound - 10 {
                if currentLedge != nil {
                    returnToGround()
                } else {
                    state = .wanderLeft
                }
            }
        case .idle, .windowWalk:
            creature.position.x += CGFloat.random(in: -0.15...0.15)
        default:
            break
        }
        
        // Floating bob
        let bob = CGFloat(sin(currentTime * 2.0)) * 1.5
        creature.position.y = baseY + bob
        
        // Scan line scroll
        scanLines.position.y = 16 + CGFloat(sin(currentTime * 3.0)) * 0.5
    }
    
    // MARK: - System Effects
    
    func applySystemEffects() {
        let monitor = SystemMonitor.shared
        
        // Low battery → more glitchy, desaturated
        if monitor.isLowBattery {
            body.fillColor = NSColor(red: 0.06, green: 0.08, blue: 0.1, alpha: 0.85)
            leftEye.fillColor = NSColor(red: 0.35, green: 0.65, blue: 0.6, alpha: 0.7)
            rightEye.fillColor = NSColor(red: 0.35, green: 0.65, blue: 0.6, alpha: 0.7)
            leftEye.glowWidth = 2
            rightEye.glowWidth = 2
        } else {
            body.fillColor = NSColor(red: 0.08, green: 0.12, blue: 0.15, alpha: 0.82)
            leftEye.fillColor = NSColor(red: 0.4, green: 0.85, blue: 0.8, alpha: 0.95)
            rightEye.fillColor = NSColor(red: 0.4, green: 0.85, blue: 0.8, alpha: 0.95)
            leftEye.glowWidth = 4
            rightEye.glowWidth = 4
        }
        
        // Night time → sleepier, dimmer eyes
        if monitor.isNightTime && state != .sleep {
            leftEye.glowWidth = max(leftEye.glowWidth - 1, 2)
            rightEye.glowWidth = max(rightEye.glowWidth - 1, 2)
            dustEmitter?.particleBirthRate = 1.5
        }
    }
    
    func transitionToNextState() {
        // Window walking has a chance to trigger
        let onGround = currentLedge == nil
        let roll = Double.random(in: 0...1)
        
        if onGround {
            switch roll {
            case 0..<0.25:
                state = .idle
            case 0.25..<0.45:
                state = .wanderLeft
            case 0.45..<0.65:
                state = .wanderRight
            case 0.65..<0.8:
                // Try to hop onto a window
                if !windowLedges.isEmpty {
                    tryWindowHop()
                    return
                }
                state = .idle
            default:
                state = .idle
            }
        } else {
            // On a window ledge
            switch roll {
            case 0..<0.3:
                state = .windowWalk
            case 0.3..<0.5:
                state = .wanderLeft
            case 0.5..<0.7:
                state = .wanderRight
            case 0.7..<0.85:
                returnToGround()
                return
            default:
                // Hop to a different window
                if windowLedges.count > 1 {
                    tryWindowHop()
                    return
                }
                state = .windowWalk
            }
        }
        scheduleNextState()
    }
    
    // MARK: - Glitch Effects
    
    func triggerGlitch(withNoData: Bool = false) {
        if soundEnabled && withNoData {
            SoundGenerator.shared.playGlitchSound()
        }
        
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
        
        let scanFlare = SKAction.run { [weak self] in
            self?.scanLines.alpha = 0.7
        }
        let scanRestore = SKAction.run { [weak self] in
            self?.scanLines.alpha = 0.25 + (self?.edgeGlitchIntensity ?? 0) * 0.5
        }
        
        let noDataShow = SKAction.run { [weak self] in
            guard let self = self, withNoData else { return }
            self.noDataLabel.alpha = 0.9
            self.noDataLabel2.alpha = 0.7
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
            chromaIn, bodyBlack, scanFlare, noDataShow,
            SKAction.wait(forDuration: 0.04),
            bodyFlicker,
            SKAction.wait(forDuration: 0.03),
            bodyRestore,
            SKAction.wait(forDuration: 0.02),
            bodyBlack,
            SKAction.wait(forDuration: 0.05),
            bodyFlicker,
            SKAction.wait(forDuration: 0.03),
            bodyRestore, chromaOut, scanRestore, noDataHide,
        ])
        creature.run(glitchSequence)
    }
    
    // MARK: - Mouse Tracking
    
    func handleGlobalMouse(at location: CGPoint) {
        // Any mouse movement resets inactivity
        inactivityTimer = 0
        if state == .sleep { wakeUp(); return }
        
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
        inactivityTimer = 0
        if state == .sleep { wakeUp(); return }
        
        let dx = location.x - creature.position.x
        let dy = location.y - creature.position.y
        let distance = sqrt(dx * dx + dy * dy)
        
        if distance < 40 {
            if soundEnabled { SoundGenerator.shared.playHappyChirp() }
            
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
        let baseY = targetLedgeY ?? groundY
        let jumpAction = SKAction.sequence([
            SKAction.moveBy(x: jumpDir * 30, y: 20, duration: 0.15),
            SKAction.moveTo(y: baseY, duration: 0.2),
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
    var scene: PetScene!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        
        // Initial system check
        SystemMonitor.shared.update()
        
        window = PetWindow(forScreen: screen)
        
        let skView = PetSKView(frame: screen.frame)
        skView.allowsTransparency = true
        skView.preferredFramesPerSecond = 60
        
        scene = PetScene(size: screen.frame.size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        skView.presentScene(scene)
        
        window.contentView = skView
        window.makeKeyAndOrderFront(nil)
        
        setupStatusItem()
        
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self = self else { return }
            let screenPoint = NSEvent.mouseLocation
            let windowPoint = self.window.convertPoint(fromScreen: screenPoint)
            let scenePoint = skView.convert(windowPoint, to: self.scene)
            self.scene.handleGlobalMouse(at: scenePoint)
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return }
            let screenPoint = NSEvent.mouseLocation
            let windowPoint = self.window.convertPoint(fromScreen: screenPoint)
            let scenePoint = skView.convert(windowPoint, to: self.scene)
            self.scene.handleGlobalClick(at: scenePoint)
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
        
        let soundItem = NSMenuItem(title: "Sound Effects", action: #selector(toggleSound(_:)), keyEquivalent: "s")
        soundItem.target = self
        soundItem.state = .on
        menu.addItem(soundItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
    
    @objc func toggleSound(_ sender: NSMenuItem) {
        scene.soundEnabled.toggle()
        sender.state = scene.soundEnabled ? .on : .off
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
