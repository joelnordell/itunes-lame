//
//  ILNonClickThruView.m
//  iTunes-LAME
//
//  Created by Nicholas Jitkoff on Wed Jun 18 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import "ILNonClickThruView.h"


@implementation ILNonClickThruView

- (NSView *)hitTest:(NSPoint)aPoint{

    if ([[self window] isKeyWindow]) return [super hitTest:aPoint];
    return nil;
}

@end
