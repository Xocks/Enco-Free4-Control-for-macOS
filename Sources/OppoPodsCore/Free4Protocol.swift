import Foundation

public enum NoiseLevel: Int, CaseIterable, Identifiable, Codable, Sendable {
    case deep = 4, medium = 5, light = 6, smart = 7
    public var id: Int { rawValue }
    public var name: String {
        switch self { case .deep: return "深度"; case .medium: return "中度"; case .light: return "轻度"; case .smart: return "智能" }
    }
}
public struct NoiseReading: Equatable, Sendable {
    public let mode: NoiseControlMode
    public let level: NoiseLevel?
}
public struct GestureEntry: Hashable, Identifiable, Sendable {
    public let side: UInt8
    public let button: UInt8
    public let action: UInt8
    public let function: UInt8
    public var id: String { "\(side)-\(button)-\(action)" }
    public init(side: UInt8, button: UInt8, action: UInt8, function: UInt8) {
        self.side = side; self.button = button; self.action = action; self.function = function
    }
    public func replacingFunction(_ value: UInt8) -> GestureEntry { .init(side: side, button: button, action: action, function: value) }
}
public struct ConnectedHost: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let connected: Bool
    public let thisMac: Bool
    public let playing: Bool
}

public enum Free4Protocol {
    public static let productID = "068C10"
    public static func noise(_ frame: OppoFrame) -> NoiseReading? {
        let b = Array(frame.payload)
        let p: [UInt8]
        if frame.command == 0x810C { guard b.first == 0 else { return nil }; p = Array(b.dropFirst()) }
        else if frame.command == 0x0204 { guard b.first == 3 else { return nil }; p = Array(b.dropFirst()) }
        else { return nil }
        guard (3...4).contains(p.count), p[0] == 1, p[1] == 1 else { return nil }
        let mask = Int(p[2]) | (p.count == 4 ? Int(p[3]) << 8 : 0)
        switch mask {
        case 1, 8: return .init(mode: .off, level: nil)
        case 2: return .init(mode: .noiseCancellation, level: nil)
        case 4, 0x100, 0x200: return .init(mode: .transparency, level: nil)
        case 0x800: return .init(mode: .adaptive, level: nil)
        case 0x10, 0x20, 0x40, 0x80:
            return .init(mode: .noiseCancellation, level: NoiseLevel(rawValue: mask.trailingZeroBitCount))
        default: return nil
        }
    }
    public static func holdCycle(_ frame: OppoFrame) -> UInt16? {
        let b = Array(frame.payload)
        guard (frame.command == 0x810C && b.first == 0) || (frame.command == 0x0204 && b.first == 3),
              (4...5).contains(b.count), b[1] == 2, b[2] == 1 else { return nil }
        return UInt16(b[3]) | (b.count == 5 ? UInt16(b[4]) << 8 : 0)
    }
    public static func features(_ frame: OppoFrame) -> [UInt8: UInt8]? {
        let b = Array(frame.payload)
        guard frame.command == 0x810D, b.count >= 2, b[0] == 0, b.count == 2 + Int(b[1]) * 2 else { return nil }
        var result: [UInt8: UInt8] = [:]
        for i in stride(from: 2, to: b.count, by: 2) {
            guard result[b[i]] == nil else { return nil }; result[b[i]] = b[i + 1]
        }
        return result
    }
    public static func gestures(_ frame: OppoFrame) -> [GestureEntry]? {
        let b = Array(frame.payload)
        guard frame.command == 0x8108, b.count >= 2, b[0] == 0, b.count == 2 + Int(b[1]) * 4 else { return nil }
        var result: [GestureEntry] = []
        for i in stride(from: 2, to: b.count, by: 4) {
            let row = GestureEntry(side: b[i], button: b[i+1], action: b[i+2], function: b[i+3])
            guard (1...2).contains(row.side), !result.contains(where: { $0.id == row.id }) else { return nil }
            result.append(row)
        }
        return result
    }
    public static func firmware(_ frame: OppoFrame) -> String? {
        let b = Array(frame.payload)
        guard frame.command == 0x8105, b.count > 2, b[0] == 0,
              let text = String(bytes: b.dropFirst(2), encoding: .utf8) else { return nil }
        let parts = text.split(separator: ",")
        guard parts.count % 3 == 0 else { return nil }
        return stride(from: 0, to: parts.count, by: 3).filter { parts[$0+1] == "2" }.map { String(parts[$0+2]) }.joined(separator: ".")
    }
    public static func hosts(_ frame: OppoFrame) -> [ConnectedHost]? {
        let b = Array(frame.payload)
        guard (frame.command == 0x8112 && b.first == 0) || (frame.command == 0x0204 && b.first == 6), b.count >= 2 else { return nil }
        var p = 2, result: [ConnectedHost] = []
        for _ in 0..<Int(b[1]) {
            guard p+10 <= b.count else { return nil }
            let mac = b[p..<p+6].map { String(format: "%02X", $0) }.joined()
            let length = Int(b[p+6]), names = Int(b[p+9])
            guard length == 3 + names, p+10+names <= b.count,
                  let name = String(bytes: b[p+10..<p+10+names], encoding: .utf8) else { return nil }
            result.append(.init(id: mac, name: name, connected: b[p+7] == 2, thisMac: b[p+8]&1 != 0, playing: b[p+8]&4 != 0))
            p += 10 + names
        }
        return p == b.count ? result : nil
    }
    public static func supportedCommands(_ frame: OppoFrame) -> Set<Int>? {
        let b = Array(frame.payload)
        guard frame.command == 0x8100, b.count >= 2, b[0] == 0 else { return nil }
        let map: [[Int]] = [
            [0x0105],[0x0106],[0x0107],[0x0108,0x0401,0x0416],[0x0109],[0x0400],[0x0402],[0x0403],
            [0x010C,0x0404],[0x0405],[0x0406,0x010F],[0x0407],[],[0x0408],[0x0409],[],[],[0x0114],[],
            [0x040E,0x040D,0x0115,0x0116],[0x040F],[0x0410,0x0119],[0x0205],[0x0F00],[],[0x0118,0x0411],
            [0x011A,0x0412],[0x011C,0x0413],[],[0x0112,0x040B],[0x011E,0x011F,0x0415],[0x040D],[],[0x0121,0x0417],
            [0x0122,0x0418],[],[0x011D,0x0414],[0x0123,0x041A],[0x0124,0x041B],[0x0125,0x041C,0x0127,0x041D,0x041F],
            [0x0421,0x0023,0x0024,0x0022,0x0126,0x0129],[0xEF01],[0xEF02],[0xEF03,0x041E],[0x0420],[0x001C],[],
            [0x0422,0x012A],[0xEF04],[0x0423,0x012B],[],[0x0424],[0xEF06],[],[],[0x0425,0x012E,0x0426],
            [0x012F],[0x0427,0x0130],[0x0131,0x0428],[0x0429,0x0132],[0x0014],[0x042D,0x0133],[0x042E],[0xEF07],[0xEF08],[0xEF09],[0x0431,0x0134]
        ]
        var result: Set<Int> = [0x0100,0x0101,0x0102,0x0103,0x0104,0x0106,0x010B,0x010D,0x0F00,0x0F03,0x0F04]
        for bit in 0..<min((b.count-1)*8, map.count) where b[1+bit/8] & (1 << (bit%8)) != 0 { result.formUnion(map[bit]) }
        return result
    }
}

// A write succeeds only after its ACK and a matching, correlated read-back.
public struct OperationConfirmation: Sendable {
    public let writeCommand: Int
    public let writeSequence: UInt8
    public private(set) var acknowledged = false
    private var reads: Set<String> = []
    public init(write: OppoFrame) { writeCommand = write.command; writeSequence = write.sequence }
    public mutating func acceptAcknowledgement(_ frame: OppoFrame) -> Bool? {
        guard frame.command == writeCommand | 0x8000, frame.sequence == writeSequence else { return nil }
        acknowledged = frame.payload.first == 0
        return acknowledged
    }
    public mutating func registerRead(_ frame: OppoFrame) {
        guard acknowledged else { return }; reads.insert("\(frame.command | 0x8000)-\(frame.sequence)")
    }
    public func acceptsRead(_ frame: OppoFrame) -> Bool { acknowledged && reads.contains("\(frame.command)-\(frame.sequence)") }
}
