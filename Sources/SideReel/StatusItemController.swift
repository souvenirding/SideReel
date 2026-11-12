import AppKit
import Combine
import SlideshowKit
import SwiftUI

final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let slideshow: SlideshowController
    private var cancellable: AnyCancellable?

    init(slideshow: SlideshowController) {
        self.slideshow = slideshow
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "SideReel")
            button.action = #selector(togglePanel)
            button.target = self
        }

        let hosting = NSHostingController(rootView: PanelView().environmentObject(slideshow))
        hosting.sizingOptions = [.intrinsicContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self

        cancellable = slideshow.$isRunning.sink { [weak self] running in
            self?.statusItem.button?.image = NSImage(
                systemSymbolName: running ? "photo.fill.on.rectangle.fill" : "photo.on.rectangle.angled",
                accessibilityDescription: "SideReel"
            )
        }
    }

    func showPanel() {
        guard let button = statusItem.button else { return }
        if let hosting = popover.contentViewController {
            hosting.view.layoutSubtreeIfNeeded()
            let size = hosting.view.fittingSize
            if size.width > 0, size.height > 0 {
                popover.contentSize = size
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPanel()
        }
    }
}