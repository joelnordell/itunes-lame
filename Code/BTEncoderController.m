#import "BTEncoderController.h"
#import <Carbon/Carbon.h>
#import <QuickTime/QuickTime.h>
#import <QuickTime/QTML.h>
#import "BDAlias.h"



#import "NSFileManager_BLTRExtensions.h"
#import "NSWorkspace_BLTRExtensions.h"
#import "NSString_BLTRExtensions.h"
#import "NSApplication_BLTRExtensions.h"
#import "NSAppleScript_BLTRExtensions.h"

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/param.h>
#include <sys/ucred.h>
#include <sys/mount.h>
#include <sys/types.h>
#include <sys/uio.h>

#include "id3tag.h"

#define GETTER_SCRIPT @"tell application \"iTunes\"\rset thePlaylist to view of front window\rif class of thePlaylist is not in {user playlist, audio CD playlist} then error \"Invalid Playlist\"\rset theList to every track in thePlaylist whose enabled is true\rset theRecordList to {}\rrepeat with theTrack in theList\rset theLocation to \"\"\rtry\rif class of theTrack = file track then set theLocation to POSIX path of (location of theTrack as alias)\rtell theTrack to set end of theRecordList to {kind,class of theTrack as string, theLocation, name as string, artist as string, composer as string, album as string, comment as string, genre as string, year, track number, track count, disc number, disc count, compilation}\rend try\rend repeat\rend tell\rdelay 0.1\rreturn {theRecordList, name of thePlaylist}"
#define keyArray [NSArray arrayWithObjects: @"pKnd",@"pcls", @"pLoc", @"pnam", @"pArt",@"pCmp",@"pAlb", @"pCmt", @"pGen", @"pGrp", @"pYr ",@"pTrN",@"pTrC",@"pDsN", @"pDsC",@"pAnt", @"pAlA", @"pSAr", @"pSAA", @"pSNm", @"pSAl", @"pSCm", nil]

#define iTunesPath	@"/Applications/iTunes.app"

#define kLameInFile	@"Source File"
#define kLameTempFile	@"Temp File"
#define kLameOutFile	@"Destination File"
#define kTrackTags	@"Tags"
#define kCacheTask	@"Cache Task"
#define kEncoderTask	@"Encoder Task"
#define kEncoderOutput	@"Encoder Output"
#define kCDPath		@"CD Path"
#define kTrackName	@"Track Name"
#define kDeleteSource	@"Delete Source"
#define kCDPath		@"CD Path"

#define kTrackCachedNotification @"Track Cached"
#define kTrackEncodedNotification @"Track Encoded"

// keys for UserDefaults
#define encodingOptionsKey @"encodingOptions"
#define kMulti		@"multi"
#define kVComment		@"vcomment"
#define kShouldCache @"cache"
#define kDestination		@"destination"
#define kUseAlternateName		@"useAlternateName"
#define kAlternateName		@"alternateName"
#define kPlaylistName		@"playlistName"
#define kUseSelection		@"useSelection"
#define kCacheLocation		@"cacheLocation"
#define kOmitDefiniteArticleInPathsKey	@"omitDefiniteArticleInPaths"

#define gDefaultName @"%a:%l:%n. %t"
#define gDefaultNameNoTrack @"%a:%l:%t"



NSString* osTypeToFourCharCode(OSType inType)
{
    char code[5];
    memcpy(code,&inType,sizeof(inType));
    code[4] = 0;
    return [NSString stringWithCString:code];
}



bool trackForFile(NSString *filepath, AEDesc *replyDesc){
    if (!filepath)return 0;
    AppleEvent event, reply;
    OSErr err;
    OSType iTunesAdr = 'hook';
    FSRef fileRef;
    AliasHandle fileAlias;
    err = FSPathMakeRef((const UInt8 *)[filepath fileSystemRepresentation], &fileRef, NULL);
    if (err != noErr) return 0;
    err = FSNewAliasMinimal(&fileRef, &fileAlias);
    if (err != noErr) return 0;
    err = AEBuildAppleEvent
        ('hook', 'Add ', typeApplSignature, &iTunesAdr, sizeof(iTunesAdr),
         kAutoGenerateReturnID, kAnyTransactionID, &event, NULL,
         "'----':alis(@@)", fileAlias);
    if (err != noErr) return 0;
    err = AESend(&event, &reply, kAEWaitReply, kAENormalPriority,kAEDefaultTimeout, NULL, NULL);
	
    err = AEGetParamDesc(&reply, keyDirectObject, typeWildCard,replyDesc);
	
    AEDisposeDesc(&event);
    AEDisposeDesc(&reply);
    return 1;
}

OSType fourCharCodeToOSType(NSString* inCode)
{
    OSType rval = 0;
    NSData* data = [inCode dataUsingEncoding: NSMacOSRomanStringEncoding];
    [data getBytes:&rval length:sizeof(rval)];
    return rval;
}

static void set_text_frame(struct id3_tag *tag, const char *id, const id3_utf8_t *value) {
  struct id3_frame *frame = NULL;
  
  if (!value || !*value) return; // Blank value == skip this frame
  
  // We shouldn't have to bother looking for existing frames, because we know this
  // file was just encoded.
  frame = id3_frame_new(id);
  if (frame == 0) {
    NSLog(@"Unable to create frame %s",id);
    return;
  }
  id3_tag_attachframe(tag, frame);
  
  id3_ucs4_t *ucs4 = id3_utf8_ucs4duplicate(value);
  if (id3_field_setstrings(&frame->fields[1], 1, &ucs4) == -1) {
    NSLog(@"Unable to set frame %s",id);
    id3_frame_delete(frame);
    return;
  }
}


static void set_comment(struct id3_tag *tag, const id3_utf8_t *value) {
  struct id3_frame *frame = NULL;
  if (!value || !*value) return;

  frame = id3_frame_new(ID3_FRAME_COMMENT);
  if (frame == 0) {
    NSLog(@"Unable to create frame %s",ID3_FRAME_COMMENT);
    return;
  }
  id3_tag_attachframe(tag, frame);

  if (id3_field_setlanguage(&frame->fields[1], "eng") != 0) {
    NSLog(@"Failed setting comment language\n");
    id3_frame_delete(frame);
    return;
  }

  id3_ucs4_t *ucs4 = id3_utf8_ucs4duplicate(value);
  if (id3_field_setfullstring(&frame->fields[3], ucs4) == -1) {
    NSLog(@"Unable to set frame %s",ID3_FRAME_COMMENT);
    id3_frame_delete(frame);
    return;
  }
}

static void add_comment(struct id3_tag *tag, NSString *language, NSString *description, NSString *comment) {
	struct id3_frame *frame = NULL;

	if (! comment || [comment isEqualToString:@""]) return;

	frame = id3_frame_new(ID3_FRAME_COMMENT);
	if (frame == 0) {
		NSLog(@"Couldn't create frame %s", ID3_FRAME_COMMENT);
		return;
	}
	id3_tag_attachframe(tag, frame);

	if (! language || [language isEqualToString:@""]) language = @"eng";
	char buf[4];
	if (YES != [language getCString:buf maxLength:4 encoding:NSUTF8StringEncoding]) {
		NSLog(@"Couldn't use [%@] as a language", language);
		id3_frame_delete(frame);
		return;
	}

	if (id3_field_setlanguage(&frame->fields[1], buf) != 0) {
		NSLog(@"Couldn't set language [%@] in frame field 1", language);
		id3_frame_delete(frame);
		return;
	}

	if (! [description isEqualToString:@""]) {
		if (id3_field_setstring(&frame->fields[2], id3_utf8_ucs4duplicate((id3_utf8_t const *)[description UTF8String])) != 0) {
			NSLog(@"Couldn't set description [%@] in frame field 2", description);
			id3_frame_delete(frame);
			return;
		}
	}

	if (id3_field_setfullstring(&frame->fields[3], id3_utf8_ucs4duplicate((id3_utf8_t const *)[comment UTF8String])) != 0) {
		NSLog(@"Couldn't set user text [%@] in frame field 3", comment);
		id3_frame_delete(frame);
		return;
	}
}

static void prepend_bytes_to_file(int fd, int n) {
  // Go through the file, starting at the end, and move everything over by n bytes.
  int fsize = lseek(fd, 0, SEEK_END);
  int p = fsize;
  int chunkSize = 1024 * 128; // Seems like a reasonable tradeoff between speed and memory efficiency
  char *buf = (char*)malloc(chunkSize);

  while (p > 0) {
    p -= chunkSize;
    if (p < 0) {
      chunkSize += p; // Reduce the chunk size by however far we overshot the beginning.
      p = 0;
    }
    
    pread(fd, buf, chunkSize, p);
    pwrite(fd, buf, chunkSize, p+n);
  }
  
  free(buf);
}

@interface BTEncoderController (Tags)

// assembles an ID3v1.1 tag from a track's tagData and returns it in an NSData
-(NSData *)id3v1ForTrack:(NSDictionary *)track;

@end


FOUNDATION_EXPORT BOOL NSDebugEnabled;
@implementation BTEncoderController



+ (void)initialize {
	
    NSMutableDictionary *defaultValues = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"LAME Import",kPlaylistName,nil];
    [defaultValues setObject:[NSArray arrayWithObjects:@"--alt-preset standard",@"-h -b 160",nil]forKey:encodingOptionsKey];
    //[defaultValues setObject:[NSNumber numberWithInt:21] forKey:@"NSExceptionHandlingMask"];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultValues];
	
    if (MPProcessors()>1){
        NSLog(@"Multiprocessing Enabled");   
    }else{
        [[NSUserDefaults standardUserDefaults]removeObjectForKey:kMulti];
    }
    if(GetCurrentKeyModifiers() & (optionKey | rightOptionKey))
        NSDebugEnabled=YES;
	
}

- (void)handleAppleEvent:(NSAppleEventDescriptor *)event withReplyEvent: (NSAppleEventDescriptor *)replyEvent{
    NSLog(@"handl");
}
- (void) awakeFromNib{
	/*
	 [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
														andSelector:@selector(handleAppleEvent:withReplyEvent:)
													  forEventClass:kAEMacPowerMgtEvt
														 andEventID:kAEMacToWake
		 ];
	 */
	
	
    launching=YES;
	
    //Compile the script
    int i;
    NSWorkspace *workspace=[NSWorkspace sharedWorkspace];
    
    [workspace launchApplication:iTunesPath];
    for (i=0;![workspace dictForApplicationName:iTunesPath] && i<100;i++){
        NSLog(@"Waiting for iTunes");
        [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:.25]];
    }
    [NSApp activateIgnoringOtherApps:YES];
    NSDictionary *errorDict=nil;
    playlistGetter = [[NSAppleScript alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[[NSBundle mainBundle]pathForResource:@"Import with LAME..." ofType:@"scpt"]] error:&errorDict];
    //playlistGetter = [[NSAppleScript alloc] initWithSource:GETTER_SCRIPT];
    [playlistGetter compileAndReturnError:&errorDict];
    if (errorDict) [NSException raise:@"Unable to compile script" format:@"Error: %@",[errorDict objectForKey: @"NSAppleScriptErrorMessage"]];
	
    
    
    
    [encoderWindow setCanHide:YES];
    [encoderWindow setMiniwindowImage:[NSImage imageNamed:@"NSApplicationIcon"]];
	
    [encoderWindow setHidesOnDeactivate:NO];
    canValidate=[self validateOptions:@"" error:nil];
	
    if (!canValidate){
        NSLog(@"This version of LAME can't validate options");
		
        [validButton setState:NO];
    }
    [self setProgressFieldValue:@""];
    [progressIndicator setStyle:NSProgressIndicatorSpinningStyle];
    [progressIndicator setDisplayedWhenStopped:NO];
    //NSArray *trackPaths=[self getCDTrackPaths:[[self getCDPaths]lastObject]];
    [versonField setStringValue:[NSApp versionString]];
    NSString *lameVersion=[self lameVersion];
    [lameVersionField setStringValue:[NSString stringWithFormat: @"LAME v%@",lameVersion]];
	
    NSLog(@"LAME v%@ found: %@",[self lameVersion],[self lamePath]);
    // [self getMusicFolder];
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    //[encoderWindow center];
	
    [optionsField addItemsWithObjectValues:[defaults arrayForKey:encodingOptionsKey]];
    [optionsField setStringValue:[optionsField itemObjectValueAtIndex:0]];
	
    activating=NO;
    encoding=NO;
    forceTerminate=NO;
	
	
    [trackNameField setStringValue:@""];
    [trackProgressField setStringValue:@""];
    [trackProgressBar setDoubleValue:0];
	
    
    outFiles=[[NSMutableArray alloc]initWithCapacity:1];
    pendingArray=[[NSMutableArray alloc]initWithCapacity:1];
    cachingArray=[[NSMutableArray alloc]initWithCapacity:1];
    preparedArray=[[NSMutableArray alloc]initWithCapacity:1];
    encodingArray=[[NSMutableArray alloc]initWithCapacity:1];
    completeArray=[[NSMutableArray alloc]initWithCapacity:1];
    
    encoderWindowSize=[encoderWindow frame].size;
    encodingBoxHeight=NSHeight([encodingBox frame]);
	
    if (![encoderWindow setFrameUsingName:@"encoderWindow"])
        [encoderWindow center];
    [self updateEncoderWindowSizeEncoding:NO multi:NO];
	
    SInt32 version;
    Gestalt (gestaltSystemVersion, &version);
	
    if(version < 0x1030 ){
        [helpButton setBezelStyle:NSShadowlessSquareBezelStyle];
        [aboutButton setBezelStyle:NSShadowlessSquareBezelStyle];
        [prefsButton setBezelStyle:NSShadowlessSquareBezelStyle];        
    }
    
	
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(taskDidTerminate:) name:NSTaskDidTerminateNotification object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(appChanged:) name:@"com.apple.HIToolbox.menuBarShownNotification" object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(appTerminated:) name:NSWorkspaceDidTerminateApplicationNotification object:nil];
	
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStatus:) name:NSFileHandleDataAvailableNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(encodeLoop) name:kTrackCachedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(encodeLoop) name:kTrackEncodedNotification object:nil];
    
	
    //[self appChanged:nil];
}


