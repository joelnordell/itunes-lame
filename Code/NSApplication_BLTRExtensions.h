//
//  NSApplication_Extensions.h
//  Daedalus
//
//  Created by Nicholas Jitkoff on Thu May 01 2003.
//  Copyright (c) 2003 Blacktree, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSApplication (Info)
- (NSString *)versionString;
- (int)featureLevel;
@end
