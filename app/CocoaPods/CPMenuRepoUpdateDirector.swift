import Cocoa

class CPMenuRepoUpdateDirector: NSObject {
  let repoCoordinator = CPSourceRepoCoordinator()

  // The thing that you click on, in the main menu
  @IBOutlet weak var sourceReposMenuItem: NSMenuItem!

  // The representation of the things that would show when clicked
  @IBOutlet weak var sourceReposMenu: NSMenu!

  override func awakeFromNib() {
    super.awakeFromNib()

    // Don't let it be clickable when there's nothing to show
    sourceReposMenuItem.enabled = false
    sourceReposMenu.removeAllItems()

    // Once everything's finished then we start looking for repo sources,
    // and re-run it after every pod install/update, which may have
    // added new sources

    for key in [NSApplicationDidFinishLaunchingNotification, "CPInstallCompleted"] {
      let center = NSNotificationCenter.defaultCenter()
      center.addObserver(self, selector: #selector(lookForSources), name:key , object: nil)
    }
  }

  func lookForSources() {
    repoCoordinator.getSourceRepos { sources in
      /// This can be on any thread, we want to do GUI work though
      dispatch_async(dispatch_get_main_queue()) {
       self.createMenuForSources(sources)
      }
    }
  }

  func createMenuForSources(sources: [CPSourceRepo]) {
    sourceReposMenu.removeAllItems()
    sourceReposMenuItem.enabled = !sources.isEmpty

    let menuItems = sources.map(menuItemForRepo)
    for menu in menuItems { sourceReposMenu.addItem(menu) }
  }

  func menuItemForRepo(source: CPSourceRepo) -> NSMenuItem {
    let menuItem = NSMenuItem()
    menuItem.view = CPSourceMenuView(source:source)
    menuItem.representedObject = source
    return menuItem
  }
}

class CPSourceMenuView: NSView {

  // I know, it's a weird one, but with this textfield
  // and that custom drawRect, we get the right highlight
  // for an NSMenuItem in all it's many possible states. :)
  var backgroundHighlightView: NSTextField!

  // 
  var titleLabel: NSTextField!
  var subtitleLabel: NSTextField!
  var updateButton: NSButton!
  var progress: NSProgressIndicator!

  var containsMouse = false {
    didSet {
      setNeedsDisplayInRect(bounds)
    }
  }

  // Orta uses a dark menu bar, this was my favourite
  // feature in Yosemite, I used to hack this in before.

  var menuIsDarkMode: Bool {
    let appearance =  NSAppearance.currentAppearance()
    return appearance.name.hasPrefix("NSAppearanceNameVibrantDark")
  }

  var source: CPSourceRepo? {
    return enclosingMenuItem?.representedObject as? CPSourceRepo
  }

  convenience init(source: CPSourceRepo) {
    let frame = CGRect(x: 0, y: 0, width: 400, height: 60)
    self.init(frame: frame)

    backgroundHighlightView = label(bounds)
    addSubview(backgroundHighlightView)

    let titleRect = CGRect(x: 20, y: 30, width: 240, height: 20)
    titleLabel = label(titleRect)
    titleLabel.stringValue = source.displayName
    titleLabel.font = NSFont.menuBarFontOfSize(15)
    addSubview(titleLabel)

    let subtitleRect = CGRect(x: 20, y: 10, width: 240, height: 20)
    subtitleLabel = label(subtitleRect)
    subtitleLabel.stringValue = source.displayAddress
    subtitleLabel.font = NSFont.menuBarFontOfSize(14)
    addSubview(subtitleLabel)

    let buttonRect = CGRect(x: 400-20-60, y: 20, width: 60, height: 20)
    updateButton = whiteBorderedButton("Update", frame: buttonRect)
    updateButton.enabled = false
    updateButton.hidden = true
    updateButton.bind("hidden", toObject:source, withKeyPath: "isUpdatingRepo", options: nil)
    addSubview(updateButton)

    let progressRect = CGRect(x: 400-20-40, y: 20, width: 20, height: 20)
    progress = NSProgressIndicator(frame: progressRect)
    progress.style = .SpinningStyle
    progress.displayedWhenStopped = false
    progress.bind("animate", toObject: source, withKeyPath: "isUpdatingRepo", options: nil)
    addSubview(progress)
  }

