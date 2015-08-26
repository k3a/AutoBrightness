#include <IOKit/hid/IOHIDEventSystemClient.h>
#include <Foundation/Foundation.h>
#include <stdio.h>
#include <UIKit/UIKit.h>
#include <dlfcn.h>
#import <notify.h>

// #define DEBUG 1
#ifdef DEBUG
#define AB_LOG(fmt, ...) NSLog((@"AutoBrightness: "  fmt), ##__VA_ARGS__)
#else
#define AB_LOG(fmt, ...)
// #define NSLog(fmt, ...)
#endif

#define useBackBoardServices (kCFCoreFoundationVersionNumber >= 1140.10) //iOS8

static int (*SBSSpringBoardServerPort)() = 0;
static void (*SBSetCurrentBacklightLevel)(int _port, float level) = 0;

typedef struct BKSDisplayBrightnessTransaction *BKSDisplayBrightnessTransactionRef;
static BKSDisplayBrightnessTransactionRef (*BKSDisplayBrightnessTransactionCreate)(CFAllocatorRef allocator) = 0;
static void (*BKSDisplayBrightnessSet)(float value) = 0;
static float (*BKSDisplayBrightnessGetCurrent)() = 0;
static void (*BKSDisplayBrightnessSetAutoBrightnessEnabled)(BOOL enabled) = 0;

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef, int);
typedef struct __IOHIDServiceClient * IOHIDServiceClientRef;
int IOHIDServiceClientSetProperty(IOHIDServiceClientRef, CFStringRef, CFNumberRef);


static IOHIDEventSystemClientRef s_hidSysC; // event system client
static bool s_running = false; // whether we are scheduled and running

static float s_lastBr = 0.0; // latest brightness value set
static bool s_screenBlanketed = false;
static bool s_resetLux = false; // when true, imemdiately set the new lux value
static bool s_isSettingBrightness = false;
static float s_threshold = -0.001;
static float s_screenOffBrightness = -0.01;
static float s_setInterval = 4;
static float s_ambientSensorInterval = 0.5;
static int s_luxMax = 5000;
static float s_luxOffset = 0;
static int s_maxBrightnessSteps = 20;

// sets the physical brightness as fast as possible (using SpringBoard services)
static void setBrightness(float br, bool skipDeltaCheck, bool instant)
{
	if (!s_running || s_isSettingBrightness) {
		return; //to keep it from running when you first turn on the screen and it is disabled??
	}

	float thres = s_threshold < 0 ? 0.002f+0.1f*br*br : s_threshold;
	float diff = fabsf(s_lastBr-br);
	if (skipDeltaCheck || diff > thres)
	{
		s_isSettingBrightness = true;
		int port = useBackBoardServices ? 1 : SBSSpringBoardServerPort();
		int numSteps = instant ? 1 : diff/0.002f; // how big a step will be
		if (numSteps == 0)
			numSteps = 1;
		else if (numSteps > s_maxBrightnessSteps)
			numSteps = s_maxBrightnessSteps;

		AB_LOG(@"setting brightness YES,			BR %f | DIFF %f | THRES %f | STEPS %d", br, diff, thres, numSteps);

		float step = (br-s_lastBr)/numSteps;
		if (useBackBoardServices)
		{
			BKSDisplayBrightnessTransactionRef transaction = BKSDisplayBrightnessTransactionCreate(kCFAllocatorDefault);
			for (int i=1; i<=numSteps; i++)
			{
				BKSDisplayBrightnessSet(s_lastBr + step*i);
				usleep(500000.0f/numSteps);
			}
			CFRelease(transaction);
		}
		else
		{
			for (int i=1; i<=numSteps; i++)
			{
				SBSetCurrentBacklightLevel( port, s_lastBr + step*i);
				usleep(500000.0f/numSteps);
			}
		}
		s_lastBr = br;
		s_isSettingBrightness = false;
		//NSLog(@"BR: %f (SET)", br);
	}
	else
	{
		//NSLog(@"BR: %f", br);
	}
}

