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

    /// 列表在目标模式下的有效高度：交互不小于交互最小值，穿透沿用基准高度。
    /// 基准高度取持久化的列表尺寸（用户主动调整或内容适配），临时增高不写回，
    /// 因此反向切换能还原紧凑高度，而用户调高的尺寸得以保留。
    public static func listHeight(baseHeight: CGFloat, interactive: Bool, interactiveMinimum: CGFloat, passthroughMinimum: CGFloat) -> CGFloat {
        max(baseHeight, interactive ? interactiveMinimum : passthroughMinimum)
    }

    /// 无历史尺寸初次自动内容测量的基准选择：仅当前交互且实测恰为交互最小值（空列表含工具栏）时，
    /// 持久化基准取穿透最小值（紧凑），实际窗口仍显示实测全高；实测超过交互最小值则存实测全高。
    /// 已有/用户主动设置的尺寸不走此路径，原意维持。
    public static func firstFitBaseHeight(measuredHeight: CGFloat, interactive: Bool, interactiveMinimum: CGFloat, passthroughMinimum: CGFloat) -> CGFloat {
        if interactive && measuredHeight == interactiveMinimum {
            return passthroughMinimum
        }
        return measuredHeight
    }

    /// 列表模式切换的目标 frame：以有效高度保留当前左上角，并夹取进当前屏可用区。
    public static func listModeFrame(current: CGRect, baseHeight: CGFloat, interactive: Bool, interactiveMinimum: CGFloat, passthroughMinimum: CGFloat, screens: [HudScreen], main: HudScreen?) -> CGRect {
        let targetHeight = listHeight(baseHeight: baseHeight, interactive: interactive, interactiveMinimum: interactiveMinimum, passthroughMinimum: passthroughMinimum)
        let frame = CGRect(
            origin: CGPoint(x: current.minX, y: current.maxY - targetHeight),
            size: CGSize(width: current.width, height: targetHeight)
        )
        if let index = bestScreenIndex(for: current, screens: screens) {
            return clamped(frame, into: screens[index].visibleFrame)
        }
        if let main {
            return clamped(frame, into: main.visibleFrame)
        }
        return frame
    }

    /// 用户调整列表窗口后的基准高度决策：仅当实际高度偏离当前模式应有的显示高度时，
    /// 视为用户真实改变了高度并更新基准；仅移动/仅调宽/程序化显示（高度等于显示高度）保留基准。
    public static func updatedListBaseHeight(actualHeight: CGFloat, currentBaseHeight: CGFloat, interactive: Bool, interactiveMinimum: CGFloat, passthroughMinimum: CGFloat) -> CGFloat {
        let displayHeight = listHeight(baseHeight: currentBaseHeight, interactive: interactive, interactiveMinimum: interactiveMinimum, passthroughMinimum: passthroughMinimum)
        return actualHeight == displayHeight ? currentBaseHeight : actualHeight
    }

    /// 列表持久化 frame：位置与宽度取实际值，高度取基准高度，避免把交互临时增高写回基准。
    public static func persistedListFrame(actual: CGRect, baseHeight: CGFloat) -> CGRect {
        CGRect(origin: CGPoint(x: actual.minX, y: actual.minY), size: CGSize(width: actual.width, height: baseHeight))
    }

    /// 收起选侧：缩窄时仅比较原窗口左/右间距，取较近的水平边（平局优先左）；
    /// 顶/底再近也不参与，避免水平位置滞留。
    public static func collapseSide(frame: CGRect, visible: CGRect) -> HudSnapEdge {
        let leftGap = max(0, frame.minX - visible.minX)
        let rightGap = max(0, visible.maxX - frame.maxX)
        return rightGap < leftGap ? .right : .left
    }

    /// 贴到所选可用区边缘：所选轴贴边，另一轴尽量保持原位置并夹取，尺寸保持。
    public static func snappedFrame(frame: CGRect, edge: HudSnapEdge, visible: CGRect) -> CGRect {
        var result = frame
        switch edge {
        case .left:
            result.origin.x = visible.minX
        case .right:
            result.origin.x = visible.maxX - result.width
        case .bottom:
            result.origin.y = visible.minY
        case .top:
            result.origin.y = visible.maxY - result.height
        }
        return clamped(result, into: visible)
    }

    /// 四象限收为列表（交互手动与穿透两入口）：以原四象限选较近的左/右侧边，
    /// 列表按目标尺寸保留垂直位置后水平贴该边并夹取，保持可见与已选尺寸。
    public static func collapsedListFrame(current: CGRect, targetSize: CGSize, screens: [HudScreen], main: HudScreen?) -> CGRect {
        let listFrame = switchedFrame(current: current, targetSize: targetSize, screens: screens, main: main)
        let screen = bestScreenIndex(for: current, screens: screens).map { screens[$0] } ?? main
        guard let screen else {
            return listFrame
        }
        let side = collapseSide(frame: current, visible: screen.visibleFrame)
        return snappedFrame(frame: listFrame, edge: side, visible: screen.visibleFrame)
    }

    /// 内容适配确定最终高度后的列表 frame：先按左上角锚定收缩到最终高度，
    /// 若收起时选了贴边则沿该边重新对齐并夹取（避免收缩后底边离开所选边缘）；无贴边状态则不吸边。
    public static func contentFittedListFrame(current: CGRect, finalHeight: CGFloat, snapEdge: HudSnapEdge?, screens: [HudScreen], main: HudScreen?) -> CGRect {
        var frame = CGRect(
            origin: CGPoint(x: current.minX, y: current.maxY - finalHeight),
            size: CGSize(width: current.width, height: finalHeight)
        )
        if let snapEdge {
            let screen = bestScreenIndex(for: frame, screens: screens).map { screens[$0] } ?? main
            if let screen {
                frame = snappedFrame(frame: frame, edge: snapEdge, visible: screen.visibleFrame)
            }
        }
        return frame
    }
}

/// HUD 收起贴边的可选边缘。
public enum HudSnapEdge: String, CaseIterable, Sendable {
    case left
    case right
    case bottom
    case top
}