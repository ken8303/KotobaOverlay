import CoreMedia

/// Use exact output-sample durations, not capture-packet durations after resampling.
/// Capture timestamps preserve real gaps; the output cursor prevents overlap from
/// converter buffering, rounding, or small backwards jumps in the capture clock.
struct AudioTimeline {
    private var origin: CMTime?
    private(set) var nextEnd = CMTime.zero

    mutating func startTime(captureTime: CMTime, outputFrames: Int, sampleRate: Int32) -> CMTime? {
        guard captureTime.isNumeric, outputFrames > 0, sampleRate > 0 else { return nil }
        if origin == nil { origin = captureTime }
        let relative = CMTimeSubtract(captureTime, origin!)
        let requested = CMTimeConvertScale(relative, timescale: sampleRate, method: .roundTowardPositiveInfinity)
        let cursor = CMTimeConvertScale(nextEnd, timescale: sampleRate, method: .roundTowardPositiveInfinity)
        let start = CMTimeMaximum(.zero, CMTimeMaximum(requested, cursor))
        nextEnd = CMTimeAdd(start, CMTime(value: Int64(outputFrames), timescale: sampleRate))
        return start
    }
}
