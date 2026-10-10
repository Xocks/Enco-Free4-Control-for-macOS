import Foundation

public struct EarTonePreset: Equatable, Identifiable, Sendable {
    public let id: UInt32
    public let valid: Bool
    public let crc32: UInt32
    public let selected: Bool
    public let name: String
    public static func parse(_ frame: OppoFrame) -> [EarTonePreset]? {
        let b = Array(frame.payload)
        guard (frame.command == 0x8121 && b.first == 0) || (frame.command == 0x0204 && b.first == 0x11), b.count >= 2 else { return nil }
        var p = 2, result: [EarTonePreset] = []
        func u32(_ offset: Int) -> UInt32 { (0..<4).reduce(UInt32(0)) { $0 | UInt32(b[offset+$1]) << ($1*8) } }
        for _ in 0..<Int(b[1]) {
            guard p+10 <= b.count else { return nil }
            let id = u32(p), valid = b[p+4], crc = u32(p+5), selected = b[p+9]
            p += 10
            var name = ""
            if p < b.count {
                let length = Int(b[p]); p += 1
                guard p+length <= b.count, let text = String(bytes:b[p..<p+length],encoding:.utf8) else { return nil }
                name = text; p += length
            }
            guard valid <= 1, selected <= 1, !result.contains(where: { $0.id == id }) else { return nil }
            result.append(.init(id:id,valid:valid == 1,crc32:crc,selected:selected == 1,name:name))
        }
        return p == b.count ? result : nil
    }
}
