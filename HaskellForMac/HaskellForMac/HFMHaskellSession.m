//
//  HFMGHC.m
//  HaskellForMac
//
//  Created by Manuel M T Chakravarty on 21/01/2014.
//  Copyright (c) 2014 Manuel M T Chakravarty. All rights reserved.
//

#import "HFMHaskellSession.h"
#import "GHCInstance_objc.h"


@interface HFMHaskellSession ()

@property (readonly, nonatomic) GHCInstance *ghcInstance;

@end


@implementation HFMHaskellSession


#pragma mark -
#pragma mark Session startup

+ (instancetype)haskellSessionStart
{
  return [[HFMHaskellSession alloc] init];
}

- (instancetype)init
{
  self = [super init];
  if (self) {

    _ghcInstance = [GHCInstance ghcInstanceStart];

  }
  return self;
}


#pragma mark -
#pragma mark Session shutdown

- (void)dealloc
{
  [self.ghcInstance stop];
}


@end
