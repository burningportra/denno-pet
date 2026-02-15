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

class PetSKView: SKView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Creature State

enum CreatureState: String {
    case idle, wanderLeft, wanderRight, curious, startle, glitch
    case sleep, windowWalk, windowHop, wakeUp
    case flee  // running from Densuke
}

struct WindowLedge {
    let x: CGFloat
    let y: CGFloat
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
    
    private func makeBuffer(duration: Float, generator: (Float, Float) -> Float) {
        let sampleRate: Float = 44100
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            data[i] = generator(Float(i) / sampleRate, duration)
        }
        playerNode.stop()
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        playerNode.play()
    }
    
    func playChirp(frequency: Float = 1200, duration: Float = 0.06) {
        makeBuffer(duration: duration) { t, dur in
            let env = 1.0 - (t / dur)
            return (sin(2 * .pi * frequency * t) + sin(2 * .pi * frequency * 2.3 * t) * 0.3) * env * 0.3
        }
    }
    
    func playGlitchSound() {
        makeBuffer(duration: 0.12) { t, dur in
            let env = max(0, 1.0 - (t / dur))
            let noise = Float.random(in: -1...1)
            let buzz = sin(2 * .pi * 180 * t) * 0.5
            return (noise * 0.3 + buzz) * env * 0.25
        }
    }
    
    func playHappyChirp() {
        makeBuffer(duration: 0.15) { t, dur in
            let env = max(0, 1.0 - (t / dur) * 0.5)
            let freq = 800 + (t / dur) * 600
            return sin(2 * .pi * freq * t) * env * 0.25
        }
    }
    
    func playSleepSound() {
        makeBuffer(duration: 0.3) { t, dur in
            let env = max(0, 1.0 - (t / dur))
            let freq: Float = 600 - (t / dur) * 300
            return sin(2 * .pi * freq * t) * env * env * 0.15
        }
    }
    
    func playBark() {
        makeBuffer(duration: 0.08) { t, dur in
            let env = max(0, 1.0 - (t / dur))
            let freq: Float = 400 + sin(t * 80) * 100
            return sin(2 * .pi * freq * t) * env * 0.2
        }
    }
}

// MARK: - System Monitor

class SystemMonitor {
    static let shared = SystemMonitor()
    var batteryLevel: Float = 1.0
    var isOnBattery: Bool = false
    var hour: Int = 12
    
    func update() {
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
           let first = sources.first,
           let desc = IOPSGetPowerSourceDescription(snapshot, first as CFTypeRef)?.takeUnretainedValue() as? [String: Any] {
            if let cap = desc[kIOPSCurrentCapacityKey] as? Int, let mx = desc[kIOPSMaxCapacityKey] as? Int, mx > 0 {
                batteryLevel = Float(cap) / Float(mx)
            }
            if let src = desc[kIOPSPowerSourceStateKey] as? String { isOnBattery = (src == kIOPSBatteryPowerValue) }
        }
        hour = Calendar.current.component(.hour, from: Date())
    }
    var isNightTime: Bool { hour >= 22 || hour < 7 }
    var isLowBattery: Bool { isOnBattery && batteryLevel < 0.2 }
}

// MARK: - Illegal (Creature Entity)

class Illegal {
    let node: SKNode
    let body: SKShapeNode
    let ghost1: SKShapeNode
    let ghost2: SKShapeNode
    let leftEye: SKShapeNode
    let rightEye: SKShapeNode
    let noDataLabel: SKLabelNode
    let scanLines: SKSpriteNode
    var trailEmitter: SKEmitterNode?
    var dustEmitter: SKEmitterNode?
    var sleepZzz: SKLabelNode?
    
    var state: CreatureState = .idle
    var stateTimer: TimeInterval = 0
    var nextStateChange: TimeInterval = 3.0
    var glitchTimer: TimeInterval = 0
    var edgeGlitchIntensity: CGFloat = 0
    var isMoving: Bool = false
    var lastX: CGFloat = 0
    var currentLedge: WindowLedge? = nil
    var targetLedgeY: CGFloat? = nil
    var fleeTarget: CGFloat? = nil
    
    let scale: CGFloat
    let groundY: CGFloat
    let isLeader: Bool
    
    init(scale: CGFloat = 1.0, groundY: CGFloat = 60, isLeader: Bool = false) {
        self.scale = scale
        self.groundY = groundY
        self.isLeader = isLeader
        
        node = SKNode()
        node.name = "illegal"
        node.setScale(scale)
        
        let bodyPath = Illegal.makeBodyPath(scale: 1.0)
        
        // Chromatic ghosts
        ghost1 = SKShapeNode(path: bodyPath)
        ghost1.fillColor = NSColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 0.3)
        ghost1.strokeColor = .clear
        ghost1.position = CGPoint(x: -3, y: 0)
        ghost1.alpha = 0
        ghost1.zPosition = -1
        node.addChild(ghost1)
        
        ghost2 = SKShapeNode(path: bodyPath)
        ghost2.fillColor = NSColor(red: 0.1, green: 0.1, blue: 0.9, alpha: 0.3)
        ghost2.strokeColor = .clear
        ghost2.position = CGPoint(x: 3, y: 0)
        ghost2.alpha = 0
        ghost2.zPosition = -1
        node.addChild(ghost2)
        
        // Body
        body = SKShapeNode(path: bodyPath)
        body.fillColor = NSColor(red: 0.08, green: 0.12, blue: 0.15, alpha: 0.82)
        body.strokeColor = NSColor(red: 0.2, green: 0.35, blue: 0.4, alpha: 0.35)
        body.lineWidth = 1.0
        body.glowWidth = 3
        node.addChild(body)
        
