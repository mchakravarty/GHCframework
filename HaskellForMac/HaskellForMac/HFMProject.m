//
//  HFMProject.m
//  HaskellForMac
//
//  Created by Manuel M T Chakravarty on 17/01/2014.
//  Copyright (c) 2014 Manuel M T Chakravarty. All rights reserved.
//

#import "HFMProject.h"
#import "HFMWindowController.h"


// File extension for Cabal files.
//
static NSString *cabalFileExtension = @"cabal";


@implementation HFMProject


#pragma mark -
#pragma mark Initialisation

  // Don't initialise the propery 'projectModel'. This only happens once when we know whether we open an existing
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
    _projectModel  = [HFMProjectViewModel projectViewModelWithCabalFileName:@"MyProject.cabal"];

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

- (BOOL)readFromFileWrapper:(NSFileWrapper *)fileWrapper
                     ofType:(NSString *)typeName
                      error:(NSError *__autoreleasing *)outError
{
#pragma unused(typeName)

  BOOL readSuccess = NO;

    // FIXME: supposedly, we should disable undo during file reading with '[[self undoManager] disableUndoRegistration]'

    // On opening a project, we read the Cabal file to get the project structure. If there is no Cabal file, we create
    // a new one.

    // Find the Cabal file.
  NSDictionary  *wrappers  = [fileWrapper fileWrappers];
  NSFileWrapper *cabalFile;

  for (NSString *fname in wrappers)
    if ([[fname pathExtension] isEqualToString:cabalFileExtension] && [wrappers[fname] isRegularFile]) {

      cabalFile = wrappers[fname];
      break;

    }

  if (cabalFile) {

      // Initialise the project view model from the Cabal file.
    NSString *fileContents = [[NSString alloc] initWithData:[cabalFile regularFileContents]
                                                   encoding:NSUTF8StringEncoding];
    _projectModel  = [HFMProjectViewModel projectViewModelWithCabalFileName:[[cabalFile filename] lastPathComponent]
                                                                     string:fileContents];

  } else {

      // If no Cabal file present, create a new, empty Cabal package whose name is derived from the package name and add
      // it to the file wrapper for the project.
    NSString *fname = [[[fileWrapper filename] lastPathComponent] stringByAppendingPathExtension:cabalFileExtension];
    [fileWrapper addRegularFileWithContents:[NSData data] preferredFilename:fname];
    _projectModel = [HFMProjectViewModel projectViewModelWithCabalFileName:fname];
      // FIXME: add this point the file wrapper is dirty as the NSData for the Cabal file wrapper is not up to date.

  }
  if (self.projectModel)
    readSuccess = YES;

  if (!readSuccess && outError)
    *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
  return readSuccess;

    // FIXME: we need to pass the file wrapper to the project view model during creation above!
}

- (NSFileWrapper *)fileWrapperOfType:(NSString *)typeName error:(NSError *__autoreleasing *)outError
{
#pragma unused(typeName)

  NSString *fileContents = [self.projectModel string];
  NSData   *data         = [fileContents dataUsingEncoding:NSUTF8StringEncoding];

    // FIXME: get the project file wrapper from the view model
    //    Do we put the 'data' into the file wrapper here or does that happen earlier
  if (!data && outError)
    *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
  return nil;  // FIXME: BOOMMMM!!!
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError *__autoreleasing *)outError
{
#pragma unused(typeName)

  NSString *fileContents = [self.projectModel string];
  NSData   *data         = [fileContents dataUsingEncoding:NSUTF8StringEncoding];

  if (!data && outError)
    *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
  return data;
}

- (void)makeWindowControllers
{
  [self addWindowController:[[HFMWindowController alloc] init]];
}

  // FIXME: do we need post-nib-loading code?


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
