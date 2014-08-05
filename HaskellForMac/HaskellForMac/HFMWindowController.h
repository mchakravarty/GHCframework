//
//  HFMWindowController.h
//  HaskellForMac
//
//  Created by Manuel M T Chakravarty on 21/01/2014.
//  Copyright (c) 2014 Manuel M T Chakravarty. All rights reserved.
//
//  Controller for main windows — one window per project (aka HfM document). It is responsible for the
//  toolbar, the outline view, and the split views. Hence, it serves as their delegate.

#import <Cocoa/Cocoa.h>
#import "HFMProject.h"
#import "HFMHeaderEditorController.h"
#import "Haskell-Swift.h"


@interface HFMWindowController : NSWindowController <NSOutlineViewDelegate, NSSplitViewDelegate>

/// View controller of the currently displayed editor if any (which depends on the item selected in the outline view).
///
/// The corresponding views are specified in separate '.xib' files. We need to keep the view controller alive here.
//
@property (nonatomic) NSViewController *editorViewController;     // maybe nil
@property (nonatomic) TextEditorController *textEditorViewController;     // maybe nil

/// View controller of the playground if any is currently visible.
///
/// The corresponding views are specified in separate '.xib' files. We need to keep the view controller alive here.
//
@property (nonatomic) PlaygroundController *playgroundController;     // maybe nil


#pragma mark -
#pragma mark Notifications

/// The data source of the outline view change. Bring the view up to date.
//
- (void)refreshOutlineView;

@end
