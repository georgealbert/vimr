/**
 * Tae Won Ha - http://taewon.de - @hataewon
 * See LICENSE
 */

import Cocoa

final class AttributesRunDrawer {

  var font: NSFont {
    didSet {
      self.updateFontMetrics()
    }
  }

  var linespacing: CGFloat {
    didSet {
      self.updateFontMetrics()
    }
  }

  var usesLigatures: Bool
  private(set) var cellSize: CGSize = .zero
  private(set) var baselineOffset: CGFloat = 0
  private(set) var descent: CGFloat = 0
  private(set) var underlinePosition: CGFloat = 0
  private(set) var underlineThickness: CGFloat = 0

  init(baseFont: NSFont, linespacing: CGFloat, usesLigatures: Bool) {
    self.font = baseFont
    self.linespacing = linespacing
    self.usesLigatures = usesLigatures

    self.updateFontMetrics()
  }

  func draw(
    _ attrsRuns: [AttributesRun],
    defaultAttributes: CellAttributes,
    offset: CGPoint,
    `in` context: CGContext
  ) {
    #if DEBUG
    self.drawByParallelComputation(
      attrsRuns,
      defaultAttributes: defaultAttributes,
      offset: offset,
      in: context
    )
    #else
    let runs = attrsRuns.map { self.fontGlyphRuns(from: $0, offset: offset) }

    for i in 0..<attrsRuns.count {
      self.draw(
        attrsRuns[i],
        fontGlyphRuns: runs[i],
        defaultAttributes: defaultAttributes,
        in: context
      )
    }
    #endif
  }

  private func draw(
    _ run: AttributesRun,
    fontGlyphRuns: [FontGlyphRun],
    defaultAttributes: CellAttributes,
    `in` context: CGContext
  ) {
    context.saveGState()
    defer { context.restoreGState() }

    self.draw(
      backgroundFor: run,
      with: defaultAttributes,
      in: context
    )

    context.setFillColor(
      ColorUtils.cgColorIgnoringAlpha(run.attrs.effectiveForeground)
    )

    fontGlyphRuns.forEach { run in
      CTFontDrawGlyphs(
        run.font,
        run.glyphs,
        run.positions,
        run.glyphs.count,
        context
      )
    }

    if run.attrs.fontTrait.contains(.underline) {
      self.drawUnderline(in: context, fontGlyphRuns: fontGlyphRuns)
    }

    if run.attrs.fontTrait.contains(.undercurl) {
      self.drawUndercurl(
        in: context,
        fontGlyphRuns: fontGlyphRuns,
        color: ColorUtils.cgColorIgnoringAlpha(run.attrs.special)
      )
    }
  }

  private func drawUnderline(in context: CGContext,
                             fontGlyphRuns: [FontGlyphRun]) {
    guard let lastPosition = fontGlyphRuns.last?.positions.last?.x else {
      return
    }

    let x1 = lastPosition + self.cellSize.width
    let x0 = fontGlyphRuns[0].positions[0].x
    let y0 = fontGlyphRuns[0].positions[0].y
    CGRect(x: x0, y: y0 + self.underlinePosition,
           width: x1 - x0, height: self.underlineThickness).fill()
  }

  private func drawUndercurl(in context: CGContext,
                             fontGlyphRuns: [FontGlyphRun],
                             color: CGColor) {
    guard let lastPosition = fontGlyphRuns.last?.positions.last?.x else {
      return
    }

    let x1 = lastPosition + self.cellSize.width
    var x0 = fontGlyphRuns[0].positions[0].x
    let count = Int(floor((x1 - x0) / self.cellSize.width))
    let y0 = fontGlyphRuns[0].positions[0].y - 0.1 * self.cellSize.height
    let w = self.cellSize.width
    let h = 0.5 * self.descent

    context.move(to: CGPoint(x: x0, y: y0))
    for _ in (0..<count) {
      context.addCurve(to: CGPoint(x: x0 + 0.5 * w, y: y0 + h),
                       control1: CGPoint(x: x0 + 0.25 * w, y: y0),
                       control2: CGPoint(x: x0 + 0.25 * w, y: y0 + h))
      context.addCurve(to: CGPoint(x: x0 + w, y: y0),
                       control1: CGPoint(x: x0 + 0.75 * w, y: y0 + h),
                       control2: CGPoint(x: x0 + 0.75 * w, y: y0))
      x0 += w
    }
    context.setStrokeColor(color)
    context.strokePath()
  }

  private let typesetter = Typesetter()

  private func draw(
    backgroundFor run: AttributesRun,
    with defaultAttributes: CellAttributes,
    `in` context: CGContext
  ) {

    if run.attrs.effectiveBackground == defaultAttributes.background { return }

    context.saveGState()
    defer { context.restoreGState() }

    let cellCount = CGFloat(run.cells.endIndex - run.cells.startIndex)
    let backgroundRect = CGRect(
      x: run.location.x,
      y: run.location.y,
      width: cellCount * self.cellSize.width,
      height: self.cellSize.height
    )

    context.setFillColor(
      ColorUtils.cgColorIgnoringAlpha(run.attrs.effectiveBackground)
    )
    context.fill(backgroundRect)
  }

  private func fontGlyphRuns(
    from attrsRun: AttributesRun,
    offset: CGPoint
  ) -> [FontGlyphRun] {
    let font = FontUtils.font(
      adding: attrsRun.attrs.fontTrait, to: self.font
    )

    let typesetFunction = self.usesLigatures
      ? self.typesetter.fontGlyphRunsWithLigatures
      : self.typesetter.fontGlyphRunsWithoutLigatures

    let fontGlyphRuns = typesetFunction(
      attrsRun.cells.map { Array($0.string.utf16) },
      attrsRun.cells.startIndex,
      CGPoint(
        x: offset.x, y: attrsRun.location.y + self.baselineOffset
      ),
      font,
      self.cellSize.width
    )

    return fontGlyphRuns
  }

  private func drawByParallelComputation(
    _ attrsRuns: [AttributesRun],
    defaultAttributes: CellAttributes,
    offset: CGPoint,
    `in` context: CGContext
  ) {
    var result = Array(repeating: [FontGlyphRun](), count: attrsRuns.count)
    DispatchQueue.concurrentPerform(iterations: attrsRuns.count) { i in
      result[i] = self.fontGlyphRuns(from: attrsRuns[i], offset: offset)
    }

    attrsRuns.enumerated().forEach { (i, attrsRun) in
      self.draw(
        attrsRun,
        fontGlyphRuns: result[i],
        defaultAttributes: defaultAttributes,
        in: context
      )
    }
  }

  private func updateFontMetrics() {
    self.cellSize = FontUtils.cellSize(
      of: self.font, linespacing: self.linespacing
    )
    self.baselineOffset = self.cellSize.height - CTFontGetAscent(self.font)
    self.descent = CTFontGetDescent(font)
    self.underlinePosition = CTFontGetUnderlinePosition(font)
    self.underlineThickness = CTFontGetUnderlineThickness(font)
  }
}
