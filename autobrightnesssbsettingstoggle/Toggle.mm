#import <notify.h>

#define PREF_FILE @"/var/mobile/Library/Preferences/me.k3a.ab.plist"

// Required
extern "C" BOOL isCapable() {
	return YES;
}

// Required
extern "C" BOOL isEnabled() {
	NSDictionary* prefs = [NSDictionary dictionaryWithContentsOfFile:PREF_FILE];
	if (!prefs) return YES; // enabled by default

	return [[prefs objectForKey:@"enabled"] boolValue];
}

// Required
extern "C" void setState(BOOL enabled) {
	NSMutableDictionary* prefs = [NSMutableDictionary dictionaryWithContentsOfFile:PREF_FILE];
	if (!prefs) prefs = [NSMutableDictionary dictionary];
	[prefs setObject:[NSNumber numberWithBool:enabled] forKey:@"enabled"];
	[prefs writeToFile:PREF_FILE atomically:YES];
	
	notify_post("me.k3a.ab.reload");
}

// Required
// How long the toggle takes to toggle, in seconds.
extern "C" float getDelayTime() {
	return 0.1f;
}

// vim:ft=objc
