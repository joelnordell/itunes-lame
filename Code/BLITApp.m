//
//  BLITApp.m
//  iTunes-LAME
//
//  Created by Nicholas Jitkoff on Fri May 23 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import "BLITApp.h"


@implementation BLITApp
+ (void)initialize {
[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:YES],@"AppleDockIconEnabled",nil]];
}


- (void)sendEvent:(NSEvent *)anEvent{
    //NSLog(@"Event%@",anEvent);
    [super sendEvent:anEvent];
}


/*
- (void)activateIgnoringOtherApps:(BOOL)flag{

    NSString *currentApp=[[[NSWorkspace sharedWorkspace] activeApplication] objectForKey:@"NSApplicationName"];
    NSLog(@"activate:%@",currentApp);
    if ([currentApp isEqualToString:@"iTunes"])[super activateIgnoringOtherApps:flag];
    else{
         NSLog(@"noTunes");
        [[NSWorkspace sharedWorkspace] activateApplication:iTunesPath];
        [super activateIgnoringOtherApps:flag];
    }

}

*/

@end
