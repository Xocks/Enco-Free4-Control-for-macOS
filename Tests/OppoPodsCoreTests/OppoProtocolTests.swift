import XCTest
@testable import OppoPodsCore

final class OppoProtocolTests: XCTestCase {
    func testPacketRoundTrip() throws {
        let data = OppoFrame(command: OppoCommand.setANC, sequence: 0xF0, payload: Data([1, 1, 2])).data
        let frame = try XCTUnwrap(OppoFrame(data: data))
        XCTAssertEqual(frame.command, OppoCommand.setANC)
        XCTAssertEqual(frame.sequence, 0xF0)
        XCTAssertEqual(frame.payload, Data([1, 1, 2]))
    }

    func testFramerHandlesSplitAndCombinedPackets() {
        let first = OppoFrame(command: OppoCommand.queryBattery, sequence: 1).data
        let second = OppoFrame(command: OppoCommand.queryANC, sequence: 2, payload: Data([1, 1])).data
        var framer = OppoPacketFramer()

        XCTAssertTrue(framer.append(first.prefix(4)).isEmpty)
        let frames = framer.append(first.dropFirst(4) + second)
        XCTAssertEqual(frames, [first, second])
    }

    func testBatteryParser() throws {
        let frame = OppoFrame(
            command: OppoCommand.batteryResponse,
            sequence: 1,
            payload: Data([1, 86, 2, UInt8(0x80 | 74), 3, 55])
        )
        let battery = try XCTUnwrap(OppoParsers.battery(from: frame))
        XCTAssertEqual(battery.left, BatteryLevel(level: 86, isCharging: false))
        XCTAssertEqual(battery.right, BatteryLevel(level: 74, isCharging: true))
        XCTAssertEqual(battery.chargingCase, BatteryLevel(level: 55, isCharging: false))
    }

    func testKnownSpatialPacket() {
        let data = OppoCommands().setSpatialAudio(.headTracking)
        XCTAssertEqual(data, Data([0xAA, 0x08, 0, 0, 0x22, 0x04, 0x01, 1, 0, 2]))
    }

    func testGameModeFeatureVariants() throws {
        let frame = OppoFrame(
            command: OppoCommand.statusResponse,
            sequence: 1,
            payload: Data([0, 2, 0x06, 1, 0x28, 0])
        )
        let status = try XCTUnwrap(OppoParsers.featureStatus(from: frame))
        XCTAssertEqual(status.lowLatencyMode, true)
        XCTAssertEqual(status.gameMode, false)
    }

    func testModelSpecificANCPayload() {
        let data = OppoCommands().setNoiseControl(protocolIndex: 11)
        XCTAssertEqual(data, Data([0xAA, 0x0B, 0, 0, 0x04, 0x04, 0x01, 4, 0, 1, 1, 0, 0x08]))
    }

    func testQueryAllEqualizersPacket() throws {
        let frame = try XCTUnwrap(OppoFrame(data: OppoCommands().queryAllEQ()))
        XCTAssertEqual(frame.command, OppoCommand.queryAllEQ)
        XCTAssertEqual(frame.payload, Data())
    }

    func testCustomEqualizerParser() throws {
        let name = Array("自定义".utf8)
        let payload = Data(
            [0, 1, 1, 0xFA, 0x06, 7, UInt8(name.count)]
                + name
                + [2, 62, 0, 3, 0xE8, 3, 0xFE]
        )
        let frame = OppoFrame(command: OppoCommand.allEQResponse, sequence: 1, payload: payload)
        let presets = try XCTUnwrap(OppoParsers.allEqualizers(from: frame))
        XCTAssertEqual(presets, [DeviceEqualizerPreset(
            id: 7,
            name: "自定义",
            isSelected: true,
            minimumGain: -6,
            maximumGain: 6,
            frequencies: [62, 1_000],
            gains: [3, -2]
        )])
    }

    func testSaveCustomEqualizerPacket() throws {
        let data = OppoCommands().saveCustomEQ(
            id: 7,
            name: "EQ",
            frequencies: [62, 1_000],
            gains: [3, -2]
        )
        let frame = try XCTUnwrap(OppoFrame(data: data))
        XCTAssertEqual(frame.command, OppoCommand.setEQDetail)
        XCTAssertEqual(
            frame.payload,
            Data([2, 0xFA, 0x06, 7, 2, 0x45, 0x51, 2, 62, 0, 3, 0xE8, 3, 0xFE])
        )
    }
}
