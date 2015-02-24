//
//  HFMWindowController.m
//  HaskellForMac
//
//  Created by Manuel M T Chakravarty on 21/01/2014.
//  Copyright (c) 2014 Manuel M T Chakravarty. All rights reserved.
//

#import "Haskell-Swift.h"
#import "HFMProject.h"
#import "HFMWindowController.h"


  // Identifiers for buttons associated with the source view.
NSString *kOutlineViewButtonAdd    = @"NavigatorAdd";
NSString *kOutlineViewButtonAction = @"NavigatorAction";

@interface HFMWindowController ()

// Views in 'ProjectWindow.xib'
//
@property (weak)   IBOutlet NSScrollView    *outlineScrollView;
@property (weak)   IBOutlet NSOutlineView   *outlineView;
@property (strong) IBOutlet NSMenu          *outlineViewAddMenu;
@property (strong) IBOutlet NSMenu          *outlineViewActionMenu;

@property (weak) IBOutlet StyledSplitView *splitView;
@property (weak) IBOutlet NSView          *editorView;
@property (weak) IBOutlet NSTextField     *noEditorLabel;
@property (weak) IBOutlet NSView          *playgroundView;

// Our cloud and local context controller (which we own).
//
@property CloudController   *cloudController;
@property ContextController *contextController;

// View controllers of the currently displayed editor and playground if any (which depends on the item selected in the
// outline view).
//
// We need to keep the view controllers alive here as we are in charge of entering the corresponding views into the
// view hierarchy and removing them again.
//
@property (nonatomic) NSViewController     *editorViewController;      // maybe nil
@property (nonatomic) PlaygroundController *playgroundController;      // maybe nil

// If we are currently editing the name of an item in the outline view, this property will refer to that item.
//
// NB: This property only gets set to the edited item iff `-rename:` was invoked via a menu action. If editing is
//     invoked by clicking a selected item, the edited item is the selected item instead.
//
@property (weak, nonatomic) ProjectItem    *editedItem;                // maybe nil

@end


/// NIB file ids
//
NSString *const kGroupCellID = @"groupCellID";
NSString *const kCabalCellID = @"cabalCellID";


@implementation HFMWindowController


#pragma mark -
#pragma mark Initialisation

- (instancetype)init
{
  return [super initWithWindowNibName:@"ProjectWindow"];
}

- (void)windowDidLoad
{
  [super windowDidLoad];

    // Initialise the size and data for the project outline view. The delegate is this window controller and data source
    // is the document project.
  [self.outlineView sizeLastColumnToFit];
  self.outlineView.delegate     = self;
  self.outlineView.dataSource   = self.document;
  self.outlineView.action       = @selector(clickSourceView:);

    // Set delegate of the split view to be this window controller.
  self.splitView.delegate = self;

    // We have got one cloud controller and one local context contoller for the lifetime of our window.
  self.cloudController   = [[CloudController alloc] initWithProject:self.document
                                              authenticationRequest:^(AuthenticationFlavour auth) {
#pragma unused(auth)
                                                NSAlert *alert = [[NSAlert alloc] init];
                                                alert.messageText = @"To use Cloudcelerate, you need to create an account.";
                                                alert.informativeText = @"The new account is tied to this copy of Haskell for Mac. By creating an account you agree to the Terms and Conditions.";
                                                [alert addButtonWithTitle:@"Create account"];
                                                [alert addButtonWithTitle:@"Do not create account"];
                                                return (BOOL)([alert runModal] == NSAlertFirstButtonReturn);
                                              }];
  self.contextController = [[ContextController alloc] initWithProject:self.document];

    // Display the current document state.
  [self refreshWindowContents];
}


#pragma mark -
#pragma mark Notifications

- (void)refreshWindowContents
{
    // Populate the outline view.
  [self.outlineView reloadData];

    // Expand all root items without animation.
  [NSAnimationContext beginGrouping];
  [[NSAnimationContext currentContext] setDuration:0];
  [self.outlineView expandItem:nil expandChildren:YES];
  [NSAnimationContext endGrouping];

    // Reset the document context.
  [self configureContextForSelectedItemInOutlineView:self.outlineView];
}


#pragma mark -
#pragma mark Menu actions

  // NB: Needs to be enabled in `-valideUserInterfaceItems:`.
- (void)newCloudAccount:(id)sender
{
#pragma unused(sender)
  [self.cloudController ping];
}

  // NB: Needs to be enabled in `-valideUserInterfaceItems:`.
