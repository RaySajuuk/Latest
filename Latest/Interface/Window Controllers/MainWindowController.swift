//
//  MainWindowController.swift
//  Latest
//
//  Created by Max Langer on 27.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa

/**
 This class controls the main window of the app. It includes the list of apps that have an update available as well as the release notes for the specific update.
 */
class MainWindowController: NSWindowController, NSMenuItemValidation, NSMenuDelegate, UpdateCheckProgressReporting {
    
	/// Encapsulates the main window items with their according tag identifiers
	private enum MainMenuItem: Int {
		case latest = 0, file, edit, view, window, help
	}
    
    /// The list view holding the apps
    lazy var listViewController : UpdateTableViewController = {
		let splitViewController = self.contentViewController as? NSSplitViewController
        guard let firstItem = splitViewController?.splitViewItems[0], let controller = firstItem.viewController as? UpdateTableViewController else {
                return UpdateTableViewController()
        }
		
		// Override sidebar collapsing behavior
		firstItem.canCollapse = false
        
        return controller
    }()
    
    /// The detail view controller holding the release notes
    lazy var releaseNotesViewController : ReleaseNotesViewController = {
        guard let splitViewController = self.contentViewController as? NSSplitViewController,
            let secondItem = splitViewController.splitViewItems[1].viewController as? ReleaseNotesViewController else {
                return ReleaseNotesViewController()
        }
        
        return secondItem
    }()
    
    /// The progress indicator showing how many apps have been checked for updates
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    
    /// The button that triggers an reload/recheck for updates
    @IBOutlet weak var reloadButton: NSButton!
    @IBOutlet weak var reloadTouchBarButton: NSButton!
    
    /// The button that triggers all available updates to be done
    @IBOutlet weak var updateAllButton: NSButton!
        
    override func windowDidLoad() {
        super.windowDidLoad()
    
		self.window?.titlebarAppearsTransparent = true

		if #available(macOS 11.0, *) {
			self.window?.toolbarStyle = .unified
			self.window?.title = Bundle.main.localizedInfoDictionary?[kCFBundleNameKey as String] as! String
		} else {
			self.window?.titleVisibility = .hidden
		}
        
		// Set ourselves as the view menu delegate
		NSApplication.shared.mainMenu?.item(at: MainMenuItem.view.rawValue)?.submenu?.delegate = self
		
		UpdateCheckCoordinator.shared.progressDelegate = self
        
        self.window?.makeFirstResponder(self.listViewController)
        self.window?.delegate = self
        self.setDefaultWindowPosition(for: self.window!)
        
        self.listViewController.checkForUpdates()
        self.listViewController.releaseNotesViewController = self.releaseNotesViewController