        // Scan lines clipped
        let scanCrop = SKCropNode()
        let mask = SKShapeNode(path: bodyPath)
        mask.fillColor = .white; mask.strokeColor = .clear
        scanCrop.maskNode = mask
        scanLines = Illegal.makeScanLines()
        scanLines.position = CGPoint(x: 0, y: 16)
        scanLines.alpha = 0.25
        scanCrop.addChild(scanLines)
        scanCrop.zPosition = 10
        node.addChild(scanCrop)
        
        // Eyes
        let eyeRadius: CGFloat = 3.5
        leftEye = SKShapeNode(circleOfRadius: eyeRadius)
        leftEye.fillColor = NSColor(red: 0.4, green: 0.85, blue: 0.8, alpha: 0.95)
        leftEye.strokeColor = .clear
        leftEye.position = CGPoint(x: -7, y: 20)
        leftEye.glowWidth = 4; leftEye.zPosition = 20
        node.addChild(leftEye)
        
        rightEye = SKShapeNode(circleOfRadius: eyeRadius)
        rightEye.fillColor = NSColor(red: 0.4, green: 0.85, blue: 0.8, alpha: 0.95)
        rightEye.strokeColor = .clear
        rightEye.position = CGPoint(x: 7, y: 20)
        rightEye.glowWidth = 4; rightEye.zPosition = 20
        node.addChild(rightEye)
        
        // NO DATA
        noDataLabel = SKLabelNode(text: "NO DATA")
        noDataLabel.fontName = "Menlo-Bold"
        noDataLabel.fontSize = 8
        noDataLabel.fontColor = NSColor(red: 0.9, green: 0.95, blue: 0.9, alpha: 0.9)
        noDataLabel.position = CGPoint(x: 0, y: 14)
        noDataLabel.alpha = 0; noDataLabel.zPosition = 30
        node.addChild(noDataLabel)
        
        // Sleep Zzz
        sleepZzz = SKLabelNode(text: "z")
        sleepZzz!.fontName = "Menlo"; sleepZzz!.fontSize = 10
        sleepZzz!.fontColor = NSColor(red: 0.4, green: 0.7, blue: 0.65, alpha: 0.6)
        sleepZzz!.position = CGPoint(x: 15, y: 30)
        sleepZzz!.alpha = 0; sleepZzz!.zPosition = 25
        node.addChild(sleepZzz!)
        
        // Breathing
        let breathe = SKAction.sequence([
            SKAction.scaleY(to: 1.04, duration: 2.5),
            SKAction.scaleY(to: 0.97, duration: 2.5)
        ])
        body.run(SKAction.repeatForever(breathe), withKey: "breathe")
        
        // Blink
        let blink = SKAction.sequence([
            SKAction.wait(forDuration: 3.0, withRange: 4.0),
            SKAction.scaleY(to: 0.1, duration: 0.08),
            SKAction.scaleY(to: 1.0, duration: 0.12),
        ])
        leftEye.run(SKAction.repeatForever(blink), withKey: "blink")
        rightEye.run(SKAction.repeatForever(blink), withKey: "blink")
        
        // Dust
        dustEmitter = Illegal.makeDust()
        if let d = dustEmitter { d.position = CGPoint(x: 0, y: 15); d.zPosition = 5; node.addChild(d) }
        
