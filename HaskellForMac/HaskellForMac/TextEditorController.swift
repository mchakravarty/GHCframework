//
//  TextEditorController.swift
//  HaskellForMac
//
//  Created by Manuel M T Chakravarty on 4/08/2014.
//  Copyright (c) 2014 Manuel M T Chakravarty. All rights reserved.
//

import Cocoa

class TextEditorController: NSViewController {

  /// Content views of the header editor
  ///
  @IBOutlet private weak var pathControl: NSPathControl!
  @IBOutlet private weak var scrollView:  NSScrollView!
  @IBOutlet private      var textView:    CodeView!

  /// Project view model item representing the edited file.
  ///
  dynamic let viewModelItem: ProjectItem

  /// Callback to load the module contained in the view model item being edited.
  ///
  private var loadModule: () -> ()

  /// We need to keep the code storage delegate alive as the delegate reference from `NSTextStorage` is unowned.
  ///
  private var codeStorageDelegate: CodeStorageDelegate!

  // Execute once `awakeFromNib` is being called.
  //
  private var awakeAction: () -> Void = {()}


  //MARK: -
  //MARK: Initialisation and deinitialisation

  /// Initialise the view controller by loading its NIB file and also set the associated file URL.
  ///
  init?(nibName: String!, bundle: NSBundle!, projectViewModelItem: ProjectItem, loadModule: () -> ()) {
    self.viewModelItem = projectViewModelItem
    self.loadModule    = loadModule

    super.init(nibName: nibName, bundle: bundle)

      // We use our gutter class as a ruler for the text view.
    NSScrollView.setRulerViewClass(TextGutterView)
  }

  required init?(coder: NSCoder) {
    NSLog("%s: WARNING: allocating empty project view model item", __FUNCTION__)
    self.viewModelItem = ProjectItem()
    self.loadModule    = { }
    super.init(coder: coder)
  }

  override func awakeFromNib() {

      // Set up for code editing (not prose).
    textView.automaticDashSubstitutionEnabled   = false
    textView.automaticDataDetectionEnabled      = false
    textView.automaticLinkDetectionEnabled      = false
    textView.automaticQuoteSubstitutionEnabled  = false
    textView.automaticSpellingCorrectionEnabled = false
    textView.automaticTextReplacementEnabled    = false

      // FIXME: How can we do that in a locale-independent way.
    var contextMenu = NSTextView.defaultMenu()
    if let item = contextMenu?.itemWithTitle("Spelling and Grammar") { contextMenu?.removeItem(item) }
    if let item = contextMenu?.itemWithTitle("Substitutions")        { contextMenu?.removeItem(item) }
    if let item = contextMenu?.itemWithTitle("Layout Orientation")   { contextMenu?.removeItem(item) }
    textView.menu = contextMenu

      // Set up the gutter.
    scrollView.hasVerticalRuler = true
    scrollView.rulersVisible    = true

      // Set up the delegate for the text storage.
    if let textStorage = textView.layoutManager?.textStorage {
      codeStorageDelegate  = CodeStorageDelegate(textStorage: textStorage)
      textStorage.delegate = codeStorageDelegate
      codeStorageDelegate.loadTriggers.observeWithContext(self, observer: curry{ controller, _ in controller.loadModule() })
    }

      // Get the intial edited code and updates on file wrapper changes.
    viewModelItem.reportItemChanges(self, wrapperChangeNotification: curry{ $0.newContentsForCodeView($1) })

      // Set the item's path on the path control.
    self.pathControl.URL = NSURL(string: viewModelItem.filePath ?? "")

    // Execute the awake action. (We do that last to ensure all connections are already set up.)
    awakeAction()
    awakeAction = {()}
  }
}

// MARK: -
// MARK: Syntax highlighting

extension TextEditorController {

  func enableHighlighting(tokeniser: HighlightingTokeniser?) {

      // If the text view isn't initialised yet, defer the set up until we awake from NIB loading.
    if let textView = self.textView {
      textView.enableHighlighting(tokeniser)
    } else {
      let oldAwakeAction = awakeAction
      awakeAction = { [unowned self] in
        oldAwakeAction()
        self.textView.enableHighlighting(tokeniser)
      }
    }
  }
}


// MARK: -
// MARK: NSTextDelegate protocol methods

extension TextEditorController: NSTextDelegate {

  func textDidChange(notification: NSNotification) {
    viewModelItem.fileContents = textView.string ?? ""
  }
}


// MARK: -
// MARK: Notifications

extension TextEditorController {

  /// NB: This is not for small incremental changes, but updates to the entire file, such as a change of the underlying
  ///     file in the file system.
  ///
  func newContentsForCodeView(newContents: String) {
    textView.string = newContents
  }

  /// Notify the gutter of a new set of issues for the associated file. (This invalidated all previous issues.)
  ///
  func updateIssues(notification: IssueNotification) {
    if let gutter = scrollView.verticalRulerView as? TextGutterView {
      gutter.updateIssues(notification)
    }
  }

  /// Notify the code storage that the module was successfully loaded.
  ///
  func moduleLoaded() { codeStorageDelegate.status.value = .LastLoaded(NSDate()) }
}


// MARK: -
// MARK: Forwarded menu actions

extension TextEditorController {

  func validateUserInterfaceItem(sender: NSValidatedUserInterfaceItem) -> Bool {
    return textView.validateUserInterfaceItem(sender)
  }

  func jumpToNextIssue(sender: AnyObject!) {
    return textView.jumpToNextIssue(sender)
  }

  func jumpToPreviousIssue(sender: AnyObject!) {
    return textView.jumpToPreviousIssue(sender)
  }
}


// MARK: -
// MARK: First responder

extension TextEditorController {

  func isCodeViewFirstResponder() -> Bool {
    return textView.window?.firstResponder === textView
  }

  func makeCodeViewFirstResponder() {
    textView.window?.makeFirstResponder(textView)
  }
}
