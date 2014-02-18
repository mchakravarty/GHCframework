//
//  HFMWindowController.m
//  HaskellForMac
//
//  Created by Manuel M T Chakravarty on 21/01/2014.
//  Copyright (c) 2014 Manuel M T Chakravarty. All rights reserved.
//

#import "HFMWindowController.h"
#import "HFMHaskellSession.h"


@interface HFMWindowController ()

// Views in 'ProjectWindow.xib'
//
@property (weak, atomic) IBOutlet NSOutlineView *outlineView;
@property (weak, atomic) IBOutlet NSView        *editorView;

// View controller of the currently displayed editor (which depends on the item selected in the outline view).
//
// The corresponding views are specified in separate '.xib' files. We need to keep the view controller alive here.
//
@property (strong, nonatomic) NSViewController *editorViewController;

// The GHC session associated with this window.
//
@property (nonatomic, readonly) HFMHaskellSession *haskellSession;

@end


@implementation HFMWindowController


#pragma mark -
#pragma mark Initialisation

- (instancetype)init
{
  self = [super initWithWindowNibName:@"ProjectWindow"];
  if (self) {

    _haskellSession = [HFMHaskellSession haskellSessionStart];
    NSLog(@"WindowController: session start");

  }
  return self;
}

- (void)windowDidLoad
{
  [super windowDidLoad];

    // Initialise the size and data for the project outline view. The delegate and data source is the document project.
  [self.outlineView sizeLastColumnToFit];
  self.outlineView.delegate   = self.document;
  self.outlineView.dataSource = self.document;
  [self.outlineView reloadData];

    // Expand all root items without animation.
  [NSAnimationContext beginGrouping];
  [[NSAnimationContext currentContext] setDuration:0];
  [self.outlineView expandItem:nil expandChildren:YES];
  [NSAnimationContext endGrouping];

}


#pragma mark -
#pragma mark Controlling the editor component

- (void)selectEditor:(NSString *)nibName
{
    // Remove the current editor view.
  if (self.editorViewController)
    [[self.editorViewController view] removeFromSuperview];

  self.editorViewController = [[NSViewController alloc] initWithNibName:nibName bundle:nil];
  NSView *view = [self.editorViewController view];
  view.frame = self.editorView.bounds;
  [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  view.translatesAutoresizingMaskIntoConstraints = YES;
  [self.editorView addSubview:view];
  self.editorView.needsLayout  = YES;
  self.editorView.needsDisplay = YES;

}

@end
