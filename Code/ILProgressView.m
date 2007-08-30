//
//  ILProgressView.m
//  iTunes-LAME
//
//  Created by Nicholas Jitkoff on Sat Aug 16 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import "ILProgressView.h"


@implementation ILProgressView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
        minimum=0;
        maximum=100;
        value=0;
        [self setColor:[NSColor colorWithCalibratedWhite:0.333 alpha:1.0]];
    }
    return self;
}

- (void)drawRect:(NSRect)rect {
    // Drawing code here.
    float progress=(value-minimum)/(maximum-minimum);
   [[self color]set];
    NSFrameRect(rect);
    NSRect innerRect=NSInsetRect(rect,2,2);
    //NSLog(@"%f",progress);
    innerRect.size.width=innerRect.size.width*progress;
    [[[self color]colorWithAlphaComponent:0.5]set];
        NSRectFill(innerRect);
}



- (void)setDoubleValue:(double)newValue {
    [self setValue:newValue];
}





- (double)minimum { return minimum; }
- (void)setMinimum:(double)newMinimum {
    minimum = newMinimum;
}


- (double)maximum { return maximum; }
- (void)setMaximum:(double)newMaximum {
    maximum = newMaximum;
}


- (double)value { return value; }
- (void)setValue:(double)newValue {
    value = newValue;
    [self setNeedsDisplay:YES];
}



- (bool)isIndeterminate { return isIndeterminate; }
- (void)setIndeterminate:(bool)flag {
    isIndeterminate = flag;
    [self setDoubleValue:0.0];
    [self setNeedsDisplay:YES];
}


- (NSColor *)color { return [[color retain] autorelease]; }

- (void)setColor:(NSColor *)newColor {
    [color release];
    color = [newColor retain];
}

@end
