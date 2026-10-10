import Foundation

struct Failure: Error, CustomStringConvertible { let description: String }
func expect(_ condition: @autoclosure () -> Bool, _ message: String = "expectation failed") throws {
    if !condition() { throw Failure(description: message) }
}
func unwrap<T>(_ value: T?) throws -> T { guard let value else { throw Failure(description: "unexpected nil") }; return value }
var passed = 0, failed = 0
func check(_ name: String, _ body: () throws -> Void) {
    do { try body(); passed += 1; print("PASS \(name)") }
    catch { failed += 1; print("FAIL \(name): \(error)") }
}
func frame(_ command: Int, _ payload: [UInt8], seq: UInt8 = 1) -> OppoFrame { .init(command: command, sequence: seq, payload: Data(payload)) }

check("LEB128 boundaries and full UInt16 payload") {
    for size in [0,1,120,121,127,128,248,255,1024,16376,16377,65535] {
        let original = OppoFrame(command: 0x0418, sequence: 254, payload: Data(repeating: 0xA5, count: size))
        try expect(OppoFrame(data: original.data) == original, "roundtrip size \(size)")
    }
    let long = OppoFrame(command: 0x0418, sequence: 1, payload: Data(repeating: 0, count: 121)).data
    try expect(Array(long.prefix(3)) == [0xAA,0x80,0x01], "128 body must use two-byte length")
}
check("stream split at every boundary and concatenation") {
    let packets = [frame(0x8106,[0,1,1,90]).data, OppoFrame(command: 0x811E, sequence: 2, payload: Data(repeating: 0xAA,count: 180)).data]
    let stream = packets.reduce(Data(),+)
    for cut in 0...stream.count {
        var framer = OppoPacketFramer()
        let output = framer.append(Data(stream.prefix(cut))) + framer.append(Data(stream.dropFirst(cut)))
        try expect(output == packets, "split at \(cut)")
    }
}
check("malformed lengths, reserved bytes and noise resynchronize") {
    let good = frame(0x8103,[0,0x10,0x8C,6]).data
    let broken: [[UInt8]] = [[0xAA,0], [0xAA,0xFF,0xFF,0xFF,0xFF], [0xAA,7,1,0,0,1,1,0,0], [0xAA,7,0,0,0,1,1,5,0]]
    for bad in broken {
        var framer = OppoPacketFramer()
        try expect(framer.append(Data([3,4,5]+bad)+good) == [good])
    }
    try expect(OppoFrame(data: Data([0xAA,0x87,0,0,0,0,1,1,0,0])) == nil, "noncanonical varint rejected")
}
check("deterministic noisy stream stress") {
    var seed: UInt64 = 20261009
    func random() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1; return seed }
    var stream = Data(), packets: [Data] = []
    for i in 0..<300 {
        stream += Data(repeating: 0x55,count: Int(random()%5))
        let data = OppoFrame(command: 0x8106,sequence: UInt8(i%254+1),payload: Data(repeating: UInt8(random()%256),count: Int(random()%1000))).data
        packets.append(data); stream += data
    }
    var framer = OppoPacketFramer(), actual: [Data] = [], offset = 0
    while offset < stream.count {
        let end = min(stream.count,offset+Int(random()%90+1))
        actual += framer.append(Data(stream[offset..<end])); offset = end
    }
    try expect(actual == packets)
}
check("ordinary identity and reject malformed PID") {
    try expect(OppoParsers.productID(from: frame(0x8103,[0,0x10,0x8C,6])) == Free4Protocol.productID)
    try expect(OppoParsers.productID(from: frame(0x8103,[1,0x10,0x8C,6])) == nil)
    try expect(OppoParsers.productID(from: frame(0x8103,[0,0x10,0xC0,6])) != Free4Protocol.productID)
}
check("battery status/count, legacy pairs and charging") {
    for bytes: [UInt8] in [[0,3,1,86,2,202,3,55], [1,86,2,202,3,55]] {
        let value = try unwrap(OppoParsers.battery(from: frame(0x8106,bytes)))
        try expect(value.left?.level == 86 && value.right?.level == 74 && value.right?.isCharging == true && value.chargingCase?.level == 55)
    }
}
check("unknown battery and malformed responses") {
    let unknown = try unwrap(OppoParsers.battery(from: frame(0x8106,[0,3,1,0,2,127,3,101])))
    try expect(unknown == BatteryStatus())
    for bytes: [UInt8] in [[0,2,1,80], [0,2,1,80,1,90], [1,4,80], [0,1,9,80]] {
        try expect(OppoParsers.battery(from: frame(0x8106,bytes)) == nil)
    }
    try expect(OppoParsers.battery(from: frame(0x0204,[1,1,2,150]))?.right == .init(level:22,isCharging:true))
}
check("Free4 writes parent modes, reports child modes") {
    let commands = OppoCommands()
    try expect(OppoFrame(data: commands.setNoiseControl(.off))?.payload == Data([1,1,1]))
    try expect(OppoFrame(data: commands.setNoiseControl(.transparency))?.payload == Data([1,1,4]))
    for (mask,mode): (UInt16,NoiseControlMode) in [(1,.off),(8,.off),(4,.transparency),(256,.transparency),(2048,.adaptive)] {
        try expect(Free4Protocol.noise(frame(0x810C,[0,1,1,UInt8(truncatingIfNeeded:mask),UInt8(mask>>8)]))?.mode == mode)
    }
    for level in NoiseLevel.allCases {
        let reading = Free4Protocol.noise(frame(0x0204,[3,1,1,UInt8(1<<level.rawValue),0]))
        try expect(reading?.level == level && reading?.mode == .noiseCancellation)
    }
}
check("hold cycle and smart realtime cannot change current ANC") {
    try expect(Free4Protocol.noise(frame(0x0204,[3,2,1,7,0])) == nil)
    try expect(Free4Protocol.noise(frame(0x0204,[3,4,1,16,0])) == nil)
    try expect(Free4Protocol.noise(frame(0x810C,[1,1,1,16])) == nil)
    try expect(Free4Protocol.holdCycle(frame(0x810C,[0,2,1,7,8])) == 0x807)
    try expect(Free4Protocol.holdCycle(frame(0x0204,[3,1,1,7,8])) == nil)
}
check("strict feature pairs and missing flags stay unknown") {
    let values = try unwrap(Free4Protocol.features(frame(0x810D,[0,2,4,1,0x11,0])))
    try expect(values[4] == 1 && values[0x11] == 0 && values[0x1B] == nil)
    try expect(Free4Protocol.features(frame(0x810D,[0,2,4,1])) == nil)
    try expect(Free4Protocol.features(frame(0x810D,[0,2,4,1,4,0])) == nil)
}
check("capability bitmap gates optional commands") {
    let commands = try unwrap(Free4Protocol.supportedCommands(frame(0x8100,[0,0,1,0,0,4])))
    try expect(commands.contains(0x0404) && commands.contains(0x0122) && !commands.contains(0x0400))
    try expect(Free4Protocol.supportedCommands(frame(0x8100,[1,255])) == nil)
}
check("gesture layout and duplicate slot rejection") {
    let rows = try unwrap(Free4Protocol.gestures(frame(0x8108,[0,2,1,1,2,5,2,3,5,7])))
    try expect(rows.count == 2 && rows[1].button == 3 && rows[0].function == 5)
    try expect(Free4Protocol.gestures(frame(0x8108,[0,2,1,1,2,5,1,1,2,6])) == nil)
    try expect(Free4Protocol.gestures(frame(0x8108,[0,2,1,1,2,5])) == nil)
    try expect(OppoFrame(data: OppoCommands().setGestures(rows))?.payload == Data([2,1,1,2,5,2,3,5,7]))
}
check("firmware triples") {
    try expect(Free4Protocol.firmware(frame(0x8105,[0,3]+Array("1,2,138,2,2,138,3,2,105".utf8))) == "138.138.105")
    try expect(Free4Protocol.firmware(frame(0x8105,[0,3]+Array("1,2".utf8))) == nil)
}
check("connected host list validates lengths") {
    let payload: [UInt8] = [0,1,1,2,3,4,5,6,6,2,5,3]+Array("Mac".utf8)
    let hosts = try unwrap(Free4Protocol.hosts(frame(0x8112,payload)))
    try expect(hosts.count == 1 && hosts[0].thisMac && hosts[0].playing && hosts[0].name == "Mac")
    try expect(Free4Protocol.hosts(frame(0x8112,Array(payload.dropLast()))) == nil)
}
check("EQ long UTF8 name is truncated on character boundaries") {
    let encoded = try unwrap(OppoFrame(data: OppoCommands().saveCustomEQ(id: 3,name: String(repeating:"耳机🎵",count:100),frequencies:[62,1000],gains:[3,-2])))
    let b = Array(encoded.payload), count = Int(encoded.payload[4])
    try expect(encoded.payload.count > 127 && count <= 255)
    try expect(String(bytes: b[5..<5+count],encoding:.utf8) != nil)
}
check("EQ list roundtrip structure and truncated bands") {
    let name = Array("自定义".utf8)
    let bytes: [UInt8] = [0,1,1,250,6,3,UInt8(name.count)] + name + [2,62,0,3,232,3,254]
    let presets = try unwrap(OppoParsers.allEqualizers(from: frame(0x8122,bytes)))
    try expect(presets.first?.gains == [3,-2] && presets.first?.frequencies == [62,1000])
    try expect(OppoParsers.allEqualizers(from: frame(0x8122,Array(bytes.dropLast()))) == nil)
    try expect(OppoParsers.allEqualizers(from: frame(0x8122,bytes+[0])) == nil)
}
check("ACK alone never confirms effect; query response must match sequence") {
    let write = frame(0x0404,[1,1,16],seq: 10), read = frame(0x010C,[1,1],seq: 11)
    var tracker = OperationConfirmation(write: write)
    tracker.registerRead(read)
    try expect(!tracker.acceptsRead(frame(0x810C,[0,1,1,16],seq:11)))
    try expect(tracker.acceptAcknowledgement(frame(0x8404,[0],seq:9)) == nil)
    try expect(tracker.acceptAcknowledgement(frame(0x8404,[0],seq:10)) == true)
    try expect(!tracker.acceptsRead(frame(0x810C,[0,1,1,16],seq:11)))
    tracker.registerRead(read)
    try expect(tracker.acceptsRead(frame(0x810C,[0,1,1,16],seq:11)))
    try expect(!tracker.acceptsRead(frame(0x810C,[0,1,1,16],seq:12)))
    try expect(!tracker.acceptsRead(frame(0x0204,[3,1,1,16],seq:11)))
}
check("negative and malformed ACK stay unconfirmed") {
    for payload: [UInt8] in [[1],[],[255]] {
        var tracker = OperationConfirmation(write: frame(0x0406,[1],seq:2))
        try expect(tracker.acceptAcknowledgement(frame(0x8406,payload,seq:2)) == false)
        tracker.registerRead(frame(0x010F,[],seq:3))
        try expect(!tracker.acceptsRead(frame(0x810F,[0,1],seq:3)))
    }
}
check("request sequence uniqueness and wrap") {
    let commands = OppoCommands()
    let seq = (0..<254).compactMap { _ in OppoFrame(data: commands.queryBattery())?.sequence }
    try expect(Set(seq).count == 254 && !seq.contains(0) && !seq.contains(255))
    try expect(OppoFrame(data: commands.queryBattery())?.sequence == 1)
}
check("personalization records validate structure and UID byte order") {
    var hearing: [UInt8] = [0,3,12]
    for side in UInt8(1)...2 { for frequency in UInt8(1)...6 { hearing += [side,frequency,255] } }
    hearing += [0x12,0x34,0x56,0x78] + Array("我的听感".utf8)
    let record = try unwrap(HearingRecord.parse(frame(0x8115,hearing)))
    try expect(record.uid == 0x12345678 && record.values == Array(repeating:-1,count:12) && record.name == "我的听感")
    var duplicate = hearing; duplicate[6] = 1; duplicate[7] = 1
    try expect(HearingRecord.parse(frame(0x8115,duplicate)) == nil)
    try expect(HearingRecord.parse(frame(0x8115,Array(hearing.prefix(42)))) == nil)
    let scan: [UInt8] = [0,3,168,0] + Array(repeating:7,count:168) + [0x12,0x34,0x56,0x78]
    try expect(EarScanRecord.parse(frame(0x811E,scan))?.uid == 0x12345678)
    try expect(EarScanRecord.parse(frame(0x811E,scan))?.data.count == 168)
    try expect(EarScanRecord.parse(frame(0x811E,Array(scan.dropLast()))) == nil)
    try expect(EarScanRecord.parse(frame(0x811E,scan+[0])) == nil)
}
check("tone presets strict lengths flags CRC and UTF8") {
    let first: [UInt8] = [1,0,0,0,1,0x78,0x56,0x34,0x12,1,0]
    let name = Array("铃声".utf8)
    let second: [UInt8] = [2,0,0,0,1,0,0,0,0,0,UInt8(name.count)] + name
    let values = try unwrap(EarTonePreset.parse(frame(0x8121,[0,2]+first+second)))
    try expect(values.count == 2 && values[0].selected && values[0].crc32 == 0x12345678 && values[1].name == "铃声")
    try expect(EarTonePreset.parse(frame(0x0204,[0x11,2]+first+second)) == values)
    try expect(EarTonePreset.parse(frame(0x8121,[0,1]+Array(first.prefix(10))))?.count == 1)
    try expect(EarTonePreset.parse(frame(0x8121,[0,2]+first+first)) == nil)
    try expect(EarTonePreset.parse(frame(0x8121,[0,2]+first+Array(second.dropLast()))) == nil)
    try expect(EarTonePreset.parse(frame(0x8121,[1,1]+first)) == nil)
    try expect(EarTonePreset.parse(frame(0x8121,[0,1]+first+[0])) == nil)
}
check("hold cycle uses minimal little endian mask") {
    let commands = OppoCommands()
    try expect(OppoFrame(data:commands.setHoldCycle(7))?.payload == Data([2,1,7]))
    try expect(OppoFrame(data:commands.setHoldCycle(0x807))?.payload == Data([2,1,7,8]))
}
print("\n\(passed) passed; \(failed) failed")
if failed > 0 { exit(1) }
