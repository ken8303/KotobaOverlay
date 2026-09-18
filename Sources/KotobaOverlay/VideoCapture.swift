import Foundation

/// Screen selection uses bottom-left coordinates. Crop before OCR so unrelated
/// webpage text never competes with the video's subtitles.
func videoCaptureRect(_ video: CGRect, subtitlesOnly: Bool) -> CGRect {
    guard subtitlesOnly else { return video }
    return CGRect(x: video.minX, y: video.minY, width: video.width, height: video.height * 0.4)
}

// Window capture coordinates have their origin at the top left.
func trackedVideoCrop(region: CGRect, windowSize: CGSize, fullscreen: Bool, subtitlesOnly: Bool) -> CGRect {
    let bounds = CGRect(origin: .zero, size: windowSize)
    var crop = fullscreen ? bounds : CGRect(x: region.minX * windowSize.width, y: region.minY * windowSize.height, width: region.width * windowSize.width, height: region.height * windowSize.height).intersection(bounds)
    if subtitlesOnly { crop.origin.y += crop.height * 0.6; crop.size.height *= 0.4 }
    return crop
}

func isFullscreenVideoWindow(_ window: CGRect, display: CGRect) -> Bool {
    abs(window.minX - display.minX) <= 3 && abs(window.minY - display.minY) <= 3 &&
    abs(window.width - display.width) <= 3 && abs(window.height - display.height) <= 3
}