- (void)updateEncoderWindowSizeEncoding:(BOOL)isEncoding multi:(BOOL)isMulti{
    NSRect currentFrame=[encoderWindow frame];
	
    NSSize newSize=encoderWindowSize;
	
    if (!isEncoding)
        newSize.height-=encodingBoxHeight-2;
    else if (!isMulti)
        newSize.height-=encodingBoxHeight-[trackProgress2Bar frame].origin.y-2;
	
	
	//    NSLog(@"%f",[trackProgress2Bar frame].origin.y);
    if (!NSEqualSizes(currentFrame.size,newSize)){
        //NSLog(@"sizeChange");
        float heightChange=newSize.height-currentFrame.size.height;
        currentFrame.size.height+=heightChange;
        currentFrame.origin.y-=heightChange;
		
        [encoderWindow setFrame:currentFrame display:YES animate:YES];
    }
    // else NSLog(@"no sizeChange");
	
	
}


- (void)appChanged:(NSNotification *)aNotification{
    //NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    //NSLog(@"appchanged");
	
	//   NSString *currentApp=[[[NSWorkspace sharedWorkspace] activeApplication] objectForKey:@"NSApplicationName"];
	
	// //  bool wasInITunes=inITunes;
	//    inITunes=[currentApp isEqualToString:@"iTunes"];
	
	//  if (inITunes){
	//     [encoderWindow orderFront:nil]; //If window is active, show it
	//   }else{
	
	// [encoderWindow orderOut:nil];
	//    }
	//  if (![encoderWindow isMiniaturized])[encoderWindow orderFront:self];
	
    //    [encoderWindow setLevel:NSNormalWindowLevel];
	// if (!wasInITunes){
	//[encoderWindow setLevel:NSFloatingWindowLevel];
    //s        [encoderWindow setLevel:NSNormalWindowLevel];
	// }
	// activating=YES;
	//[NSApp activateIgnoringOtherApps:YES];
	//  if (!activating)[[NSWorkspace sharedWorkspace] activateApplication:iTunesPath];
    //}
	// else if (![currentApp isEqualToString:@"iTunes-LAME"]);

    //    NSLog(@"switch to %@",currentApp);
    /*
     if (active=[currentApp isEqualToString:@"iTunes"]){
         //[[HotKeyCenter sharedCenter] addHotKey:@"beatKey" combo:[KeyCombo keyComboWithKeyCode:48 andModifiers:optionKey] target:self action:@selector(beat:)];
         [BPMFloater orderFront:nil]; //If window is active, show it
     }else{
         //[[HotKeyCenter sharedCenter] removeHotKey:@"beatKey"];
         [BPMFloater orderOut:nil];
         [beatTimer invalidate];
         [beatButtonL setState:0];
         [beatButtonR setState:0];
}
//[mainWindow saveFrameUsingName:@"mainWindow"];
*/

}

- (IBAction)closeChooseCDPanel: (id)sender{
    [NSApp stopModal];
}


