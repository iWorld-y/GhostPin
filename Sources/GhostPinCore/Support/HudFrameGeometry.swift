import CoreGraphics
import Foundation

/// 屏幕的完整 frame 与可用 frame，供 HUD 窗口几何计算与回归检查使用。
public struct HudScreen: Equatable, Sendable {
    public let frame: CGRect
    public let visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public enum HudFrameGeometry {
    /// 与给定 frame 相交面积最大的屏幕下标；无相交返回 nil。
    public static func bestScreenIndex(for frame: CGRect, screens: [HudScreen]) -> Int? {
        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for (index, screen) in screens.enumerated() {
            let intersection = frame.intersection(screen.frame)
            guard !intersection.isNull else {
                continue
            }
            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// 将 frame 完整夹取进可用区域，必要时先缩小尺寸。
    public static func clamped(_ frame: CGRect, into visible: CGRect) -> CGRect {
        var result = frame
        result.size.width = min(result.width, visible.width)
        result.size.height = min(result.height, visible.height)
        result.origin.x = min(max(result.origin.x, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.origin.y, visible.minY), visible.maxY - result.height)
        return result
    }

    /// 启动恢复：选相交面积最大的屏幕并完整夹取进其可用区；
    /// 与任何屏幕都不相交时回退主屏，避免窗口留在屏外。
    public static func restoredFrame(_ frame: CGRect, screens: [HudScreen], main: HudScreen?) -> CGRect {
        if let index = bestScreenIndex(for: frame, screens: screens) {
            return clamped(frame, into: screens[index].visibleFrame)
        }
        if let main {
            return clamped(frame, into: main.visibleFrame)
        }
        return frame
    }

    /// 布局切换：保留当前左上角，仅取目标尺寸，在当前屏可用区内夹取。
    public static func switchedFrame(current: CGRect, targetSize: CGSize, screens: [HudScreen], main: HudScreen?) -> CGRect {
        let frame = CGRect(
            origin: CGPoint(x: current.minX, y: current.maxY - targetSize.height),
            size: targetSize
        )
        if let index = bestScreenIndex(for: current, screens: screens) {
            return clamped(frame, into: screens[index].visibleFrame)
        }
        if let main {
            return clamped(frame, into: main.visibleFrame)
        }
        return frame
    }
}