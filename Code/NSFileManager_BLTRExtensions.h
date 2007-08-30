//
//  NSFileManager_CarbonExtensions.h
//  Quicksilver
//
//  Created by Nicholas Jitkoff on Thu Apr 03 2003.
//  Copyright (c) 2003 Blacktree, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSFileManager (BLTRExtensions)
- (BOOL)createDirectoriesForPath:(NSString *)path;
- (NSString *)fullyResolvedPathForPath:(NSString *)sourcePath;
- (NSString *)resolveAliasAtPath:(NSString *)aliasFullPath;
@end