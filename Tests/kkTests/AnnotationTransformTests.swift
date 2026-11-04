import AppKit
import XCTest
@testable import kk

final class AnnotationTransformTests: XCTestCase {
    func testStrokeHitsChooseTopmostAndIgnoreHollowInterior() {
        let rect = ScreenAnnotation(tool: .rectangle, color: .red, lineWidth: 3, points: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200)])
        XCTAssertNil(AnnotationTransform.hit(at: CGPoint(x: 150, y: 150), marks: [rect], hovered: nil))
        XCTAssertEqual(AnnotationTransform.hit(at: CGPoint(x: 103, y: 150), marks: [rect, rect], hovered: nil), AnnotationHit(index: 1, corner: nil))
        XCTAssertEqual(AnnotationTransform.hit(at: CGPoint(x: 100, y: 100), marks: [rect], hovered: 0), AnnotationHit(index: 0, corner: 0))
        var freehand = rect
        freehand = ScreenAnnotation(tool: .freehand, color: .blue, lineWidth: 3, smoothed: true, points: rect.points)
        XCTAssertTrue(AnnotationTransform.corners(of: freehand).isEmpty)
        XCTAssertTrue(AnnotationTransform.hitsStroke(CGPoint(x: 150, y: 150), mark: freehand))
    }

    func testResizeAllToolsAndCornersKeepsOppositeCornerFixed() {
        for tool in [AnnotationTool.ellipse, .rectangle] {
            for points in [[CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200)], [CGPoint(x: 200, y: 200), CGPoint(x: 100, y: 100)]] {
                let mark = ScreenAnnotation(tool: tool, color: .purple, lineWidth: 5, points: points)
                let handles = AnnotationTransform.corners(of: mark)
                for corner in handles.indices {
                    let target = CGPoint(x: handles[corner].x + (corner == 0 || corner == 3 ? -30 : 30), y: handles[corner].y + (corner < 2 ? -20 : 20))
                    let resized = AnnotationTransform.resized(mark, corner: corner, to: target)
                    let result = AnnotationTransform.corners(of: resized)
                    XCTAssertEqual(result[corner], target)
                    XCTAssertEqual(result[(corner + 2) % 4], handles[(corner + 2) % 4])
                    XCTAssertEqual(resized.color, mark.color)
                    XCTAssertEqual(resized.lineWidth, mark.lineWidth)
                }
            }
        }
        let horizontal = ScreenAnnotation(tool: .arrow, color: .red, lineWidth: 3, points: [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10)])
        XCTAssertTrue(AnnotationTransform.resized(horizontal, corner: 1, to: CGPoint(x: 150, y: 60)).points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @MainActor
    func testCanvasMovesAndResizesExistingMarkWithUndo() throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let doc = AnnotationDocument()
        doc.begin(at: CGPoint(x: 100, y: 100), tool: .ellipse, color: .red, lineWidth: 3)
        doc.move(to: CGPoint(x: 200, y: 200)); doc.finish()
        let original = doc.annotations[0]
        let canvas = AnnotationCanvasView(document: doc, preferences: prefs)
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, 100, 150))
        canvas.mouseDragged(with: try event(.leftMouseDragged, 130, 170))
        canvas.mouseUp(with: try event(.leftMouseUp, 140, 180))
        XCTAssertEqual(doc.annotations.count, 1)
        XCTAssertEqual(doc.annotations[0], AnnotationTransform.moved(original, by: CGPoint(x: 40, y: 30)))
        doc.undo()
        XCTAssertEqual(doc.annotations[0], original)
        canvas.mouseMoved(with: try event(.mouseMoved, 100, 150))
        canvas.mouseMoved(with: try event(.mouseMoved, 100, 100))
        canvas.mouseDown(with: try event(.leftMouseDown, 100, 100))
        canvas.mouseDragged(with: try event(.leftMouseDragged, 60, 60))
        canvas.mouseUp(with: try event(.leftMouseUp, 60, 60))
        XCTAssertEqual(doc.annotations[0].points, [CGPoint(x: 60, y: 60), CGPoint(x: 200, y: 200)])
        doc.undo()
        XCTAssertEqual(doc.annotations[0], original)
    }
}