        // Trail
        trailEmitter = Illegal.makeTrail()
        if let t = trailEmitter { t.position = .zero; t.zPosition = -2; t.particleBirthRate = 0; node.addChild(t) }
    }
    
    // MARK: - Static Factories
    
    static func makeBodyPath(scale: CGFloat = 1.0) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -22, y: -2))
        p.addCurve(to: CGPoint(x: -18, y: 18), control1: CGPoint(x: -28, y: 5), control2: CGPoint(x: -24, y: 16))
        p.addCurve(to: CGPoint(x: -5, y: 34), control1: CGPoint(x: -14, y: 22), control2: CGPoint(x: -10, y: 36))
        p.addCurve(to: CGPoint(x: 8, y: 32), control1: CGPoint(x: 0, y: 37), control2: CGPoint(x: 5, y: 35))
        p.addCurve(to: CGPoint(x: 20, y: 16), control1: CGPoint(x: 14, y: 30), control2: CGPoint(x: 22, y: 22))
        p.addCurve(to: CGPoint(x: 18, y: 0), control1: CGPoint(x: 24, y: 10), control2: CGPoint(x: 22, y: 3))
        p.addCurve(to: CGPoint(x: 5, y: -4), control1: CGPoint(x: 14, y: -3), control2: CGPoint(x: 10, y: -5))
        p.addCurve(to: CGPoint(x: -8, y: -3), control1: CGPoint(x: 0, y: -6), control2: CGPoint(x: -4, y: -4))
        p.addCurve(to: CGPoint(x: -22, y: -2), control1: CGPoint(x: -14, y: -4), control2: CGPoint(x: -18, y: -3))
        p.closeSubpath()
        return p
    }
    
    static func makeScanLines() -> SKSpriteNode {
        let w = 50, h = 44
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        NSColor.clear.setFill(); NSRect(origin: .zero, size: NSSize(width: w, height: h)).fill()
        for y in stride(from: 0, to: h, by: 3) {
            NSColor(white: 1.0, alpha: 0.4).setFill()
            NSRect(x: 0, y: y, width: w, height: 1).fill()
        }
        img.unlockFocus()
        let s = SKSpriteNode(texture: SKTexture(image: img)); s.blendMode = .alpha; return s
    }
    
    static func makeSquareTexture(size: Int) -> SKTexture {
        let s = CGSize(width: size, height: size)
        let img = NSImage(size: s)
        img.lockFocus(); NSColor.white.setFill(); NSRect(origin: .zero, size: s).fill(); img.unlockFocus()
        return SKTexture(image: img)
    }
    
    static func makeDust() -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleBirthRate = 2.5; e.particleLifetime = 1.8; e.particleLifetimeRange = 1.0
        e.emissionAngle = .pi/2; e.emissionAngleRange = .pi*0.6
        e.particleSpeed = 4; e.particleSpeedRange = 6
        e.particleAlpha = 0.35; e.particleAlphaRange = 0.2; e.particleAlphaSpeed = -0.2
        e.particleScale = 0.25; e.particleScaleRange = 0.15
        e.particleColor = NSColor(red: 0.3, green: 0.7, blue: 0.65, alpha: 1); e.particleColorBlendFactor = 1
        e.particleTexture = makeSquareTexture(size: 3)
        return e
    }
    
    static func makeTrail() -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleBirthRate = 12; e.particleLifetime = 0.8; e.particleLifetimeRange = 0.4
        e.emissionAngle = -.pi/2; e.emissionAngleRange = .pi*0.4
        e.particleSpeed = 3; e.particleSpeedRange = 5
        e.particleAlpha = 0.5; e.particleAlphaRange = 0.2; e.particleAlphaSpeed = -0.6
        e.particleScale = 0.4; e.particleScaleRange = 0.3; e.particleScaleSpeed = -0.2
        e.particleColor = NSColor(red: 0.05, green: 0.08, blue: 0.1, alpha: 1); e.particleColorBlendFactor = 1
        e.particleTexture = makeSquareTexture(size: 4)
        return e
    }
    
    // MARK: - Glitch
    
    func triggerGlitch(withNoData: Bool = false, sound: Bool = false) {
        if sound && withNoData { SoundGenerator.shared.playGlitchSound() }
        
        let seq = SKAction.sequence([
            SKAction.run { [weak self] in
                guard let s = self else { return }
                let off = CGFloat.random(in: 2...5)
                s.ghost1.position.x = -off; s.ghost2.position.x = off
                s.ghost1.alpha = 0.5; s.ghost2.alpha = 0.5
                s.body.fillColor = NSColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 0.95)
                s.body.glowWidth = 0; s.node.position.x += CGFloat.random(in: -4...4)
                s.scanLines.alpha = 0.7
                if withNoData { s.noDataLabel.alpha = 0.9; s.leftEye.alpha = 0; s.rightEye.alpha = 0 }
            },
            SKAction.wait(forDuration: 0.04),
            SKAction.run { [weak self] in self?.body.alpha = CGFloat.random(in: 0.2...0.5) },
            SKAction.wait(forDuration: 0.03),
            SKAction.run { [weak self] in
                guard let s = self else { return }
                s.body.fillColor = NSColor(red: 0.08, green: 0.12, blue: 0.15, alpha: 0.82)
                s.body.alpha = 1.0; s.body.glowWidth = 3
            },
            SKAction.wait(forDuration: 0.02),
            SKAction.run { [weak self] in
                self?.body.fillColor = NSColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 0.95)
                self?.body.alpha = CGFloat.random(in: 0.2...0.5)
            },
            SKAction.wait(forDuration: 0.05),
            SKAction.run { [weak self] in
                guard let s = self else { return }
                s.body.fillColor = NSColor(red: 0.08, green: 0.12, blue: 0.15, alpha: 0.82)
                s.body.alpha = 1.0; s.body.glowWidth = 3
                s.ghost1.alpha = 0; s.ghost2.alpha = 0
                s.scanLines.alpha = 0.25 + s.edgeGlitchIntensity * 0.5
                s.noDataLabel.alpha = 0; s.leftEye.alpha = 1; s.rightEye.alpha = 1
            },
        ])
        node.run(seq)
    }
    
    // MARK: - Sleep
    
    func enterSleep(sound: Bool) {
        guard state != .sleep else { return }
        state = .sleep
        if sound { SoundGenerator.shared.playSleepSound() }
        node.run(SKAction.fadeAlpha(to: 0.4, duration: 2.0))
        leftEye.run(SKAction.scaleY(to: 0.05, duration: 0.5))
        rightEye.run(SKAction.scaleY(to: 0.05, duration: 0.5))
        body.removeAction(forKey: "breathe")
        body.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scaleY(to: 1.02, duration: 4.0),
            SKAction.scaleY(to: 0.98, duration: 4.0)
        ])), withKey: "breathe")
        dustEmitter?.particleBirthRate = 0.5
        animateZzz()
    }
    
    func animateZzz() {
        guard state == .sleep, let zzz = sleepZzz else { return }
        zzz.text = ["z","zz","zzz"].randomElement()!
        zzz.position = CGPoint(x: CGFloat.random(in: 12...18), y: 30)
        zzz.run(SKAction.sequence([
            SKAction.group([SKAction.fadeAlpha(to: 0.6, duration: 0.3), SKAction.moveBy(x: CGFloat.random(in: -3...5), y: 15, duration: 2.0)]),
            SKAction.fadeAlpha(to: 0, duration: 0.5),
            SKAction.wait(forDuration: Double.random(in: 1...3)),
            SKAction.run { [weak self] in self?.animateZzz() }
        ]), withKey: "zzz")
    }
    
    func wakeUp(sound: Bool) {
        guard state == .sleep else { return }
        state = .wakeUp
        if sound { SoundGenerator.shared.playChirp(frequency: 900, duration: 0.08) }
        sleepZzz?.removeAction(forKey: "zzz"); sleepZzz?.alpha = 0
        node.run(SKAction.fadeAlpha(to: 1.0, duration: 0.5))
        leftEye.run(SKAction.scaleY(to: 1.0, duration: 0.3))
        rightEye.run(SKAction.scaleY(to: 1.0, duration: 0.3))
        body.removeAction(forKey: "breathe")
        body.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scaleY(to: 1.04, duration: 2.5), SKAction.scaleY(to: 0.97, duration: 2.5)
        ])), withKey: "breathe")
        dustEmitter?.particleBirthRate = 2.5
        triggerGlitch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.state = .idle; self?.scheduleNext()
        }
    }
    
    func scheduleNext() {
        nextStateChange = Double.random(in: 2...6)
        stateTimer = 0
    }
    
    // MARK: - Flee from Densuke
    
    func startFlee(from dogX: CGFloat, screenWidth: CGFloat) {
        state = .flee
        // Run away from dog
        let dir: CGFloat = dogX > node.position.x ? -1 : 1
        fleeTarget = node.position.x + dir * CGFloat.random(in: 80...200)
        fleeTarget = max(50, min(screenWidth - 50, fleeTarget!))
        triggerGlitch(withNoData: true)
    }
}

