import SwiftUI

/// A direct-position seek bar: both a click and a drag map to absolute time.
/// Playback is changed on release; the time readouts preview the target meanwhile.
struct SeekBar: View {
    @AppStorage("seekStepSeconds") private var seekStepSeconds = 5
    @AppStorage("appLanguage") private var appLanguage = "system"
    @Environment(\.controlActiveState) private var controlActiveState
    let value: Double
    let duration: Double
    let isEnabled: Bool
    let onPreview: (Double?) -> Void
    let onSeek: (Double) -> Void
    let onEditingChanged: (Bool) -> Void
    @State private var preview: Double?
    @State private var feedback: Double?
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let x = SeekBarGeometry.position(for: preview ?? value, duration: duration, width: width)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.18))
                    .frame(height: 4).padding(.horizontal, SeekBarGeometry.inset)
                Capsule().fill(controlActiveState == .key ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
                    .frame(width: max(0, x - SeekBarGeometry.inset), height: 4)
                    .offset(x: SeekBarGeometry.inset)
                Circle().fill(Color(nsColor: .controlColor))
                    .overlay { Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .frame(width: 16, height: 16).offset(x: x - 8)
            }
            .frame(width: width, height: 28)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { event in
                    guard isEnabled else { return }
                    feedbackTask?.cancel()
                    if preview == nil { onEditingChanged(true) }
                    let target = SeekBarGeometry.time(at: event.location.x, duration: duration, width: width)
                    preview = target
                    feedback = target
                    onPreview(target)
                }
                .onEnded { event in
                    guard isEnabled else { return }
                    let target = SeekBarGeometry.time(at: event.location.x, duration: duration, width: width)
                    onSeek(target)
                    preview = nil
                    onPreview(nil)
                    onEditingChanged(false)
                    feedback = target
                    feedbackTask?.cancel()
                    feedbackTask = Task { @MainActor in
                        do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                        feedback = nil
                    }
                })
            .overlay(alignment: .topLeading) {
                if let time = preview ?? feedback {
                    let bubbleWidth: CGFloat = duration >= 3600 ? 82 : 62
                    let targetX = SeekBarGeometry.position(for: time, duration: duration, width: width)
                    Text(PlayerModel.time(time))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: bubbleWidth, height: 24)
                        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 6))
                        .offset(x: min(max(targetX - bubbleWidth / 2, 0), max(0, width - bubbleWidth)), y: -26)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(minWidth: 62, minHeight: 28, maxHeight: 28)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(.easeOut(duration: 0.15), value: controlActiveState)
        .allowsHitTesting(isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("播放进度"))
        .accessibilityValue("\(PlayerModel.time(preview ?? value)) / \(PlayerModel.time(duration))")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: onSeek(min(value + Double((1...60).contains(seekStepSeconds) ? seekStepSeconds : 5), duration))
            case .decrement: onSeek(max(value - Double((1...60).contains(seekStepSeconds) ? seekStepSeconds : 5), 0))
            @unknown default: break
            }
        }
        .onChange(of: isEnabled) { _, enabled in if !enabled { reset() } }
        // The owner resets interaction state when closing/changing fullscreen.
        // Destruction must not write bindings back into the disappearing graph.
        .onDisappear { feedbackTask?.cancel() }
    }

    private func reset() {
        feedbackTask?.cancel()
        feedbackTask = nil
        feedback = nil
        if preview != nil {
            preview = nil
            onPreview(nil)
            onEditingChanged(false)
        }
    }
}

/// Shared mapping keeps clicks and thumb dragging aligned, including at the ends.
enum SeekBarGeometry {
    static let inset: CGFloat = 8

    static func time(at x: CGFloat, duration: Double, width: CGFloat) -> Double {
        guard duration.isFinite, duration > 0, width > inset * 2, x.isFinite else { return 0 }
        return Double(min(max((x - inset) / (width - inset * 2), 0), 1)) * duration
    }

    static func position(for time: Double, duration: Double, width: CGFloat) -> CGFloat {
        guard duration.isFinite, duration > 0, time.isFinite else { return inset }
        return inset + CGFloat(min(max(time / duration, 0), 1)) * max(0, width - inset * 2)
    }
}
