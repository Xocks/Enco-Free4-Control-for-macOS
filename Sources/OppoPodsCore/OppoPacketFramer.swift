import Foundation

public struct OppoPacketFramer: Sendable {
    private var pending: [UInt8] = []
    public init() {}
    public mutating func append(_ data: Data) -> [Data] {
        pending += data
        var frames: [Data] = []
        while !pending.isEmpty {
            guard let first = pending.firstIndex(of: 0xAA) else { pending.removeAll(); break }
            if first > 0 { pending.removeFirst(first) }
            guard pending.count > 1 else { break }
            guard let h = OppoFrame.header(pending) else {
                // At most three bytes of length; a partial varint must wait.
                if pending.count < 4 && pending.dropFirst().allSatisfy({ $0 & 0x80 != 0 }) { break }
                pending.removeFirst(); continue
            }
            guard pending.count >= h.offset + 7 else { break }
            let o = h.offset
            let inner = Int(pending[o + 5]) | Int(pending[o + 6]) << 8
            guard pending[o] == 0, pending[o + 1] == 0, inner == h.length - 7 else {
                pending.removeFirst(); continue
            }
            let length = h.offset + h.length
            guard pending.count >= length else { break }
            let packet = Data(pending.prefix(length))
            if OppoFrame(data: packet) != nil { frames.append(packet) }
            pending.removeFirst(length)
        }
        return frames
    }
}
