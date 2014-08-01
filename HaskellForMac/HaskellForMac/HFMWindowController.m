//
//  HFMWindowController.m
//  HaskellForMac
//
//  Created by Manuel M T Chakravarty on 21/01/2014.
//  Copyright (c) 2014 Manuel M T Chakravarty. All rights reserved.
//

#import "HFMWindowController.h"
#import "HFMProject.h"
#import "HFMHeaderEditorController.h"
#import "HFMTextEditorController.h"
#import "Haskell-Swift.h"


@interface HFMWindowController ()

// Views in 'ProjectWindow.xib'
//
@property (weak)              IBOutlet NSOutlineView *outlineView;
@property (weak)              IBOutlet NSSplitView   *splitView;
@property (weak)              IBOutlet NSView        *editorView;
@property (weak)              IBOutlet NSTextField   *noEditorLabel;
@property (weak)              IBOutlet NSView        *playgroundView;
@property (unsafe_unretained) IBOutlet NSTextView    *replView;


/// The GHC session associated with this window.
//
@property (nonatomic, readonly) HaskellSession *haskellSession;

/// A dictionary associating file extensions with the editor used to edit files of that type. Editors are identified
/// be the name of their NIB file.
//
@property (nonatomic, readonly) NSDictionary *editors;

@property NSUInteger startOfCommand;   // FIXME: provisional starting location of type command in REPL

@end


/// Editor NIB file names
//
NSString *const kPackageHeaderEditor = @"PackageHeaderEditor";
NSString *const kTextEditor          = @"TextEditor";
NSString *const kPlayground          = @"Playground";

/// NIB file ids
//
NSString *const kGroupCellID = @"groupCellID";
NSString *const kCabalCellID = @"cabalCellID";


@implementation HFMWindowController


#pragma mark -
#pragma mark Initialisation

- (instancetype)init
{
  self = [super initWithWindowNibName:@"ProjectWindow"];
  if (self) {

    _haskellSession = [HaskellSession haskellSessionStart];
    NSLog(@"WindowController: session start");

    _editors = @{@"cabal": kPackageHeaderEditor,
                 @"hs":    kTextEditor,
                 @"txt":   kTextEditor,
                 @"md":    kTextEditor};

  }
  return self;
}

- (void)windowDidLoad
{
  [super windowDidLoad];

    // Initialise the size and data for the project outline view. The delegate is this window controller and data source
    // is the document project.
  [self.outlineView sizeLastColumnToFit];
  self.outlineView.delegate   = self;
  self.outlineView.dataSource = self.document;

  [self.outlineView reloadData];

    // Set delegate of the split view to be this window controller.
  self.splitView.delegate = self;

    // Expand all root items without animation.
  [NSAnimationContext beginGrouping];
  [[NSAnimationContext currentContext] setDuration:0];
  [self.outlineView expandItem:nil expandChildren:YES];
  [NSAnimationContext endGrouping];
}


#pragma mark -
#pragma mark Notifications

- (void)refreshOutlineView
{
  [self.outlineView reloadData];

    // Expand all root items without animation.
  [NSAnimationContext beginGrouping];
  [[NSAnimationContext currentContext] setDuration:0];
  [self.outlineView expandItem:nil expandChildren:YES];
  [NSAnimationContext endGrouping];
}


#pragma mark -
#pragma mark NSOutlineViewDelegate protocol methods

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(HFMProjectViewModelItem *)item
{
#pragma unused(outlineView)

  return item.tag == PVMItemTagGroup;
}

