//
//  NSWorkspace_BLTRExtensions.m
//  Quicksilver
//
//  Created by Nicholas Jitkoff on Fri May 09 2003.
//  Copyright (c) 2003 Blacktree, Inc. All rights reserved.
//

#import "NSWorkspace_BLTRExtensions.h"
#include <signal.h>


#import "Carbon/Carbon.h"

@implementation NSWorkspace (Misc)
- (NSDictionary *)dictForApplicationName:(NSString *)path{
    NSEnumerator *appEnumerator=[[self launchedApplications]objectEnumerator];
    NSDictionary *theApp;
    while(theApp=[appEnumerator nextObject]){
	if ([[theApp objectForKey:@"NSApplicationPath"]isEqualToString:path]||[[theApp objectForKey:@"NSApplicationName"]isEqualToString:path])
		return theApp;
	}
    return nil;
}
@end