// The app's Main Action.
// Called encode: but won't encode.
// Button is called "Import".
//		- haiku by Rich Martin
- (IBAction)encode:(id)sender{
	//  NSLog(@"encode");

	// Re-click Import Button means "Abort" (this should go into the docs _RAM)
	// Shift-click Import Button means "Queue up some more tracks"
    if (encoding && !([[NSApp currentEvent]modifierFlags] & NSShiftKeyMask)){
        [self cancelEncoding:self];
        return;
    }

    // try to make sure the user-supplied LAME Encoding Options will actually work
    // Option-click Import Button means "Force processing even if options won't validate" (this should go into the docs _RAM)
    NSString *validateError=nil;	// whoops, validateOptions:error: returns bool now, no longer NSString _RAM
    if (canValidate && ![self validateOptions:[optionsField stringValue] error:&validateError]) {
        if (validateError) NSLog(@"Validation Error:%@",validateError);
        [self setProgressFieldValue:NSLocalizedString(@"Encoding Options are Invalid",@"Invalid Options Message")];
        if (!([[NSApp currentEvent]modifierFlags] & NSAlternateKeyMask)) return;
		
		
		
    }

    [encoderWindow makeFirstResponder:encoderWindow];
    [self setEncodingOptions:optionsField];

	// obtain track data from iTunes
	[self updateTracksArray];
	if (!tracksArray) return;
	
    NS_DURING
        
        NSFileManager *manager=[NSFileManager defaultManager];
        
        NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];

        // update the UI
        [progressIndicator setIndeterminate:YES];
        [progressIndicator startAnimation:self];
		
        [self setProgressFieldValue: NSLocalizedString(@"Preparing Tracks", @"Preparing Tracks")];
        NSString *lameVersion=[self lameVersion];

		// ask iTunes whether user likes track numbers in front of their filenames,
		// ask iTunes where user's root music folder is, just in case
        [self getMusicPreferences];
		// This message is misleading: musicDirectory will only be used for encoding as a fallback _RAM
        NSLog(@"Encoding to folder: %@",musicDirectory);
        //    [self setProgressFieldValue:[NSString stringWithFormat:@"Encoding to %@",musicPath]];
		
		
        NSArray *trackPaths=nil;
		
		// Prepare options for LAME,
		// combining user-supplied LAME Encoding Options (internal settings) with iT-L prefs
		// Get internal settings
		NSMutableArray *arguments=[NSMutableArray arrayWithCapacity:1];
		[arguments setArray:[[optionsField stringValue]componentsSeparatedByString:@" "]];
		
		bool includeComment=NO;
		bool multiProcess=NO;
		bool deleteSource=NO;
		
		bool shouldCache=NO;
		
		shouldCache=[defaults boolForKey:kShouldCache];
		includeComment=[defaults boolForKey:kVComment];
		multiProcess=[defaults boolForKey:kMulti];// || MPProcessors()>1 )

		// if "--delete-source" is in user-supplied LAME Encoding Options,
		// we need to process that ourselves: it is not a valid option for LAME
		// Hmmm...wouldn't validateOptions:error above choke on this? _RAM
			if (deleteSource=[arguments containsObject:@"--delete-source"])
				[arguments removeObject:@"--delete-source"];
			
			
			NSMutableDictionary *track;
			NSMutableDictionary *tags;
			bool mp3input;
			int i;
			
			BOOL protectedWarning=NO;

			// only reset totalTracks if we're not appending new tracks to the job
			if(!encoding)
				totalTracks=0;

			// this loop is too huge. it needs simplification _RAM
			for(i=0; i<[tracksArray count];i++){
				
				track=[tracksArray objectAtIndex:i];
				tags=[track objectForKey:kTrackTags];

				// all this outFile business could be encapsulated by yet another instance method _RAM
				//=-=-=-=-=-=-=-=-=-=-=-= Construct Output Filepath =-=-=-=-=-=-=-=-=
				NSString *escapedAlbum =			[[[[tags objectForKey:@"pAlb"]stringValue]stringByReplacing:@"/" with:@"_"]stringByReplacing:@":" with:@"_"];
				NSString *escapedSortAlbum =		[[[[tags objectForKey:@"pSAl"]stringValue]stringByReplacing:@"/" with:@"_"]stringByReplacing:@":" with:@"_"];
				NSString *escapedArtist =			[[[[tags objectForKey:@"pArt"]stringValue]stringByReplacing:@"/" with:@"_"]stringByReplacing:@":" with:@"_"];
				NSString *escapedAlbumArtist =		[[[[tags objectForKey:@"pAlA"]stringValue]stringByReplacing:@"/" with:@"_"]stringByReplacing:@":" with:@"_"];
				NSString *escapedSortAlbumArtist =	[[[[tags objectForKey:@"pSAA"]stringValue]stringByReplacing:@"/" with:@"_"]stringByReplacing:@":" with:@"_"];
				NSString *escapedSortArtist =		[[[[tags objectForKey:@"pSAr"]stringValue]stringByReplacing:@"/" with:@"_"]stringByReplacing:@":" with:@"_"];
				NSString *escapedName =				[[[[tags objectForKey:@"pnam"]stringValue]stringByReplacing:@"/" with:@"_"]stringByReplacing:@":" with:@"_"];
				NSString *escapedSortName =			[[[[tags objectForKey:@"pSNm"]stringValue]stringByReplacing:@"/" with:@"_"]stringByReplacing:@":" with:@"_"];
				NSString *escapedGenre =			[[[[tags objectForKey:@"pGen"]stringValue]stringByReplacing:@"/" with:@"_"]stringByReplacing:@":" with:@"_"];
				NSString *escapedGrouping =			[[[[tags objectForKey:@"pGrp"]stringValue]stringByReplacing:@"/" with:@"_"]stringByReplacing:@":" with:@"_"];
				NSString *year =					[NSString stringWithFormat:@"%d",[[tags objectForKey:@"pYr "] int32Value]];
				NSString *escapedComposer =			[[[[tags objectForKey:@"pCmp"]stringValue]stringByReplacing:@"/" with:@"_"]stringByReplacing:@":" with:@"_"];
				NSString *escapedSortComposer =		[[[[tags objectForKey:@"pSCm"]stringValue]stringByReplacing:@"/" with:@"_"]stringByReplacing:@":" with:@"_"];
				
				if ([[tags objectForKey:@"pAnt"]booleanValue])
					escapedArtist = NSLocalizedString(@"Compilations",@"Compilations Folder Name");
				
				NSString *outFile =[defaults stringForKey:kDestination];
				if (![outFile length])outFile=musicDirectory;
				
				
				
				NSString *nameTemplate=nil;
				if ([defaults boolForKey:kUseAlternateName])
					nameTemplate=[defaults stringForKey:kAlternateName];
				if (![nameTemplate length])
					nameTemplate=useTrackNumbers?gDefaultName:gDefaultNameNoTrack;
				
				
				nameTemplate= [nameTemplate stringByReplacing:@":" with:@"!#!"];
				nameTemplate= [nameTemplate stringByReplacing:@"/" with:@":"];
				nameTemplate= [nameTemplate stringByReplacing:@"!#!" with:@"/"];
				
				// *** these substitutions will mess up if tags contain the tokens
				if ([defaults boolForKey:kOmitDefiniteArticleInPathsKey]) {
					nameTemplate = [nameTemplate stringByReplacing:@"%a" with:(escapedArtist?[escapedArtist stringByRemovingLeadingDefiniteArticle]:NSLocalizedString(@"~Unknown Artist",@"Unknown Artist Folder Name"))];	// _RAM
				} else {
					nameTemplate= [nameTemplate stringByReplacing:@"%a" with:(escapedArtist?escapedArtist:NSLocalizedString(@"~Unknown Artist",@"Unknown Artist Folder Name"))];
				}
				nameTemplate = [nameTemplate stringByReplacing:@"%l" with:(escapedAlbum?escapedAlbum:NSLocalizedString(@"~Unknown Album",@"Unknown Album Folder Name"))];
				nameTemplate = [nameTemplate stringByReplacing:@"%n" with:[NSString stringWithFormat:@"%02d",[[tags objectForKey:@"pTrN"]int32Value]]];
				nameTemplate = [nameTemplate stringByReplacing:@"%y" with:(year ? year: NSLocalizedString(@"Unknown Year", @"Unknown Year"))];
				nameTemplate = [nameTemplate stringByReplacing:@"%t" with:(escapedName ? escapedName : NSLocalizedString(@"Unknown Title", @"Unknown Title"))];
				nameTemplate = [nameTemplate stringByReplacing:@"%T" with:(escapedSortName ? escapedSortName : NSLocalizedString(@"Unknown Sort Title", @"Unknown Sort Title"))];
				nameTemplate = [nameTemplate stringByReplacing:@"%g" with:(escapedGenre ? escapedGenre : NSLocalizedString(@"Unknown Genre", @"Unknown Genre"))];
				nameTemplate = [nameTemplate stringByReplacing:@"%G" with:(escapedGrouping ? escapedGrouping : NSLocalizedString(@"Unknown Grouping", @"Unknown Grouping"))];
				nameTemplate = [nameTemplate stringByReplacing:@"%A" with :(escapedSortArtist ? escapedSortArtist : NSLocalizedString(@"Unknown Sort Artist", @"Unknown Sort Artist"))];
				nameTemplate = [nameTemplate stringByReplacing:@"%L" with :(escapedSortAlbum ? escapedSortAlbum : NSLocalizedString(@"Unknown Sort Album", @"Unknown Sort Album"))];
				nameTemplate = [nameTemplate stringByReplacing:@"%b" with:(escapedAlbumArtist ? escapedAlbumArtist : NSLocalizedString(@"Unknown Album Artist", @"Unknown Album Artist"))];
				nameTemplate = [nameTemplate stringByReplacing:@"%B" with:(escapedSortAlbumArtist ? escapedSortAlbumArtist : NSLocalizedString(@"Unknown Sort Album Artist", @"Unknown Sort Album Artist"))];
				nameTemplate = [nameTemplate stringByReplacing:@"%c" with:(escapedComposer ? escapedComposer : NSLocalizedString(@"Unknown Composer", @"Unknown Composer"))];
				nameTemplate = [nameTemplate stringByReplacing:@"%C" with:(escapedSortComposer ? escapedSortComposer : NSLocalizedString(@"Unknown Sort Composer", @"Unknown Sort Composer"))];
				outFile =[outFile stringByAppendingPathComponent:nameTemplate];
				NSString *proposedOutFile=[outFile stringByAppendingString:@".mp3"];
				
				if (![manager fileExistsAtPath:proposedOutFile] && ![outFiles containsObject:proposedOutFile]) // if file is already being used.
					outFile=proposedOutFile;
				else{
					//***ask mwhether to replace
					//@"One or more of the songs you have selected to import have already been imported. Do you want to import them again?", @"Replace Existing", @"Cancel", @"Yes"
					int j;
					for (j=1;j<100;j++){
						proposedOutFile=[NSString stringWithFormat:@"%@ %d.mp3",outFile,j];
						if (![manager fileExistsAtPath:proposedOutFile] && ![outFiles containsObject:proposedOutFile]){
							outFile=proposedOutFile;
							//                    if (NSDebugEnabled) NSLog(@"Outfile existed, using alternate.");
							break;
						}
					}
				}
				//=-=-=-=-=-=-=-=-=-= end Construct Output Filepath =-=-=-=-=-=-=-=-=
				[outFiles addObject:outFile];
				
				if(includeComment && ![tags objectForKey:@"pCmt"])[tags setObject:[NSAppleEventDescriptor descriptorWithString:[NSString stringWithFormat:NSLocalizedString(@"Encoded with LAME v%@ (%@)", @"Encoded with LAME v%@ (%@)"),lameVersion,[arguments componentsJoinedByString:@" "]]] forKey:@"pCmt"];
				
				NSString *kind=[[tags objectForKey:@"pKnd"]stringValue];
				NSString *class=[[tags objectForKey:@"pcls"]stringValue];
				//NSLog(@"class:%@",class);

				// is this track already an MP3? if so, we will tell LAME to re-encode later
				mp3input=[kind rangeOfString:@"MPEG"].location!=NSNotFound; //*** can match a substring instead?
				
				int trackNumber=[[tags objectForKey:@"pTrN"]int32Value]-1;
				
				NSString *inFile=nil;
				NSString *tempFile=nil;
				bool cacheThisTrack=NO;
				bool invalidInFile=NO;
				NSString *cacheTool=nil;

				// is the source file a track on a CD-Audio disc?
				if ([class rangeOfString:@"CD"].location!=NSNotFound){
					if (multiProcess && !shouldCache){
						SInt32 version;
						Gestalt (gestaltSystemVersion, &version);
						if(version >= 0x1030 ){
							NSLog(@"Forcing Cache for Panther");
							shouldCache=YES;   
						}
					}
					
					cacheThisTrack=shouldCache;

					// assert our list of filenames for this CD
					if (!trackPaths){
						NSString *CDPath=[self currentCD];
						if (!CDPath) NSLog(@"Could not find CD");
						trackPaths=[self getCDTrackPaths:CDPath]; //Get list of tracks, but only the first time.
						
					}

					// assert good source file: track number is valid and its filePath is valid
					if (trackNumber<[trackPaths count]) inFile=[trackPaths objectAtIndex:trackNumber];
					if (invalidInFile=![manager fileExistsAtPath:inFile]){ // Bypass for bad cd listings
						NSLog(@"Track \"%@\" supposedly does not exist, using shell completion to match.",[inFile lastPathComponent]);
						inFile=[NSString stringWithFormat:@"%d\\ *.aiff",[[tags objectForKey:@"pTrN"]int32Value]];
					}
				}else{
					// the source file is on the hard disk
					inFile=[[tags objectForKey:@"pLoc"]stringValue];

					// skip over FairPlay-protected files
					if ([kind rangeOfString:@"AAC"].location!=NSNotFound && [[inFile pathExtension]isEqual:@"m4p"]){
						if (!protectedWarning){
							NSBeginCriticalAlertSheet(@"Protected Files",nil,nil,nil,encoderWindow,nil,nil,nil,nil,@"Some of the selected tracks are protected, and iTunes-LAME is unable to read data from them.");
							//	APPKIT_EXTERN void NSBeginCriticalAlertSheet(NSString *title, NSString *defaultButton, NSString *alternateButton, NSString *otherButton, NSWindow *docWindow, id modalDelegate, SEL didEndSelector, SEL didDismissSelector, void *contextInfo, NSString *msg, ...);
							
							protectedWarning=YES;
						}
						continue;
					}

					// unless source file is AIF, WAV or MP3, cache this track using qtaiff
					if ([kind rangeOfString:@"AIFF"].location==NSNotFound && [kind rangeOfString:@"WAV"].location==NSNotFound && !mp3input){
						cacheThisTrack=YES;
						cacheTool=[[NSBundle mainBundle]pathForResource:@"qtaiff" ofType:@""];
					}
				}
				
				if (cacheThisTrack){
					// create a name for the cache file
					tempFile=[[defaults objectForKey:kCacheLocation]stringByStandardizingPath];
					if (!tempFile)tempFile=NSTemporaryDirectory();
					tempFile=[tempFile stringByAppendingPathComponent:[NSString stringWithFormat: @"lame_input_%04d.aiff",totalTracks+1]];
				}
				// this message seems a bit out of place. can't it follow assignment of inFile above? _RAM
				if (!inFile) NSLog(@"Unable to obtain a source for track of kind \"%@\" and class \"%@\"",kind,class);
				
				// append the re-encode option to LAME args if source file is an MP3
				// this is an odd way to express it _RAM
				// and shouldn't the assignment of mp3input be move to here? _RAM
				NSString *options=[[optionsField stringValue]stringByAppendingString:(mp3input?@" --mp3input":@"")];
				
				if (NSDebugEnabled) NSLog(@"Track %d prepared%@\r\tSource:\t%@ (%@)\r\tDestination:\t%@\r\tOptions:\t%@",totalTracks+1, (tempFile?@" (Caching)":@""),inFile, kind, outFile, options);
				
				if (!inFile)[NSException raise:@"Unable to find Source" format:@"Track Kind is:%@",kind];
				if (!outFile)[NSException raise:@"Unable to find Destination" format:@""];
				
				
				[track setObject:inFile forKey:kLameInFile];
				[track setObject:outFile forKey:kLameOutFile];
				if (tempFile){
					[track setObject:tempFile forKey:kLameTempFile];
					NSTask *cacher=[self cacheTaskWithTool:cacheTool source:inFile destination:tempFile valid:!invalidInFile];
					if (cacher)
						[track setObject:cacher forKey:kCacheTask];
				}
				
				NSTask *encoder=[self lameTaskWithOptions:options source:(tempFile?tempFile:inFile) destination:outFile valid:!invalidInFile];
				if (encoder) [track setObject:encoder forKey:kEncoderTask];
				else  [NSException raise:@"Unable to prepare encoder" format:@""];
				if (deleteSource) [track setObject:[NSNumber numberWithBool:deleteSource] forKey:kDeleteSource];
				
				if (tempFile)
					[pendingArray addObject:track];
				else
					[preparedArray addObject:track];

				// totalTracks is displayed in UI
				totalTracks++;
			}
			
			
			
			if (NSDebugEnabled) NSLog(@"Preparing to Encode");
			[self setCurrentCD:nil];
			
			// we're done with tracksArray
			[self setTracksArray:nil];

			// update the UI
			if (!encoding){
				encoding=YES;
				
				[self updateEncodeButtonAppearance];
				
				currentTrack=0;
				
				[trackNameField setStringValue:NSLocalizedString(@"Preparing to Import...", @"Preparing to Import...")];
				[trackProgressField setStringValue:@""];
				
				[trackProgressBar setIndeterminate:YES];
				[trackName2Field setStringValue:NSLocalizedString(@"Preparing to Import...", @"Preparing to Import...")];
				[trackProgress2Field setStringValue:@""];
				[trackProgress2Bar setIndeterminate:YES];
				
				
				[trackNumberField setStringValue:@""];
				[self setProgressFieldValue:NSLocalizedString(@"Importing", @"Importing")];
				
				[self updateEncoderWindowSizeEncoding:encoding multi:NO];
			}
			
			
			if (![progressTimer isValid]){
				[progressTimer release];
				progressTimer = [[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updateStatus:) userInfo:nil repeats:YES]retain];
			}
			
			[progressIndicator stopAnimation:self];
			[self setProgressFieldValue:@""];
			
			// let the real work begin
			[self encodeLoop];
			
			
    NS_HANDLER
        NSBeginCriticalAlertSheet(NSLocalizedString(@"Import Error", @"Import Error"),nil,nil,nil,encoderWindow,nil,nil,nil,nil,@"%@\r%@",[localException name],[localException reason]);
        [progressIndicator stopAnimation:self];
    NS_ENDHANDLER
    
}

