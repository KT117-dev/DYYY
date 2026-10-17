#import <UIKit/UIKit.h>

@interface DYYYSettingsCoordinator : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)installGestureInWindow:(UIWindow *)window;
- (void)presentFromWindow:(UIWindow *)window;
+ (UIViewController *)presenter;
+ (UINavigationController *)navigationController;
+ (void)closeSettings;
+ (void)configurePopover:(UIViewController *)controller from:(UIViewController *)presenter;
@end