- (void)runProjectInCloud:(id)sender
{
#pragma unused(sender)
  [self.cloudController run];
}


#pragma mark -
#pragma mark NSOutlineViewDelegate protocol methods

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(ProjectItem *)item
{
#pragma unused(outlineView)

  return (item) ? item.isGroup : NO;
}

- (NSTableCellView *)outlineView:(NSOutlineView *)outlineView
              viewForTableColumn:(NSTableColumn *)tableColumn
                            item:(ProjectItem *)item
{
#pragma unused(tableColumn)     // there is only one column

    // Do we need a group cell or a cabal cell item?
  if (item.isGroup) {

    NSTableCellView *cell      = [outlineView makeViewWithIdentifier:kGroupCellID owner:self];
    cell.textField.stringValue = [item.identifier uppercaseString];
    cell.textField.toolTip     = [item helpTip];
    cell.imageView.toolTip     = [item helpTip];
    return cell;


  } else {

    NSTableCellView *cell      = [outlineView makeViewWithIdentifier:kCabalCellID owner:self];
    cell.textField.stringValue = item.identifier;
    cell.textField.toolTip     = [item helpTip];
    cell.imageView.toolTip     = [item helpTip];
    if (item.isPackage)
          // FIXME: use the .hsproj icon once we have one
      ;//        cell.imageView.image = ???;
    else if (item.isExecutable)
      cell.imageView.image = [[NSWorkspace sharedWorkspace] iconForFileType:@"public.unix-executable"];
    else if (item.isFile)
      cell.imageView.image = [[NSWorkspace sharedWorkspace] iconForFileType:[item.identifier pathExtension]];
    else if (item.isFileGroup || item.isFolder)
      cell.imageView.image = [[NSWorkspace sharedWorkspace] iconForFileType:(__bridge NSString *)kUTTypeFolder];
    return cell;
  }
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(ProjectItem *)item
{
#pragma unused(outlineView)

  return !item.isGroup;
}

- (void)outlineViewSelectionIsChanging:(NSNotification *)notification
{
#pragma unused(notification)
  [self.contextController commitEditing];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
  if (self.outlineView.selectedRow != -1) {

    NSTableCellView *cellView = [self.outlineView viewAtColumn:self.outlineView.selectedColumn
                                                           row:self.outlineView.selectedRow
                                               makeIfNecessary:NO];
    cellView.textField.refusesFirstResponder = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([NSEvent doubleClickInterval] * 1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     cellView.textField.refusesFirstResponder = NO;
                   });

  }

  [self configureContextForSelectedItemInOutlineView:[notification object]];
}

// Do not try to use
// - (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item;
// as it is only for cell-based table views.


#pragma mark -
#pragma mark NSOutlineView context menu target-action methods

-(void)clickSourceView:(id)sender
{
#pragma unused(sender)

    // We use the action at the moment, but we need to register it for the following reason: Without setting an action
    // method on the outline view, a right-click/control-click (to get the context menu) will also start editing the
    // clicked on cell view if it is already selected. Unfortunately, setting the action also has the side effect of
    // delivering clicks onto a cell view twice (which starts editing cells with a single click). To avoid that, we
    // that cell views refuse first responder for a brief time interval after having been selected in
    // '-[outlineViewSelectionDidChange:]'.
}

#pragma mark File menu target-action methods

- (IBAction)openInEditor:(NSMenuItem *)sender
{
#pragma unused(sender)
  NSInteger row = [self.outlineView clickedRow] == -1 ? [self.outlineView selectedRow]
                                                      : [self.outlineView clickedRow];
  if (row < 0) return;    // no item clicked or selected

  ProjectItem *clickedItem = [self.outlineView itemAtRow:row];
  HFMProject  *project     = (HFMProject*)self.document;

  NSString *externalTextEditor = [[NSUserDefaults standardUserDefaults] stringForKey:Swift.swift_kPreferenceExternalTextEditor];
  if (!externalTextEditor || externalTextEditor.length == 0)
    [[NSWorkspace sharedWorkspace] openURL:[project.fileURL URLByAppendingPathComponent:clickedItem.filePath]];
  else
    [[NSWorkspace sharedWorkspace] openFile:[project.fileURL URLByAppendingPathComponent:clickedItem.filePath].path
                            withApplication:externalTextEditor];
}

