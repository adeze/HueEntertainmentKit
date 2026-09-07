import Foundation
import NIOCore

public struct HueStreamPacketEncoder: Sendable {
    public init() {}

    public func encode(configurationID: UUID, sequence: UInt8, frame: HueFrame) -> ByteBuffer {
        var buffer = header(configurationID: configurationID, sequence: sequence, colorSpace: .rgb,
            channelCount: frame.colors.count)
        for entry in frame.colors {
            buffer.writeInteger(entry.channelID)
            buffer.writeInteger(Self.quantize(entry.color.red), endianness: .big)
            buffer.writeInteger(Self.quantize(entry.color.green), endianness: .big)
            buffer.writeInteger(Self.quantize(entry.color.blue), endianness: .big)
        }
        return buffer
    }

    public func encode(configurationID: UUID, sequence: UInt8, frame: HueXYFrame) -> ByteBuffer {
        var buffer = header(configurationID: configurationID, sequence: sequence, colorSpace: .xyBrightness,
            channelCount: frame.colors.count)
        for entry in frame.colors {
            buffer.writeInteger(entry.channelID)
            buffer.writeInteger(Self.quantize(entry.color.x), endianness: .big)
            buffer.writeInteger(Self.quantize(entry.color.y), endianness: .big)
            buffer.writeInteger(Self.quantize(entry.color.brightness), endianness: .big)
        }
        return buffer
    }

    private func header(
        configurationID: UUID, sequence: UInt8, colorSpace: HueColorSpace, channelCount: Int
    ) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: 52 + channelCount * 7)
        buffer.writeString("HueStream")
        buffer.writeBytes([0x02, 0x00, sequence, 0x00, 0x00, colorSpace.rawValue, 0x00])
        buffer.writeString(configurationID.uuidString.lowercased())
        return buffer
    }

    private static func quantize(_ value: Double) -> UInt16 {
        UInt16((value * Double(UInt16.max)).rounded())
    }
}
