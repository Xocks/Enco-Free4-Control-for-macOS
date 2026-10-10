import Foundation

public enum OppoCommand {
    public static let handshake = 0x0100
    public static let queryProductID = 0x0103
    public static let queryBattery = 0x0106
    public static let queryStatus = 0x010D
    public static let queryANC = 0x010C
    public static let queryEQ = 0x010F
    public static let queryAllEQ = 0x0122
    public static let queryBroadcastCodes = 0x0200
    public static let subscribeBroadcast = 0x0205
    public static let activeReport = 0x0204
    public static let setFeature = 0x0403
    public static let setANC = 0x0404
    public static let setEQ = 0x0406
    public static let setEQDetail = 0x0418
    public static let setSpatialAudio = 0x0422
    public static let spatialAudioNotify = 0x0510

    public static let productIDResponse = 0x8103
    public static let batteryResponse = 0x8106
    public static let statusResponse = 0x810D
    public static let ancResponse = 0x810C
    public static let eqResponse = 0x810F
    public static let allEQResponse = 0x8122
    public static let setEQDetailResponse = 0x8418
    public static let broadcastCodesResponse = 0x8200
}

public struct OppoFrame: Equatable, Sendable {
    public let command: Int
    public let sequence: UInt8
    public let payload: Data

    public init(command: Int, sequence: UInt8, payload: Data = Data()) {
        self.command = command
        self.sequence = sequence
        self.payload = payload
    }

    // AA + unsigned LEB128(body length) + reserved(2) + command(2) + seq + payload length(2).
    public init?(data: Data) {
        let bytes = Array(data)
        guard let header = Self.header(bytes), bytes.count == header.offset + header.length,
              header.length >= 7 else { return nil }
        let o = header.offset
        guard bytes[o] == 0, bytes[o + 1] == 0 else { return nil }
        let length = Int(bytes[o + 5]) | Int(bytes[o + 6]) << 8
        guard length == header.length - 7 else { return nil }
        command = Int(bytes[o + 2]) | Int(bytes[o + 3]) << 8
        sequence = bytes[o + 4]
        payload = Data(bytes.dropFirst(o + 7))
    }

    static func header(_ bytes: [UInt8]) -> (offset: Int, length: Int)? {
        guard bytes.first == 0xAA else { return nil }
        var value = 0
        for index in 1...3 {
            guard index < bytes.count else { return nil }
            let byte = bytes[index]
            value |= Int(byte & 0x7F) << ((index - 1) * 7)
            if byte & 0x80 == 0 {
                guard value >= 7, value <= 65_542,
                      index == 1 || byte != 0 else { return nil }
                return (index + 1, value)
            }
        }
        return nil
    }

    public var data: Data {
        precondition(payload.count <= 65_535, "Protocol payload exceeds UInt16 length")
        var remaining = payload.count + 7
        var bytes: [UInt8] = [0xAA]
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining > 0 { byte |= 0x80 }
            bytes.append(byte)
        } while remaining > 0
        bytes += [0, 0, UInt8(truncatingIfNeeded: command), UInt8(truncatingIfNeeded: command >> 8),
                  sequence, UInt8(truncatingIfNeeded: payload.count), UInt8(truncatingIfNeeded: payload.count >> 8)]
        return Data(bytes) + payload
    }
}

public final class OppoPacketBuilder: @unchecked Sendable {
    private let lock = NSLock()
    private var sequence: UInt8 = 1

    public init() {}

    public func make(_ command: Int, payload: [UInt8] = []) -> Data {
        lock.lock()
        let current = sequence
        sequence = sequence >= 0xFE ? 1 : sequence + 1
        lock.unlock()
        return OppoFrame(command: command, sequence: current, payload: Data(payload)).data
    }

    public func make(_ command: Int, fixedSequence: UInt8, payload: [UInt8] = []) -> Data {
        OppoFrame(command: command, sequence: fixedSequence, payload: Data(payload)).data
    }
}
