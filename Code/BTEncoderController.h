/* BTEncoderController */

#import <Cocoa/Cocoa.h>

#import "ILProgressView.h"
@interface BTEncoderController : NSWindowController
{
    IBOutlet NSWindow *encoderWindow;
    IBOutlet NSComboBox *optionsField;
    
    IBOutlet NSProgressIndicator *progressIndicator;
    IBOutlet NSTextField *progressField;
    IBOutlet NSTextField *progressFieldBevel;


    IBOutlet NSBox *encodingBox;
    IBOutlet NSTextField *trackNumberField;
    IBOutlet NSTextField *trackNameField;
    IBOutlet NSTextField *trackProgressField;
    IBOutlet ILProgressView *trackProgressBar;
    IBOutlet NSTextField *trackName2Field;
    IBOutlet NSTextField *trackProgress2Field;
    IBOutlet ILProgressView *trackProgress2Bar;
    
    IBOutlet NSButton *encodeButton;
    IBOutlet NSButton *cancelButton;

    
    IBOutlet NSButton *helpButton;
    IBOutlet NSButton *aboutButton;
    IBOutlet NSButton *prefsButton;
    
    IBOutlet NSButton *validButton;
    IBOutlet NSButton *helpValidButton;
    
    
    IBOutlet NSPanel *aboutPanel;
    IBOutlet NSPanel *prefsPanel;
    IBOutlet NSPanel *helpPanel;

    IBOutlet NSTextView *helpView;


    IBOutlet NSTextField *helpOptionsField;
    



    IBOutlet NSPanel *chooseCDPanel;
    IBOutlet NSPopUpButton *cdPopUp;


    IBOutlet NSTextField *lameVersionField;
    IBOutlet NSTextField *versonField;
    
    NSMutableArray *tracksArray;
    NSString *currentPlaylist;
    NSString *currentCD;

    NSMutableArray *outFiles;
    
    NSMutableArray *pendingArray;
    NSMutableArray *cachingArray;
    NSMutableArray *preparedArray;
    NSMutableArray *encodingArray;
    NSMutableArray *completeArray;

    
    NSSize encoderWindowSize;
    float encodingBoxHeight;
    
    NSString *musicDirectory;
    NSAppleScript *playlistGetter;

    bool launching;
    bool activating;
    bool encoding;
    bool forceTerminate;
    bool readyToEncode;
    int currentTrack;
    int totalTracks;
    bool inITunes;
    bool useTrackNumbers;
    bool canValidate;
    bool caching;

    NSTimer *progressTimer;
    
    IBOutlet NSButton *multiSwitch;     
    IBOutlet NSButton *cacheSwitch;     
    IBOutlet NSButton *vCommentSwitch; 
    IBOutlet NSPopUpButton *destinationPopUp; 
    IBOutlet NSPopUpButton *cacheLocationPopUp; 
    IBOutlet NSButton *alternateNameSwitch;
    IBOutlet NSTextField *alternateNameField;
    
    IBOutlet NSButton *useSelectionSwitch;
    
   // IBOutlet NSTextField *playlistNameField;
}
- (void)handleAppleEvent:(NSAppleEventDescriptor *)event withReplyEvent: (NSAppleEventDescriptor *)replyEvent;
- (void) awakeFromNib;
- (void)appChanged:(NSNotification *)aNotification;
- (IBAction)closeChooseCDPanel: (id)sender;
- (IBAction)encode:(id)sender;
- (void) encodeLoop;
- (void) updateTrackNumbers;
- (void) cacheTrack:(NSDictionary *)track;
- (void) encodeTrack:(NSDictionary *)track;
- (IBAction)openWebsiteForToolTip:(id)sender;
- (void)abortAllFiles;
- (IBAction)cancelEncoding: (id)sender;
-(void)finishEncodingWithError:(NSString *)error;
- (void) updateStatus:(NSNotification *)aNotification;
- (bool) scanProgressString:(NSString *)string intoProgress:(float *)progress rate:(float *)rate remainingTime:(NSString **)remainingTime;
- (void) updateEncodeButtonAppearance;
- (void)taskDidTerminate:(NSNotification *)aNotification;
- (NSMutableDictionary *)trackForTask:(NSTask *)task;
-(bool)removeFileAndTrack:(NSString *)path;
-(bool)addAndTagTrack:(NSMutableDictionary *)trackInfo;
-(NSTask *)cacheTaskWithTool:(NSString *)tool source:(NSString *)source destination:(NSString*)destination valid:(BOOL)valid;
-(NSTask *)lameTaskWithOptions:(NSString *)options source:(NSString *)source destination:(NSString*)destination valid:(BOOL)valid;
-(NSArray *)getCDPaths;
-(NSArray *)getCDTrackPaths:(NSString *)cdPath;
- (void)setProgressFieldValue:(NSString *)string;
- (NSString *)lamePath;
- (NSString *)lameVersion;
- (IBAction)showAbout:(id)sender;
- (IBAction)showPrefs:(id)sender;
- (IBAction)setPrefsForSender:(id)sender;
- (IBAction)endContainingSheet:(id)sender;
- (IBAction)optionsHelp:(id)sender;
- (bool)validateOptions:(NSString *)encodingOptions error:(NSString **)errorString;
- (IBAction)setEncodingOptions:(id)sender;
- (BOOL)control:(NSControl *)control isValidObject:(id)object;
- (void)controlTextDidChange:(NSNotification *)aNotification;
- (void)comboBoxSelectionDidChange:(NSNotification *)notification;
-(void)getMusicPreferences;
-(void)updateTracksArray;
- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag;
- (void)applicationWillTerminate:(NSNotification *)aNotification;
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender;
- (BOOL)windowShouldClose:(id)sender;
- (void)windowDidBecomeKey:(NSNotification *)aNotification;
- (void)windowDidResignKey:(NSNotification *)aNotification;
- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (NSString *)currentCD;
- (void)flagsChanged:(NSEvent *)theEvent;
- (void)appTerminated:(NSNotification*)notif;
- (NSArray *)tracksArray ;
- (void)setTracksArray:(NSArray *)newTracksArray ;
- (NSString *)musicDirectory ;
- (void)setMusicDirectory:(NSString *)newMusicDirectory ;
- (NSString *)currentPlaylist ;
- (void)setCurrentPlaylist:(NSString *)newCurrentPlaylist ;
- (void)setCurrentCD:(NSString *)newCurrentCD ;
- (IBAction)setValueForSender:(id)sender;
- (IBAction)populatePrefs:(id)sender;
- (void)updateEncoderWindowSizeEncoding:(BOOL)isEncoding multi:(BOOL)isMulti;
@end
