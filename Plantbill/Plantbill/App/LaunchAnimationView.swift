import CoreText
import SwiftUI
import UIKit

/// The opening animation, shown once each time the app starts, over the app
/// while it loads underneath: the leaf springs in, "Plantbill" is written out
/// stroke by stroke and then filled, and "Powered by Dofida" settles in below.
///
/// About two seconds in all — long enough to feel finished, short enough that
/// a shop owner with a customer waiting never feels held up. With Reduce
/// Motion on it is a brief, still fade instead.
struct LaunchAnimationView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var leafShown = false
    @State private var writing: CGFloat = 0
    @State private var filled = false
    @State private var creditShown = false

    private static let word = WordOutline(text: "Plantbill", fontSize: 46)

    var body: some View {
        ZStack {
            PlantbillColor.background.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(PlantbillColor.green)
                    .scaleEffect(leafShown ? 1 : 0.3)
                    .rotationEffect(.degrees(leafShown ? 0 : -40))
                    .opacity(leafShown ? 1 : 0)

                ZStack {
                    // The pen: the letters' outlines traced left to right…
                    Self.word
                        .trim(from: 0, to: writing)
                        .stroke(
                            PlantbillColor.textPrimary,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                    // …then the ink fills in.
                    Self.word
                        .fill(PlantbillColor.textPrimary)
                        .opacity(filled ? 1 : 0)
                }
                .frame(width: Self.word.size.width, height: Self.word.size.height)
            }
            .offset(y: -24)

            VStack {
                Spacer()
                PoweredByDofida()
                    .opacity(creditShown ? 1 : 0)
                    .offset(y: creditShown ? 0 : 10)
                    .padding(.bottom, PlantbillSpacing.xl)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Plantbill, powered by Dofida"))
        .task { await play() }
    }

    private func play() async {
        guard !reduceMotion else {
            leafShown = true
            writing = 1
            filled = true
            creditShown = true
            try? await Task.sleep(for: .milliseconds(600))
            onFinished()
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) { leafShown = true }
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(.easeInOut(duration: 1.0)) { writing = 1 }
        try? await Task.sleep(for: .milliseconds(750))
        withAnimation(.easeIn(duration: 0.35)) { filled = true }
        withAnimation(.easeOut(duration: 0.45)) { creditShown = true }
        try? await Task.sleep(for: .milliseconds(850))
        onFinished()
    }
}

/// A word's outline, built from the font's own glyphs so it can be traced as
/// if written, then filled. Letters are added left to right, which is the
/// order `trim` draws them in.
struct WordOutline: Shape {
    private let outline: Path
    let size: CGSize

    init(text: String, fontSize: CGFloat) {
        let base = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: fontSize) } ?? base
        let ctFont = font as CTFont
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))

        let path = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                if let glyphPath = CTFontCreatePathForGlyph(ctFont, glyph, nil) {
                    path.addPath(glyphPath, transform: CGAffineTransform(translationX: position.x, y: position.y))
                }
            }
        }

        // CoreText's y axis points up: flip it, and move the word to the origin.
        let bounds = path.boundingBoxOfPath
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -bounds.minX, ty: bounds.maxY)
        outline = Path(path.copy(using: &flip) ?? path)
        size = bounds.size
    }

    nonisolated func path(in rect: CGRect) -> Path {
        guard size.width > 0, size.height > 0 else { return Path() }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let transform = CGAffineTransform(
            translationX: rect.minX + (rect.width - size.width * scale) / 2,
            y: rect.minY + (rect.height - size.height * scale) / 2
        ).scaledBy(x: scale, y: scale)
        return outline.applying(transform)
    }
}

#Preview {
    LaunchAnimationView {}
}
