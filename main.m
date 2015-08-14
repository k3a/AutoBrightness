#include <IOKit/hid/IOHIDEventSystemClient.h>
#include <Foundation/Foundation.h>
#include <stdio.h>
#include <UIKit/UIKit.h>
#include <dlfcn.h>
#import <notify.h>

//#define AB_LOG 1
#define useBackBoardServices (kCFCoreFoundationVersionNumber >= 1140.10) //iOS8

static int (*SBSSpringBoardServerPort)() = 0;
static void (*SBSetCurrentBacklightLevel)(int _port, float level) = 0;

typedef struct BKSDisplayBrightnessTransaction *BKSDisplayBrightnessTransactionRef;
static BKSDisplayBrightnessTransactionRef (*BKSDisplayBrightnessTransactionCreate)(CFAllocatorRef allocator) = 0;
static void (*BKSDisplayBrightnessSet)(float value) = 0;

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef, int);
typedef struct __IOHIDServiceClient * IOHIDServiceClientRef;
int IOHIDServiceClientSetProperty(IOHIDServiceClientRef, CFStringRef, CFNumberRef);


static IOHIDEventSystemClientRef s_hidSysC; // event system client
static bool s_running = false; // whether we are scheduled and running

static float s_lastBr = 0; // latest brightness value set
static bool s_screenBlanketed = false;
static bool s_resetLux = false; // when true, imemdiately set the new lux value

// sets the physical brightness as fast as possible (using SpringBoard services)
static void setBrightness(float br, bool skipDeltaCheck)
{
	float thres = 0.002f+0.1f*br*br;
	float diff = fabsf(s_lastBr-br);
	if (skipDeltaCheck || diff > thres)
	{
		int port = useBackBoardServices ? 1 : SBSSpringBoardServerPort();
		int numSteps = diff/0.002f; // how big a step will be
		if (numSteps == 0)
			numSteps = 1;
		else if (numSteps > 20)
			numSteps = 20;

#ifdef AB_LOG
		NSLog(@"AutoBrightness: setting brightness %f | DIFF %f | THRES %f | STEPS %d", br, diff, thres, numSteps);
#endif

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
			lastTime = tim - 10;
			luxTotal = luxNow;
			luxNum = 1;
		}
#ifdef AB_LOG
		NSLog(@"AutoBrightness: %d got new data - lux now %d", tim, luxNow);
#endif

		// skip if less than x-seconds since the last event
		if (tim - lastTime < 4 && !s_resetLux)
		{
			luxTotal += luxNow;
			luxNum++;
			return;
		}
		lastTime = tim;
		s_resetLux = false;

		// compute filtered lux
		int luxValue = ((float)luxTotal)/luxNum;
		luxTotal = luxNow;
		luxNum = 1;

		// comute current brightness from lux value
		//float br = sqrtf(luxValue)/50.0f;
		float br = 0.199311f*logf(0.03f*luxValue+1.0f);
		if (br>1) br = 1;
		//NSLog(@"LUX: %d -> %.4f", luxValue, br);

		// get old brightness
		//static float oldBr = 0;
		//if (oldBr == 0) oldBr = br;

		// smooth brightness
		//br = (oldBr*2+br)/3.0f;

		// set
#ifdef AB_LOG
		NSLog(@"AutoBrightness: %d timeout %d - computed %f brightness", tim, tim - lastTime, br);
#endif
		setBrightness(br, s_resetLux);

		// store...
		//oldBr = br;
	}
}

void reloadPrefs()
{
#ifdef AB_LOG
	NSLog(@"AB: reloading prefs");
#endif

	NSDictionary* prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/me.k3a.ab.plist"];
	bool enabled = true; // enabled by default

	if (prefs)
	{
		enabled = [[prefs objectForKey:@"enabled"] boolValue];
	}

	if (!s_running && enabled) // enable!
	{
		IOHIDEventSystemClientScheduleWithRunLoop(s_hidSysC, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
		IOHIDEventSystemClientRegisterEventCallback(s_hidSysC, handle_event1, NULL, NULL);
		s_running = true;
		NSLog(@"AB: enabled");
	}
	else if (s_running && !enabled) // disable!
	{
		IOHIDEventSystemClientUnscheduleWithRunLoop(s_hidSysC, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
		IOHIDEventSystemClientUnregisterEventCallback(s_hidSysC);
		s_running = false;
		NSLog(@"AB: disabled");
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

	int ri = 500000;//1000;
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
											  if (!s_screenBlanketed)
											  {
												  setBrightness(s_lastBr, true);
												  s_resetLux = true;
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