// Even though this contains no actual loop, it will be re-invoked often to process the list of tracks.
- (void) encodeLoop{
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    BOOL multiProcess=[defaults boolForKey:kMulti];

    // as long as there are prepared tracks and free processors, launch another encoding task
	// Two CPUs hardcoded here _RAM
    while ([preparedArray count] && [encodingArray count]<(multiProcess?2:1))
        [self encodeTrack:[preparedArray objectAtIndex:0]];
	
    // Any more tracks need caching? start another caching task only if none already in progress
    if ([pendingArray count] && ![cachingArray count])
        [self cacheTrack:[pendingArray objectAtIndex:0]];

    // update the UI
    [self updateTrackNumbers];
    [self updateEncoderWindowSizeEncoding:encoding multi:([encodingArray count]+[cachingArray count]>1)];
    
    NSLog(@"Status: %d pending, %d caching, %d prepared, %d encoding, %d complete",[pendingArray count],[cachingArray count],[preparedArray count],[encodingArray count],[completeArray count]);

    // all queues drained? another job well done!
    if (!([pendingArray count]+[cachingArray count]+[preparedArray count]+[encodingArray count])){
		if (NSDebugEnabled) NSLog(@"Import Complete");   
        [self finishEncodingWithError:nil];
    }
}
- (void) updateTrackNumbers{
    NSString *statusString;
    if ([encodingArray count]>1){
        statusString=[NSString stringWithFormat:NSLocalizedString(@"Tracks %d & %d of %d",@"Current Tracks Message (Multi)"), [completeArray count]+1,[completeArray count]+2,totalTracks];
    }else{
        statusString=[NSString stringWithFormat:NSLocalizedString(@"Track %d of %d",@"Current Track Message"), [completeArray count]+1,totalTracks];
    }
    
    if ([pendingArray count]){
        statusString=[statusString stringByAppendingString:[NSString stringWithFormat: @" (Caching %d)",[pendingArray count]+[cachingArray count]]];
    }
    [trackNumberField setStringValue:statusString];
    
}

// Launch the caching task for a given track.
- (void) cacheTrack:(NSDictionary *)track{
    if (NSDebugEnabled) NSLog(@"Caching track: %@ to %@",[track objectForKey:kTrackName],[track objectForKey:kLameTempFile]);
    NSFileManager *manager=[NSFileManager defaultManager];

	// Two CPUs hardcoded here _RAM
	// but we only need to know: is there a free progress view? (is [encodingArray count] less than numProcessors?)
	// we only need one free view, because there is only one cache task allowed at a time
    if ([encodingArray count]<2){
    	// update the UI
    	// this progress view will be at the top (primary) only if no encoding is underway
    	// otherwise, caching progress shows at the bottom of the window
        int primary=(![encodingArray count]);
		
        ILProgressView * thisProgressBar=primary?trackProgressBar:trackProgress2Bar;
        id thisNameField=primary?trackNameField:trackName2Field;
        id thisProgressField=primary?trackProgressField:trackProgress2Field;
        
        [thisProgressField setStringValue:@""];
        [thisProgressBar setIndeterminate:YES];
        [thisNameField setStringValue:[NSString stringWithFormat:@"Caching: \"%@\"",[track objectForKey:kTrackName]]];
        [thisNameField display];
    }

    // if cache file already exists, delete it before we create ours
    [manager removeFileAtPath:[track objectForKey:kLameTempFile] handler:nil];

	// move this track from pending queue to caching queue
	[cachingArray addObject:track];
    [pendingArray removeObject:track];

    [[track objectForKey:kCacheTask] launch];
}

// Launch the encoding task for a given track.
- (void) encodeTrack:(NSDictionary *)track{
    NSFileManager *manager=[NSFileManager defaultManager];

    // move this track from prepared queue to encoding queue
    [encodingArray addObject:track];
    [preparedArray removeObject:track];
    
	//  NSString *inFile=[track objectForKey:kLameInFile];
	//   NSString *tempFile=[track objectForKey:kLameTempFile];
    
    
    NSTask *encoder=[track objectForKey:kEncoderTask];

    // assert path to destination folder
    [manager createDirectoriesForPath:[[track objectForKey:kLameOutFile]stringByDeletingLastPathComponent]];
    
    NSPipe *outputPipe=[NSPipe pipe];
    
    if (!outputPipe) NSLog(@"Unable to create output pipe");
    else [encoder setStandardError:outputPipe];
    
    //    [[[encoder standardError]fileHandleForReading]waitForDataInBackgroundAndNotify];
    [encoder launch];
}

- (IBAction)openWebsiteForToolTip:(id)sender{[[NSWorkspace sharedWorkspace]openURL:[NSURL URLWithString:[sender toolTip]]];}
- (void)abortAllFiles{
    int i;
    for (i=0;i<[encodingArray count];i++){
        [[[encodingArray objectAtIndex:i] objectForKey:kEncoderTask]terminate];
        [[NSFileManager defaultManager] removeFileAtPath:[[encodingArray objectAtIndex:i] objectForKey:kLameOutFile] handler:nil];
        [[NSFileManager defaultManager] removeFileAtPath:[[encodingArray objectAtIndex:i] objectForKey:kLameTempFile] handler:nil];    }
    for (i=0;i<[cachingArray count];i++){
        [[[cachingArray objectAtIndex:i] objectForKey:kCacheTask]terminate];
        [[NSFileManager defaultManager] removeFileAtPath:[[cachingArray objectAtIndex:i] objectForKey:kLameTempFile] handler:nil];
    }
    for (i=0;i<[pendingArray count];i++){
        [[NSFileManager defaultManager] removeFileAtPath:[[pendingArray objectAtIndex:i] objectForKey:kLameTempFile] handler:nil];
    }
}
- (IBAction)cancelEncoding: (id)sender{
    encoding=NO;
    [progressTimer invalidate];
    [self updateEncoderWindowSizeEncoding:NO multi:NO];
	
    [trackProgressBar setDoubleValue:0];
    [trackProgressBar display];
    
    [self abortAllFiles];
    [outFiles removeAllObjects];
    
    [pendingArray removeAllObjects];
    [cachingArray removeAllObjects];
    [preparedArray removeAllObjects];
    [encodingArray removeAllObjects];
    [completeArray removeAllObjects];
	
    [self updateEncodeButtonAppearance];
    [self setProgressFieldValue:NSLocalizedString(@"Import Cancelled", @"Import Cancelled")];
}



-(void)finishEncodingWithError:(NSString *)error{
    encoding=NO;
    [progressTimer invalidate];
    [self updateEncoderWindowSizeEncoding:NO multi:NO];
    [trackNameField setStringValue:@""];
    [trackProgressField setStringValue:@""];
    [trackProgressBar setDoubleValue:0];
    [trackProgressBar display];
	
    if (error){
        if (![error length]) error=NSLocalizedString(@"Unknown Error", @"Unknown Error");
        NSBeep();
        NSBeginCriticalAlertSheet(NSLocalizedString(@"Import Error", @"Import Error"),nil,nil,nil,encoderWindow,nil,nil,nil,nil,
                                  NSLocalizedString(@"An error occured during import:\r%@",@"Error Message"),error);
        [self abortAllFiles];
    }else{
        [self setProgressFieldValue:[NSString stringWithFormat:NSLocalizedString(@"Imported %d %@",@"Import success"),[completeArray count],([completeArray count]==1?NSLocalizedString(@"track", @"track"):NSLocalizedString(@"tracks", @"tracks (plural)"))]];
        [[NSSound soundNamed:@"EncodingComplete"]play]; //***make this work
    }
	
    [outFiles removeAllObjects];
    
    [pendingArray removeAllObjects];
    [cachingArray removeAllObjects];
    [preparedArray removeAllObjects];
    [encodingArray removeAllObjects];
    [completeArray removeAllObjects];
	
    [self updateEncodeButtonAppearance];
}



- (void) updateStatus:(NSNotification *)aNotification{
    NSFileHandle *outputHandle;//=[aNotification object];
    
    if (!encoding || ![encodingArray count]) return;
	
    int i;
    BOOL primary;
    for (i=0;i<[encodingArray count];i++){
		
        
		
        if (![[[[encodingArray objectAtIndex:i]objectForKey:kEncoderTask]standardError]respondsToSelector:@selector(fileHandleForReading)]) return;
        outputHandle=[[[[encodingArray objectAtIndex:i]objectForKey:kEncoderTask]standardError]fileHandleForReading];
        //primary=(outputHandle==[[[[encodingArray objectAtIndex:0]objectForKey:kEncoderTask]standardError]fileHandleForReading]);
        primary=!i;
        
        ILProgressView * thisProgressBar=primary?trackProgressBar:trackProgress2Bar;
        id thisNameField=primary?trackNameField:trackName2Field;
        id thisProgressField=primary?trackProgressField:trackProgress2Field;
		
        NSMutableDictionary *track=[encodingArray objectAtIndex:!primary];
        NSString *string=[[[NSString alloc] initWithData:[outputHandle availableData] encoding:NSUTF8StringEncoding]autorelease]; //Find a way not to block!
        if (![string length])return;
		
        NSString *lastLine=nil;
        NSScanner *lineScanner=[NSScanner scannerWithString:string];
        while ([lineScanner scanUpToString:@"\r" intoString:&lastLine]);
        if (![lastLine length])return;
        float speed;
        float progress=0;
        NSString *remainingTime=nil;
		
        [self scanProgressString:lastLine intoProgress:&progress rate:&speed remainingTime:&remainingTime];
		
        [thisNameField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Importing: \"%@\"",@"Importing Message"),[track objectForKey:kTrackName]]];
        if (remainingTime) [thisProgressField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Time Remaining: %@ (%.1fx)",@"Time Remaining Message"),remainingTime,speed]];
        [thisProgressBar setIndeterminate:NO];
        [thisProgressBar setDoubleValue:100*progress];
		
    }
	// [outputHandle waitForDataInBackgroundAndNotify];
    
}

- (bool) scanProgressString:(NSString *)string intoProgress:(float *)progress rate:(float *)rate remainingTime:(NSString **)remainingTime{
    
    int doneFrames, totalFrames;
    NSString *test=nil;
    NSScanner *progressScanner=[NSScanner scannerWithString:string];
    [progressScanner scanInt:&doneFrames];
    [progressScanner scanString:@"/" intoString:&test];
    [progressScanner scanInt:&totalFrames];
    [progressScanner scanUpToString:@"|" intoString:&test];
    [progressScanner scanString:@"|" intoString:&test];
    [progressScanner scanUpToString:@"|" intoString:&test];
    [progressScanner scanString:@"|" intoString:&test];
    [progressScanner scanUpToString:@"|" intoString:&test];
    [progressScanner scanString:@"|" intoString:&test];
    [progressScanner scanFloat:rate];
    [progressScanner scanString:@"x|" intoString:&test];
    [progressScanner scanUpToString:@"\r" intoString:remainingTime];
	
    *progress=(float)doneFrames/(float)totalFrames;
	
    return YES;
}

- (void) updateEncodeButtonAppearance{
    bool shiftDown=[[NSApp currentEvent]modifierFlags] & NSShiftKeyMask;
    if (encoding){
        if (shiftDown){
            [encodeButton setImage:[NSImage imageNamed:@"ImportButtonS"]];
            [encodeButton setAlternateImage:[NSImage imageNamed:@"ImportButtonSP"]];
        }else{
            [encodeButton setImage:[NSImage imageNamed:@"ImportButtonI"]];
            [encodeButton setAlternateImage:[NSImage imageNamed:@"ImportButtonIP"]];
        }
    }else{
        [encodeButton setImage:[NSImage imageNamed:@"ImportButton"]];
        [encodeButton setAlternateImage:[NSImage imageNamed:@"ImportButtonI"]];
    }
	
}

