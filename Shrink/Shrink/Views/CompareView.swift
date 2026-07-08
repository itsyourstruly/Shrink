//
//  CompareView.swift
//  Shrink
//

import SwiftUI
import AVFoundation
import AppKit
import AVKit
import Combine

struct CompareView: View {
    let originalURL: URL
    let compressedURL: URL
    let fileType: FileType
    
    @State private var sliderOffset: CGFloat = 0.5
    @State private var scale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var hoverLocation: CGPoint? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack {
                    if fileType == .image {
                        ImageCompareView(
                            originalURL: originalURL,
                            compressedURL: compressedURL,
                            sliderOffset: $sliderOffset,
                            scale: $scale,
                            panOffset: $panOffset,
                            hoverLocation: $hoverLocation,
                            size: geo.size
                        )
                    } else if fileType == .video {
                        VideoCompareView(
                            originalURL: originalURL,
                            compressedURL: compressedURL,
                            sliderOffset: $sliderOffset,
                            scale: $scale,
                            panOffset: $panOffset,
                            hoverLocation: $hoverLocation,
                            size: geo.size
                        )
                    } else {
                        Text("Preview not supported for this file type.")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .background(Color.black.opacity(0.95))
            
            // Bottom bar with close button
            HStack {
                Text("Original (Left) vs Compressed (Right)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                if scale > 1.0 {
                    Text("• Zoom: \(Int(scale * 100))%")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                    
                    Button("Reset Zoom") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            scale = 1.0
                            panOffset = .zero
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.blue, lineWidth: 1)
                    )
                }
                
                Spacer()
                
                Button("Close") {
                    for window in NSApp.windows {
                        if window.title.hasPrefix("Compare: ") && window.isKeyWindow {
                            window.close()
                            return
                        }
                    }
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
        .frame(minWidth: 800, minHeight: 550)
    }
}

struct ImageCompareView: View {
    let originalURL: URL
    let compressedURL: URL
    @Binding var sliderOffset: CGFloat
    @Binding var scale: CGFloat
    @Binding var panOffset: CGSize
    @Binding var hoverLocation: CGPoint?
    let size: CGSize
    
    @State private var originalImage: NSImage?
    @State private var compressedImage: NSImage?
    
    var body: some View {
        ZStack {
            if let orig = originalImage, let comp = compressedImage {
                // Compressed image on bottom
                Image(nsImage: comp)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(scale)
                    .offset(panOffset)
                
                // Original image on top, masked
                Image(nsImage: orig)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(scale)
                    .offset(panOffset)
                    .mask(
                        GeometryReader { maskGeo in
                            Rectangle()
                                .frame(width: maskGeo.size.width * sliderOffset, height: maskGeo.size.height)
                        }
                    )
                
                // Zoom & Pan Interceptor
                ZoomGestureView(
                    scale: $scale,
                    panOffset: $panOffset,
                    size: size,
                    hoverLocation: $hoverLocation,
                    sliderOffset: $sliderOffset
                )
                
                // Hairpin slider line
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1.5)
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
                    .offset(x: -size.width/2 + size.width * sliderOffset)
                    .allowsHitTesting(false)
                
                // Slider handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                    .overlay(
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.blue)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.blue)
                        }
                    )
                    .offset(x: -size.width/2 + size.width * sliderOffset)
                    .gesture(
                        DragGesture(coordinateSpace: .named("compareImageSpace"))
                            .onChanged { value in
                                let newOffset = value.location.x / size.width
                                sliderOffset = max(0.0, min(1.0, newOffset))
                            }
                    )
            } else {
                ProgressView("Loading Images...")
                    .onAppear {
                        loadImages()
                    }
            }
        }
        .coordinateSpace(name: "compareImageSpace")
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverLocation = location
            case .ended:
                break
            }
        }
    }
    
    private func loadImages() {
        let isAccessingOrig = originalURL.startAccessingSecurityScopedResource()
        let isAccessingComp = compressedURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingOrig { originalURL.stopAccessingSecurityScopedResource() }
            if isAccessingComp { compressedURL.stopAccessingSecurityScopedResource() }
        }
        
        if let origData = try? Data(contentsOf: originalURL),
           let compData = try? Data(contentsOf: compressedURL) {
            originalImage = NSImage(data: origData)
            compressedImage = NSImage(data: compData)
        }
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