- (IBAction)showInFinder:(NSMenuItem *)sender
{
#pragma unused(sender)
  NSInteger row = [self.outlineView clickedRow] == -1 ? [self.outlineView selectedRow]
                                                      : [self.outlineView clickedRow];
  if (row < 0) return;    // no item clicked or selected

  ProjectItem *clickedItem = [self.outlineView itemAtRow:row];
  HFMProject  *project     = (HFMProject*)self.document;

  [[NSWorkspace sharedWorkspace]
   activateFileViewerSelectingURLs:@[[project.fileURL URLByAppendingPathComponent:clickedItem.filePath]]];
}

- (IBAction)addExistingFiles:(NSMenuItem *)sender
{
  NSInteger row = [self.outlineView clickedRow] == -1 ? [self.outlineView selectedRow]
                                                      : [self.outlineView clickedRow];
  HFMProject  *project    = (HFMProject*)self.document;
  ProjectItem *parentItem;
  NSInteger    itemIndex;
  if (row < 0) {    // no item clicked or selected

    parentItem = project.projectModel.groupItems.dataGroupItem;
    itemIndex  = 0;

  } else {

    ProjectItem *clickedItem = [self.outlineView itemAtRow:row];
    parentItem               = (clickedItem.isFile) ? [self.outlineView parentForItem:clickedItem] : clickedItem;
    itemIndex                = (parentItem == clickedItem) ? 0 : clickedItem.index + 1;
  }
  if (!parentItem.fileWrapper.isDirectory) return;      // We can only add files to directories.

    // Ensure that the document representation in memory and on disk are in sync.
    // NB: Do this before the open panel as it needs a run loop iteration to take effect.
  [project saveDocument:sender];    // FIXME: Is this really the right way to save the document programmatically?

    // Ask the user to specify all files (no directories at the moment) that should be copied into the project.
    //
  NSOpenPanel *openPanel = [NSOpenPanel openPanel];
  openPanel.canChooseDirectories    = NO;
  openPanel.allowsMultipleSelection = YES;
  if (parentItem.isInExecutableCategory) {
    openPanel.allowedFileTypes      = @[[HFMProjectViewModel haskellFileExtension]];
    openPanel.title                 = @"Add Haskell files";
  } else
    openPanel.title                 = @"Add files";
  openPanel.prompt                  = @"Add";
  if ([openPanel runModal] == NSFileHandlingPanelCancelButton) return;

    // Try to add the selected files to the project, one by one.
  for (NSURL *url in openPanel.URLs) {

    NSString *fname        = [url lastPathComponent];
    BOOL      skipThisFile = NO;
    BOOL      nameClash    = NO;
    for (ProjectItem *child in parentItem.children) {

        // Name clash => ask user for resolution
      nameClash = [fname isEqualToString:child.identifier];
      if (nameClash) {

          // Set up overwrite conformation alert.
        NSAlert *alert        = [[NSAlert alloc] init];
        alert.messageText     = [NSString stringWithFormat:@"There already is a file called '%@' at this location.",
                                 fname];
        alert.informativeText = @"If you add the new file, the contents of the existing file will be overwritten.";
        [alert addButtonWithTitle:@"Overwrite existing file"];
        [alert addButtonWithTitle:@"Keep the existing file"];

        if ([alert runModal] == NSAlertSecondButtonReturn)   // Keep existing file
          skipThisFile = YES;
        break;                                               // Skip iterating over the other children of 'parentItem'

      }
    }
    if (skipThisFile) continue;     // User declined to overwrite an existing file => bail

      // Add the given file to the project model.
    NSError *error;
    if (![parentItem copyFileAtURL:url toIndex:itemIndex error:&error]) {

      NSAlert *alert = [NSAlert alertWithError:error];
      [alert runModal];
      return;
    }

      // Update the outline view if a new item was added.
    if (!nameClash) {

      [self.outlineView beginUpdates];
      [self.outlineView insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)itemIndex]
                                    inParent:parentItem
                               withAnimation:NSTableViewAnimationSlideDown];
      [self.outlineView endUpdates];

    }

      // Mark document as edited.
    [self.document updateChangeCount:NSChangeDone];
  }
    // Save the document to create the new files on external storage.
  [project saveDocument:sender];    // FIXME: Is this really the right way to save the document programmatically?
}

- (IBAction)newFile:(NSMenuItem *)sender
{
  [self newFileOrFolder:sender folder:NO];
}

- (IBAction)newFolder:(NSMenuItem *)sender
{
  [self newFileOrFolder:sender folder:YES];
}

