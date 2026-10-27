import Foundation

public enum ProgressRingStyle: String, CaseIterable, Identifiable, Sendable {
    case classicMinimal = "classicMinimal"
    case dualBalanced = "dualBalanced"
    case pulsingGlow = "pulsingGlow"
    case dottedOrbit = "dottedOrbit"
    case auroraVivid = "auroraVivid"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classicMinimal:
            return "极简微弧 (Classic Thin)"
        case .dualBalanced:
            return "双弧平衡 (Dual Balanced)"
        case .pulsingGlow:
            return "静止呼吸 (Pulsing Breath)"
        case .dottedOrbit:
            return "精密虚线 (Dotted Radar)"
        case .auroraVivid:
            return "极光双色 (Aurora Vivid)"
        }
    }

    public var subtitle: String {
        switch self {
        case .classicMinimal:
            return "1.0pt 单色细弧，微速旋转，极度内敛"
        case .dualBalanced:
            return "对称双段微弧，平稳匀速，消除偏心晃动"
        case .pulsingGlow:
            return "无任何旋转，原位静默呼吸明暗明灭"
        case .dottedOrbit:
            return "精密齿轮仪表虚线，科技质感"
        case .auroraVivid:
            return "青紫双色渐变弧，活力动感"
        }
    }
}
