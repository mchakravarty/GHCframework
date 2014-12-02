//
//  PreferencesController.swift
//  HaskellForMac
//
//  Created by Manuel M T Chakravarty on 8/11/2014.
//  Copyright (c) 2014 Manuel M T Chakravarty. All rights reserved.
//

import Cocoa


// IB identifiers of the various preferences views.
//
let kGeneralPreferences     = "GeneralPreferences"
let kTextEditingPreferences = "TextEditingPreferences"
let kAccountPreferences     = "AccountPreferences"

class PreferencesController: NSWindowController {

  @IBOutlet weak var cloudMenu:          NSMenuItem!
  @IBOutlet weak var toolbar:            NSToolbar!
  @IBOutlet weak var accountToolbarItem: NSToolbarItem!

  // The nib containing the associated window.
  //
  override var windowNibName : String! {
    return "Preferences"
  }

  // Set the defaults before the nib is loaded.
  //
  override class func initialize() {
    let defaultValues = [ kPreferenceIndentationWidth:   2
                        , kPreferenceExternalTextEditor: ""    // use the default application by file extension
                        , kPreferenceEnableCloud: false
                        , kPreferenceGHCLogLevel: 0
                        , kPreferenceSpriteKitLogLevel: 0
                        , kPreferenceCloudLogLevel: 0
                        ]
    NSUserDefaults.standardUserDefaults().registerDefaults(defaultValues)
    NSUserDefaultsController.sharedUserDefaultsController().initialValues = defaultValues
  }

  // Reopen the preferences window when the app's persistent state is restored.
  //
  class func restoreWindowWithIdentifier(identifier: String,
    state: NSCoder,
    completionHandler: (NSWindow, NSError!) -> Void) -> Bool
  {
    completionHandler(((NSApp as NSApplication).delegate as AppDelegate).preferencesController.window!, nil)
    return true
  }

  override func awakeFromNib() {
    super.awakeFromNib()

      // Get rid of the Cloud menu if the cloud is disabled.
      //
      // NB: `windowDidLoad()` is too late for that as the Preferences window is not in the main nib.
    cloudMenu.hidden = !NSUserDefaults.standardUserDefaults().boolForKey(kPreferenceEnableCloud)
  }

  override func windowDidLoad() {
    super.windowDidLoad()

    window?.hidesOnDeactivate       = false
    window?.excludedFromWindowsMenu = true
    window?.identifier              = "Preferences"
    window?.restorationClass        = PreferencesController.self

    toolbar.delegate               = self
    toolbar.selectedItemIdentifier = kGeneralPreferences   // FIXME: this should come from autosave, but it doesn't...
    window?.title                  = "General";            //        this, too, of course

      // Currently, we don't dynamically enable and disable the account preferences tab. Its status is determined once.
    if !NSUserDefaults.standardUserDefaults().boolForKey(kPreferenceEnableCloud) {
      toolbar.removeItemAtIndex((toolbar.items as NSArray).indexOfObject(accountToolbarItem))
    }
  }

  // MARK: -
  // MARK: Window delegate
  //
  // NB: We set this controller as the window's delegate in IB.

    // We do this to catch the case where the user enters a value into one of the text fields but closes the window
    // without hitting enter or tab.
    //
  func windowShouldClose(window: NSWindow) -> Bool {
    return window.makeFirstResponder(nil)   // validate editing
  }
}


// MARK: -
// MARK: NSToolbarDelegate methods

extension PreferencesController: NSToolbarDelegate {

//  func toolbarDefaultItemIdentifiers(toolbar: NSToolbar) -> [String] {
//    return [kGeneralPreferences, kTextEditingPreferences, kAccountPreferences]
//  }
//
//  func toolbarAllowedItemIdentifiers(toolbar: NSToolbar) -> [String] {
//    return [kGeneralPreferences, kTextEditingPreferences, kAccountPreferences]
//  }

  func toolbarSelectableItemIdentifiers(toolbar: NSToolbar) -> [String] {
    return [kGeneralPreferences, kTextEditingPreferences, kAccountPreferences]
  }
}

extension PreferencesController {

  @IBAction func selectPreferenceTab(item: NSToolbarItem) {

    // The change propagates automatically to the tab view by way of a binding. NB: the toolbar item seems to need this
    // action (and associated validation), even if it is empty.
    window?.title = item.label
  }

  override func validateToolbarItem(toolbarItem: NSToolbarItem) -> Bool {

    let identifier = toolbarItem.itemIdentifier;

    if (identifier == kAccountPreferences) {

      return NSUserDefaults.standardUserDefaults().boolForKey(kPreferenceEnableCloud)

    } else { return true }
  }
}


// MARK: -
// MARK: NSTabViewDelegate methods

extension PreferencesController: NSTabViewDelegate {

}