        if let splitViewController = self.contentViewController as? NSSplitViewController {
            let detailItem = splitViewController.splitViewItems[1]
            detailItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings
        }
    }

    
    // MARK: - Action Methods
    
    /// Reloads the list / checks for updates
    @IBAction func reload(_ sender: Any?) {
        self.listViewController.checkForUpdates()
    }
    
    /// Open all apps that have an update available. If apps from the Mac App Store are there as well, open the Mac App Store
    @IBAction func updateAll(_ sender: Any?) {
		// Separate app store updates from the others
		let apps = UpdateCheckCoordinator.shared.appProvider.updatableApps
		let nonAppStoreApps = apps.filter { app in
			app.source != .appStore
		}
		
		// If more than one app store update is available, open the Updates page, update only non-App Store apps individually
		let combineMacAppStoreUpdates = (apps.count - nonAppStoreApps.count > 1)
		if combineMacAppStoreUpdates {
			NSWorkspace.shared.open(URL(string: "macappstore://showUpdatesPage")!)
		}
		(combineMacAppStoreUpdates ? nonAppStoreApps : apps).forEach({ app in
			if !app.isUpdating {
				app.performUpdate()
			}
		})
    }
    	
	@IBAction func performFindPanelAction(_ sender: Any?) {
		self.window?.makeFirstResponder(self.listViewController.searchField)
	}
    
	@IBAction func visitWebsite(_ sender: NSMenuItem?) {
		NSWorkspace.shared.open(URL(string: "https://max.codes/latest")!)
    }
	
	@IBAction func donate(_ sender: NSMenuItem?) {
		NSWorkspace.shared.open(URL(string: "https://max.codes/latest/donate/")!)
	}
    
    
    // MARK: Menu Item ShowIgnoredUpdatesKeytion

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else {
            return true
        }
        
        switch action {
        case #selector(updateAll(_:)):
			return UpdateCheckCoordinator.shared.appProvider.updatableApps.count != 0
        case #selector(reload(_:)):
            return self.reloadButton.isEnabled
		case #selector(performFindPanelAction(_:)):
			// Only allow the find item
			return menuItem.tag == 1
        default:
            return true
        }
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.forEach { (menuItem) in
            guard let action = menuItem.action else { return }
            
            switch action {
			case #selector(toggleShowInstalledUpdates(_:)):
                menuItem.state = AppListSettings.shared.showInstalledUpdates ? .on : .off
			case #selector(toggleShowIgnoredUpdates(_:)):
                menuItem.state = AppListSettings.shared.showIgnoredUpdates ? .on : .off
			case #selector(toggleShowUnsupportedUpdates(_:)):
				menuItem.state = AppListSettings.shared.showUnsupportedUpdates ? .on : .off
            default:
                ()
            }
        }
    }
    
    
    // MARK: - Update Checker Progress Delegate
	
	func updateCheckerDidStartScanningForApps(_ updateChecker: UpdateCheckCoordinator) {
		// Disable UI
        self.reloadButton.isEnabled = false
        self.reloadTouchBarButton.isEnabled = false
		
		// Setup indeterminate progress indicator
		self.progressIndicator.isIndeterminate = true
        self.progressIndicator.isHidden = false
		self.progressIndicator.startAnimation(updateChecker)
	}
    
    /// This implementation activates the progress indicator, sets its max value and disables the reload button
	func updateChecker(_ updateChecker: UpdateCheckCoordinator, didStartCheckingApps numberOfApps: Int) {
		// Setup progress indicator
		self.progressIndicator.isIndeterminate = false
        self.progressIndicator.doubleValue = 0
        self.progressIndicator.maxValue = Double(numberOfApps - 1)
	}
    
    /// Update the progress indicator
	func updateChecker(_ updateChecker: UpdateCheckCoordinator, didCheckApp: App) {
		self.progressIndicator.increment(by: 1)
    }
	
	func updateCheckerDidFinishCheckingForUpdates(_ updateChecker: UpdateCheckCoordinator) {
		self.reloadButton.isEnabled = true
		self.reloadTouchBarButton.isEnabled = true
		self.progressIndicator.isHidden = true
        self.updateAllButton.isEnabled = UpdateCheckCoordinator.shared.appProvider.updatableApps.count != 0
	}
    
	
	// MARK: - Actions
	
	@IBAction func toggleShowInstalledUpdates(_ sender: NSMenuItem?) {
		AppListSettings.shared.showInstalledUpdates = !AppListSettings.shared.showInstalledUpdates
	}
	
	@IBAction func toggleShowIgnoredUpdates(_ sender: NSMenuItem?) {
		AppListSettings.shared.showIgnoredUpdates = !AppListSettings.shared.showIgnoredUpdates
	 }
	
	@IBAction func toggleShowUnsupportedUpdates(_ sender: NSMenuItem?) {
		AppListSettings.shared.showUnsupportedUpdates = !AppListSettings.shared.showUnsupportedUpdates
	}

    
    // MARK: - Private Methods
    	
    private func showReleaseNotes(_ show: Bool, animated: Bool) {
        guard let splitViewController = self.contentViewController as? NSSplitViewController else {
            return
        }
        
        let detailItem = splitViewController.splitViewItems[1]
        
        if animated {
            detailItem.animator().isCollapsed = !show
        } else {
            detailItem.isCollapsed = !show
        }
        
        if !show {
            // Deselect current app
            self.listViewController.selectApp(at: nil)
        }
    }
	
}

extension MainWindowController: NSWindowDelegate {
    
    private static let WindowSizeKey = "WindowSizeKey"

    // This will be called before decodeRestorableState
    func setDefaultWindowPosition(for window: NSWindow) {
        guard let screen = window.screen?.frame else { return }
        
        var rect = NSRect(x: 0, y: 0, width: 360, height: 500)
        rect.origin.x = screen.width / 2 - rect.width / 2
        rect.origin.y = screen.height / 2 - rect.height / 2
        
        window.setFrame(rect, display: true)
    }
    
    func window(_ window: NSWindow, willEncodeRestorableState state: NSCoder) {
        state.encode(window.frame, forKey: MainWindowController.WindowSizeKey)
    }
    
    func window(_ window: NSWindow, didDecodeRestorableState state: NSCoder) {
        window.setFrame(state.decodeRect(forKey: MainWindowController.WindowSizeKey), display: true)
    }
	
	func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
		// Always position sheets at the top of the window, ignoring toolbar insets
		return NSRect(x: rect.minX, y: window.frame.height, width: rect.width, height: rect.height)
	}
    
}
