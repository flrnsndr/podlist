import PodlistKit
import SwiftUI
import UIKit

/// The player's progress bar with chapters as segments (concept §4.6, `ChapterProgress`): the
/// played part in the accent color, the current chapter taller. A horizontal drag anywhere on
/// it scrubs (`scrubPosition` follows the finger, a tick when it crosses into another chapter)
/// and seeks on release; a vertical drag still moves the sheet. VoiceOver adjusts it by the
/// skip intervals.
struct ChapterProgressBar: View {
    let progress: ChapterProgress
    /// The scrub position while dragging, else the player's time.
    let position: TimeInterval
    @Binding var scrubPosition: TimeInterval?
    let seek: (TimeInterval) -> Void
    let skipForward: () -> Void
    let skipBackward: () -> Void
    @State private var width: CGFloat = 0

    private static let gap = 2.0
    private static let height: CGFloat = 4
    private static let currentHeight: CGFloat = 8
    /// Tall enough to hit with a finger.
    private static let touchHeight: CGFloat = 32

    var body: some View {
        let current = progress.index(at: position)
        let frames = progress.frames(width: width, gap: Self.gap)
        ZStack(alignment: .leading) {
            ForEach(Array(zip(progress.segments.indices, frames)), id: \.0) { index, frame in
                segment(played: progress.played(index, at: position), width: frame.width)
                    .frame(width: frame.width, height: index == current ? Self.currentHeight : Self.height)
                    .offset(x: frame.x)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.touchHeight, alignment: .leading)
        .contentShape(.rect)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .animation(.snappy, value: current)
        .gesture(HorizontalPan { x in
            scrubPosition = progress.time(atX: x, width: width, gap: Self.gap)
        } ended: { commit in
            if commit, let scrubPosition { seek(scrubPosition) }
            scrubPosition = nil
        })
        .sensoryFeedback(.selection, trigger: current) { _, _ in scrubPosition != nil }
        .accessibilityElement()
        .accessibilityLabel(Text("Position"))
        .accessibilityValue(Text(position.clockText))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: skipForward()
            case .decrement: skipBackward()
            @unknown default: break
            }
        }
        .accessibilityIdentifier("progressBar")
    }

    private func segment(played: Double, width: CGFloat) -> some View {
        Capsule()
            .fill(.tertiary)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.tint)
                    .frame(width: width * played)
            }
            .clipShape(.capsule)
    }
}

/// A pan that only begins when it starts sideways, so a vertical drag on the bar still goes to
/// the scroll view (the sheet's snap between player and notes, N80), which waits for it to fail.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let changed: (CGFloat) -> Void
    /// true when the finger lifted, false when the system cancelled the pan.
    let ended: (Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed: changed(context.converter.localLocation.x)
        case .ended: ended(true)
        case .cancelled, .failed: ended(false)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            other.view is UIScrollView
        }
    }
}