// MARK: - Densuke (Dog Entity)

class Densuke {
    let node: SKNode
    let bodyShape: SKShapeNode
    let leftEye: SKShapeNode
    let rightEye: SKShapeNode
    let nose: SKShapeNode
    let tail: SKShapeNode
    var trailEmitter: SKEmitterNode?
    
    var isActive: Bool = false
    var targetIllegal: Illegal? = nil
    var chaseTimer: TimeInterval = 0
    var lifetime: TimeInterval = 0
    var maxLifetime: TimeInterval
    var sniffTimer: TimeInterval = 0
    
    enum DogState { case enter, wander, sniff, chase, exit }
    var state: DogState = .enter
    
    init(maxLifetime: TimeInterval = 30) {
        self.maxLifetime = maxLifetime
        node = SKNode()
        node.name = "densuke"
        node.setScale(0.9)
        
        // Densuke — cream/yellow-white chubby puppy dog
        // Inspired by the actual Dennō Coil design: round, soft, friendly
        // Looks like a small Labrador/Shiba puppy
        let dogPath = CGMutablePath()
        
        // Start at bottom-left of body
        dogPath.move(to: CGPoint(x: -20, y: 2))
        // Back haunch (chubby rear)
        dogPath.addCurve(to: CGPoint(x: -16, y: 12),
                         control1: CGPoint(x: -22, y: 5),
                         control2: CGPoint(x: -20, y: 10))
        // Back (gentle slope up to head)
        dogPath.addCurve(to: CGPoint(x: -4, y: 18),
                         control1: CGPoint(x: -12, y: 14),
                         control2: CGPoint(x: -8, y: 17))
        // Back of head (round)
        dogPath.addCurve(to: CGPoint(x: 2, y: 26),
                         control1: CGPoint(x: -2, y: 20),
                         control2: CGPoint(x: -1, y: 24))
        // Left floppy ear (droops down from head)
        dogPath.addCurve(to: CGPoint(x: -4, y: 20),
                         control1: CGPoint(x: -1, y: 27),
                         control2: CGPoint(x: -4, y: 24))
        dogPath.addCurve(to: CGPoint(x: 0, y: 16),
                         control1: CGPoint(x: -5, y: 17),
                         control2: CGPoint(x: -2, y: 16))
        // Top of head (round dome)
        dogPath.addCurve(to: CGPoint(x: 12, y: 26),
                         control1: CGPoint(x: 3, y: 20),
                         control2: CGPoint(x: 8, y: 26))
        // Right floppy ear (droops down)
        dogPath.addCurve(to: CGPoint(x: 18, y: 20),
                         control1: CGPoint(x: 16, y: 27),
                         control2: CGPoint(x: 18, y: 24))
        dogPath.addCurve(to: CGPoint(x: 14, y: 22),
                         control1: CGPoint(x: 19, y: 17),
                         control2: CGPoint(x: 16, y: 19))
        // Forehead down to snout
        dogPath.addCurve(to: CGPoint(x: 22, y: 16),
                         control1: CGPoint(x: 16, y: 22),
                         control2: CGPoint(x: 20, y: 20))
        // Snout (short, rounded — puppy face)
        dogPath.addCurve(to: CGPoint(x: 26, y: 13),
                         control1: CGPoint(x: 24, y: 16),
                         control2: CGPoint(x: 26, y: 15))
        dogPath.addCurve(to: CGPoint(x: 22, y: 10),
                         control1: CGPoint(x: 27, y: 12),
                         control2: CGPoint(x: 25, y: 10))
        // Under chin
        dogPath.addCurve(to: CGPoint(x: 16, y: 10),
                         control1: CGPoint(x: 20, y: 10),
                         control2: CGPoint(x: 18, y: 10))
        // Chest (round, chubby)
        dogPath.addCurve(to: CGPoint(x: 18, y: 2),
                         control1: CGPoint(x: 18, y: 7),
                         control2: CGPoint(x: 20, y: 4))
        // Front legs (stubby)
        dogPath.addCurve(to: CGPoint(x: 14, y: -2),
                         control1: CGPoint(x: 18, y: 0),
                         control2: CGPoint(x: 16, y: -2))
        dogPath.addLine(to: CGPoint(x: 10, y: -2))
        dogPath.addCurve(to: CGPoint(x: 8, y: 2),
                         control1: CGPoint(x: 9, y: -1),
                         control2: CGPoint(x: 8, y: 0))
        // Belly (round, sags slightly)
        dogPath.addCurve(to: CGPoint(x: -6, y: 0),
                         control1: CGPoint(x: 4, y: -1),
                         control2: CGPoint(x: -2, y: -2))
        // Rear legs (stubby)
        dogPath.addCurve(to: CGPoint(x: -10, y: -2),
                         control1: CGPoint(x: -8, y: -1),
                         control2: CGPoint(x: -10, y: -1))
        dogPath.addLine(to: CGPoint(x: -14, y: -2))
        dogPath.addCurve(to: CGPoint(x: -20, y: 2),
                         control1: CGPoint(x: -16, y: -2),
                         control2: CGPoint(x: -20, y: -1))
        dogPath.closeSubpath()
        
        bodyShape = SKShapeNode(path: dogPath)
        // Densuke's cream/yellowish-white color — warm, soft, "solid" digital pet
        bodyShape.fillColor = NSColor(red: 0.95, green: 0.92, blue: 0.82, alpha: 0.88)
        bodyShape.strokeColor = NSColor(red: 0.8, green: 0.75, blue: 0.6, alpha: 0.4)
        bodyShape.lineWidth = 1.0
        bodyShape.glowWidth = 1.5
        node.addChild(bodyShape)
        
        // Eyes — small, dark, round (classic anime dog eyes)
        leftEye = SKShapeNode(circleOfRadius: 2.0)
        leftEye.fillColor = NSColor(red: 0.15, green: 0.12, blue: 0.08, alpha: 0.95)
        leftEye.strokeColor = .clear
        leftEye.position = CGPoint(x: 8, y: 20)
        leftEye.glowWidth = 0.5; leftEye.zPosition = 5
        node.addChild(leftEye)
        
        rightEye = SKShapeNode(circleOfRadius: 2.0)
        rightEye.fillColor = NSColor(red: 0.15, green: 0.12, blue: 0.08, alpha: 0.95)
        rightEye.strokeColor = .clear
        rightEye.position = CGPoint(x: 16, y: 20)
        rightEye.glowWidth = 0.5; rightEye.zPosition = 5
        node.addChild(rightEye)
        
        // Nose — small, dark, at tip of snout
        nose = SKShapeNode(circleOfRadius: 1.8)
        nose.fillColor = NSColor(red: 0.18, green: 0.15, blue: 0.12, alpha: 0.95)
        nose.strokeColor = .clear
        nose.position = CGPoint(x: 25, y: 14)
        nose.zPosition = 5
        node.addChild(nose)
        
        // Tail — short, curled upward (happy puppy tail)
        let tailPath = CGMutablePath()
        tailPath.move(to: CGPoint(x: -20, y: 8))
        tailPath.addCurve(to: CGPoint(x: -28, y: 18),
                          control1: CGPoint(x: -24, y: 10),
                          control2: CGPoint(x: -28, y: 14))
        tailPath.addCurve(to: CGPoint(x: -24, y: 20),
                          control1: CGPoint(x: -28, y: 20),
                          control2: CGPoint(x: -26, y: 21))
        tail = SKShapeNode(path: tailPath)
        tail.strokeColor = NSColor(red: 0.92, green: 0.88, blue: 0.75, alpha: 0.8)
        tail.lineWidth = 3.0; tail.lineCap = .round
        tail.zPosition = -1
        node.addChild(tail)
        
        // Wag animation (happy, faster)
        let wag = SKAction.sequence([
            SKAction.rotate(toAngle: 0.25, duration: 0.12),
            SKAction.rotate(toAngle: -0.25, duration: 0.12),
        ])
        tail.run(SKAction.repeatForever(wag))
        
        // Trot animation (bouncy puppy)
        let trot = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 2.5, duration: 0.18),
            SKAction.moveBy(x: 0, y: -2.5, duration: 0.18),
        ])
        bodyShape.run(SKAction.repeatForever(trot))
        
        // Eye blink
        let blink = SKAction.sequence([
            SKAction.wait(forDuration: 2.5, withRange: 3.0),
            SKAction.scaleY(to: 0.15, duration: 0.06),
            SKAction.scaleY(to: 1.0, duration: 0.1),
        ])
        leftEye.run(SKAction.repeatForever(blink))
        rightEye.run(SKAction.repeatForever(blink))
        
        node.alpha = 0
    }
    
    func spawn(at x: CGFloat, groundY: CGFloat) {
        isActive = true
        lifetime = 0; chaseTimer = 0; sniffTimer = 0
        state = .enter
        node.position = CGPoint(x: x, y: groundY)
        node.alpha = 0
        node.run(SKAction.fadeAlpha(to: 1.0, duration: 0.5))
    }
    
    func despawn() {
        state = .exit
        node.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0, duration: 1.0),
            SKAction.run { [weak self] in self?.isActive = false; self?.targetIllegal = nil }
        ]))
    }
    
    func update(dt: TimeInterval, illegals: [Illegal], screenWidth: CGFloat, groundY: CGFloat, sound: Bool) {
        guard isActive else { return }
        lifetime += dt
        
        if lifetime > maxLifetime && state != .exit {
            despawn(); return
        }
        
        let bob = CGFloat(sin(lifetime * 3)) * 1.0
        node.position.y = groundY + bob
        
        switch state {
        case .enter:
            // Walk toward center
            let centerX = screenWidth / 2
            let dir: CGFloat = centerX > node.position.x ? 1 : -1
            node.position.x += dir * 0.8
            node.xScale = dir > 0 ? 1 : -1
            if abs(node.position.x - centerX) < 50 { state = .wander; sniffTimer = 0 }
            
        case .wander:
            // Wander randomly, occasionally sniff
            sniffTimer += dt
            node.position.x += (node.xScale > 0 ? 0.4 : -0.4)
            if node.position.x < 50 { node.xScale = 1 }
            if node.position.x > screenWidth - 50 { node.xScale = -1 }
            
            // After sniffing around, find an Illegal to chase
            if sniffTimer > Double.random(in: 3...6) {
                if let closest = illegals.min(by: { abs($0.node.position.x - node.position.x) < abs($1.node.position.x - node.position.x) }) {
                    targetIllegal = closest
                    state = .chase
                    if sound { SoundGenerator.shared.playBark() }
                }
            }
            
        case .sniff:
            // Pause and sniff (nose bob animation)
            sniffTimer += dt
            nose.position.y = 12 + CGFloat(sin(sniffTimer * 8)) * 1.5
            if sniffTimer > 2 { state = .wander; sniffTimer = 0 }
            
        case .chase:
            guard let target = targetIllegal else { state = .wander; return }
            let dx = target.node.position.x - node.position.x
            let dir: CGFloat = dx > 0 ? 1 : -1
            node.xScale = dir > 0 ? 1 : -1
            node.position.x += dir * 1.2 // Faster than Illegals
            
            // Make the Illegal flee
            if target.state != .flee && target.state != .sleep {
                target.startFlee(from: node.position.x, screenWidth: screenWidth)
            }
            
            chaseTimer += dt
            // Bark occasionally during chase
            if chaseTimer.truncatingRemainder(dividingBy: 3.0) < dt && sound {
                SoundGenerator.shared.playBark()
            }
            
            // Stop chasing after a while or if close enough and it ran away
            let dist = abs(dx)
            if chaseTimer > 8 || dist > 300 {
                targetIllegal = nil; state = .sniff; chaseTimer = 0; sniffTimer = 0
            }
            
        case .exit:
            break
        }
    }
}

