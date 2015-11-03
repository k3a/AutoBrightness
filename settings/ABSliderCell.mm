#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSViewController.h>

#import "ABSliderCell.h"

@implementation ABSliderCell
-(void)enableControls:(BOOL)arg1
{
	title.enabled = arg1;
	value.enabled = arg1;
	value.alpha = arg1 ? 1.0 : 0.5;
	slider.enabled = arg1;
}

- (NSUInteger)decimalPlacesForFloat:(float)number
{
	NSNumber *num = [NSNumber numberWithFloat:number];

	NSString *resultString = [num stringValue];
	resultString = [resultString stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"0"]];

	NSScanner *theScanner = [NSScanner scannerWithString:resultString];
	NSString *decimalPoint = @".";
	NSString *unwanted = nil;

	[theScanner scanUpToString:decimalPoint intoString:&unwanted];

	NSUInteger numDecimalPlaces = (([resultString length] - [unwanted length]) > 0) ? [resultString length] - [unwanted length] - 1 : 0;

	return numDecimalPlaces;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier
{
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier specifier:specifier];

	if (self) {
		specifierObject = [specifier propertyForKey:@"key"];
		defaults = [specifier propertyForKey:@"defaults"];
		PostNotification = [specifier propertyForKey:@"PostNotification"];
		self.backgroundColor = [UIColor whiteColor];
		_row = [specifier propertyForKey:@"row"] ? [[specifier propertyForKey:@"row"] intValue] : -1;

		CGRect titleFrame = CGRectMake(15, 10, self.frame.size.width - 120, 20);
		CGRect valueFrame = CGRectMake(self.frame.size.width - 100, 3, 85, 30);
		CGRect sliderFrame = CGRectMake(15, 28, self.frame.size.width - 30, 40);

		title = [[UILabel alloc] initWithFrame:titleFrame];
		[title setNumberOfLines:1];
		[title setText:[specifier propertyForKey:@"name"]];
		[title setBackgroundColor:[UIColor clearColor]];
		title.textColor = [UIColor blackColor];
		title.textAlignment = NSTextAlignmentLeft;

		UIButton *editButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
		editButton.frame = valueFrame;
		[editButton setTitle:@"" forState:UIControlStateNormal];
		[editButton addTarget:self action:@selector(askUserForInput) forControlEvents:UIControlEventTouchUpInside];
		editButton.layer.cornerRadius = 5;
		editButton.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.04];

		value = [[UITextField alloc] initWithFrame:valueFrame];
		[value setText:@"0"];
		[value setBackgroundColor:[UIColor clearColor]];
		value.textColor = [UIColor blueColor];
		value.textAlignment = NSTextAlignmentRight;
		value.enabled = NO;

		if ([specifier propertyForKey:@"type"]) {
			UILabel *dollarSign = [[UILabel alloc] initWithFrame:CGRectMake(0,0,0,0)];
			dollarSign.font = [UIFont systemFontOfSize:15];
			dollarSign.text = [specifier propertyForKey:@"type"];
			dollarSign.textColor = [UIColor blueColor];
			[dollarSign sizeToFit];

			value.rightView = dollarSign;
			value.rightViewMode = UITextFieldViewModeAlways;
			value.returnKeyType = UIReturnKeyDone;
		}

		slider = [[UISlider alloc] initWithFrame:sliderFrame];
		[slider addTarget:self action:@selector(sliderValueChangedAction:) forControlEvents:UIControlEventValueChanged];
		[slider addTarget:self action:@selector(sliderTouchUpInsideOutsideAction:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];

		step = [specifier propertyForKey:@"step"] ? [[specifier propertyForKey:@"step"] floatValue] : 1.0;
		min = [[specifier propertyForKey:@"min"] floatValue];
		max = [[specifier propertyForKey:@"max"] floatValue];
		slider.minimumValue = min;
		slider.maximumValue = max;
		slider.continuous = YES;

		slider.value = [[specifier propertyForKey:@"default"] floatValue];
		if (defaults) {
			NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", defaults]];
			if (preferences) {
				if ([preferences objectForKey:specifierObject]) {
					slider.value = [[preferences objectForKey:specifierObject] floatValue];
				}
			}
		}

		NSUInteger numDigits = [self decimalPlacesForFloat:step];
		formatter = [[NSNumberFormatter alloc] init];
		[formatter setNumberStyle:NSNumberFormatterDecimalStyle];
		[formatter setMinimumFractionDigits:numDigits];
		[formatter setMaximumFractionDigits:numDigits];
		value.text = [NSString stringWithFormat:@"%@", [formatter stringFromNumber:[NSNumber numberWithFloat:roundf(slider.value / step) * step]]];

		value.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
		editButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
		slider.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleWidth;

		[((UITableViewCell *)self).contentView addSubview:title];
		[((UITableViewCell *)self).contentView addSubview:value];
		[((UITableViewCell *)self).contentView addSubview:editButton];
		[((UITableViewCell *)self).contentView addSubview:slider];
	}

	return self;
}

