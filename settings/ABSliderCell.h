#import <Preferences/PSTableCell.h>

@interface ABSliderCell : PSTableCell {
	UILabel *title;
	UITextField *value;
	UISlider *slider;

	float min;
	float max;
	float step;

	int _row;

	NSNumberFormatter *formatter;
	id specifierObject;
	NSString *defaults;
	NSString *PostNotification;
}
-(void)enableControls:(BOOL)arg1;
@end