// MARK: - Pet Scene

class PetScene: SKScene {
    var illegals: [Illegal] = []
    var densuke: Densuke!
    var soundEnabled: Bool = true
    
    var inactivityTimer: TimeInterval = 0
    var systemCheckTimer: TimeInterval = 0
    var windowScanTimer: TimeInterval = 0
    var densukeSpawnTimer: TimeInterval = 0
    var windowLedges: [WindowLedge] = []
    var lastMousePosition: CGPoint = .zero
    
    let groundY: CGFloat = 60
    let edgePanicZone: CGFloat = 80
    let sleepAfterSeconds: TimeInterval = 180
    
    override func didMove(to view: SKView) {
        backgroundColor = .clear
        
        // Main Illegal (leader)
        let leader = Illegal(scale: 1.0, groundY: groundY, isLeader: true)
        leader.node.position = CGPoint(x: size.width / 2, y: groundY)
        leader.lastX = leader.node.position.x
        addChild(leader.node)
        illegals.append(leader)
        
        // Two companion Illegals (smaller)
        for i in 0..<2 {
            let scale = CGFloat.random(in: 0.55...0.75)
            let companion = Illegal(scale: scale, groundY: groundY, isLeader: false)
            let offset = CGFloat(i == 0 ? -60 : 60) + CGFloat.random(in: -20...20)
            companion.node.position = CGPoint(x: size.width / 2 + offset, y: groundY)
            companion.lastX = companion.node.position.x
            companion.node.alpha = 0.85
            addChild(companion.node)
            illegals.append(companion)
        }
        
        // Schedule states
        for ill in illegals { ill.scheduleNext() }
        
        // Densuke (starts inactive)
        densuke = Densuke(maxLifetime: Double.random(in: 20...40))
        addChild(densuke.node)
        
        inactivityTimer = 0
        densukeSpawnTimer = 0
    }
    