  func label(frame: CGRect) -> NSTextField {
    let label = CPNoFancyTransparencyTextField(frame: frame)
    label.bezeled = false
    label.drawsBackground = false
    label.editable = false
    label.selectable = false
    label.usesSingleLineMode = true
    return label
  }

  func whiteBorderedButton(title: String, frame: CGRect) -> NSButton {
    let button = NSButton(frame: frame)
    let updateCell = CPBorderedButtonCell(textCell: title)
    updateCell.imageDimsWhenDisabled = false
    updateCell.imageScaling = .ScaleAxesIndependently

    button.cell = updateCell
    button.bordered = false
    button.image = NSImage(named: "TransparentButtonBG")
    button.imagePosition = .ImageOverlaps
    return button
  }

  // The drawing is handled inside a drawrect, as we need
  // to handle the background ourselves.

  override func drawRect(dirtyRect: NSRect) {
    guard let source = source else { return }

    if containsMouse {
      titleLabel.textColor = .selectedMenuItemTextColor();
      drawSelectionBackground(dirtyRect)
      updateButton.hidden = source.isUpdatingRepo

    } else {
      titleLabel.textColor = menuIsDarkMode ? .whiteColor() : .textColor()
      updateButton.hidden = true
      super.drawRect(dirtyRect)
    }
  }

  func drawSelectionBackground(dirtyRect: CGRect) {
    // Taken from:
    // https://gist.github.com/joelcox/28de2f0cb21ea47bd789

    NSColor.selectedMenuItemColor().set()
    NSRectFillUsingOperation(dirtyRect, .CompositeSourceOver);

    if (dirtyRect.size.height > 1) {
      let heightMinus1 = dirtyRect.size.height - 1
      let currentControlTint = NSColor.currentControlTint()
      let startingOpacity: CGFloat = currentControlTint == .BlueControlTint ? 0.16 : 0.09

      let gradient = NSGradient(startingColor: NSColor(white: CGFloat(1.0), alpha:startingOpacity), endingColor:NSColor(white: CGFloat(1.0), alpha: 0.0))!
      let startPoint = NSMakePoint(dirtyRect.origin.x, dirtyRect.origin.y + heightMinus1)
      let endPoint = NSMakePoint(dirtyRect.origin.x, dirtyRect.origin.y + 1)
      gradient.drawFromPoint(startPoint, toPoint: endPoint, options:NSGradientDrawsBeforeStartingLocation)

      if currentControlTint == .BlueControlTint {
        NSColor(white: CGFloat(1.0), alpha: CGFloat(0.1)).set()

        let smallerRect = NSMakeRect(dirtyRect.origin.x, dirtyRect.origin.y + heightMinus1, dirtyRect.size.width, CGFloat(1.0))
        NSRectFillUsingOperation(smallerRect, .CompositeSourceOver)
      }
    }
  }

  // Ensure we have one tracking reference to get in/out notifications
  override func updateTrackingAreas() {
    if trackingAreas.isEmpty {
      addTrackingArea(
        NSTrackingArea(rect: bounds, options: [.ActiveWhenFirstResponder, .MouseEnteredAndExited, .EnabledDuringMouseDrag], owner: self, userInfo: nil)
      )
    }
  }

  override func mouseEntered(theEvent: NSEvent) {
    super.mouseEntered(theEvent)
    containsMouse = true
  }

  override func mouseExited(theEvent: NSEvent) {
    super.mouseExited(theEvent)
    containsMouse = false
  }

  override func mouseUp(theEvent: NSEvent) {
    guard let sourceRepo = source else { return }
    sourceRepo.updateRepo(nil)
  }
}

class CPNoFancyTransparencyTextField : NSTextField {
  override var allowsVibrancy: Bool {
    return false
  }
}