// Notification handler
// We observe this notification to sense the completion of caching and encoding tasks.
- (void)taskDidTerminate:(NSNotification *)aNotification{
    NSTask *task=[aNotification object];
    
    // if the cache queue has a track in it (cache queue is limited to one track),
    // if this is its completion, post a notification to start a new task, then bail.
    if ([cachingArray count]){
        NSDictionary *cachingTrack=[cachingArray lastObject];
        if (task==[cachingTrack objectForKey:kCacheTask]){
            //   NSLog(@"Caching Finished: %@",[cachingTrack objectForKey:kTrackName]);
            [preparedArray addObject:cachingTrack];
            [cachingArray removeObject:cachingTrack];
            if (![pendingArray count]) NSBeep();
            [[NSNotificationCenter defaultCenter]postNotificationName:kTrackCachedNotification object:nil];
            return;
        }
    }

	// so there was nothing in the cache queue - is this one of our encoding tasks?
    NSMutableDictionary *track=[self trackForTask:task];
	
    // encoding becomes false on error or after the last track is encoded
    if (track && encoding){
    	// primary is true when this task is at index zero,
    	// so we will update the progress view at the top of the window
        int primary=![encodingArray indexOfObject:track];
		
		
        if (NSDebugEnabled) NSLog(@"Queued:%d Encoding:%d Complete:%d",[preparedArray count],[encodingArray count],[completeArray count]);
		
        if ([task terminationStatus]){ //The task failed
            NSFileHandle *output=[[track objectForKey:kEncoderOutput]fileHandleForReading];
            NSString *string=[NSString stringWithFormat:@"LAME failed (%d)\rArguments:%@\rData:%@\r",[task terminationStatus],[[task arguments]componentsJoinedByString:@", "],[[[NSString alloc] initWithData:[output availableData] encoding:NSUTF8StringEncoding]autorelease]];
            if (NSDebugEnabled) NSLog(string);
            [self finishEncodingWithError:string];
        }else{

			// figure out which progress view to update in the UI, primary or secondary
            ILProgressView * thisProgressBar=primary?trackProgressBar:trackProgress2Bar;
            id thisNameField=primary?trackNameField:trackName2Field;
            id thisProgressField=primary?trackProgressField:trackProgress2Field;

			// update the UI
			[thisProgressBar setIndeterminate:YES];
			[thisProgressBar display];
            [thisNameField setStringValue:[NSString stringWithFormat:@"Finishing: \"%@\"",[track objectForKey:kTrackName]]];
            [thisNameField display];
            [thisProgressField setStringValue:NSLocalizedString(@"Adding Track to Library", @"Adding Track to Library")];
            [thisProgressField display];

			// write this track's iTunes metadata to ID3v2.4 tags via libid3tag
            [self writeTag:track];
            // send AppleScript to iTunes to add this track to our playlist
            [self addTrack:track];
            
            
			//[[[track objectForKey:kEncoderTask]standardError]autorelease];
            [track removeObjectForKey:kEncoderTask];

			// if user had "--delete-source" spec'd in their encoding options, honor that request here
            if ([[track objectForKey:kDeleteSource]boolValue] && ![[[[track objectForKey:kTrackTags] objectForKey:@"pKnd"]stringValue] isEqualToString:@"Audio CD Track"]){
                [thisProgressField setStringValue:NSLocalizedString(@"Removing Source File", @"Removing Source File")];
                [thisProgressField display];
                [self removeFileAndTrack:[track objectForKey:kLameInFile]];
            }

			// clean up the cache file, if any
			NSString *tempFile=[track objectForKey:kLameTempFile];
            if (tempFile)
                [[NSFileManager defaultManager] removeFileAtPath:tempFile handler:nil];

			// update the UI again
            [thisProgressBar setIndeterminate:NO];
            [thisProgressBar setDoubleValue:0];
            [thisProgressField setStringValue:NSLocalizedString(@"Track Complete", @"Track Complete")];
            [thisProgressField display];
			
			// move this track from encoding queue to complete queue
            [completeArray addObject:track];
            [encodingArray removeObject:track];
			
 		   // post a notification to start a new task.
            [[NSNotificationCenter defaultCenter]postNotificationName:kTrackEncodedNotification object:nil];
            
        }
    }
}

- (NSMutableDictionary *)trackForTask:(NSTask *)task{
    int i;
    for (i=0;i<[encodingArray count];i++)
        if ([[encodingArray objectAtIndex:i] objectForKey:kEncoderTask] == task) return [encodingArray objectAtIndex:i];
    return nil;
}

-(bool)removeFileAndTrack:(NSString *)path{
    AEDesc trackDescriptor;
    trackForFile(path,&trackDescriptor);
	
    AppleEvent event, reply;
    OSErr err;
    OSType iTunesAdr = 'hook';
    AEBuildError error;
	
    SInt32 transactionID=(int)path;
	
	
    // core\delo{ ----:obj { form:'ID  ', want:'cFlT', seld:162, from:obj { form:'ID  ', want:'cLiP', seld:39, from:obj { form:'ID  ', want:'cSrc', seld:34, from:'null'() } } }, &csig:65536 }
	
    //NSLog(@"tagging key: '%@' (%@)",key,[propertyDescriptor stringValue]);
    err = AEBuildAppleEvent ('core', 'delo', typeApplSignature, &iTunesAdr, sizeof(iTunesAdr),
                             kAutoGenerateReturnID, transactionID, &event, &error,"'----':@",&trackDescriptor);
	
    //Handle xx;
    //AEPrintDescToHandle(&event, &xx);
    //NSLog(@"Event %s", *xx);
    //DisposeHandle(xx);
	
    if (err) NSLog(@"%d: error at %d",error.fError,error.fErrorPos);// print the error and where it occurs
		
        err = AESend(&event, &reply, kAEWaitReply, kAENormalPriority,kAEDefaultTimeout, NULL, NULL);
        err= AEGetParamDesc (&reply, (AEKeyword) 'errn', 'shor', nil);
        if (err == noErr) NSLog(@"Unable to remove from playlist: %@",path);
		
        AEDisposeDesc(&event);
        AEDisposeDesc(&reply);
		
		
		
        if (![[NSFileManager defaultManager] removeFileAtPath:path handler:nil]){
            NSLog(@"Unable to delete");
            return NO;
        }
        return YES;
		
}


-(bool)writeTag:(NSMutableDictionary *)trackInfo{
  NSDictionary *tags=[trackInfo objectForKey:kTrackTags];

  struct id3_file *id3file;
  struct id3_tag *id3tag;
  id key;
  char *tmp;

  id3tag = id3_tag_new();

  NSEnumerator *enumerator = [keyArray objectEnumerator];
  while ((key = [enumerator nextObject])) {

    if ([key isEqualToString:@"pAlb"]) { // ID3_FRAME_ALBUM (TALB)
      set_text_frame(id3tag, ID3_FRAME_ALBUM, (const id3_utf8_t *)[[[tags objectForKey:key]stringValue]UTF8String]);

    } else if ([key isEqualToString:@"pArt"]) { // ID3_FRAME_ARTIST (TPE1)
      set_text_frame(id3tag, ID3_FRAME_ARTIST, (const id3_utf8_t *)[[[tags objectForKey:key]stringValue]UTF8String]);

    } else if ([key isEqualToString:@"pnam"]) { // ID3_FRAME_TITLE (TIT2)
      set_text_frame(id3tag, ID3_FRAME_TITLE, (const id3_utf8_t *)[[[tags objectForKey:key]stringValue]UTF8String]);

    } else if ([key isEqualToString:@"pCmt"]) { // ID3_FRAME_COMMENT (COMM)
      set_comment(id3tag, (const id3_utf8_t *)[[[tags objectForKey:key]stringValue]UTF8String]);

    } else if ([key isEqualToString:@"pCmp"]) { // COMPOSER (TCOM)
      set_text_frame(id3tag, "TCOM", (const id3_utf8_t *)[[[tags objectForKey:key]stringValue]UTF8String]);

    } else if ([key isEqualToString:@"pGen"]) { // ID3_FRAME_GENRE (TCON)
      set_text_frame(id3tag, "TCON", (const id3_utf8_t *)[[[tags objectForKey:key]stringValue]UTF8String]);

    } else if ([key isEqualToString:@"pGrp"]) { // GROUPING (TIT1)
      set_text_frame(id3tag, "TIT1", (const id3_utf8_t *)[[[tags objectForKey:key]stringValue]UTF8String]);

    } else if ([key isEqualToString:@"pYr "]) { // ID3_FRAME_YEAR
      asprintf(&tmp, "%d", [[tags objectForKey:key]int32Value]);
      set_text_frame(id3tag, ID3_FRAME_YEAR, (const id3_utf8_t *)tmp);
      free(tmp);

    } else if ([key isEqualToString:@"pAnt"]) { // COMPILATION (TCMP)
      if ([[tags objectForKey:key]int32Value]) {
        set_text_frame(id3tag, "TCMP", (const id3_utf8_t *)"1");
      }

	} else if ([key isEqualToString:@"pAlA"]) {	// Album Artist (TPE2)
		set_text_frame(id3tag, "TPE2", (const id3_utf8_t *)[[[tags objectForKey:key]stringValue]UTF8String]);

	} else if ([key isEqualToString:@"pSAr"]) {	// Sort Artist (TSOP)
		set_text_frame(id3tag, "TSOP", (const id3_utf8_t *)[[[tags objectForKey:key]stringValue]UTF8String]);

	} else if ([key isEqualToString:@"pSAA"]) {
		set_text_frame(id3tag, "TSO2", (const id3_utf8_t *)[[[tags objectForKey:key]stringValue]UTF8String]);

	} else if ([key isEqualToString:@"pSNm"]) {	// Sort Name (TSOT)
		set_text_frame(id3tag, "TSOT", (const id3_utf8_t *)[[[tags objectForKey:key]stringValue]UTF8String]);

	} else if ([key isEqualToString:@"pSAl"]) {	// Sort Album (TSOA)
		set_text_frame(id3tag, "TSOA", (const id3_utf8_t *)[[[tags objectForKey:key]stringValue]UTF8String]);

	} else if ([key isEqualToString:@"pSCm"]) {
		set_text_frame(id3tag, "TSOC", (const id3_utf8_t *)[[[tags objectForKey:key]stringValue]UTF8String]);

	} else {
		//NSLog(@"Unhandled tag key: %@", key);
    }
        // TODO: ID3 Beats Per Minute (TBPM)
  }

  // Track Number and Disc Number are a little funky because one frame includes
  // TWO items from the iTunes tag data.  So do them here, rather than in the enumerator.
  int trackNumber=[[tags objectForKey:@"pTrN"]int32Value];
  int trackCount=[[tags objectForKey:@"pTrC"]int32Value];
  int discNumber=[[tags objectForKey:@"pDsN"]int32Value];
  int discCount=[[tags objectForKey:@"pDsC"]int32Value];

  if (trackNumber) {
    if (trackCount) {
      asprintf(&tmp, "%d/%d", trackNumber, trackCount);
    } else {
      asprintf(&tmp, "%d", trackNumber);
    }
    set_text_frame(id3tag, ID3_FRAME_TRACK, (const id3_utf8_t *)tmp);
    free(tmp);
  }

  if (discNumber) {
    if (discCount) {
      asprintf(&tmp, "%d/%d", discNumber, discCount);
    } else {
      asprintf(&tmp, "%d", discNumber);
    }
    set_text_frame(id3tag, "TPOS", (const id3_utf8_t *)tmp);
    free(tmp);
  }

  // Render the tag
  id3tag->options = 0; // ID3_TAG_OPTION_CRC and ID3_TAG_OPTION_COMPRESSION, which are the default, cause interoperability problems.
  id3tag->flags |= ID3_TAG_FLAG_FOOTERPRESENT;
  id3_length_t len = id3_tag_render(id3tag, NULL);
  char *buf = (char*)malloc(len);
  len = id3_tag_render(id3tag, (id3_byte_t *)buf);

  // Open the file (it should have been already created by lame.)
  const char *filename=[[trackInfo objectForKey:kLameOutFile]UTF8String];
  int fd = open(filename, O_RDWR, 0644);
  if (fd == -1) {
    NSLog(@"Error opening output file");
    id3_tag_delete(id3tag);
    return NO;
  }

  // Write the ID3 tag to the beginning of the file.  But first we need to move the whole file n bytes over.
  prepend_bytes_to_file(fd, len);
  lseek(fd, 0, SEEK_SET);
  write(fd, buf, len);
  free(buf);

	// get an ID3v1.1 tag and append it to the file
	NSData *v1data = [self id3v1ForTrack:trackInfo];
	lseek(fd, 0, SEEK_END);
	if (128 == [v1data length]) write(fd, [v1data bytes], 128);

  close(fd);

  id3_tag_delete(id3tag);
  return YES;
}

