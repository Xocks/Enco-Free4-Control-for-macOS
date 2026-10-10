import Foundation

public struct HearingRecord: Codable, Equatable, Sendable {
    public let uid: UInt32
    public let name: String
    public let values: [Int]
    public static func parse(_ frame: OppoFrame) -> HearingRecord? {
        let b = Array(frame.payload)
        guard frame.command == 0x8115, b.count >= 43, b[0] == 0, b[1] == 3, b[2] == 12 else { return nil }
        var values = [Int](repeating: 0, count: 12), seen: Set<Int> = []
        for index in 0..<12 {
            let p = 3 + index*3, side = Int(b[p]), frequency = Int(b[p+1])
            guard (1...2).contains(side), (1...6).contains(frequency) else { return nil }
            let slot = (side-1)*6 + frequency-1
            guard seen.insert(slot).inserted else { return nil }
            values[slot] = Int(Int8(bitPattern: b[p+2]))
        }
        let uid = b[39..<43].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard let name = String(bytes: b.dropFirst(43), encoding: .utf8) else { return nil }
        return .init(uid: uid, name: name, values: values)
    }
}
public struct EarScanRecord: Codable, Equatable, Sendable {
    public let uid: UInt32
    public let data: Data
    public static func parse(_ frame: OppoFrame) -> EarScanRecord? {
        let b = Array(frame.payload)
        guard frame.command == 0x811E, b.count >= 8, b[0] == 0, b[1] == 3 else { return nil }
        let length = Int(b[2]) | Int(b[3]) << 8
        guard length == 168, b.count == length+8 else { return nil }
        let uid = b[(4+length)..<(8+length)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return .init(uid: uid, data: Data(b[4..<4+length]))
    }
}