- (void)newFileOrFolder:(NSMenuItem *)sender folder:(BOOL)folderWanted
{
  NSInteger row = [self.outlineView clickedRow] == -1 ? [self.outlineView selectedRow]
                                                      : [self.outlineView clickedRow];
  if (row < 0) return;    // no item clicked or selected

  ProjectItem *clickedItem = [self.outlineView itemAtRow:row];
  ProjectItem *parentItem  = (clickedItem.isFile) ? [self.outlineView parentForItem:clickedItem] : clickedItem;
  NSInteger    itemIndex   = (parentItem == clickedItem) ? 0 : [clickedItem index] + 1;
  HFMProject  *project     = (HFMProject*)self.document;

    // Add a new source file or folder to the view model and if successful...
  if ([parentItem newItemAtIndex:itemIndex folder:folderWanted]) {

      // Update the outline view.
    [self.outlineView beginUpdates];
    [self.outlineView insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)itemIndex]
                                  inParent:parentItem
                             withAnimation:NSTableViewAnimationSlideDown];
    [self.outlineView endUpdates];

      // Make sure the parent is expanded.
      // NB: Testing suggests that it seems to be necessary to do this *after* updating the outline view above...
    if (![self.outlineView isItemExpanded:parentItem])
      [self.outlineView expandItem:parentItem];

      // Mark document as edited and save it to create the new file on external storage.
    [self.document updateChangeCount:NSChangeDone];
    [project saveDocument:sender];    // FIXME: Is this really the right way to save the document programmatically?


      // Select and enter editing mode for the newly added item.
    ProjectItem *newItem    = [project outlineView:self.outlineView child:itemIndex ofItem:parentItem];
    NSInteger    newItemRow = [self.outlineView rowForItem:newItem];
    [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)newItemRow] byExtendingSelection:NO];
    [self performSelector:@selector(fileEdit:) withObject:newItem afterDelay:0.4];
      // NB: After returning from the current method, the selected row gets deselected, interrupting editing. So, we
      //     delay editing. It does seem like a hack, though. Is there a better way to achieve this?
  }
}


- (void)fileEdit:(ProjectItem *)editedItem
{
  NSInteger row = [self.outlineView rowForItem:editedItem];
  if (row == -1) return;

  self.editedItem = editedItem;
  [self.outlineView editColumn:0 row:row withEvent:nil select:YES];
}

- (IBAction)rename:(NSMenuItem *)sender {
#pragma unused(sender)

  NSInteger row = [self.outlineView clickedRow] == -1 ? [self.outlineView selectedRow]
                                                      : [self.outlineView clickedRow];
  if (row < 0) return;    // no item clicked or selected

  ProjectItem *clickedItem = [self.outlineView itemAtRow:row];
  [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
  [self fileEdit:clickedItem];
}

- (IBAction)delete:(NSMenuItem *)sender
{
#pragma unused(sender)

  NSInteger row = [self.outlineView clickedRow] == -1 ? [self.outlineView selectedRow]
                                                      : [self.outlineView clickedRow];
  if (row < 0) return;    // no item clicked or selected

  ProjectItem *item      = [self.outlineView itemAtRow:row];
  NSUInteger   itemIndex = (NSUInteger)[item index];

    // Set up confirmation alert.
  NSAlert *alert = [[NSAlert alloc] init];
//  alert.messageText = [NSString stringWithFormat:@"Do you really want to move the %@ '%@' to the Trash?",
  alert.messageText = [NSString stringWithFormat:@"Do you really want to remove the %@ '%@'?",
                       (item.isFile) ? @"file" : @"folder",
                       item.identifier];
//  [alert addButtonWithTitle:@"Move to Trash"];
  [alert addButtonWithTitle:@"Remove"];
  [alert addButtonWithTitle:@"Cancel"];

  if ([alert runModal] == NSAlertFirstButtonReturn) {   // Move to Trash

      // If we are deleting the currently selected entry, we need to remove it from the context.
    if ([self.outlineView selectedRow] == row) {

      [self.contextController deselectCurrentItem];
      [self configureEditor:nil playground:nil];

    }

      // Remove the file from the view model and if successful...
    if ([item remove]) {

        // FIXME: move to trash (Issue #166)

        // Update the UI.
      [self.outlineView beginUpdates];
      [self.outlineView removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:itemIndex]
                                    inParent:[self.outlineView parentForItem:item]
                               withAnimation:NSTableViewAnimationSlideUp];
      [self.outlineView endUpdates];

        // Mark document as edited.
      [self.document updateChangeCount:NSChangeDone];
    }
  }
}

