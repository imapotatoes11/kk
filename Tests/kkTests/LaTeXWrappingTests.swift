import AppKit
import SwiftMath
import SwiftUI
import XCTest
@testable import kk

final class LaTeXWrappingTests: XCTestCase {
    @MainActor
    func testLongDisplayEquationWrapsAtOperatorsWithoutSplittingFractionsOrDelimiters() throws {
        _ = NSApplication.shared
        let source = #"f(x) = \frac{a+b+c}{d+e+f} + \sqrt{x^2+y^2} + (p+q+r) + u + v + w + z"#
        let wrapped = LaTeXWrapping.equation(source, width: 190, fontSize: 18)
        XCTAssertTrue(wrapped.contains(#"\begin{gather}"#))
        XCTAssertTrue(wrapped.contains(#"\\"#))
        var error: NSError?
        XCTAssertNotNil(MTMathListBuilder.build(fromString: wrapped, error: &error))
        XCTAssertNil(error)
        let original = try XCTUnwrap(MTMathListBuilder.build(fromString: source))
        XCTAssertTrue(original.atoms.contains { $0.type == .fraction })
        XCTAssertEqual(LaTeXWrapping.equation(source, width: 2000, fontSize: 18), source)
        XCTAssertEqual(LaTeXWrapping.equation(#"\frac{a+b+c+d+e+f}{x+y+z}"#, width: 60, fontSize: 18), #"\frac{a+b+c+d+e+f}{x+y+z}"#)
    }

    @MainActor
    func testAbsoluteValueDelimitersStayTogetherWhenSurroundingTermsWrap() {
        _ = NSApplication.shared
        let wrapped = LaTeXWrapping.equation("f(x)=|a+b+c+d+e+f+g|+u+v+w+z", width: 120, fontSize: 18)
        XCTAssertTrue(wrapped.contains(#"\begin{gather}"#))
        for row in wrapped.components(separatedBy: #" \\ "#) {
            let bars = row.filter { $0 == "|" || $0 == "‖" }.count
                + row.components(separatedBy: #"\vert"#).count - 1
                + row.components(separatedBy: #"\Vert"#).count - 1
            XCTAssertTrue(bars.isMultiple(of: 2), "Absolute-value bars must not be split between rows")
        }
    }

    @MainActor
    func testRewriterLeavesCodeAndInlineMathAndExistingMultilineMathUntouched() {
        let equation = "a+b+c+d+e+f+g+h+i+j+k+l+m+n"
        let source = "```latex\n$$" + equation + "$$\n```\n`$$" + equation + "$$`\nInline $" + equation + "$\n\n$$" + equation + "$$"
        let rewritten = LaTeXWrapping.markdown(source, width: 120, fontSize: 18)
        XCTAssertTrue(rewritten.hasPrefix(source.components(separatedBy: "\n\n")[0]))
        XCTAssertEqual(rewritten.components(separatedBy: #"\begin{gather}"#).count, 2)
        let aligned = #"\begin{aligned}a&=b+c\\d&=e+f\end{aligned}"#
        XCTAssertEqual(LaTeXWrapping.equation(aligned, width: 80, fontSize: 18), aligned)
    }

    @MainActor
    func testWrappedMathActuallyUsesMultipleRowsAtTheOriginalFontSize() async throws {
        _ = NSApplication.shared
        let equation = "a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p+q+r"
        let host = NSHostingView(rootView: ResponseView(markdown: "$$" + equation + "$$", isStreaming: false, textSize: 18)
            .environment(\.kkWrapLaTeX, true).frame(width: 240).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        let labels = views(host).compactMap { $0 as? MTMathUILabel }
        let wrapped = try XCTUnwrap(labels.first { $0.latex.contains(#"\begin{gather}"#) })
        XCTAssertNil(wrapped.error)
        XCTAssertEqual(wrapped.fontSize, 20)
        XCTAssertGreaterThan(wrapped.fittingSize.height, 40)
        XCTAssertLessThanOrEqual(wrapped.fittingSize.width, 240)
    }
}