-(bool)addTrack:(NSMutableDictionary *)trackInfo{
    //NSLog(@"Tagging");
	
    NSWorkspace *workspace=[NSWorkspace sharedWorkspace];
	
    if (![workspace dictForApplicationName:iTunesPath]){
        [workspace launchApplication:iTunesPath]; 
        int i;
        for (i=0;![workspace dictForApplicationName:iTunesPath] && i<100;i++){
            NSLog(@"Waiting for iTunes");
            [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
            
        }
    }
    
    NSDictionary *errorDict=nil;
    NSAppleEventDescriptor *trackDescriptor=[playlistGetter executeSubroutine:@"add_trackfile" arguments:
        [NSArray arrayWithObjects:
            [trackInfo objectForKey:kLameOutFile],[[NSUserDefaults standardUserDefaults] objectForKey:kPlaylistName],nil]
                                                                        error:&errorDict];
    
    if (errorDict)NSLog(@"%@",errorDict);
    //NSLog(@"descr%@",trackNSDesc);
    
    return YES;
}

-(NSTask *)paranoiaCacheTaskWithTool:(NSString *)tool source:(NSString *)source destination:(NSString*)destination valid:(BOOL)valid{
    if (!tool)tool=@"/usr/local/bin/cdparanoia";
    NSTask *lameTask=[[[NSTask alloc]init]autorelease];
    if (valid){
        [lameTask setLaunchPath:tool];
        [lameTask setArguments:[NSArray arrayWithObjects:source,destination,nil]];
        //NSLog(@"copyargs:%@",[lameTask arguments]);
    }
    return lameTask;
}
-(NSTask *)cacheTaskWithTool:(NSString *)tool source:(NSString *)source destination:(NSString*)destination valid:(BOOL)valid{
    if (!tool)tool=@"/bin/cp";
    NSTask *lameTask=[[[NSTask alloc]init]autorelease];
    if (valid){
        [lameTask setLaunchPath:tool];
        [lameTask setArguments:[NSArray arrayWithObjects:source,destination,nil]];
        //NSLog(@"copyargs:%@",[lameTask arguments]);
    }else{
        NSString *fullOptions=[NSString stringWithFormat:@"%@ %@ %@",tool,source,destination];
        [lameTask setCurrentDirectoryPath: [self currentCD]];
        [lameTask setLaunchPath:@"/bin/tcsh"];
        [lameTask setArguments:[NSArray arrayWithObjects:@"-c",fullOptions]];
    }
    return lameTask;
}


-(NSTask *)lameTaskWithOptions:(NSString *)options source:(NSString *)source destination:(NSString*)destination valid:(BOOL)valid{
    NSTask *lameTask=[[[NSTask alloc]init]autorelease];
    if (valid){
        NSMutableArray *arguments=[NSMutableArray arrayWithCapacity:1];
        [arguments setArray:[options componentsSeparatedByString:@" "]];
		// [arguments addObject:@"--disptime"];
		//                 [arguments addObject:@"0.5"];
        [arguments addObject:source];
        [arguments addObject:destination];
        [lameTask setLaunchPath:[self lamePath]];
        [lameTask setArguments:arguments];
    }else{
        NSString *escapedDestination=[destination stringByReplacing:@"'" with:@"'\"'\"'"];
        NSString *fullOptions=[NSString stringWithFormat:@"%@ %@ %@ \'%@\'",[self lamePath], options, source, escapedDestination];
        [lameTask setCurrentDirectoryPath: [self currentCD]];
        [lameTask setLaunchPath:@"/bin/tcsh"];

        NSMutableArray *arguments=[NSMutableArray arrayWithCapacity:0];
        [arguments addObject:@"-c"];
        [arguments addObject:fullOptions];
        [lameTask setArguments:arguments];
    }
    return lameTask;
}


-(NSArray *)getCDPaths{
    struct statfs* mnts;
    int i, mnt_count;
    NSMutableArray *paths=[NSMutableArray arrayWithCapacity:1];
    mnt_count = getmntinfo(&mnts, MNT_WAIT);
    for (i = 0; i < mnt_count; i++) {
        NSString *path=[[NSFileManager defaultManager]stringWithFileSystemRepresentation:mnts[i].f_mntonname length:strlen(mnts[i].f_mntonname)];
        if (strcmp(mnts[i].f_fstypename, "cddafs")==0){
            [paths addObject: path];
        }
        if (NSDebugEnabled) NSLog(@"Volume: %@ (%s)",path,mnts[i].f_fstypename);
    }
	
    if (![paths count]){
        if (NSDebugEnabled) NSLog(@"No CD was found");
        NSString *volume;
        NSEnumerator *enumerator = [[[NSFileManager defaultManager]directoryContentsAtPath:@"/Volumes/"]objectEnumerator];
        //NSString *fakeFile;
        while (volume = [enumerator nextObject])
            if (![volume isEqualToString:@".DS_Store"])
                [paths addObject:[@"/Volumes/" stringByAppendingPathComponent:volume]];
		
    }
    return paths;
}

-(NSArray *)getCDTrackPaths:(NSString *)cdPath{
    NSFileManager *manager=[NSFileManager defaultManager];
    NSMutableArray *fullPaths=[NSMutableArray arrayWithCapacity:1];
    NSString *file;
    NSEnumerator *enumerator = [[[NSFileManager defaultManager] directoryContentsAtPath:cdPath]objectEnumerator];
    //NSString *fakeFile;
    while (file = [enumerator nextObject]) {
        // NSLog(@"%@",file);
        if ([manager fileExistsAtPath:[cdPath stringByAppendingPathComponent:file]]){
            //NSLog(@"%@",file);
        }else{
            //NSLog(@"%@ does not exist!",file);
            //fakeFile=[NSString stringWithUTF8String:"1 Test \u221a\260.aiff"];
            //if ([manager fileExistsAtPath:[cdPath stringByAppendingPathComponent:file]])
            //NSLog(@"%@ does exist",fakeFile);
			
        }
		
		
        if ([[file pathExtension] isEqualToString:@"aiff"])
            [fullPaths addObject:[cdPath stringByAppendingPathComponent:file]];
    }
    if (![fullPaths count]){
        NSLog(@"No tracks found. These volumes are available:%@ tried theseFiles: %@",[[NSFileManager defaultManager]directoryContentsAtPath:@"/Volumes/"],[[NSFileManager defaultManager] directoryContentsAtPath:cdPath]);
		
    }
    return fullPaths;
}



- (void)setProgressFieldValue:(NSString *)string{
    [progressField setStringValue:string];
    [progressFieldBevel setStringValue:string];
	
    [progressFieldBevel display];
    [progressField display];
}

- (NSString *)lamePath{
    NSFileManager *fileManager=[NSFileManager defaultManager];
    NSArray *pathArray=[NSArray arrayWithObjects:@"/usr/local/bin/lame",@"/sw/bin/lame",nil];
    int i;
    for (i=0;i<[pathArray count];i++)
        if ([fileManager isExecutableFileAtPath:[pathArray objectAtIndex:i]]) return [pathArray objectAtIndex:i];
    return [[NSBundle mainBundle]pathForResource:@"lame" ofType:@""];
	
}

- (NSString *)lameVersion{
    NSTask *lameTask=[[[NSTask alloc] init]autorelease];
    NSPipe *helpPipe=[NSPipe pipe];
    [lameTask setStandardError:helpPipe];
    [lameTask setStandardOutput:[NSPipe pipe]];
    [lameTask setLaunchPath:[self lamePath]];
    [lameTask launch];
    [lameTask waitUntilExit];
	
    NSFileHandle *output=[helpPipe fileHandleForReading];
    NSString *string=[[[NSString alloc] initWithData:[output availableData] encoding:NSUTF8StringEncoding]autorelease];
	
    NSString *versionString=nil;
    NSScanner *versionScanner=[NSScanner scannerWithString:string];
    [versionScanner scanString:@"LAME 32bits version " intoString:nil];
    [versionScanner scanUpToString:@" " intoString:&versionString];
	
    return versionString;
}

- (IBAction)showAbout:(id)sender{
    [NSApp beginSheet: aboutPanel
       modalForWindow: encoderWindow
        modalDelegate: nil
       didEndSelector: nil
          contextInfo: nil];
}

- (IBAction)showPrefs:(id)sender{
    
    [self populatePrefs:self];
	[NSApp beginSheet: prefsPanel
	   modalForWindow: encoderWindow
		modalDelegate: nil
	   didEndSelector: nil
		  contextInfo: nil];
}
- (IBAction)setPrefsForSender:(id)sender{
	[NSApp beginSheet: prefsPanel
	   modalForWindow: encoderWindow
		modalDelegate: nil
	   didEndSelector: nil
		  contextInfo: nil];
}


- (IBAction)endContainingSheet:(id)sender{
    [[sender window] makeFirstResponder:[sender window]];
    [NSApp endSheet: [sender window]];
    [[sender window] orderOut: self];
}


- (IBAction)optionsHelp:(id)sender{
	
	
    [helpOptionsField setStringValue:[optionsField stringValue]];
	
    if (![[helpView string]length]){
        NSTask *lameTask=[[[NSTask alloc] init]autorelease];
        NSPipe *helpPipe=[NSPipe pipe];
        // [lameTask setStandardError:helpPipe];
        [lameTask setStandardOutput:helpPipe];
        [lameTask setLaunchPath:[self lamePath]];
        [lameTask setArguments:[NSArray arrayWithObject:@"--longhelp"]];
        [lameTask launch];
		
		NSLog([self lamePath]);
		NSString *string=nil;
		int i;
		for (i=0;i<20 && [lameTask isRunning];i++){
			//NSLog(@"sleep");
			usleep(1000);
		}
		
		if ([lameTask isRunning]){
			[lameTask terminate];
		}else{
			NSFileHandle *output=[helpPipe fileHandleForReading];
			[helpOptionsField setStringValue:[optionsField stringValue]];
			string=[[[NSString alloc] initWithData:[output readDataToEndOfFile] encoding:NSUTF8StringEncoding]autorelease];
			NSRange startPoint=[string rangeOfString:@"  Operational options:"];
			if (startPoint.location!=NSNotFound)
				string=[string substringFromIndex:startPoint.location];
		}
        [helpView setFont:[NSFont fontWithName:@"Monaco" size:9]];
        [helpView setString:(string?string:@"Unable To Print Options")];
        [helpView replaceCharactersInRange:NSMakeRange(0,0) withRTF:[NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"EncodingHelp" ofType:@"rtf"]]];
    }
    
    [NSApp beginSheet: helpPanel
       modalForWindow: encoderWindow
        modalDelegate: nil
       didEndSelector: nil
          contextInfo: nil];
}


- (bool)validateOptions:(NSString *)encodingOptions error:(NSString **)errorString{
    NSMutableArray *argumentsArray=[NSMutableArray arrayWithCapacity:2];
    [argumentsArray setArray:[encodingOptions componentsSeparatedByString:@" "]];
	
    [argumentsArray addObject:@"-"];
    [argumentsArray addObject:@"-"];
	
    NSTask *lameTask=[[[NSTask alloc] init]autorelease];
	
    [lameTask setStandardInput:[NSFileHandle fileHandleWithNullDevice]];
    [lameTask setStandardError:[NSPipe pipe]];
    [lameTask setStandardOutput:[NSPipe pipe]];
    [lameTask setLaunchPath:[self lamePath]];
    [lameTask setArguments:argumentsArray];
    [lameTask launch];
    [lameTask waitUntilExit];
	
	
    int status = [lameTask terminationStatus];
	
    if (status && errorString){
        NSFileHandle *output=[[lameTask standardError] fileHandleForReading];
        NSString *string=[[[NSString alloc] initWithData:[output availableData] encoding:NSUTF8StringEncoding]autorelease];
		
        NSLog(@"Task status: %d\r%@",status, string);
        
        //        if (status) *errorString=nil;
        //        else *errorString=string;
    }
	
	//    errorString= status ? string : nil;
	
    return !status;
}

