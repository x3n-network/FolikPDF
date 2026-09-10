import Foundation
import CoreGraphics

nonisolated enum FormLayoutAction: String, CaseIterable, Identifiable {
    case left, right, top, bottom, width, height, size, horizontalSpacing, verticalSpacing
    var id: Self { self }
    var title: String {
        switch self {
        case .left: "Align left"
        case .right: "Align right"
        case .top: "Align top"
        case .bottom: "Align bottom"
        case .width: "Match width"
        case .height: "Match height"
        case .size: "Match size"
        case .horizontalSpacing: "Space evenly across"
        case .verticalSpacing: "Space evenly down"
        }
    }
    var minimumCount: Int { self == .horizontalSpacing || self == .verticalSpacing ? 3 : 2 }

    func arrange(_ bounds: [CGRect]) -> [CGRect]? {
        guard bounds.count >= minimumCount, let reference = bounds.first else { return nil }
        if self == .horizontalSpacing || self == .verticalSpacing {
            let horizontal = self == .horizontalSpacing
            let sorted = bounds.indices.sorted { horizontal ? bounds[$0].minX < bounds[$1].minX : bounds[$0].minY < bounds[$1].minY }
            let first = bounds[sorted[0]], last = bounds[sorted[sorted.count - 1]]
            let start = horizontal ? first.minX : first.minY
            let end = horizontal ? last.maxX : last.maxY
            let total = bounds.reduce(CGFloat.zero) { $0 + (horizontal ? $1.width : $1.height) }
            let gap = (end - start - total) / CGFloat(bounds.count - 1)
            guard gap >= 0 else { return nil }
            var result = bounds
            var position = start
            for index in sorted {
                if horizontal { result[index].origin.x = position } else { result[index].origin.y = position }
                position += (horizontal ? bounds[index].width : bounds[index].height) + gap
            }
            return result
        }
        return bounds.map { old in
            var next = old
            switch self {
            case .left: next.origin.x = reference.minX
            case .right: next.origin.x = reference.maxX - old.width
            case .top: next.origin.y = reference.maxY - old.height
            case .bottom: next.origin.y = reference.minY
            case .width: next.size.width = reference.width
            case .height: next.size.height = reference.height; next.origin.y = old.maxY - reference.height
            case .size: next.size = reference.size; next.origin.y = old.maxY - reference.height
            default: break
            }
            return next
        }
    }
}