@MainActor
class VideoSyncManager: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    
    var originalPlayer: AVPlayer?
    var compressedPlayer: AVPlayer?
    
    private var timeObserverToken: Any?
    private var durationObservation: NSKeyValueObservation?
    private var isScrubbing = false
    private let originalURL: URL
    private let compressedURL: URL
    
    init(originalURL: URL, compressedURL: URL) {
        self.originalURL = originalURL
        self.compressedURL = compressedURL
    }
    
    func setup() {
        _ = originalURL.startAccessingSecurityScopedResource()
        _ = compressedURL.startAccessingSecurityScopedResource()
        
        let origAsset = AVURLAsset(url: originalURL)
        let compAsset = AVURLAsset(url: compressedURL)
        
        let origItem = AVPlayerItem(asset: origAsset)
        let compItem = AVPlayerItem(asset: compAsset)
        
        let origPlayer = AVPlayer(playerItem: origItem)
        let compPlayer = AVPlayer(playerItem: compItem)
        
        origPlayer.isMuted = false
        compPlayer.isMuted = true
        
        self.originalPlayer = origPlayer
        self.compressedPlayer = compPlayer
        
        // Loop synchronization
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: origItem,
            queue: .main
        ) { [weak origPlayer, weak compPlayer] _ in
            origPlayer?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            compPlayer?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            origPlayer?.play()
            compPlayer?.play()
        }
        
        // Duration observer
        durationObservation = origItem.observe(\.duration, options: [.new, .initial]) { [weak self] item, _ in
            let secs = item.duration.seconds
            if secs.isFinite && secs > 0 {
                DispatchQueue.main.async {
                    self?.duration = secs
                }
            }
        }
        
        // Time observer
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserverToken = origPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak origPlayer, weak compPlayer] time in
            Task { @MainActor [weak self, weak origPlayer, weak compPlayer] in
                self?.handleTimeUpdate(time: time, origPlayer: origPlayer, compPlayer: compPlayer)
            }
        }
    }
    
    @MainActor
    private func handleTimeUpdate(time: CMTime, origPlayer: AVPlayer?, compPlayer: AVPlayer?) {
        guard !isScrubbing else { return }
        let currentSecs = time.seconds
        currentTime = currentSecs
        
        // Sync compressed player to original player if out of sync
        if let orig = origPlayer, let comp = compPlayer {
            let diff = abs(orig.currentTime().seconds - comp.currentTime().seconds)
            if diff > 0.05 {
                comp.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
    }
    
    func togglePlay() {
        guard let orig = originalPlayer, let comp = compressedPlayer else { return }
        if isPlaying {
            orig.pause()
            comp.pause()
            isPlaying = false
        } else {
            let time = orig.currentTime()
            comp.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak orig, weak comp, weak self] _ in
                orig?.play()
                comp?.play()
                DispatchQueue.main.async {
                    self?.isPlaying = true
                }
            }
        }
    }
    
    func startScrubbing() {
        isScrubbing = true
    }
    
    func stopScrubbing() {
        isScrubbing = false
        syncPlayers()
    }
    
    func seek(to seconds: Double) {
        currentTime = seconds
        guard let orig = originalPlayer, let comp = compressedPlayer else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        orig.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        comp.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    private func syncPlayers() {
        guard let orig = originalPlayer, let comp = compressedPlayer else { return }
        let time = orig.currentTime()
        comp.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func cleanup() {
        if let token = timeObserverToken {
            originalPlayer?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        durationObservation?.invalidate()
        durationObservation = nil
        
        originalPlayer?.pause()
        compressedPlayer?.pause()
        originalURL.stopAccessingSecurityScopedResource()
        compressedURL.stopAccessingSecurityScopedResource()
    }
}

struct VideoCompareView: View {
    let originalURL: URL
    let compressedURL: URL
    @Binding var sliderOffset: CGFloat
    @Binding var scale: CGFloat
    @Binding var panOffset: CGSize
    @Binding var hoverLocation: CGPoint?
    let size: CGSize
    
    @StateObject private var syncManager: VideoSyncManager
    
    init(originalURL: URL, compressedURL: URL, sliderOffset: Binding<CGFloat>, scale: Binding<CGFloat>, panOffset: Binding<CGSize>, hoverLocation: Binding<CGPoint?>, size: CGSize) {
        self.originalURL = originalURL
        self.compressedURL = compressedURL
        self._sliderOffset = sliderOffset
        self._scale = scale
        self._panOffset = panOffset
        self._hoverLocation = hoverLocation
        self.size = size
        self._syncManager = StateObject(wrappedValue: VideoSyncManager(originalURL: originalURL, compressedURL: compressedURL))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let orig = syncManager.originalPlayer, let comp = syncManager.compressedPlayer {
                    // Compressed video
                    PlayerView(player: comp)
                        .frame(width: size.width, height: size.height - 72)
                        .scaleEffect(scale)
                        .offset(panOffset)
                    
                    // Original video masked
                    PlayerView(player: orig)
                        .frame(width: size.width, height: size.height - 72)
                        .scaleEffect(scale)
                        .offset(panOffset)
                        .mask(
                            GeometryReader { maskGeo in
                                Rectangle()
                                    .frame(width: maskGeo.size.width * sliderOffset, height: maskGeo.size.height)
                            }
                        )
                    
                    // Zoom & Pan Interceptor
                    ZoomGestureView(
                        scale: $scale,
                        panOffset: $panOffset,
                        size: CGSize(width: size.width, height: size.height - 72),
                        hoverLocation: $hoverLocation,
                        sliderOffset: $sliderOffset
                    )
                    
                    // Hairpin slider line
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 1.5)
                        .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
                        .offset(x: -size.width/2 + size.width * sliderOffset)
                        .padding(.bottom, 72)
                        .allowsHitTesting(false)
                    
                    // Slider handle
                    Circle()
                        .fill(Color.white)
                        .frame(width: 32, height: 32)
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                        .overlay(
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.blue)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.blue)
                            }
                        )
                        .offset(x: -size.width/2 + size.width * sliderOffset)
                        .padding(.bottom, 72)
                        .gesture(
                            DragGesture(coordinateSpace: .named("compareVideoSpace"))
                                .onChanged { value in
                                    let newOffset = value.location.x / size.width
                                    sliderOffset = max(0.0, min(1.0, newOffset))
                                }
                        )
                } else {
                    ProgressView("Loading Videos...")
                }
            }
            .coordinateSpace(name: "compareVideoSpace")
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                case .ended:
                    break
                }
            }
            
            // Video Scrubber & Playback Controls
            if syncManager.originalPlayer != nil && syncManager.compressedPlayer != nil {
                VStack(spacing: 4) {
                    // Timeline Slider
                    HStack(spacing: 12) {
                        Text(formatTime(syncManager.currentTime))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Slider(value: Binding(
                            get: { syncManager.currentTime },
                            set: { newValue in
                                syncManager.seek(to: newValue)
                            }
                        ), in: 0...max(0.1, syncManager.duration), onEditingChanged: { editing in
                            if editing {
                                syncManager.startScrubbing()
                            } else {
                                syncManager.stopScrubbing()
                            }
                        })
                        .accentColor(.blue)
                        
                        Text(formatTime(syncManager.duration))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    HStack(spacing: 16) {
                        Button(action: {
                            syncManager.togglePlay()
                        }) {
                            Image(systemName: syncManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.blue))
                        }
                        .buttonStyle(.plain)
                        
                        Text(syncManager.isPlaying ? "Playing synchronized" : "Paused")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
                .frame(height: 72)
                .background(Color.black.opacity(0.4))
            }
        }
        .onAppear {
            syncManager.setup()
        }
        .onDisappear {
            syncManager.cleanup()
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && seconds.isFinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct ZoomGestureView: NSViewRepresentable {
    @Binding var scale: CGFloat
    @Binding var panOffset: CGSize
    var size: CGSize
    @Binding var hoverLocation: CGPoint?
    @Binding var sliderOffset: CGFloat
    
    func makeNSView(context: Context) -> ScrollInterceptView {
        let view = ScrollInterceptView(parent: self)
        view.frame = NSRect(origin: .zero, size: size)
        view.autoresizingMask = [.width, .height]
        return view
    }
    
    func updateNSView(_ nsView: ScrollInterceptView, context: Context) {
        nsView.parent = self
    }
}

class ScrollInterceptView: NSView {
    var parent: ZoomGestureView
    private var lastDragLocation: NSPoint?
    private var trackingArea: NSTrackingArea?
    
    init(parent: ZoomGestureView) {
        self.parent = parent
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func updateTrackingAreas() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited]
        let newArea = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        trackingArea = newArea
    }
    
    override func scrollWheel(with event: NSEvent) {
        let deltaY = event.scrollingDeltaY
        
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            // Zoom logic
            guard deltaY != 0 else { return }
            
            let zoomFactor: CGFloat = 1.05
            let oldScale = parent.scale
            var newScale = oldScale
            
            if deltaY > 0 {
                newScale = min(10.0, oldScale * zoomFactor)
            } else {
                newScale = max(1.0, oldScale / zoomFactor)
            }
            
            if newScale != oldScale {
                let hover = parent.hoverLocation ?? CGPoint(x: parent.size.width / 2, y: parent.size.height / 2)
                let center = CGPoint(x: parent.size.width / 2, y: parent.size.height / 2)
                
                let pX = hover.x
                let pY = hover.y
                let cX = center.x
                let cY = center.y
                let o1X = parent.panOffset.width
                let o1Y = parent.panOffset.height
                
                let o2X = (pX - cX) - (pX - cX - o1X) * (newScale / oldScale)
                let o2Y = (pY - cY) - (pY - cY - o1Y) * (newScale / oldScale)
                
                let maxOffset = parent.size.width * (newScale - 1) / 2
                let maxOffsetY = parent.size.height * (newScale - 1) / 2
                
                parent.scale = newScale
                parent.panOffset = CGSize(
                    width: max(-maxOffset, min(maxOffset, o2X)),
                    height: max(-maxOffsetY, min(maxOffsetY, o2Y))
                )
            }
        } else {
            // Pan logic
            if parent.scale > 1.0 {
                let dx = event.scrollingDeltaX
                let dy = -event.scrollingDeltaY
                
                let newOffsetX = parent.panOffset.width + dx
                let newOffsetY = parent.panOffset.height + dy
                
                let maxOffset = parent.size.width * (parent.scale - 1) / 2
                let maxOffsetY = parent.size.height * (parent.scale - 1) / 2
                
                parent.panOffset = CGSize(
                    width: max(-maxOffset, min(maxOffset, newOffsetX)),
                    height: max(-maxOffsetY, min(maxOffsetY, newOffsetY))
                )
            } else {
                super.scrollWheel(with: event)
            }
        }
    }
    
    override func magnify(with event: NSEvent) {
        let delta = event.magnification
        let oldScale = parent.scale
        let newScale = max(1.0, min(10.0, oldScale * (1.0 + delta)))
        
        if newScale != oldScale {
            let hover = parent.hoverLocation ?? CGPoint(x: parent.size.width / 2, y: parent.size.height / 2)
            let center = CGPoint(x: parent.size.width / 2, y: parent.size.height / 2)
            
            let pX = hover.x
            let pY = hover.y
            let cX = center.x
            let cY = center.y
            let o1X = parent.panOffset.width
            let o1Y = parent.panOffset.height
            
            let o2X = (pX - cX) - (pX - cX - o1X) * (newScale / oldScale)
            let o2Y = (pY - cY) - (pY - cY - o1Y) * (newScale / oldScale)
            
            let maxOffset = parent.size.width * (newScale - 1) / 2
            let maxOffsetY = parent.size.height * (newScale - 1) / 2
            
            parent.scale = newScale
            parent.panOffset = CGSize(
                width: max(-maxOffset, min(maxOffset, o2X)),
                height: max(-maxOffsetY, min(maxOffsetY, o2Y))
            )
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if parent.scale > 1.0 {
            lastDragLocation = event.locationInWindow
            NSCursor.closedHand.set()
        } else {
            super.mouseDown(with: event)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        if let lastLoc = lastDragLocation, parent.scale > 1.0 {
            let currentLoc = event.locationInWindow
            let dx = currentLoc.x - lastLoc.x
            let dy = currentLoc.y - lastLoc.y
            
            let newOffsetX = parent.panOffset.width + dx
            let newOffsetY = parent.panOffset.height + dy
            
            let maxOffset = parent.size.width * (parent.scale - 1) / 2
            let maxOffsetY = parent.size.height * (parent.scale - 1) / 2
            
            parent.panOffset = CGSize(
                width: max(-maxOffset, min(maxOffset, newOffsetX)),
                height: max(-maxOffsetY, min(maxOffsetY, newOffsetY))
            )
            
            lastDragLocation = currentLoc
            NSCursor.closedHand.set()
        } else {
            super.mouseDragged(with: event)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if lastDragLocation != nil {
            lastDragLocation = nil
            updateCursor(with: event)
        } else {
            super.mouseUp(with: event)
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        updateCursor(with: event)
    }
    
    override func mouseEntered(with event: NSEvent) {
        updateCursor(with: event)
    }
    
    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }
    
    private func updateCursor(with event: NSEvent) {
        if parent.scale > 1.0 {
            let clickX = self.convert(event.locationInWindow, from: nil).x
            let sliderX = parent.size.width * parent.sliderOffset
            if abs(clickX - sliderX) > 20 {
                if lastDragLocation != nil {
                    NSCursor.closedHand.set()
                } else {
                    NSCursor.openHand.set()
                }
            } else {
                NSCursor.resizeLeftRight.set()
            }
        } else {
            let clickX = self.convert(event.locationInWindow, from: nil).x
            let sliderX = parent.size.width * parent.sliderOffset
            if abs(clickX - sliderX) <= 20 {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}
