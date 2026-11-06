// Silent WAV PCM generator for KeepAlive audio loop.
import Foundation

public enum SilentWav {
    /// Generates a standard WAV file (PCM 16-bit mono 8000Hz) with all-zero sample bytes.
    /// Size: 44 header bytes + 16000 * seconds data bytes.
    public static func make(seconds: Int) -> Data {
        let sec = max(1, seconds)
        let sampleRate: UInt32 = 8000
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8) // 16000 bytes/sec
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8) // 2 bytes
        let dataSize: UInt32 = UInt32(byteRate) * UInt32(sec) // 16000 * sec
        let chunkSize: UInt32 = 36 + dataSize

        var data = Data(capacity: Int(44 + dataSize))

        // 1. RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        appendUInt32LE(chunkSize, to: &data)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // 2. fmt subchunk
        data.append(contentsOf: [0x66, 0x6d, 0x74, 0x20]) // "fmt "
        appendUInt32LE(16, to: &data) // subchunk1Size = 16
        appendUInt16LE(1, to: &data)  // audioFormat = 1 (PCM)
        appendUInt16LE(numChannels, to: &data)
        appendUInt32LE(sampleRate, to: &data)
        appendUInt32LE(byteRate, to: &data)
        appendUInt16LE(blockAlign, to: &data)
        appendUInt16LE(bitsPerSample, to: &data)

        // 3. data subchunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        appendUInt32LE(dataSize, to: &data)

        // 4. Zero-filled audio samples
        data.append(Data(repeating: 0, count: Int(dataSize)))

        return data
    }

    private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private static func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }
}
