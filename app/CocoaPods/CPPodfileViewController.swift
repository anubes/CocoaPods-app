import Cocoa

/// UIVIewController to represent the Podfile editor
/// It's scope is keeping track of the user project,
/// handling / exposing tabs and providing a central
/// access place for mutable state within the Podfile
/// section of CocoaPods.app

class CPPodfileViewController: NSViewController, NSTabViewDelegate {

  var userProject:CPUserProject!
  dynamic var installAction: CPInstallAction!

  @IBOutlet weak var actionTitleLabel: NSTextField!
  @IBOutlet weak var documentIconContainer: NSView!

  var pluginCoordinator: CPPodfilePluginCoordinator!
  @IBOutlet var sourcesCoordinator: CPSourceRepoCoordinator!

  @IBOutlet var tabViewDelegate: CPTabViewDelegate!

  override func viewWillAppear() {

    // The userProject is DI'd in after viewDidLoad
    installAction = CPInstallAction(userProject: userProject, notify: true)

    // The view needs to be added to a window before we can use
    // the window to pull out to the document icon from the window

    guard
      let window = view.window as? CPModifiedDecorationsWindow,
      let documentIcon = window.documentIconButton else {
        return print("Window type is not CPModifiedDecorationsWindow")
    }

    // Grab the document icon and move it into the space on our 
    // custom title bar
    documentIcon.frame = documentIcon.bounds
    documentIconContainer.addSubview(documentIcon)

    // Default the bottom label to hidden
    hideWarningLabel(false)

    // Check for whether we need to install plugins
    pluginCoordinator = CPPodfilePluginCoordinator(controller: self)
    pluginCoordinator.comparePluginsWithinUserProject(userProject)

    // Keep track of active source repos
    sourcesCoordinator.getSourceRepos()

    // Makes the tabs highlight correctly
    tabController.hiddenTabDelegate = tabViewDelegate

    // When integrating into one xcodeproj
    // we should show "Podfile for ProjectName" instead
    userProject.registerForFullMetadataCallback {
      guard let targets = self.userProject.xcodeIntegrationDictionary["projects"] as? [String:AnyObject] else { return }
      if targets.keys.count == 1 {
        let project = targets.keys.first!
        let url = NSURL(fileURLWithPath: project)
        let name = url.lastPathComponent!.stringByReplacingOccurrencesOfString(".xcproj", withString: "")
        self.actionTitleLabel.stringValue = "Podfile for \(name)"
      }
    }
  }

  var tabController: CPHiddenTabViewController {
    return childViewControllers.filter { $0.isKindOfClass(CPHiddenTabViewController) }.first! as! CPHiddenTabViewController
  }

  @IBAction func install(obj: AnyObject) {
    userProject.saveDocument(self)
    let options = InstallOptions(verbose: false)
    installAction.performAction(.Install(options: options))
    showConsoleTab(self)
  }

  @IBAction func installVerbose(obj: AnyObject) {
    userProject.saveDocument(self)
    let options = InstallOptions(verbose: true)
    installAction.performAction(.Install(options: options))
    showConsoleTab(self)
  }

  @IBAction func installUpdate(obj: AnyObject) {
    userProject.saveDocument(self)
    let options = InstallOptions(verbose: false)
    installAction.performAction(.Update(options: options))
    showConsoleTab(self)
  }

  @IBAction func installUpdateVerbose(obj: AnyObject) {
    userProject.saveDocument(self)
    let options = InstallOptions(verbose: true)
    installAction.performAction(.Update(options: options))
    showConsoleTab(self)
  }

  @IBOutlet var installMenu: NSMenu!
  @IBAction func showInstallOptions(button: NSButton) {
    guard let event = NSApp.currentEvent else { return }
    NSMenu.popUpContextMenu(installMenu, withEvent: event, forView: button)
  }

  @IBAction func showEditorTab(sender: AnyObject) {
    tabController.selectedTabViewItemIndex = 0
  }

  @IBAction func showConsoleTab(sender: AnyObject) {
    tabController.selectedTabViewItemIndex = 2
  }

  @IBAction func showInformationTab(sender: AnyObject) {
    tabController.selectedTabViewItemIndex = 1
  }

  @IBOutlet weak var warningDoneButton: NSButton!
  @IBOutlet weak var warningLabel: NSTextField!
  @IBOutlet weak var warningView: BlueView!
  @IBOutlet weak var warningLabelHeight: NSLayoutConstraint!

  func showWarningLabelWithSender(message: String, actionTitle: String, target: AnyObject?, action: Selector, animated: Bool) {
    let constraint = warningLabelHeight
    warningLabelHeight.active = false

    warningLabel.stringValue = message
    warningDoneButton.title = actionTitle
    warningDoneButton.target = target
    warningDoneButton.action = action
    warningDoneButton.enabled = true
    view.layoutSubtreeIfNeeded()

    let height = animated ? constraint.animator() : constraint
    height.constant = warningView.fittingSize.height
    warningLabelHeight = constraint
    constraint.active = true
  }

  func hideWarningLabel(animated:Bool = true) {
    view.layoutSubtreeIfNeeded()
    let constraint = animated ? warningLabelHeight.animator() : warningLabelHeight
    constraint.constant = 0
    constraint.active = true
    warningDoneButton.enabled = false
  }

  var popover: NSPopover?

  @IBAction func showSourceRepoUpdatePopover(button: NSButton) {

    let podfileSources = userProject.podfileSources
    let allRepos = sourcesCoordinator.allRepos

    let activeProjects:[CPSourceRepo]
    let inactiveProjects:[CPSourceRepo]

    // Handle the implicit CP source repo when none are defined

    if podfileSources.isEmpty {
      activeProjects = allRepos.filter { $0.isCocoaPodsSpecs }
      inactiveProjects = allRepos.filter { $0.isCocoaPodsSpecs == false }
    } else {
      activeProjects = allRepos.filter { podfileSources.contains($0.address) }
      inactiveProjects = allRepos.filter { podfileSources.contains($0.address) == false }
    }

    guard let viewController = storyboard?.instantiateControllerWithIdentifier("RepoSources") as? CPSourceReposViewController else { return }

    let popover = NSPopover()
    popover.contentViewController = viewController
    popover.behavior = .Transient

    viewController.setActiveSourceRepos(activeProjects, inactiveRepos: inactiveProjects)
    popover.contentSize = NSSize(width: 400, height: viewController.heightOfData())

    popover.showRelativeToRect(button.bounds, ofView: button, preferredEdge: .MaxY)
    self.popover = popover
  }

}

extension NSViewController {

  /// Recurse the parentViewControllers till we find a CPPodfileViewController
  /// this lets child view controllers access this class for shared state.

  var podfileViewController: CPPodfileViewController? {

    guard let parent = self.parentViewController else { return nil }
    if let appVC = parent as? CPPodfileViewController {
      return appVC
    } else {
      return parent.podfileViewController
    }
  }
}
