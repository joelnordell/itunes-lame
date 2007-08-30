//
//  NSString_CompletionExtensions.m
//  Quicksilver
//
//  Created by Nicholas Jitkoff on Mon Mar 03 2003.
//  Copyright (c) 2003 Blacktree, Inc. All rights reserved.
//

#import "NSString_BLTRExtensions.h"


@implementation NSString (Replacement)

- (NSString *) stringByReplacing:(NSString *)search with:(NSString *)replacement{
	NSMutableString *result=[NSMutableString stringWithCapacity:[self length]];
	[result setString:self];
	[result replaceOccurrencesOfString:search withString:replacement options:NSLiteralSearch range:NSMakeRange(0,[self length])];
	return result;
}

@end

@implementation NSString (PathWildcard)

-(NSString *)firstUnusedFilePath{
	NSString *basePath=[self stringByDeletingPathExtension];
	NSString *extension=[self pathExtension];
	NSString *alternatePath=self;
	int i;
	for (i=1;[[NSFileManager defaultManager] fileExistsAtPath:alternatePath]; i++)
		alternatePath=[NSString stringWithFormat:@"%@ %d.%@",basePath,i,extension];
	return alternatePath;
}

@end