- (IBAction)setEncodingOptions:(id)sender{
    // NSLog(@"options set");
    NSString *options=[[sender stringValue]stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	
    //int selectedIndex=[optionsField indexOfItemWithObjectValue:options];
    //if (selectedIndex!=NSNotFound){
	//if (![self validateOptions:options error:nil])
	// [optionsField insertItemWithObjectValue:options atIndex:0];
	//else
	//    NSLog(@"validation failed in set");
    //}
    //else
	[optionsField removeItemWithObjectValue:options];

    [optionsField insertItemWithObjectValue:options atIndex:0];


    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];

    [defaults setObject:[optionsField objectValues] forKey:encodingOptionsKey];
    [defaults synchronize];
}


- (BOOL)control:(NSControl *)control isValidObject:(id)object{
    //NSLog(@"Optins \"%@\" are valid: %d",object, [self validateOptions:object]);
    return ([self validateOptions:object error:nil] || !canValidate);
}
- (void)controlTextDidChange:(NSNotification *)aNotification{
    //  NSLog(@"valid %d",[self validateOptions:[[aNotification object]stringValue]]);
	
	
    NSButton *validationButton=(NSButton *)[[aNotification object]nextKeyView];
    bool valid=[self validateOptions:[[aNotification object]stringValue] error:nil];
	
    [validationButton setState:!valid];
    //NSLog(@"%d",valid);
}

- (void)comboBoxSelectionDidChange:(NSNotification *)notification{
	
}


-(void)getMusicPreferences{
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    [defaults addSuiteNamed:@"com.apple.iTunes"]; //Add Apple's iTunes item
    NSData *musicFolderAliasData=[defaults dataForKey:@"alis:11345:Music Folder Location"];
    NSData *preferencesData=[defaults dataForKey:@"pref:129:Preferences"];
	
    //NSLog(@"Pref Data: %@",[preferencesData subdataWithRange:NSMakeRange(0, 128)]);
    //NSLog(@"Pref Data: %@",[preferencesData subdataWithRange:NSMakeRange(14, 2)]);
    //NSLog(@"Pref Data: %@",[preferencesData subdataWithRange:NSMakeRange(84, 1)]);
    //NSLog(@"Pref Data: %@",[NSData dataWithBytes:&location length:4]);
	
    short location;
    [preferencesData getBytes:&location range:NSMakeRange(14, 2)];
    char useTrackNumbersChar;
    [preferencesData getBytes:&useTrackNumbersChar range:NSMakeRange(84, 1)];
    useTrackNumbers=useTrackNumbersChar;
	
	
    bool customFolder=(location==11345); //    [preferencesData isEqualTaData: ];
	
    NSString *musicPath=nil;
	
    if (musicFolderAliasData && customFolder){
        musicPath=[[BDAlias aliasWithData:musicFolderAliasData]fullPath];
        if (!musicPath) NSLog(@"Unable to find iTunes music library location");
        else
            NSLog(@"Using iTunes music library location: %@",[musicPath stringByAbbreviatingWithTildeInPath]);
    }
    if (!musicPath){
        NSLog(@"Using iTunes default music library location");
        musicPath=[[NSFileManager defaultManager] fullyResolvedPathForPath:@"~/Music/iTunes/iTunes Music/"];
    }
	
    if (DEBUG) NSLog(@"Files should%@ have track numbers",(useTrackNumbers?@"":@" not"));
	
	
    [self setMusicDirectory:musicPath];
}


