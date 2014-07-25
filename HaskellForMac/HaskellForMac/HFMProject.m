//
//  HFMProject.m
//  HaskellForMac
//
//  Created by Manuel M T Chakravarty on 17/01/2014.
//  Copyright (c) 2014 Manuel M T Chakravarty. All rights reserved.
//

#import "HFMProject.h"
#import "HFMWindowController.h"


@implementation HFMProject


#pragma mark -
#pragma mark Initialisation

  // NB: Don't initialise the propery 'projectModel'. This only happens once when we know whether we open an existing
  // document or are creating a new one.
- (instancetype)init
{
  self = [super init];

  return self;
}

  // FIXME: We probably still have to special case the situation where a document was autosaved, but never explicitly saved
  //  to a particular location. Might have to override 'initForURL:withContentsOfURL:ofType:error:'
  //  or 'initWithContentsOfURL:ofType:error:'

  // This initialisation method is invoked if a new document is being created.

- (instancetype)initWithType:(NSString *)typeName error:(NSError *__autoreleasing *)outError
{
#pragma unused(outError)

  self = [self init];
  if (self) {

    [self setFileType:typeName];
    NSFileWrapper *projectFileWrapper = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{}];
    [projectFileWrapper setPreferredFilename:@"Untitled.hsproj"];
    _projectModel = [HFMProjectViewModel projectViewModelWithProjectFileWrapper:projectFileWrapper
                                                               cabalFileWrapper:nil];

  }
  return self;
}


#pragma mark -
#pragma mark NSDocument methods

+ (BOOL)canConcurrentlyReadDocumentsOfType:(NSString *)typeName
{
#pragma unused(typeName)

  return YES;
}

+ (BOOL)autosavesInPlace;
{
  return YES;
}

- (BOOL)readFromFileWrapper:(NSFileWrapper *)projectFileWrapper
                     ofType:(NSString *)typeName
                      error:(NSError *__autoreleasing *)outError
{
#pragma unused(typeName)

  BOOL readSuccess = NO;

    // FIXME: supposedly, we should disable undo during file reading with '[[self undoManager] disableUndoRegistration]'

    // On opening a project, we read the Cabal file to get the project structure. If there is no Cabal file, we create
    // a new one.

    // Find the Cabal file.
  NSString      *cabalFileExtension = [HFMProjectViewModel cabalFileExtension];
  NSDictionary  *wrappers           = [projectFileWrapper fileWrappers];
  NSFileWrapper *cabalFile;

  for (NSString *fname in wrappers)
    if ([[fname pathExtension] isEqualToString:cabalFileExtension] && [wrappers[fname] isRegularFile]) {

      cabalFile = wrappers[fname];
      break;

    }

    // Initialise the project view model with the project and Cabal file wrappers. The latter *may* be nil!
  _projectModel  = [HFMProjectViewModel projectViewModelWithProjectFileWrapper:projectFileWrapper
                                                              cabalFileWrapper:cabalFile];

  if (self.projectModel)
    readSuccess = YES;

  if (!readSuccess && outError)
    *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
  return readSuccess;
}

- (NSFileWrapper *)fileWrapperOfType:(NSString *)typeName error:(NSError *__autoreleasing *)outError
{
#pragma unused(typeName)

    // Flush any pending edits in the editor view. NB: We have got exactly one window controller.
  HFMWindowController *windowController = self.windowControllers[0];
  [windowController.editorViewController commitEditing];

  return [self.projectModel fileWrapperWithError:outError];
}

- (void)makeWindowControllers
{
  [self addWindowController:[[HFMWindowController alloc] init]];
}

- (void)showWindows
{
    // First, do show the window.
  [super showWindows];

    // Then, get the window controller associated with this document.
  NSWindowController *myWindowController = [self.windowControllers lastObject];
  if (!myWindowController) {
    NSLog(@"%s: window controller of document missing; URL = %@", __func__, self.fileURL);
    return;
  }

    // If this is an untitled document, ask the user to configure a new project.
  if (!self.fileURL) {

    NSWindow *window   = myWindowController.window;
    NSString *fname    = [self.projectModel.fileWrapper preferredFilename];
    NSSavePanel* panel = [NSSavePanel savePanel];
    [panel setNameFieldStringValue:fname];
    [panel beginSheetModalForWindow:window completionHandler:^(NSInteger result) {

      switch (result) {
        case NSFileHandlingPanelOKButton:
          self.fileURL = [panel URL];
          break;

        default:
          [window close];
          break;
      }
      
    }];

  }
}


#pragma mark -
#pragma mark NSOutlineViewDataSource protocol methods

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(HFMProjectViewModelItem *)item
{
#pragma unused(outlineView, index, item)


  if (!item) {            // If this is a group item, get the static group item from the model

    if ((NSUInteger)index >= self.projectModel.groupItems.count) {
      NSLog(@"%s: out of bounds access to group item: index = %ld", __func__, (long)index);
      return nil;
    }
    return self.projectModel.groupItems[(NSUInteger)index];

  } else {                // All non-group items are accessed via their parent

    NSArray *children = item.children;
    if ((NSUInteger)index >= children.count) {
      NSLog(@"%s: out of bounds access to children of '%@': index = %ld", __func__, item.identifier, (long)index);
      return nil;
    }
    return children[(NSUInteger)index];

  }
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(HFMProjectViewModelItem *)item
{
#pragma unused(outlineView)
  
  return item.children.count > 0;
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(HFMProjectViewModelItem *)item
{
#pragma unused(outlineView)

    // Without a window controller, we do not currently display this document anywhere.
  if (!self.windowControllers.firstObject)
    return 0;

  if (!item)
    return (NSInteger)[self.projectModel.groupItems count];
  else
    return (NSInteger)item.children.count;
}

/* Need to implement this if the user should be able to edit the items of the outline view:

- (void)outlineView:(NSOutlineView *)outlineView
     setObjectValue:(id)object
     forTableColumn:(NSTableColumn *)tableColumn
             byItem:(id)item
{
}
 
 */

@end
