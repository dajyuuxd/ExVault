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
        var cs = chunkSize.littleEndian
        withUnsafeBytes(of: &cs) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // 2. fmt subchunk
        data.append(contentsOf: [0x66, 0x6d, 0x74, 0x20]) // "fmt "
        var subchunk1Size: UInt32 = 16.littleEndian
        withUnsafeBytes(of: &subchunk1Size) { data.append(contentsOf: $0) }
        var audioFormat: UInt16 = 1.littleEndian // 1 = PCM
        withUnsafeBytes(of: &audioFormat) { data.append(contentsOf: $0) }
        var channels = numChannels.littleEndian
        withUnsafeBytes(of: &channels) { data.append(contentsOf: $0) }
        var sRate = sampleRate.littleEndian
        withUnsafeBytes(of: &sRate) { data.append(contentsOf: $0) }
        var bRate = byteRate.littleEndian
        withUnsafeBytes(of: &bRate) { data.append(contentsOf: $0) }
        var bAlign = blockAlign.littleEndian
        withUnsafeBytes(of: &bAlign) { data.append(contentsOf: $0) }
        var bps = bitsPerSample.littleEndian
        withUnsafeBytes(of: &bps) { data.append(contentsOf: $0) }

        // 3. data subchunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        var ds = dataSize.littleEndian
        withUnsafeBytes(of: &ds) { data.append(contentsOf: $0) }

        // 4. Zero-filled audio samples
        data.append(Data(repeating: 0, count: Int(dataSize)))

        return data
    }
}
