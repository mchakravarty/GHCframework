//
//  HFMWindowController.m
//  HaskellForMac
//
//  Created by Manuel M T Chakravarty on 21/01/2014.
//  Copyright (c) 2014 Manuel M T Chakravarty. All rights reserved.
//

#import "HFMWindowController.h"
#import "HFMHeaderEditorController.h"
#import "HFMTextEditorController.h"
#import "HFMHaskellSession.h"


@interface HFMWindowController ()

// Views in 'ProjectWindow.xib'
//
@property (weak, atomic) IBOutlet NSOutlineView *outlineView;
@property (weak, atomic) IBOutlet NSSplitView   *verticalSplitView;
@property (weak, atomic) IBOutlet NSSplitView   *horizontalSplitView;
@property (weak, atomic) IBOutlet NSView        *editorView;

// View controller of the currently displayed editor (which depends on the item selected in the outline view).
//
// The corresponding views are specified in separate '.xib' files. We need to keep the view controller alive here.
//
@property (strong, nonatomic) NSViewController *editorViewController;

// The GHC session associated with this window.
//
@property (nonatomic, readonly) HFMHaskellSession *haskellSession;

// A dictionary associating file extensions with the editor used to edit files of that type. Editors are identified
// be the name of their NIB file.
//
@property (nonatomic, readonly) NSDictionary *editors;

@end


/// Editor NIB file names
//
NSString *const kPackageHeaderEditor = @"PackageHeaderEditor";
NSString *const kTextEditor          = @"TextEditor";

/// NIB file ids
//
NSString *const kCabalCellID = @"cabalCellID";


@implementation HFMWindowController


#pragma mark -
#pragma mark Initialisation

- (instancetype)init
{
  self = [super initWithWindowNibName:@"ProjectWindow"];
  if (self) {

    _haskellSession = [HFMHaskellSession haskellSessionStart];
    NSLog(@"WindowController: session start");

    _editors = @{@"cabal": kPackageHeaderEditor,
                 @"hs":    kTextEditor};

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

    // Set delegate of the split views is this window controller.
  self.verticalSplitView.delegate   = self;
  self.horizontalSplitView.delegate = self;

    // Expand all root items without animation.
  [NSAnimationContext beginGrouping];
  [[NSAnimationContext currentContext] setDuration:0];
  [self.outlineView expandItem:nil expandChildren:YES];
  [NSAnimationContext endGrouping];

}


#pragma mark -
#pragma mark NSOutlineViewDelegate protocol methods

- (NSTableCellView *)outlineView:(NSOutlineView *)outlineView
              viewForTableColumn:(NSTableColumn *)tableColumn
                            item:(NSString *)name
{
#pragma unused(tableColumn)     // there is only one column

  NSTableCellView *cell = [outlineView makeViewWithIdentifier:kCabalCellID owner:self];
  cell.textField.stringValue = name;
  return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
  NSOutlineView *outlineView = [notification object];
  NSInteger      row         = [outlineView selectedRow];

  if (row != -1) {   // If a row is selected...

    if (row == 0) // FIXME: hardcoded here for now
      [self selectEditor:@"cabal"];

  }
}


#pragma mark -
#pragma mark NSSplitViewDelegate protocol methods

- (CGFloat)splitView:(NSSplitView *)sv constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)di
{
#pragma unused(di)

  if (sv == self.verticalSplitView)
    return proposedMin < 150 ? 150 : proposedMin;
  else if (sv == self.horizontalSplitView)
    return proposedMin < 150 ? 150 : proposedMin;
  else {

    NSLog(@"%s: unexpected split view: %@", __func__, [sv description]);
    return proposedMin;

  }
}


#pragma mark -
#pragma mark Controlling the editor component

- (void)selectEditor:(NSString *)fileExtension
{
    // Remove the current editor view.
  if (self.editorViewController)
    [[self.editorViewController view] removeFromSuperview];

    // Select suitable editor.
  NSString *nibName = [self.editors objectForKey:fileExtension];
  if (!nibName)
    return;

    // Load the new view by way of the matching view controller.
  if ([nibName isEqual:kPackageHeaderEditor])
    self.editorViewController = [[HFMHeaderEditorController alloc] initWithNibName:nibName bundle:nil];
  else if ([nibName isEqual:kTextEditor])
    self.editorViewController = [[HFMTextEditorController alloc] initWithNibName:nibName bundle:nil];
  if (!self.editorView) {

    NSLog(@"%s: cannot load editor nib %@", __func__, nibName);
    return;

  }

    // Enter editor view into the view hierachy.
  NSView *view = [self.editorViewController view];
  view.frame = self.editorView.bounds;
  [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  view.translatesAutoresizingMaskIntoConstraints = YES;
  [self.editorView addSubview:view];
  self.editorView.needsLayout  = YES;
  self.editorView.needsDisplay = YES;

}

@end