void handle_event1 (void* target, void* refcon, IOHIDEventQueueRef queue, IOHIDEventRef event)
{
	if (s_screenBlanketed) return;

	if (IOHIDEventGetType(event)==kIOHIDEventTypeAmbientLightSensor)
	{
		int luxNow = IOHIDEventGetIntegerValue(event, (IOHIDEventField)kIOHIDEventFieldAmbientLightSensorLevel); // lux Event Field
		static int luxTotal = 0;
		static int luxNum = 0;

		// comput time elapset...
		static time_t lastTime = 0;
		time_t tim = time(NULL);
		if (lastTime == 0 || s_resetLux)
		{
			// first time this function is called - set to "now" values
			lastTime = tim - 2.5 * s_setInterval;
			luxTotal = luxNow;
			luxNum = 1;
		}

		AB_LOG(@"got new data at %ld - lux now %d", tim, luxNow);

		// skip if less than x-seconds since the last event
		if (tim - lastTime < s_setInterval && !s_resetLux)
		{
			luxTotal += luxNow;
			luxNum++;
			return;
		}
		s_resetLux = false;

		// compute filtered lux
		int luxValue = ((float)luxTotal)/luxNum;
		luxTotal = luxNow;
		luxNum = 1;

		// comute current brightness from lux value
		//float br = sqrtf(luxValue)/50.0f;
		float br = 0.199311f * logf((5000.0f / s_luxMax) * 0.03f * luxValue + 1.0f + s_luxOffset);
		if (br>1) br = 1;
		//NSLog(@"LUX: %d -> %.4f", luxValue, br);

		// get old brightness
		//static float oldBr = 0;
		//if (oldBr == 0) oldBr = br;

		// smooth brightness
		//br = (oldBr*2+br)/3.0f;

		// set
		AB_LOG(@"check brightness, time diff %4ld | BR %f | MAXLUX %6d | OFFSET %7.3f | LUX %d", tim - lastTime, br, s_luxMax, s_luxOffset, luxValue);
		lastTime = tim;
		setBrightness(br, s_resetLux, false);
		// store...
		//oldBr = br;
	}
}

