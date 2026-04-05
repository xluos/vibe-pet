import SwiftUI

struct PetView: View {
    let state: PetState

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
            Canvas { context, size in
                let frame = frameIndex(for: timeline.date)
                drawCat(context: context, size: size, frame: frame)
            }
        }
    }

    private var frameInterval: Double {
        switch state {
        case .idle: return 0.5
        case .active: return 0.17
        case .needsAttention: return 0.2
        case .sleeping: return 1.0
        }
    }

    private func frameIndex(for date: Date) -> Int {
        let total = frameCount
        let tick = Int(date.timeIntervalSinceReferenceDate / frameInterval)
        return tick % total
    }

    private var frameCount: Int {
        switch state {
        case .idle: return 2
        case .active: return 4
        case .needsAttention: return 4
        case .sleeping: return 2
        }
    }

    // MARK: - Pixel Cat Drawing

    private func drawCat(context: GraphicsContext, size: CGSize, frame: Int) {
        let pixels = spriteData(frame: frame)
        let gridSize = pixels.count
        guard gridSize > 0 else { return }
        let pixelW = size.width / CGFloat(pixels[0].count)
        let pixelH = size.height / CGFloat(gridSize)

        for (row, line) in pixels.enumerated() {
            for (col, pixel) in line.enumerated() {
                guard pixel > 0 else { continue }
                let color = colorForPixel(pixel)
                let rect = CGRect(
                    x: CGFloat(col) * pixelW,
                    y: CGFloat(row) * pixelH,
                    width: pixelW + 0.5, // slight overlap to avoid gaps
                    height: pixelH + 0.5
                )
                context.fill(Path(rect), with: .color(color))
            }
        }
    }

    private func colorForPixel(_ value: UInt8) -> Color {
        switch value {
        case 1: return .white          // outline / body
        case 2: return .orange         // accent (ears, tail)
        case 3: return .pink           // nose / inner ear
        case 4: return Color(red: 1.0, green: 0.82, blue: 0.18) // eyes
        case 5: return .red            // alert indicator
        default: return .white
        }
    }

    // 12x12 pixel cat sprites
    // 0=transparent, 1=white(body), 2=orange(accent), 3=pink, 4=amber(eyes), 5=red(alert)
    private func spriteData(frame: Int) -> [[UInt8]] {
        switch state {
        case .idle:
            return frame == 0 ? catIdle0 : catIdle1
        case .active:
            return [catRun0, catRun1, catRun2, catRun1][frame]
        case .needsAttention:
            return frame % 2 == 0 ? catAlert0 : catAlert1
        case .sleeping:
            return frame == 0 ? catSleep0 : catSleep1
        }
    }

    // Idle frame 0: sitting, tail right
    private var catIdle0: [[UInt8]] { [
        [0,0,2,0,0,0,0,0,2,0,0,0],
        [0,2,1,2,0,0,0,2,1,2,0,0],
        [0,2,1,1,1,1,1,1,1,2,0,0],
        [0,1,4,1,1,1,1,4,1,1,0,0],
        [0,1,1,1,3,3,1,1,1,1,0,0],
        [0,0,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,0,0,0,0,0,1,2,0,0],
        [0,0,1,0,0,0,0,0,1,0,2,0],
        [0,0,0,0,0,0,0,0,0,0,0,2],
    ] }

    // Idle frame 1: sitting, tail right with a blink
    private var catIdle1: [[UInt8]] { [
        [0,0,2,0,0,0,0,0,2,0,0,0],
        [0,2,1,2,0,0,0,2,1,2,0,0],
        [0,2,1,1,1,1,1,1,1,2,0,0],
        [0,1,1,1,1,1,1,1,1,1,0,0],
        [0,1,1,1,3,3,1,1,1,1,0,0],
        [0,0,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,0,0,0,0,0,1,2,0,0],
        [0,0,1,0,0,0,0,0,1,0,2,0],
        [0,0,0,0,0,0,0,0,0,0,0,2],
    ] }

    // Running frames: side profile, facing left with an upright tail
    private var catRun0: [[UInt8]] { [
        [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,2,0,0],
        [0,0,0,2,0,0,0,0,0,0,2,0],
        [0,0,2,1,2,0,0,0,0,2,0,0],
        [0,3,1,4,1,1,1,1,2,0,0,0],
        [0,1,1,1,1,1,1,1,1,2,0,0],
        [0,0,1,1,1,1,1,1,1,1,0,0],
        [0,0,0,0,1,1,1,1,1,0,0,0],
        [0,0,1,0,0,1,0,0,1,0,0,0],
        [0,1,0,0,0,0,1,0,0,1,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0],
    ] }

    private var catRun1: [[UInt8]] { [
        [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,2,0,0,0,0,0,2,0,0],
        [0,0,2,1,2,0,0,0,0,0,2,0],
        [0,3,1,4,1,1,1,1,2,0,0,0],
        [0,1,1,1,1,1,1,1,1,2,0,0],
        [0,0,1,1,1,1,1,1,1,1,0,0],
        [0,0,0,0,1,1,1,1,1,0,0,0],
        [0,0,0,1,0,1,0,1,0,0,0,0],
        [0,0,0,0,1,0,0,0,1,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0],
    ] }

    private var catRun2: [[UInt8]] { [
        [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,2,0],
        [0,0,0,2,0,0,0,0,0,2,0,0],
        [0,0,2,1,2,0,0,0,0,0,0,0],
        [0,3,1,4,1,1,1,1,2,0,0,0],
        [0,1,1,1,1,1,1,1,1,2,0,0],
        [0,0,1,1,1,1,1,1,1,1,2,0],
        [0,0,0,0,1,1,1,1,1,0,0,0],
        [0,1,0,0,1,0,0,0,1,0,0,0],
        [1,0,0,0,0,1,0,0,0,1,0,0],
        [0,0,0,0,0,0,1,0,0,0,1,0],
        [0,0,0,0,0,0,0,0,0,0,0,0],
    ] }

    // Alert frames (jumping with "!" above)
    private var catAlert0: [[UInt8]] { [
        [0,0,0,0,0,5,0,0,0,0,0,0],
        [0,0,2,0,0,5,0,0,2,0,0,0],
        [0,2,1,2,0,0,0,2,1,2,0,0],
        [0,2,1,1,1,1,1,1,1,2,0,0],
        [0,1,4,1,1,1,1,4,1,1,0,0],
        [0,1,1,1,3,3,1,1,1,1,0,0],
        [0,0,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,1,1,1,1,1,1,0,0,0],
        [0,0,0,1,0,0,0,1,0,0,0,0],
        [0,0,1,0,0,0,0,0,1,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0],
    ] }

    private var catAlert1: [[UInt8]] { [
        [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,5,0,0,0,0,0,0],
        [0,0,2,0,0,5,0,0,2,0,0,0],
        [0,2,1,2,0,0,0,2,1,2,0,0],
        [0,2,1,1,1,1,1,1,1,2,0,0],
        [0,1,4,1,1,1,1,4,1,1,0,0],
        [0,1,1,1,3,3,1,1,1,1,0,0],
        [0,0,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,0,0,0,0,0,1,0,0,0],
        [0,0,1,0,0,0,0,0,1,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0],
    ] }

    // Sleeping frames
    private var catSleep0: [[UInt8]] { [
        [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,1,0],
        [0,0,0,0,0,0,0,0,0,1,1,1],
        [0,2,2,0,0,0,0,0,2,2,0,0],
        [0,2,1,1,1,1,1,1,1,2,0,0],
        [0,1,1,1,1,1,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,1,1,1,0,0],
        [0,0,1,1,1,1,1,1,1,0,0,0],
        [0,2,1,1,1,1,1,1,1,0,0,0],
        [2,0,0,0,0,0,0,0,0,0,0,0],
    ] }

    private var catSleep1: [[UInt8]] { [
        [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,1,0],
        [0,0,0,0,0,0,0,0,0,1,1,1],
        [0,0,0,0,0,0,0,0,0,0,1,0],
        [0,2,2,0,0,0,0,0,2,2,0,0],
        [0,2,1,1,1,1,1,1,1,2,0,0],
        [0,1,1,1,1,1,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,1,1,1,0,0],
        [0,0,1,1,1,1,1,1,1,0,0,0],
        [0,2,1,1,1,1,1,1,1,0,0,0],
        [2,0,0,0,0,0,0,0,0,0,0,0],
    ] }
}
