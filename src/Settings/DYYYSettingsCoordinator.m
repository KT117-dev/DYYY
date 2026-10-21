#import "DYYYSettingsCoordinator.h"
#import <objc/runtime.h>
#import "DYYYSettingViewController.h"
#import "DYYYSettingsHelper.h"
#import "DYYYSettingsRegistry.h"
#import "DYYYUtils.h"
#import "DYYYBottomAlertView.h"

CGFloat const DYYYSettingsCornerRadius = 35;

@interface DYYYSettingsWindow : UIWindow
@property(nonatomic) BOOL acceptsTextInput;
@property(nonatomic, weak) UIWindow *hostWindow;
@end
@implementation DYYYSettingsWindow
- (BOOL)canBecomeKeyWindow {
    return self.acceptsTextInput;
}
- (void)sendEvent:(UIEvent *)event {
    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseBegan)
            continue;
        for (UIView *view = touch.view; view; view = view.superview) {
            if ([view isKindOfClass:UITextField.class] || [view isKindOfClass:UITextView.class]) {
                [DYYYSettingsCoordinator prepareForTextInput];
                break;
            }
        }
    }
    [super sendEvent:event];
}
@end

@interface DYYYSettingsOverlayController : UIViewController
@property(nonatomic, strong) UIViewController *contentController;
@property(nonatomic) CGRect keyboardFrame;
@end