#pragma mark NSOutlineView button and button menu target-action methods

- (IBAction)buttonPush:(NSButton *)button
{
  NSPoint loc = (NSPoint){5, CGRectGetMinY(button.bounds) - 20};   // FIXME: dodgy constant: whats the height of a menu item?
  if ([button.identifier isEqualToString:kOutlineViewButtonAdd]) {               // Pop up the add menu

    NSMenuItem *lastItem = [self.outlineViewAddMenu itemAtIndex:[self.outlineViewAddMenu numberOfItems] - 1];
    [self.outlineViewAddMenu popUpMenuPositioningItem:lastItem atLocation:loc inView:button];

  } else if ([button.identifier isEqualToString:kOutlineViewButtonAction]) {     // Pop up the action menu

    NSMenuItem *lastItem = [self.outlineViewActionMenu itemAtIndex:[self.outlineViewActionMenu numberOfItems] - 1];
    [self.outlineViewActionMenu popUpMenuPositioningItem:lastItem atLocation:loc inView:button];
  }
}

#pragma mark View menu target-action methods

- (IBAction)toggleNavigatorView:(id)sender
{
#pragma unused(sender)

  [self.splitView animateSetSubview:self.outlineScrollView toCollapsed:!self.outlineScrollView.hidden completionHandler:^{
      // We cannot show the source view without the editor view.
    if (!self.outlineScrollView.hidden && self.editorView.hidden) [self toggleEditorView:sender];
  }];
}

- (IBAction)toggleEditorView:(id)sender
{
#pragma unused(sender)

    // We cannot hide the editor unless the playground is visible.
  if (self.playgroundView.hidden && !self.editorView.hidden)
    [self.splitView animateSetSubview:self.playgroundView toCollapsed:NO completionHandler:^{

      if (!self.editorView.hidden)
        [self toggleEditorView:sender];

    }];
  else
    [self.splitView animateSetSubview:self.editorView toCollapsed:!self.editorView.hidden completionHandler:^{

        // We cannot hide the editor view without hiding the source view.
      if (self.editorView.hidden && !self.outlineScrollView.hidden) [self toggleNavigatorView:sender];

        // Make editor the first responder if presented; otherwise, the playground.
      if (!self.editorView.hidden && [self.editorViewController isKindOfClass:[TextEditorController class]])
        [((TextEditorController *)self.editorViewController) makeCodeViewFirstResponder];
      else if (!self.playgroundView.hidden && self.playgroundController)
        [self.playgroundController makeCodeViewFirstResponder];

    }];
}

- (IBAction)togglePlaygroundView:(id)sender
{
#pragma unused(sender)

    // We cannot hide the playground unless the editor is visible.
  if (self.editorView.hidden && !self.playgroundView.hidden)
    [self.splitView animateSetSubview:self.editorView toCollapsed:NO completionHandler:^{

      if (!self.playgroundView.hidden)
        [self togglePlaygroundView:sender];

    }];
  else
    [self.splitView animateSetSubview:self.playgroundView toCollapsed:!self.playgroundView.hidden completionHandler:^{

        // Make playground the first responder if presented; otherwise, the editor.
      if (!self.playgroundView.hidden && self.playgroundController)
        [self.playgroundController makeCodeViewFirstResponder];
      else if (!self.editorView.hidden && [self.editorViewController isKindOfClass:[TextEditorController class]])
        [((TextEditorController *)self.editorViewController) makeCodeViewFirstResponder];

    }];
}

- (IBAction)moveViewLeft:(id)sender
{
#pragma unused(sender)

  if (!self.playgroundView.hidden && self.editorView.hidden)
    [self.splitView animateSetSubview:self.editorView toCollapsed:NO completionHandler:nil];         // reveal editor
  else if (!self.playgroundView.hidden && !self.editorView.hidden && self.outlineScrollView.hidden)
    [self.splitView animateSetSubview:self.outlineScrollView toCollapsed:NO completionHandler:nil];  // reveal navigator
  else if (!self.playgroundView.hidden && !self.editorView.hidden && !self.outlineScrollView.hidden)
    [self.splitView animateSetSubview:self.playgroundView toCollapsed:YES completionHandler:nil];    // hide playground

    // Make editor the first responder if presented; otherwise, the playground.
  if (!self.editorView.hidden && [self.editorViewController isKindOfClass:[TextEditorController class]])
    [((TextEditorController *)self.editorViewController) makeCodeViewFirstResponder];
  else if (!self.playgroundView.hidden && self.playgroundController)
    [self.playgroundController makeCodeViewFirstResponder];
}