-(void)updateTracksArray{
    NSDictionary		*errorDict=nil;
    NSAppleEventDescriptor 	*returnDescriptor;
    NSWorkspace *workspace=[NSWorkspace sharedWorkspace];
    //NSLog(@"Updating");
    [progressIndicator setIndeterminate:YES];
    [progressIndicator startAnimation:self];
	
	
    [self setProgressFieldValue:NSLocalizedString(@"Gathering information", @"Gathering information")];
    if (![workspace dictForApplicationName:iTunesPath])
        [workspace launchApplication:iTunesPath];
    
    
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    
    NS_DURING
        
        returnDescriptor=[playlistGetter executeSubroutine:@"get_track_list" arguments:[NSAppleEventDescriptor descriptorWithBoolean:[defaults boolForKey:kUseSelection]] error:&errorDict];
		// returnDescriptor=[playlistGetter executeAndReturnError:&errorDict];
        if (errorDict) NSLog(@"got error!%@",errorDict);
		NS_HANDLER
			NSBeep();
			[self setTracksArray:nil];
			NSBeginCriticalAlertSheet(NSLocalizedString(@"Import Error", @"Import Error"),nil,nil,nil,encoderWindow,nil,nil,nil,nil,
									  NSLocalizedString(@"An error occured while trying to  get track listing:\r%@",@"Track Error Message"),[localException name]);
			NSLog(@"An error occured while getting tracks: %@ %@",[localException name],[localException reason]);
			return;
		NS_ENDHANDLER
		
		//[scriptObject release];
		if ([returnDescriptor descriptorType]) { //	The execution succeeded
			if (kAENullEvent!=[returnDescriptor descriptorType]) { //	The script returned an AppleScript result
				if (cAEList==[returnDescriptor descriptorType]) { //	Result is a list of other descriptors
					[self setCurrentPlaylist:[[returnDescriptor descriptorAtIndex:2]stringValue]];
					NSAppleEventDescriptor *tracksDescriptor=[returnDescriptor descriptorAtIndex:1];
					if (cAEList==[tracksDescriptor descriptorType]) { //	Result is a list of other descriptors
																	  //[self setProgressFieldValue:[NSString stringWithFormat:@"Processing %d songs.",[tracksDescriptor numberOfItems]]];
						NSMutableArray *newTracksArray=[NSMutableArray arrayWithCapacity:[tracksDescriptor numberOfItems]];
						int i;
						NSAppleEventDescriptor 	*itemDescriptor;
						for (i=0;i<[tracksDescriptor numberOfItems];i++){
							NSMutableDictionary *propertiesDict=[NSMutableDictionary dictionaryWithCapacity:[keyArray count]];
							itemDescriptor=[tracksDescriptor descriptorAtIndex:i+1];
							if (cAEList==[itemDescriptor descriptorType]) {
								int j;
								for (j=0;j<[itemDescriptor numberOfItems];j++){
									// if the user modifies our AppleScript resource, j can overflow. So we check.
									if (j > [keyArray count]-1) break;
									NSString *key=[keyArray objectAtIndex:j];
									NSAppleEventDescriptor *descriptor=[itemDescriptor descriptorAtIndex:j+1];
									DescType type=[descriptor descriptorType];
									// When tagging AIFF files on the hard drive, iTunes makes the Sorting tab available for editing in the Info window.
									// However, when ripping a CD, the Sorting tab is disabled (no idea why).
									// When iTunes-LAME requests these sorting fields, iTunes will supply a 'missing data' descriptor for them when ripping a CD.
									// You'd think it would just return "" or omit these from the reply, but it doesn't.
									// So when we check the [descriptor stringValue] for length, we also have to make sure it isn't the string @"msng".
									if ((type=='true') ||
										(type==cLongInteger && [descriptor int32Value])||
										([[descriptor stringValue]length] && ! [[descriptor stringValue] isEqualToString:@"msng"])){
										//  NSLog(@"KEY: %@, %@",key,osTypeToFourCharCode(type));
										if (descriptor) [propertiesDict setObject:descriptor forKey:key];
										else  NSLog(@"Invalid descriptor for key: %@", key);
									}
								}
								NSMutableDictionary *trackDict=[NSMutableDictionary dictionaryWithObject:propertiesDict forKey:kTrackTags];
								NSString *name=[[propertiesDict objectForKey:@"pnam"]stringValue];
								[trackDict setObject:(name?name:@"Unknown") forKey:kTrackName];
								[newTracksArray addObject:trackDict];
							}
							if (![newTracksArray count]){
								if ([currentPlaylist isEqualToString:@"Library"] || [currentPlaylist isEqualToString:@"Radio"])
									[self setProgressFieldValue:NSLocalizedString(@"Select a CD or File Playlist", @"Select a CD or File Playlist")];
								else
									[self setProgressFieldValue:NSLocalizedString(@"Use checkmarks to choose songs",@"Use checkmarks to choose songs")];
							}
							[self setTracksArray:newTracksArray];
						}
					}
				} else {
					NSLog(@"AppleScript has no result.");
					[self setTracksArray:nil];
				}
			}
        } else {
            NSLog(@"errorDict %@",errorDict);
            NSString *error=[errorDict objectForKey: @"NSAppleScriptErrorMessage"];
            if ([error isEqualToString:@"Invalid Playlist"])
                [self setProgressFieldValue:NSLocalizedString(@"Select a CD or File Playlist", @"Select a CD or File Playlist")];
            else{
                [self setProgressFieldValue:NSLocalizedString(@"No Tracks Found",@"No Tracks Found")];
                NSLog(@"Error: %@", error);
            }
            [self setTracksArray:nil];
        }
		
		//NSLog(@"Updating Complete");
		//[encodeButton setEnabled: !encoding];
		[progressIndicator setIndeterminate:NO];
		[progressIndicator stopAnimation:self];
		
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag{
	//   [[NSWorkspace sharedWorkspace] activateFrontWindowOfApplication:iTunesPath];
	
	[encoderWindow makeKeyAndOrderFront:self];
    return NO;
}


- (void)applicationWillTerminate:(NSNotification *)aNotification{
    if (encoding)
		[self cancelEncoding:self];
    [encoderWindow saveFrameUsingName:@"encoderWindow"];
}


- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender{
    if (encoding && !forceTerminate){
        NSBeginAlertSheet(NSLocalizedString(@"Cancel Import?",@"Cancel Import?"), NSLocalizedString(@"Continue Import",@"Continue Import"), NSLocalizedString(@"Quit",@"Quit"),
						  nil, encoderWindow, self, @selector(sheetDidEnd:returnCode:contextInfo:), nil, nil,
                          NSLocalizedString(@"Importing in progress.\nAre you sure you want to interrupt it?",@"Interrupt Import Message"));
        return NO;
    }
    else{
        return YES;
    }
}


//Encoder Window Delegate

- (BOOL)windowShouldClose:(id)sender{
    [encoderWindow saveFrameUsingName:@"encoderWindow"];
    [NSApp terminate:self];
    return NO;
} 


- (void)windowDidBecomeKey:(NSNotification *)aNotification{
    
}

- (void)windowDidResignKey:(NSNotification *)aNotification{
	// [encodeButton setEnabled:NO];
}

//Window Sheet

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo{
	
    if (sheet!=aboutPanel){
        if (returnCode==NSAlertAlternateReturn){
            forceTerminate=YES;
            [self cancelEncoding:self];
            [NSApp terminate:self];
        }
    }
}





- (NSString *)currentCD{
    if (!currentCD){
		
        NSArray *cdPaths=[self getCDPaths];
        NSString *cdPath=nil;
		
        int i;
		
        if ([cdPaths count]>1){
            NSMutableArray *cdTitles=[NSMutableArray arrayWithCapacity:[cdPaths count]];
            for (i=0;i<[cdPaths count];i++)
                [cdTitles addObject:[[cdPaths objectAtIndex:i]lastPathComponent]];
            
            int matchedPlaylist=[cdTitles indexOfObject: [currentPlaylist stringByReplacing:@"/" with:@":"]];
            
            if (matchedPlaylist!=NSNotFound){
                cdPath=[cdPaths objectAtIndex:matchedPlaylist];
                if (NSDebugEnabled) NSLog(@"Multiple CDs Found. Matched playlist name:%@",cdPath);
            }else{
                if (NSDebugEnabled) NSLog(@"Multiple CDs Found. None match playlist.",cdPath);
                [cdPopUp removeAllItems];
                [cdPopUp addItemsWithTitles:cdTitles];
				
                [NSApp beginSheet: chooseCDPanel
                   modalForWindow: encoderWindow
                    modalDelegate: nil
                   didEndSelector: nil
                      contextInfo: nil];
				
                [NSApp runModalForWindow: chooseCDPanel];
                // Sheet is up here.
                [NSApp endSheet: chooseCDPanel];
                [chooseCDPanel orderOut: self];
                cdPath=[cdPaths objectAtIndex:[cdPopUp indexOfSelectedItem]];
                if (NSDebugEnabled) NSLog(@"CD Chosen Manually:%@",cdPath);
            }
        }
        if (!cdPath) cdPath=[cdPaths lastObject];
        [self setCurrentCD:cdPath];
        NSLog(@"Using CD: %@",cdPath);
    }
    return [[currentCD retain] autorelease];
}


- (void)flagsChanged:(NSEvent *)theEvent{
    //NSLog(@"flagchanged");
	
    [self updateEncodeButtonAppearance];
}



- (void)appTerminated:(NSNotification*)notif{
    NSString *terminatedApp=[[notif userInfo] objectForKey:@"NSApplicationName"];
    if ([terminatedApp isEqualToString:@"iTunes"]){
        NSLog(@"iTunes Terminated");
		
        [NSApp terminate:self];
    }
}

//

- (NSArray *)tracksArray {
    if (!tracksArray) [self updateTracksArray];
    return [[tracksArray retain] autorelease]; }

- (void)setTracksArray:(NSArray *)newTracksArray {
    [tracksArray release];
    tracksArray = [newTracksArray retain];
}


- (NSString *)musicDirectory { return [[musicDirectory retain] autorelease]; }

- (void)setMusicDirectory:(NSString *)newMusicDirectory {
    [musicDirectory release];
    musicDirectory = [newMusicDirectory retain];
}

- (NSString *)currentPlaylist { return [[currentPlaylist retain] autorelease]; }

- (void)setCurrentPlaylist:(NSString *)newCurrentPlaylist {
    [currentPlaylist release];
    currentPlaylist = [newCurrentPlaylist retain];
}

- (void)setCurrentCD:(NSString *)newCurrentCD {
    [currentCD release];
    currentCD = [newCurrentCD retain];
}


- (IBAction)setValueForSender:(id)sender{
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    
    
	if (sender==useSelectionSwitch)
		[defaults setBool:[sender state] forKey:kUseSelection];
    if (sender==multiSwitch)
        [defaults setBool:[sender state] forKey:kMulti];
    if (sender==cacheSwitch)
        [defaults setBool:[sender state] forKey:kShouldCache];
    else if (sender==vCommentSwitch)
        [defaults setBool:[sender state] forKey:kVComment];
    else if (sender==alternateNameSwitch)
        [defaults setBool:[sender state] forKey:kUseAlternateName];
    else if (sender==alternateNameField)
        [defaults setObject:[sender stringValue] forKey:kAlternateName];
    else if (sender==destinationPopUp){
        int selection=[[destinationPopUp selectedItem]tag];
        if (selection==1){
            [defaults removeObjectForKey:kDestination];
        }else if (selection==3){
            
            NSOpenPanel *openPanel=[NSOpenPanel openPanel];
            [openPanel setCanChooseDirectories:YES];
            [openPanel setCanChooseFiles:NO];
            if ([openPanel runModalForTypes:nil])
                [defaults setObject:[openPanel filename] forKey:kDestination];
        }
    }
    else if (sender==cacheLocationPopUp){
        int selection=[[cacheLocationPopUp selectedItem]tag];
        if (selection==1){
            [defaults removeObjectForKey:kCacheLocation];
        }else if (selection==3){
            
            NSOpenPanel *openPanel=[NSOpenPanel openPanel];
            [openPanel setCanChooseDirectories:YES];
            [openPanel setCanChooseFiles:NO];
            if ([openPanel runModalForTypes:nil])
                [defaults setObject:[openPanel filename] forKey:kCacheLocation];
        }
    }
    [defaults synchronize];
    [self populatePrefs:self];
}
- (IBAction)populatePrefs:(id)sender{
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    
    
    [multiSwitch setState:[defaults boolForKey:kMulti]];
    [multiSwitch setEnabled:(MPProcessors()>1 ||[defaults boolForKey:kMulti]||NSDebugEnabled)];
    SInt32 version;
    Gestalt (gestaltSystemVersion, &version);
    
    bool forceCache=[defaults boolForKey:kMulti] && (version >= 0x1030);
    
    
	
    [useSelectionSwitch setState:[defaults boolForKey:kUseSelection]];
	
    [cacheSwitch setState:[defaults boolForKey:kShouldCache]||forceCache];
    [cacheSwitch setEnabled:!forceCache];
    
    [vCommentSwitch setState:[defaults boolForKey:kVComment]];
    [alternateNameSwitch setState:[defaults boolForKey:kUseAlternateName]];
    [alternateNameField setEnabled:[defaults boolForKey:kUseAlternateName]];
    
    NSString *altName=[defaults stringForKey:kAlternateName];
    [alternateNameField setStringValue:(altName?altName:gDefaultNameNoTrack)];
    
    NSString *destination=[defaults stringForKey:kDestination];
    id <NSMenuItem> customItem=[destinationPopUp itemAtIndex:[destinationPopUp indexOfItemWithTag:2]];
    [destinationPopUp selectItemAtIndex:-1];
    if ([destination length]){
        [customItem setTitle:[destination lastPathComponent]];
        [customItem setEnabled:YES];
        [destinationPopUp selectItem:customItem];
    }else{
        [customItem setTitle:@"Default"];
        [customItem setEnabled:NO];
        [destinationPopUp selectItemAtIndex:[destinationPopUp indexOfItemWithTag:1]];
    }
    
    
    NSString *cacheLoc=[defaults stringForKey:kCacheLocation];
    customItem=[cacheLocationPopUp itemAtIndex:[cacheLocationPopUp indexOfItemWithTag:2]];
    [cacheLocationPopUp selectItemAtIndex:-1];
    if ([cacheLoc length]){
        [customItem setTitle:[cacheLoc lastPathComponent]];
        [customItem setEnabled:YES];
        [cacheLocationPopUp selectItem:customItem];
    }else{
        [customItem setTitle:@"Default"];
        [customItem setEnabled:NO];
        [cacheLocationPopUp selectItemAtIndex:[cacheLocationPopUp indexOfItemWithTag:1]];
    }
    
}



@end


@implementation BTEncoderController (Tags)

// assembles an ID3v1.1 tag from a track's tagData and returns it in an NSData
-(NSData *)id3v1ForTrack:(NSDictionary *)track {
	NSDictionary	*tags = [track objectForKey:kTrackTags];
	NSMutableData	*tagData = [NSMutableData dataWithCapacity:128];
	NSArray *id3v1Genres = [NSArray arrayWithObjects:@"blues", @"classic rock", @"country", @"dance", @"disco", @"funk", @"grunge", @"hip-hop", @"jazz", @"metal", @"new age", @"oldies", @"other", @"pop", @"r&b", @"rap", @"reggae", @"rock", @"techno", @"industrial", @"alternative", @"ska", @"death metal", @"pranks", @"soundtrack", @"euro-techno", @"ambient", @"trip-hop", @"vocal", @"jazz+funk", @"fusion", @"trance", @"classical", @"instrumental", @"acid", @"house", @"game", @"sound clip", @"gospel", @"noise", @"alternrock", @"bass", @"soul", @"punk", @"space", @"meditative", @"instrumental pop", @"instrumental rock", @"ethnic", @"gothic", @"darkwave", @"techno-industrial", @"electronic", @"pop-folk", @"eurodance", @"dream", @"southern rock", @"comedy", @"cult", @"gangsta", @"top 40", @"christian rap", @"pop/funk", @"jungle", @"native american", @"cabaret", @"new wave", @"psychadelic", @"rave", @"showtunes", @"trailer", @"lo-fi", @"tribal", @"acid punk", @"acid jazz", @"polka", @"retro", @"musical", @"rock & roll", @"hard rock", @"folk", @"folk-rock", @"national folk", @"swing", @"fast fusion", @"bebob", @"latin", @"revival", @"celtic", @"bluegrass", @"avantgarde", @"gothic rock", @"progressive rock", @"psychedelic rock", @"symphonic rock", @"slow rock", @"big band", @"chorus", @"easy listening", @"acoustic", @"humour", @"speech", @"chanson", @"opera", @"chamber music", @"sonata", @"symphony", @"booty bass", @"primus", @"porn groove", @"satire", @"slow jam", @"club", @"tango", @"samba", @"folklore", @"ballad", @"power ballad", @"rhythmic soul", @"freestyle", @"duet", @"punk rock", @"drum solo", @"a capella", @"euro-house", @"dance hall", nil];
	unsigned char buf[3];

	// id3v1.x must begin with 'TAG'
	buf[0] = 'T';
	buf[1] = 'A';
	buf[2] = 'G';
	[tagData appendBytes:buf length:3];

	// add the id3v1.x track title
	NSString *tagValue = [(NSAppleEventDescriptor *)[tags objectForKey:@"pnam"] stringValue];
	[tagData appendData:[[tagValue substringToIndex:MIN(30,[tagValue length])] dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES]];
	// zero-pad to 30 chars
	[tagData increaseLengthBy:33 - [tagData length]];

	// add the id3v1.x artist name
	tagValue = [(NSAppleEventDescriptor *)[tags objectForKey:@"pArt"] stringValue];
	[tagData appendData:[[tagValue substringToIndex:MIN(30,[tagValue length])] dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES]];
	// zero-pad to 30 chars
	[tagData increaseLengthBy:63 - [tagData length]];

	// add the id3v1.x album title
	tagValue = [(NSAppleEventDescriptor *)[tags objectForKey:@"pAlb"] stringValue];
	[tagData appendData:[[tagValue substringToIndex:MIN(30,[tagValue length])] dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES]];
	// zero-pad to 30 chars
	[tagData increaseLengthBy:93 - [tagData length]];

	// add the id3v1.x year
	tagValue = [(NSAppleEventDescriptor *)[tags objectForKey:@"pYr "] stringValue];
	if (! [tagValue isEqualToString:@"0"]) {	// iTunes puts a zero here if there's no year
		[tagData appendData:[[tagValue substringToIndex:MIN(4,[tagValue length])] dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES]];
	// zero-pad to 4 chars
		[tagData increaseLengthBy:97 - [tagData length]];
	} else {	// there was no year, just write NULs
		[tagData increaseLengthBy:4];
	}

	// add the comment, limited to 28 chars for ID3v1.1 compatibility
	tagValue = [(NSAppleEventDescriptor *)[tags objectForKey:@"pCmt"] stringValue];
	[tagData appendData:[[tagValue substringToIndex:MIN(28,[tagValue length])] dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES]];
	// zero-pad to 28 chars
	[tagData increaseLengthBy:125 - [tagData length]];

	// terminate the comment for ID3v1.0 readers
	[tagData increaseLengthBy:1];

	// this is the special byte which is ID3v1.1 only: the track number
	buf[0] = 0x000000FF & [(NSAppleEventDescriptor *)[tags objectForKey:@"pTrN"] int32Value];
	[tagData appendBytes:buf length:1];

	// add the ID3v1.x genre, or 0xFF if genre doesn't match any in id3v1Genres above
	tagValue = [[(NSAppleEventDescriptor *)[tags objectForKey:@"pGen"] stringValue] lowercaseString];
	buf[0] = 0x000000FF & [id3v1Genres indexOfObject:tagValue];
	[tagData appendBytes:buf length:1];

	return tagData;
}

@end

