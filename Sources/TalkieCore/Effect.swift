import Foundation

/// Voice effects, applied on your Mac before your voice is sent.
public enum Effect: Int, CaseIterable, Sendable {
    case off, canyon, tinCan, helium, machine

    public var title: String {
        switch self {
        case .off: return "OFF"
        case .canyon: return "CANYON"
        case .tinCan: return "TIN CAN"
        case .helium: return "HELIUM"
        case .machine: return "MACHINE"
        }
    }

    public var blurb: String {
        switch self {
        case .off: return "CLEAN VOICE"
        case .canyon: return "COMES BACK TWICE"
        case .tinCan: return "THIN AND CRUNCHY"
        case .helium: return "AN OCTAVE UP"
        case .machine: return "RING-MODULATED"
        }
    }

    /// One line for the effects picker.
    public var detail: String {
        switch self {
        case .off: return "Your own voice."
        case .canyon: return "An echo with room to travel."
        case .tinCan: return "Thin, crunchy, distant."
        case .helium: return "One octave up."
        case .machine: return "A little less human."
        }
    }

    /// Which of the mic's four effect lights is on (1...4), or nil when off.
    public var slot: Int? { self == .off ? nil : rawValue }

    public var next: Effect {
        Effect(rawValue: (rawValue + 1) % Effect.allCases.count) ?? .off
    }
}