extension AnnotationTransformTests {
    @MainActor
    func testEraserDeletesTopmostStrokeWithUndoAndDoesNotDrawOrDismiss() throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.annotationTool = .eraser
        let doc = AnnotationDocument()
        for color in [AnnotationColor.red, .blue] {
            doc.begin(at: CGPoint(x: 100, y: 100), tool: .rectangle, color: color, lineWidth: 3)
            doc.move(to: CGPoint(x: 200, y: 200)); doc.finish()
        }
        let originals = doc.annotations
        let canvas = AnnotationCanvasView(document: doc, preferences: prefs)
        canvas.onEmptyClick = { XCTFail("Eraser clicks must not dismiss kk"); return true }
        func click(_ point: CGPoint) {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                canvas.mouseEventForTesting(type, at: point, timestamp: 1)
            }
        }
        click(CGPoint(x: 150, y: 150))
        XCTAssertEqual(doc.annotations, originals, "Hollow interiors are not eraser targets")
        click(CGPoint(x: 100, y: 150))
        XCTAssertEqual(doc.annotations, [originals[0]])
        XCTAssertNil(doc.current)
        doc.undo()
        XCTAssertEqual(doc.annotations, originals)
        doc.clear()
        click(.zero)
        XCTAssertTrue(doc.annotations.isEmpty)
        doc.begin(at: .zero, tool: .eraser, color: .red, lineWidth: 3)
        XCTAssertNil(doc.current, "Eraser must never become a rendered mark")
    }

    @MainActor
    func testHoverDeleteToggleUndoExitAndGestureGuards() throws {
        _ = NSApplication.shared
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let prefs = Preferences(defaults: defaults)
        XCTAssertTrue(prefs.deleteHoveredAnnotation)
        let doc = AnnotationDocument()
        doc.begin(at: CGPoint(x: 100, y: 100), tool: .freehand, color: .red, lineWidth: 3)
        doc.move(to: CGPoint(x: 200, y: 100)); doc.finish()
        let original = doc.annotations
        let canvas = AnnotationCanvasView(document: doc, preferences: prefs)
        let delete = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51))
        canvas.mouseEventForTesting(.mouseMoved, at: CGPoint(x: 150, y: 100))
        prefs.deleteHoveredAnnotation = false
        XCTAssertFalse(Preferences(defaults: defaults).deleteHoveredAnnotation)
        XCTAssertFalse(canvas.handleDeleteShortcut(delete))
        XCTAssertEqual(doc.annotations, original)
        prefs.deleteHoveredAnnotation = true
        doc.isPreparing = true
        XCTAssertFalse(canvas.handleDeleteShortcut(delete))
        doc.isPreparing = false
        canvas.mouseEventForTesting(.leftMouseDown, at: CGPoint(x: 150, y: 100))
        XCTAssertFalse(canvas.handleDeleteShortcut(delete), "Cannot delete during a transform")
        canvas.mouseEventForTesting(.leftMouseDragged, at: CGPoint(x: 150, y: 160))
        canvas.mouseEventForTesting(.leftMouseUp, at: CGPoint(x: 150, y: 160))
        let moved = doc.annotations
        XCTAssertTrue(canvas.handleDeleteShortcut(delete))
        XCTAssertTrue(doc.annotations.isEmpty)
        doc.undo()
        XCTAssertEqual(doc.annotations, moved, "Delete immediately after dragging must target the moved mark")
        doc.undo()
        XCTAssertEqual(doc.annotations, original)
        canvas.mouseEventForTesting(.mouseExited, at: .zero)
        XCTAssertFalse(canvas.handleDeleteShortcut(delete))
        canvas.mouseEventForTesting(.mouseMoved, at: CGPoint(x: 150, y: 100))
        doc.isDrawing = false
        XCTAssertFalse(canvas.handleDeleteShortcut(delete))
    }

    @MainActor
    func testEraserBindingMigrationPreservesConflictsAndClearedBindings() throws {
        for conflict in [false, true] {
            let defaults = UserDefaults(suiteName: UUID().uuidString)!
            var bindings = AnnotationShortcut.defaults
            bindings.removeValue(forKey: "eraser")
            if conflict { bindings["freehand"] = AnnotationShortcut.defaults["eraser"] }
            defaults.set(try JSONEncoder().encode(bindings), forKey: "annotationBindings")
            let prefs = Preferences(defaults: defaults)
            XCTAssertEqual(prefs.annotationBindings["eraser"]?.label, conflict ? nil : "X")
            if conflict { XCTAssertEqual(prefs.annotationBindings["freehand"]?.label, "X") }
            prefs.annotationBindings.removeValue(forKey: "eraser")
            XCTAssertNil(Preferences(defaults: defaults).annotationBindings["eraser"])
        }
    }

    func testArrowsHaveExactlyTwoIndependentEndpointHandles() {
        for points in [[CGPoint(x: 10, y: 20), CGPoint(x: 90, y: 80)], [CGPoint(x: 90, y: 80), CGPoint(x: 10, y: 20)], [CGPoint(x: 10, y: 20), CGPoint(x: 90, y: 20)]] {
            let mark = ScreenAnnotation(tool: .arrow, color: .red, lineWidth: 3, points: points)
            XCTAssertEqual(AnnotationTransform.corners(of: mark), points)
            for index in 0..<2 {
                let target = CGPoint(x: -50, y: 150)
                let moved = AnnotationTransform.resized(mark, corner: index, to: target)
                XCTAssertEqual(moved.points[index], target)
                XCTAssertEqual(moved.points[1 - index], points[1 - index])
                XCTAssertEqual(AnnotationTransform.hit(at: points[index], marks: [mark], hovered: 0), AnnotationHit(index: 0, corner: index))
            }
        }
    }
}

@MainActor
private extension AnnotationCanvasView {
    func mouseEventForTesting(_ type: NSEvent.EventType, at point: CGPoint, timestamp: TimeInterval = 1) {
        let event = NSEvent.mouseEvent(with: type == .mouseExited ? .mouseMoved : type, location: point, modifierFlags: [], timestamp: timestamp, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        switch type {
        case .mouseMoved: mouseMoved(with: event)
        case .mouseExited: mouseExited(with: event)
        case .leftMouseDown: mouseDown(with: event)
        case .leftMouseDragged: mouseDragged(with: event)
        case .leftMouseUp: mouseUp(with: event)
        default: break
        }
    }
}
