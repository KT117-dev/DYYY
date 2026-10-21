#import <UIKit/UIKit.h>

FOUNDATION_EXPORT CGFloat const DYYYSettingsCornerRadius;

@interface DYYYSettingsCoordinator : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)installGestureInWindow:(UIWindow *)window;
- (void)presentFromWindow:(UIWindow *)window;
+ (UIViewController *)presenter;
+ (UINavigationController *)navigationController;
+ (void)closeSettings;
+ (void)prepareForTextInput;
+ (BOOL)isSettingsInputFocusNotification:(NSNotification *)notification;
+ (void)configurePopover:(UIViewController *)controller from:(UIViewController *)presenter;
@end
