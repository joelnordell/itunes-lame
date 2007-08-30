//
//  ILProgressView.h
//  iTunes-LAME
//
//  Created by Nicholas Jitkoff on Sat Aug 16 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <AppKit/AppKit.h>


@interface ILProgressView : NSView {
    double		minimum;
    double		maximum;
    double		value;
    
    bool isIndeterminate;
    NSColor *color;
    
}

- (void)setDoubleValue:(double)newValue;
    
- (double)minimum;
- (void)setMinimum:(double)newMinimum;

- (double)maximum;
- (void)setMaximum:(double)newMaximum;

- (double)value;
- (void)setValue:(double)newValue;

- (bool)isIndeterminate;
- (void)setIndeterminate:(bool)flag;

- (NSColor *)color;
- (void)setColor:(NSColor *)newColor;
@end
