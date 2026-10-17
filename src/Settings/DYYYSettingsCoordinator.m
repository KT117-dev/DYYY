#import "DYYYSettingsCoordinator.h"
#import <objc/runtime.h>
#import "DYYYSettingViewController.h"
#import "DYYYSettingsHelper.h"
#import "DYYYSettingsRegistry.h"
#import "DYYYUtils.h"

@interface DYYYSettingsTabBarController : UITabBarController
@property(nonatomic, weak) UIWindowScene *sourceScene;
@property(nonatomic, strong) id themeRegistration;
@property(nonatomic, strong) DYYYSettingsRegistry *registry;
@end
@implementation DYYYSettingsTabBarController
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.overrideUserInterfaceStyle = self.sourceScene ? self.sourceScene.traitCollection.userInterfaceStyle : UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    if (@available(iOS 17.0, *)) {
        if (!self.themeRegistration && self.sourceScene) {
            __weak typeof(self) weakSelf = self;
            self.themeRegistration = [self.sourceScene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                                                                   withHandler:^(UIWindowScene *scene, __unused UITraitCollection *previous) {
                                                                     weakSelf.overrideUserInterfaceStyle = scene.traitCollection.userInterfaceStyle;
                                                                   }];
        }
    }
}
- (void)dealloc {
    [self.registry invalidate];
    if (@available(iOS 17.0, *)) {
        if (self.themeRegistration)
            [self.sourceScene unregisterForTraitChanges:self.themeRegistration];
    }
}
@end

@interface DYYYSettingsCoordinator () <UITabBarControllerDelegate, UIAdaptivePresentationControllerDelegate>
@property(nonatomic, weak) UITabBarController *settings;
@property(nonatomic) BOOL keyboardVisible;
@end