@implementation DYYYSettingsOverlayController
- (CGRect)contentFrame {
    CGRect bounds = self.view.bounds;
    CGFloat top = self.view.safeAreaInsets.top + 8;
    CGRect frame = CGRectMake(bounds.size.width * 0.035, top, bounds.size.width * 0.93, CGRectGetMaxY(bounds) - top);
    if (!CGRectIsEmpty(self.keyboardFrame)) {
        CGRect keyboard = [self.view convertRect:self.keyboardFrame fromView:nil];
        if (CGRectIntersectsRect(frame, keyboard)) {
            frame.size.height = MAX(0, CGRectGetMinY(keyboard) - 12 - frame.origin.y);
        }
    }
#if DEBUG
    if (!CGRectIsEmpty(bounds))
        NSAssert(CGRectContainsRect(bounds, frame), @"设置悬浮容器不能超出显示区域");
#endif
    return frame;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.view.accessibilityViewIsModal = YES;
    [self addChildViewController:self.contentController];
    [self.view addSubview:self.contentController.view];
    [self.contentController didMoveToParentViewController:self];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.contentController.view.frame = self.contentFrame;
}
- (void)keyboardChanged:(NSNotification *)note {
    self.keyboardFrame = [note.name isEqualToString:UIKeyboardWillHideNotification] ? CGRectZero : [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval duration = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions options = [note.userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;
    [UIView animateWithDuration:duration delay:0 options:options | UIViewAnimationOptionBeginFromCurrentState animations:^{
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
        [self.contentController.view layoutIfNeeded];
    } completion:nil];
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
@end

@interface DYYYSettingsTabBarController : UITabBarController
@property(nonatomic, strong) DYYYSettingsRegistry *registry;
@property(nonatomic, strong) UIVisualEffectView *glass;
@end
@implementation DYYYSettingsTabBarController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.glass = [[DYYYGlassBackgroundView alloc] initWithCornerRadius:DYYYSettingsCornerRadius settingsPrefix:@"DYYYSettings"];
    self.glass.userInteractionEnabled = NO;
    self.glass.accessibilityElementsHidden = YES;
    [self.view insertSubview:self.glass atIndex:0];
    UITabBarAppearance *appearance = [self.tabBar.standardAppearance copy];
    appearance.shadowColor = UIColor.clearColor;
    self.tabBar.standardAppearance = appearance;
    if (@available(iOS 15.0, *))
        self.tabBar.scrollEdgeAppearance = appearance;
    self.tabBar.layer.shadowOpacity = 0;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (@available(iOS 26.0, *)) {
        CGRect frame = [self.view convertRect:self.tabBar.bounds fromView:self.tabBar];
        // 底栏可见边缘比主容器两侧各内收 8 点。
        frame.origin.x = CGRectGetMinX(self.view.bounds) - 12;
        frame.size.width = self.view.bounds.size.width + 24;
        CGRect target = [self.tabBar.superview convertRect:frame fromView:self.view];
        if (!CGRectEqualToRect(self.tabBar.frame, target))
            self.tabBar.frame = target;
    }
    CGRect bar = [self.view convertRect:self.tabBar.bounds fromView:self.tabBar];
    CGRect content = self.view.bounds;
    content.size.height = MAX(0, MIN(content.size.height, CGRectGetMinY(bar) - 16));
    if (!CGRectEqualToRect(self.glass.frame, content)) {
        self.glass.frame = content;
        [self.selectedViewController.view setNeedsLayout];
    }
}
- (void)dealloc {
    [self.registry invalidate];
}
@end

@interface DYYYSettingsCoordinator () <UITabBarControllerDelegate>
@property(nonatomic, weak) UITabBarController *settings;
@property(nonatomic, strong) DYYYSettingsWindow *settingsWindow;
@property(nonatomic) BOOL keyboardVisible;
@property(nonatomic) BOOL transferringInputFocus;
@end

@implementation DYYYSettingsCoordinator
+ (instancetype)shared {
    static DYYYSettingsCoordinator *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      instance = [self new];
      [NSNotificationCenter.defaultCenter addObserver:instance selector:@selector(keyboardShown:) name:UIKeyboardWillShowNotification object:nil];
      [NSNotificationCenter.defaultCenter addObserver:instance selector:@selector(keyboardHidden:) name:UIKeyboardWillHideNotification object:nil];
      [NSNotificationCenter.defaultCenter addObserver:instance selector:@selector(textInputEnded:) name:UIKeyboardDidHideNotification object:nil];
    });
    return instance;
}
- (void)keyboardShown:(NSNotification *)note {
    self.keyboardVisible = YES;
}
- (void)keyboardHidden:(NSNotification *)note {
    self.keyboardVisible = NO;
}
- (void)textInputEnded:(NSNotification *)note {
    DYYYSettingsWindow *window = self.settingsWindow;
    window.acceptsTextInput = NO;
    if (window.isKeyWindow)
        [self transferInputFocusToWindow:window.hostWindow];
}
- (void)transferInputFocusToWindow:(UIWindow *)window {
    self.transferringInputFocus = YES;
    [window makeKeyWindow];
    self.transferringInputFocus = NO;
}
+ (BOOL)isSettingsInputFocusNotification:(NSNotification *)notification {
    DYYYSettingsCoordinator *coordinator = [self shared];
    DYYYSettingsWindow *window = coordinator.settingsWindow;
    // 只识别同步焦点交接，不屏蔽应用生命周期或其他窗口的通知。
    return coordinator.transferringInputFocus && window &&
        (notification.object == window || notification.object == window.hostWindow) &&
        ([notification.name isEqualToString:UIWindowDidResignKeyNotification] ||
         [notification.name isEqualToString:UIWindowDidBecomeKeyNotification]);
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
    DYYYSettingsCoordinator *coordinator = [self shared];
    UIViewController *selected = coordinator.settings.selectedViewController;
    if ([selected isKindOfClass:UINavigationController.class])
        return (UINavigationController *)selected;
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
    self.settings = tabs;
    tabs.registry = [DYYYSettingsRegistry current];
    [tabs.registry build];
    [tabs loadViewIfNeeded];
    NSArray *titles = @[ @"播放", @"外观", @"净化", @"关于", @"搜索" ];
    NSArray *symbols = @[ @"play.rectangle", @"paintbrush", @"eye.slash", @"info.circle", @"magnifyingglass" ];
    NSMutableArray *controllers = [NSMutableArray array];
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; i++) {
        DYYYSettingViewController *list = [[DYYYSettingViewController alloc] initWithTab:titles[i]];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:list];
        navigation.additionalSafeAreaInsets = UIEdgeInsetsMake(0, 0, 16, 0);
        UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
        [appearance configureWithTransparentBackground];
        appearance.shadowColor = UIColor.clearColor;
        navigation.navigationBar.standardAppearance = appearance;
        navigation.navigationBar.scrollEdgeAppearance = appearance;
        navigation.navigationBar.compactAppearance = appearance;
        if ([titles[i] isEqualToString:@"搜索"]) {
            [navigation loadViewIfNeeded];
            [list loadViewIfNeeded];
        }
        if (@available(iOS 18.0, *)) {
            if ([titles[i] isEqualToString:@"搜索"]) {
                UISearchTab *search = [[UISearchTab alloc] initWithViewControllerProvider:^UIViewController *(UITab *tab) {
                    return navigation;
                }];
                if (@available(iOS 26.0, *))
                    search.automaticallyActivatesSearch = YES;
                [items addObject:search];
            } else {
                [items addObject:[[UITab alloc] initWithTitle:titles[i]
                                                      image:[UIImage systemImageNamed:symbols[i]]
                                                 identifier:titles[i]
                                     viewControllerProvider:^UIViewController *(UITab *tab) {
                                         return navigation;
                                     }]];
            }
        } else {
            navigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:titles[i] image:[UIImage systemImageNamed:symbols[i]] tag:i];
            [controllers addObject:navigation];
        }
    }
    if (@available(iOS 18.0, *))
        tabs.tabs = items;
    else
        tabs.viewControllers = controllers;
    tabs.delegate = self;
    // 不覆盖 tabBar 材质；iOS 26 的系统 UITabBar 自行提供 Liquid Glass。
    tabs.view.backgroundColor = UIColor.clearColor;
    DYYYSettingsOverlayController *overlay = [DYYYSettingsOverlayController new];
    overlay.contentController = tabs;
    self.settingsWindow = [[DYYYSettingsWindow alloc] initWithWindowScene:window.windowScene];
    self.settingsWindow.hostWindow = window;
    self.settingsWindow.frame = window.bounds;
    self.settingsWindow.windowLevel = window.windowLevel + 1;
    self.settingsWindow.backgroundColor = UIColor.clearColor;
    self.settingsWindow.opaque = NO;
    self.settingsWindow.rootViewController = overlay;
    overlay.view.alpha = 0;
    // 独立窗口隔离宿主布局与手势，普通列表操作保留宿主窗口焦点。
    self.settingsWindow.hidden = NO;
    tabs.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [UIView animateWithDuration:0.2 animations:^{
        overlay.view.alpha = 1;
    } completion:^(__unused BOOL finished) {
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, tabs.view);
        if (![NSUserDefaults.standardUserDefaults boolForKey:@"DYYYUserAgreementAccepted"])
            [DYYYSettingsHelper showUserAgreementAlert];
    }];
}
- (void)tabBarController:(UITabBarController *)controller didSelectViewController:(UIViewController *)viewController {
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
}
- (BOOL)tabBarController:(UITabBarController *)controller shouldSelectTab:(UITab *)tab API_AVAILABLE(ios(18.0)) {
    if ([tab isKindOfClass:UISearchTab.class])
        [self.class prepareForTextInput];
    return YES;
}
+ (void)prepareForTextInput {
    DYYYSettingsCoordinator *coordinator = [self shared];
    DYYYSettingsWindow *window = coordinator.settingsWindow;
    window.acceptsTextInput = YES;
    [coordinator transferInputFocusToWindow:window];
}
+ (void)closeSettings {
    DYYYSettingsCoordinator *coordinator = [self shared];
    DYYYSettingsRegistry *registry = ((DYYYSettingsTabBarController *)coordinator.settings).registry;
    UIViewController *overlay = coordinator.settingsWindow.rootViewController;
    [overlay.view endEditing:YES];
    [UIView animateWithDuration:0.2 animations:^{
        overlay.view.alpha = 0;
    } completion:^(__unused BOOL finished) {
        [registry invalidate];
        BOOL restoreFocus = coordinator.settingsWindow.isKeyWindow;
        UIWindow *hostWindow = coordinator.settingsWindow.hostWindow;
        if (restoreFocus)
            [coordinator transferInputFocusToWindow:hostWindow];
        coordinator.settingsWindow.hidden = YES;
        coordinator.settingsWindow.rootViewController = nil;
        coordinator.settingsWindow = nil;
        coordinator.settings = nil;
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
    }];
}
@end
