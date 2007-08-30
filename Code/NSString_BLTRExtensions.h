//
//  NSString_CompletionExtensions.h
//  Quicksilver
//
//  Created by Nicholas Jitkoff on Mon Mar 03 2003.
//  Copyright (c) 2003 Blacktree, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (Replacement)
- (NSString *) stringByReplacing:(NSString *)search with:(NSString *)replacement;

@end