@implementation DYYYSettingsCoordinator
+ (instancetype)shared {
    static DYYYSettingsCoordinator *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      instance = [self new];
      [NSNotificationCenter.defaultCenter addObserver:instance selector:@selector(keyboardShown:) name:UIKeyboardWillShowNotification object:nil];
      [NSNotificationCenter.defaultCenter addObserver:instance selector:@selector(keyboardHidden:) name:UIKeyboardWillHideNotification object:nil];
    });
    return instance;
}
- (void)keyboardShown:(NSNotification *)note {
    self.keyboardVisible = YES;
}
- (void)keyboardHidden:(NSNotification *)note {
    self.keyboardVisible = NO;
}
- (void)installGestureInWindow:(UIWindow *)window {
    if (!NSThread.isMainThread || !window || window.windowLevel != UIWindowLevelNormal)
        return;
    const void *key = @selector(installGestureInWindow:);
    if (objc_getAssociatedObject(window, key))
        return;
    UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
    gesture.numberOfTouchesRequired = 2;
    gesture.minimumPressDuration = 0.6;
    gesture.allowableMovement = 10;
    gesture.cancelsTouchesInView = NO;
    gesture.delegate = self;
    [window addGestureRecognizer:gesture];
    objc_setAssociatedObject(window, key, gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (self.settings || self.keyboardVisible)
        return NO;
    for (UIView *view = touch.view; view; view = view.superview) {
        if ([view isKindOfClass:UITextField.class] || [view isKindOfClass:UITextView.class] || [view isKindOfClass:UISearchBar.class])
            return NO;
        for (UIGestureRecognizer *other in view.gestureRecognizers) {
            if ([other isKindOfClass:UIPinchGestureRecognizer.class] && (other.state == UIGestureRecognizerStateBegan || other.state == UIGestureRecognizerStateChanged))
                return NO;
        }
    }
    return YES;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    UIWindow *window = (UIWindow *)gesture.view;
    return !self.settings && !self.keyboardVisible && window.isKeyWindow && window.windowLevel == UIWindowLevelNormal &&
           (!window.windowScene || window.windowScene.activationState == UISceneActivationStateForegroundActive) && ![self containsTextInputResponder:window];
}
- (BOOL)containsTextInputResponder:(UIView *)view {
    if (view.isFirstResponder && [view conformsToProtocol:@protocol(UITextInput)])
        return YES;
    for (UIView *child in view.subviews)
        if ([self containsTextInputResponder:child])
            return YES;
    return NO;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return ![other isKindOfClass:UIPinchGestureRecognizer.class] && ![other isKindOfClass:UILongPressGestureRecognizer.class];
}
- (void)longPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan)
        return;
    [self presentFromWindow:(UIWindow *)gesture.view];
}
+ (UIViewController *)topController:(UIViewController *)controller {
    while (controller) {
        if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) {
            controller = controller.presentedViewController;
            continue;
        }
        if ([controller isKindOfClass:UINavigationController.class]) {
            controller = ((UINavigationController *)controller).visibleViewController;
            continue;
        }
        if ([controller isKindOfClass:UITabBarController.class]) {
            controller = ((UITabBarController *)controller).selectedViewController;
            continue;
        }
        break;
    }
    return controller;
}
+ (UIViewController *)presenter {
    UITabBarController *settings = [self shared].settings;
    if (settings)
        return [self topController:settings];
    return [self topController:[DYYYUtils getActiveWindow].rootViewController];
}
+ (UINavigationController *)navigationController {
    if ([DYYYSettingsRegistry isBuilding])
        return nil;
    return [self presenter].navigationController;
}
+ (void)configurePopover:(UIViewController *)controller from:(UIViewController *)presenter {
    UIPopoverPresentationController *popover = controller.popoverPresentationController;
    if (popover) {
        popover.sourceView = presenter.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
        popover.permittedArrowDirections = 0;
    }
}
- (void)presentFromWindow:(UIWindow *)window {
    if (!NSThread.isMainThread || self.settings || self.keyboardVisible || !window.rootViewController)
        return;
    UIViewController *presenter = [self.class topController:window.rootViewController];
    if (!presenter.view.window || presenter.isBeingPresented || presenter.isBeingDismissed || presenter.transitionCoordinator || [presenter isKindOfClass:UIAlertController.class])
        return;
    DYYYSettingsTabBarController *tabs = [DYYYSettingsTabBarController new];
    tabs.sourceScene = window.windowScene;
    self.settings = tabs;
    tabs.registry = [DYYYSettingsRegistry current];
    [tabs.registry build];
    NSArray *titles = @[ @"总览", @"播放", @"外观", @"净化", @"工具" ];
    NSArray *symbols = @[ @"square.grid.2x2", @"play.rectangle", @"paintbrush", @"eye.slash", @"slider.horizontal.3" ];
    NSMutableArray *controllers = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; i++) {
        DYYYSettingViewController *list = [[DYYYSettingViewController alloc] initWithTab:titles[i]];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:list];
        navigation.navigationBar.prefersLargeTitles = YES;
        navigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:titles[i] image:[UIImage systemImageNamed:symbols[i]] tag:i];
        [controllers addObject:navigation];
    }
    tabs.viewControllers = controllers;
    tabs.delegate = self;
    // 不覆盖 tabBar 材质；iOS 26 的系统 UITabBar 自行提供 Liquid Glass。
    tabs.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    tabs.modalPresentationStyle = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? UIModalPresentationFormSheet : UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        tabs.sheetPresentationController.detents = @[ UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent ];
        tabs.sheetPresentationController.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
        tabs.sheetPresentationController.prefersGrabberVisible = YES;
        tabs.sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge = YES;
    }
    tabs.presentationController.delegate = self;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [presenter presentViewController:tabs
                            animated:YES
                          completion:^{
                            tabs.presentationController.delegate = self;
                            if (![NSUserDefaults.standardUserDefaults boolForKey:@"DYYYUserAgreementAccepted"])
                                [DYYYSettingsHelper showUserAgreementAlert];
                          }];
}
- (void)tabBarController:(UITabBarController *)controller didSelectViewController:(UIViewController *)viewController {
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    DYYYSettingsTabBarController *tabs = (DYYYSettingsTabBarController *)presentationController.presentedViewController;
    [tabs.registry invalidate];
    self.settings = nil;
}
+ (void)closeSettings {
    DYYYSettingsCoordinator *coordinator = [self shared];
    DYYYSettingsRegistry *registry = ((DYYYSettingsTabBarController *)coordinator.settings).registry;
    [coordinator.settings dismissViewControllerAnimated:YES
                                             completion:^{
                                               [registry invalidate];
                                               coordinator.settings = nil;
                                             }];
}
@end
