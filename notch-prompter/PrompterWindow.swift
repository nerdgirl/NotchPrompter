import AppKit
import SwiftUI
import Combine

final class PrompterWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow!
    private let viewModel: PrompterViewModel
    private var cancellables: Set<AnyCancellable> = []

    // Custom drag position (nil = auto-dock under the notch).
    private var customOrigin: CGPoint?
    private var isAdjusting = false
    private static let originXKey = "PrompterCustomOriginX"
    private static let originYKey = "PrompterCustomOriginY"

    init(viewModel: PrompterViewModel) {
        self.viewModel = viewModel
        super.init()

        let contentView = PrompterView(viewModel: viewModel)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: 0
            )).border(Color.black.opacity(0.0), width: 0)

        let hosting = NSHostingView(rootView: contentView)
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = true

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0,
                                width: viewModel.prompterWidth,
                                height: viewModel.prompterHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.hasShadow = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true   // drag anywhere to reposition
        window.contentView = hosting
        window.alphaValue = CGFloat(viewModel.opacity)
        window.delegate = self

        // Restore a previously dragged position, if any.
        let d = UserDefaults.standard
        if d.object(forKey: Self.originXKey) != nil {
            customOrigin = CGPoint(x: d.double(forKey: Self.originXKey),
                                   y: d.double(forKey: Self.originYKey))
        }

        viewModel.$prompterWidth
            .combineLatest(viewModel.$prompterHeight)
            .receive(on: RunLoop.main)
            .sink { [weak self] width, height in
                self?.resizeWindow(width: width, height: height)
            }
            .store(in: &cancellables)

        viewModel.$opacity
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.window.alphaValue = CGFloat(value)
            }
            .store(in: &cancellables)

        viewModel.$selectedScreenIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.resizeWindow(width: self.viewModel.prompterWidth, height: self.viewModel.prompterHeight)
            }
            .store(in: &cancellables)

        // Choosing a Position alignment re-docks under the notch (clears the drag position).
        viewModel.$horizontalAlignment
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.customOrigin = nil
                UserDefaults.standard.removeObject(forKey: Self.originXKey)
                UserDefaults.standard.removeObject(forKey: Self.originYKey)
                self.resizeWindow(width: self.viewModel.prompterWidth, height: self.viewModel.prompterHeight)
            }
            .store(in: &cancellables)

        viewModel.$isPrompterVisible
            .receive(on: RunLoop.main)
            .sink { [weak self] isVisible in
                if isVisible { self?.animateShow() } else { self?.animateHide() }
            }
            .store(in: &cancellables)

        viewModel.$hideFromScreenRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] hideFromRecording in
                self?.updateScreenRecordingVisibility(hideFromRecording)
            }
            .store(in: &cancellables)

        updateScreenRecordingVisibility(viewModel.hideFromScreenRecording)
    }

    // MARK: - Drag persistence
    func windowDidMove(_ notification: Notification) {
        guard !isAdjusting else { return }   // ignore our own programmatic moves
        let o = window.frame.origin
        customOrigin = o
        let d = UserDefaults.standard
        d.set(Double(o.x), forKey: Self.originXKey)
        d.set(Double(o.y), forKey: Self.originYKey)
    }

    func show() {
        guard let screen = getSelectedScreen() else {
            window.center(); window.makeKeyAndOrderFront(nil); return
        }
        moveWindow(to: currentFrame(width: viewModel.prompterWidth, height: viewModel.prompterHeight, screen: screen), animate: false)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func resizeWindow(width: CGFloat, height: CGFloat) {
        guard let screen = getSelectedScreen() else { return }
        moveWindow(to: currentFrame(width: width, height: height, screen: screen), animate: true)
    }

    private func moveWindow(to frame: CGRect, animate: Bool) {
        isAdjusting = true
        if animate {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = animationSpeed
                window.animator().setFrame(frame, display: true)
            }, completionHandler: { [weak self] in self?.isAdjusting = false })
        } else {
            window.setFrame(frame, display: true)
            isAdjusting = false
        }
    }

    private func getSelectedScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let index = viewModel.selectedScreenIndex
        if index >= 0 && index < screens.count { return screens[index] }
        return NSScreen.main
    }

    // Frame to use: a dragged position (clamped on-screen) or the notch dock.
    private func currentFrame(width: CGFloat, height: CGFloat, screen: NSScreen) -> CGRect {
        if let o = customOrigin {
            let x = min(max(o.x, screen.frame.minX), screen.frame.maxX - width)
            let y = min(max(o.y, screen.frame.minY), screen.frame.maxY - height)
            return CGRect(x: x, y: y, width: width, height: height)
        }
        return topCenterFrame(width: width, height: height, screen: screen)
    }

    private func topCenterFrame(width: CGFloat, height: CGFloat, screen: NSScreen) -> CGRect {
        let alignmentPosition: CGFloat = {
            switch viewModel.horizontalAlignment {
            case .left: return 0.0
            case .center: return 0.5
            case .right: return 1.0
            }
        }()
        let padding: CGFloat = 20
        let availableWidth = screen.frame.width - width - (padding * 2)
        let x = screen.frame.minX + padding + (availableWidth * alignmentPosition)
        let heightOfBorderTopWithRadiusToHide: CGFloat = 4
        let y = screen.frame.maxY - height + heightOfBorderTopWithRadiusToHide
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func updateScreenRecordingVisibility(_ hideFromRecording: Bool) {
        window.sharingType = hideFromRecording ? .none : .readOnly
    }

    private let animationSpeed = 0.25

    private func animateShow() {
        guard let screen = getSelectedScreen() else { return }
        let finalFrame = currentFrame(width: viewModel.prompterWidth, height: viewModel.prompterHeight, screen: screen)
        var startFrame = finalFrame
        startFrame.origin.y = screen.frame.maxY
        isAdjusting = true
        window.setFrame(startFrame, display: false)
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationSpeed
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(finalFrame, display: true)
        }, completionHandler: { [weak self] in self?.isAdjusting = false })
    }

    private func animateHide() {
        guard let screen = getSelectedScreen() else { window.orderOut(nil); return }
        var targetFrame = window.frame
        targetFrame.origin.y = screen.frame.maxY
        isAdjusting = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationSpeed
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(targetFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.window.orderOut(nil)
            self?.isAdjusting = false
        })
    }
}
