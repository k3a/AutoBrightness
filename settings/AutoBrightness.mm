#import <UIKit/UIKit.h>
#include <IOKit/hid/IOHIDEventSystem.h>
#include <IOKit/hid/IOHIDEventSystemClient.h>

#import <Preferences/Preferences.h>
#import <Preferences/PSTableCell.h>

#define useBackBoardServices (kCFCoreFoundationVersionNumber >= 1140.10) //iOS8
#define _plistfile @"/private/var/mobile/Library/Preferences/me.k3a.ab.plist"
static NSMutableDictionary *_settings;

extern "C" {
	float BKSDisplayBrightnessGetCurrent();
	IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
	int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
	CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef, int);
	typedef struct __IOHIDServiceClient * IOHIDServiceClientRef;
	int IOHIDServiceClientSetProperty(IOHIDServiceClientRef, CFStringRef, CFNumberRef);
}

static IOHIDEventSystemClientRef s_hidSysC;
static int ambientPreviewState = 0;
static UITableViewCell *monitorCell;

static void handle_event1 (void* target, void* refcon, IOHIDEventQueueRef queue, IOHIDEventRef event)
{
	if (IOHIDEventGetType(event)==kIOHIDEventTypeAmbientLightSensor) {
		int luxNow = IOHIDEventGetIntegerValue(event, (IOHIDEventField)kIOHIDEventFieldAmbientLightSensorLevel); // lux Event Field
		if (useBackBoardServices) {
			monitorCell.textLabel.text = [NSString stringWithFormat:@"Monitor: Lux = %4d, br = %0.3f", luxNow, BKSDisplayBrightnessGetCurrent()];
		} else {
			monitorCell.textLabel.text = [NSString stringWithFormat:@"Monitor: Lux = %d", luxNow];
		}
	}
}

@interface AutoBrightnessListController: PSListController {
}
- (void)ambientPreview;
- (void)shutdownPreview;
- (void)applicationWillResignActive:(NSNotification *)notification;
@end

@implementation AutoBrightnessListController
- (void)ambientPreview
{
	if (ambientPreviewState == 0) {
		int pv1 = 0xff00;
		int pv2 = 4;
		CFNumberRef mVals[2];
		CFStringRef mKeys[2];

		mVals[0] = CFNumberCreate(CFAllocatorGetDefault(), kCFNumberSInt32Type, &pv1);
		mVals[1] = CFNumberCreate(CFAllocatorGetDefault(), kCFNumberSInt32Type, &pv2);
		mKeys[0] = CFStringCreateWithCString(0, "PrimaryUsagePage", 0);
		mKeys[1] = CFStringCreateWithCString(0, "PrimaryUsage", 0);

		CFDictionaryRef matchInfo = CFDictionaryCreate(CFAllocatorGetDefault(),(const void**)mKeys,(const void**)mVals, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

		s_hidSysC = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
		IOHIDEventSystemClientSetMatching(s_hidSysC,matchInfo);

		CFArrayRef matchingsrvs = IOHIDEventSystemClientCopyServices(s_hidSysC,0);

		if (CFArrayGetCount(matchingsrvs) != 0) {
			IOHIDServiceClientRef alssc = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(matchingsrvs, 0);

			int ri = 1 * 1000000;
			CFNumberRef interval = CFNumberCreate(CFAllocatorGetDefault(), kCFNumberIntType, &ri);
			IOHIDServiceClientSetProperty(alssc,CFSTR("ReportInterval"),interval);

			IOHIDEventSystemClientScheduleWithRunLoop(s_hidSysC, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
			IOHIDEventSystemClientRegisterEventCallback(s_hidSysC, handle_event1, NULL, NULL);

			ambientPreviewState = 1;
		}
	} else if (ambientPreviewState == 1) {
		monitorCell.textLabel.text = @"Monitor";
		IOHIDEventSystemClientUnscheduleWithRunLoop(s_hidSysC, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
		IOHIDEventSystemClientUnregisterEventCallback(s_hidSysC);
		ambientPreviewState = 2;
	} else {
		IOHIDEventSystemClientScheduleWithRunLoop(s_hidSysC, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
		IOHIDEventSystemClientRegisterEventCallback(s_hidSysC, handle_event1, NULL, NULL);

		ambientPreviewState = 1;
	}
}

- (id)initForContentSize:(CGSize)size
{
	if ((self = [super initForContentSize:size]) != nil) {
		_settings = [NSMutableDictionary dictionaryWithContentsOfFile:_plistfile] ?: [NSMutableDictionary dictionary];
	}

	return self;
}

- (void)viewDidLoad
{
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];

	[super viewDidLoad];
}

- (void)shutdownPreview
{
	if (ambientPreviewState == 1) {
		IOHIDEventSystemClientUnscheduleWithRunLoop(s_hidSysC, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
		IOHIDEventSystemClientUnregisterEventCallback(s_hidSysC);
	}

	if (ambientPreviewState != 0) {
		CFRelease(s_hidSysC);
		monitorCell.textLabel.text = @"Monitor";
		ambientPreviewState = 0;
	}
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
	[self shutdownPreview];
}

-(void)viewWillAppear:(BOOL)animated
{
	_settings = ([NSMutableDictionary dictionaryWithContentsOfFile:_plistfile] ?: [NSMutableDictionary dictionary]);
	[super viewWillAppear:animated];
	[self reload];
}

-(void)viewWillDisappear:(BOOL)animated
{
	[self shutdownPreview];

	[super viewWillDisappear:animated];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier
{
	_settings = nil;
	_settings = ([NSMutableDictionary dictionaryWithContentsOfFile:_plistfile] ?: [NSMutableDictionary dictionary]);
	[_settings setObject:value forKey:specifier.properties[@"key"]];
	[_settings writeToFile:_plistfile atomically:YES];

	NSString *post = specifier.properties[@"PostNotification"];
	if (post) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),  (__bridge CFStringRef)post, NULL, NULL, TRUE);
	}
}

- (id)readPreferenceValue:(PSSpecifier *)specifier
{
	NSString *key = [specifier propertyForKey:@"key"];
	id defaultValue = [specifier propertyForKey:@"default"];
	id plistValue = [_settings objectForKey:key];
	if (!plistValue) plistValue = defaultValue;

	return plistValue;
}

- (id)specifiers
{

	if(_specifiers == nil) {
		_specifiers = [self loadSpecifiersFromPlistName:@"AutoBrightness" target:self];
	}
	return _specifiers;
}

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = (UITableViewCell *)[super tableView:tableView cellForRowAtIndexPath:indexPath];
	if (indexPath.row > 0 && indexPath.row % 2 != 0) {
		cell.backgroundColor = [UIColor clearColor];
	} else if (indexPath.row == 0) {
		monitorCell = nil;
		monitorCell = cell;
	}

	return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (([indexPath indexAtPosition:0] == 0 && ([indexPath indexAtPosition:1] == 0 || [indexPath indexAtPosition:1] == 2))) {
		return 44;
	} else if (([indexPath indexAtPosition:0] == 0 && [indexPath indexAtPosition:1] % 2 == 0)) {
		return 70;
	}

	return 6;
}
@end
