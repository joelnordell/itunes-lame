//
//  ILWindow.m
//  iTunes-LAME
//
//  Created by Nicholas Jitkoff on Sun Jan 05 2003.
//  Copyright (c) 2003 Blacktree, Inc. All rights reserved.
//

#import "ILWindow.h"


@implementation ILWindow
- (void)performMiniaturize:(id)sender {
    [self miniaturize: sender];
}

/*

- (id)initWithContentRect:(NSRect)contentRect styleMask:(unsigned int)aStyle backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag{
    NSWindow* result = [super initWithContentRect:contentRect styleMask:aStyle|NSMiniaturizableWindowMask backing:bufferingType defer:flag];
    //[self setBackgroundColor: [NSColor clearColor]];//colorWithCalibratedWhite:0.75 alpha:0.5]];
    return result;
}

*/
- (void) awakeFromNib{
    [[self standardWindowButton:NSWindowMiniaturizeButton]setEnabled:YES];
    
    //[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appActivated:) name:@"NSApplicationDidBecomeActiveNotification" object:NULL];

    //[self setStyleMask:257];
    
    //NSLog(@"init?");
    //[self setFloatingPanel:YES];
}
/*
- (unsigned int)styleMask{
    NSLog(@"mask? %d",[super styleMask]);
    //return (NSTexturedBackgroundWindowMask);
    return [super styleMask]|NSMiniaturizableWindowMask;
}*/

/*
- (void)sendEvent:(NSEvent *)anEvent{
//    ;
    NSLog(@"Send %d",[self isKeyWindow]);
    if ([anEvent type]!=NSLeftMouseDown || [self isKeyWindow]) [super sendEvent:anEvent];
    else [self makeKeyAndOrderFront:self];
}
*/
@end
