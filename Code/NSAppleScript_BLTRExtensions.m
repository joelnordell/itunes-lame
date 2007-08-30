//
//  NSAppleScript_BLTRExtensions.m
//  Quicksilver
//
//  Created by Nicholas Jitkoff on Thu Aug 28 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import "NSAppleScript_BLTRExtensions.h"

#import <Carbon/Carbon.h>
@implementation NSAppleScript (Subroutine)
- (NSAppleEventDescriptor *)executeSubroutine:(NSString *)name arguments:(id)arguments error:(NSDictionary **)errorInfo{
 //   NSLog(@"Handlers: %@",[self handlers]);
    NSAppleEventDescriptor* event;
    NSAppleEventDescriptor* targetAddress;
    NSAppleEventDescriptor* subroutineDescriptor;
    // NSAppleEventDescriptor* arguments;
    if (arguments && ![arguments isKindOfClass:[NSAppleEventDescriptor class]])
        arguments=[NSAppleEventDescriptor descriptorWithObject:arguments];
    if (arguments && [arguments descriptorType]!=cAEList){
        NSAppleEventDescriptor *argumentList=[NSAppleEventDescriptor listDescriptor];
        [argumentList insertDescriptor:arguments atIndex:[arguments numberOfItems]+1];
        arguments=argumentList;
    }
    int pid = [[NSProcessInfo processInfo] processIdentifier];
    targetAddress = [[[NSAppleEventDescriptor alloc] initWithDescriptorType:typeKernelProcessID bytes:&pid length:sizeof(pid)]autorelease];
    event = [[[NSAppleEventDescriptor alloc] initWithEventClass:kASAppleScriptSuite eventID:kASSubroutineEvent targetDescriptor:targetAddress returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID]autorelease];
    subroutineDescriptor = [NSAppleEventDescriptor descriptorWithString:name];
    [event setParamDescriptor:subroutineDescriptor forKeyword:keyASSubroutineName];
    if (arguments) [event setParamDescriptor:arguments forKeyword:keyDirectObject];
    return [self executeAppleEvent:event error:errorInfo];
}
@end

@implementation NSAppleEventDescriptor (CocoaConversion)
+ (NSAppleEventDescriptor *)descriptorWithObject:(id)object{
    NSAppleEventDescriptor *descriptorObject=nil;
    if ([object isKindOfClass:[NSArray class]]){
        descriptorObject=[NSAppleEventDescriptor listDescriptor];
        int i;
        for (i=0;i<[object count];i++){
            [descriptorObject insertDescriptor:[NSAppleEventDescriptor descriptorWithObject:[object objectAtIndex:i]]
                                       atIndex:i+1];
        }
        return descriptorObject; 
    }
    else if ([object isKindOfClass:[NSString class]]){
        return [NSAppleEventDescriptor descriptorWithString:object];
    }else if ([object isKindOfClass:[NSNumber class]]){
        return [NSAppleEventDescriptor descriptorWithInt32:[object intValue]];
    }else if ([object isKindOfClass:[NSAppleEventDescriptor class]]){
        return object;
    }else if ([object isKindOfClass:[NSNull class]]){
        return [NSAppleEventDescriptor nullDescriptor];
    }
    
    return nil;
}
- (id)objectValue{
    // NSLog(@"Convert type: %@",NSFileTypeForHFSTypeCode([self descriptorType]));
    switch ([self descriptorType]){
        case kAENullEvent:
            return nil;
        case cAEList:
        {
            NSMutableArray *array=[NSMutableArray arrayWithCapacity:[self numberOfItems]];
            int i;
            id theItem;
            // NSAppleEventDescriptor *itemDescriptor;
            for (i=0;i<[self numberOfItems];i++){
                theItem=[[self descriptorAtIndex:i+1]objectValue];
                if (theItem)[array addObject:theItem];
            }
                return array;
        }
        case cBoolean:
            return [NSNumber numberWithBool:[self booleanValue]];
            
            //   if (typeAERecord==[self descriptorType]) {
            //      return [NSNumber numberWithBool:[self booleanValue]];
            //    }
        default:
            return [self stringValue];
    }
    return nil;
}

+ (NSAppleEventDescriptor *)descriptorWithPath:(NSString *)path{
    if (!path)return 0;
  //  AppleEvent event, reply;
    OSErr err;
    FSRef fileRef;
    AliasHandle fileAlias;
    err = FSPathMakeRef([path fileSystemRepresentation], &fileRef, NULL);
    if (err != noErr) return nil;
    err = FSNewAliasMinimal(&fileRef, &fileAlias);
    if (err != noErr) return nil;
    return [NSAppleEventDescriptor descriptorWithDescriptorType:typeAlias bytes:fileAlias length:sizeof(*fileAlias)];
        
}

@end