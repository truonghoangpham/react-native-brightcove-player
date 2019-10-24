#import "BrightcoveCastButton.h"

@implementation BrightcoveCastButton

RCT_EXPORT_MODULE(BrightcoveCastButton)

- (UIView *)view
{
    CGRect buttonFrame = CGRectMake( 0, 0, 50, 50 );
    GCKUICastButton *castButton = [[GCKUICastButton alloc] initWithFrame: buttonFrame];
//    UIButton *castButton = [[UIButton alloc] initWithFrame: buttonFrame];
//    [castButton setBackgroundColor:[UIColor redColor]];
    return castButton;
}

@end
