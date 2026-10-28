import Foundation

/// A drag needs both movement and a new drag pasteboard. Holding Shift during a
/// normal click must never re-open the wheel for an earlier file selection.
struct DragGestureGate {
    private var idlePasteboardCount: Int
    private var pressOrigin: CGPoint?

    init(pasteboardCount: Int) { idlePasteboardCount = pasteboardCount }

    mutating func shouldOffer(pressed: Bool, point: CGPoint, pasteboardCount: Int, requested: Bool) -> Bool {
        guard pressed else {
            idlePasteboardCount = pasteboardCount
            pressOrigin = nil
            return false
        }
        if pressOrigin == nil { pressOrigin = point }
        guard requested, pasteboardCount != idlePasteboardCount, let origin = pressOrigin else { return false }
        return hypot(point.x - origin.x, point.y - origin.y) >= 6
    }
}
