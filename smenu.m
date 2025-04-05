#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSTimer *timer;
@property (strong, nonatomic) NSAppleScript *spotifyScript;
@property (strong, nonatomic) NSArray<NSAppleScript *> *controlScripts;
@property (strong, nonatomic) NSString *lastTrackInfo;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [self setupMenu];
    [self setupControlScripts];
    [self initializeSpotifyScript];
    
    [self updateSpotifyStatus];
    
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self 
                                                        selector:@selector(spotifyDidChangeTrack:) 
                                                            name:@"com.spotify.client.PlaybackStateChanged" 
                                                          object:nil];
    
    self.timer = [NSTimer timerWithTimeInterval:10.0
                                         target:self
                                       selector:@selector(updateSpotifyStatus)
                                       userInfo:nil
                                        repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(applicationDidLaunch:)
                                                               name:NSWorkspaceDidLaunchApplicationNotification
                                                             object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(applicationDidTerminate:)
                                                               name:NSWorkspaceDidTerminateApplicationNotification
                                                             object:nil];
    if (@available(macOS 10.14, *)) {
        [[NSApplication sharedApplication] addObserver:self
                                            forKeyPath:@"effectiveAppearance"
                                               options:NSKeyValueObservingOptionNew
                                               context:NULL];
    }
}

- (void)spotifyDidChangeTrack:(NSNotification *)notification {
    [self updateSpotifyStatus];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"effectiveAppearance"]) {
        [self updateAppearance];
    }
}

- (void)updateAppearance {
    NSString *currentText = self.statusItem.button.title;
    self.statusItem.button.title = currentText;
}

- (void)setupMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Refresh" action:@selector(updateSpotifyStatus) keyEquivalent:@"r"];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Open Spotify" action:@selector(openSpotify) keyEquivalent:@"o"];
    [menu addItemWithTitle:@"Play/Pause" action:@selector(togglePlayPause) keyEquivalent:@"p"];
    [menu addItemWithTitle:@"Next Track" action:@selector(nextTrack) keyEquivalent:@"n"];
    [menu addItemWithTitle:@"Previous Track" action:@selector(previousTrack) keyEquivalent:@"b"];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    self.statusItem.menu = menu;
}

- (void)setupControlScripts {
    self.controlScripts = @[
        [[NSAppleScript alloc] initWithSource:@"tell application \"Spotify\" to playpause"],
        [[NSAppleScript alloc] initWithSource:@"tell application \"Spotify\" to next track"],
        [[NSAppleScript alloc] initWithSource:@"tell application \"Spotify\" to previous track"],
    ];
}

- (void)initializeSpotifyScript {
    NSString *scriptSource = @"tell application \"System Events\"\n"
                             "    set isRunning to (exists (processes where name is \"Spotify\"))\n"
                             "end tell\n"
                             "\n"
                             "if isRunning then\n"
                             "    tell application \"Spotify\"\n"
                             "        if player state is playing then\n"
                             "            set currentTrack to name of current track\n"
                             "            set currentArtist to artist of current track\n"
                             "            return currentTrack & \" - \" & currentArtist\n"
                             "        else\n"
                             "            return \"⏸\"\n"
                             "        end if\n"
                             "    end tell\n"
                             "else\n"
                             "    return \"⏹\"\n"
                             "end if";
    self.spotifyScript = [[NSAppleScript alloc] initWithSource:scriptSource];
}

- (void)updateSpotifyStatus {
    if (!self.spotifyScript) {
        [self initializeSpotifyScript];
    }
    NSDictionary *errorInfo = nil;
    NSAppleEventDescriptor *descriptor = [self.spotifyScript executeAndReturnError:&errorInfo];
    if (errorInfo) {
        if (![[errorInfo objectForKey:NSAppleScriptErrorMessage] containsString:@"Not running"]) {
            NSLog(@"AppleScript error: %@", errorInfo);
        }
        self.statusItem.button.title = @"Spotify";
        return;
    }
    NSString *output = descriptor.stringValue;
    if (output && ![output isEqualToString:self.lastTrackInfo]) {
        self.lastTrackInfo = output;
        if (output.length > 40) {
            output = [[output substringToIndex:37] stringByAppendingString:@"..."];
        }
        if (![output isEqualToString:@"Paused"] && ![output isEqualToString:@"Spotify not running"]) {
            output = [NSString stringWithFormat:@"%@", output];
        }
        self.statusItem.button.title = output;
    }
}

- (void)openSpotify {
    NSURL *spotifyURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.spotify.client"];
    if (spotifyURL) {
        NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:spotifyURL 
                                              configuration:configuration 
                                          completionHandler:^(NSRunningApplication * _Nullable app, NSError * _Nullable error) {
            if (error) {
                NSLog(@"Error opening Spotify: %@", error);
            } else {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self updateSpotifyStatus];
                });
            }
        }];
    } else {
        NSLog(@"Could not find Spotify application");
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Spotify Not Found";
        alert.informativeText = @"Could not find Spotify application. Please ensure it is installed.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    }
}

- (void)togglePlayPause {
    [self executeControlScript:0];
}

- (void)nextTrack {
    [self executeControlScript:1];
}

- (void)previousTrack {
    [self executeControlScript:2];
}

- (void)executeControlScript:(NSInteger)index {
    if (index < 0 || index >= self.controlScripts.count) {
        return;
    }
    NSDictionary *errorInfo = nil;
    [self.controlScripts[index] executeAndReturnError:&errorInfo];
    if (errorInfo) {
        NSLog(@"Control script error: %@", errorInfo);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateSpotifyStatus];
    });
}

- (void)applicationDidLaunch:(NSNotification *)notification {
    NSRunningApplication *app = notification.userInfo[NSWorkspaceApplicationKey];
    if ([app.bundleIdentifier isEqualToString:@"com.spotify.client"]) {
        [self updateSpotifyStatus];
    }
}

- (void)applicationDidTerminate:(NSNotification *)notification {
    NSRunningApplication *app = notification.userInfo[NSWorkspaceApplicationKey];
    if ([app.bundleIdentifier isEqualToString:@"com.spotify.client"]) {
        self.statusItem.button.title = @"Spotify";
        self.lastTrackInfo = nil;
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.timer invalidate];
    self.timer = nil;
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
    if (@available(macOS 10.14, *)) {
        [[NSApplication sharedApplication] removeObserver:self forKeyPath:@"effectiveAppearance"];
    }
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [application setDelegate:delegate];
        [application run];
    }
    return 0;
}