- (void) askUserForInput
{
	NSString *message = [NSString stringWithFormat:@"Please enter a value between\n%0.3f%@ and %0.3f%@ (%@)",
						 min,
						 [self.specifier propertyForKey:@"type"] ?: @"",
						 max,
						 [self.specifier propertyForKey:@"type"] ?: @"",
						 value.text];

	alert = [[UIAlertView alloc] initWithTitle:nil
													message:message
												   delegate:self
										  cancelButtonTitle:@"Cancel"
										  otherButtonTitles:@"Save"
						  , nil];
	alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	alert.tag = 2626;

	[[alert textFieldAtIndex:0] setKeyboardType:UIKeyboardTypeDecimalPad];

	BOOL negativeSign = min < 0;
	if (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPad && negativeSign) {
		UIToolbar *toolBar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 44)];
		UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithTitle:@"Negative" style:UIBarButtonItemStylePlain target:self action:@selector(enterNegativeSign)];
		NSArray *buttons = [NSArray arrayWithObjects:button, nil];
		[toolBar setItems:buttons animated:NO];
		[[alert textFieldAtIndex:0] setInputAccessoryView:toolBar];
	}

	[alert show];
}

-(void)enterNegativeSign
{
	if (alert) {
		NSString *text = [alert textFieldAtIndex:0].text;
		if ([text hasPrefix:@"-"]) {
			[alert textFieldAtIndex:0].text = [text substringFromIndex:1];
		} else {
			[alert textFieldAtIndex:0].text = [NSString stringWithFormat:@"-%@", text];
		}
	}
}

-(void) alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if (alertView.tag == 2626 && buttonIndex == 1) {
		slider.value = [[alertView textFieldAtIndex:0].text floatValue];
		[self sliderValueChangedAction:slider];
		[self sliderTouchUpInsideOutsideAction:slider];
	}
}

- (void) sliderValueChangedAction:(UISlider *)paramSender
{
	value.text = [NSString stringWithFormat:@"%@", [formatter stringFromNumber:[NSNumber numberWithFloat:roundf(slider.value / step) * step]]];
}

- (void) sliderTouchUpInsideOutsideAction:(UISlider *)paramSender
{
	NSNumber *val = [NSNumber numberWithFloat:roundf(slider.value / step) * step];
	value.text = [NSString stringWithFormat:@"%@", [formatter stringFromNumber:val]];

	if (defaults) {
		NSString *fileName = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", defaults];
		NSMutableDictionary *preferences = ([NSMutableDictionary dictionaryWithContentsOfFile:fileName] ?: [NSMutableDictionary dictionary]);
		if (preferences) {
			[preferences setObject:val forKey:specifierObject];
			[preferences writeToFile:fileName atomically:YES];
		}

		fileName = nil;
	}

	if (PostNotification) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)PostNotification, NULL, NULL, TRUE);
	}

	val = nil;
}
@end
