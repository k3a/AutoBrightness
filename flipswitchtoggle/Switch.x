#import <notify.h>

#import "FSSwitchDataSource.h"
#import "FSSwitchPanel.h"

#define PREF_FILE @"/var/mobile/Library/Preferences/me.k3a.ab.plist"

@interface K3AAutoBrightnessSwitch : NSObject <FSSwitchDataSource>
@end

@implementation K3AAutoBrightnessSwitch

- (FSSwitchState)stateForSwitchIdentifier:(NSString *)switchIdentifier
{
    NSDictionary* prefs = [NSDictionary dictionaryWithContentsOfFile:PREF_FILE];
    if (!prefs) return YES; // enabled by default

    return [[prefs objectForKey:@"enabled"] boolValue]; 
}

- (void)applyState:(FSSwitchState)newState forSwitchIdentifier:(NSString *)switchIdentifier
{
    if (newState == FSSwitchStateIndeterminate)
        return;

    NSMutableDictionary* prefs = [NSMutableDictionary dictionaryWithContentsOfFile:PREF_FILE];
    if (!prefs) prefs = [NSMutableDictionary dictionary];
    [prefs setObject:[NSNumber numberWithBool:newState] forKey:@"enabled"];
    [prefs writeToFile:PREF_FILE atomically:YES];

    notify_post("me.k3a.ab.reload");
}

@end
