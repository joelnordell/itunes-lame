//
//  NSAppleScript_BLTRExtensions.h
//  Quicksilver
//
//  Created by Nicholas Jitkoff on Thu Aug 28 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSAppleScript (Subroutine)
- (NSAppleEventDescriptor *)executeSubroutine:(NSString *)name arguments:(id)arguments error:(NSDictionary **)errorInfo;
@end

@interface NSAppleEventDescriptor (CocoaConversion)
- (id)objectValue;
+ (NSAppleEventDescriptor *)descriptorWithObject:(id)object;
@end