void reloadPrefs()
{
	AB_LOG(@"reloading prefs");

	NSDictionary* prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/me.k3a.ab.plist"];
	bool enabled = true; // enabled by default
	s_threshold = -0.001;
	s_screenOffBrightness = -0.01;
	s_setInterval = 4;
	s_ambientSensorInterval = 0.5;
	s_luxMax = 5000;
	s_luxOffset = 0;
	s_maxBrightnessSteps = 20;

	if (prefs)
	{
		enabled = [[prefs objectForKey:@"enabled"] boolValue];

		if ([prefs objectForKey:@"setInterval"] != nil)
		{
			s_setInterval = [[prefs objectForKey:@"setInterval"] floatValue];
		}

		if ([prefs objectForKey:@"threshold"] != nil)
		{
			s_threshold = [[prefs objectForKey:@"threshold"] floatValue];
		}

		if ([prefs objectForKey:@"screenOffBrightness"] != nil)
		{
			s_screenOffBrightness = [[prefs objectForKey:@"screenOffBrightness"] floatValue];
		}

		if ([prefs objectForKey:@"ambientSensorInterval"] != nil)
		{
			s_ambientSensorInterval = [[prefs objectForKey:@"ambientSensorInterval"] floatValue];
		}

		if ([prefs objectForKey:@"luxMax"] != nil) {
			s_luxMax = [[prefs objectForKey:@"luxMax"] intValue];
		}

		if ([prefs objectForKey:@"luxOffset"] != nil)
		{
			s_luxOffset = [[prefs objectForKey:@"luxOffset"] floatValue];
		}

		if ([prefs objectForKey:@"maxBrightnessSteps"] != nil)
		{
			s_maxBrightnessSteps = [[prefs objectForKey:@"maxBrightnessSteps"] intValue];
		}
	}
	else
	{
		prefs = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithBool:YES], @"enabled",
				[NSNumber numberWithFloat:s_threshold], @"threshold",
				[NSNumber numberWithFloat:s_screenOffBrightness], @"screenOffBrightness",
				[NSNumber numberWithFloat:s_setInterval], @"setInterval",
				[NSNumber numberWithFloat:s_ambientSensorInterval], @"ambientSensorInterval",
				[NSNumber numberWithInteger:s_luxMax], @"luxMax",
				[NSNumber numberWithFloat:s_luxOffset], @"luxOffset",
				[NSNumber numberWithInteger:s_maxBrightnessSteps], @"maxBrightnessSteps",
				nil];
		[prefs writeToFile:@"/var/mobile/Library/Preferences/me.k3a.ab.plist" atomically:YES];
	}

	if (s_ambientSensorInterval < 0.25) s_ambientSensorInterval = 0.25;
	if (s_setInterval < s_ambientSensorInterval) s_setInterval = s_ambientSensorInterval;
	if (s_maxBrightnessSteps < 1) s_maxBrightnessSteps = 1;
	if (s_maxBrightnessSteps > 200) s_maxBrightnessSteps = 200;
	if (s_screenOffBrightness > 1) s_screenOffBrightness = 1;
	if (s_luxMax < 100) s_luxMax = 100;
	if (s_luxMax > 5000) s_luxMax = 5000;
	if (s_luxOffset < 0) s_luxOffset = 0;
	if (s_luxOffset > 10) s_luxOffset = 10;
	if (s_threshold > 0.1) s_threshold = 0.1;

	if (!s_running && enabled) // enable!
	{
		s_running = true;
		s_resetLux = true;
		if (useBackBoardServices)
		{
			s_lastBr = BKSDisplayBrightnessGetCurrent();
			BKSDisplayBrightnessSetAutoBrightnessEnabled(NO);
		}

		IOHIDEventSystemClientScheduleWithRunLoop(s_hidSysC, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
		IOHIDEventSystemClientRegisterEventCallback(s_hidSysC, handle_event1, NULL, NULL);
		NSLog(@"AutoBrightness: enabled, interval = %0.2f, s_threshold = %0.4f", s_setInterval, s_threshold);
	}
	else if (s_running && !enabled) // disable!
	{
		IOHIDEventSystemClientUnscheduleWithRunLoop(s_hidSysC, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
		IOHIDEventSystemClientUnregisterEventCallback(s_hidSysC);
		s_running = false;
		NSLog(@"AutoBrightness: disabled");
	}
}

int main()
{
	// ------- get functs ----------------
	if (useBackBoardServices)
	{
		void *backBoardServices = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY);
		if (!backBoardServices)
		{
			NSLog(@"AutoBrightness: Failed to open BackBoardServices framework!");
			return 1;
		}

		BKSDisplayBrightnessTransactionCreate = (BKSDisplayBrightnessTransactionRef (*)(CFAllocatorRef))dlsym(backBoardServices, "BKSDisplayBrightnessTransactionCreate");
		if (!BKSDisplayBrightnessTransactionCreate)
		{
			NSLog(@"AutoBrightness: Failed to get BKSDisplayBrightnessTransactionCreate!");
			return 1;
		}

		BKSDisplayBrightnessSet = (void (*)(float))dlsym(backBoardServices, "BKSDisplayBrightnessSet");
		if (!BKSDisplayBrightnessSet)
		{
			NSLog(@"AutoBrightness: Failed to get BKSDisplayBrightnessSet!");
			return 1;
		}

		BKSDisplayBrightnessGetCurrent = (float (*)())dlsym(backBoardServices, "BKSDisplayBrightnessGetCurrent");
		if (!BKSDisplayBrightnessGetCurrent)
		{
			NSLog(@"AutoBrightness: Failed to get BKSDisplayBrightnessGetCurrent!");
			return 1;
		}

		BKSDisplayBrightnessSetAutoBrightnessEnabled = (void (*)(BOOL))dlsym(backBoardServices, "BKSDisplayBrightnessSetAutoBrightnessEnabled");
		if (!BKSDisplayBrightnessSetAutoBrightnessEnabled)
		{
			NSLog(@"AutoBrightness: Failed to get BKSDisplayBrightnessSetAutoBrightnessEnabled!");
			return 1;
		}
	}
	else
	{
		void *uikit = dlopen("/System/Library/Framework/UIKit.framework/UIKit", RTLD_LAZY);
		if (!uikit)
		{
			NSLog(@"AutoBrightness: Failed to open UIKit framework!");
			return 1;
		}

		SBSSpringBoardServerPort = (int (*)())dlsym(uikit, "SBSSpringBoardServerPort");
		if (!SBSSpringBoardServerPort)
		{
			NSLog(@"AutoBrightness: Failed to get SBSSpringBoardServerPort!");
			return 1;
		}

		SBSetCurrentBacklightLevel = (void (*)(int,float))dlsym(uikit, "SBSetCurrentBacklightLevel");
		if (!SBSSpringBoardServerPort)
		{
			NSLog(@"AutoBrightness: Failed to get SBSetCurrentBacklightLevel!");
			return 1;
		}
	}

	// ------- get ALS service -----------

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

	if (CFArrayGetCount(matchingsrvs) == 0)
	{
		NSLog(@"AutoBrightness: ALS Not found!");
		return 1;
	}

	// ----- configure the service -----------------

	IOHIDServiceClientRef alssc = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(matchingsrvs, 0);

	int ri = s_ambientSensorInterval * 1000000;
	CFNumberRef interval = CFNumberCreate(CFAllocatorGetDefault(), kCFNumberIntType, &ri);
	IOHIDServiceClientSetProperty(alssc,CFSTR("ReportInterval"),interval);

	// ----- set ALS callback -----------------

	// will be set later in reloadPrefs
	/*IOHIDEventSystemClientScheduleWithRunLoop(s_hidSysC, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	IOHIDEventSystemClientRegisterEventCallback(s_hidSysC, handle_event1, NULL, NULL);
	s_running = true;*/

	// ----------- set lock notif ---------------------
	int notifyToken;
	int status = notify_register_dispatch("com.apple.springboard.hasBlankedScreen",
										  &notifyToken,
										  dispatch_get_main_queue(), ^(int t) {
											  uint64_t state;
											  int result = notify_get_state(t, &state);
											  s_screenBlanketed = state != 0;
											  if (s_running && !s_screenBlanketed)
											  {
												  s_resetLux = true;
											  }
											  else if (s_running && s_screenOffBrightness >= 0)
											  {
												  setBrightness(s_screenOffBrightness, true, true);
											  }
											  //NSLog(@"AutoBrightness: lock state change = %llu", state);
											  if (result != NOTIFY_STATUS_OK) {
												  NSLog(@"AutoBrightness: notify_get_state() not returning NOTIFY_STATUS_OK");
											  }
										  });
	if (status != NOTIFY_STATUS_OK) {
		NSLog(@"AutoBrightness: notify_register_dispatch() not returning NOTIFY_STATUS_OK");
	}

	// -------------- set toggle notif ------------------
	int toggleNotifToken;
	status = notify_register_dispatch("me.k3a.ab.reload",
										&toggleNotifToken,
										dispatch_get_main_queue(), ^(int t) {
											reloadPrefs();
										});

	if (status != NOTIFY_STATUS_OK) {
		NSLog(@"AutoBrightness: toggle notif: notify_register_dispatch() not returning NOTIFY_STATUS_OK");
	}

	// -------- run! ------------------------------
	reloadPrefs();
	CFRunLoopRun();

	return 0;

}
