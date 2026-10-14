import PodlistKit
import SwiftUI

/// A selectable capsule with a playlist's symbol and name (filter bar, assignment sheet, details).
struct PlaylistChip: View {
    let title: String
    var symbolName: String?
    var color: Color = .accentColor
    /// A hidden playlist (N65): an extra symbol, so it is not only the place at the end.
    var isHidden = false
    let isSelected: Bool
    let action: () -> Void

    init(playlist: Playlist, isSelected: Bool, action: @escaping () -> Void) {
        self.title = playlist.displayName
        self.symbolName = playlist.symbolName
        self.color = playlist.color
        self.isHidden = playlist.isHidden
        self.isSelected = isSelected
        self.action = action
    }

    init(title: String, symbolName: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.symbolName = symbolName
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            PlaylistPill(title: title, symbolName: symbolName, color: color, isHidden: isHidden,
                         isSelected: isSelected, size: .regular)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isHidden ? Text("playlist.hidden") : Text(verbatim: ""))
    }
}

/// A playlist as a small pill in episode rows (inbox, Up Next, former queues): the look of
/// an unselected chip, not tappable.
struct PlaylistTag: View {
    let playlist: Playlist

    var body: some View {
        PlaylistPill(title: playlist.displayName, symbolName: playlist.symbolName, color: playlist.color,
                     isHidden: playlist.isHidden, isSelected: false, size: .small)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(playlist.displayName))
            .accessibilityValue(playlist.isHidden ? Text("playlist.hidden") : Text(verbatim: ""))
    }
}

/// The capsule behind chips and tags.
private struct PlaylistPill: View {
    enum Size { case regular, small }

    let title: String
    let symbolName: String?
    let color: Color
    let isHidden: Bool
    let isSelected: Bool
    let size: Size

    var body: some View {
        HStack(spacing: size == .regular ? 6 : 3) {
            if let symbolName {
                Image(systemName: symbolName).accessibilityHidden(true)
            }
            Text(title).lineLimit(1)
            if isHidden {
                Image(systemName: "eye.slash").font(size == .regular ? .caption : .caption2).accessibilityHidden(true)
            }
            if isSelected {
                Image(systemName: "checkmark").font(.caption.bold()).accessibilityHidden(true)
            }
        }
        .font(size == .regular ? .subheadline : .caption)
        .padding(.horizontal, size == .regular ? 12 : 7)
        .padding(.vertical, size == .regular ? 7 : 2)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(color))
        .background(isSelected ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.15)), in: .capsule)
    }
}

/// Lays out views in rows that wrap, like words in a paragraph.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty, row.width + spacing + size.width > maxWidth {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
