//
//  NSApplication_Extensions.m
//  Quicksilver
//
//  Created by Nicholas Jitkoff on Thu May 01 2003.
//  Copyright (c) 2003 Blacktree, Inc. All rights reserved.
//

#import "NSApplication_BLTRExtensions.h"


@implementation NSApplication (Info)

- (NSString *)versionString{
    NSDictionary *infoDict=[[NSBundle mainBundle]infoDictionary];
    
        
    return [NSString stringWithFormat:@"%@ v%@ (%@)",[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"],[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],[infoDict objectForKey:@"CFBundleVersion"]];
}

- (int)featureLevel{return 0;}

@end