- (NSTableCellView *)outlineView:(NSOutlineView *)outlineView
              viewForTableColumn:(NSTableColumn *)tableColumn
                            item:(HFMProjectViewModelItem *)item
{
#pragma unused(tableColumn)     // there is only one column

    // Do we need a group cell or a cabal cell item?
  if (item.tag == PVMItemTagGroup) {

    NSTableCellView *cell = [outlineView makeViewWithIdentifier:kGroupCellID owner:self];
    cell.textField.stringValue = [item.identifier uppercaseString];
    return cell;


  } else {

    NSTableCellView *cell = [outlineView makeViewWithIdentifier:kCabalCellID owner:self];
    cell.textField.stringValue = item.identifier;
    switch (item.tag) {
      case PVMItemTagPackage:
          // FIXME: use the .hsproj icon once we have one
//        cell.imageView.image = ???;
        break;
      case PVMItemTagExecutable:
        cell.imageView.image = [[NSWorkspace sharedWorkspace] iconForFileType:@"public.unix-executable"];
        break;
      case PVMItemTagFile:
        cell.imageView.image = [[NSWorkspace sharedWorkspace] iconForFileType:[item.identifier pathExtension]];
        break;
      case PVMItemTagFolder:
      case PVMItemTagFileGroup:
        cell.imageView.image = [[NSWorkspace sharedWorkspace] iconForFileType:(__bridge NSString *)kUTTypeFolder];
        break;
      default:
        break;
    }
    return cell;

  }
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(HFMProjectViewModelItem *)item
{
#pragma unused(outlineView)

  return item.tag != PVMItemTagGroup;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
  NSOutlineView *outlineView = [notification object];
  NSInteger      row         = [outlineView selectedRow];

  if (row != -1) {   // If a row is selected...

    HFMProjectViewModelItem *item = [outlineView itemAtRow:row];

    if (item && (item.tag == PVMItemTagPackage || item.tag == PVMItemTagFile))
      [self selectEditor:item];

  }
}


#pragma mark -
#pragma mark NSSplitViewDelegate protocol methods

/* DON'T constraint the size of component views with the delegate methods, as it doesn't work properly with
 * AutoLayout.
 */


#pragma mark -
#pragma mark NSTextViewDelegate protocol methods

  // FIXME: This is provisionally the delegate for the REPL view while it is so simple.

- (BOOL)textView:(NSTextView *)replTextView doCommandBySelector:(SEL)aSelector
{

  if (replTextView != self.replView) {

    NSLog(@"%s: textView:doCommandBySelector from unexpected text view", __func__);
    return NO;

  }

  if (aSelector == @selector(insertNewline:)) {

    NSFont   *menlo13     = [NSFont fontWithName:@"Menlo-Regular" size:13];
    NSColor  *grey        = [NSColor colorWithWhite:0.5 alpha:1];
    NSString *userCommand = [replTextView.textStorage.string substringFromIndex:self.startOfCommand];

      // Render the command in grey
    [replTextView.textStorage addAttribute:NSForegroundColorAttributeName
                                     value:grey
                                     range:(NSRange){self.startOfCommand,
                                                     [replTextView.textStorage length] - self.startOfCommand}];

      // Move insertion point to the end
    [replTextView setSelectedRange:(NSRange){[replTextView.textStorage length], 0}];
    [replTextView insertNewline:self];

      // Execute command
    NSString *evalResult = [self.haskellSession evalExprFromString:userCommand];

      // Insert result in the REPL area
    [replTextView.textStorage appendAttributedString:[[NSAttributedString alloc]
                                                      initWithString:evalResult
                                                      attributes:@{ NSFontAttributeName : menlo13 }]];

    self.startOfCommand = [self.replView selectedRange].location + 1;   // '+1' to account for the newline

  }
  return NO;
}


#pragma mark -
#pragma mark Controlling the editor component

/// Select the editor appropriate to editing the file backing the given given view model item; the type of editor is
/// determined on the basis of the file extension.
///
/// If no suitable editor is available, remove the current editor view (if any).
//
- (void)selectEditor:(HFMProjectViewModelItem *)item
{
  HFMProject *project       = self.document;
  NSString   *fileName      = item.fileName;
  NSURL      *fileURL       = [project.fileURL URLByAppendingPathComponent:fileName];
  NSString   *fileExtension = [fileName pathExtension];
  NSError    *error;

  if (!fileName) return;
  if (![item.fileWrapper isRegularFile]) return;

    // Check that the file is still there and force reading its contents. (We'll need it in a sec.)
  if (!fileURL || ![item.fileWrapper readFromURL:fileURL options:NSFileWrapperReadingImmediate error:&error]) {
    NSLog(@"%s: re-reading file wrapper from %@ failed: %@", __func__, fileURL, error);
    return;
  }

    // Remove the current editor view and playground view.
  if (self.editorViewController) {

    [[self.editorViewController view] removeFromSuperview];
    self.noEditorLabel.hidden = NO;

  }
  if (self.playgroundController)
    [[self.playgroundController view] removeFromSuperview];

    // Select suitable editor.
  NSString *nibName = self.editors[fileExtension];
  if (!nibName)
    return;

    // Load the new view by way of the matching view controller.
  if ([nibName isEqual:kPackageHeaderEditor]) {

    HFMProject *project = self.document;

    self.editorViewController =
      [[HFMHeaderEditorController alloc] initWithNibName:nibName
                                                  bundle:nil
                                        projectViewModel:project.projectModel
                                              projectURL:fileURL];

  } else if ([nibName isEqual:kTextEditor]) {

    self.editorViewController = [[HFMTextEditorController alloc] initWithNibName:nibName
                                                                          bundle:nil
                                                            projectViewModelItem:item
                                                                         fileURL:fileURL];
      // FIXME: TEMPORARY HACK
    item.loadString = ^(NSString *moduleText) {

      NSString           *result   = [[self.haskellSession loadModuleFromString:moduleText] stringByAppendingString:@"\n\n"];
      NSFont             *menlo13  = [NSFont fontWithName:@"Menlo-Regular" size:13];
      NSAttributedString *attrText = [[NSAttributedString alloc] initWithString:result
                                                                     attributes:@{ NSFontAttributeName : menlo13 }];
      [self.replView.textStorage setAttributedString:attrText];
      [self.replView scrollRangeToVisible:(NSRange){[self.replView.textStorage length], 0}];
      self.startOfCommand = [self.replView selectedRange].location;

    };

  }
  if (!self.editorView) {

    NSLog(@"%s: cannot load editor nib %@", __func__, nibName);
    return;

  }

  if ([fileExtension isEqualToString:[HFMProjectViewModel haskellFileExtension]]) {

    self.playgroundController = [[PlaygroundController alloc] initWithNibName:kPlayground bundle:nil];
    if (!self.playgroundController)
      NSLog(@"%s: cannot load playground nib %@", __func__, nibName);

  }

    // Enter editor view into the view hierachy.
  NSView *editorContentView = [self.editorViewController view];
  editorContentView.frame = self.editorView.bounds;
  [editorContentView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  editorContentView.translatesAutoresizingMaskIntoConstraints = YES;
  [self.editorView addSubview:editorContentView];
  self.editorView.needsLayout  = YES;
  self.editorView.needsDisplay = YES;

    // Enter playground view into the view hierachy if available.
  if (self.playgroundController) {

    NSView *playgroundContentView = [self.playgroundController view];
    playgroundContentView.frame = self.playgroundView.bounds;
    [playgroundContentView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    playgroundContentView.translatesAutoresizingMaskIntoConstraints = YES;
    [self.playgroundView addSubview:playgroundContentView];
    self.playgroundView.needsLayout  = YES;
    self.playgroundView.needsDisplay = YES;

  }

  self.noEditorLabel.hidden = YES;

}

@end
