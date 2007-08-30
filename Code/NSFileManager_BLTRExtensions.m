//
//  NSFileManager_CarbonExtensions.m
//  Quicksilver
//
//  Created by Nicholas Jitkoff on Thu Apr 03 2003.
//  Copyright (c) 2003 Blacktree, Inc. All rights reserved.
//

#import "NSFileManager_BLTRExtensions.h"


#import "Carbon/Carbon.h"

@implementation NSFileManager (BLTRExtensions)

- (BOOL)createDirectoriesForPath:(NSString *)path{
    //  NSLog(@"creating folder: (%@)",path);
    if (![path length]) return NO;
    if (![self fileExistsAtPath:[path stringByDeletingLastPathComponent] isDirectory:nil])
        [self createDirectoriesForPath:[path stringByDeletingLastPathComponent]];
    
    return [self createDirectoryAtPath:path attributes:nil];

}




- (NSString *)fullyResolvedPathForPath:(NSString *)sourcePath{
    NSEnumerator *enumer=[[[[sourcePath stringByStandardizingPath]stringByResolvingSymlinksInPath] pathComponents]objectEnumerator];
    NSString *thisComponent;
    NSString *path=@"";
    while(thisComponent=[enumer nextObject]){
        path=[path stringByAppendingPathComponent:thisComponent];
        
        if (![self fileExistsAtPath:path])continue;
        
        LSItemInfoRecord infoRec;
        LSCopyItemInfoForURL((CFURLRef)[NSURL fileURLWithPath:path],
							 kLSRequestBasicFlagsOnly, &infoRec);
        
        if (infoRec.flags & kLSItemInfoIsAliasFile)
            path=[[self resolveAliasAtPath:path]stringByResolvingSymlinksInPath];
        
        
		// NSLog(path);
    }
    return path;
}



- (NSString *)resolveAliasAtPath:(NSString *)aliasFullPath{
    NSString *outString = nil;
    //  Boolean success = false;
    NSURL *url;
    FSRef aliasRef;
    //  OSErr anErr = noErr;
    Boolean targetIsFolder;
    Boolean wasAliased;
    
    if (!CFURLGetFSRef((CFURLRef)[NSURL fileURLWithPath:aliasFullPath], &aliasRef))
        return nil;
    
    
    if (FSResolveAliasFileWithMountFlags(&aliasRef, true, &targetIsFolder, &wasAliased,kResolveAliasFileNoUI) != noErr)
        return nil;
    
    if (url = (NSURL *) CFURLCreateFromFSRef(kCFAllocatorDefault, &aliasRef)){
        outString=[url path];
        CFRelease(url);
        return outString;
    }
    
    return nil;
}


@end