    // MARK: - Update
    
    override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval = 1.0 / 60.0
        inactivityTimer += dt
        systemCheckTimer += dt
        windowScanTimer += dt
        densukeSpawnTimer += dt
        
        if systemCheckTimer > 30 {
            SystemMonitor.shared.update()
            systemCheckTimer = 0
        }
        if windowScanTimer > 10 {
            scanWindowLedges()
            windowScanTimer = 0
        }
        
        // Densuke spawn logic — appears every 60-120s for 20-40s
        if !densuke.isActive && densukeSpawnTimer > Double.random(in: 60...120) {
            let spawnX: CGFloat = Bool.random() ? -30 : size.width + 30
            densuke.maxLifetime = Double.random(in: 20...40) // Doesn't work since let, but timer handles it
            densuke.spawn(at: spawnX, groundY: groundY)
            densukeSpawnTimer = 0
        }
        
        // Update Densuke
        densuke.update(dt: dt, illegals: illegals, screenWidth: size.width, groundY: groundY, sound: soundEnabled)
        
        // Update each Illegal
        let leaderPos = illegals.first?.node.position ?? .zero
        
        for (index, ill) in illegals.enumerated() {
            ill.stateTimer += dt
            ill.glitchTimer += dt
            
            // Sleep check (only if leader triggers it)
            if ill.isLeader && ill.state != .sleep && ill.state != .wakeUp && inactivityTimer > sleepAfterSeconds {
                for i in illegals { i.enterSleep(sound: soundEnabled && i.isLeader) }
                return
            }
            
            if ill.state == .sleep {
                let bob = CGFloat(sin(currentTime * 0.8)) * 0.5
                ill.node.position.y = (ill.targetLedgeY ?? groundY) + bob
                continue
            }
            if ill.state == .wakeUp || ill.state == .windowHop { continue }
            
            // Flee behavior
            if ill.state == .flee {
                if let target = ill.fleeTarget {
                    let dir: CGFloat = target > ill.node.position.x ? 1 : -1
                    ill.node.position.x += dir * 1.8 // Fast flee
                    ill.node.xScale = dir > 0 ? 1 : -1
                    ill.trailEmitter?.particleBirthRate = 18
                    
                    if abs(ill.node.position.x - target) < 5 {
                        ill.state = .idle; ill.fleeTarget = nil; ill.scheduleNext()
                        ill.trailEmitter?.particleBirthRate = 0
                    }
                    // Shared glitch: nearby illegals glitch sympathetically
                    if ill.glitchTimer > 1 {
                        ill.triggerGlitch(withNoData: true, sound: soundEnabled && ill.isLeader)
                        ill.glitchTimer = 0
                    }
                } else {
                    ill.state = .idle; ill.scheduleNext()
                }
                let bob = CGFloat(sin(currentTime * 4)) * 2 // panicked bob
                ill.node.position.y = groundY + bob
                continue
            }
            
            // State transition
            if ill.stateTimer >= ill.nextStateChange {
                transitionState(for: ill, index: index)
            }
            
            // Edge glitch
            let leftDist = ill.node.position.x
            let rightDist = size.width - ill.node.position.x
            let edgeDist = min(leftDist, rightDist)
            
            if edgeDist < edgePanicZone {
                ill.edgeGlitchIntensity = 1.0 - (edgeDist / edgePanicZone)
                ill.scanLines.alpha = 0.25 + ill.edgeGlitchIntensity * 0.5
                if ill.glitchTimer > Double(2.0 - ill.edgeGlitchIntensity * 1.5) {
                    ill.triggerGlitch(withNoData: ill.edgeGlitchIntensity > 0.5, sound: soundEnabled && ill.isLeader)
                    ill.glitchTimer = 0
                    // Sympathetic glitch
                    if ill.isLeader {
                        for other in illegals where other !== ill {
                            if Bool.random() { other.triggerGlitch() }
                        }
                    }
                }
            } else {
                ill.edgeGlitchIntensity = 0
                ill.scanLines.alpha = 0.25
                if ill.glitchTimer > Double.random(in: 8...20) {
                    ill.triggerGlitch(withNoData: Bool.random() && Bool.random(), sound: soundEnabled && ill.isLeader)
                    ill.glitchTimer = 0
                }
            }
            
            // Trail
            let dx = abs(ill.node.position.x - ill.lastX)
            ill.isMoving = dx > 0.3
            ill.lastX = ill.node.position.x
            ill.trailEmitter?.particleBirthRate = ill.isMoving ? 12 : 0
            
            // Movement
            let baseY = ill.targetLedgeY ?? groundY
            let speed: CGFloat = ill.isLeader ? 0.5 : 0.4
            
            switch ill.state {
            case .wanderLeft:
                ill.node.position.x -= speed
                ill.node.xScale = -1
                if ill.node.position.x < 50 { ill.state = .wanderRight }
            case .wanderRight:
                ill.node.position.x += speed
                ill.node.xScale = 1
                if ill.node.position.x > size.width - 50 { ill.state = .wanderLeft }
            case .idle, .windowWalk:
                ill.node.position.x += CGFloat.random(in: -0.15...0.15)
                // Companions drift toward leader
                if !ill.isLeader {
                    let toLeader = leaderPos.x - ill.node.position.x
                    let flockPull: CGFloat = 0.02
                    ill.node.position.x += toLeader * flockPull
                    // Also maintain spacing
                    for other in illegals where other !== ill {
                        let sep = ill.node.position.x - other.node.position.x
                        if abs(sep) < 25 {
                            ill.node.position.x += (sep > 0 ? 0.1 : -0.1)
                        }
                    }
                }
            default: break
            }
            
            // Bob
            let bobSpeed: CGFloat = ill.isLeader ? 2.0 : 2.0 + CGFloat(index) * 0.3
            let bob = CGFloat(sin(currentTime * bobSpeed)) * 1.5
            ill.node.position.y = baseY + bob
            
            // Scan line scroll
            ill.scanLines.position.y = 16 + CGFloat(sin(currentTime * 3.0)) * 0.5
        }
    }
    
    func transitionState(for ill: Illegal, index: Int) {
        let roll = Double.random(in: 0...1)
        
        if ill.isLeader {
            let onGround = ill.currentLedge == nil
            if onGround {
                switch roll {
                case 0..<0.25: ill.state = .idle
                case 0.25..<0.45: ill.state = .wanderLeft
                case 0.45..<0.65: ill.state = .wanderRight
                case 0.65..<0.8:
                    if !windowLedges.isEmpty { tryWindowHop(for: ill); return }
                    ill.state = .idle
                default: ill.state = .idle
                }
            } else {
                switch roll {
                case 0..<0.3: ill.state = .windowWalk
                case 0.3..<0.5: ill.state = .wanderLeft
                case 0.5..<0.7: ill.state = .wanderRight
                case 0.7..<0.85: returnToGround(for: ill); return
                default: ill.state = .windowWalk
                }
            }
        } else {
            // Companions mostly follow leader
            switch roll {
            case 0..<0.4: ill.state = .idle
            case 0.4..<0.6: ill.state = .wanderLeft
            case 0.6..<0.8: ill.state = .wanderRight
            default: ill.state = .idle
            }
        }
        ill.scheduleNext()
    }
    
    // MARK: - Window Walking
    
    func scanWindowLedges() {
        windowLedges.removeAll()
        guard let screen = NSScreen.main else { return }
        let screenH = screen.frame.height
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in windowList {
            guard let bounds = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = w[kCGWindowLayer as String] as? Int,
                  let owner = w[kCGWindowOwnerName as String] as? String else { continue }
            guard layer == 0 else { continue }
            if owner == "denno-pet" || owner == "Dock" || owner == "Window Server" { continue }
            let x = bounds["X"] ?? 0; let y = bounds["Y"] ?? 0
            let width = bounds["Width"] ?? 0; let height = bounds["Height"] ?? 0
            guard width > 100 && height > 50 else { continue }
            windowLedges.append(WindowLedge(x: x, y: screenH - y, width: width, windowName: owner))
        }
        windowLedges.sort { $0.y > $1.y }
    }
    
    func tryWindowHop(for ill: Illegal) {
        guard !windowLedges.isEmpty else { return }
        let ledge = windowLedges.randomElement()!
        ill.currentLedge = ledge
        ill.state = .windowHop
        let targetX = ledge.x + CGFloat.random(in: 20...max(ledge.width - 20, 30))
        let targetY = ledge.y
        if soundEnabled { SoundGenerator.shared.playChirp(frequency: 1400, duration: 0.04) }
        let midY = max(ill.node.position.y, targetY) + 40
        let jumpUp = SKAction.moveTo(y: midY, duration: 0.2); jumpUp.timingMode = .easeOut
        let moveOver = SKAction.moveTo(x: targetX, duration: 0.25); moveOver.timingMode = .easeInEaseOut
        let land = SKAction.moveTo(y: targetY, duration: 0.15); land.timingMode = .easeIn
        ill.node.run(SKAction.sequence([
            SKAction.group([jumpUp, moveOver]), land,
            SKAction.run { ill.state = .windowWalk; ill.targetLedgeY = targetY; ill.scheduleNext() }
        ]))
    }
    
    func returnToGround(for ill: Illegal) {
        ill.currentLedge = nil; ill.targetLedgeY = nil
        if soundEnabled { SoundGenerator.shared.playChirp(frequency: 600, duration: 0.05) }
        let fall = SKAction.moveTo(y: groundY, duration: 0.3); fall.timingMode = .easeIn
        ill.node.run(SKAction.sequence([fall, SKAction.run { ill.state = .idle; ill.scheduleNext() }]))
    }
    
    // MARK: - Mouse
    
    func handleGlobalMouse(at location: CGPoint) {
        inactivityTimer = 0
        
        let mouseDelta = sqrt(pow(location.x - lastMousePosition.x, 2) + pow(location.y - lastMousePosition.y, 2))
        lastMousePosition = location
        
        for ill in illegals {
            if ill.state == .sleep { ill.wakeUp(sound: soundEnabled && ill.isLeader); continue }
            
            let dx = location.x - ill.node.position.x
            let dy = location.y - ill.node.position.y
            let dist = sqrt(dx * dx + dy * dy)
            
            if dist < 200 && dist > 0 {
                let eyeOff = min(dx / dist * 2, 2)
                ill.leftEye.position.x = -7 + eyeOff
                ill.rightEye.position.x = 7 + eyeOff
                
                if mouseDelta > 50 && dist < 100 && ill.state != .flee {
                    triggerStartle(for: ill, awayFrom: location)
                }
            } else {
                ill.leftEye.position.x = -7
                ill.rightEye.position.x = 7
            }
        }
    }
    
    func handleGlobalClick(at location: CGPoint) {
        inactivityTimer = 0
        
        for ill in illegals {
            if ill.state == .sleep { ill.wakeUp(sound: soundEnabled && ill.isLeader); continue }
            let dx = location.x - ill.node.position.x
            let dy = location.y - ill.node.position.y
            if sqrt(dx * dx + dy * dy) < 40 * ill.scale {
                if soundEnabled { SoundGenerator.shared.playHappyChirp() }
                ill.node.run(SKAction.sequence([
                    SKAction.scale(to: ill.scale * 1.15, duration: 0.1),
                    SKAction.scale(to: ill.scale, duration: 0.2)
                ]))
                ill.leftEye.run(SKAction.sequence([SKAction.scaleY(to: 0.5, duration: 0.1), SKAction.scaleY(to: 1.0, duration: 0.3)]))
                ill.rightEye.run(SKAction.sequence([SKAction.scaleY(to: 0.5, duration: 0.1), SKAction.scaleY(to: 1.0, duration: 0.3)]))
                break
            }
        }
    }
    
    func triggerStartle(for ill: Illegal, awayFrom point: CGPoint) {
        let jumpDir: CGFloat = point.x > ill.node.position.x ? -1 : 1
        let baseY = ill.targetLedgeY ?? groundY
        ill.node.run(SKAction.sequence([
            SKAction.moveBy(x: jumpDir * 30, y: 20, duration: 0.15),
            SKAction.moveTo(y: baseY, duration: 0.2)
        ]))
        ill.triggerGlitch(withNoData: true, sound: soundEnabled && ill.isLeader)
        // Sympathetic startle
        for other in illegals where other !== ill {
            if abs(other.node.position.x - ill.node.position.x) < 100 {
                other.triggerGlitch()
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: PetWindow!
    var statusItem: NSStatusItem!
    var scene: PetScene!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
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
        
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self = self else { return }
            let sp = NSEvent.mouseLocation
            let wp = self.window.convertPoint(fromScreen: sp)
            self.scene.handleGlobalMouse(at: skView.convert(wp, to: self.scene))
        }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self = self else { return }
            let sp = NSEvent.mouseLocation
            let wp = self.window.convertPoint(fromScreen: sp)
            self.scene.handleGlobalClick(at: skView.convert(wp, to: self.scene))
        }
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "👾"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Dennō Pet", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let soundItem = NSMenuItem(title: "Sound Effects", action: #selector(toggleSound(_:)), keyEquivalent: "s")
        soundItem.target = self; soundItem.state = .on
        menu.addItem(soundItem)
        menu.addItem(.separator())
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