- (IBAction)moveViewRight:(id)sender
{
#pragma unused(sender)

  if (self.playgroundView.hidden)
    [self.splitView animateSetSubview:self.playgroundView toCollapsed:NO completionHandler:nil];     // reveal playground
  else if (!self.playgroundView.hidden && !self.outlineScrollView.hidden)
    [self.splitView animateSetSubview:self.outlineScrollView toCollapsed:YES completionHandler:nil]; // hide navigator
  else if (!self.playgroundView.hidden && !self.editorView.hidden)
    [self.splitView animateSetSubview:self.editorView toCollapsed:YES completionHandler:nil];        // hide editor

    // Make playground the first responder if presented; otherwise, the editor.
  if (!self.playgroundView.hidden && self.playgroundController)
    [self.playgroundController makeCodeViewFirstResponder];
  else if (!self.editorView.hidden && [self.editorViewController isKindOfClass:[TextEditorController class]])
    [((TextEditorController *)self.editorViewController) makeCodeViewFirstResponder];
}

#pragma mark Navigate menu target-action methods (forwarded)

- (void)moveFocusToNextArea:(id)sender
{
#pragma unused(sender)

  if ([self.editorViewController isKindOfClass:[TextEditorController class]] &&
      [((TextEditorController *)self.editorViewController) isCodeViewFirstResponder]) {
    if (!self.playgroundView.hidden && self.playgroundController)
      [self.playgroundController makeCodeViewFirstResponder];
  }
  else if ([self.playgroundController isCodeViewFirstResponder]) {
    if (!self.outlineScrollView.hidden)
      [self.window makeFirstResponder:self.outlineView];
  }
  else if ([self.window.firstResponder isEqual:self.outlineView]) {
    if (!self.editorView.hidden && [self.editorViewController isKindOfClass:[TextEditorController class]])
      [((TextEditorController *)self.editorViewController) makeCodeViewFirstResponder];
  }
}

- (void)jumpToNextIssue:(id)sender
{
  [self.contextController jumpToNextIssue:sender];
}

- (void)jumpToPreviousIssue:(id)sender
{
  [self.contextController jumpToPreviousIssue:sender];
}

#pragma mark NSMenuValidation and NSUserInterfaceValidations protocol methods

  // We set the appropriate menu titles in this method and defer to '-validateUserInterfaceItem:' for the actual
  // validation.
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
  SEL action = [menuItem action];

  if (action == @selector(toggleNavigatorView:)) {

    menuItem.title = self.outlineScrollView.hidden ? @"Show Project Navigator" : @"Hide Project Navigator";

  } else if (action == @selector(toggleEditorView:)) {

    menuItem.title = self.editorView.hidden ? @"Show Editor" : @"Hide Editor";
    
  } else if (action == @selector(togglePlaygroundView:)) {

    menuItem.title = self.playgroundView.hidden ? @"Show Playground" : @"Hide Playground";
    
  }
  return [self validateUserInterfaceItem:menuItem];
}


  // NB: At the moment, we only support individual selections (and not groups of selections). This will have to change
  //     at some point. Once, we supported selected groups, and the user right-clicks for the context menu, we need to
  //     check whether the clicked is part of the selected group. If so, the action ought to apply to the entire group.
- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)interfaceItem
{
  SEL       action = [interfaceItem action];
  NSInteger row    = [self.outlineView clickedRow] == -1 ? [self.outlineView selectedRow]
                                                         : [self.outlineView clickedRow];

  if (action == @selector(openInEditor:) || action == @selector(showInFinder:)) {

    ProjectItem *item = [self.outlineView itemAtRow:row];
    return item.isFile || item.isFolder;

  } else if (action == @selector(addExistingFiles:)) {

    ProjectItem *item = [self.outlineView itemAtRow:row];
    return (row == -1
            || item.isDirectory || item.isFile);

  } else if (action == @selector(newFile:)) {

    ProjectItem *item = [self.outlineView itemAtRow:row];
    return item.isDirectory || item.isFile;

  } else if (action == @selector(newFolder:)) {

    ProjectItem *item = [self.outlineView itemAtRow:row];
    return item.isDirectory || item.isFile;
    
  } else if (action == @selector(rename:)) {

    ProjectItem *item = [self.outlineView itemAtRow:row];
    return item.isFolder || item.isFileGroup || item.isFile;

  } else if (action == @selector(delete:)) {

    ProjectItem *item = [self.outlineView itemAtRow:row];
    return item.isFolder || item.isFileGroup || item.isFile;

  } else if (action == @selector(toggleNavigatorView:)) {

    return [Swift swift_isOperatingSystemAtLeastVersion10_10]   // always avaliable on 10.10 and later
           || !self.editorView.hidden;

  } else if (action == @selector(toggleEditorView:)) {

    return [Swift swift_isOperatingSystemAtLeastVersion10_10]   // always avaliable on 10.10 and later
           || self.outlineScrollView.hidden;

  } else if (action == @selector(togglePlaygroundView:)) {

    return YES;

  } else if (action == @selector(moveViewLeft:)) {

    return self.outlineScrollView.hidden || self.editorView.hidden || !self.playgroundView.hidden;
    
  } else if (action == @selector(moveViewRight:)) {

    return !self.outlineScrollView.hidden || !self.editorView.hidden || self.playgroundView.hidden;

  } else if (action == @selector(newCloudAccount:)) {

    return ![self.cloudController accountStatus];

  } else if (action == @selector(runProjectInCloud:)) {

    return YES; // FIXME: Should only be YES if there are no errors etc and the cloud is not offline etc.

  } else if (action == @selector(moveFocusToNextArea:)) {

      // We need more than one area for moving the focus to make sense.
    return !self.editorView.hidden && !self.playgroundView.hidden;

  } else if (action == @selector(jumpToNextIssue:) || action == @selector(jumpToPreviousIssue:)) {

      // When a diagnostics popup is presented, the responder chain goes from the popup to the main window; we
      // redirect to the editor
    return [self.contextController validateUserInterfaceItem:interfaceItem];

  }

  return NO;
}


#pragma mark -
#pragma mark NSSplitViewDelegate protocol methods

/* DON'T constraint the size of component views with the delegate methods, as it doesn't work properly with
 * AutoLayout. In particular, don't use any of 'splitView:constrainMinCoordinate:ofSubviewAt:',
 * 'splitView:constrainMaxCoordinate:ofSubviewAt:', 'splitView:resizeSubviewsWithOldSize:', and
 * 'splitView:shouldAdjustSizeOfSubview:'.
 */

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview
{
#pragma unused(splitView)

    // The editor view can only be collapsed if the outline view is already collapsed.
  return (subview != self.editorView || [self.splitView isSubviewCollapsed:self.outlineScrollView]) ? YES : NO;
}

- (BOOL)splitView:(NSSplitView *)splitView
shouldCollapseSubview:(NSView *)subview
forDoubleClickOnDividerAtIndex:(NSInteger)dividerIndex;
{
#pragma unused(splitView)

  return (([subview isEqual:self.outlineScrollView] && dividerIndex == 0)
          || ([subview isEqual:self.playgroundView] && dividerIndex == 1));
}


#pragma mark -
#pragma mark NSTextFieldDelegate protocol methods

- (BOOL)control:(NSControl *)control isValidObject:(NSString*)string
{
#pragma unused(control)

    // Either we initiated editing through a menu action or the edited item must be the selected.
  ProjectItem *item = self.editedItem ? self.editedItem
                                      : [self.outlineView itemAtRow:[self.outlineView selectedRow]];

    // Accept Haskell module names with a '.hs' suffix (for modules) and plain Haskell module names for folders.
  NSString *extension = [string pathExtension];
  NSString *name      = [string stringByDeletingPathExtension];

    // FIXME: We need some constraints on the names of non-Haskell files. The same fix needs to be applied in `-controlTextDidEndEditing:`.
  if (item.isInDataCategory || item.isInExtraSourceCategory)
      return YES;

  if (item.isFile)
    return ([Swift swift_isValidModuleName:name] && [extension isEqualToString:[HFMProjectViewModel haskellFileExtension]]);

  if (item.isFolder)
    return [Swift swift_isValidModuleName:string];

  return NO;
}

#pragma mark -
#pragma mark NSControl protocol methods

  // This is used when the editing of a text field of the source view ends.
