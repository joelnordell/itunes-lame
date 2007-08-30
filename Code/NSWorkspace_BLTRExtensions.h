//
//  NSWorkspace_BLTRExtensions.h
//  Quicksilver
//
//  Created by Nicholas Jitkoff on Fri May 09 2003.
//  Copyright (c) 2003 Blacktree, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSWorkspace (Misc)
- (NSDictionary *)dictForApplicationName:(NSString *)path;
@end
