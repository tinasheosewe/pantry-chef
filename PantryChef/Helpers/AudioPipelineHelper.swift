import Foundation

// MARK: - Audio Pipeline Helper
//
// Pure functions for audio data conversion between PCM16 (Realtime API
// format) and Float32 (AVAudioEngine format).  Every function is testable
// without AVFoundation or audio hardware dependencies.

enum AudioPipelineHelper {

    // MARK: - PCM16 ↔ Float32

    /// Converts PCM16 little-endian bytes → Float32 samples in [-1.0, 1.0].
    /// Each sample is 2 bytes (Int16).  Partial trailing bytes are dropped.
    static func pcm16ToFloat32(_ data: Data) -> [Float] {
        let sampleCount = data.count / 2
        guard sampleCount > 0 else { return [] }
        return data.withUnsafeBytes { rawBuf in
            let int16Ptr = rawBuf.bindMemory(to: Int16.self)
            return (0..<sampleCount).map { Float(int16Ptr[$0]) / 32768.0 }
        }
    }

    /// Converts Float32 samples → PCM16 little-endian bytes.
    /// Values outside [-1.0, 1.0) are clamped to Int16 range.
    static func float32ToPCM16(_ samples: [Float]) -> Data {
        guard !samples.isEmpty else { return Data() }
        var data = Data(count: samples.count * 2)
        data.withUnsafeMutableBytes { rawBuf in
            let int16Ptr = rawBuf.bindMemory(to: Int16.self)
            for i in 0..<samples.count {
                let scaled = Int32(samples[i] * 32768.0)
                let clamped = min(max(scaled, Int32(Int16.min)), Int32(Int16.max))
                int16Ptr[i] = Int16(clamped)
            }
        }
        return data
    }

    // MARK: - Base64 ↔ PCM16

    /// Encodes PCM16 data to base64 for the Realtime API `input_audio_buffer.append`.
    static func pcm16ToBase64(_ data: Data) -> String {
        data.base64EncodedString()
    }

    /// Decodes base64 audio from the Realtime API back to PCM16 bytes.
    static func base64ToPCM16(_ base64: String) -> Data? {
        Data(base64Encoded: base64)
    }

    // MARK: - Chunk Threshold

    /// The minimum bytes of PCM16 data to accumulate before flushing
    /// to the player node (~100 ms at the given sample rate, 2 bytes per sample).
    static func chunkThreshold(sampleRate: Double) -> Int {
        Int(sampleRate * 0.1) * 2
    }

    // MARK: - Convenience: fill AVAudioPCMBuffer from PCM16 Data

    /// Writes PCM16 data into a pre-allocated Float32 channel buffer.
    /// Used by `flushPendingAudio` to avoid an intermediate `[Float]` allocation.
    /// - Parameters:
    ///   - data: PCM16 little-endian audio bytes.
    ///   - floatPtr: The destination Float32 buffer (`floatChannelData[0]`).
    ///   - frameCount: Number of frames (samples) to convert.
    static func pcm16ToFloatBuffer(from data: Data, into floatPtr: UnsafeMutablePointer<Float>, frameCount: Int) {
        data.withUnsafeBytes { rawBuf in
            let int16Ptr = rawBuf.bindMemory(to: Int16.self)
            for i in 0..<frameCount {
                floatPtr[i] = Float(int16Ptr[i]) / 32768.0
            }
        }
    }
}