- (void)controlTextDidEndEditing:(NSNotification *)notification
{
  NSText      *text      = notification.userInfo[@"NSFieldEditor"];
  NSTextField *textField = notification.object;
    // Either we initiated editing through a menu action or the edited item must be the selected.
  ProjectItem *item      = self.editedItem ? self.editedItem
                                           : [self.outlineView itemAtRow:[self.outlineView selectedRow]];
  NSString    *oldName   = item.identifier;
  NSString    *newName   = text.string;

  self.editedItem = nil;

    // Add a Haskell file extension to file names if not present yet and not in the support files or extra sources groups.
  if (item.isFile
      && ![[newName pathExtension] isEqualToString:[HFMProjectViewModel haskellFileExtension]]
      && !(item.isInDataCategory || item.isInExtraSourceCategory)) {
    newName = [newName stringByAppendingPathExtension:[HFMProjectViewModel haskellFileExtension]];
    textField.stringValue = newName;
  }
  NSString *finalName = [item renameTo:newName];
  if (finalName) textField.stringValue = finalName;

    // Mark document as edited and save to change filename on external storage.
  if (![textField.stringValue isEqualToString:oldName]) {

    [self.document updateChangeCount:NSChangeDone];
    [self.document saveDocument:self];    // FIXME: Is this really the right way to save the document programmatically?

  }

    // Make sure any change of the string in this method is reflected in the UI.
  [self.outlineView reloadItem:item];
}


#pragma mark -
#pragma mark NSEditor protocol methods

- (BOOL)commitEditing
{
  return [self.contextController commitEditing];
}


#pragma mark -
#pragma mark Configuration management

/// Configure the context according to the currently selected item in the source view.
///
- (void)configureContextForSelectedItemInOutlineView:(NSOutlineView *)outlineView
{
  NSInteger row = [outlineView selectedRow];

  if (row != -1) {   // If a row is selected...

    ProjectItem *item = [outlineView itemAtRow:row];

    if (item && (item.isPackage || item.isFile)) {

      NSViewController     *editorController     = nil;
      PlaygroundController *playgroundController = nil;

      [self.contextController selectItem:item returningEditor:&editorController playground:&playgroundController];
      [self configureEditor:editorController playground:playgroundController];

        // Load the newly selected module right away.
      [self.contextController loadContextModule];
    }

  } else {          // If there is no selection...

    [self.contextController deselectCurrentItem];
    [self configureEditor:nil playground:nil];

  }
}

/// Configure a new editor and playground controller.
///
/// First removes any old editor and/or playground, and then, installs the new ones (if the arguments are non-nil).
///
- (void)configureEditor:(NSViewController *)newEditor playground:(PlaygroundController *)newPlayground
{
  BOOL previousConfigurationHadAPlayground = self.playgroundController != nil;

    // Remove the current editor view and playground view.
  if (self.editorViewController) {

    [self.editorViewController.view removeFromSuperview];
    self.noEditorLabel.hidden = NO;

  }
  if (self.playgroundController)
    [self.playgroundController.view removeFromSuperview];

    // Enter new editor view into the view hierachy if available.
  self.editorViewController = newEditor;
  if (self.editorViewController) {

    NSView *editorContentView = self.editorViewController.view;
    editorContentView.frame = self.editorView.bounds;
    [editorContentView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    editorContentView.translatesAutoresizingMaskIntoConstraints = YES;
    [self.editorView addSubview:editorContentView];
    self.editorView.needsLayout  = YES;
    self.editorView.needsDisplay = YES;
    self.noEditorLabel.hidden    = YES;

  }

    // Enter playground view into the view hierachy if available.
    //
    // We hide the playground view if no playground is available iff it was hidden *and* no playground was available in
    // the previous configuration. (In other words, if there was a playground in the previous configuration and it was
    // hidden, keep it hidden.)
  self.playgroundController = newPlayground;
  if (self.playgroundController) {

    NSView *playgroundContentView = self.playgroundController.view;
    playgroundContentView.frame = self.playgroundView.bounds;
    [playgroundContentView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    playgroundContentView.translatesAutoresizingMaskIntoConstraints = YES;
    [self.playgroundView addSubview:playgroundContentView];
    self.playgroundView.needsLayout  = YES;
    self.playgroundView.needsDisplay = YES;

    if (self.playgroundView.hidden && !previousConfigurationHadAPlayground)
      [self togglePlaygroundView:self];

  } else if (!self.playgroundView.hidden)
    [self togglePlaygroundView:self];
}

@end
