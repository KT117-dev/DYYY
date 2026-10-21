//
//  DYYY
//
//  Copyright (c) 2024 huami. All rights reserved.
//  Channel: @huamidev
//  Created on: 2024/10/04
//
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <float.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <syslog.h>

#import "AwemeHeaders.h"
#import "CityManager.h"
#import "DYYYBottomAlertView.h"
#import "DYYYManager.h"

#import "AWMSafeDispatchTimer.h"
#import "DYYYConstants.h"
#import "DYYYFloatClearButton.h"
#import "DYYYFloatSpeedButton.h"
#import "DYYYSettingViewController.h"
#import "DYYYSettingsCoordinator.h"
#import "DYYYToast.h"
#import "DYYYUtils.h"

static BOOL DYYYFullscreenVideoFullscreenOn(void);
static BOOL DYYYFullscreenPreventCommentMovement(void);
static CGRect DYYYFullscreenVideoContainerTargetFrame(UIView *view);
static BOOL DYYYFullscreenRectsClose(CGRect lhs, CGRect rhs);
static BOOL DYYYFullscreenCommentFullPanelOnScreen(void);
static CGRect DYYYFullscreenFeedHUDAdjustFrame(UIView *view, CGRect frame);
static void DYYYFullscreenHUDStatusBarCoverSync(UIViewController *interaction);
static CGFloat DYYYFullscreenHUDStatusBarCoverHeight(UIView *hudView);
static Class DYYYFullscreenVideoFeedTableClass(void);
static UIView *DYYYFullscreenFeedTableForView(UIView *view);
static NSNumber *DYYYFullscreenVideoFeedTableOriginalHeight(UIView *table);
static BOOL DYYYFullscreenVideoFeedTablePrepareForController(UIViewController *controller, UITableView *table);
static CGRect DYYYFullscreenAdjustFrame(UIView *view, CGRect frame);

static CGFloat gStartY = 0.0;
static CGFloat gStartVal = 0.0;
static DYEdgeMode gMode = DYEdgeModeNone;
static __weak UICollectionView *gFeedCV = nil;
static BOOL dyyyVideoMixBarVisibilityHookEnabled = NO;

static const CGFloat kInvalidAlpha = -1.0;
static const CGFloat kInvalidHeight = -1.0;
static CGFloat gGlobalTransparency = kInvalidAlpha;
static CGFloat gCurrentTabBarHeight = kInvalidHeight;
static CGFloat originalTabBarHeight = kInvalidHeight;
static NSString *const kDYYYGlobalTransparencyKey = @"DYYYGlobalTransparency";
static NSString *const kDYYYGlobalTransparencyDidChangeNotification = @"DYYYGlobalTransparencyDidChangeNotification";
static char kDYYYGlobalTransparencyBaseAlphaKey;
static NSInteger dyyyGlobalTransparencyMutationDepth = 0;

static void updateGlobalTransparencyCache() {
    NSString *transparentValue = DYYYGetString(kDYYYGlobalTransparencyKey);
    if (transparentValue.length > 0) {
        float alphaValue;
        NSScanner *scanner = [NSScanner scannerWithString:transparentValue];
        if ([scanner scanFloat:&alphaValue] && scanner.isAtEnd) {
            gGlobalTransparency = MIN(MAX(alphaValue, 0.0), 1.0);
            return;
        }
    }
    gGlobalTransparency = kInvalidAlpha;
}

static NSDictionary<NSString *, NSString *> *DYYYTopTabTitleMapping(void) {
    static NSString *cachedRawValue = nil;
    static NSDictionary<NSString *, NSString *> *cachedMapping = nil;

    NSString *currentValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYModifyTopTabText"];
    BOOL rawValueChanged = (cachedRawValue != currentValue) && ![cachedRawValue isEqualToString:currentValue];

    if (!rawValueChanged) {
        return cachedMapping;
    }

    cachedRawValue = [currentValue copy];

    if (currentValue.length == 0) {
        cachedMapping = nil;
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *mapping = [NSMutableDictionary dictionary];
    NSArray<NSString *> *titlePairs = [currentValue componentsSeparatedByString:@"#"];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    for (NSString *pair in titlePairs) {
        NSArray<NSString *> *components = [pair componentsSeparatedByString:@"="];
        if (components.count != 2) {
            continue;
        }

        NSString *originalTitle = [components[0] stringByTrimmingCharactersInSet:whitespace];
        NSString *newTitle = [components[1] stringByTrimmingCharactersInSet:whitespace];

        if (originalTitle.length == 0 || newTitle.length == 0) {
            continue;
        }

        mapping[originalTitle] = newTitle;
    }

    cachedMapping = mapping.count > 0 ? [mapping copy] : nil;
    return cachedMapping;
}

static NSString *DYYYCustomAssetsDirectory(void) {
    static NSString *customDirectory = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
      NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
      customDirectory = [documentsPath stringByAppendingPathComponent:@"DYYY"];
      [[NSFileManager defaultManager] createDirectoryAtPath:customDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    });

    return customDirectory;
}

static NSString *DYYYCustomIconFileNameForButtonName(NSString *nameString) {
    if (nameString.length == 0) {
        return nil;
    }

    static NSDictionary<NSString *, NSString *> *prefixMapping = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      prefixMapping = @{
          @"icon_home_like_after" : @"like_after.png",
          @"icon_home_like_before" : @"like_before.png",
          @"icon_home_comment" : @"comment.png",
          @"icon_home_unfavorite" : @"unfavorite.png",
          @"icon_home_favorite" : @"favorite.png",
          @"iconHomeShareRight" : @"share.png"
      };
    });

    for (NSString *prefix in prefixMapping) {
        if ([nameString hasPrefix:prefix]) {
            return prefixMapping[prefix];
        }
    }

    if ([nameString containsString:@"_comment"]) {
        return @"comment.png";
    }
    if ([nameString containsString:@"_like"]) {
        BOOL isLikedState = [nameString containsString:@"_after"] || [nameString containsString:@"_liked"];
        return isLikedState ? @"like_after.png" : @"like_before.png";
    }
    if ([nameString containsString:@"_collect"]) {
        return @"unfavorite.png";
    }
    if ([nameString containsString:@"_share"]) {
        return @"share.png";
    }

    return nil;
}

static UIImage *DYYYLoadCustomImage(NSString *fileName, CGSize targetSize) {
    if (fileName.length == 0) {
        return nil;
    }

    static NSCache<NSString *, UIImage *> *imageCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      imageCache = [[NSCache alloc] init];
      imageCache.name = @"com.dyyy.customIcons.cache";
    });

    NSString *cacheKey = (targetSize.width > 0.0 && targetSize.height > 0.0) ? [NSString stringWithFormat:@"%@_%0.1f_%0.1f", fileName, targetSize.width, targetSize.height] : fileName;

    UIImage *cachedImage = [imageCache objectForKey:cacheKey];
    if (cachedImage) {
        return cachedImage;
    }

    NSString *fullPath = [DYYYCustomAssetsDirectory() stringByAppendingPathComponent:fileName];
    UIImage *sourceImage = [UIImage imageWithContentsOfFile:fullPath];
    if (!sourceImage) {
        return nil;
    }

    if (targetSize.width <= 0.0 || targetSize.height <= 0.0) {
        [imageCache setObject:sourceImage forKey:cacheKey];
        return sourceImage;
    }

    CGSize originalSize = sourceImage.size;
    if (originalSize.width <= 0.0 || originalSize.height <= 0.0) {
        return sourceImage;
    }

    CGFloat widthScale = targetSize.width / originalSize.width;
    CGFloat heightScale = targetSize.height / originalSize.height;
    CGFloat scale = fmin(widthScale, heightScale);

    if (fabs(1.0 - scale) <= FLT_EPSILON) {
        [imageCache setObject:sourceImage forKey:cacheKey];
        return sourceImage;
    }

    CGSize newSize = CGSizeMake(originalSize.width * scale, originalSize.height * scale);
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 0.0);
    [sourceImage drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    UIImage *resultImage = resizedImage ?: sourceImage;
    [imageCache setObject:resultImage forKey:cacheKey];
    return resultImage;
}

static BOOL DYYYShouldHandleSpeedFeatures(void) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableFloatSpeedButton"]) {
        return YES;
    }

    float defaultSpeed = [[NSUserDefaults standardUserDefaults] floatForKey:@"DYYYDefaultSpeed"];
    if (defaultSpeed <= 0.0f) {
        return NO;
    }

    return fabsf(defaultSpeed - 1.0f) > FLT_EPSILON;
}

static __weak AWEPlayInteractionViewController *dyyyActiveSpeedInteractionController = nil;
static __weak AWEAwemeModel *dyyyCurrentSpeedAweme = nil;
static NSString *dyyyLastAutoRestoredSpeedAwemeIdentifier = nil;
static BOOL dyyyLongPressFastSpeedActive = NO;
static BOOL dyyyLongPressLockedSpeedActive = NO;

static void DYYYClearLongPressSpeedState(void) {
    dyyyLongPressFastSpeedActive = NO;
    dyyyLongPressLockedSpeedActive = NO;
}

static CGFloat DYYYViewControllerVisibilityScore(UIViewController *viewController) {
    if (!viewController || !viewController.isViewLoaded) {
        return -1.0;
    }

    UIView *view = viewController.view;
    UIWindow *window = view.window;
    if (!window || view.hidden || view.alpha <= 0.01 || CGRectIsEmpty(view.bounds)) {
        return -1.0;
    }

    CGRect frameInWindow = [view convertRect:view.bounds toView:window];
    CGRect visibleFrame = CGRectIntersection(frameInWindow, window.bounds);
    if (CGRectIsNull(visibleFrame) || CGRectIsEmpty(visibleFrame)) {
        return -1.0;
    }

    CGFloat visibleArea = CGRectGetWidth(visibleFrame) * CGRectGetHeight(visibleFrame);
    CGFloat totalArea = CGRectGetWidth(frameInWindow) * CGRectGetHeight(frameInWindow);
    CGFloat visibleRatio = totalArea > 0.0 ? visibleArea / totalArea : 0.0;
    CGPoint windowCenter = CGPointMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds));
    CGFloat centerBonus = CGRectContainsPoint(visibleFrame, windowCenter) ? 1000000000.0 : 0.0;
    return centerBonus + visibleRatio * 1000000.0 + visibleArea;
}

static BOOL DYYYAwemeModelsMatch(AWEAwemeModel *lhs, AWEAwemeModel *rhs) {
    if (!lhs || !rhs) {
        return NO;
    }
    if (lhs == rhs) {
        return YES;
    }

    NSString *lhsItemID = lhs.itemID;
    NSString *rhsItemID = rhs.itemID;
    return lhsItemID.length > 0 && rhsItemID.length > 0 && [lhsItemID isEqualToString:rhsItemID];
}

static NSString *DYYYSpeedAwemeIdentifier(AWEAwemeModel *aweme) {
    if (!aweme) {
        return nil;
    }
    if (aweme.itemID.length > 0) {
        return aweme.itemID;
    }
    return [NSString stringWithFormat:@"%p", aweme];
}

static AWEAwemeModel *DYYYSpeedAwemeFromObject(id object) {
    Class awemeClass = NSClassFromString(@"AWEAwemeModel");
    if (!object || !awemeClass) {
        return nil;
    }
    if ([object isKindOfClass:awemeClass]) {
        return (AWEAwemeModel *)object;
    }

    for (NSString *key in @[ @"model", @"awemeModel", @"currentAweme" ]) {
        @try {
            id value = [object valueForKey:key];
            if ([value isKindOfClass:awemeClass]) {
                return (AWEAwemeModel *)value;
            }
        } @catch (NSException *exception) {
        }
    }
    return nil;
}

static double DYYYDefaultPlaybackSpeed(void) {
    double defaultSpeed = [[NSUserDefaults standardUserDefaults] doubleForKey:@"DYYYDefaultSpeed"];
    if (isfinite(defaultSpeed) && defaultSpeed > 0.0) {
        return defaultSpeed;
    }
    return 1.0;
}

static void DYYYRestoreFloatSpeedButtonForAwemeIfNeeded(AWEAwemeModel *aweme) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL shouldAutoRestore = [defaults boolForKey:@"DYYYEnableFloatSpeedButton"] && [defaults boolForKey:@"DYYYAutoRestoreSpeed"];
    if (!shouldAutoRestore) {
        dyyyLastAutoRestoredSpeedAwemeIdentifier = nil;
        return;
    }

    NSString *awemeIdentifier = DYYYSpeedAwemeIdentifier(aweme);
    if (awemeIdentifier.length == 0 || [awemeIdentifier isEqualToString:dyyyLastAutoRestoredSpeedAwemeIdentifier]) {
        return;
    }

    dyyyLastAutoRestoredSpeedAwemeIdentifier = [awemeIdentifier copy];
    if (!setCurrentSpeedValue((float)DYYYDefaultPlaybackSpeed())) {
        setCurrentSpeedIndex(0);
    }
    updateSpeedButtonUI();
}

static NSArray<AWEPlayInteractionViewController *> *DYYYSpeedInteractionControllers(AWEPlayInteractionViewController *preferredController) {
    NSMutableArray<AWEPlayInteractionViewController *> *controllers = [NSMutableArray array];
    Class interactionControllerClass = NSClassFromString(@"AWEPlayInteractionViewController");
    UIWindow *window = [DYYYUtils getActiveWindow];
    UIViewController *rootViewController = window.rootViewController;
    while (rootViewController.presentedViewController) {
        rootViewController = rootViewController.presentedViewController;
    }

    for (UIViewController *viewController in rootViewController ? findViewControllersInHierarchy(rootViewController) : @[]) {
        if (interactionControllerClass && [viewController isKindOfClass:interactionControllerClass]) {
            [controllers addObject:(AWEPlayInteractionViewController *)viewController];
        }
    }

    if (preferredController && ![controllers containsObject:preferredController]) {
        [controllers addObject:preferredController];
    }
    return controllers;
}

static AWEPlayInteractionViewController *DYYYResolveSpeedInteractionController(AWEPlayInteractionViewController *preferredController, AWEAwemeModel *targetAweme, BOOL allowVisibleFallback) {
    AWEPlayInteractionViewController *bestModelMatch = nil;
    AWEPlayInteractionViewController *bestVisibleController = nil;
    CGFloat bestModelMatchScore = -1.0;
    CGFloat bestVisibleScore = -1.0;

    for (AWEPlayInteractionViewController *controller in DYYYSpeedInteractionControllers(preferredController)) {
        CGFloat visibilityScore = DYYYViewControllerVisibilityScore(controller);
        if (visibilityScore < 0.0) {
            continue;
        }

        if (visibilityScore > bestVisibleScore) {
            bestVisibleScore = visibilityScore;
            bestVisibleController = controller;
        }
        if (targetAweme && DYYYAwemeModelsMatch(controller.model, targetAweme) && visibilityScore > bestModelMatchScore) {
            bestModelMatchScore = visibilityScore;
            bestModelMatch = controller;
        }
    }

    return bestModelMatch ?: (allowVisibleFallback ? bestVisibleController : nil);
}

static AWEPlayInteractionViewController *DYYYResolveCurrentSpeedInteractionController(AWEPlayInteractionViewController *preferredController) {
    return DYYYResolveSpeedInteractionController(preferredController, dyyyCurrentSpeedAweme, YES);
}

id DYYYCurrentSpeedInteractionController(void) {
    return DYYYResolveCurrentSpeedInteractionController(dyyyActiveSpeedInteractionController);
}

static void DYYYEnsureFloatSpeedButton(AWEPlayInteractionViewController *interactionController) {
    [FloatingSpeedButton reloadConfiguration];
    AWEAwemeModel *targetAweme = dyyyCurrentSpeedAweme;
    BOOL allowVisibleFallback = !targetAweme || (interactionController && DYYYAwemeModelsMatch(interactionController.model, targetAweme));
    AWEPlayInteractionViewController *currentController = DYYYResolveSpeedInteractionController(interactionController, targetAweme, allowVisibleFallback);
    if (!currentController) {
        updateSpeedButtonVisibility();
        return;
    }

    if ((dyyyLongPressFastSpeedActive || dyyyLongPressLockedSpeedActive) &&
        currentController.model &&
        !DYYYAwemeModelsMatch(dyyyCurrentSpeedAweme, currentController.model)) {
        DYYYClearLongPressSpeedState();
    }

    dyyyActiveSpeedInteractionController = currentController;
    dyyyCurrentSpeedAweme = currentController.model;
    dyyyInteractionViewVisible = YES;

    if (!isFloatSpeedButtonEnabled) {
        updateSpeedButtonVisibility();
        return;
    }

    UIWindow *keyWindow = [DYYYUtils getActiveWindow];
    if (!keyWindow) {
        return;
    }

    DYYYRestoreFloatSpeedButtonForAwemeIfNeeded(currentController.model);

    if (!speedButton) {
        CGRect windowBounds = keyWindow.bounds;
        CGRect initialFrame = CGRectMake((windowBounds.size.width - speedButtonSize) / 2.0, (windowBounds.size.height - speedButtonSize) / 2.0, speedButtonSize, speedButtonSize);
        speedButton = [[FloatingSpeedButton alloc] initWithFrame:initialFrame];
        speedButton.interactionController = currentController;
        updateSpeedButtonUI();
    } else if (speedButton.interactionController != currentController) {
        speedButton.interactionController = currentController;
        [speedButton resetButtonState];
    }

    if (![speedButton isDescendantOfView:keyWindow]) {
        [keyWindow addSubview:speedButton];
        [speedButton loadSavedPosition];
        [speedButton resetFadeTimer];
    }

    [keyWindow bringSubviewToFront:speedButton];
    updateSpeedButtonVisibility();
}

// 提供给跨文件调用的刷新入口：根据当前可见 PlayInteractionVC 重新评估并恢复倍速按钮，
// 用于清屏退出等场景，避免清屏期间 viewDidDisappear 把 dyyyInteractionViewVisible 置 NO 后状态卡住。
void DYYYRefreshFloatSpeedButton(void) {
    void (^applyBlock)(void) = ^{
        AWEPlayInteractionViewController *currentController = (AWEPlayInteractionViewController *)DYYYCurrentSpeedInteractionController();
        DYYYEnsureFloatSpeedButton(currentController);
    };
    if ([NSThread isMainThread]) {
        applyBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), applyBlock);
    }
}

static BOOL DYYYSetPlaybackRateOnTarget(id target, double speed) {
    if (!target || ![target respondsToSelector:@selector(setVideoControllerPlaybackRate:)]) {
        return NO;
    }

    @try {
        [(AWEAwemePlayVideoViewController *)target setVideoControllerPlaybackRate:speed];
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

static BOOL DYYYApplyPlaybackSpeed(AWEPlayInteractionViewController *interactionController, double speed) {
    interactionController = DYYYResolveCurrentSpeedInteractionController(interactionController);
    if (!interactionController) {
        return NO;
    }

    Protocol *speedControllerProtocol = NSProtocolFromString(@"AWEFastSpeedControllerProtocol");
    if (speedControllerProtocol && [interactionController respondsToSelector:@selector(controllerByProtocol:)]) {
        @try {
            id speedController = [interactionController controllerByProtocol:speedControllerProtocol];
            if ([speedController respondsToSelector:@selector(playVideoViewController)]) {
                id playVideoViewController = [(AWEPlayInteractionSpeedController *)speedController playVideoViewController];
                if (DYYYSetPlaybackRateOnTarget(playVideoViewController, speed)) {
                    return YES;
                }
            }
        } @catch (NSException *exception) {
        }
    }

    if ([interactionController respondsToSelector:@selector(videoDelegate)] && DYYYSetPlaybackRateOnTarget([interactionController videoDelegate], speed)) {
        return YES;
    }

    UIWindow *window = [DYYYUtils getActiveWindow];
    UIViewController *rootViewController = window.rootViewController;
    while (rootViewController.presentedViewController) {
        rootViewController = rootViewController.presentedViewController;
    }

    UIViewController *bestPlayerViewController = nil;
    CGFloat bestPlayerVisibilityScore = -1.0;
    for (UIViewController *viewController in rootViewController ? findViewControllersInHierarchy(rootViewController) : @[]) {
        if ([viewController isKindOfClass:NSClassFromString(@"AWEAwemePlayVideoViewController")] ||
            [viewController isKindOfClass:NSClassFromString(@"AWEDPlayerFeedPlayerViewController")] ||
            [viewController isKindOfClass:NSClassFromString(@"AWEDPlayerViewController_Merge")]) {
            CGFloat visibilityScore = DYYYViewControllerVisibilityScore(viewController);
            if (visibilityScore > bestPlayerVisibilityScore) {
                bestPlayerVisibilityScore = visibilityScore;
                bestPlayerViewController = viewController;
            }
        }
    }

    return DYYYSetPlaybackRateOnTarget(bestPlayerViewController, speed);
}

static double DYYYConfiguredPlaybackSpeed(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"DYYYEnableFloatSpeedButton"]) {
        return getCurrentSpeed();
    }

    if ([defaults boolForKey:@"DYYYUserAgreementAccepted"]) {
        return DYYYDefaultPlaybackSpeed();
    }
    return 1.0;
}

static BOOL DYYYShouldPrepareDefaultPlaybackSpeedForPlayer(id playerViewController) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"DYYYEnableFloatSpeedButton"] || ![defaults boolForKey:@"DYYYAutoRestoreSpeed"]) {
        return NO;
    }

    AWEAwemeModel *targetAweme = DYYYSpeedAwemeFromObject(playerViewController) ?: dyyyCurrentSpeedAweme;
    NSString *awemeIdentifier = DYYYSpeedAwemeIdentifier(targetAweme);
    return awemeIdentifier.length > 0 && ![awemeIdentifier isEqualToString:dyyyLastAutoRestoredSpeedAwemeIdentifier];
}

static double DYYYPreparedPlaybackSpeedForPlayer(id playerViewController) {
    // Auto-restore belongs to aweme transitions; current-video refreshes should keep the selected quick speed.
    if (DYYYShouldPrepareDefaultPlaybackSpeedForPlayer(playerViewController)) {
        return DYYYDefaultPlaybackSpeed();
    }
    return DYYYConfiguredPlaybackSpeed();
}

static void DYYYApplyPreparedPlaybackSpeedToPlayer(id playerViewController) {
    if (!DYYYShouldHandleSpeedFeatures() || !playerViewController || dyyyLongPressFastSpeedActive || dyyyLongPressLockedSpeedActive) {
        return;
    }

    double speed = DYYYPreparedPlaybackSpeedForPlayer(playerViewController);
    void (^applyBlock)(void) = ^{
      DYYYSetPlaybackRateOnTarget(playerViewController, speed);
    };
    if ([NSThread isMainThread]) {
        applyBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), applyBlock);
    }
}

static void DYYYBindAndApplyCurrentPlaybackSpeed(void) {
    if (!DYYYShouldHandleSpeedFeatures() || dyyyLongPressFastSpeedActive || dyyyLongPressLockedSpeedActive) {
        return;
    }

    AWEAwemeModel *targetAweme = dyyyCurrentSpeedAweme;
    AWEPlayInteractionViewController *currentController = DYYYResolveSpeedInteractionController(nil, targetAweme, targetAweme == nil);
    if (!currentController) {
        return;
    }

    DYYYEnsureFloatSpeedButton(currentController);
    DYYYApplyPlaybackSpeed(currentController, DYYYConfiguredPlaybackSpeed());
}

static void DYYYScheduleConfiguredPlaybackSpeedRestoreAfterDelay(NSTimeInterval delay) {
    dispatch_block_t restoreBlock = ^{
      DYYYBindAndApplyCurrentPlaybackSpeed();
    };
    if (delay <= 0.0) {
        dispatch_async(dispatch_get_main_queue(), restoreBlock);
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), restoreBlock);
    }
}

static void DYYYScheduleConfiguredPlaybackSpeedRestore(void) {
    DYYYScheduleConfiguredPlaybackSpeedRestoreAfterDelay(0.0);
    DYYYScheduleConfiguredPlaybackSpeedRestoreAfterDelay(0.2);
}

static void DYYYEndLockedLongPressSpeedAndRestoreIfNeeded(void) {
    if (!dyyyLongPressLockedSpeedActive) {
        return;
    }
    dyyyLongPressLockedSpeedActive = NO;
    DYYYScheduleConfiguredPlaybackSpeedRestore();
}

static void DYYYHandleCurrentSpeedAwemeChanged(id aweme) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          DYYYHandleCurrentSpeedAwemeChanged(aweme);
        });
        return;
    }

    Class awemeClass = NSClassFromString(@"AWEAwemeModel");
    if (awemeClass && [aweme isKindOfClass:awemeClass]) {
        dyyyCurrentSpeedAweme = (AWEAwemeModel *)aweme;
    }
    if (!DYYYShouldHandleSpeedFeatures()) {
        return;
    }

    DYYYClearLongPressSpeedState();
    DYYYRestoreFloatSpeedButtonForAwemeIfNeeded(dyyyCurrentSpeedAweme);

    DYYYBindAndApplyCurrentPlaybackSpeed();
    DYYYScheduleConfiguredPlaybackSpeedRestore();
}

@interface AWEFeedProgressSlider (DYYYProgressLabel)
- (NSString *)dyyy_formatTimeFromSeconds:(CGFloat)seconds;
- (CGFloat)dyyy_modelDurationInSeconds;
- (CGFloat)dyyy_scheduleVerticalOffset;
- (void)dyyy_removeScheduleLabels;
- (void)dyyy_updateScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration;
@end

@interface AWEPlayInteractionProgressController (DYYYProgressLabel)
- (void)dyyy_syncScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration;
@end

@interface AWEDProgressCoreContainer (DYYYProgressLabel)
- (void)dyyy_syncScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration;
@end

@interface UIView (DYYYProgressLabelLegacy)
- (void)dyyy_updateScheduleLabelsLegacyWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration model:(id)model;
@end

@implementation UIView (DYYYProgressLabelLegacy)

- (NSString *)dyyy_legacyFormatTimeFromSeconds:(CGFloat)seconds {
    CGFloat safeSeconds = seconds;
    if (safeSeconds < 0) {
        safeSeconds = 0;
    }

    NSInteger total = (NSInteger)floor(safeSeconds);
    NSInteger hours = total / 3600;
    NSInteger minutes = (total % 3600) / 60;
    NSInteger secs = total % 60;

    if (hours > 0) {
        return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)hours, (long)minutes, (long)secs];
    }
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)secs];
}

- (CGFloat)dyyy_legacyScheduleVerticalOffset {
    CGFloat verticalOffset = -12.5;
    NSString *offsetValueString = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYTimelineVerticalPosition"];
    if (offsetValueString.length > 0) {
        CGFloat configuredOffset = [offsetValueString floatValue];
        if (configuredOffset != 0) {
            verticalOffset = configuredOffset;
        }
    }
    return verticalOffset;
}

- (CGFloat)dyyy_legacyModelDurationInSeconds:(id)model {
    if (!model || ![model respondsToSelector:@selector(videoDuration)]) {
        return 0;
    }

    CGFloat videoDurationMs = [[model valueForKey:@"videoDuration"] doubleValue];
    if (videoDurationMs <= 0) {
        return 0;
    }
    return videoDurationMs / 1000.0;
}

- (void)dyyy_updateScheduleLabelsLegacyWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration model:(id)model {
    if (!DYYYGetBool(@"DYYYShowScheduleDisplay")) {
        UIView *parentView = self.superview;
        if (parentView) {
            [[parentView viewWithTag:10001] removeFromSuperview];
            [[parentView viewWithTag:10002] removeFromSuperview];
        }
        return;
    }

    if (![NSThread isMainThread]) {
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
          [weakSelf dyyy_updateScheduleLabelsLegacyWithCurrentTime:currentTime totalDuration:totalDuration model:model];
        });
        return;
    }

    UIView *parentView = self.superview;
    if (!parentView) {
        return;
    }
    [parentView layoutIfNeeded];
    [self layoutIfNeeded];

    NSString *scheduleStyle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYScheduleStyle"];
    BOOL showRightRemainingTime = [scheduleStyle isEqualToString:@"进度条右侧剩余"];
    BOOL showRightCompleteTime = [scheduleStyle isEqualToString:@"进度条右侧完整"];
    BOOL showLeftRemainingTime = [scheduleStyle isEqualToString:@"进度条左侧剩余"];
    BOOL showLeftCompleteTime = [scheduleStyle isEqualToString:@"进度条左侧完整"];

    BOOL shouldShowLeftLabel = !showRightRemainingTime && !showRightCompleteTime;
    BOOL shouldShowRightLabel = !showLeftRemainingTime && !showLeftCompleteTime;

    CGFloat modelDuration = [self dyyy_legacyModelDurationInSeconds:model];
    CGFloat effectiveTotalDuration = totalDuration > 0 ? totalDuration : modelDuration;
    if (effectiveTotalDuration < 0) {
        effectiveTotalDuration = 0;
    }

    CGFloat effectiveCurrentTime = currentTime;
    if (effectiveCurrentTime < 0) {
        effectiveCurrentTime = 0;
    }
    if (effectiveTotalDuration > 0 && effectiveCurrentTime > effectiveTotalDuration) {
        effectiveCurrentTime = effectiveTotalDuration;
    }

    CGRect sliderFrameInParent = [self convertRect:self.bounds toView:parentView];
    if (CGRectGetWidth(sliderFrameInParent) <= 1.0 || CGRectGetHeight(sliderFrameInParent) <= 1.0) {
        return;
    }
    CGFloat labelYPosition = CGRectGetMinY(sliderFrameInParent) + [self dyyy_legacyScheduleVerticalOffset];
    CGFloat labelHeight = 15.0;
    UIFont *labelFont = [UIFont systemFontOfSize:8];
    NSString *labelColorHex = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYProgressLabelColor"];

    UILabel *leftLabel = (UILabel *)[parentView viewWithTag:10001];
    if (leftLabel && ![leftLabel isKindOfClass:[UILabel class]]) {
        [leftLabel removeFromSuperview];
        leftLabel = nil;
    }

    if (shouldShowLeftLabel) {
        if (!leftLabel) {
            leftLabel = [[UILabel alloc] init];
            leftLabel.backgroundColor = [UIColor clearColor];
            leftLabel.tag = 10001;
            [parentView addSubview:leftLabel];
        }
        leftLabel.font = labelFont;

        NSString *newLeftText = nil;
        if (showLeftRemainingTime) {
            newLeftText = [self dyyy_legacyFormatTimeFromSeconds:MAX(effectiveTotalDuration - effectiveCurrentTime, 0)];
        } else if (showLeftCompleteTime) {
            newLeftText = [NSString stringWithFormat:@"%@/%@", [self dyyy_legacyFormatTimeFromSeconds:effectiveCurrentTime], [self dyyy_legacyFormatTimeFromSeconds:effectiveTotalDuration]];
        } else {
            newLeftText = [self dyyy_legacyFormatTimeFromSeconds:effectiveCurrentTime];
        }

        if (![leftLabel.text isEqualToString:newLeftText]) {
            leftLabel.text = newLeftText;
        }
        [leftLabel sizeToFit];
        leftLabel.frame = CGRectMake(CGRectGetMinX(sliderFrameInParent), labelYPosition, CGRectGetWidth(leftLabel.bounds), labelHeight);
        [DYYYUtils applyColorSettingsToLabel:leftLabel colorHexString:labelColorHex];
    } else {
        [leftLabel removeFromSuperview];
    }

    UILabel *rightLabel = (UILabel *)[parentView viewWithTag:10002];
    if (rightLabel && ![rightLabel isKindOfClass:[UILabel class]]) {
        [rightLabel removeFromSuperview];
        rightLabel = nil;
    }

    if (shouldShowRightLabel) {
        if (!rightLabel) {
            rightLabel = [[UILabel alloc] init];
            rightLabel.backgroundColor = [UIColor clearColor];
            rightLabel.tag = 10002;
            [parentView addSubview:rightLabel];
        }
        rightLabel.font = labelFont;

        NSString *newRightText = nil;
        if (showRightRemainingTime) {
            newRightText = [self dyyy_legacyFormatTimeFromSeconds:MAX(effectiveTotalDuration - effectiveCurrentTime, 0)];
        } else if (showRightCompleteTime) {
            newRightText = [NSString stringWithFormat:@"%@/%@", [self dyyy_legacyFormatTimeFromSeconds:effectiveCurrentTime], [self dyyy_legacyFormatTimeFromSeconds:effectiveTotalDuration]];
        } else {
            newRightText = [self dyyy_legacyFormatTimeFromSeconds:effectiveTotalDuration];
        }

        if (![rightLabel.text isEqualToString:newRightText]) {
            rightLabel.text = newRightText;
        }
        [rightLabel sizeToFit];
        CGFloat rightLabelX = MAX(CGRectGetMaxX(sliderFrameInParent) - CGRectGetWidth(rightLabel.bounds), CGRectGetMinX(sliderFrameInParent));
        rightLabel.frame = CGRectMake(rightLabelX, labelYPosition, CGRectGetWidth(rightLabel.bounds), labelHeight);
        [DYYYUtils applyColorSettingsToLabel:rightLabel colorHexString:labelColorHex];
    } else {
        [rightLabel removeFromSuperview];
    }
}

@end

// 关闭不可见水印
%hook AWEHPChannelInvisibleWaterMarkModel

- (BOOL)isEnter {
    return NO;
}

- (BOOL)isAppear {
    return NO;
}

%end

// 长按复制个人简介
%hook AWEProfileMentionLabel

- (void)layoutSubviews {
    %orig;

    if (!DYYYGetBool(@"DYYYBioCopyText")) {
        return;
    }

    BOOL hasLongPressGesture = NO;
    for (UIGestureRecognizer *gesture in self.gestureRecognizers) {
        if ([gesture isKindOfClass:[UILongPressGestureRecognizer class]]) {
            hasLongPressGesture = YES;
            break;
        }
    }

    if (!hasLongPressGesture) {
        UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        longPressGesture.minimumPressDuration = 0.5;
        [self addGestureRecognizer:longPressGesture];
        self.userInteractionEnabled = YES;
    }
}

%new
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        NSString *bioText = self.text;
        if (bioText && bioText.length > 0) {
            [[UIPasteboard generalPasteboard] setString:bioText];
            [DYYYToast showSuccessToastWithMessage:@"个人简介已复制"];
        }
    }
}

%end

// 抖音 39.1.0 访问他人主页时会由详情组件直接上传访客记录
%hook AWEProfileUserDetailComponent

- (void)reportUserDetailVisitIfNeeded:(id)user {
    if (DYYYGetBool(@"DYYYDisableProfileVisitRecordUpload")) {
        return;
    }

    %orig;
}

%end

// 兼容旧版访客记录上传路径
%hook AWEProfileRecordHelper

+ (void)postProfileRecordWithParams:(id)params completionBlock:(id)completionBlock {
    if (DYYYGetBool(@"DYYYDisableProfileVisitRecordUpload")) {
        return;
    }

    %orig;
}

%end

@interface AWENowPlayingInfoCenter : NSObject
@property(nonatomic, weak) id playingPlayer;
@end

@interface MPNowPlayingInfoCenter : NSObject
@property(nonatomic, copy) NSDictionary *nowPlayingInfo;
+ (instancetype)defaultCenter;
@end

static BOOL dyyyClearingFeedNowPlayingSystemInfo = NO;
static CFTimeInterval dyyyLastFeedNowPlayingSystemClearTime = 0.0;

static void DYYYClearFeedNowPlayingSystemInfoThrottled(void) {
    if (!DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo") || dyyyClearingFeedNowPlayingSystemInfo) {
        return;
    }

    CFTimeInterval currentTime = CFAbsoluteTimeGetCurrent();
    if (currentTime - dyyyLastFeedNowPlayingSystemClearTime < 0.25) {
        return;
    }
    dyyyLastFeedNowPlayingSystemClearTime = currentTime;

    Class nowPlayingInfoCenterClass = NSClassFromString(@"MPNowPlayingInfoCenter");
    if (!nowPlayingInfoCenterClass || ![nowPlayingInfoCenterClass respondsToSelector:@selector(defaultCenter)]) {
        return;
    }

    id center = ((id (*)(Class, SEL))objc_msgSend)(nowPlayingInfoCenterClass, @selector(defaultCenter));
    if (!center) {
        return;
    }

    dyyyClearingFeedNowPlayingSystemInfo = YES;
    @try {
        if ([center respondsToSelector:@selector(setNowPlayingInfo:)]) {
            ((void (*)(id, SEL, id))objc_msgSend)(center, @selector(setNowPlayingInfo:), nil);
        }

        SEL setPlaybackStateSelector = NSSelectorFromString(@"setPlaybackState:");
        if ([center respondsToSelector:setPlaybackStateSelector]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(center, setPlaybackStateSelector, 0);
        }
    } @catch (__unused NSException *exception) {
    } @finally {
        dyyyClearingFeedNowPlayingSystemInfo = NO;
    }
}

static BOOL DYYYShouldBlockFeedNowPlayingSystemInfoWrite(void) {
    return DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo") && !dyyyClearingFeedNowPlayingSystemInfo;
}

%hook AWEAwemeBackgroundPlayModule

- (id)nowPlayingInfo {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return nil;
    }

    return %orig;
}

- (void)refreshNowPlayingInfoIfNeeded {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

- (void)updateNowPlayingInfoPlayback {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

%end

%hook AWEFeedBackgroundPlayManager

- (id)nowPlayingInfo {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return nil;
    }

    return %orig;
}

- (void)setNowPlayingInfo:(id)nowPlayingInfo {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

- (void)resetNowPlayingInfo:(id)model {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

- (void)refreshNowPlayingInfo {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

- (void)refreshNowPlayingInfoIsForce:(BOOL)isForce {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

- (void)updateNowPlayingInfoPlayback {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

%end

// 采用 HideNowPlayingInfo 的强屏蔽思路：播放中心写入时直接清空系统 Now Playing，不再走原实现。
%hook AWENowPlayingInfoCenter

- (void)becomePlayingPlayer:(id)player {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

- (void)setNowPlayingInfo:(id)nowPlayingInfo {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

- (void)refreshNowPlayingInfo {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

%end

// 耳机或系统媒体会话可能绕过抖音播放中心，最终都要写入 MPNowPlayingInfoCenter。
%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)nowPlayingInfo {
    if (DYYYShouldBlockFeedNowPlayingSystemInfoWrite()) {
        %orig(nil);
        return;
    }

    %orig;
}

- (void)setPlaybackState:(NSInteger)playbackState {
    if (DYYYShouldBlockFeedNowPlayingSystemInfoWrite()) {
        %orig(0);
        return;
    }

    %orig;
}

%end

static BOOL DYYYShouldDisableAllHDR(void);
static NSArray *DYYYFilteredSDRBitrateModels(NSArray *models);
static NSArray *DYYYFilteredSDRRawBitrateData(NSArray *rawData);
static void DYYYStripHDRHintsFromBitrateModels(NSArray *models);

// 默认视频流最高画质
%hook AWEVideoModel

- (AWEURLModel *)playURL {
    if (!DYYYGetBool(@"DYYYEnableVideoHighestQuality")) {
        return %orig;
    }

    // 获取比特率模型数组
    NSArray *bitrateModels = [self bitrateModels];
    if (!bitrateModels || bitrateModels.count == 0) {
        return %orig;
    }

    // 查找比特率最高的模型
    id highestBitrateModel = nil;
    NSInteger highestBitrate = 0;

    for (id model in bitrateModels) {
        NSInteger bitrate = 0;
        BOOL validModel = NO;

        if ([model isKindOfClass:NSClassFromString(@"AWEVideoBSModel")]) {
            id bitrateValue = [model bitrate];
            if (bitrateValue) {
                bitrate = [bitrateValue integerValue];
                validModel = YES;
            }
        }

        if (validModel && bitrate > highestBitrate) {
            highestBitrate = bitrate;
            highestBitrateModel = model;
        }
    }

    // 如果找到了最高比特率模型，获取其播放地址
    if (highestBitrateModel) {
        id playAddr = [highestBitrateModel valueForKey:@"playAddr"];
        if (playAddr && [playAddr isKindOfClass:%c(AWEURLModel)]) {
            return playAddr;
        }
    }

    return %orig;
}

- (NSArray *)bitrateModels {

    NSArray *originalModels = %orig;

    if (DYYYShouldDisableAllHDR()) {
        NSArray *filteredModels = DYYYFilteredSDRBitrateModels(originalModels);
        DYYYStripHDRHintsFromBitrateModels(filteredModels);
        originalModels = filteredModels;
    }

    if (!DYYYGetBool(@"DYYYEnableVideoHighestQuality")) {
        return originalModels;
    }

    if (originalModels.count == 0) {
        return originalModels;
    }

    // 查找比特率最高的模型
    id highestBitrateModel = nil;
    NSInteger highestBitrate = 0;

    for (id model in originalModels) {

        NSInteger bitrate = 0;
        BOOL validModel = NO;

        if ([model isKindOfClass:NSClassFromString(@"AWEVideoBSModel")]) {
            id bitrateValue = [model bitrate];
            if (bitrateValue) {
                bitrate = [bitrateValue integerValue];
                validModel = YES;
            }
        }

        if (validModel) {
            if (bitrate > highestBitrate) {
                highestBitrate = bitrate;
                highestBitrateModel = model;
            }
        }
    }

    if (highestBitrateModel) {
        return @[ highestBitrateModel ];
    }

    return originalModels;
}

- (void)setBitrateModels:(NSArray *)bitrateModels {
    if (DYYYShouldDisableAllHDR()) {
        NSArray *filteredModels = DYYYFilteredSDRBitrateModels(bitrateModels);
        DYYYStripHDRHintsFromBitrateModels(filteredModels);
        %orig(filteredModels);
        return;
    }
    %orig;
}

- (void)setManualBitrateModels:(NSArray *)manualBitrateModels {
    if (DYYYShouldDisableAllHDR()) {
        NSArray *filteredModels = DYYYFilteredSDRBitrateModels(manualBitrateModels);
        DYYYStripHDRHintsFromBitrateModels(filteredModels);
        %orig(filteredModels);
        return;
    }
    %orig;
}

- (NSArray *)manualBitrateModels {
    NSArray *models = %orig;
    if (DYYYShouldDisableAllHDR()) {
        models = DYYYFilteredSDRBitrateModels(models);
        DYYYStripHDRHintsFromBitrateModels(models);
    }
    return models;
}

- (void)setBitrateRawData:(NSArray *)bitrateRawData {
    if (DYYYShouldDisableAllHDR()) {
        %orig(DYYYFilteredSDRRawBitrateData(bitrateRawData));
        return;
    }
    %orig;
}

- (NSArray *)bitrateRawData {
    NSArray *rawData = %orig;
    if (DYYYShouldDisableAllHDR()) {
        rawData = DYYYFilteredSDRRawBitrateData(rawData);
    }
    return rawData;
}

- (void)setHasFilterHDR:(BOOL)hasFilterHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : hasFilterHDR);
}

- (BOOL)hasFilterHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setIsSourceHDR:(NSInteger)isSourceHDR {
    %orig(DYYYShouldDisableAllHDR() ? 0 : isSourceHDR);
}

- (NSInteger)isSourceHDR {
    if (DYYYShouldDisableAllHDR()) {
        return 0;
    }
    return %orig;
}

%end

static NSString *const kDYYYHDRModeKey = @"DYYYHDRMode";
static NSString *const kDYYYHDRModeOff = @"关闭";
static NSString *const kDYYYHDRModeDisable = @"全局屏蔽HDR效果";
static NSString *const kDYYYHDRModeFilter = @"全局过滤HDR作品";
static char kDYYYHDRStrippedAwemeModelKey;
static char kDYYYHDRStrippedVideoModelKey;
static char kDYYYHDROnlyAwemeModelKey;
static char kDYYYHDROnlyVideoModelKey;

static void DYYYMigrateCombinedHDRModeIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults boolForKey:@"DYYYHDRModeMigratedV1"]) {
            return;
        }

        NSString *mode = [defaults stringForKey:kDYYYHDRModeKey];
        BOOL hasValidMode = [mode isEqualToString:kDYYYHDRModeOff] ||
                            [mode isEqualToString:kDYYYHDRModeDisable] ||
                            [mode isEqualToString:kDYYYHDRModeFilter];
        if (!hasValidMode) {
            if ([defaults boolForKey:@"DYYYDisableAllHDR"]) {
                mode = kDYYYHDRModeDisable;
            } else if ([defaults boolForKey:@"DYYYFilterFeedHDR"]) {
                mode = kDYYYHDRModeFilter;
            } else {
                mode = kDYYYHDRModeOff;
            }
        }

        [defaults setObject:mode forKey:kDYYYHDRModeKey];
        [defaults removeObjectForKey:@"DYYYDisableAllHDR"];
        [defaults removeObjectForKey:@"DYYYFilterFeedHDR"];
        [defaults setBool:YES forKey:@"DYYYHDRModeMigratedV1"];
    });
}

static BOOL DYYYShouldDisableAllHDR(void) {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:kDYYYHDRModeKey] isEqualToString:kDYYYHDRModeDisable];
}

static BOOL DYYYShouldFilterGlobalHDR(void) {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:kDYYYHDRModeKey] isEqualToString:kDYYYHDRModeFilter];
}

static id DYYYKVCValueIfPossible(id object, NSString *key) {
    if (!object || key.length == 0) {
        return nil;
    }

    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void DYYYSetKVCValueIfPossible(id object, NSString *key, id value) {
    if (!object || key.length == 0) {
        return;
    }

    @try {
        [object setValue:value forKey:key];
    } @catch (__unused NSException *exception) {
    }
}

static id DYYYIvarValueIfPossible(id object, const char *ivarName) {
    if (!object || !ivarName) {
        return nil;
    }

    Class cls = object_getClass(object);
    while (cls) {
        Ivar ivar = class_getInstanceVariable(cls, ivarName);
        if (ivar) {
            return object_getIvar(object, ivar);
        }
        cls = class_getSuperclass(cls);
    }

    return nil;
}

static id DYYYValuePreferringIvar(id object, const char *ivarName, NSString *key) {
    id ivarValue = DYYYIvarValueIfPossible(object, ivarName);
    if (ivarValue) {
        return ivarValue;
    }
    return DYYYKVCValueIfPossible(object, key);
}

static NSInteger DYYYIntegerValueForKeyIfPossible(id object, NSString *key, NSInteger fallback) {
    id value = DYYYKVCValueIfPossible(object, key);
    if ([value respondsToSelector:@selector(integerValue)]) {
        return [value integerValue];
    }
    return fallback;
}

static BOOL DYYYStringValueLooksHDR(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return NO;
    }

    NSString *lowercaseValue = [(NSString *)value lowercaseString];
    return [lowercaseValue containsString:@"hdr"] ||
           [lowercaseValue containsString:@"hlg"] ||
           [lowercaseValue containsString:@"dolby"] ||
           [lowercaseValue containsString:@"vivid"] ||
           [lowercaseValue isEqualToString:@"pq"] ||
           [lowercaseValue containsString:@"_pq"] ||
           [lowercaseValue containsString:@"pq_"];
}

static BOOL DYYYRawBitrateDictionaryLooksHDR(NSDictionary *dictionary);

static BOOL DYYYBitrateModelLooksHDR(id bitrateModel) {
    if (!bitrateModel) {
        return NO;
    }

    if ([bitrateModel isKindOfClass:[NSDictionary class]]) {
        return DYYYRawBitrateDictionaryLooksHDR((NSDictionary *)bitrateModel);
    }

    id hdrTypeValue = DYYYKVCValueIfPossible(bitrateModel, @"hdrType");
    id hdrBitValue = DYYYKVCValueIfPossible(bitrateModel, @"hdrBit");
    NSInteger hdrType = DYYYIntegerValueForKeyIfPossible(bitrateModel, @"hdrType", 0);
    NSInteger hdrBit = DYYYIntegerValueForKeyIfPossible(bitrateModel, @"hdrBit", 0);
    BOOL hasHdrType = DYYYIntegerValueForKeyIfPossible(bitrateModel, @"hasHdrType", 0) > 0;
    BOOL hasHdrBit = DYYYIntegerValueForKeyIfPossible(bitrateModel, @"hasHdrBit", 0) > 0;

    return hdrType > 0 ||
           hdrBit >= 10 ||
           hasHdrType ||
           hasHdrBit ||
           DYYYStringValueLooksHDR(hdrTypeValue) ||
           DYYYStringValueLooksHDR(hdrBitValue);
}

static BOOL DYYYStringKeyLooksVideoBitrateList(NSString *key) {
    NSString *lowercaseKey = key.lowercaseString;
    if (lowercaseKey.length == 0 || [lowercaseKey containsString:@"audio"]) {
        return NO;
    }

    return [lowercaseKey containsString:@"bit_rate"] ||
           [lowercaseKey containsString:@"bitrate"] ||
           [lowercaseKey containsString:@"bit_rate_model"] ||
           [lowercaseKey containsString:@"bitratemodel"];
}

static BOOL DYYYRawBitrateDictionaryLooksHDR(NSDictionary *dictionary) {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    for (id rawKey in dictionary) {
        id value = dictionary[rawKey];
        NSString *key = [[rawKey description] lowercaseString];
        NSInteger numericValue = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;

        if (([key isEqualToString:@"hdr_type"] ||
             [key isEqualToString:@"hdrtype"] ||
             [key isEqualToString:@"videohdrtype"] ||
             [key isEqualToString:@"video_hdr_type"] ||
             [key isEqualToString:@"source_hdr_type"]) && numericValue > 0) {
            return YES;
        }

        if (([key isEqualToString:@"hdr_bit"] ||
             [key isEqualToString:@"hdrbit"] ||
             [key isEqualToString:@"bit_depth"] ||
             [key isEqualToString:@"bitdepth"]) && numericValue >= 10) {
            return YES;
        }

        if (([key isEqualToString:@"is_source_hdr"] ||
             [key isEqualToString:@"source_hdr"] ||
             [key isEqualToString:@"is_hdr"] ||
             [key isEqualToString:@"ishdr"] ||
             [key isEqualToString:@"has_hdr"] ||
             [key isEqualToString:@"hashdr"] ||
             [key isEqualToString:@"has_filter_hdr"] ||
             [key isEqualToString:@"filter_hdr"] ||
             [key isEqualToString:@"has_hdr_type"] ||
             [key isEqualToString:@"hashdrtype"] ||
             [key isEqualToString:@"has_hdr_bit"] ||
             [key isEqualToString:@"hashdrbit"]) && numericValue > 0) {
            return YES;
        }

        if (DYYYStringValueLooksHDR(value)) {
            return YES;
        }
    }

    return NO;
}

static void DYYYCollectRawBitrateHDRStatus(id object, NSUInteger depth, BOOL *foundHDRBitrate, BOOL *foundSDRBitrate) {
    if (!object || depth > 8 || (foundSDRBitrate && *foundSDRBitrate)) {
        return;
    }

    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)object;
        for (id rawKey in dictionary) {
            id value = dictionary[rawKey];
            NSString *key = [rawKey description];

            if (DYYYStringKeyLooksVideoBitrateList(key) && [value isKindOfClass:[NSArray class]]) {
                for (id entry in (NSArray *)value) {
                    if (![entry isKindOfClass:[NSDictionary class]]) {
                        continue;
                    }

                    if (DYYYRawBitrateDictionaryLooksHDR((NSDictionary *)entry)) {
                        if (foundHDRBitrate) {
                            *foundHDRBitrate = YES;
                        }
                    } else if (foundSDRBitrate) {
                        *foundSDRBitrate = YES;
                        return;
                    }
                }
                continue;
            }

            if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
                DYYYCollectRawBitrateHDRStatus(value, depth + 1, foundHDRBitrate, foundSDRBitrate);
            }
        }
    } else if ([object isKindOfClass:[NSArray class]]) {
        for (id value in (NSArray *)object) {
            DYYYCollectRawBitrateHDRStatus(value, depth + 1, foundHDRBitrate, foundSDRBitrate);
        }
    }
}

static BOOL DYYYRawObjectHasOnlyHDRBitrateModels(id object) {
    BOOL foundHDRBitrate = NO;
    BOOL foundSDRBitrate = NO;
    DYYYCollectRawBitrateHDRStatus(object, 0, &foundHDRBitrate, &foundSDRBitrate);
    return foundHDRBitrate && !foundSDRBitrate;
}

static BOOL DYYYVideoModelHasOnlyHDRBitrateModels(id video) {
    if (!video) {
        return NO;
    }

    NSNumber *cachedResult = objc_getAssociatedObject(video, &kDYYYHDROnlyVideoModelKey);
    if (cachedResult) {
        return cachedResult.boolValue;
    }

    NSMutableArray *models = [NSMutableArray array];
    NSArray *bitrateModels = DYYYValuePreferringIvar(video, "_bitrateModels", @"bitrateModels");
    if ([bitrateModels isKindOfClass:[NSArray class]]) {
        [models addObjectsFromArray:bitrateModels];
    }

    NSArray *manualBitrateModels = DYYYValuePreferringIvar(video, "_manualBitrateModels", @"manualBitrateModels");
    if ([manualBitrateModels isKindOfClass:[NSArray class]]) {
        [models addObjectsFromArray:manualBitrateModels];
    }

    NSArray *bitrateRawData = DYYYValuePreferringIvar(video, "_bitrateRawData", @"bitrateRawData");
    if ([bitrateRawData isKindOfClass:[NSArray class]]) {
        [models addObjectsFromArray:bitrateRawData];
    }

    if (models.count == 0) {
        return NO;
    }

    BOOL onlyHDR = YES;
    for (id model in models) {
        if (!DYYYBitrateModelLooksHDR(model)) {
            onlyHDR = NO;
            break;
        }
    }

    objc_setAssociatedObject(video, &kDYYYHDROnlyVideoModelKey, @(onlyHDR), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return onlyHDR;
}

static BOOL DYYYAwemeModelHasOnlyHDRBitrateModels(id aweme) {
    if (!aweme) {
        return NO;
    }

    NSNumber *cachedResult = objc_getAssociatedObject(aweme, &kDYYYHDROnlyAwemeModelKey);
    if (cachedResult) {
        return cachedResult.boolValue;
    }

    BOOL onlyHDR = NO;
    BOOL shouldCacheResult = NO;
    id video = DYYYValuePreferringIvar(aweme, "_video", @"video");
    if (video) {
        shouldCacheResult = YES;
    }
    if (DYYYVideoModelHasOnlyHDRBitrateModels(video)) {
        onlyHDR = YES;
    } else {
        NSArray *albumImages = DYYYValuePreferringIvar(aweme, "_albumImages", @"albumImages");
        if ([albumImages isKindOfClass:[NSArray class]]) {
            shouldCacheResult = shouldCacheResult || albumImages.count > 0;
            for (id imageModel in albumImages) {
                id clipVideo = DYYYValuePreferringIvar(imageModel, "_clipVideo", @"clipVideo");
                if (DYYYVideoModelHasOnlyHDRBitrateModels(clipVideo)) {
                    onlyHDR = YES;
                    break;
                }
            }
        }
    }

    if (shouldCacheResult || onlyHDR) {
        objc_setAssociatedObject(aweme, &kDYYYHDROnlyAwemeModelKey, @(onlyHDR), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return onlyHDR;
}

static NSArray *DYYYFilteredSDRRawBitrateData(NSArray *rawData) {
    if (![rawData isKindOfClass:[NSArray class]] || rawData.count == 0) {
        return rawData;
    }

    NSMutableArray *sdrData = [NSMutableArray arrayWithCapacity:rawData.count];
    NSUInteger hdrCount = 0;
    for (id entry in rawData) {
        if ([entry isKindOfClass:[NSDictionary class]] && DYYYRawBitrateDictionaryLooksHDR((NSDictionary *)entry)) {
            hdrCount++;
            continue;
        }
        [sdrData addObject:entry];
    }

    if (hdrCount == 0 || sdrData.count == 0) {
        return rawData;
    }

    return [sdrData copy];
}

static NSArray *DYYYFilteredSDRBitrateModels(NSArray *models) {
    if (![models isKindOfClass:[NSArray class]] || models.count == 0) {
        return models;
    }

    NSMutableArray *sdrModels = [NSMutableArray arrayWithCapacity:models.count];
    NSUInteger hdrCount = 0;
    for (id model in models) {
        if (DYYYBitrateModelLooksHDR(model)) {
            hdrCount++;
            continue;
        }
        [sdrModels addObject:model];
    }

    // 只有 HDR 档的作品在模型层过滤；这里不清空列表，避免播放器拿不到可播档导致有声黑屏。
    if (hdrCount == 0 || sdrModels.count == 0) {
        return models;
    }

    return [sdrModels copy];
}

static void DYYYStripHDRHintsFromBitrateModels(NSArray *models) {
    if (![models isKindOfClass:[NSArray class]]) {
        return;
    }

    for (id model in models) {
        DYYYSetKVCValueIfPossible(model, @"hdrType", @0);
        DYYYSetKVCValueIfPossible(model, @"hdrBit", @8);
        DYYYSetKVCValueIfPossible(model, @"hasHdrType", @NO);
        DYYYSetKVCValueIfPossible(model, @"hasHdrBit", @NO);
    }
}

static void DYYYStripHDRHintsFromVideoModel(id video) {
    if (!DYYYShouldDisableAllHDR() || !video) {
        return;
    }

    if (objc_getAssociatedObject(video, &kDYYYHDRStrippedVideoModelKey)) {
        return;
    }
    objc_setAssociatedObject(video, &kDYYYHDRStrippedVideoModelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if ([video respondsToSelector:@selector(setIsSourceHDR:)]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(video, @selector(setIsSourceHDR:), 0);
    }
    if ([video respondsToSelector:@selector(setHasFilterHDR:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(video, @selector(setHasFilterHDR:), NO);
    }

    NSArray *bitrateModels = DYYYKVCValueIfPossible(video, @"bitrateModels");
    NSArray *filteredBitrateModels = DYYYFilteredSDRBitrateModels(bitrateModels);
    if (filteredBitrateModels && filteredBitrateModels != bitrateModels) {
        DYYYSetKVCValueIfPossible(video, @"bitrateModels", filteredBitrateModels);
        bitrateModels = filteredBitrateModels;
    }
    DYYYStripHDRHintsFromBitrateModels(bitrateModels);

    NSArray *manualBitrateModels = DYYYKVCValueIfPossible(video, @"manualBitrateModels");
    NSArray *filteredManualBitrateModels = DYYYFilteredSDRBitrateModels(manualBitrateModels);
    if (filteredManualBitrateModels && filteredManualBitrateModels != manualBitrateModels) {
        DYYYSetKVCValueIfPossible(video, @"manualBitrateModels", filteredManualBitrateModels);
        manualBitrateModels = filteredManualBitrateModels;
    }
    DYYYStripHDRHintsFromBitrateModels(manualBitrateModels);

    NSArray *bitrateRawData = DYYYValuePreferringIvar(video, "_bitrateRawData", @"bitrateRawData");
    NSArray *filteredBitrateRawData = DYYYFilteredSDRRawBitrateData(bitrateRawData);
    if (filteredBitrateRawData && filteredBitrateRawData != bitrateRawData) {
        DYYYSetKVCValueIfPossible(video, @"bitrateRawData", filteredBitrateRawData);
    }
}

static void DYYYStripHDRHintsFromAwemeModel(id aweme) {
    if (!DYYYShouldDisableAllHDR() || !aweme) {
        return;
    }

    if (objc_getAssociatedObject(aweme, &kDYYYHDRStrippedAwemeModelKey)) {
        return;
    }
    objc_setAssociatedObject(aweme, &kDYYYHDRStrippedAwemeModelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    id video = DYYYValuePreferringIvar(aweme, "_video", @"video");
    DYYYStripHDRHintsFromVideoModel(video);

    NSArray *albumImages = DYYYValuePreferringIvar(aweme, "_albumImages", @"albumImages");
    if ([albumImages isKindOfClass:[NSArray class]]) {
        for (id imageModel in albumImages) {
            DYYYStripHDRHintsFromVideoModel(DYYYValuePreferringIvar(imageModel, "_clipVideo", @"clipVideo"));
        }
    }
}

static id DYYYStandardCADynamicRange(void) {
    static id standardDynamicRange = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *symbol = dlsym(RTLD_DEFAULT, "CADynamicRangeStandard");
        if (symbol) {
            id __unsafe_unretained *value = (id __unsafe_unretained *)symbol;
            standardDynamicRange = *value;
        }
    });
    return standardDynamicRange;
}

static id DYYYToneMapModeIfSupported(void) {
    static id toneMapMode = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *symbol = dlsym(RTLD_DEFAULT, "CAToneMapModeIfSupported");
        if (symbol) {
            id __unsafe_unretained *value = (id __unsafe_unretained *)symbol;
            toneMapMode = *value;
        }
    });
    return toneMapMode;
}

static void DYYYApplySDRDynamicRangeToImageView(UIImageView *imageView) {
    if (!DYYYShouldDisableAllHDR() || !imageView) {
        return;
    }

    if (@available(iOS 17.0, *)) {
        imageView.preferredImageDynamicRange = UIImageDynamicRangeStandard;
    }
}

// 头像加号可能由异步动画重建图层，需要在 CALayer 写入点继续压制。
static BOOL DYYYShouldForceHideAvatarActionLayer(CALayer *layer);
static BOOL DYYYShouldClearAvatarActionLayer(CALayer *layer);
static void DYYYPrepareAvatarActionSublayer(CALayer *parentLayer, CALayer *sublayer);

static void DYYYDisableExtendedRangeForLayer(CALayer *layer) {
    if (!DYYYShouldDisableAllHDR() || !layer) {
        return;
    }

    SEL setWantsEDRSelector = @selector(setWantsExtendedDynamicRangeContent:);
    if ([layer respondsToSelector:setWantsEDRSelector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(layer, setWantsEDRSelector, NO);
    }

    id toneMapMode = DYYYToneMapModeIfSupported();
    SEL setToneMapModeSelector = @selector(setToneMapMode:);
    if (toneMapMode && [layer respondsToSelector:setToneMapModeSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(layer, setToneMapModeSelector, toneMapMode);
    }

    id standardDynamicRange = DYYYStandardCADynamicRange();
    SEL setPreferredDynamicRangeSelector = @selector(setPreferredDynamicRange:);
    if (standardDynamicRange && [layer respondsToSelector:setPreferredDynamicRangeSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(layer, setPreferredDynamicRangeSelector, standardDynamicRange);
    }

    if (@available(iOS 16.0, *)) {
        if ([layer isKindOfClass:[CAMetalLayer class]]) {
            ((CAMetalLayer *)layer).EDRMetadata = nil;
        }
    }
}

static void DYYYDisableExtendedRangeForMetalLayer(CAMetalLayer *metalLayer) {
    if (!DYYYShouldDisableAllHDR() || !metalLayer) {
        return;
    }

    DYYYDisableExtendedRangeForLayer(metalLayer);
}

static void DYYYDisableAVPlayerItemHDRMetadata(AVPlayerItem *item) {
    if (!DYYYShouldDisableAllHDR() || !item) {
        return;
    }

    if (@available(iOS 14.0, *)) {
        item.appliesPerFrameHDRDisplayMetadata = NO;
    }
}

// 保留 HDR 解码及原生 HDR -> SDR 转换，只关闭亮度增强、SDR -> HDR 和最终 EDR 输出。

%hook AVPlayer

+ (AVPlayerHDRMode)availableHDRModes {
    if (DYYYShouldDisableAllHDR()) {
        return 0;
    }
    return %orig;
}

+ (BOOL)eligibleForHDRPlayback {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (instancetype)playerWithURL:(NSURL *)URL {
    AVPlayer *player = %orig;
    DYYYDisableAVPlayerItemHDRMetadata(player.currentItem);
    return player;
}

+ (instancetype)playerWithPlayerItem:(AVPlayerItem *)item {
    DYYYDisableAVPlayerItemHDRMetadata(item);
    return %orig;
}

- (instancetype)initWithURL:(NSURL *)URL {
    self = %orig;
    DYYYDisableAVPlayerItemHDRMetadata(self.currentItem);
    return self;
}

- (instancetype)initWithPlayerItem:(AVPlayerItem *)item {
    DYYYDisableAVPlayerItemHDRMetadata(item);
    return %orig;
}

- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    DYYYDisableAVPlayerItemHDRMetadata(item);
    %orig;
}

%end

%hook AVPlayerItem

+ (instancetype)playerItemWithURL:(NSURL *)URL {
    AVPlayerItem *item = %orig;
    DYYYDisableAVPlayerItemHDRMetadata(item);
    return item;
}

+ (instancetype)playerItemWithAsset:(AVAsset *)asset {
    AVPlayerItem *item = %orig;
    DYYYDisableAVPlayerItemHDRMetadata(item);
    return item;
}

+ (instancetype)playerItemWithAsset:(AVAsset *)asset automaticallyLoadedAssetKeys:(NSArray<NSString *> *)automaticallyLoadedAssetKeys {
    AVPlayerItem *item = %orig;
    DYYYDisableAVPlayerItemHDRMetadata(item);
    return item;
}

- (instancetype)initWithURL:(NSURL *)URL {
    self = %orig;
    DYYYDisableAVPlayerItemHDRMetadata(self);
    return self;
}

- (instancetype)initWithAsset:(AVAsset *)asset {
    self = %orig;
    DYYYDisableAVPlayerItemHDRMetadata(self);
    return self;
}

- (instancetype)initWithAsset:(AVAsset *)asset automaticallyLoadedAssetKeys:(NSArray<NSString *> *)automaticallyLoadedAssetKeys {
    self = %orig;
    DYYYDisableAVPlayerItemHDRMetadata(self);
    return self;
}

- (void)setAppliesPerFrameHDRDisplayMetadata:(BOOL)appliesPerFrameHDRDisplayMetadata {
    %orig(DYYYShouldDisableAllHDR() ? NO : appliesPerFrameHDRDisplayMetadata);
}

- (BOOL)appliesPerFrameHDRDisplayMetadata {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook AVPlayerLayer

- (void)setPlayer:(AVPlayer *)player {
    DYYYDisableAVPlayerItemHDRMetadata(player.currentItem);
    %orig;
    DYYYDisableExtendedRangeForLayer(self);
}

- (void)layoutSublayers {
    %orig;
    DYYYDisableAVPlayerItemHDRMetadata(self.player.currentItem);
    DYYYDisableExtendedRangeForLayer(self);
}

%end

%hook AWEKnowledgeABTestSettings

+ (BOOL)enableHDRAutomaticIdentification {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook AWEFeedABSettings

+ (BOOL)enableHDRBrightnessOpt {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)enableProfilePreloadHDRBrightnessFilter {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)enableDynamicGaussianBlurHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)enableHDRFullModelAdaptation {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)hdrAutomaticIdentification {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook AWEFeedABTestServiceObjc

+ (BOOL)enableProfilePreloadHDRBrightnessFilter {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook BDSimPlayerBizConfig

- (BOOL)enableHDRBrightnessOpt {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (BOOL)enableHDRFullModelAdaptation {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (BOOL)hdrAutomaticIdentification {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook AWEBDSimPlayerBizConfig

- (BOOL)enableHDRBrightnessOpt {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (BOOL)enableHDRFullModelAdaptation {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (BOOL)hdrAutomaticIdentification {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook AWEVideoPlayerConfiguration

+ (void)setHDRBrightnessStrategy:(id)strategy {
    if (!DYYYShouldDisableAllHDR()) {
        %orig;
    }
}

+ (double)getHDRBrightnessOffset:(id)configuration brightness:(double)brightness {
    if (DYYYShouldDisableAllHDR()) {
        return 0.0;
    }
    return %orig;
}

%end

%hook AWEDPlayerVideoDisplayOptState

- (BOOL)enableHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setEnableHDR:(BOOL)enableHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : enableHDR);
}

%end

%hook AWEPlayVideoPlayerContext

- (BOOL)enableHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setEnableHDR:(BOOL)enableHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : enableHDR);
}

%end

%hook AWEDPlayerVideoModel

- (BOOL)awe_isHDRVideo {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setAwe_isHDRVideo:(BOOL)awe_isHDRVideo {
    %orig(DYYYShouldDisableAllHDR() ? NO : awe_isHDRVideo);
}

%end

%hook AWEPlayVideoViewController

- (BOOL)enableHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setEnableHDR:(BOOL)enableHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : enableHDR);
}

- (BOOL)awe_isCurrentVideoHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setPlayerLutFilter:(id)lutFilter HDRLutImage:(id)HDRLutImage {
    %orig(lutFilter, DYYYShouldDisableAllHDR() ? nil : HDRLutImage);
}

%end

%hook AWEDPlayerBrightnessContainer

- (BOOL)awe_isCurrentVideoHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook AWEVideoPlayerScreenBrightnessManager

- (BOOL)isHDRVideo {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setIsHDRVideo:(BOOL)isHDRVideo {
    // 播放器复用时会重新写入当前作品的 HDR 状态，需同时清除写入值和读取结果。
    %orig(DYYYShouldDisableAllHDR() ? NO : isHDRVideo);
}

%end

%hook ALMOwnPlayerWrapper

- (void)setLutFilter:(id)lutFilter HDRLutImage:(id)HDRLutImage {
    %orig(lutFilter, DYYYShouldDisableAllHDR() ? nil : HDRLutImage);
}

%end

%hook ALMSysPlayerWrapper

- (void)setLutFilter:(id)lutFilter HDRLutImage:(id)HDRLutImage {
    %orig(lutFilter, DYYYShouldDisableAllHDR() ? nil : HDRLutImage);
}

%end

%hook ALMVideoPlayerConfig

+ (void)setPlayerEffectHDRLutImageEnable:(BOOL)enable {
    %orig(DYYYShouldDisableAllHDR() ? NO : enable);
}

%end

%hook IESVideoPlayerConfig

+ (void)setPlayerEffectHDRLutImageEnable:(BOOL)enable {
    %orig(DYYYShouldDisableAllHDR() ? NO : enable);
}

%end

%hook AWEIMModuleService

- (BOOL)im_forceHDRToSDR {
    if (DYYYShouldDisableAllHDR()) {
        return YES;
    }
    return %orig;
}

%end

%hook IESIMVideoPlayerWrapper

- (void)setupHDREnable:(BOOL)enable {
    %orig(DYYYShouldDisableAllHDR() ? NO : enable);
}

%end

%hook AWEIMVideoBrowserCollectionViewCell

- (void)setEnablePlayHDR:(BOOL)enable {
    %orig(DYYYShouldDisableAllHDR() ? NO : enable);
}

%end

%hook AWEECOMIMAppSettingsService

+ (BOOL)enableVideoPreviewSupportHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook IESLiveAudienceHDRController

+ (BOOL)currentHDRStatusForRoomID:(id)roomID {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)isCurrentRoomSupportHDR:(id)roomID roomModel:(id)roomModel {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)isFeedCanEnableHDRFeature {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)isInnerFeedCanEnableHDRFeature {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)isUserEnableHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)p_isHDRFeatureEnable {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (void)setUserEnableHDR:(BOOL)enableHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : enableHDR);
}

+ (BOOL)shouldShowHDRSwitchForRoom:(id)room {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook IESLivePlayerController

- (BOOL)isVideoSDR2HDRSupport {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setEnableVideoSDR2HDR:(BOOL)enable callTrace:(id)callTrace {
    %orig(DYYYShouldDisableAllHDR() ? NO : enable, callTrace);
}

- (BOOL)enableCloseSDR2HDR {
    if (DYYYShouldDisableAllHDR()) {
        return YES;
    }
    return %orig;
}

%end

%hook AWELivePreStreamPlayer

- (void)changeSDR2HDRWithStrategy {
    if (!DYYYShouldDisableAllHDR()) {
        %orig;
    }
}

%end

%hook HTSLiveStreamPlayer

- (void)setEnableVideoSDR2HDR:(BOOL)enable callTrace:(id)callTrace {
    %orig(DYYYShouldDisableAllHDR() ? NO : enable, callTrace);
}

- (void)changeSDR2HDRWithStrategy {
    if (!DYYYShouldDisableAllHDR()) {
        %orig;
    }
}

%end

%hook IESLiveStreamPlayerVideoAudioEffectPlugin

- (void)setEnableVideoSDR2HDR:(BOOL)enable callTrace:(id)callTrace {
    %orig(DYYYShouldDisableAllHDR() ? NO : enable, callTrace);
}

- (void)changeSDR2HDRWithStrategy {
    if (!DYYYShouldDisableAllHDR()) {
        %orig;
    }
}

%end

%hook TVLManager

- (BOOL)shouldForbidHDR10Render {
    if (DYYYShouldDisableAllHDR()) {
        return YES;
    }
    return %orig;
}

- (void)setShouldForbidHDR10Render:(BOOL)shouldForbid {
    %orig(DYYYShouldDisableAllHDR() ? YES : shouldForbid);
}

- (void)setupVideoSDR2HDR:(id)config {
    if (!DYYYShouldDisableAllHDR()) {
        %orig;
    }
}

%end

%hook TVLPlayerItemPreferences

- (BOOL)forbidSDR2HDRInPreview {
    if (DYYYShouldDisableAllHDR()) {
        return YES;
    }
    return %orig;
}

- (void)setForbidSDR2HDRInPreview:(BOOL)forbid {
    %orig(DYYYShouldDisableAllHDR() ? YES : forbid);
}

- (BOOL)enableUseSDR2HDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setEnableUseSDR2HDR:(BOOL)enable {
    %orig(DYYYShouldDisableAllHDR() ? NO : enable);
}

%end

%hook TVLSettingsManager

- (BOOL)enableMetalRenderHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook IESFiltersManager

- (void)setHDRIndensity:(double)intensity {
    %orig(DYYYShouldDisableAllHDR() ? 0.0 : intensity);
}

%end

%hook BDImageDecoderFactory

+ (BOOL)isHDRImageData:(id)data withHeifDecoderClass:(Class)decoderClass {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook BDImageDecoderImageIO

- (BOOL)isHDRCGImage:(CGImageRef)image decodedToHDR:(BOOL)decodedToHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (id)hdrOptionsFor:(id)image decodedToHDR:(BOOL *)decodedToHDR {
    if (DYYYShouldDisableAllHDR()) {
        if (decodedToHDR) {
            *decodedToHDR = NO;
        }
        return nil;
    }
    return %orig;
}

%end

%hook BDImageDecoderHeic

+ (BOOL)isHDRData:(id)data {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (BOOL)isHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setIsHDR:(BOOL)isHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : isHDR);
}

%end

%hook BDImageDecoderBVC2

- (BOOL)isHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setIsHDR:(BOOL)isHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : isHDR);
}

%end

%hook BDImageDecoderWebP

- (BOOL)isHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setIsHDR:(BOOL)isHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : isHDR);
}

%end

%hook BDImage

- (BOOL)isHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setIsHDR:(BOOL)isHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : isHDR);
}

%end

%hook HDRMTUIImageView

- (instancetype)initWithFrame:(CGRect)frame hdrEnabled:(BOOL)hdrEnabled {
    return %orig(frame, DYYYShouldDisableAllHDR() ? NO : hdrEnabled);
}

- (BOOL)hdrEnabled {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setHdrEnabled:(BOOL)hdrEnabled {
    %orig(DYYYShouldDisableAllHDR() ? NO : hdrEnabled);
}

- (void)setImage:(UIImage *)image {
    if (DYYYShouldDisableAllHDR()) {
        self.hdrEnabled = NO;
    }
    DYYYApplySDRDynamicRangeToImageView(self);
    %orig;
    DYYYApplySDRDynamicRangeToImageView(self);
}

%end

%hook HDRMTImageView

- (void)setMetalLayer:(CAMetalLayer *)metalLayer {
    %orig;
    DYYYDisableExtendedRangeForMetalLayer(metalLayer);
}

- (void)setUpEnv {
    %orig;
    DYYYDisableExtendedRangeForMetalLayer(self.metalLayer);
}

- (void)layoutSubviews {
    %orig;
    DYYYDisableExtendedRangeForMetalLayer(self.metalLayer);
}

%end

%hook HDRMTButton

- (void)configHDRContent {
    %orig;
    DYYYApplySDRDynamicRangeToImageView(self.hdrmtImageView);
}

%end

%hook CAMetalLayer

- (void)setWantsExtendedDynamicRangeContent:(BOOL)wantsExtendedDynamicRangeContent {
    %orig(DYYYShouldDisableAllHDR() ? NO : wantsExtendedDynamicRangeContent);
}

- (BOOL)wantsExtendedDynamicRangeContent {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setEDRMetadata:(CAEDRMetadata *)EDRMetadata {
    %orig(DYYYShouldDisableAllHDR() ? nil : EDRMetadata);
}

- (CAEDRMetadata *)EDRMetadata {
    if (DYYYShouldDisableAllHDR()) {
        return nil;
    }
    return %orig;
}

%end

%hook CALayer

- (void)setHidden:(BOOL)hidden {
    %orig(DYYYShouldForceHideAvatarActionLayer(self) ? YES : hidden);
}

- (void)setContents:(id)contents {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? nil : contents);
}

- (void)setBackgroundColor:(CGColorRef)backgroundColor {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? UIColor.clearColor.CGColor : backgroundColor);
}

- (void)setOpaque:(BOOL)opaque {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? NO : opaque);
}

- (void)setBorderWidth:(CGFloat)borderWidth {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? 0.0 : borderWidth);
}

- (void)setBorderColor:(CGColorRef)borderColor {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? UIColor.clearColor.CGColor : borderColor);
}

- (void)setShadowOpacity:(float)shadowOpacity {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? 0.0f : shadowOpacity);
}

- (void)setShadowColor:(CGColorRef)shadowColor {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? UIColor.clearColor.CGColor : shadowColor);
}

- (void)addSublayer:(CALayer *)layer {
    DYYYPrepareAvatarActionSublayer(self, layer);
    %orig(layer);
}

- (void)insertSublayer:(CALayer *)layer atIndex:(unsigned int)index {
    DYYYPrepareAvatarActionSublayer(self, layer);
    %orig(layer, index);
}

- (void)insertSublayer:(CALayer *)layer below:(CALayer *)sibling {
    DYYYPrepareAvatarActionSublayer(self, layer);
    %orig(layer, sibling);
}

- (void)insertSublayer:(CALayer *)layer above:(CALayer *)sibling {
    DYYYPrepareAvatarActionSublayer(self, layer);
    %orig(layer, sibling);
}

- (void)setSublayers:(NSArray<CALayer *> *)sublayers {
    for (CALayer *layer in sublayers) {
        DYYYPrepareAvatarActionSublayer(self, layer);
    }
    %orig(sublayers);
}

- (void)setWantsExtendedDynamicRangeContent:(BOOL)wantsExtendedDynamicRangeContent {
    %orig(DYYYShouldDisableAllHDR() ? NO : wantsExtendedDynamicRangeContent);
}

- (BOOL)wantsExtendedDynamicRangeContent {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setPreferredDynamicRange:(id)preferredDynamicRange {
    id standardDynamicRange = DYYYStandardCADynamicRange();
    %orig(DYYYShouldDisableAllHDR() && standardDynamicRange ? standardDynamicRange : preferredDynamicRange);
}

- (id)preferredDynamicRange {
    id preferredDynamicRange = %orig;
    if (DYYYShouldDisableAllHDR()) {
        id standardDynamicRange = DYYYStandardCADynamicRange();
        if (standardDynamicRange) {
            return standardDynamicRange;
        }
    }
    return preferredDynamicRange;
}

%end

%hook CAShapeLayer

- (void)setFillColor:(CGColorRef)fillColor {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? UIColor.clearColor.CGColor : fillColor);
}

- (void)setStrokeColor:(CGColorRef)strokeColor {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? UIColor.clearColor.CGColor : strokeColor);
}

%end

// 直播间真实人数
%hook IESLiveUserSeqlistFragment

- (void)refreshVerticalUserCount:(id)arg1 horizontalUserCount:(id)arg2 trueValue:(NSInteger)trueValue {
    if ( trueValue > 0 && DYYYGetBool(@"DYYYEnableLiveRealCount") ) {
        NSString *realStr = [NSString stringWithFormat:@"%ld", (long)trueValue];
        %orig(realStr, realStr, trueValue);
    } else {
        %orig;
    }
}

%end

// 评论具体时间
%hook AWEDateTimeFormatter

+ (id)formattedDateForTimestamp:(double)timestamp {
    if (!DYYYGetBool(@"DYYYCommentExactTime")) return %orig(timestamp);
    return [NSString stringWithFormat:@"%.0f ", timestamp];
}

%end

%hook AWERLVirtualLabel

- (void)setText:(NSString *)text {
    if (!DYYYGetBool(@"DYYYCommentExactTime") || !text || text.length == 0) {
        %orig(text);
        return;
    }

    if ([text isEqualToString:@"回复"]) {
        %orig(@"");
        return;
    }

    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(\\d{10,13})([\\s\\S]*)" options:0 error:&error];
    
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];

    if (match) {
        NSString *rawTs = [text substringWithRange:[match rangeAtIndex:1]];
        NSString *suffix = [text substringWithRange:[match rangeAtIndex:2]];
        
        long long ts = [rawTs longLongValue];
        
        if (ts > 100000000000) {
            ts = ts / 1000;
        }
        
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *formattedDate = [formatter stringFromDate:date];
        
        NSString *newText = [NSString stringWithFormat:@"%@%@", formattedDate, suffix];
        %orig(newText);
    } else {
        %orig(text);
    }
}

%end

%group DYYYCommentExactTimeGroup
%hook AWECommentSwiftBizUI_CommentInteractionBaseLabel

- (void)setText:(NSString *)text {
    %orig(text); // 先让系统把文本赋上去
    
    if (!DYYYGetBool(@"DYYYCommentExactTime")) {
        return;
    }

    UILabel *label = (UILabel *)self;
    if (!text || text.length == 0) return;

    // --- 1. 拦截翻译文本，将其绝对定位在屏幕右侧 100 像素 ---
    if ([text isEqualToString:@"翻译"] || [text isEqualToString:@"隐藏翻译"]) {
        CGRect currentFrame = label.frame;
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        // 重新计算 X 坐标：屏幕宽度 - 100 - 标签自身宽度
        currentFrame.origin.x = screenWidth - 100.0 - currentFrame.size.width;
        label.frame = currentFrame;
        return;
    }

    // --- 2. 拦截时间文本，如果不够宽则扩充宽度 ---
    UIFont *font = label.font;
    if (font) {
        CGFloat expectedWidth = ceilf([text sizeWithAttributes:@{NSFontAttributeName: font}].width);
        CGRect currentFrame = label.frame;
        
        // 如果当前宽度不够，并且不是尚未初始化的状态（>0），则强行修改并重新赋值
        if (currentFrame.size.width < expectedWidth && currentFrame.size.width > 0) {
            currentFrame.size.width = expectedWidth;
            label.frame = currentFrame; 
            label.clipsToBounds = NO;
        }
    }
}

- (void)setFrame:(CGRect)frame {
    if (!DYYYGetBool(@"DYYYCommentExactTime") || ![self respondsToSelector:@selector(text)]) {
        %orig(frame);
        return;
    }

    UILabel *label = (UILabel *)self;
    NSString *text = label.text;

    if (text && text.length > 0) {
        // --- 1. 拦截翻译文本，将其绝对定位在屏幕右侧 100 像素 ---
        if ([text isEqualToString:@"翻译"] || [text isEqualToString:@"隐藏翻译"]) {
            CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
            frame.origin.x = screenWidth - 100.0 - frame.size.width;
        } 
        // --- 2. 拦截时间文本，如果不够宽则扩充宽度 ---
        else if ([self respondsToSelector:@selector(font)]) {
            UIFont *font = label.font;
            if (font) {
                CGFloat expectedWidth = ceilf([text sizeWithAttributes:@{NSFontAttributeName: font}].width);
                if (frame.size.width < expectedWidth && frame.size.width > 0) {
                    frame.size.width = expectedWidth;
                    label.clipsToBounds = NO;
                }
            }
        }
    }

    %orig(frame);
}

%end
%end

// 前面的AWEDateTimeFormatter会导致图文视频展开时间文本变成时间戳，这里处理下
%hook YYLabel

// 1. Hook 富文本赋值方法 (核心)
- (void)setAttributedText:(NSAttributedString *)attributedText {
    if (!DYYYGetBool(@"DYYYCommentExactTime") || !attributedText || attributedText.length == 0) {
        %orig(attributedText);
        return;
    }

    NSString *plainText = [attributedText string];

    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(\\d{10,13})" options:0 error:&error];
    NSTextCheckingResult *match = [regex firstMatchInString:plainText options:0 range:NSMakeRange(0, plainText.length)];

    if (match) {
        NSString *rawTs = [plainText substringWithRange:[match rangeAtIndex:1]];
        long long ts = [rawTs longLongValue];
        
        if (ts > 100000000000) {
            ts = ts / 1000;
        }
        
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *formattedDate = [formatter stringFromDate:date];
        
        NSMutableAttributedString *newAttrStr = [attributedText mutableCopy];
        [newAttrStr replaceCharactersInRange:[match rangeAtIndex:1] withString:formattedDate];
        
        %orig(newAttrStr);
    } else {
        %orig(attributedText);
    }
}

%end

// 禁用自动进入直播间
%hook AWELiveGuideElement

- (BOOL)enableAutoEnterRoom {
    if (DYYYGetBool(@"DYYYDisableAutoEnterLive")) {
        return NO;
    }
    return %orig;
}

- (BOOL)enableNewAutoEnter {
    if (DYYYGetBool(@"DYYYDisableAutoEnterLive")) {
        return NO;
    }
    return %orig;
}

%end

%hook AWEFeedChannelManager

- (void)reloadChannelWithChannelModels:(id)arg1 currentChannelIDList:(id)arg2 reloadType:(id)arg3 selectedChannelID:(id)arg4 {
    NSArray *channelModels = arg1;
    NSMutableArray *newChannelModels = [NSMutableArray array];
    NSArray *currentChannelIDList = arg2;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *newCurrentChannelIDList = [NSMutableArray arrayWithArray:currentChannelIDList];

    if (!arg1 || !arg2) {
        %orig(arg1, arg2, arg3, arg4);
        return;
    }

    if (![channelModels isKindOfClass:[NSArray class]] || ![currentChannelIDList isKindOfClass:[NSArray class]]) {
        %orig(arg1, arg2, arg3, arg4);
        return;
    }

    if (channelModels.count == 0) {
        %orig(arg1, arg2, arg3, arg4);
        return;
    }

    for (AWEHPTopTabItemModel *tabItemModel in channelModels) {
        NSString *channelID = tabItemModel.channelID;
        BOOL isHideChannel = NO;

        if ([channelID isEqualToString:@"homepage_hot_container"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideHotContainer"];
        } else if ([channelID isEqualToString:@"homepage_follow"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideFollow"];
        } else if ([channelID isEqualToString:@"homepage_mall"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideMall"];
        } else if ([channelID isEqualToString:@"homepage_nearby"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideNearby"];
        } else if ([channelID isEqualToString:@"homepage_groupon"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideGroupon"];
        } else if ([channelID isEqualToString:@"homepage_tablive"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideTabLive"];
        } else if ([channelID isEqualToString:@"homepage_pad_hot"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHidePadHot"];
        } else if ([channelID isEqualToString:@"homepage_hangout"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideHangout"];
        } else if ([channelID isEqualToString:@"homepage_familiar"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideFriend"];
        } else if ([channelID isEqualToString:@"homepage_playlet_stream"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHidePlaylet"];
        } else if ([channelID isEqualToString:@"homepage_pad_cinema"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideCinema"];
        } else if ([channelID isEqualToString:@"homepage_pad_kids_v2"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideKidsV2"];
        } else if ([channelID isEqualToString:@"homepage_pad_game"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideGame"];
        } else if ([channelID isEqualToString:@"homepage_mediumvideo"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideMediumVideo"];
        }

        if (!isHideChannel) {
            [newChannelModels addObject:tabItemModel];
        } else {
            [newCurrentChannelIDList removeObject:channelID];
        }
    }

    %orig(newChannelModels, newCurrentChannelIDList, arg3, arg4);
}

%end

%hook AWELandscapeFeedViewController
- (void)viewDidLoad {
    %orig;

    // 尝试优先走属性
    gFeedCV = self.collectionView;

    // 保险起见再fallback,遍历 subviews
    if (!gFeedCV) {
        gFeedCV = [DYYYUtils findSubviewOfClass:[UICollectionView class] inContainer:self.view];
    }
}
%end

%hook UICollectionView

// 拦截手指拖动
- (void)handlePan:(UIPanGestureRecognizer *)pan {

    /* 仅处理横屏Feed列表。其余collectionView直接走系统逻辑 */
    if (self != gFeedCV || !DYYYGetBool(@"DYYYVideoGesture")) {
        %orig;
        return;
    }

    /* 取触点坐标、手势状态 */
    CGPoint loc = [pan locationInView:self];
    CGFloat w = self.bounds.size.width;
    CGFloat xPct = loc.x / w; // 0.0 ~ 1.0
    UIGestureRecognizerState st = pan.state;

    /* BEGAN：判定左右 20 % 区域 → 进入亮度 / 音量模式 */
    if (st == UIGestureRecognizerStateBegan) {

        gStartY = loc.y;

        if (xPct <= 0.20) { // 左边缘 → 亮度
            gMode = DYEdgeModeBrightness;
            gStartVal = [UIScreen mainScreen].brightness;

        } else if (xPct >= 0.80) { // 右边缘 → 音量
            gMode = DYEdgeModeVolume;
            gStartVal = [[objc_getClass("AVSystemController") sharedAVSystemController] volumeForCategory:@"Audio/Video"];

        } else {
            gMode = DYEdgeModeNone; // 中间区域走原逻辑
        }
    }

    /* 调节阶段：左右边缘时吞掉滚动、修改亮度/音量 */
    if (gMode != DYEdgeModeNone) {

        if (st == UIGestureRecognizerStateChanged) {

            CGFloat delta = (gStartY - loc.y) / self.bounds.size.height; // ↑ 为正
            const CGFloat kScale = 2.0;                                  // 灵敏度
            float newVal = gStartVal + delta * kScale;
            newVal = fminf(fmaxf(newVal, 0.0), 1.0); // Clamp 0~1

            if (gMode == DYEdgeModeBrightness) {
                [UIScreen mainScreen].brightness = newVal;
                // 弹系统亮度 HUD
                [[%c(SBHUDController) sharedInstance] presentHUDWithIcon:@"Brightness" level:newVal];

            } else { // DYEdgeModeVolume
                // iOS 18 音量控制 + 系统音量 HUD
                [[objc_getClass("AVSystemController") sharedAVSystemController] setVolumeTo:newVal forCategory:@"Audio/Video"];
            }

            // 吞掉滚动：归零 translation，防止内容位移
            [pan setTranslation:CGPointZero inView:self];
        }

        /* 结束／取消：状态复位 */
        if (st == UIGestureRecognizerStateEnded || st == UIGestureRecognizerStateCancelled || st == UIGestureRecognizerStateFailed) {
            gMode = DYEdgeModeNone;
        }

        return; // 左右边缘：彻底阻断 %orig，避免翻页
    }

    /* 中间区域：直接执行原先翻页逻辑 */
    %orig;
}

%end

%hook AWELeftSideBarAddChildTransitionObject

- (void)handleShowSliderPanGesture:(id)gr {
    if (DYYYGetBool(@"DYYYDisableSidebarGesture")) {
        return;
    }
    %orig(gr);
}

%end

%hook AWEPlayInteractionUserAvatarElement
- (void)onFollowViewClicked:(UITapGestureRecognizer *)gesture {
    if (!DYYYGetBool(@"DYYYFollowTips")) {
        %orig;
        return;
    }
    AWEUserModel *author = self.model.author;
    NSString *userID = author.userID;
    [DYYYBottomAlertView showFollowConfirmationForUser:author avatarView:self.userAvatarView confirmAction:^{
        if (![self.model.author.userID isEqualToString:userID]) {
            [DYYYUtils showToast:@"当前作品已切换，请重新确认"];
            return;
        }
        %orig(gesture);
    }];
}

%end

%hook AWEPlayInteractionUserAvatarFollowController
- (void)onFollowViewClicked:(UITapGestureRecognizer *)gesture {
    if (!DYYYGetBool(@"DYYYFollowTips")) {
        %orig;
        return;
    }
    AWEUserModel *author = self.model.author;
    NSString *userID = author.userID;
    [DYYYBottomAlertView showFollowConfirmationForUser:author avatarView:self.userAvatarView confirmAction:^{
        if (![self.model.author.userID isEqualToString:userID]) {
            [DYYYUtils showToast:@"当前作品已切换，请重新确认"];
            return;
        }
        %orig(gesture);
    }];
}

%end

%hook AWEFeedTopBarContainer
- (void)didMoveToSuperview {
    %orig;
    applyTopBarTransparency(self);
}
- (void)setAlpha:(CGFloat)alpha {
    NSString *transparentValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYTopBarTransparent"];
    if (transparentValue && transparentValue.length > 0) {
        CGFloat alphaValue = [transparentValue floatValue];
        if (alphaValue >= 0.0 && alphaValue <= 1.0) {
            CGFloat finalAlpha = (alphaValue < 0.011) ? 0.011 : alphaValue;
            %orig(finalAlpha);
        } else {
            %orig(1.0);
        }
    } else {
        %orig(1.0);
    }
}
%end

// 设置修改顶栏标题
%hook AWEHPTopTabItemTextContentView

- (void)layoutSubviews {
    %orig;
    NSDictionary<NSString *, NSString *> *titleMapping = DYYYTopTabTitleMapping();
    if (titleMapping.count == 0) {
        return;
    }

    NSString *accessibilityLabel = nil;
    if ([self.superview respondsToSelector:@selector(accessibilityLabel)]) {
        accessibilityLabel = self.superview.accessibilityLabel;
    }
    if (accessibilityLabel.length == 0) {
        return;
    }

    NSString *newTitle = titleMapping[accessibilityLabel];
    if (newTitle.length == 0) {
        return;
    }

    if ([self respondsToSelector:@selector(setContentText:)]) {
        [self setContentText:newTitle];
    } else {
        [self setValue:newTitle forKey:@"contentText"];
    }
}

%end

%hook AWEDanmakuContentLabel
- (void)setTextColor:(UIColor *)textColor {
    if (DYYYGetBool(@"DYYYEnableDanmuColor")) {
        NSString *danmuColor = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDanmuColor"];
        if (DYYYGetBool(@"DYYYDanmuRainbowRotating")) {
            danmuColor = @"rainbow_rotating";
        }
        [DYYYUtils applyColorSettingsToLabel:self colorHexString:danmuColor];
    } else {
        %orig(textColor);
    }
}

- (void)setStrokeWidth:(double)strokeWidth {
    if (DYYYGetBool(@"DYYYEnableDanmuColor")) {
        %orig(FLT_MIN);
    } else {
        %orig(strokeWidth);
    }
}

- (void)setStrokeColor:(UIColor *)strokeColor {
    if (DYYYGetBool(@"DYYYEnableDanmuColor")) {
        %orig(nil);
    } else {
        %orig(strokeColor);
    }
}

%end

%hook XIGDanmakuPlayerView

- (id)initWithFrame:(CGRect)frame {
    id orig = %orig;

    ((UIView *)orig).tag = DYYY_IGNORE_GLOBAL_ALPHA_TAG;

    return orig;
}

- (void)setAlpha:(CGFloat)alpha {
    if (DYYYGetBool(@"DYYYCommentShowDanmaku") && alpha == 0.0) {
        return;
    } else {
        %orig(alpha);
    }
}

%end

%hook DDanmakuPlayerView

- (void)setAlpha:(CGFloat)alpha {
    if (DYYYGetBool(@"DYYYCommentShowDanmaku") && alpha == 0.0) {
        return;
    } else {
        %orig(alpha);
    }
}

%end

%hook AWEMarkView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideLocation")) {
        self.hidden = YES;
        return;
    }
}

%end

%group DYYYSettingsGesture

// 宿主把窗口失焦当作离开播放页；插件文本输入的焦点交接不改变播放状态。
%hook AWEFCMessesController
- (void)windowDidResignKeyNotification:(NSNotification *)notification {
    if (![DYYYSettingsCoordinator isSettingsInputFocusNotification:notification])
        %orig;
}
- (void)windowDidBecomeKeyNotification:(NSNotification *)notification {
    if (![DYYYSettingsCoordinator isSettingsInputFocusNotification:notification])
        %orig;
}
%end

%hook AFDContainerViewController
- (void)_windowDidResignKeyNotification:(NSNotification *)notification {
    if (![DYYYSettingsCoordinator isSettingsInputFocusNotification:notification])
        %orig;
}
- (void)_windowDidBecomeKeyNotification:(NSNotification *)notification {
    if (![DYYYSettingsCoordinator isSettingsInputFocusNotification:notification])
        %orig;
}
%end

%hook AWEAwemeDetailTableViewController
- (void)_windowDidResignKeyNotification:(NSNotification *)notification {
    if (![DYYYSettingsCoordinator isSettingsInputFocusNotification:notification])
        %orig;
}
- (void)_windowDidBecomeKeyNotification:(NSNotification *)notification {
    if (![DYYYSettingsCoordinator isSettingsInputFocusNotification:notification])
        %orig;
}
%end

%hook AWECommonFeedAutoPlayHandler
- (void)windowDidResignKeyNotification:(NSNotification *)notification {
    if (![DYYYSettingsCoordinator isSettingsInputFocusNotification:notification])
        %orig;
}
- (void)windowDidBecomeKeyNotification:(NSNotification *)notification {
    if (![DYYYSettingsCoordinator isSettingsInputFocusNotification:notification])
        %orig;
}
%end

%hook AWECommonFeedContainerViewController
- (void)windowDidResignKeyNotification:(NSNotification *)notification {
    if (![DYYYSettingsCoordinator isSettingsInputFocusNotification:notification])
        %orig;
}
- (void)windowDidBecomeKeyNotification:(NSNotification *)notification {
    if (![DYYYSettingsCoordinator isSettingsInputFocusNotification:notification])
        %orig;
}
%end

%hook UIWindow
- (void)becomeKeyWindow {
    %orig;
    [[DYYYSettingsCoordinator shared] installGestureInWindow:self];
}

- (void)makeKeyAndVisible {
    %orig;
    [[DYYYSettingsCoordinator shared] installGestureInWindow:self];

    if (!isFloatSpeedButtonEnabled || self.windowLevel != UIWindowLevelNormal)
        return;

    if (speedButton && ![speedButton isDescendantOfView:self]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self addSubview:speedButton];
          [speedButton loadSavedPosition];
          [speedButton resetFadeTimer];
        });
    }
}
%end
%end


%hook AWEFeedVideoButton
- (id)touchUpInsideBlock {
    id r = %orig;

    // 只有收藏按钮才显示确认弹窗
    if (DYYYGetBool(@"DYYYCollectTips") && [self.accessibilityLabel isEqualToString:@"收藏"]) {

        dispatch_async(dispatch_get_main_queue(), ^{
          [DYYYBottomAlertView showCollectConfirmationWithAction:^{
                                      if (r && [r isKindOfClass:NSClassFromString(@"NSBlock")]) {
                                          ((void (^)(void))r)();
                                      }
                                    }];
        });

        return nil;
    }

    return r;
}
%end

%hook AWEPlayInteractionProgressContainerView
- (void)layoutSubviews {
    %orig;
    DYYYApplyFloatClearProgressStateToView(self);
}

%end

%hook AWEFeedProgressSlider

- (void)layoutSubviews {
    %orig;
    DYYYApplyFloatClearProgressStateToView(self);
}

- (void)setAlpha:(CGFloat)alpha {
    if (DYYYGetBool(@"DYYYShowScheduleDisplay")) {
        if (DYYYGetBool(@"DYYYHideVideoProgress")) {
            %orig(0);
        } else {
            %orig(1.0);
        }
    } else {
        %orig;
    }
}

%new
- (NSString *)dyyy_formatTimeFromSeconds:(CGFloat)seconds {
    CGFloat safeSeconds = seconds;
    if (safeSeconds < 0) {
        safeSeconds = 0;
    }

    NSInteger total = (NSInteger)floor(safeSeconds);
    NSInteger hours = total / 3600;
    NSInteger minutes = (total % 3600) / 60;
    NSInteger secs = total % 60;

    if (hours > 0) {
        return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)hours, (long)minutes, (long)secs];
    }
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)secs];
}

%new
- (CGFloat)dyyy_modelDurationInSeconds {
    id delegate = self.progressSliderDelegate;
    if (!delegate || ![delegate respondsToSelector:@selector(model)]) {
        return 0;
    }

    id model = [delegate valueForKey:@"model"];
    if (!model || ![model respondsToSelector:@selector(videoDuration)]) {
        return 0;
    }

    CGFloat videoDurationMs = [[model valueForKey:@"videoDuration"] doubleValue];
    if (videoDurationMs <= 0) {
        return 0;
    }
    return videoDurationMs / 1000.0;
}

%new
- (CGFloat)dyyy_scheduleVerticalOffset {
    CGFloat verticalOffset = -12.5;
    NSString *offsetValueString = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYTimelineVerticalPosition"];
    if (offsetValueString.length > 0) {
        CGFloat configuredOffset = [offsetValueString floatValue];
        if (configuredOffset != 0) {
            verticalOffset = configuredOffset;
        }
    }
    return verticalOffset;
}

%new
- (void)dyyy_removeScheduleLabels {
    UIView *parentView = self.superview;
    if (!parentView) {
        return;
    }
    [parentView layoutIfNeeded];
    [self layoutIfNeeded];
    [[parentView viewWithTag:10001] removeFromSuperview];
    [[parentView viewWithTag:10002] removeFromSuperview];
}

%new
- (void)dyyy_updateScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration {
    if (!DYYYGetBool(@"DYYYShowScheduleDisplay")) {
        [self dyyy_removeScheduleLabels];
        return;
    }

    if (![NSThread isMainThread]) {
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
          [weakSelf dyyy_updateScheduleLabelsWithCurrentTime:currentTime totalDuration:totalDuration];
        });
        return;
    }

    UIView *parentView = self.superview;
    if (!parentView) {
        return;
    }
    [parentView layoutIfNeeded];
    [self layoutIfNeeded];

    NSString *scheduleStyle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYScheduleStyle"];
    BOOL showRightRemainingTime = [scheduleStyle isEqualToString:@"进度条右侧剩余"];
    BOOL showRightCompleteTime = [scheduleStyle isEqualToString:@"进度条右侧完整"];
    BOOL showLeftRemainingTime = [scheduleStyle isEqualToString:@"进度条左侧剩余"];
    BOOL showLeftCompleteTime = [scheduleStyle isEqualToString:@"进度条左侧完整"];

    BOOL shouldShowLeftLabel = !showRightRemainingTime && !showRightCompleteTime;
    BOOL shouldShowRightLabel = !showLeftRemainingTime && !showLeftCompleteTime;

    CGFloat modelDuration = [self dyyy_modelDurationInSeconds];
    CGFloat effectiveTotalDuration = totalDuration > 0 ? totalDuration : modelDuration;
    if (effectiveTotalDuration < 0) {
        effectiveTotalDuration = 0;
    }

    CGFloat effectiveCurrentTime = currentTime;
    if (effectiveCurrentTime < 0) {
        effectiveCurrentTime = 0;
    }
    if (effectiveTotalDuration > 0 && effectiveCurrentTime > effectiveTotalDuration) {
        effectiveCurrentTime = effectiveTotalDuration;
    }

    CGRect sliderFrameInParent = [self convertRect:self.bounds toView:parentView];
    if (CGRectGetWidth(sliderFrameInParent) <= 1.0 || CGRectGetHeight(sliderFrameInParent) <= 1.0) {
        return;
    }
    CGFloat labelYPosition = CGRectGetMinY(sliderFrameInParent) + [self dyyy_scheduleVerticalOffset];
    CGFloat labelHeight = 15.0;
    UIFont *labelFont = [UIFont systemFontOfSize:8];
    NSString *labelColorHex = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYProgressLabelColor"];

    UILabel *leftLabel = (UILabel *)[parentView viewWithTag:10001];
    if (leftLabel && ![leftLabel isKindOfClass:[UILabel class]]) {
        [leftLabel removeFromSuperview];
        leftLabel = nil;
    }

    if (shouldShowLeftLabel) {
        if (!leftLabel) {
            leftLabel = [[UILabel alloc] init];
            leftLabel.backgroundColor = [UIColor clearColor];
            leftLabel.tag = 10001;
            [parentView addSubview:leftLabel];
        }

        leftLabel.font = labelFont;
        NSString *newLeftText = nil;
        if (showLeftRemainingTime) {
            newLeftText = [self dyyy_formatTimeFromSeconds:MAX(effectiveTotalDuration - effectiveCurrentTime, 0)];
        } else if (showLeftCompleteTime) {
            newLeftText = [NSString stringWithFormat:@"%@/%@", [self dyyy_formatTimeFromSeconds:effectiveCurrentTime], [self dyyy_formatTimeFromSeconds:effectiveTotalDuration]];
        } else {
            newLeftText = [self dyyy_formatTimeFromSeconds:effectiveCurrentTime];
        }

        if (![leftLabel.text isEqualToString:newLeftText]) {
            leftLabel.text = newLeftText;
        }
        [leftLabel sizeToFit];
        leftLabel.frame = CGRectMake(CGRectGetMinX(sliderFrameInParent), labelYPosition, CGRectGetWidth(leftLabel.bounds), labelHeight);
        [DYYYUtils applyColorSettingsToLabel:leftLabel colorHexString:labelColorHex];
    } else {
        [leftLabel removeFromSuperview];
    }

    UILabel *rightLabel = (UILabel *)[parentView viewWithTag:10002];
    if (rightLabel && ![rightLabel isKindOfClass:[UILabel class]]) {
        [rightLabel removeFromSuperview];
        rightLabel = nil;
    }

    if (shouldShowRightLabel) {
        if (!rightLabel) {
            rightLabel = [[UILabel alloc] init];
            rightLabel.backgroundColor = [UIColor clearColor];
            rightLabel.tag = 10002;
            [parentView addSubview:rightLabel];
        }

        rightLabel.font = labelFont;
        NSString *newRightText = nil;
        if (showRightRemainingTime) {
            newRightText = [self dyyy_formatTimeFromSeconds:MAX(effectiveTotalDuration - effectiveCurrentTime, 0)];
        } else if (showRightCompleteTime) {
            newRightText = [NSString stringWithFormat:@"%@/%@", [self dyyy_formatTimeFromSeconds:effectiveCurrentTime], [self dyyy_formatTimeFromSeconds:effectiveTotalDuration]];
        } else {
            newRightText = [self dyyy_formatTimeFromSeconds:effectiveTotalDuration];
        }

        if (![rightLabel.text isEqualToString:newRightText]) {
            rightLabel.text = newRightText;
        }
        [rightLabel sizeToFit];
        CGFloat rightLabelX = MAX(CGRectGetMaxX(sliderFrameInParent) - CGRectGetWidth(rightLabel.bounds), CGRectGetMinX(sliderFrameInParent));
        rightLabel.frame = CGRectMake(rightLabelX, labelYPosition, CGRectGetWidth(rightLabel.bounds), labelHeight);
        [DYYYUtils applyColorSettingsToLabel:rightLabel colorHexString:labelColorHex];
    } else {
        [rightLabel removeFromSuperview];
    }
}

- (void)setLimitUpperActionArea:(BOOL)arg1 {
    %orig;
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      [weakSelf dyyy_updateScheduleLabelsWithCurrentTime:0 totalDuration:0];
    });
}

- (void)setHidden:(BOOL)hidden {
    %orig;
    BOOL hideVideoProgress = DYYYGetBool(@"DYYYHideVideoProgress");
    BOOL showScheduleDisplay = DYYYGetBool(@"DYYYShowScheduleDisplay");
    if (hideVideoProgress && showScheduleDisplay && !hidden) {
        self.alpha = 0;
    }
}

%end

%hook AWEPlayInteractionTimestampElement

- (id)timestampLabel {
    UILabel *label = %orig;
    BOOL isEnableArea = DYYYGetBool(@"DYYYEnableArea");
    if (!isEnableArea) {
        return label;
    }

    NSString *labelColorHex = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYLabelColor"];
    if (DYYYGetBool(@"DYYYEnableRandomGradient")) {
        labelColorHex = @"random_gradient";
    }

    BOOL boldEnabled = DYYYGetBool(@"DYYYBoldTimestamp");
    if (boldEnabled && label.font) {
        UIFont *boldFont = [UIFont boldSystemFontOfSize:label.font.pointSize];
        label.font = boldFont;
    }

    NSString *cityCode = self.model.cityCode;
    NSString *regionCode = nil;
    if ([self.model respondsToSelector:@selector(region)]) {
        regionCode = [self.model performSelector:@selector(region)];
    }

    if (cityCode && ([cityCode isEqualToString:@"0"] || [cityCode integerValue] == 0)) {
        cityCode = nil;
    }

    static NSCache *locationCache;
    static NSMutableSet *inFlight;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        locationCache = [[NSCache alloc] init];
        locationCache.countLimit = 100;
        inFlight = [[NSMutableSet alloc] init];
    });

    void (^updateLabelWithLocation)(UILabel *, NSString *) = ^(UILabel *lbl, NSString *location) {
        if (location.length == 0) return;

        NSString *currentText = lbl.text ?: @"";
        if ([currentText containsString:location]) return;

        if ([currentText containsString:@"IP属地："]) {
            NSRange range = [currentText rangeOfString:@"IP属地："];
            NSString *baseText = [currentText substringToIndex:range.location];
            lbl.text = [NSString stringWithFormat:@"%@IP属地：%@", baseText, location];
        } else if (currentText.length > 0) {
            lbl.text = [NSString stringWithFormat:@"%@  IP属地：%@", currentText, location];
        }

        [DYYYUtils applyColorSettingsToLabel:lbl colorHexString:labelColorHex];
    };

    if (cityCode.length == 0 && regionCode.length == 0) {
        updateLabelWithLocation(label, @"未知地区");
        return label;
    }

    NSString *cacheKey = cityCode.length > 0 ? cityCode : regionCode;

    NSString *cachedLocation = [locationCache objectForKey:cacheKey];
    if (cachedLocation) {
        updateLabelWithLocation(label, cachedLocation);

        NSString *ipScaleValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNicknameScale"];
        if (ipScaleValue.length > 0) {
            UIFont *originalFont = label.font;
            CGFloat offset = DYYYGetFloat(@"DYYYIPLabelVerticalOffset");
            if (offset > 0) {
                label.transform = CGAffineTransformMakeTranslation(0, -offset);
            } else {
                label.transform = CGAffineTransformMakeTranslation(0, -3);
            }
            label.font = originalFont;
        }
        return label;
    }

    NSString *displayLocation = nil;

    if (cityCode.length > 0) {
        displayLocation = [CityManager.sharedInstance getCityNameWithCode:cityCode];

        if (!displayLocation) {
            @synchronized(inFlight) {
                if ([inFlight containsObject:cityCode]) {
                    return label;
                }
                [inFlight addObject:cityCode];
            }

            [CityManager fetchLocationWithGeonameId:cityCode completionHandler:^(NSDictionary *locationInfo, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    @synchronized(inFlight) {
                        [inFlight removeObject:cityCode];
                    }

                    NSString *apiLocation = nil;

                    if (!error && locationInfo) {
                        NSString *localName = locationInfo[@"name"];
                        NSString *adminName1 = locationInfo[@"adminName1"];
                        NSString *countryName = locationInfo[@"countryName"];

                        if (![localName isKindOfClass:[NSString class]]) {
                            localName = nil;
                        }
                        if (![adminName1 isKindOfClass:[NSString class]]) {
                            adminName1 = nil;
                        }
                        if (![countryName isKindOfClass:[NSString class]]) {
                            countryName = nil;
                        }

                        if (countryName.length > 0) {
                            if (adminName1.length > 0 && localName.length > 0 && ![countryName isEqualToString:localName]) {
                                if ([adminName1 isEqualToString:localName]) {
                                    apiLocation = [NSString stringWithFormat:@"%@ %@", countryName, localName];
                                } else {
                                    apiLocation = [NSString stringWithFormat:@"%@ %@ %@", countryName, adminName1, localName];
                                }
                            } else if (localName.length > 0 && ![countryName isEqualToString:localName]) {
                                apiLocation = [NSString stringWithFormat:@"%@ %@", countryName, localName];
                            } else if (adminName1.length > 0 && ![countryName isEqualToString:adminName1]) {
                                apiLocation = [NSString stringWithFormat:@"%@ %@", countryName, adminName1];
                            } else {
                                apiLocation = countryName;
                            }
                        } else if (localName.length > 0) {
                            apiLocation = localName;
                        } else if (adminName1.length > 0) {
                            apiLocation = adminName1;
                        }
                    }

                    if (apiLocation.length > 0) {
                        [locationCache setObject:apiLocation forKey:cacheKey];
                        updateLabelWithLocation(label, apiLocation);
                    } else {
                        if (regionCode.length > 0) {
                            NSString *fallbackCountry = [CityManager.sharedInstance getCountryNameWithCode:regionCode];
                            updateLabelWithLocation(label, fallbackCountry);
                        }
                    }
                });
            }];

            return label;
        }
    }

    if (!displayLocation && !cityCode && regionCode.length > 0) {
        displayLocation = [CityManager.sharedInstance getCountryNameWithCode:regionCode];
    }

    if (!displayLocation) {
        displayLocation = @"未知地区";
        updateLabelWithLocation(label, displayLocation);
        return label;
    }

    [locationCache setObject:displayLocation forKey:cacheKey];
    updateLabelWithLocation(label, displayLocation);

    NSString *ipScaleValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNicknameScale"];
    if (ipScaleValue.length > 0) {
        UIFont *originalFont = label.font;
        CGFloat offset = DYYYGetFloat(@"DYYYIPLabelVerticalOffset");
        if (offset > 0) {
            label.transform = CGAffineTransformMakeTranslation(0, -offset);
        } else {
            label.transform = CGAffineTransformMakeTranslation(0, -3);
        }
        label.font = originalFont;
    }
    return label;
}

+ (BOOL)shouldActiveWithData:(id)arg1 context:(id)arg2 {
    return DYYYGetBool(@"DYYYEnableArea");
}

%end

%hook AWEPlayInteractionProgressController

%new
- (void)dyyy_syncScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration {
    if (!DYYYGetBool(@"DYYYShowScheduleDisplay")) {
        return;
    }

    id progressSlider = self.progressSlider;
    if (progressSlider && [progressSlider respondsToSelector:@selector(dyyy_updateScheduleLabelsWithCurrentTime:totalDuration:)]) {
        [progressSlider dyyy_updateScheduleLabelsWithCurrentTime:currentTime totalDuration:totalDuration];
    }

    if ([progressSlider isKindOfClass:[UIView class]]) {
        [(UIView *)progressSlider dyyy_updateScheduleLabelsLegacyWithCurrentTime:currentTime totalDuration:totalDuration model:self.model];
    }
}

- (void)updateProgressSliderWithTime:(CGFloat)arg1 totalDuration:(CGFloat)arg2 {
    %orig;
    [self dyyy_syncScheduleLabelsWithCurrentTime:arg1 totalDuration:arg2];
}

%end

%hook AWEDProgressCoreContainer

%new
- (void)dyyy_syncScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration {
    if (!DYYYGetBool(@"DYYYShowScheduleDisplay")) {
        return;
    }

    id progressSlider = self.progressSlider;
    if (progressSlider && [progressSlider respondsToSelector:@selector(dyyy_updateScheduleLabelsWithCurrentTime:totalDuration:)]) {
        [progressSlider dyyy_updateScheduleLabelsWithCurrentTime:currentTime totalDuration:totalDuration];
    }

    id model = nil;
    if ([self respondsToSelector:@selector(model)]) {
        model = [self valueForKey:@"model"];
    }

    if ([progressSlider isKindOfClass:[UIView class]]) {
        [(UIView *)progressSlider dyyy_updateScheduleLabelsLegacyWithCurrentTime:currentTime totalDuration:totalDuration model:model];
    }
}

- (void)updateProgressSliderWithTime:(CGFloat)arg1 totalDuration:(CGFloat)arg2 {
    %orig;
    [self dyyy_syncScheduleLabelsWithCurrentTime:arg1 totalDuration:arg2];
}

%end

%hook AWEPlayInteractionDescriptionScrollView

- (void)layoutSubviews {
    %orig;

    self.transform = CGAffineTransformIdentity;

    NSString *descriptionOffsetValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDescriptionVerticalOffset"];
    CGFloat verticalOffset = 0;
    if (descriptionOffsetValue.length > 0) {
        verticalOffset = [descriptionOffsetValue floatValue];
    }

    UIView *parentView = self.superview;
    UIView *grandParentView = nil;

    if (parentView) {
        grandParentView = parentView.superview;
    }

    if (grandParentView && verticalOffset != 0) {
        CGAffineTransform translationTransform = CGAffineTransformMakeTranslation(0, verticalOffset);
        grandParentView.transform = translationTransform;
    }
}

%end

// 对新版文案的偏移（33.0以上）
%hook AWEPlayInteractionDescriptionLabel

static char kLongPressGestureKey;
static NSString *const kDYYYLongPressCopyEnabledKey = @"DYYYLongPressCopyTextEnabled";

- (void)didMoveToWindow {
    %orig;

    BOOL longPressCopyEnabled = DYYYGetBool(kDYYYLongPressCopyEnabledKey);

    if (![[NSUserDefaults standardUserDefaults] objectForKey:kDYYYLongPressCopyEnabledKey]) {
        longPressCopyEnabled = NO;
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kDYYYLongPressCopyEnabledKey];
    }

    UIGestureRecognizer *existingGesture = objc_getAssociatedObject(self, &kLongPressGestureKey);
    if (existingGesture && !longPressCopyEnabled) {
        [self removeGestureRecognizer:existingGesture];
        objc_setAssociatedObject(self, &kLongPressGestureKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (longPressCopyEnabled && !objc_getAssociatedObject(self, &kLongPressGestureKey)) {
        UILongPressGestureRecognizer *highPriorityLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleHighPriorityLongPress:)];
        highPriorityLongPress.minimumPressDuration = 0.3;

        [self addGestureRecognizer:highPriorityLongPress];

        UIView *currentView = self;
        while (currentView.superview) {
            currentView = currentView.superview;

            for (UIGestureRecognizer *recognizer in currentView.gestureRecognizers) {
                if ([recognizer isKindOfClass:[UILongPressGestureRecognizer class]] || [recognizer isKindOfClass:[UIPinchGestureRecognizer class]]) {
                    [recognizer requireGestureRecognizerToFail:highPriorityLongPress];
                }
            }
        }

        objc_setAssociatedObject(self, &kLongPressGestureKey, highPriorityLongPress, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer.view isEqual:self] && [gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        return NO;
    }
    return YES;
}

%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer.view isEqual:self] && [gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        return YES;
    }
    return NO;
}

%new
- (void)handleHighPriorityLongPress:(UILongPressGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {

        NSString *description = self.text;

        if (description.length > 0) {
            [[UIPasteboard generalPasteboard] setString:description];
            [DYYYToast showSuccessToastWithMessage:@"视频文案已复制"];
        }
    }
}

- (void)layoutSubviews {
    %orig;

    self.transform = CGAffineTransformIdentity;

    NSString *descriptionOffsetValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDescriptionVerticalOffset"];
    CGFloat verticalOffset = 0;
    if (descriptionOffsetValue.length > 0) {
        verticalOffset = [descriptionOffsetValue floatValue];
    }

    UIView *parentView = self.superview;
    UIView *grandParentView = nil;

    if (parentView) {
        grandParentView = parentView.superview;
    }

    if (grandParentView && verticalOffset != 0) {
        CGAffineTransform translationTransform = CGAffineTransformMakeTranslation(0, verticalOffset);
        grandParentView.transform = translationTransform;
    }
}

%end

%hook AWEUserNameLabel

- (void)layoutSubviews {
    %orig;

    self.transform = CGAffineTransformIdentity;

    // 添加垂直偏移支持
    NSString *verticalOffsetValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNicknameVerticalOffset"];
    CGFloat verticalOffset = 0;
    if (verticalOffsetValue.length > 0) {
        verticalOffset = [verticalOffsetValue floatValue];
    }

    UIView *parentView = self.superview;
    UIView *grandParentView = nil;

    if (parentView) {
        grandParentView = parentView.superview;
    }

    // 检查祖父视图是否为 AWEBaseElementView 类型
    if (grandParentView && [grandParentView.superview isKindOfClass:%c(AWEBaseElementView)]) {
        CGRect scaledFrame = grandParentView.frame;
        CGFloat translationX = -scaledFrame.origin.x;

        CGAffineTransform translationTransform = CGAffineTransformMakeTranslation(translationX, verticalOffset);
        grandParentView.transform = translationTransform;
    }
}

%end

%hook AWEFeedVideoButton

- (void)setImage:(id)arg1 {
    UIImage *imageToApply = arg1;
    NSString *nameString = nil;

    if ([self respondsToSelector:@selector(imageNameString)]) {
        IMP imp = [self methodForSelector:@selector(imageNameString)];
        if (imp) {
            NSString *(*func)(id, SEL) = (NSString * (*)(id, SEL)) imp;
            if (func) {
                nameString = func(self, @selector(imageNameString));
            }
        }
    }

    NSString *customFileName = DYYYCustomIconFileNameForButtonName(nameString);
    if (customFileName.length > 0) {
        UIImage *customImage = DYYYLoadCustomImage(customFileName, CGSizeMake(44.0, 44.0));
        if (customImage) {
            imageToApply = customImage;
        }
    }

    %orig(imageToApply);
}

%end

%hook AWENormalModeTabBarGeneralPlusButton
- (void)setImage:(UIImage *)image forState:(UIControlState)state {

    UIImage *imageToApply = image;
    if ([self.accessibilityLabel isEqualToString:@"拍摄"]) {
        UIImage *customImage = DYYYLoadCustomImage(@"tab_plus.png", CGSizeZero);
        if (customImage) {
            imageToApply = customImage;
        }
    }

    %orig(imageToApply, state);
}
%end

// 获取资源的地址
%hook AWEURLModel
%new - (NSURL *)getDYYYSrcURLDownload {
    NSURL *bestURL;
    for (NSString *url in self.originURLList) {
        if ([url containsString:@"video_mp4"] || [url containsString:@".jpeg"] || [url containsString:@".mp3"]) {
            bestURL = [NSURL URLWithString:url];
        }
    }

    if (bestURL == nil) {
        bestURL = [NSURL URLWithString:[self.originURLList firstObject]];
    }

    return bestURL;
}
%end

// 为 AWEUserActionSheetView 添加毛玻璃效果
%hook AWEUserActionSheetView

- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYEnableSheetBlur")) {
        [self applyBlurEffectAndWhiteText];
    }
}

%new
- (void)applyBlurEffectAndWhiteText {
    // 应用毛玻璃效果到容器视图
    if (self.containerView) {
        self.containerView.backgroundColor = [UIColor clearColor];

        // 动态获取用户设置的透明度
        float userTransparency = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYSheetBlurTransparent"] floatValue];
        if (userTransparency <= 0 || userTransparency > 1) {
            userTransparency = 0.9; // 默认值0.9
        }

        [DYYYUtils applyBlurEffectToView:self.containerView transparency:userTransparency blurViewTag:9999];
        [DYYYUtils clearBackgroundRecursivelyInView:self.containerView];
        // 调用新的通用方法设置文本颜色，这里没有排除需求，所以传入 nil Block
        [DYYYUtils applyTextColorRecursively:[UIColor whiteColor] inView:self.containerView shouldExcludeViewBlock:nil];
    }
}

%end

%hook _TtC33AWECommentLongPressPanelSwiftImpl32CommentLongPressPanelCopyElement

- (void)elementTapped {
    if (!DYYYGetBool(@"DYYYCommentCopyText")) {
        %orig;
        return;
    }

    AWECommentLongPressPanelContext *commentPageContext = [self commentPageContext];
    AWECommentModel *selectdComment = [commentPageContext selectdComment];
    if (!selectdComment) {
        AWECommentLongPressPanelParam *params = [commentPageContext params];
        selectdComment = [params selectdComment];
    }
    NSString *descText = [selectdComment content];
    if (descText.length == 0) {
        %orig;
        return;
    }

    [[UIPasteboard generalPasteboard] setString:descText];
    [DYYYToast showSuccessToastWithMessage:@"评论已复制"];
}
%end

// 启用自动勾选原图
%hook AWEIMPhotoPickerFunctionModel

- (void)setUseShadowIcon:(BOOL)arg1 {
    BOOL enabled = DYYYGetBool(@"DYYYAutoSelectOriginalPhoto");
    if (enabled) {
        %orig(YES);
    } else {
        %orig(arg1);
    }
}

- (BOOL)isSelected {
    BOOL enabled = DYYYGetBool(@"DYYYAutoSelectOriginalPhoto");
    if (enabled) {
        return YES;
    }
    return %orig;
}

%end

// 屏蔽直播PCDN
%hook HTSLiveStreamPcdnManager

+ (void)start {
    BOOL disablePCDN = DYYYGetBool(@"DYYYDisableLivePCDN");
    if (!disablePCDN) {
        %orig;
    } else {
        NSLog(@"[DYYY] HTSLiveStreamPcdnManager start blocked");
    }
}

+ (void)configAndStartLiveIO {
    BOOL disablePCDN = DYYYGetBool(@"DYYYDisableLivePCDN");
    if (!disablePCDN) {
        %orig;
    } else {
        NSLog(@"[DYYY] HTSLiveStreamPcdnManager configAndStartLiveIO blocked");
    }
}

%end

// PCDN启动任务hook
%hook IESLiveLaunchTaskPcdn

- (void)excute {
    BOOL disablePCDN = DYYYGetBool(@"DYYYDisableLivePCDN");
    if (disablePCDN) {
        NSLog(@"[DYYY] IESLiveLaunchTaskPcdn excute blocked");
        return;
    }
    %orig;
}

%end

// 投屏忽略 VPN 检测
%hook BDByteCastUtils

+ (BOOL)netVPNStatus {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        return NO;
    }
    return %orig;
}

%end

%hook BDByteCastNetUtilities

- (BOOL)getVPNStatus {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        return NO;
    }
    return %orig;
}

%end

%hook BDByteCastMonitorManager

- (BOOL)netVPNStatus {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        return NO;
    }
    return %orig;
}

- (void)setNetVPNStatus:(BOOL)netVPNStatus {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        %orig(NO);
        return;
    }
    %orig(netVPNStatus);
}

%end

%hook BDByteCastEnvInfo

- (BOOL)isVPNActive {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        return NO;
    }
    return %orig;
}

- (void)setIsVPNActive:(BOOL)isVPNActive {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        %orig(NO);
        return;
    }
    %orig(isVPNActive);
}

%end

%hook BDByteScreenCastContext

- (BOOL)isVPNActive {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        return NO;
    }
    return %orig;
}

- (void)setIsVPNActive:(BOOL)isVPNActive {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        %orig(NO);
        return;
    }
    %orig(isVPNActive);
}

%end

// 调整直播默认清晰度功能
static NSArray<NSString *> *dyyy_qualityRank = nil;

%hook HTSLiveStreamQualityFragment

- (void)setupStreamQuality:(id)arg1 {
    %orig;

    NSString *preferredQuality = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYLiveQuality"];
    if (!preferredQuality || [preferredQuality isEqualToString:@"自动"]) {
        NSLog(@"[DYYY] Live quality auto - skipping hook");
        return;
    }

    BOOL preferLower = YES;
    NSLog(@"[DYYY] preferredQuality=%@ preferLower=%@", preferredQuality, @(preferLower));

    NSArray *qualities = self.streamQualityArray;
    if (!qualities || qualities.count == 0) {
        qualities = [self getQualities];
    }
    if (!qualities || qualities.count == 0) {
        return;
    }

    if (!dyyy_qualityRank) {
        dyyy_qualityRank = @[ @"蓝光帧彩", @"蓝光", @"超清", @"高清", @"标清" ];
    }
    NSArray *orderedNames = dyyy_qualityRank;

    // Map available names to their indices in the provided order
    NSMutableDictionary<NSString *, NSNumber *> *nameToIndex = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *availableNames = [NSMutableArray array];
    NSMutableArray<NSNumber *> *rankArray = [NSMutableArray array];
    for (NSInteger i = 0; i < qualities.count; i++) {
        id q = qualities[i];
        NSString *name = nil;
        if ([q respondsToSelector:@selector(name)]) {
            name = [q name];
        } else {
            name = [q valueForKey:@"name"];
        }
        if (name) {
            [availableNames addObject:name];
            nameToIndex[name] = @(i);
            NSInteger rank = [orderedNames indexOfObject:name];
            if (rank != NSNotFound) {
                [rankArray addObject:@(rank)];
            }
        }
    }
    NSLog(@"[DYYY] available qualities: %@", availableNames);

    BOOL qualityDesc = YES; // ranks ascending -> high to low
    BOOL qualityAsc = YES;  // ranks descending -> low to high
    for (NSInteger i = 1; i < rankArray.count; i++) {
        NSInteger prev = rankArray[i - 1].integerValue;
        NSInteger curr = rankArray[i].integerValue;
        if (curr < prev) {
            qualityDesc = NO;
        }
        if (curr > prev) {
            qualityAsc = NO;
        }
    }

    NSInteger count = availableNames.count;
    NSInteger (^convertIndex)(NSInteger) = ^NSInteger(NSInteger idx) {
      if (qualityAsc && !qualityDesc) {
          return count - 1 - idx;
      }
      return idx;
    };

    NSArray *searchOrder = orderedNames;

    NSNumber *indexToUse = nameToIndex[preferredQuality];
    if (indexToUse) {
        NSInteger finalIdx = convertIndex(indexToUse.integerValue);
        NSLog(@"[DYYY] exact quality %@ found at index %ld", preferredQuality, (long)finalIdx);
        [self setResolutionWithIndex:finalIdx isManual:YES beginChange:nil completion:nil];
        return;
    }

    NSInteger targetPos = [orderedNames indexOfObject:preferredQuality];
    if (targetPos == NSNotFound) {
        NSLog(@"[DYYY] preferred quality %@ not in list", preferredQuality);
        return;
    }

    NSInteger step = preferLower ? 1 : -1;
    BOOL applied = NO;
    for (NSInteger pos = targetPos + step; pos >= 0 && pos < searchOrder.count; pos += step) {
        NSString *candidate = searchOrder[pos];
        NSNumber *idx = nameToIndex[candidate];
        if (idx) {
            NSInteger finalIdx = convertIndex(idx.integerValue);
            NSLog(@"[DYYY] fallback quality %@ at index %ld", candidate, (long)finalIdx);
            [self setResolutionWithIndex:finalIdx isManual:YES beginChange:nil completion:nil];
            applied = YES;
            break;
        }
    }
    if (!applied) {
        NSLog(@"[DYYY] no suitable fallback quality found");
    }
}

%end

// 强制启用新版抖音长按 UI（现代风）
%hook AWELongPressPanelDataManager
+ (BOOL)enableModernLongPressPanelConfigWithSceneIdentifier:(id)arg1 {
    return DYYYGetBool(@"DYYYEnableModernPanel");
}
%end

%hook AWELongPressPanelABSettings
+ (NSUInteger)modernLongPressPanelStyleMode {
    if (!DYYYGetBool(@"DYYYEnableModernPanel")) {
        return %orig;
    }

    BOOL forceBlur = DYYYGetBool(@"DYYYLongPressPanelBlur");
    BOOL forceDark = DYYYGetBool(@"DYYYLongPressPanelDark");

    if (forceBlur && forceDark) {
        return 1;
    } else if (!forceBlur && !forceDark) {
        BOOL isDarkMode = [DYYYUtils isDarkMode];
        return isDarkMode ? 1 : 2;
    }
}
%end

%hook AWEModernLongPressPanelUIConfig
+ (NSUInteger)modernLongPressPanelStyleMode {
    if (!DYYYGetBool(@"DYYYEnableModernPanel")) {
        return %orig;
    }

    BOOL forceBlur = DYYYGetBool(@"DYYYLongPressPanelBlur");
    BOOL forceDark = DYYYGetBool(@"DYYYLongPressPanelDark");

    if (forceBlur && forceDark) {
        return 1;
    } else if (!forceBlur && !forceDark) {
        BOOL isDarkMode = [DYYYUtils isDarkMode];
        return isDarkMode ? 1 : 2;
    }
}
%end

// 禁用个人资料自动进入橱窗
%hook AWEUserTabListModel

- (NSInteger)profileLandingTab {
    if (DYYYGetBool(@"DYYYDefaultEnterWorks")) {
        return 0;
    } else {
        return %orig;
    }
}

%end

%group AutoPlay

%hook AWEAwemeDetailTableViewController

- (BOOL)hasIphoneAutoPlaySwitch {
    return YES;
}

%end

%hook AWEAwemeDetailContainerPlayControlConfig

- (BOOL)enableUserProfilePostAutoPlay {
    return YES;
}

%end

%hook AWEFeedIPhoneAutoPlayManager

- (BOOL)isAutoPlayOpen {
    return YES;
}

%end

%hook AWEFeedModuleService

- (BOOL)getFeedIphoneAutoPlayState {
    return YES;
}
%end

%hook AWEFeedIPhoneAutoPlayManager

- (BOOL)getFeedIphoneAutoPlayState {
    BOOL r = %orig;
    return YES;
}
%end

%end

%hook AWEPlayInteractionSpeedController

static CGFloat currentLongPressSpeed = 0;
static CGFloat initialTouchX = 0;
static BOOL isGestureActive = NO;

- (CGFloat)longPressFastSpeedValue {
    float longPressSpeed = DYYYGetFloat(@"DYYYLongPressSpeed");
    if (longPressSpeed == 0) {
        longPressSpeed = 2.0;
    }
    return longPressSpeed;
}

- (void)changeSpeed:(double)speed {
    float longPressSpeed = DYYYGetFloat(@"DYYYLongPressSpeed");

    if (isGestureActive && currentLongPressSpeed > 0) {
        %orig(currentLongPressSpeed);
        return;
    }

    if (speed == 2.0 && longPressSpeed != 0 && longPressSpeed != 2.0) {
        %orig(longPressSpeed);
        return;
    }

    if (speed <= 1.0 && dyyyLongPressLockedSpeedActive) {
        DYYYEndLockedLongPressSpeedAndRestoreIfNeeded();
    }

    %orig(speed);
}

- (void)handleLongPressFastSpeed:(UILongPressGestureRecognizer *)gesture {
    BOOL enableSpeedGesture = DYYYGetBool(@"DYYYEnableLongPressSpeedGesture");
    CGPoint location = [gesture locationInView:gesture.view];
    static CGFloat initialTouchY = 0;
    BOOL isBeginning = gesture.state == UIGestureRecognizerStateBegan;
    BOOL isEnding = gesture.state == UIGestureRecognizerStateEnded ||
                    gesture.state == UIGestureRecognizerStateCancelled ||
                    gesture.state == UIGestureRecognizerStateFailed;

    if (isBeginning) {
        dyyyLongPressFastSpeedActive = YES;
        dyyyLongPressLockedSpeedActive = NO;
    } else if (isEnding) {
        isGestureActive = NO;
        currentLongPressSpeed = 0;
        initialTouchY = 0;
        dyyyLongPressFastSpeedActive = NO;
    }

    %orig;

    if (isEnding) {
        DYYYScheduleConfiguredPlaybackSpeedRestore();
    }

    if (!enableSpeedGesture) {
        return;
    }

    if (isBeginning) {
        initialTouchY = location.y;
        isGestureActive = YES;

        float longPressSpeed = DYYYGetFloat(@"DYYYLongPressSpeed");
        if (longPressSpeed == 0) {
            longPressSpeed = 2.0;
        }
        currentLongPressSpeed = longPressSpeed;
    }
    else if (gesture.state == UIGestureRecognizerStateChanged && isGestureActive) {
        CGFloat deltaY = location.y - initialTouchY;
        CGFloat threshold = 10.0;

        if (fabs(deltaY) > threshold) {
            CGFloat speedChange;
            speedChange = (deltaY > 0) ? 0.25 : -0.25;

            CGFloat newSpeed = currentLongPressSpeed + speedChange;
            newSpeed = MAX(0.5, MIN(3.0, newSpeed));

            if (newSpeed != currentLongPressSpeed) {
                currentLongPressSpeed = newSpeed;
                initialTouchY = location.y;
                [self changeSpeed:currentLongPressSpeed];
            }
        }
    }
}

- (void)handleLongPressLockedSpeedBegan {
    dyyyLongPressFastSpeedActive = YES;
    dyyyLongPressLockedSpeedActive = NO;
    %orig;
}

- (void)handleLongPressLockedDoubleSpeedChanged:(id)arg1 gesture:(UIGestureRecognizer *)gesture {
    dyyyLongPressFastSpeedActive = YES;
    dyyyLongPressLockedSpeedActive = NO;
    %orig(arg1, gesture);
}

- (void)handleLongPressLockedDoubleSpeedEnded:(id)arg1 gesture:(UIGestureRecognizer *)gesture {
    %orig(arg1, gesture);
    dyyyLongPressFastSpeedActive = NO;
    dyyyLongPressLockedSpeedActive = YES;
}

- (void)longPressSpeedControlDidChangeSpeed:(double)speed {
    %orig(speed);
    if (speed <= 1.0 && dyyyLongPressLockedSpeedActive) {
        DYYYEndLockedLongPressSpeedAndRestoreIfNeeded();
    }
}
%end

%hook UILabel

- (void)setText:(NSString *)text {
    UIView *superview = self.superview;

    if ([superview isKindOfClass:%c(AFDFastSpeedView)] && text) {
        CGFloat displaySpeed = isGestureActive && currentLongPressSpeed > 0 ? currentLongPressSpeed : DYYYGetFloat(@"DYYYLongPressSpeed");
        if (displaySpeed == 0) {
            displaySpeed = 2.0;
        }

        NSString *speedString = [NSString stringWithFormat:@"%.2f", displaySpeed];
        if ([speedString hasSuffix:@".00"]) {
            speedString = [speedString substringToIndex:speedString.length - 3];
        } else if ([speedString hasSuffix:@"0"] && [speedString containsString:@"."]) {
            speedString = [speedString substringToIndex:speedString.length - 1];
        }

        if ([text containsString:@"2"]) {
            text = [text stringByReplacingOccurrencesOfString:@"2" withString:speedString];
        }
    }

    %orig(text);
}
%end

// 强制启用保存他人头像
%hook AFDProfileAvatarFunctionManager
- (BOOL)shouldShowSaveAvatarItem {
    BOOL shouldEnable = DYYYGetBool(@"DYYYEnableSaveAvatar");
    if (shouldEnable) {
        return YES;
    }
    return %orig;
}
%end

%hook AWECommentMediaDownloadConfigLivePhoto

BOOL commentLivePhotoNotWaterMark = DYYYGetBool(@"DYYYCommentLivePhotoNotWaterMark");

- (BOOL)needClientWaterMark {
    return commentLivePhotoNotWaterMark ? 0 : %orig;
}

- (BOOL)needClientEndWaterMark {
    return commentLivePhotoNotWaterMark ? 0 : %orig;
}

- (id)watermarkConfig {
    return commentLivePhotoNotWaterMark ? nil : %orig;
}

%end

%hook AWECommentImageModel
- (id)downloadUrl {
    if (DYYYGetBool(@"DYYYCommentNotWaterMark")) {
        return self.originUrl;
    }
    return %orig;
}
%end

%group EnableStickerSaveMenu
static __weak YYAnimatedImageView *targetStickerView = nil;
static BOOL dyyyShouldUseLastStickerURL = NO;

%hook _TtCV28AWECommentPanelListSwiftImpl6NEWAPI27CommentCellStickerComponent

- (void)handleLongPressWithGes:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if ([gesture.view isKindOfClass:%c(YYAnimatedImageView)]) {
            targetStickerView = (YYAnimatedImageView *)gesture.view;
            NSLog(@"DYYY 长按表情：%@", targetStickerView);
        } else {
            targetStickerView = nil;
        }
    }

    %orig;
}

%end

%hook _TtC33AWECommentLongPressPanelSwiftImpl37CommentLongPressPanelSaveImageElement

- (BOOL)elementShouldShow {
    BOOL shouldShow = %orig;
    if (!DYYYGetBool(@"DYYYForceDownloadEmotion") && !DYYYGetBool(@"DYYYForceDownloadCommentAudio")) {
        return shouldShow;
    }
    AWECommentLongPressPanelContext *context = [self commentPageContext];
    AWECommentModel *selected = [context selectdComment] ?: [[context params] selectdComment];
    AWEIMStickerModel *sticker = [selected sticker];
    NSArray *originURLList = sticker.staticURLModel.originURLList;
    if (originURLList.count > 0) {
        return YES;
    }
    AWECommentAudioModel *audio = [selected audioModel];
    if (audio && audio.content) {
        return YES;
    }
    return shouldShow;
}

- (void)elementTapped {
    AWECommentLongPressPanelContext *context = [self commentPageContext];
    AWECommentLongPressPanelParam *params = [context params];
    AWECommentModel *comment = [context selectdComment] ?: [params selectdComment];
    
    // 判断保存类型(表情包/音频/图片)
    AWEIMStickerModel *sticker = [comment sticker];
    NSArray *stickerURLList = sticker.staticURLModel.originURLList;
    BOOL hasSticker = (stickerURLList.count > 0);

    AWECommentAudioModel *audio = [comment audioModel];
    BOOL hasAudio = (audio && audio.content);
    
    NSArray *imageList = nil;
    if ([comment respondsToSelector:@selector(imageList)]) {
        imageList = [comment imageList];
    }
    BOOL hasImages = (imageList && imageList.count > 0);
    
    // 表情包保存逻辑
    if (hasSticker && DYYYGetBool(@"DYYYForceDownloadEmotion")) {
        NSString *urlString = dyyyShouldUseLastStickerURL ? stickerURLList.lastObject : stickerURLList.firstObject;
        dyyyShouldUseLastStickerURL = NO;
        NSURL *stickerURL = [NSURL URLWithString:urlString];
        
        if (stickerURL) {
            [DYYYManager downloadMedia:stickerURL
                             mediaType:MediaTypeHeic
                                 audio:nil
                            completion:^(BOOL success) {
                              if (!success && stickerURLList.count > 1) {
                                  dyyyShouldUseLastStickerURL = YES;
                              }
                            }];
            return;
        }
    }

    // 音频保存逻辑
    if (hasAudio && DYYYGetBool(@"DYYYForceDownloadCommentAudio")) {
        NSString *audioContent = audio.content;
        
        NSString *userName = @"未知用户";
        if (comment.author && [comment.author respondsToSelector:@selector(nickname)]) {
            NSString *nickname = [comment.author performSelector:@selector(nickname)];
            if (nickname && nickname.length > 0) {
                userName = nickname;
            }
        }
        
        [DYYYManager downloadAndShareCommentAudio:audioContent
                                         userName:userName
                                       createTime:comment.createTime];
        return;
    }

    // 图片保存逻辑
    if (hasImages && DYYYGetBool(@"DYYYForceDownloadCommentImage")) {
        // 检查 is_pic_inflow 判断是保存全部还是单张
        // is_pic_inflow = 1: 点开具体图片后长按 -> 只保存当前图片
        // is_pic_inflow = 0: 直接在评论区长按 -> 保存全部图片
        NSDictionary *extraParams = [params extraParams];
        BOOL isPicInflow = NO;
        if (extraParams && [extraParams isKindOfClass:[NSDictionary class]]) {
            id isPicInflowValue = extraParams[@"is_pic_inflow"];
            if (isPicInflowValue) {
                isPicInflow = [isPicInflowValue integerValue] == 1;
            }
        }
        
        NSInteger currentIndex = -1; // -1 表示保存全部
        
        if (isPicInflow) {
            // 使用 DYYYUtils 封装的方法查找目标控制器
            UIViewController *topVC = [DYYYUtils topView];
            
            // 获取 Ivar 定义的类和目标控制器类
            Class ivarClass = NSClassFromString(@"AWECommentMediaFeedSwfitImpl.CommentMediaFeedCellViewController");
            Class targetClass = NSClassFromString(@"AWECommentMediaFeedSwfitImpl.CommentMediaFeedCommonImageCellViewController");
            
            if (ivarClass && targetClass && topVC) {
                Ivar multiIndexIvar = class_getInstanceVariable(ivarClass, "currentIndexInMultiImageList");
                if (multiIndexIvar) {
                    UIViewController *cellVC = [DYYYUtils findViewControllerOfClass:targetClass inViewController:topVC];
                    if (cellVC) {
                        ptrdiff_t offset = ivar_getOffset(multiIndexIvar);
                        NSInteger *ptr = (NSInteger *)((char *)(__bridge void *)cellVC + offset);
                        currentIndex = *ptr;
                    }
                }
            }
        }
        
        [DYYYManager saveCommentImages:imageList
                            currentIndex:currentIndex
                            completion:nil];
        return;
    }
    
    // 默认行为
    %orig;
}

%end

%hook UIMenu

+ (instancetype)menuWithTitle:(NSString *)title image:(UIImage *)image identifier:(UIMenuIdentifier)identifier options:(UIMenuOptions)options children:(NSArray<UIMenuElement *> *)children {
    BOOL hasAddStickerOption = NO;
    BOOL hasSaveLocalOption = NO;

    for (UIMenuElement *element in children) {
        NSString *elementTitle = nil;

        if ([element isKindOfClass:%c(UIAction)]) {
            elementTitle = [(UIAction *)element title];
        } else if ([element isKindOfClass:%c(UICommand)]) {
            elementTitle = [(UICommand *)element title];
        }

        if ([elementTitle isEqualToString:@"添加到表情"]) {
            hasAddStickerOption = YES;
        } else if ([elementTitle isEqualToString:@"保存到相册"]) {
            hasSaveLocalOption = YES;
        }
    }

    if (hasAddStickerOption && !hasSaveLocalOption) {
        NSMutableArray *newChildren = [children mutableCopy];

        UIAction *saveAction = [%c(UIAction) actionWithTitle:@"保存到相册"
                                                                 image:nil
                                                            identifier:nil
                                                               handler:^(__kindof UIAction *_Nonnull action) {
                                                                 // 使用全局变量 targetStickerView 保存当前长按的表情
                                                                 if (targetStickerView) {
                                                                     [DYYYManager saveAnimatedSticker:targetStickerView];
                                                                 } else {
                                                                     [DYYYUtils showToast:@"无法获取表情视图"];
                                                                 }
                                                               }];

        [newChildren addObject:saveAction];
        return %orig(title, image, identifier, options, newChildren);
    }

    return %orig;
}

%end
%end

%hook AWEIMEmoticonPreviewV2

// 添加保存按钮
- (void)layoutSubviews {
    %orig;
    static char kHasSaveButtonKey;
    BOOL DYYYForceDownloadPreviewEmotion = DYYYGetBool(@"DYYYForceDownloadPreviewEmotion");
    if (DYYYForceDownloadPreviewEmotion) {
        if (!objc_getAssociatedObject(self, &kHasSaveButtonKey)) {
            UIButton *saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
            UIImage *downloadIcon = [UIImage systemImageNamed:@"arrow.down.circle"];
            [saveButton setImage:downloadIcon forState:UIControlStateNormal];
            [saveButton setTintColor:[UIColor whiteColor]];
            saveButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.9 alpha:0.5];

            saveButton.layer.shadowColor = [UIColor blackColor].CGColor;
            saveButton.layer.shadowOffset = CGSizeMake(0, 2);
            saveButton.layer.shadowOpacity = 0.3;
            saveButton.layer.shadowRadius = 3;

            saveButton.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:saveButton];
            CGFloat buttonSize = 24.0;
            saveButton.layer.cornerRadius = buttonSize / 2;

            [NSLayoutConstraint activateConstraints:@[
                [saveButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-15], [saveButton.rightAnchor constraintEqualToAnchor:self.rightAnchor constant:-10],
                [saveButton.widthAnchor constraintEqualToConstant:buttonSize], [saveButton.heightAnchor constraintEqualToConstant:buttonSize]
            ]];

            saveButton.userInteractionEnabled = YES;
            [saveButton addTarget:self action:@selector(dyyy_saveButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            objc_setAssociatedObject(self, &kHasSaveButtonKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

%new
- (void)dyyy_saveButtonTapped:(UIButton *)sender {
    // 获取表情包URL
    AWEIMEmoticonModel *emoticonModel = self.model;
    if (!emoticonModel) {
        [DYYYUtils showToast:@"无法获取表情包信息"];
        return;
    }

    NSString *urlString = nil;
    MediaType mediaType = MediaTypeImage;

    // 尝试动态URL
    if ([emoticonModel valueForKey:@"animate_url"]) {
        urlString = [emoticonModel valueForKey:@"animate_url"];
    }
    // 如果没有动态URL，则使用静态URL
    else if ([emoticonModel valueForKey:@"static_url"]) {
        urlString = [emoticonModel valueForKey:@"static_url"];
    }
    // 使用animateURLModel获取URL
    else if ([emoticonModel valueForKey:@"animateURLModel"]) {
        AWEURLModel *urlModel = [emoticonModel valueForKey:@"animateURLModel"];
        if (urlModel.originURLList.count > 0) {
            urlString = urlModel.originURLList[0];
        }
    }

    if (!urlString) {
        [DYYYUtils showToast:@"无法获取表情包链接"];
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    [DYYYManager downloadMedia:url
                     mediaType:MediaTypeHeic
                         audio:nil
                    completion:^(BOOL success){
                    }];
}

%end

static NSString *DYYYIMMessageStringValue(id object, NSString *selectorName) {
    if (!object || selectorName.length == 0) {
        return nil;
    }
    SEL selector = NSSelectorFromString(selectorName);
    if (!selector || ![object respondsToSelector:selector]) {
        return nil;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id value = [object performSelector:selector];
#pragma clang diagnostic pop
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
        return value;
    }
    return nil;
}

static NSURL *DYYYIMEmotionDownloadURLFromMessage(AWEIMGiphyMessage *giphyMessage) {
    if (!giphyMessage) {
        return nil;
    }
    NSString *urlString = nil;
    if (giphyMessage.giphyURL.originURLList.count > 0) {
        urlString = giphyMessage.giphyURL.originURLList.firstObject;
    }
    if (urlString.length == 0) {
        NSString *animateURL = DYYYIMMessageStringValue(giphyMessage, @"animateURL");
        if (animateURL.length > 0) {
            urlString = animateURL;
        }
    }
    if (urlString.length == 0) {
        NSString *displayIconURL = DYYYIMMessageStringValue(giphyMessage, @"displayIconURL");
        if (displayIconURL.length > 0) {
            urlString = displayIconURL;
        }
    }
    if (urlString.length == 0) {
        return nil;
    }
    return [NSURL URLWithString:urlString];
}

static AWEIMCustomMenuModel *DYYYIMCreateDownloadMenuItem(AWEIMReusableCommonCell *cell) {
    if (!cell) {
        return nil;
    }
    __weak AWEIMReusableCommonCell *weakCell = cell;
    AWEIMCustomMenuModel *menuItem = [%c(AWEIMCustomMenuModel) new];
    menuItem.title = @"保存表情";
    menuItem.imageName = @"im_emoticon_interactive_tab_new";
    menuItem.trackerName = @"保存表情";
    menuItem.willPerformMenuActionSelectorBlock = ^(id arg1) {
      AWEIMReusableCommonCell *strongCell = weakCell;
      if (!strongCell) {
          [DYYYUtils showToast:@"无法获取表情包信息"];
          return;
      }
      AWEIMMessageComponentContext *context = (AWEIMMessageComponentContext *)strongCell.currentContext;
      if (!context || ![context.message isKindOfClass:%c(AWEIMGiphyMessage)]) {
          [DYYYUtils showToast:@"无法获取表情包信息"];
          return;
      }
      NSURL *downloadURL = DYYYIMEmotionDownloadURLFromMessage((AWEIMGiphyMessage *)context.message);
      if (!downloadURL) {
          [DYYYUtils showToast:@"无法获取表情包链接"];
          return;
      }
      [DYYYManager downloadMedia:downloadURL
                       mediaType:MediaTypeHeic
                           audio:nil
                      completion:^(BOOL success){
                      }];
    };
    return menuItem;
}

static NSArray *DYYYIMMenuItemsByAddingDownloadAction(NSArray *menuItems, id cell) {
    if (!DYYYGetBool(@"DYYYForceDownloadIMEmotion")) {
        return menuItems;
    }
    if (!menuItems || !cell) {
        return menuItems;
    }
    AWEIMReusableCommonCell *commonCell = [cell isKindOfClass:%c(AWEIMReusableCommonCell)] ? (AWEIMReusableCommonCell *)cell : nil;
    if (!commonCell) {
        return menuItems;
    }
    AWEIMMessageComponentContext *context = (AWEIMMessageComponentContext *)commonCell.currentContext;
    if (!context || ![context.message isKindOfClass:%c(AWEIMGiphyMessage)]) {
        return menuItems;
    }
    for (AWEIMCustomMenuModel *item in menuItems) {
        if ([item isKindOfClass:%c(AWEIMCustomMenuModel)] && [item.title isEqualToString:@"保存表情"]) {
            return menuItems;
        }
    }
    NSMutableArray *newMenuItems = [menuItems mutableCopy];
    AWEIMCustomMenuModel *downloadItem = DYYYIMCreateDownloadMenuItem(commonCell);
    if (downloadItem) {
        [newMenuItems addObject:downloadItem];
    }
    return newMenuItems ?: menuItems;
}

%group DYYYIMMenuLegacyGroup
%hook AWEIMCustomMenuComponent
- (void)msg_showMenuForBubbleFrameInScreen:(CGRect)bubbleFrame tapLocationInScreen:(CGPoint)tapLocation menuItemList:(NSArray *)menuItems moreEmoticon:(BOOL)moreEmoticon onCell:(id)cell extra:(id)extra {
    NSArray *updatedMenuItems = DYYYIMMenuItemsByAddingDownloadAction(menuItems, cell);
    %orig(bubbleFrame, tapLocation, updatedMenuItems, moreEmoticon, cell, extra);
}
%end
%end

%group DYYYIMMenuTapLocationGroup
%hook AWEIMCustomMenuComponent
- (void)msg_showMenuForBubbleFrameInScreen:(CGRect)bubbleFrame tapLocationInScreen:(CGPoint)tapLocation menuItemList:(NSArray *)menuItems menuPanelOptions:(unsigned long long)menuPanelOptions moreEmoticon:(BOOL)moreEmoticon onCell:(id)cell extra:(id)extra {
    NSArray *updatedMenuItems = DYYYIMMenuItemsByAddingDownloadAction(menuItems, cell);
    %orig(bubbleFrame, tapLocation, updatedMenuItems, menuPanelOptions, moreEmoticon, cell, extra);
}
%end
%end

%group DYYYIMMenuHighLowGroup
%hook AWEIMCustomMenuComponent
- (void)msg_showMenuForBubbleFrameInScreen:(CGRect)bubbleFrame highLocationInScreen:(CGPoint)highLocation lowLocationInScreen:(CGPoint)lowLocation tryHighLocationFirst:(BOOL)tryHighLocationFirst menuItemList:(NSArray *)menuItems menuPanelOptions:(unsigned long long)menuPanelOptions onCell:(id)cell extra:(id)extra {
    NSArray *updatedMenuItems = DYYYIMMenuItemsByAddingDownloadAction(menuItems, cell);
    %orig(bubbleFrame, highLocation, lowLocation, tryHighLocationFirst, updatedMenuItems, menuPanelOptions, cell, extra);
}
%end
%end

%hook AWEFeedTabJumpGuideView

- (void)layoutSubviews {
    %orig;
    [self removeFromSuperview];
}

%end

%hook AWEFeedLiveMarkView
- (void)setHidden:(BOOL)hidden {
    if (DYYYGetBool(@"DYYYHideAvatarLive") || DYYYGetBool(@"DYYYHideAvatarButton")) {
        hidden = YES;
    }

    %orig(hidden);
}
%end

static id DYYYAvatarObjectForSelector(id object, SEL selector) {
    if (!object || !selector || ![object respondsToSelector:selector]) {
        return nil;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [object performSelector:selector];
#pragma clang diagnostic pop
}

static UIView *DYYYAvatarViewForSelector(id object, SEL selector) {
    id value = DYYYAvatarObjectForSelector(object, selector);
    return [value isKindOfClass:[UIView class]] ? value : nil;
}

static char kDYYYAvatarFollowDeferredApplyKey;
static char kDYYYAvatarFollowScopeViewKey;
static char kDYYYAvatarActionHiddenViewKey;
static char kDYYYAvatarActionRemovedViewKey;
static char kDYYYAvatarActionChromeViewKey;
static char kDYYYAvatarActionHiddenLayerKey;
static char kDYYYAvatarActionChromeLayerKey;
static char kDYYYAvatarSurroundingHiddenViewKey;

static BOOL DYYYAvatarFollowOptionsEnabled(void) {
    return DYYYGetBool(@"DYYYHideLOTAnimationView") || DYYYGetBool(@"DYYYHideFollowPromptView");
}

static BOOL DYYYShouldForceHideAvatarActionLayer(CALayer *layer) {
    return layer && objc_getAssociatedObject(layer, &kDYYYAvatarActionHiddenLayerKey) && DYYYAvatarFollowOptionsEnabled();
}

static BOOL DYYYShouldClearAvatarActionLayer(CALayer *layer) {
    if (!layer || (!objc_getAssociatedObject(layer, &kDYYYAvatarActionChromeLayerKey) &&
                   !objc_getAssociatedObject(layer, &kDYYYAvatarActionHiddenLayerKey))) {
        return NO;
    }
    return DYYYAvatarFollowOptionsEnabled();
}

static void DYYYMarkAvatarActionLayerHidden(CALayer *layer) {
    if (!layer) {
        return;
    }

    objc_setAssociatedObject(layer, &kDYYYAvatarActionHiddenLayerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    layer.hidden = YES;
    for (CALayer *sublayer in [layer.sublayers copy]) {
        DYYYMarkAvatarActionLayerHidden(sublayer);
    }
}

static void DYYYMarkAvatarActionLayerChrome(CALayer *layer) {
    if (!layer) {
        return;
    }

    objc_setAssociatedObject(layer, &kDYYYAvatarActionChromeLayerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    layer.contents = nil;
    layer.opaque = NO;
    layer.backgroundColor = UIColor.clearColor.CGColor;
    layer.borderWidth = 0.0;
    layer.borderColor = UIColor.clearColor.CGColor;
    layer.shadowOpacity = 0.0;
    layer.shadowColor = UIColor.clearColor.CGColor;
    if ([layer isKindOfClass:[CAShapeLayer class]]) {
        CAShapeLayer *shapeLayer = (CAShapeLayer *)layer;
        shapeLayer.fillColor = UIColor.clearColor.CGColor;
        shapeLayer.strokeColor = UIColor.clearColor.CGColor;
    }

    for (CALayer *sublayer in [layer.sublayers copy]) {
        DYYYMarkAvatarActionLayerHidden(sublayer);
    }
}

static void DYYYPrepareAvatarActionSublayer(CALayer *parentLayer, CALayer *sublayer) {
    if (!parentLayer || !sublayer) {
        return;
    }

    BOOL isSuppressedTree = objc_getAssociatedObject(parentLayer, &kDYYYAvatarActionChromeLayerKey) ||
                            objc_getAssociatedObject(parentLayer, &kDYYYAvatarActionHiddenLayerKey);
    if (isSuppressedTree && DYYYAvatarFollowOptionsEnabled()) {
        DYYYMarkAvatarActionLayerHidden(sublayer);
    }
}

static void DYYYMarkAvatarActionViewHidden(UIView *view) {
    if (!view) {
        return;
    }

    objc_setAssociatedObject(view, &kDYYYAvatarActionHiddenViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.hidden = YES;
}

static BOOL DYYYShouldForceAvatarActionViewHidden(UIView *view) {
    if (!view) {
        return NO;
    }

    BOOL hideVisual = objc_getAssociatedObject(view, &kDYYYAvatarActionHiddenViewKey) != nil;
    BOOL removeView = objc_getAssociatedObject(view, &kDYYYAvatarActionRemovedViewKey) != nil;
    if (!hideVisual && !removeView) {
        return NO;
    }
    return (hideVisual && DYYYAvatarFollowOptionsEnabled()) || (removeView && DYYYGetBool(@"DYYYHideFollowPromptView"));
}

static BOOL DYYYShouldClearAvatarActionViewChrome(UIView *view) {
    return view && objc_getAssociatedObject(view, &kDYYYAvatarActionChromeViewKey) && DYYYGetBool(@"DYYYHideLOTAnimationView");
}

static void DYYYHideAvatarVisualForSelector(id object, SEL selector) {
    UIView *view = DYYYAvatarViewForSelector(object, selector);
    if (view) {
        view.hidden = YES;
    }
}

static void DYYYMarkAvatarSurroundingViewHidden(UIView *view) {
    if (!view) {
        return;
    }

    objc_setAssociatedObject(view, &kDYYYAvatarSurroundingHiddenViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.hidden = YES;
    view.userInteractionEnabled = NO;
}

static BOOL DYYYShouldForceAvatarSurroundingViewHidden(UIView *view) {
    return view && objc_getAssociatedObject(view, &kDYYYAvatarSurroundingHiddenViewKey) && DYYYGetBool(@"DYYYHideAvatarButton");
}

static void DYYYHideAvatarSurroundingVisualForSelector(id object, SEL selector) {
    UIView *view = DYYYAvatarViewForSelector(object, selector);
    DYYYMarkAvatarSurroundingViewHidden(view);
}

static void DYYYApplyAvatarSurroundingSettingsForOwner(id owner) {
    if (!owner || !DYYYGetBool(@"DYYYHideAvatarButton")) {
        return;
    }

    for (NSString *selectorName in @[
             @"colorRingView",
             @"storyRingView",
             @"story25RingView",
             @"decorationView",
             @"avatarDecorationView",
             @"avatarPendantView",
             @"avatarLiveMarkView",
             @"liveMarkView",
             @"avatarLiveTagView",
             @"liveTagView",
         ]) {
        DYYYHideAvatarSurroundingVisualForSelector(owner, NSSelectorFromString(selectorName));
    }
}

static void DYYYRemoveAvatarView(UIView *view) {
    if (!view) {
        return;
    }
    objc_setAssociatedObject(view, &kDYYYAvatarActionRemovedViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.hidden = YES;
    view.userInteractionEnabled = NO;
}

static void DYYYRemoveAvatarViewForSelector(id object, SEL selector) {
    UIView *view = DYYYAvatarViewForSelector(object, selector);
    DYYYRemoveAvatarView(view);
}

static void DYYYHideAvatarFollowLayerContents(UIView *view) {
    if (!view) {
        return;
    }
    objc_setAssociatedObject(view, &kDYYYAvatarActionChromeViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    DYYYMarkAvatarActionLayerChrome(view.layer);
}

static void DYYYClearAvatarActionLayerChrome(CALayer *layer) {
    DYYYMarkAvatarActionLayerChrome(layer);
}

static void DYYYClearAvatarActionSubviewChrome(UIView *view) {
    if (!view) {
        return;
    }

    objc_setAssociatedObject(view, &kDYYYAvatarActionChromeViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    DYYYClearAvatarActionLayerChrome(view.layer);

    for (UIView *subview in [view.subviews copy]) {
        DYYYClearAvatarActionSubviewChrome(subview);
    }
}

static void DYYYClearAvatarActionViewChrome(UIView *view) {
    if (!view) {
        return;
    }

    objc_setAssociatedObject(view, &kDYYYAvatarActionChromeViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    DYYYClearAvatarActionLayerChrome(view.layer);

    for (UIView *subview in [view.subviews copy]) {
        DYYYClearAvatarActionSubviewChrome(subview);
    }
}

static BOOL DYYYIsLegacyAvatarFollowAnimationView(UIView *view) {
    Class promptClass = NSClassFromString(@"AWEPlayInteractionFollowPromptView");
    UIView *ancestor = view.superview;
    for (NSInteger depth = 0; ancestor && depth < 6; depth++, ancestor = ancestor.superview) {
        if (promptClass && [ancestor isKindOfClass:promptClass]) {
            return YES;
        }
    }
    return NO;
}

static BOOL DYYYHideAvatarFollowIconInView(UIView *view) {
    if (!view) {
        return NO;
    }

    NSString *className = NSStringFromClass(view.class);
    if ([className isEqualToString:@"LOTAnimationView"]) {
        DYYYHideAvatarFollowLayerContents(view);
        return YES;
    }

    if ([className isEqualToString:@"AWEPlayInteractionStaticFollowAnimationView"]) {
        BOOL foundIcon = NO;
        for (NSString *selectorName in @[ @"plusImageView", @"tickImageView" ]) {
            UIView *iconView = DYYYAvatarViewForSelector(view, NSSelectorFromString(selectorName));
            if (iconView) {
                DYYYMarkAvatarActionViewHidden(iconView);
                foundIcon = YES;
            }
        }
        if (!foundIcon) {
            DYYYHideAvatarFollowLayerContents(view);
        }
        return YES;
    }

    BOOL foundIcon = NO;
    for (UIView *subview in view.subviews) {
        foundIcon = DYYYHideAvatarFollowIconInView(subview) || foundIcon;
    }
    return foundIcon;
}

static BOOL DYYYIsAvatarFollowContainerView(UIView *view) {
    NSString *className = NSStringFromClass(view.class);
    return [className containsString:@"Follow"] || [className containsString:@"follow"] ||
           [className containsString:@"Prompt"] || [className containsString:@"Add"] ||
           [className containsString:@"SendMessage"] || [className containsString:@"sendMessage"] ||
           [className containsString:@"SendMsg"] || [className containsString:@"sendMsg"] ||
           [className containsString:@"EnterStore"] || [className containsString:@"enterStore"] ||
           [className containsString:@"LinkIcon"] || [className containsString:@"linkIcon"];
}

static BOOL DYYYIsSmallAvatarFollowBadgeView(UIView *view) {
    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat height = CGRectGetHeight(view.bounds);
    return width > 0.0 && height > 0.0 && width <= 52.0 && height <= 52.0;
}

static UIView *DYYYAvatarFollowRemovalTargetForView(UIView *view, UIView *rootView) {
    UIView *target = view;
    UIView *ancestor = view.superview;
    while (ancestor && ancestor != rootView) {
        if (DYYYIsAvatarFollowContainerView(ancestor) || DYYYIsSmallAvatarFollowBadgeView(ancestor)) {
            target = ancestor;
            ancestor = ancestor.superview;
            continue;
        }
        break;
    }
    return target;
}

static BOOL DYYYHideAvatarAuxiliaryActionVisualsInView(UIView *view) {
    if (!view) {
        return NO;
    }

    NSString *className = NSStringFromClass(view.class);
    BOOL isActionVisual = [view isKindOfClass:[UIImageView class]] ||
                          [className containsString:@"GuideAnimation"] ||
                          [className containsString:@"SendMessageImage"] ||
                          [className containsString:@"SendMsgImage"] ||
                          [className containsString:@"EnterStoreImage"] ||
                          [className containsString:@"LinkIcon"];
    if (isActionVisual) {
        DYYYMarkAvatarActionViewHidden(view);
        return YES;
    }

    BOOL foundVisual = NO;
    for (UIView *subview in [view.subviews copy]) {
        foundVisual = DYYYHideAvatarAuxiliaryActionVisualsInView(subview) || foundVisual;
    }
    return foundVisual;
}

static NSArray<NSArray<NSString *> *> *DYYYAvatarAuxiliaryActionSelectorGroups(void) {
    return @[
        @[ @"sendMessageView", @"avatarSendMessageImageView", @"sendMessageGuideView" ],
        @[ @"enterStoreView", @"avatarEnterStoreImageView", @"enterStoreGuideView" ],
        @[ @"linkIconContainerView", @"userAvatarLinkIcon" ],
    ];
}

static BOOL DYYYApplyAvatarAuxiliaryActionSettingsForOwner(id owner) {
    BOOL hidePlus = DYYYGetBool(@"DYYYHideLOTAnimationView");
    BOOL removePlus = DYYYGetBool(@"DYYYHideFollowPromptView");
    if (!hidePlus && !removePlus) {
        return NO;
    }

    BOOL handled = NO;
    for (NSArray<NSString *> *selectorGroup in DYYYAvatarAuxiliaryActionSelectorGroups()) {
        UIView *containerView = DYYYAvatarViewForSelector(owner, NSSelectorFromString(selectorGroup.firstObject));
        NSMutableArray<UIView *> *visualViews = [NSMutableArray array];
        for (NSUInteger index = 1; index < selectorGroup.count; index++) {
            UIView *visualView = DYYYAvatarViewForSelector(owner, NSSelectorFromString(selectorGroup[index]));
            if (visualView) {
                [visualViews addObject:visualView];
            }
        }

        if (removePlus) {
            UIView *fallbackVisual = visualViews.firstObject;
            UIView *removalTarget = containerView ?: DYYYAvatarFollowRemovalTargetForView(fallbackVisual, nil);
            DYYYRemoveAvatarView(removalTarget);
            for (UIView *visualView in visualViews) {
                DYYYRemoveAvatarView(visualView);
            }
            handled = (removalTarget || visualViews.count > 0) || handled;
            continue;
        }

        for (UIView *visualView in visualViews) {
            visualView.hidden = YES;
            handled = YES;
        }
        if (containerView) {
            DYYYClearAvatarActionViewChrome(containerView);
            BOOL foundVisual = DYYYHideAvatarAuxiliaryActionVisualsInView(containerView);
            if (!foundVisual && visualViews.count == 0) {
                DYYYHideAvatarFollowLayerContents(containerView);
            }
            handled = YES;
        }
    }
    return handled;
}

static BOOL DYYYApplyAvatarFollowSettingsInView(UIView *view, UIView *rootView) {
    if (!view) {
        return NO;
    }

    BOOL hidePlus = DYYYGetBool(@"DYYYHideLOTAnimationView");
    BOOL removePlus = DYYYGetBool(@"DYYYHideFollowPromptView");
    if (!hidePlus && !removePlus) {
        return NO;
    }

    // 记录已识别的头像操作树，便于异步追加子视图时立即再识别。
    objc_setAssociatedObject(view, &kDYYYAvatarFollowScopeViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSString *className = NSStringFromClass(view.class);
    BOOL isAvatarView = [className isEqualToString:@"AWEPlayInteractionUserAvatarView"];
    BOOL isStaticFollowView = [className isEqualToString:@"AWEPlayInteractionStaticFollowAnimationView"];
    BOOL isLegacyFollowAnimation = [className isEqualToString:@"LOTAnimationView"] && DYYYIsLegacyAvatarFollowAnimationView(view);
    BOOL isLegacyPromptContainer = [className isEqualToString:@"AWEPlayInteractionFollowPromptView"];
    BOOL handled = NO;

    if (isAvatarView) {
        handled = DYYYApplyAvatarAuxiliaryActionSettingsForOwner(view) || handled;
    }

    if (isStaticFollowView || isLegacyFollowAnimation) {
        if (removePlus) {
            DYYYRemoveAvatarView(DYYYAvatarFollowRemovalTargetForView(view, rootView));
        } else {
            DYYYHideAvatarFollowIconInView(view);
        }
        handled = YES;
    } else if (removePlus && isLegacyPromptContainer) {
        view.hidden = YES;
        view.userInteractionEnabled = NO;
        handled = YES;
    }

    for (UIView *subview in [view.subviews copy]) {
        handled = DYYYApplyAvatarFollowSettingsInView(subview, rootView) || handled;
    }
    return handled;
}

static void DYYYApplyAvatarFollowSettingsForContext(id context) {
    UIView *elementView = DYYYAvatarViewForSelector(context, NSSelectorFromString(@"elementView"));
    if (elementView) {
        DYYYApplyAvatarFollowSettingsInView(elementView, elementView);
    }
}

static void DYYYApplyAvatarFollowPromptSettings(id owner) {
    BOOL hidePlus = DYYYGetBool(@"DYYYHideLOTAnimationView");
    BOOL removePlus = DYYYGetBool(@"DYYYHideFollowPromptView");
    if (!hidePlus && !removePlus) {
        return;
    }

    for (NSString *selectorName in @[ @"followAnimationView", @"unfollowAnimationView", @"staticFollowAnimationView" ]) {
        UIView *animationView = DYYYAvatarViewForSelector(owner, NSSelectorFromString(selectorName));
        if (!animationView) {
            continue;
        }
        if (removePlus) {
            DYYYRemoveAvatarView(DYYYAvatarFollowRemovalTargetForView(animationView, nil));
        } else {
            DYYYHideAvatarFollowIconInView(animationView);
        }
    }

    UIView *followAddView = DYYYAvatarViewForSelector(owner, NSSelectorFromString(@"followAddView"));
    if (removePlus) {
        DYYYRemoveAvatarView(followAddView);
    } else {
        BOOL foundIcon = DYYYHideAvatarFollowIconInView(followAddView);
        if (hidePlus && followAddView) {
            DYYYClearAvatarActionViewChrome(followAddView);
            if (!foundIcon) {
                DYYYHideAvatarFollowLayerContents(followAddView);
            }
        }
    }

    UIView *followPromptView = DYYYAvatarViewForSelector(owner, NSSelectorFromString(@"followPromptView"));
    if (removePlus) {
        DYYYRemoveAvatarView(followPromptView);
    } else {
        DYYYApplyAvatarFollowSettingsInView(followPromptView, followPromptView);
    }

    DYYYApplyAvatarAuxiliaryActionSettingsForOwner(owner);

    if ([owner isKindOfClass:[UIView class]]) {
        DYYYApplyAvatarFollowSettingsInView((UIView *)owner, (UIView *)owner);
    } else if ([owner isKindOfClass:[UIViewController class]]) {
        DYYYApplyAvatarFollowSettingsInView(((UIViewController *)owner).view, ((UIViewController *)owner).view);
    }
    UIView *userAvatarView = DYYYAvatarViewForSelector(owner, NSSelectorFromString(@"userAvatarView"));
    if (userAvatarView) {
        DYYYApplyAvatarFollowSettingsInView(userAvatarView, userAvatarView);
    }
    DYYYApplyAvatarFollowSettingsForContext(DYYYAvatarObjectForSelector(owner, NSSelectorFromString(@"userAvatarContext")));
}

static void DYYYApplyAvatarFollowPromptSettingsWithRetry(id owner) {
    DYYYApplyAvatarFollowPromptSettings(owner);
    if (!owner || !DYYYAvatarFollowOptionsEnabled() || objc_getAssociatedObject(owner, &kDYYYAvatarFollowDeferredApplyKey)) {
        return;
    }

    objc_setAssociatedObject(owner, &kDYYYAvatarFollowDeferredApplyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id target = owner;
    dispatch_async(dispatch_get_main_queue(), ^{
        DYYYApplyAvatarFollowPromptSettings(target);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DYYYApplyAvatarFollowPromptSettings(target);
            objc_setAssociatedObject(target, &kDYYYAvatarFollowDeferredApplyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        });
    });
}

// 隐藏头像加号和透明
%hook LOTAnimationView
- (void)layoutSubviews {
    %orig;
    // 旧版加号动画可能被额外容器包裹，沿父视图向上识别关注提示视图。
    if (DYYYIsLegacyAvatarFollowAnimationView(self)) {
        // 检查是否需要隐藏加号
        if (DYYYAvatarFollowOptionsEnabled()) {
            if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
                DYYYRemoveAvatarView(DYYYAvatarFollowRemovalTargetForView(self, nil));
            } else {
                DYYYHideAvatarFollowLayerContents(self);
            }
            DYYYApplyAvatarFollowPromptSettingsWithRetry(self.superview ?: self);
            return;
        }
        // 应用透明度设置
        NSString *transparencyValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYAvatarViewTransparency"];
        if (transparencyValue && transparencyValue.length > 0) {
            CGFloat alphaValue = [transparencyValue floatValue];
            self.alpha = alphaValue;
        }
    }
}
%end

%hook AWEPlayInteractionStaticFollowAnimationView
- (void)layoutSubviews {
    %orig;
    if (DYYYAvatarFollowOptionsEnabled()) {
        DYYYApplyAvatarFollowSettingsInView((UIView *)self, nil);
        DYYYApplyAvatarFollowPromptSettingsWithRetry(self.superview ?: self);
    }
}
%end

// 首页头像隐藏和透明
%hook AWEAdAvatarView
- (void)layoutSubviews {
    %orig;

    // 检查是否需要隐藏头像
    if (DYYYGetBool(@"DYYYHideAvatarButton")) {
        self.hidden = YES;
        return;
    }

    // 应用透明度设置
    NSString *transparencyValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYAvatarViewTransparency"];
    if (transparencyValue && transparencyValue.length > 0) {
        CGFloat alphaValue = [transparencyValue floatValue];
        if (alphaValue >= 0.0 && alphaValue <= 1.0) {
            self.alpha = alphaValue;
        }
    }
}
%end

// 移除同城吃喝玩乐提示框
%hook AWENearbySkyLightCapsuleView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideNearbyCapsuleView")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end


// 隐藏右下音乐和取消静音按钮
%hook AFDCancelMuteAwemeView
- (void)layoutSubviews {
    %orig;

    UIView *superview = self.superview;

    if ([superview isKindOfClass:NSClassFromString(@"AWEBaseElementView")]) {
        if (DYYYGetBool(@"DYYYHideCancelMute")) {
            self.hidden = YES;
            return;
        }
    }
}
%end

// 隐藏弹幕按钮
%hook AWEPlayDanmakuInputContainView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideDanmuButton")) {
        self.hidden = YES;
        return;
    }
}

%end

// 隐藏评论区免费去看短剧
%hook AWEShowPlayletCommentHeaderView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        self.hidden = YES;
        return;
    }
}

%end

// 隐藏评论区定位
%hook AWEPOIEntryAnchorView

- (void)p_addViews {
    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        return;
    }
    %orig;
}

%end

// 隐藏评论音乐
%hook AWECommentGuideLunaAnchorView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        [self setHidden:YES];
    }

    if (DYYYGetBool(@"DYYYMusicCopyText")) {
        UILabel *label = nil;
        if ([self respondsToSelector:@selector(preTitleLabel)]) {
            label = [self valueForKey:@"preTitleLabel"];
        }
        if (label && [label isKindOfClass:[UILabel class]]) {
            label.text = @"";
        }
    }
}

- (void)p_didClickSong {
    if (DYYYGetBool(@"DYYYMusicCopyText")) {
        // 通过 KVC 拿到内部的 songButton
        UIButton *btn = nil;
        if ([self respondsToSelector:@selector(songButton)]) {
            btn = (UIButton *)[self valueForKey:@"songButton"];
        }

        // 获取歌曲名并复制到剪贴板
        if (btn && [btn isKindOfClass:[UIButton class]]) {
            NSString *song = btn.currentTitle;
            if (song.length) {
                [UIPasteboard generalPasteboard].string = song;
                [DYYYToast showSuccessToastWithMessage:@"歌曲名已复制"];
            }
        }
    } else {
        %orig;
    }
}

%end

// Swift 类组
%group CommentHeaderGeneralGroup
%hook AWECommentPanelHeaderSwiftImpl_CommentHeaderGeneralView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        [self setHidden:YES];
    }
}
%end
%end
%group CommentHeaderGoodsGroup
%hook AWECommentPanelHeaderSwiftImpl_CommentHeaderGoodsView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        [self setHidden:YES];
    }
}
%end
%end
%group CommentHeaderTemplateGroup
%hook AWECommentPanelHeaderSwiftImpl_CommentHeaderTemplateAnchorView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        [self setHidden:YES];
    }
}
%end
%end
%group CommentBottomTipsVCGroup
%hook AWECommentPanelListSwiftImpl_CommentBottomTipsContainerViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    if (DYYYGetBool(@"DYYYHideCommentTips")) {
        ((UIViewController *)self).view.hidden = YES;
    }
}
%end
%end

// 去除隐藏大家都在搜后的留白
%hook AWESearchAnchorListModel

- (BOOL)hideWords {
    return DYYYGetBool(@"DYYYHideCommentViews");
}

%end

// 隐藏观看历史搜索
%hook AWEDiscoverFeedEntranceView
- (id)init {
    if (DYYYGetBool(@"DYYYHideInteractionSearch")) {
        return nil;
    }
    return %orig;
}
%end

// 隐藏校园提示
%hook AWETemplateTagsCommonView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideTemplateTags")) {
        UIView *parentView = self.superview;
        if (parentView) {
            parentView.hidden = YES;
        } else {
            self.hidden = YES;
        }
    }
}

%end


// 隐藏消息页顶栏头像气泡
%hook AFDSkylightCellBubble
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideAvatarBubble")) {
        [self removeFromSuperview];
    }
    %orig;
}
%end

// 隐藏消息页开启通知提示
%hook AWEIMMessageTabOptPushBannerView

- (instancetype)initWithFrame:(CGRect)frame {
    if (DYYYGetBool(@"DYYYHidePushBanner")) {
        return %orig(CGRectMake(frame.origin.x, frame.origin.y, 0, 0));
    }
    return %orig;
}

%end

// 隐藏消息页顶栏红包
%hook AWEIMMessageTabSideBarView
- (void)layoutSubviews {
    %orig;

    if (!DYYYGetBool(@"DYYYHideMessageTabRedPacket")) {
        return;
    }

    UIView *parentView = self.superview;
    if (!parentView) {
        return;
    }

    NSArray<UIView *> *siblings = [parentView.subviews copy];
    if (siblings.count <= 1) {
        return;
    }

    for (UIView *subview in siblings) {
        if (subview != self) {
            [subview removeFromSuperview];
        }
    }
}
%end

// 隐藏我的添加朋友
%hook AWEProfileNavigationButton
- (void)setupUI {

    if (DYYYGetBool(@"DYYYHideButton")) {
        return;
    }
    %orig;
}
%end

// 隐藏朋友"关注/不关注"按钮
%hook AWEFeedUnfollowFamiliarFollowAndDislikeView
- (void)showUnfollowFamiliarView {
    if (DYYYGetBool(@"DYYYHideFamiliar")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

// 隐藏朋友日常按钮
%hook AWEFamiliarNavView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideFamiliar")) {
        self.hidden = YES;
    }
    %orig;
}
%end

// 隐藏分享给朋友提示
%hook AWEPlayInteractionStrongifyShareContentView

- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideShareContentView")) {
        UIView *parentView = self.superview;
        if (parentView) {
            parentView.hidden = YES;
        } else {
            self.hidden = YES;
        }
    }
}

%end


%hook AWELeftSideBarEntranceView

- (void)setRedDot:(id)redDot {
    %orig(nil);
}

- (void)setNumericalRedDot:(id)numericalRedDot {
    %orig(nil);
}

- (void)layoutSubviews {
    %orig;

    // 隐藏左侧边栏的 badge
    for (UIView *subview in self.subviews) {
        if ([subview isKindOfClass:%c(DUXBadge)]) {
            subview.hidden = YES;
            break;
        }
    }

    UIResponder *responder = self;
    UIViewController *parentVC = nil;
    while ((responder = [responder nextResponder])) {
        if ([responder isKindOfClass:%c(AWEFeedContainerViewController)]) {
            parentVC = (UIViewController *)responder;
            break;
        }
    }

    if (!(parentVC && [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLeftSideBar"])) {
        return;
    }

    static char kDYLeftSideViewCacheKey;
    NSArray *cachedViews = objc_getAssociatedObject(self, &kDYLeftSideViewCacheKey);
    if (!cachedViews) {
        NSMutableArray *views = [NSMutableArray array];
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:%c(DUXBaseImageView)]) {
                [views addObject:subview];
            }
        }
        cachedViews = [views copy];
        objc_setAssociatedObject(self, &kDYLeftSideViewCacheKey, cachedViews, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UIView *v in cachedViews) {
        v.hidden = YES;
    }
}

%end

%hook AWEFeedVideoButton

- (void)layoutSubviews {
    %orig;

    NSString *accessibilityLabel = self.accessibilityLabel;

    BOOL hideBtn = NO;
    BOOL hideLabel = NO;

    if ([accessibilityLabel isEqualToString:@"点赞"]) {
        hideBtn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLikeButton"];
        hideLabel = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLikeLabel"];
    } else if ([accessibilityLabel isEqualToString:@"评论"]) {
        hideBtn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentButton"];
        hideLabel = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentLabel"];
    } else if ([accessibilityLabel isEqualToString:@"分享"]) {
        hideBtn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideShareButton"];
        hideLabel = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideShareLabel"];
    } else if ([accessibilityLabel isEqualToString:@"收藏"]) {
        hideBtn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCollectButton"];
        hideLabel = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCollectLabel"];
    }

    if (!hideBtn && !hideLabel) {
        return; // 设置未启用，无需额外处理
    }

    if (hideBtn) {
        [self removeFromSuperview];
        return;
    }

    static char kDYLabelCacheKey;
    NSArray *cachedLabels = objc_getAssociatedObject(self, &kDYLabelCacheKey);
    if (!cachedLabels) {
        NSMutableArray *labels = [NSMutableArray array];
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:[UILabel class]]) {
                [labels addObject:subview];
            }
        }
        cachedLabels = [labels copy];
        objc_setAssociatedObject(self, &kDYLabelCacheKey, cachedLabels, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UILabel *label in cachedLabels) {
        label.hidden = hideLabel;
    }
}

%end

%hook UIButton

- (void)layoutSubviews {
    %orig;

    NSString *accessibilityLabel = self.accessibilityLabel;

    if ([accessibilityLabel isEqualToString:@"拍照搜同款"] || [accessibilityLabel isEqualToString:@"扫一扫"]) {
        if (DYYYGetBool(@"DYYYHideScancode")) {
            [self removeFromSuperview];
        }
    }

    if ([accessibilityLabel isEqualToString:@"返回"]) {
        if (DYYYGetBool(@"DYYYHideBack")) {
            UIView *parent = self.superview;
            // 父视图是AWEBaseElementView(排除用户主页返回按钮) 按钮类不是AWENoxusHighlightButton(排除横屏返回按钮)
            if ([parent isKindOfClass:%c(AWEBaseElementView)] && ![self isKindOfClass:%c(AWENoxusHighlightButton)]) {
                [self removeFromSuperview];
            }
            return;
        }
    }
}

%end

%hook AWEIMFeedVideoQuickReplayInputViewController

- (void)viewDidLayoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideReply")) {
        [self.view removeFromSuperview];
        return;
    }
}

%end

%hook AWEHPSearchBubbleEntranceView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideSearchBubble")) {
        [self removeFromSuperview];
        return;
    }
}

%end

%hook AWEFeedLiveTabTopSelectionView
- (void)setHideTimer:(id)timer {
    if (DYYYGetBool(@"DYYYDisableAutoHideLive")) {
        timer = nil;
    }
    %orig(timer);
}
%end

%hook AWEMusicCoverButton

- (void)layoutSubviews {
    %orig;
    NSString *accessibilityLabel = self.accessibilityLabel;
    if ([accessibilityLabel isEqualToString:@"音乐详情"]) {
        if (DYYYGetBool(@"DYYYHideMusicButton")) {
            UIView *parent = self.superview;
            if (parent) {
                [parent removeFromSuperview];
            }
            return;
        }
    }
}

%end

%hook AWEPlayInteractionListenFeedView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideMusicButton")) {
        [self removeFromSuperview];
        return;
    }
}
%end

%hook AWEPlayInteractionFollowPromptView

- (void)layoutSubviews {
    %orig;

    if (DYYYAvatarFollowOptionsEnabled()) {
        DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
        if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
            return;
        }
    }
}

- (void)didMoveToWindow {
    %orig;

    if (DYYYAvatarFollowOptionsEnabled()) {
        DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
    }
}

- (void)didMoveToSuperview {
    %orig;

    if (DYYYAvatarFollowOptionsEnabled()) {
        DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
        return;
    }
}

%end

%hook AWEPlayInteractionElementMaskView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideGradient")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEGradientView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideGradient")) {
        UIView *parent = self.superview;
        if ([parent.accessibilityLabel isEqualToString:@"暂停，按钮"] || [parent.accessibilityLabel isEqualToString:@"播放，按钮"] || [parent.accessibilityLabel isEqualToString:@"“切换视角，按钮"] ||
            [parent isKindOfClass:%c(AWEStoryProgressContainerView)]) {
            self.hidden = YES;
        }
        return;
    }
    %orig;
}
%end

%hook AWEHotSpotBlurView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideGradient")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEHotSearchInnerBottomView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideHotSearch")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end

// 隐藏双指缩放虾线
%hook AWELoadingAndVolumeView

- (void)layoutSubviews {
    %orig;
    self.hidden = YES;
    return;
}

%end

// 隐藏状态栏
%hook AWEFeedRootViewController
- (BOOL)prefersStatusBarHidden {
    if (DYYYGetBool(@"DYYYHideStatusbar")) {
        return YES;
    }
    if (DYYYGetBool(@"DYYYHideStatusBarOnClear") && hideButton && hideButton.isElementsHidden) {
        return YES;
    }
    if (class_getInstanceMethod([self class], @selector(prefersStatusBarHidden)) != class_getInstanceMethod([%c(AWEFeedRootViewController) class], @selector(prefersStatusBarHidden))) {
        return %orig;
    }
    return NO;
}
%end

static const void *kDYYYLiveDurationViewKey = &kDYYYLiveDurationViewKey;
static const void *kDYYYLiveDurationTimerKey = &kDYYYLiveDurationTimerKey;
static const void *kDYYYLiveDurationRoomKey = &kDYYYLiveDurationRoomKey;
static NSString *const kDYYYLiveDurationCenterXPercentKey = @"DYYYLiveDurationCenterXPercent";
static NSString *const kDYYYLiveDurationCenterYPercentKey = @"DYYYLiveDurationCenterYPercent";
static NSString *const kDYYYLiveDurationPositionLockedKey = @"DYYYLiveDurationPositionLocked";

static UIEdgeInsets DYYYLiveDurationSafeInsets(UIView *root) {
    return [root respondsToSelector:@selector(safeAreaInsets)] ? root.safeAreaInsets : UIEdgeInsetsZero;
}

static CGPoint DYYYLiveDurationClampedCenter(CGPoint center, CGSize viewSize, UIView *root) {
    if (!root) {
        return center;
    }

    UIEdgeInsets safeInsets = DYYYLiveDurationSafeInsets(root);
    CGFloat halfWidth = viewSize.width / 2.0;
    CGFloat halfHeight = viewSize.height / 2.0;
    CGFloat minX = safeInsets.left + halfWidth + 4.0;
    CGFloat maxX = fmax(minX, CGRectGetWidth(root.bounds) - safeInsets.right - halfWidth - 4.0);
    CGFloat minY = safeInsets.top + halfHeight + 4.0;
    CGFloat maxY = fmax(minY, CGRectGetHeight(root.bounds) - safeInsets.bottom - halfHeight - 4.0);
    return CGPointMake(fmin(fmax(center.x, minX), maxX), fmin(fmax(center.y, minY), maxY));
}

@interface DYYYLiveDurationWeakViewBox : NSObject
@property(nonatomic, weak) UIView *view;
@end

@implementation DYYYLiveDurationWeakViewBox
@end

@interface DYYYLiveDurationView : UIView
@property(nonatomic, strong) UILabel *durationLabel;
@property(nonatomic, assign, getter=isDragging) BOOL dragging;
@property(nonatomic, assign, getter=isMovementLocked) BOOL movementLocked;
- (CGRect)frameByApplyingSavedPositionToFrame:(CGRect)frame inRoot:(UIView *)root;
@end

@implementation DYYYLiveDurationView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.42];
        self.layer.cornerRadius = 7.0;
        self.layer.masksToBounds = YES;
        self.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;
        self.layer.borderWidth = 0.5;
        self.accessibilityIdentifier = @"dyyy_live_duration_view";

        _durationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _durationLabel.textColor = [UIColor whiteColor];
        _durationLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
        _durationLabel.textAlignment = NSTextAlignmentCenter;
        _durationLabel.adjustsFontSizeToFitWidth = YES;
        _durationLabel.minimumScaleFactor = 0.75;
        _durationLabel.shadowColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
        _durationLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        [self addSubview:_durationLabel];

        _movementLocked = [[NSUserDefaults standardUserDefaults] boolForKey:kDYYYLiveDurationPositionLockedKey];

        UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        longPressGesture.minimumPressDuration = 0.5;
        [self addGestureRecognizer:longPressGesture];

        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [panGesture requireGestureRecognizerToFail:longPressGesture];
        [self addGestureRecognizer:panGesture];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.durationLabel.frame = CGRectInset(self.bounds, 7.0, 2.0);
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *root = self.superview;
    if (self.isMovementLocked || !root) {
        return;
    }

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.dragging = YES;
        self.alpha = 0.8;
    }

    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:root];
        CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
        self.center = DYYYLiveDurationClampedCenter(newCenter, self.bounds.size, root);
        [gesture setTranslation:CGPointZero inView:root];
    }

    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        self.dragging = NO;
        self.alpha = 1.0;
        [self savePosition];
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }

    self.movementLocked = !self.isMovementLocked;
    [[NSUserDefaults standardUserDefaults] setBool:self.isMovementLocked forKey:kDYYYLiveDurationPositionLockedKey];
    if (self.isMovementLocked) {
        [self savePosition];
    }

    [DYYYUtils showToast:self.isMovementLocked ? @"开播时长位置已锁定" : @"开播时长位置已解锁"];
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator prepare];
        [generator impactOccurred];
    }
}

- (void)savePosition {
    UIView *root = self.superview;
    if (!root) {
        return;
    }

    CGFloat rootWidth = CGRectGetWidth(root.bounds);
    CGFloat rootHeight = CGRectGetHeight(root.bounds);
    if (rootWidth <= 0.0 || rootHeight <= 0.0) {
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:self.center.x / rootWidth forKey:kDYYYLiveDurationCenterXPercentKey];
    [defaults setDouble:self.center.y / rootHeight forKey:kDYYYLiveDurationCenterYPercentKey];
}

- (CGRect)frameByApplyingSavedPositionToFrame:(CGRect)frame inRoot:(UIView *)root {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:kDYYYLiveDurationCenterXPercentKey] || ![defaults objectForKey:kDYYYLiveDurationCenterYPercentKey]) {
        return frame;
    }

    CGFloat rootWidth = CGRectGetWidth(root.bounds);
    CGFloat rootHeight = CGRectGetHeight(root.bounds);
    if (rootWidth <= 0.0 || rootHeight <= 0.0) {
        return frame;
    }

    CGFloat centerXPercent = fmin(fmax([defaults doubleForKey:kDYYYLiveDurationCenterXPercentKey], 0.0), 1.0);
    CGFloat centerYPercent = fmin(fmax([defaults doubleForKey:kDYYYLiveDurationCenterYPercentKey], 0.0), 1.0);
    CGPoint center = CGPointMake(centerXPercent * rootWidth, centerYPercent * rootHeight);
    center = DYYYLiveDurationClampedCenter(center, frame.size, root);
    return CGRectIntegral(CGRectMake(center.x - frame.size.width / 2.0, center.y - frame.size.height / 2.0, frame.size.width, frame.size.height));
}

@end

static id DYYYLiveDurationSafeValue(id obj, NSString *key) {
    if (!obj || key.length == 0) {
        return nil;
    }

    @try {
        return [obj valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static long long DYYYLiveDurationLongValue(id obj, NSString *key) {
    id value = DYYYLiveDurationSafeValue(obj, key);
    return [value respondsToSelector:@selector(longLongValue)] ? [value longLongValue] : 0;
}

static BOOL DYYYLiveDurationBoolValue(id obj, NSString *key) {
    id value = DYYYLiveDurationSafeValue(obj, key);
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

static NSTimeInterval DYYYLiveDurationNowSeconds(void) {
    return [[NSDate date] timeIntervalSince1970];
}

static NSTimeInterval DYYYLiveDurationNormalizeTimestamp(long long timestamp) {
    if (timestamp <= 0) {
        return 0.0;
    }
    return timestamp > 20000000000LL ? ((NSTimeInterval)timestamp / 1000.0) : (NSTimeInterval)timestamp;
}

static long long DYYYLiveDurationFirstPositiveValue(id obj, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        long long value = DYYYLiveDurationLongValue(obj, key);
        if (value > 0) {
            return value;
        }
    }
    return 0;
}

static BOOL DYYYLiveDurationLooksLikeRoomObject(id obj) {
    if (!obj) {
        return NO;
    }

    NSString *className = NSStringFromClass([obj class]);
    NSArray<NSString *> *excludedParts = @[ @"Cell", @"Item", @"Aisle", @"Context", @"Config", @"Controller", @"View", @"Factory" ];
    for (NSString *part in excludedParts) {
        if ([className rangeOfString:part options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return NO;
        }
    }

    if ([className rangeOfString:@"LiveRoom" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [className rangeOfString:@"RoomModel" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [className rangeOfString:@"WebcastRoom" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return YES;
    }

    return DYYYLiveDurationSafeValue(obj, @"roomID") || DYYYLiveDurationSafeValue(obj, @"idStr");
}

static NSTimeInterval DYYYLiveDurationElapsedSeconds(id roomModel) {
    if (!DYYYLiveDurationLooksLikeRoomObject(roomModel)) {
        return -1.0;
    }

    id rawRoom = DYYYLiveDurationSafeValue(roomModel, @"rawRoom") ?: roomModel;
    NSArray<NSString *> *startKeys = @[ @"startTime", @"createTime", @"liveStartTime", @"start_time", @"create_time" ];
    long long startTime = DYYYLiveDurationFirstPositiveValue(rawRoom, startKeys);
    if (startTime <= 0) {
        startTime = DYYYLiveDurationFirstPositiveValue(roomModel, startKeys);
    }

    NSTimeInterval timestamp = DYYYLiveDurationNormalizeTimestamp(startTime);
    NSTimeInterval now = DYYYLiveDurationNowSeconds();
    if (timestamp > 1000000000.0 && timestamp <= now + 3600.0) {
        return fmax(0.0, now - timestamp);
    }

    NSArray<NSString *> *durationKeys = @[ @"liveDuration", @"liveTime", @"duration", @"totalDuration" ];
    long long duration = DYYYLiveDurationFirstPositiveValue(rawRoom, durationKeys);
    if (duration <= 0) {
        duration = DYYYLiveDurationFirstPositiveValue(roomModel, durationKeys);
    }
    if (duration > 0 && duration < 365LL * 24LL * 3600LL) {
        return (NSTimeInterval)duration;
    }

    return -1.0;
}

static BOOL DYYYLiveDurationHasValidLiveTime(id obj) {
    return DYYYLiveDurationElapsedSeconds(obj) >= 0.0;
}

static id DYYYLiveDurationRoomFromCarrierDepth(id obj, NSUInteger depth);

static id DYYYLiveDurationRoomFromKnownKeys(id obj, NSUInteger depth) {
    if (!obj || depth > 3) {
        return nil;
    }

    NSArray<NSString *> *keys = @[
        @"rawHTSLiveRoomModel", @"rawDataRoomModel", @"roomModel", @"rawRoom", @"liveRoom", @"room", @"currentRoom",
        @"containerContext", @"roomDI", @"roomConfig", @"roomAisle"
    ];
    for (NSString *key in keys) {
        id value = DYYYLiveDurationSafeValue(obj, key);
        if (DYYYLiveDurationHasValidLiveTime(value)) {
            return value;
        }

        id nestedRawRoom = DYYYLiveDurationSafeValue(value, @"rawRoom");
        if (DYYYLiveDurationHasValidLiveTime(nestedRawRoom)) {
            return value;
        }

        id nestedRoom = DYYYLiveDurationRoomFromCarrierDepth(value, depth + 1);
        if (nestedRoom) {
            return nestedRoom;
        }
    }
    return nil;
}

static id DYYYLiveDurationRoomFromCarrierDepth(id obj, NSUInteger depth) {
    if (!obj || depth > 3) {
        return nil;
    }

    if (DYYYLiveDurationHasValidLiveTime(obj)) {
        return obj;
    }

    id room = DYYYLiveDurationRoomFromKnownKeys(obj, depth + 1);
    if (room) {
        return room;
    }

    if ([obj respondsToSelector:@selector(liveRoomModel)]) {
        @try {
            id value = ((id (*)(id, SEL))objc_msgSend)(obj, @selector(liveRoomModel));
            if (DYYYLiveDurationHasValidLiveTime(value)) {
                return value;
            }
        } @catch (__unused NSException *exception) {
        }
    }

    NSArray<NSString *> *carrierKeys = @[ @"itemModel", @"awemeModel", @"aweme", @"model", @"item" ];
    for (NSString *key in carrierKeys) {
        id carrier = DYYYLiveDurationSafeValue(obj, key);
        room = DYYYLiveDurationRoomFromCarrierDepth(carrier, depth + 1);
        if (room) {
            return room;
        }
    }

    return nil;
}

static id DYYYLiveDurationRoomFromCarrier(id obj) {
    return DYYYLiveDurationRoomFromCarrierDepth(obj, 0);
}

static NSString *DYYYLiveDurationFormatElapsed(NSTimeInterval seconds) {
    long long totalSeconds = (long long)fmax(0.0, floor(seconds));
    long long days = totalSeconds / 86400;
    long long hours = (totalSeconds % 86400) / 3600;
    long long minutes = (totalSeconds % 3600) / 60;
    long long secs = totalSeconds % 60;

    if (days > 0) {
        return [NSString stringWithFormat:@"已开播 %lld天%02lld:%02lld:%02lld", days, hours, minutes, secs];
    }
    return [NSString stringWithFormat:@"已开播 %02lld:%02lld:%02lld", hours, minutes, secs];
}

static DYYYLiveDurationView *DYYYLiveDurationEnsureView(UIView *root) {
    DYYYLiveDurationView *durationView = objc_getAssociatedObject(root, kDYYYLiveDurationViewKey);
    if (durationView && durationView.superview == root) {
        return durationView;
    }

    durationView = [[DYYYLiveDurationView alloc] initWithFrame:CGRectZero];
    objc_setAssociatedObject(root, kDYYYLiveDurationViewKey, durationView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [root addSubview:durationView];
    return durationView;
}

static CGRect DYYYLiveDurationFrameForRoot(UIView *root, id roomModel, NSString *text) {
    UIEdgeInsets safeInsets = DYYYLiveDurationSafeInsets(root);

    CGFloat rootWidth = CGRectGetWidth(root.bounds);
    CGFloat rootHeight = CGRectGetHeight(root.bounds);
    BOOL isLandscape = rootWidth > rootHeight || DYYYLiveDurationBoolValue(roomModel, @"isLandscape");
    if (!isLandscape) {
        long long orientation = DYYYLiveDurationLongValue(roomModel, @"orientation");
        isLandscape = orientation == 2 || orientation == 90 || orientation == 270;
    }

    UIFont *font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    CGSize textSize = [text ?: @"已开播 00:00:00" sizeWithAttributes:@{NSFontAttributeName : font}];
    CGFloat width = fmin(ceil(fmax(textSize.width + 18.0, 118.0)), isLandscape ? 190.0 : 170.0);
    CGFloat height = 26.0;

    CGFloat minX = safeInsets.left + 4.0;
    CGFloat maxX = fmax(minX, rootWidth - safeInsets.right - width - 4.0);
    CGFloat minY = safeInsets.top + 4.0;
    CGFloat maxY = fmax(minY, rootHeight - safeInsets.bottom - height - 4.0);

    CGFloat x = fmin(fmax(safeInsets.left + 12.0, minX), maxX);
    CGFloat y = fmin(fmax(safeInsets.top + (isLandscape ? 12.0 : 86.0), minY), maxY);
    return CGRectIntegral(CGRectMake(x, y, width, height));
}

static void DYYYLiveDurationRemoveFromView(UIView *root) {
    if (!root) {
        return;
    }

    NSTimer *timer = objc_getAssociatedObject(root, kDYYYLiveDurationTimerKey);
    [timer invalidate];
    objc_setAssociatedObject(root, kDYYYLiveDurationTimerKey, nil, OBJC_ASSOCIATION_ASSIGN);

    UIView *durationView = objc_getAssociatedObject(root, kDYYYLiveDurationViewKey);
    [durationView removeFromSuperview];
    objc_setAssociatedObject(root, kDYYYLiveDurationViewKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(root, kDYYYLiveDurationRoomKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static void DYYYLiveDurationUpdateView(UIView *root) {
    if (!root) {
        return;
    }

    if (!DYYYGetBool(@"DYYYShowLiveDuration")) {
        DYYYLiveDurationRemoveFromView(root);
        return;
    }

    id roomModel = objc_getAssociatedObject(root, kDYYYLiveDurationRoomKey);
    NSTimeInterval elapsed = DYYYLiveDurationElapsedSeconds(roomModel);
    DYYYLiveDurationView *durationView = objc_getAssociatedObject(root, kDYYYLiveDurationViewKey);
    if (elapsed < 0.0) {
        durationView.hidden = YES;
        return;
    }

    NSString *text = DYYYLiveDurationFormatElapsed(elapsed);
    durationView = DYYYLiveDurationEnsureView(root);
    durationView.durationLabel.text = text;
    if (!durationView.isDragging) {
        CGRect defaultFrame = DYYYLiveDurationFrameForRoot(root, roomModel, text);
        durationView.frame = [durationView frameByApplyingSavedPositionToFrame:defaultFrame inRoot:root];
        durationView.alpha = 1.0;
    }
    durationView.hidden = NO;
    [root bringSubviewToFront:durationView];
}

@interface DYYYLiveDurationTicker : NSObject
+ (instancetype)sharedTicker;
- (void)tick:(NSTimer *)timer;
@end

@implementation DYYYLiveDurationTicker

+ (instancetype)sharedTicker {
    static DYYYLiveDurationTicker *ticker = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      ticker = [DYYYLiveDurationTicker new];
    });
    return ticker;
}

- (void)tick:(NSTimer *)timer {
    DYYYLiveDurationWeakViewBox *box = (DYYYLiveDurationWeakViewBox *)timer.userInfo;
    UIView *root = box.view;
    if (![root isKindOfClass:[UIView class]]) {
        [timer invalidate];
        return;
    }
    if (!root.window) {
        DYYYLiveDurationRemoveFromView(root);
        return;
    }
    DYYYLiveDurationUpdateView(root);
}

@end

static void DYYYLiveDurationEnsureTimer(UIView *root) {
    NSTimer *timer = objc_getAssociatedObject(root, kDYYYLiveDurationTimerKey);
    if (timer && timer.isValid) {
        return;
    }

    DYYYLiveDurationWeakViewBox *box = [DYYYLiveDurationWeakViewBox new];
    box.view = root;
    timer = [NSTimer timerWithTimeInterval:1.0 target:[DYYYLiveDurationTicker sharedTicker] selector:@selector(tick:) userInfo:box repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    objc_setAssociatedObject(root, kDYYYLiveDurationTimerKey, timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DYYYLiveDurationInstallOnView(UIView *root, id carrier) {
    if (!root) {
        return;
    }

    void (^installBlock)(void) = ^{
      if (!DYYYGetBool(@"DYYYShowLiveDuration")) {
          DYYYLiveDurationRemoveFromView(root);
          return;
      }

      id room = DYYYLiveDurationRoomFromCarrier(carrier);
      if (!DYYYLiveDurationHasValidLiveTime(room)) {
          UIViewController *viewController = [DYYYUtils firstAvailableViewControllerFromView:root];
          room = DYYYLiveDurationRoomFromCarrier(viewController);
      }

      if (DYYYLiveDurationHasValidLiveTime(room)) {
          objc_setAssociatedObject(root, kDYYYLiveDurationRoomKey, room, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      }

      DYYYLiveDurationUpdateView(root);
      if (DYYYLiveDurationHasValidLiveTime(objc_getAssociatedObject(root, kDYYYLiveDurationRoomKey))) {
          DYYYLiveDurationEnsureTimer(root);
      }
    };

    if ([NSThread isMainThread]) {
        installBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), installBlock);
    }
}

static UIViewController *DYYYLiveDurationContainerAudienceVC(id container) {
    UIViewController *viewController = DYYYLiveDurationSafeValue(container, @"audienceVC");
    if (![viewController isKindOfClass:[UIViewController class]] && [container respondsToSelector:@selector(audienceViewController)]) {
        @try {
            viewController = ((id (*)(id, SEL))objc_msgSend)(container, @selector(audienceViewController));
        } @catch (__unused NSException *exception) {
            viewController = nil;
        }
    }
    return [viewController isKindOfClass:[UIViewController class]] ? viewController : nil;
}

static void DYYYLiveDurationInstallFromContainer(id container) {
    UIViewController *viewController = DYYYLiveDurationContainerAudienceVC(container);
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationInstallOnView(viewController.view, DYYYLiveDurationSafeValue(container, @"roomModel") ?: container);
    }
}

static void DYYYLiveDurationInstallFromAudienceWrapper(id wrapper) {
    UIViewController *viewController = DYYYLiveDurationSafeValue(wrapper, @"audienceViewController");
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationInstallOnView(viewController.view, DYYYLiveDurationSafeValue(wrapper, @"roomModel") ?: wrapper);
    }
}

static void DYYYLiveDurationInstallFromInnerFeedCell(id cell) {
    UIViewController *viewController = DYYYLiveDurationSafeValue(cell, @"audienceVC");
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationInstallOnView(viewController.view, cell);
    }
}

%hook AWELiveAudienceContainerController

- (id)initWithRoomModel:(id)roomModel {
    id result = %orig;
    __weak id weakResult = result;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DYYYLiveDurationInstallFromContainer(weakResult);
    });
    return result;
}

- (id)initWithRoomModel:(id)roomModel config:(id)config {
    id result = %orig;
    __weak id weakResult = result;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DYYYLiveDurationInstallFromContainer(weakResult);
    });
    return result;
}

- (id)initWithRoomModel:(id)roomModel context:(id)context {
    id result = %orig;
    __weak id weakResult = result;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DYYYLiveDurationInstallFromContainer(weakResult);
    });
    return result;
}

- (id)initWithRoomModel:(id)roomModel context:(id)context player:(id)player {
    id result = %orig;
    __weak id weakResult = result;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DYYYLiveDurationInstallFromContainer(weakResult);
    });
    return result;
}

- (void)setAudienceVC:(UIViewController *)audienceVC {
    %orig;
    DYYYLiveDurationInstallFromContainer(self);
}

- (void)setRoomModel:(id)roomModel {
    %orig;
    DYYYLiveDurationInstallFromContainer(self);
}

- (void)createAudienceViewController:(id)arg beginTime:(double)beginTime {
    %orig;
    __weak id weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DYYYLiveDurationInstallFromContainer(weakSelf);
    });
}

- (id)audienceControllerWithRoom:(id)room beginTime:(double)beginTime {
    id result = %orig;
    __weak id weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      DYYYLiveDurationInstallFromContainer(weakSelf);
    });
    return result;
}

- (void)updateWithRoomModel:(id)roomModel config:(id)config {
    %orig;
    DYYYLiveDurationInstallFromContainer(self);
}

- (void)updateWithRoomModel:(id)roomModel context:(id)context {
    %orig;
    DYYYLiveDurationInstallFromContainer(self);
}

- (void)updateWithRoomModel:(id)roomModel context:(id)context player:(id)player {
    %orig;
    DYYYLiveDurationInstallFromContainer(self);
}

- (void)clearAudience {
    UIViewController *viewController = DYYYLiveDurationContainerAudienceVC(self);
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

- (void)prepareForReuse {
    UIViewController *viewController = DYYYLiveDurationContainerAudienceVC(self);
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

- (void)dealloc {
    UIViewController *viewController = DYYYLiveDurationContainerAudienceVC(self);
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

%end

%hook AWELiveAudienceViewController

- (id)initWithRoomModel:(id)roomModel {
    id result = %orig;
    __weak id weakResult = result;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DYYYLiveDurationInstallFromAudienceWrapper(weakResult);
    });
    return result;
}

- (void)setRoomModel:(id)roomModel {
    %orig;
    DYYYLiveDurationInstallFromAudienceWrapper(self);
}

- (void)setAudienceViewController:(UIViewController *)audienceViewController {
    %orig;
    DYYYLiveDurationInstallFromAudienceWrapper(self);
}

- (void)attachAudienceViewControllerDelegate:(id)delegate {
    %orig;
    DYYYLiveDurationInstallFromAudienceWrapper(self);
}

- (void)exitLiveRoomWithType:(unsigned long long)type {
    UIViewController *viewController = DYYYLiveDurationSafeValue(self, @"audienceViewController");
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

- (void)dealloc {
    UIViewController *viewController = DYYYLiveDurationSafeValue(self, @"audienceViewController");
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

%end

%hook IESLiveInnerFeedLiveRoomCell

- (void)setItemModel:(id)itemModel {
    %orig;
    DYYYLiveDurationInstallFromInnerFeedCell(self);
}

- (void)setRoomAisle:(id)roomAisle {
    %orig;
    DYYYLiveDurationInstallFromInnerFeedCell(self);
}

- (void)setAudienceVC:(UIViewController *)audienceVC {
    %orig;
    DYYYLiveDurationInstallFromInnerFeedCell(self);
}

- (void)updateWithItemModel:(id)itemModel {
    %orig;
    DYYYLiveDurationInstallFromInnerFeedCell(self);
}

- (void)prepareForReuse {
    UIViewController *viewController = DYYYLiveDurationSafeValue(self, @"audienceVC");
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

%end

// 直播状态栏
%hook IESLiveAudienceViewController
- (BOOL)prefersStatusBarHidden {
    if (DYYYGetBool(@"DYYYHideStatusbar")) {
        return YES;
    }
    if (DYYYGetBool(@"DYYYHideStatusBarOnClear") && hideButton && hideButton.isElementsHidden) {
        return YES;
    }
    if (class_getInstanceMethod([self class], @selector(prefersStatusBarHidden)) !=
        class_getInstanceMethod([%c(IESLiveAudienceViewController) class], @selector(prefersStatusBarHidden))) {
        return %orig;
    }
    return NO;
}

- (void)viewDidLoad {
    %orig;
    DYYYLiveDurationInstallOnView(self.view, self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    DYYYLiveDurationInstallOnView(self.view, self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    DYYYLiveDurationInstallOnView(self.view, self);
    DYYYLiveDurationUpdateView(self.view);
}

- (void)didEnterRoom:(id)room {
    %orig;
    DYYYLiveDurationInstallOnView(self.view, room ?: self);
}

- (void)didPreloadRoom:(id)room {
    %orig;
    DYYYLiveDurationInstallOnView(self.view, room ?: self);
}

- (void)didCloseRoom:(id)room closeType:(unsigned long long)type {
    DYYYLiveDurationRemoveFromView(self.view);
    %orig;
}

- (void)dealloc {
    if (self.isViewLoaded) {
        DYYYLiveDurationRemoveFromView(self.view);
    }
    %orig;
}
%end

// 主页状态栏
%hook AWEAwemeDetailTableViewController
- (BOOL)prefersStatusBarHidden {
    if (DYYYGetBool(@"DYYYHideStatusbar")) {
        return YES;
    }
    if (DYYYGetBool(@"DYYYHideStatusBarOnClear") && hideButton && hideButton.isElementsHidden) {
        return YES;
    }
    if (class_getInstanceMethod([self class], @selector(prefersStatusBarHidden)) !=
        class_getInstanceMethod([%c(AWEAwemeDetailTableViewController) class], @selector(prefersStatusBarHidden))) {
        return %orig;
    }
    return NO;
}
%end

// 热点状态栏
%hook AWEAwemeHotSpotTableViewController
- (BOOL)prefersStatusBarHidden {
    if (DYYYGetBool(@"DYYYHideStatusbar")) {
        return YES;
    }
    if (DYYYGetBool(@"DYYYHideStatusBarOnClear") && hideButton && hideButton.isElementsHidden) {
        return YES;
    }
    if (class_getInstanceMethod([self class], @selector(prefersStatusBarHidden)) !=
        class_getInstanceMethod([%c(AWEAwemeHotSpotTableViewController) class], @selector(prefersStatusBarHidden))) {
        return %orig;
    }
    return NO;
}
%end

// 图文状态栏
%hook AWEFullPageFeedNewContainerViewController
- (BOOL)prefersStatusBarHidden {
    if (DYYYGetBool(@"DYYYHideStatusbar")) {
        return YES;
    }
    if (DYYYGetBool(@"DYYYHideStatusBarOnClear") && hideButton && hideButton.isElementsHidden) {
        return YES;
    }
    if (class_getInstanceMethod([self class], @selector(prefersStatusBarHidden)) !=
        class_getInstanceMethod([%c(AWEFullPageFeedNewContainerViewController) class], @selector(prefersStatusBarHidden))) {
        return %orig;
    }
    return NO;
}
%end

// 纯净模式状态栏
%hook AFDPureModePageContainerViewController
- (BOOL)prefersStatusBarHidden {
    if (DYYYGetBool(@"DYYYHideStatusbar")) {
        return YES;
    }
    if (DYYYGetBool(@"DYYYHideStatusBarOnClear") && hideButton && hideButton.isElementsHidden) {
        return YES;
    }
    if (class_getInstanceMethod([self class], @selector(prefersStatusBarHidden)) !=
        class_getInstanceMethod([%c(AFDPureModePageContainerViewController) class], @selector(prefersStatusBarHidden))) {
        return %orig;
    }
    return NO;
}
%end


%hook AWEPlayInteractionSearchAnchorView

- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideInteractionSearch")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}

%end


// 隐藏暂停关键词
%hook AWEFeedPauseRelatedWordComponent

- (id)updateViewWithModel:(id)arg0 {
    if (DYYYGetBool(@"DYYYHidePauseVideoRelatedWord")) {
        return nil;
    }
    return %orig;
}

- (id)pauseContentWithModel:(id)arg0 {
    if (DYYYGetBool(@"DYYYHidePauseVideoRelatedWord")) {
        return nil;
    }
    return %orig;
}

- (id)recommendsWords {
    if (DYYYGetBool(@"DYYYHidePauseVideoRelatedWord")) {
        return nil;
    }
    return %orig;
}

- (void)showRelatedRecommendPanelControllerWithSelectedText:(id)arg0 {
    if (DYYYGetBool(@"DYYYHidePauseVideoRelatedWord")) {
        return;
    }
    %orig;
}

- (void)setupUI {
    %orig;
    if (DYYYGetBool(@"DYYYHidePauseVideoRelatedWord")) {
        if (self.relatedView) {
            self.relatedView.hidden = YES;
        }
    }
}

%end

// 隐藏视频顶部搜索框、隐藏搜索框背景、应用全局透明
%hook AWESearchEntranceView

- (void)layoutSubviews {

    if (DYYYGetBool(@"DYYYHideSearchEntrance")) {
        self.hidden = YES;
        return;
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideSearchEntranceIndicator"]) {
        static char kDYSearchIndicatorKey;
        NSArray *indicatorViews = objc_getAssociatedObject(self, &kDYSearchIndicatorKey);
        if (!indicatorViews) {
            NSMutableArray *tmp = [NSMutableArray array];
            for (UIView *subviews in self.subviews) {
                if ([subviews isKindOfClass:%c(UIImageView)] && [NSStringFromClass([((UIImageView *)subviews).image class]) isEqualToString:@"_UIResizableImage"]) {
                    [tmp addObject:subviews];
                }
            }
            indicatorViews = [tmp copy];
            objc_setAssociatedObject(self, &kDYSearchIndicatorKey, indicatorViews, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        for (UIImageView *imgView in indicatorViews) {
            imgView.hidden = YES;
        }
    }

    %orig;
}

%end

// 隐藏视频滑条
%hook AWEStoryProgressSlideView

- (void)layoutSubviews {
    %orig;

    BOOL shouldHide = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideStoryProgressSlide"];
    if (!shouldHide)
        return;

    static char kDYStoryProgressCacheKey;
    UIView *targetView = objc_getAssociatedObject(self, &kDYStoryProgressCacheKey);
    if (!targetView) {
        for (UIView *obj in self.subviews) {
            if ([obj isKindOfClass:NSClassFromString(@"UISlider")] || obj.frame.size.height < 5) {
                targetView = obj.superview;
                break;
            }
        }
        if (targetView) {
            objc_setAssociatedObject(self, &kDYStoryProgressCacheKey, targetView, OBJC_ASSOCIATION_ASSIGN);
        }
    }

    if (targetView) {
        targetView.hidden = YES;
    }
}

%end

// 隐藏好友分享私信
%hook AFDNewFastReplyView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHidePrivateMessages")) {
        UIView *parentView = self.superview;
        if (parentView) {
            parentView.hidden = YES;
        } else {
            self.hidden = YES;
        }
    }
}

%end


// 隐藏直播发现
%hook AWEFeedLiveTabRevisitControlView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideLiveDiscovery")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook IESLiveDynamicRankListEntranceView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideLiveDetail")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook _TtC18IESLiveRevenueImpl34IESLiveDynamicRankListEntranceView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideLiveDetail")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook IESLiveMatrixEntranceView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideLiveDetail")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook IESLiveShortTouchActionView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideTouchView")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook IESLiveLotteryAnimationViewNew
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideTouchView")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook IESLiveConfigurableShortTouchEntranceView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideTouchView")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook IESLiveRedEnvelopeAniLynxView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideTouchView")) {
        self.hidden = YES;
        return;
    }
}
%end

// 隐藏直播点歌
%hook IESLiveKTVSongIndicatorView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideKTVSongIndicator")) {
        self.hidden = YES;
        return;
    }
}
%end

// 隐藏昵称右侧
%hook UILabel

static NSHashTable *processedParentViews = nil;

+ (void)load {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      processedParentViews = [NSHashTable weakObjectsHashTable];
    });
}

- (void)layoutSubviews {
    %orig;

    BOOL hideRightLabel = DYYYGetBool(@"DYYYHideRightLabel");
    if (!hideRightLabel)
        return;

    NSString *accessibilityLabel = self.accessibilityLabel;
    if (!accessibilityLabel || accessibilityLabel.length == 0)
        return;

    // 避免重复处理同一个父视图
    UIView *parentView = self.superview;
    if (!parentView)
        return;

    @synchronized(processedParentViews) {
        if ([processedParentViews containsObject:parentView]) {
            return;
        }
    }

    NSString *trimmedLabel = [accessibilityLabel stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    BOOL shouldRemove = NO;

    if ([trimmedLabel hasSuffix:@"人共创"] && trimmedLabel.length > 3) {
        NSString *prefix = [trimmedLabel substringToIndex:trimmedLabel.length - 3];
        NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        shouldRemove = ([prefix rangeOfCharacterFromSet:nonDigits].location == NSNotFound);
    }

    if (!shouldRemove) {
        shouldRemove = [trimmedLabel isEqualToString:@"章节要点"] || [trimmedLabel isEqualToString:@"图集"] || [trimmedLabel isEqualToString:@"下一章"];
    }

    if (shouldRemove) {
        @synchronized(processedParentViews) {
            [processedParentViews addObject:parentView];
        }

        UIView *grandparentView = parentView.superview; // 爷爷视图

        if (grandparentView) {

            dispatch_async(dispatch_get_main_queue(), ^{
              if ([grandparentView isKindOfClass:[UIStackView class]]) {
                  UIStackView *stackView = (UIStackView *)grandparentView;
                  [stackView removeArrangedSubview:parentView];
              }

              [parentView removeFromSuperview];

              // 强制刷新爷爷视图布局
              [grandparentView setNeedsLayout];
              [grandparentView layoutIfNeeded];
            });
        }
    }
}

%end

// 隐藏顶栏关注下的提示线
%hook AWEFeedMultiTabSelectedContainerView

- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideTopBarLine")) {
        self.hidden = YES;
    }
}

%end

%hook AFDRecommendToFriendEntranceLabel
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideRecommendTips")) {
        if (self.accessibilityLabel) {
            [self removeFromSuperview];
        }
    }
}

%end

// 隐藏自己无公开作品的视图
%hook AWEProfileMixItemCollectionViewCell
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHidePostView")) {
        if ([self.accessibilityLabel isEqualToString:@"私密作品"]) {
            self.hidden = YES;
            return;
        }
    }
}
%end

%hook AWEProfilePostEmptyPublishGuideCollectionViewCell

- (void)didMoveToSuperview {
    %orig;
    if (DYYYGetBool(@"DYYYHidePostView")) {
        if ([(UIView *)self superview]) {
            [(UIView *)self setHidden:YES];
        }
    }
}

%end

%hook AWEProfileTaskCardStyleListCollectionViewCell
- (BOOL)shouldShowPublishGuide {
    if (DYYYGetBool(@"DYYYHidePostView")) {
        return NO;
    }
    return %orig;
}
%end

%hook AWEProfileRichEmptyView

- (void)setTitle:(id)title {
    if (DYYYGetBool(@"DYYYHidePostView")) {
        return;
    }
    %orig(title);
}

- (void)setDetail:(id)detail {
    if (DYYYGetBool(@"DYYYHidePostView")) {
        return;
    }
    %orig(detail);
}
%end

// 隐藏关注直播顶端的直播视图
%hook AWENewLiveSkylightViewController

- (void)showSkylight:(BOOL)arg0 animated:(BOOL)arg1 actionMethod:(unsigned long long)arg2 {
    if (DYYYGetBool(@"DYYYHideLiveView")) {
        return;
    }
    %orig(arg0, arg1, arg2);
}

- (void)updateIsSkylightShowing:(BOOL)arg0 {
    if (DYYYGetBool(@"DYYYHideLiveView")) {
        %orig(NO);
    } else {
        %orig(arg0);
    }
}

%end

// 隐藏关注直播
%hook AWELiveSkylightViewModel

- (id)dataSource {
	BOOL DYYYHideConcernCapsuleView = DYYYGetBool(@"DYYYHideConcernCapsuleView");
	if (DYYYHideConcernCapsuleView) {
		return nil;
	}
	return %orig;
}

- (void)setDataSource:(id)dataSource {
	BOOL DYYYHideConcernCapsuleView = DYYYGetBool(@"DYYYHideConcernCapsuleView");
	if (DYYYHideConcernCapsuleView) {
		%orig(nil);
		return;
	}
	%orig;
}

%end

%hook AWELiveAutoEnterStyleAView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideLiveView")) {
        self.hidden = YES;
        return;
    }
}

%end

// 隐藏同城顶端
%hook AWENearbyFullScreenViewModel

- (void)setShowSkyLight:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideMenuView")) {
        arg1 = nil;
    }
    %orig(arg1);
}

- (void)setHaveSkyLight:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideMenuView")) {
        arg1 = nil;
    }
    %orig(arg1);
}

%end

// 隐藏笔记
%hook AWECorrelationItemTag

- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideItemTag")) {
        self.hidden = YES;
        return;
    }
}

%end

// 屏蔽模板按钮组件（底部互动）- hook button 方法返回 nil
%hook AWEPlayInteractionTemplateButton
- (id)button {
	BOOL DYYYHideBottomInteraction = DYYYGetBool(@"DYYYHideBottomInteraction");
	if (DYYYHideBottomInteraction) {
		return nil;
	}
	return %orig;
}

- (void)setButton:(id)button {
	BOOL DYYYHideBottomInteraction = DYYYGetBool(@"DYYYHideBottomInteraction");
	if (DYYYHideBottomInteraction) {
		return;  // 不设置按钮
	}
	%orig;
}
%end

// 隐藏右上搜索，但可点击
%hook AWEHPDiscoverFeedEntranceView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideDiscover")) {
        UIView *firstSubview = self.subviews.firstObject;
        if ([firstSubview isKindOfClass:[UIImageView class]]) {
            ((UIImageView *)firstSubview).image = nil;
        }
    }
}

%end

// 隐藏点击进入直播间
%hook AWELiveFeedStatusLabel
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideEnterLive")) {
        UIView *parentView = self.superview;
        UIView *grandparentView = parentView.superview;

        if (grandparentView) {
            grandparentView.hidden = YES;
            return;
        } else if (parentView) {
            parentView.hidden = YES;
            return;
        } else {
            self.hidden = YES;
            return;
        }
    }
    %orig;
}
%end

// 去除消息群直播提示
%hook AWEIMCellLiveStatusContainerView

- (void)p_initUI {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYHideGroupLiveIndicator"])
        %orig;
}
%end

%hook AWELiveStatusIndicatorView

- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideGroupLiveIndicator")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWELiveFeedLabelTagView
- (void)layoutSubviews {

    if (DYYYGetBool(@"DYYYHideLiveCapsuleView")) {
        UIView *parentView = self.superview;
        if (parentView) {
            parentView.hidden = YES;
            return;
        } else {
            self.hidden = YES;
            return;
        }
    }
    %orig;
}

%end

%hook AWEPlayInteractionLiveExtendGuideView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveCapsuleView")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end

// 隐藏首页直播胶囊
%hook AWEHPTopTabItemBadgeContentView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideConcernCapsuleView")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

// 隐藏群商店
%hook AWEIMFansGroupTopDynamicDomainTemplateView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideGroupShop")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

// 去除群聊天输入框上方快捷方式
%hook AWEIMInputActionBarInteractor

- (void)p_setupUI {
    if (DYYYGetBool(@"DYYYHideGroupInputActionBar")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

// 隐藏相机定位
%hook AWETemplateCommonView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideCameraLocation")) {
        [self removeFromSuperview];
    }
}
%end

// 隐藏侧栏红点
%hook AWEHPTopBarCTAItemView

- (void)showRedDot {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYHideSidebarDot"])
        %orig;
}

- (void)hideCountRedDot {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYHideSidebarDot"])
        %orig;
}

- (void)layoutSubviews {
    %orig;

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideSidebarDot"]) {
        return;
    }

    static char kDYSidebarBadgeCacheKey;
    NSArray *cachedBadges = objc_getAssociatedObject(self, &kDYSidebarBadgeCacheKey);
    if (!cachedBadges) {
        NSMutableArray *badges = [NSMutableArray array];
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:%c(DUXBadge)]) {
                [badges addObject:subview];
            }
        }
        cachedBadges = [badges copy];
        objc_setAssociatedObject(self, &kDYSidebarBadgeCacheKey, cachedBadges, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UIView *badge in cachedBadges) {
        badge.hidden = YES;
    }
}
%end

// 隐藏搜同款
%hook ACCStickerContainerView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideSearchSame")) {
        [self removeFromSuperview];
    }
}
%end

// 隐藏礼物展馆
%hook BDXWebView
- (void)layoutSubviews {
    %orig;

    BOOL enabled = DYYYGetBool(@"DYYYHideGiftPavilion");
    if (!enabled)
        return;

    NSString *title = [self valueForKey:@"title"];

    if ([title containsString:@"任务Banner"] || [title containsString:@"活动Banner"]) {
        self.hidden = YES;
    }
}
%end

%hook AWEVideoTypeTagView

- (void)setupUI {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYHideLiveGIF"])
        %orig;
}
%end

// 隐藏直播广场
%hook IESLiveFeedDrawerEntranceView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideLivePlayground")) {
        self.hidden = YES;
    }
}

%end

// 隐藏直播退出清屏、投屏按钮
%hook IESLiveButton

- (void)layoutSubviews {
    %orig;
    BOOL hideClear = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLiveRoomClear"];
    BOOL hideMirror = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLiveRoomMirroring"];
    BOOL hideFull = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLiveRoomFullscreen"];
    BOOL hideClose = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLiveRoomClose"];

    if (!(hideClear || hideMirror || hideFull)) {
        return;
    }

    NSString *label = self.accessibilityLabel;
    if (hideClear && [label isEqualToString:@"退出清屏"] && self.superview) {
        [self.superview removeFromSuperview];
        return;
    } else if (hideMirror && [label isEqualToString:@"投屏"] && self.superview) {
        self.superview.hidden = YES;
        return;
    } else if (hideFull && [label isEqualToString:@"横屏"] && self.superview) {
        static char kDYLiveButtonCacheKey;
        NSArray *cached = objc_getAssociatedObject(self, &kDYLiveButtonCacheKey);
        if (!cached) {
            cached = [self.subviews copy];
            objc_setAssociatedObject(self, &kDYLiveButtonCacheKey, cached, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        for (UIView *subview in cached) {
            subview.hidden = YES;
        }
        return;
    } else if (hideClose && [self.superview isKindOfClass:%c(HTSLive4LayerContainerView)]) {
        self.hidden = YES;
        return;
    }
}

%end

// 隐藏直播间右上方关闭直播按钮
%hook IESLiveLayoutPlaceholderView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideLiveRoomClose")) {
        [self removeFromSuperview];
        return;
    }
}
%end

// 隐藏直播间流量弹窗
%hook AWELiveFlowAlertView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideCellularAlert")) {
        self.hidden = YES;
        return;
    }
}
%end

// 隐藏直播间商品和推广
%hook IESECLivePluginLayoutView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook IESECLiveCardSizeComponent
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook IESECLiveGoodsCardView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook IESLiveBottomRightCardView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook IESLiveGameCPExplainCardContainerImpl
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook AWEPOILivePurchaseAtmosphereView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg") && self.superview) {
        self.superview.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook IESLiveActivityBannnerView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end

// 隐藏直播间点赞动画
%hook HTSLiveDiggView
- (void)setIconImageView:(UIImageView *)arg1 {
    if (DYYYGetBool(@"DYYYHideLiveLikeAnimation")) {
        %orig(nil);
    } else {
        %orig(arg1);
    }
}
%end

// 隐藏直播间文字贴纸
%hook IESLiveStickerView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideStickerView")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end

// 隐藏直播间礼物挑战
%hook IESLiveGroupLiveComponentView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideGroupComponent")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end

// 预约直播
%hook IESLivePreAnnouncementPanelViewNew
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideStickerView")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

// 隐藏会员进场特效
%hook IESLiveDynamicUserEnterView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLivePopup")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

// 会员进场特效: 高版本启用swift类名
%hook _TtC18IESLiveRevenueImpl32IESLiveSwiftDynamicUserEnterView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLivePopup")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

// 隐藏特殊进场特效
%hook PlatformCanvasView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideLivePopup")) {
        UIView *pview = self.superview;
        UIView *gpview = pview.superview;
        // 基于accessibilitylabel的判断
        BOOL isLynxView = [pview isKindOfClass:%c(UILynxView)] && [gpview isKindOfClass:%c(LynxView)] && [gpview.accessibilityLabel isEqualToString:@"lynxview"];
        // 基于最近的视图控制器IESLiveAudienceViewController的判断
        UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:self];
        BOOL isLiveAudienceVC = [vc isKindOfClass:%c(IESLiveAudienceViewController)];
        if (isLynxView && isLiveAudienceVC) {
            self.hidden = YES;
        }
    }
    return;
}
%end

// 特殊视频进场特效:高版本启用swift类名
%hook _TtC18IESLiveRevenueImpl35IESLiveSwiftVideoLayerUserEnterView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLivePopup")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook IESLiveDanmakuVariousView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveDanmaku")) {
        self.hidden = YES;
        return;
    }
    %orig;
}

%end

%hook IESLiveDanmakuSupremeView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveDanmaku")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook IESLiveHotMessageView
- (void)layoutSubviews {

    if (DYYYGetBool(@"DYYYHideLiveHotMessage")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEListDataController

- (void)setDataSource:(NSMutableArray *)dataSource {
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    %orig(filtered);
}

- (NSMutableArray *)dataSource {
    NSMutableArray *dataSource = %orig;
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    if (filtered != dataSource && [dataSource isKindOfClass:[NSMutableArray class]]) {
        [dataSource setArray:filtered];
    } else if (filtered != dataSource) {
        return [filtered mutableCopy];
    }
    return dataSource;
}

- (void)setFilteredDataSource:(NSMutableArray *)filteredDataSource {
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:filteredDataSource];
    %orig(filtered);
}

- (NSMutableArray *)filteredDataSource {
    NSMutableArray *filteredDataSource = %orig;
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:filteredDataSource];
    if (filtered != filteredDataSource && [filteredDataSource isKindOfClass:[NSMutableArray class]]) {
        [filteredDataSource setArray:filtered];
    } else if (filtered != filteredDataSource) {
        return [filtered mutableCopy];
    }
    return filteredDataSource;
}

%end

%hook AWEMixVideoListDataController

- (void)setDataSource:(id)dataSource {
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    %orig(filtered);
}

- (id)dataSource {
    id dataSource = %orig;
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    if (filtered != dataSource && [dataSource isKindOfClass:[NSMutableArray class]]) {
        [dataSource setArray:filtered];
    } else if (filtered != dataSource) {
        return filtered;
    }
    return dataSource;
}

%end

%hook AWEMixVideoDetailPlayListDataController

- (void)setDataSource:(id)dataSource {
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    %orig(filtered);
}

%end

%hook AWEMixVideoRelatedListDataController

- (void)setDataSource:(id)dataSource {
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    %orig(filtered);
}

- (id)dataSource {
    id dataSource = %orig;
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    if (filtered != dataSource && [dataSource isKindOfClass:[NSMutableArray class]]) {
        [dataSource setArray:filtered];
    } else if (filtered != dataSource) {
        return filtered;
    }
    return dataSource;
}

%end

%hook AWEHotListDataController

%new
- (NSNumber *)dyyy_numberValueForLowLikesFilter:(id)rawValue {
    if (!rawValue || rawValue == [NSNull null]) {
        return nil;
    }

    if ([rawValue isKindOfClass:[NSNumber class]]) {
        return (NSNumber *)rawValue;
    }

    if ([rawValue isKindOfClass:[NSString class]]) {
        NSString *trimmed = [(NSString *)rawValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            return nil;
        }

        NSString *normalized = [[trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
        normalized = [normalized stringByReplacingOccurrencesOfString:@"," withString:@""];
        normalized = [normalized stringByReplacingOccurrencesOfString:@"+" withString:@""];
        if ([normalized hasSuffix:@"赞"]) {
            normalized = [normalized substringToIndex:normalized.length - 1];
        }

        double multiplier = 1.0;
        NSString *lowercaseValue = [normalized lowercaseString];
        if ([normalized hasSuffix:@"亿"]) {
            multiplier = 100000000.0;
            normalized = [normalized substringToIndex:normalized.length - 1];
        } else if ([normalized hasSuffix:@"万"] || [lowercaseValue hasSuffix:@"w"]) {
            multiplier = 10000.0;
            normalized = [normalized substringToIndex:normalized.length - 1];
        } else if ([normalized hasSuffix:@"千"] || [lowercaseValue hasSuffix:@"k"]) {
            multiplier = 1000.0;
            normalized = [normalized substringToIndex:normalized.length - 1];
        }

        NSScanner *doubleScanner = [NSScanner scannerWithString:normalized];
        double doubleValue = 0.0;
        if ([doubleScanner scanDouble:&doubleValue] && doubleScanner.isAtEnd) {
            return @((long long)llround(doubleValue * multiplier));
        }
    }

    return nil;
}

%new
- (NSNumber *)dyyy_resolvedDiggCountForAweme:(AWEAwemeModel *)aweme {
    if (!aweme) {
        return nil;
    }

    static NSArray<NSString *> *diggKeyPaths = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        diggKeyPaths = @[
            @"statistics.diggCount",
            @"statistics.digg_count",
            @"diggCount",
            @"digg_count",
            @"feedSequenceExtendFeature.digg_count",
            @"feedSequenceExtendFeature.diggCount",
            @"recommendFeedExtendFeature.digg_count",
            @"recommendFeedExtendFeature.diggCount"
        ];
    });

    for (NSString *keyPath in diggKeyPaths) {
        id rawValue = nil;
        @try {
            rawValue = [aweme valueForKeyPath:keyPath];
        } @catch (__unused NSException *exception) {
            rawValue = nil;
        }

        NSNumber *resolved = [self dyyy_numberValueForLowLikesFilter:rawValue];
        if (resolved) {
            return resolved;
        }
    }

    return nil;
}

- (id)transferAwemeListIfNeededWithArray:(id)arg1 isInitFetch:(BOOL)arg2 {
    NSArray *orig = %orig;
    if (![orig isKindOfClass:[NSArray class]] || orig.count == 0) {
        return orig;
    }

    // --- 配置读取 ---
    NSInteger daysThreshold = DYYYGetInteger(@"DYYYFilterTimeLimit");
    BOOL skipLive = DYYYGetBool(@"DYYYSkipLive"); // 读取直播过滤开关
    NSInteger minLikesThreshold = DYYYGetInteger(@"DYYYFilterLowLikes"); // 读取低赞过滤阈值 (例如: 1000)
    BOOL skipPhotoText = DYYYGetBool(@"DYYYSkipPhotoText"); // 图文过滤
    BOOL skipPhoto = DYYYGetBool(@"DYYYSkipPhoto"); // 图集过滤
    BOOL skipMusic = DYYYGetBool(@"DYYYSkipMusic"); // 音乐过滤
    BOOL shouldDisableHDR = DYYYShouldDisableAllHDR();
    BOOL noAds = DYYYGetBool(@"DYYYNoAds");

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval thresholdInSeconds = MAX(daysThreshold, 0) * 86400.0;

    // 第一阶段：先做稳定字段过滤（直播/时间/类型）
    NSMutableArray *baseFiltered = [NSMutableArray arrayWithCapacity:orig.count];

    for (id obj in orig) {
        if (![obj isKindOfClass:%c(AWEAwemeModel)]) {
            [baseFiltered addObject:obj];
            continue;
        }

        AWEAwemeModel *m = (AWEAwemeModel *)obj;

        // 1. 广告过滤：合集、搜索内流、分页追加等旁路也会进入此共享转换。
        if (noAds && [DYYYUtils isAdvertisementAwemeModel:m]) {
            continue;
        }

        // 2. 直播过滤逻辑 (仅依赖 cellRoom)
        if (skipLive && [m respondsToSelector:@selector(cellRoom)] && m.cellRoom != nil) {
            continue; // 命中直播过滤，跳过
        }

        // 2.1 图文模式过滤逻辑（推荐页）
        if (skipPhotoText &&
            [m respondsToSelector:@selector(isNewTextMode)] &&
            m.isNewTextMode &&
            [m respondsToSelector:@selector(referString)] &&
            [m.referString isEqualToString:@"homepage_hot"]) {
            continue; // 图文模式且来自推荐页，跳过
        }

        // 2.2 图集过滤逻辑（推荐页）
        if (skipPhoto &&
            [m respondsToSelector:@selector(awemeType)] &&
            m.awemeType == 68 &&
            [m respondsToSelector:@selector(referString)] &&
            [m.referString isEqualToString:@"homepage_hot"]) {
            continue; // 图集且来自推荐页，跳过
        }

        // 2.3 音乐过滤逻辑（推荐页）
        if (skipMusic &&
            [m respondsToSelector:@selector(referString)] &&
            [m.referString isEqualToString:@"homepage_hot"] &&
            [m respondsToSelector:@selector(musicCard)] &&
            m.musicCard) {
            continue; // 音乐卡片且来自推荐页，跳过
        }

        // 3. 时间限制过滤
        if (daysThreshold > 0 && [m respondsToSelector:@selector(createTime)]) {
            NSTimeInterval vTs = [m.createTime doubleValue];
            if (vTs > 1e12) {
                vTs /= 1000.0; // 毫秒转秒
            }

            if (vTs > 0 && (now - vTs) > thresholdInSeconds) {
                continue; // 超过设定时限，跳过
            }
        }

        // 4. 全局屏蔽 HDR 时，若作品没有 SDR 码率档，直接过滤，避免强播纯 HDR 源导致黑屏或 HDR 漏出。
        if (shouldDisableHDR &&
            ![m dyyy_shouldExcludeFromGlobalHDRFilter] &&
            DYYYAwemeModelHasOnlyHDRBitrateModels(m)) {
            continue;
        }

        if (shouldDisableHDR) {
            DYYYStripHDRHintsFromAwemeModel(m);
        }

        [baseFiltered addObject:obj];
    }

    if (minLikesThreshold <= 0 || baseFiltered.count == 0) {
        return [baseFiltered copy];
    }

    // 第二阶段：低赞过滤。字段缺失时放行；只要能解析到数值，就严格按阈值过滤。
    NSMutableArray *lowLikesFiltered = [NSMutableArray arrayWithCapacity:baseFiltered.count];

    for (id obj in baseFiltered) {
        if (![obj isKindOfClass:%c(AWEAwemeModel)]) {
            [lowLikesFiltered addObject:obj];
            continue;
        }

        AWEAwemeModel *m = (AWEAwemeModel *)obj;
        NSNumber *diggCountValue = [self dyyy_resolvedDiggCountForAweme:m];

        if (!diggCountValue) {
            [lowLikesFiltered addObject:obj];
            continue;
        }

        if (diggCountValue.integerValue < minLikesThreshold) {
            continue;
        }

        [lowLikesFiltered addObject:obj];
    }

    return [lowLikesFiltered copy];
}

%end

%hook AWEAwemeModel

- (id)initWithDictionary:(id)arg1 error:(id *)arg2 {
    id orig = %orig;
    if (orig) {
        BOOL shouldDisableHDR = DYYYShouldDisableAllHDR();
        BOOL shouldFilterOnlyHDRSource = NO;
        if (shouldDisableHDR && ![self dyyy_shouldExcludeFromGlobalHDRFilter]) {
            shouldFilterOnlyHDRSource = DYYYAwemeModelHasOnlyHDRBitrateModels(self);
            if (!shouldFilterOnlyHDRSource) {
                shouldFilterOnlyHDRSource = DYYYRawObjectHasOnlyHDRBitrateModels(arg1);
                if (shouldFilterOnlyHDRSource) {
                    objc_setAssociatedObject(self, &kDYYYHDROnlyAwemeModelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
        }
        BOOL shouldFilter = DYYYGetBool(@"DYYYNoAds") &&
                            ([DYYYUtils isAdvertisementAwemeModel:self] || [DYYYUtils isAdvertisementRawData:arg1]);
        if (!shouldFilter) {
            shouldFilter = [self contentFilter];
        }
        if (!shouldFilter && shouldFilterOnlyHDRSource) {
            shouldFilter = YES;
        }
        if (!shouldFilter && DYYYShouldFilterGlobalHDR() &&
            ![self dyyy_shouldExcludeFromGlobalHDRFilter] &&
            [self dyyy_containsHDRMetadataInObject:arg1 depth:0]) {
            shouldFilter = YES;
        }
        if (shouldFilter) {
            return nil;
        }
        if (shouldDisableHDR) {
            DYYYStripHDRHintsFromAwemeModel(self);
        }
    }
    return orig;
}

- (void)setVideo:(AWEVideoModel *)video {
    DYYYStripHDRHintsFromVideoModel(video);
    %orig;
}

- (AWEVideoModel *)video {
    return %orig;
}

- (void)setAlbumImages:(NSArray<AWEImageAlbumImageModel *> *)albumImages {
    if (DYYYShouldDisableAllHDR()) {
        for (AWEImageAlbumImageModel *imageModel in albumImages) {
            DYYYStripHDRHintsFromVideoModel(DYYYValuePreferringIvar(imageModel, "_clipVideo", @"clipVideo"));
        }
    }
    %orig;
}

- (NSArray<AWEImageAlbumImageModel *> *)albumImages {
    return %orig;
}

- (BOOL)awe_enableHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (id)awe_HDRValueFor:(long long)value enableHDR:(BOOL)enableHDR {
    return %orig(value, DYYYShouldDisableAllHDR() ? NO : enableHDR);
}

%new
- (BOOL)dyyy_shouldExcludeFromGlobalHDRFilter {
    NSString *referString = [self.referString lowercaseString];
    if (referString.length == 0) {
        return NO;
    }

    return [referString isEqualToString:@"chat"] ||
           [referString containsString:@"chat_room"] ||
           [referString containsString:@"message"] ||
           [referString containsString:@"forward"] ||
           [referString containsString:@"private"] ||
           [referString containsString:@"share"] ||
           [referString hasPrefix:@"im_"] ||
           [referString containsString:@"_im_"];
}

%new
- (BOOL)dyyy_containsHDRMetadataInObject:(id)object depth:(NSUInteger)depth {
    if (!object || depth > 8) {
        return NO;
    }

    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)object;
        for (id rawKey in dictionary) {
            id value = dictionary[rawKey];
            NSString *key = [[rawKey description] lowercaseString];
            NSInteger numericValue = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;

            if (([key isEqualToString:@"is_source_hdr"] || [key isEqualToString:@"has_filter_hdr"]) && numericValue > 0) {
                return YES;
            }
            if ([key isEqualToString:@"hdr_type"] && numericValue > 0) {
                return YES;
            }
            if ([key isEqualToString:@"hdr_bit"] && numericValue >= 10) {
                return YES;
            }
            if (([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) &&
                [self dyyy_containsHDRMetadataInObject:value depth:depth + 1]) {
                return YES;
            }
        }
    } else if ([object isKindOfClass:[NSArray class]]) {
        for (id value in (NSArray *)object) {
            if ([self dyyy_containsHDRMetadataInObject:value depth:depth + 1]) {
                return YES;
            }
        }
    }

    return NO;
}

%new
- (BOOL)contentFilter {
    BOOL noAds = DYYYGetBool(@"DYYYNoAds");
    BOOL skipAllLive = DYYYGetBool(@"DYYYSkipAllLive");
    BOOL skipHotSpot = DYYYGetBool(@"DYYYSkipHotSpot");
    BOOL skipPhoto = DYYYGetBool(@"DYYYSkipPhoto");
    BOOL skipPhotoText = DYYYGetBool(@"DYYYSkipPhotoText");
    BOOL skipMusic = DYYYGetBool(@"DYYYSkipMusic");
    BOOL skipAIInteraction = DYYYGetBool(@"DYYYSkipAIInteraction");
    BOOL filterHDR = DYYYShouldFilterGlobalHDR();

    BOOL shouldFilterAds = noAds && [DYYYUtils isAdvertisementAwemeModel:self];
    BOOL shouldFilterHotSpot = skipHotSpot && self.hotSpotLynxCardModel;
    BOOL shouldFilterAllLive = skipAllLive && [self.videoFeedTag isEqualToString:@"直播中"];
    BOOL isRecommendFeed = [self.referString isEqualToString:@"homepage_hot"];
    BOOL shouldskipPhoto = skipPhoto && (self.awemeType == 68) && isRecommendFeed;
    BOOL shouldskipPhotoText = skipPhotoText && self.isNewTextMode && isRecommendFeed;
    BOOL shouldFilterMusic = skipMusic && self.musicCard && isRecommendFeed;
    BOOL shouldFilterAIInteraction = skipAIInteraction && (self.awemeType == 162) && isRecommendFeed;
    BOOL shouldFilterHDR = NO;
    BOOL shouldFilterLowLikes = NO;
    BOOL shouldFilterKeywords = NO;
    BOOL shouldFilterProp = NO;
    BOOL shouldFilterTime = NO;
    BOOL shouldFilterUser = NO;

    // 获取用户设置的需要过滤的关键词
    NSString *filterKeywords = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterKeywords"];
    NSArray *keywordsList = nil;

    if (filterKeywords.length > 0) {
        keywordsList = [filterKeywords componentsSeparatedByString:@","];
    }

    // 过滤包含指定拍同款的视频
    NSString *filterProp = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterProp"];
    NSArray *propKeywordsList = nil;

    if (filterProp.length > 0) {
        propKeywordsList = [filterProp componentsSeparatedByString:@","];
    }

    // 获取需要过滤的用户列表
    NSString *filterUsers = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterUsers"];
    BOOL disableHDR = DYYYShouldDisableAllHDR();

    // 检查是否需要过滤特定用户
    if (isRecommendFeed && filterUsers.length > 0 && self.author) {
        NSArray *usersList = [filterUsers componentsSeparatedByString:@","];
        NSString *currentShortID = self.author.shortID;
        NSString *currentNickname = self.author.nickname;

        if (currentShortID.length > 0) {
            for (NSString *userInfo in usersList) {
                // 解析"昵称-id"格式
                NSArray *components = [userInfo componentsSeparatedByString:@"-"];
                if (components.count >= 2) {
                    NSString *userId = [components lastObject];
                    NSString *userNickname = [[components subarrayWithRange:NSMakeRange(0, components.count - 1)] componentsJoinedByString:@"-"];

                    if ([userId isEqualToString:currentShortID]) {
                        shouldFilterUser = YES;
                        break;
                    }
                }
            }
        }
    }

    // 仅在推荐页过滤关键词和道具
    if (isRecommendFeed) {
        // 过滤包含特定关键词的视频
        if (keywordsList.count > 0) {
            // 检查视频标题
            if (self.descriptionString.length > 0) {
                for (NSString *keyword in keywordsList) {
                    NSString *trimmedKeyword = [keyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (trimmedKeyword.length > 0 && [self.descriptionString containsString:trimmedKeyword]) {
                        shouldFilterKeywords = YES;
                        break;
                    }
                }
            }
        }

        // 过滤包含特定道具的视频
        if (propKeywordsList.count > 0 && self.propGuideV2) {
            NSString *propName = self.propGuideV2.propName;
            if (propName.length > 0) {
                for (NSString *propKeyword in propKeywordsList) {
                    NSString *trimmedKeyword = [propKeyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (trimmedKeyword.length > 0 && [propName containsString:trimmedKeyword]) {
                        shouldFilterProp = YES;
                        break;
                    }
                }
            }
        }
    }

    // 全局屏蔽 HDR 时，仍允许有 SDR 档的作品降档播放；纯 HDR 档作品直接过滤，避免黑屏或 HDR 漏出。
    if (disableHDR &&
        ![self dyyy_shouldExcludeFromGlobalHDRFilter] &&
        DYYYAwemeModelHasOnlyHDRBitrateModels(self)) {
        shouldFilterHDR = YES;
    }

    // 全场景过滤 HDR 作品，但保留私信、消息详情和转发链路。
    if (filterHDR && ![self dyyy_shouldExcludeFromGlobalHDRFilter] && self.video) {
        AWEVideoModel *video = self.video;
        if ([video respondsToSelector:@selector(isSourceHDR)] && video.isSourceHDR > 0) {
            shouldFilterHDR = YES;
        } else if ([video respondsToSelector:@selector(hasFilterHDR)] && video.hasFilterHDR) {
            shouldFilterHDR = YES;
        }

        if (!shouldFilterHDR) {
            for (id bitrateModel in video.bitrateModels) {
                @try {
                    NSNumber *hdrType = [bitrateModel valueForKey:@"hdrType"];
                    NSNumber *hdrBit = [bitrateModel valueForKey:@"hdrBit"];

                    // hdrType 覆盖 HDR10、HLG、HDR Vivid 等类型；无类型字段时保留 10bit 兜底。
                    if ((hdrType && [hdrType integerValue] > 0) ||
                        (!hdrType && hdrBit && [hdrBit integerValue] >= 10)) {
                        shouldFilterHDR = YES;
                        break;
                    }
                } @catch (__unused NSException *exception) {
                }
            }
        }
    }

    return shouldFilterAds || shouldFilterAllLive || shouldFilterHotSpot || shouldFilterMusic || shouldFilterHDR || shouldFilterKeywords || shouldFilterProp ||
           shouldFilterTime || shouldFilterUser;
}

- (AWEECommerceLabel *)ecommerceBelowLabel {
    if (DYYYGetBool(@"DYYYHideHisShop")) {
        return nil;
    }
    return %orig;
}

- (void)setEcommerceBelowLabel:(id)label {
	if (DYYYGetBool(@"DYYYHideHisShop")) {
		%orig(nil);
		return;
	}
	%orig;
}

- (void)setDescriptionString:(NSString *)desc {
    NSString *labelStyle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYLabelStyle"];
    BOOL hideLabel = [labelStyle isEqualToString:@"文案标签隐藏"];
    if (hideLabel) {
        // 过滤掉所有以 # 开头的标签
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"#\\S+" options:0 error:nil];
        NSString *filtered = [regex stringByReplacingMatchesInString:desc options:0 range:NSMakeRange(0, desc.length) withTemplate:@""];
        // 去除首尾空白字符
        filtered = [filtered stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // 为空则赋nil，避免显示空行
        desc = filtered.length > 0 ? filtered : nil;
    }
    %orig(desc);
}

- (void)setTextExtras:(NSArray *)extras {
    NSString *labelStyle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYLabelStyle"];
    BOOL disableLabelSearch = [labelStyle isEqualToString:@"文案标签禁止跳转搜索"] || [labelStyle isEqualToString:@"文案标签隐藏"];
    if (disableLabelSearch && [extras isKindOfClass:[NSArray class]]) {
        NSMutableArray *filtered = [NSMutableArray array];
        for (AWEAwemeTextExtraModel *model in extras) {
            if (model.userID.length > 0) {
                [filtered addObject:model];
            }
        }
        extras = [filtered copy];
    }
    %orig(extras);
}

// 固定设置为 1，启用自定义背景色
- (NSUInteger)awe_playerBackgroundViewShowType {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYVideoBGColor"]) {
        return 1;
    }
    return %orig;
}

- (UIColor *)awe_smartBackgroundColor {
    NSString *colorHex = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYVideoBGColor"];
    if (colorHex && colorHex.length > 0) {
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        UIColor *customColor = [DYYYUtils colorFromSchemeHexString:colorHex targetWidth:screenWidth];
        if (customColor)
            return customColor;
    }
    return %orig;
}

//屏蔽章节要点数据
- (NSArray *)chapterList {
	BOOL hideChapterList = DYYYGetBool(@"DYYYHideChapterProgress");
	if (hideChapterList) {
		return @[]; // 返回空数组
	}
	return %orig;
}

// 屏蔽共创数据
- (id)acceptedCoCreators {
	BOOL DYYYHideGongChuang = DYYYGetBool(@"DYYYHideGongChuang");
	if (DYYYHideGongChuang) {
		return @[]; // 永远为空
	}
	return %orig;
}

- (id)unAcceptedCoCreators {
	BOOL DYYYHideGongChuang = DYYYGetBool(@"DYYYHideGongChuang");
	if (DYYYHideGongChuang) {
		return @[];
	}
	return %orig;
}

- (NSInteger)acceptedCoCreatorsNums {
	BOOL DYYYHideGongChuang = DYYYGetBool(@"DYYYHideGongChuang");
	if (DYYYHideGongChuang) {
		return 0;
	}
	return %orig;
}

- (id)awe_coCreatorPoster {
	BOOL DYYYHideGongChuang = DYYYGetBool(@"DYYYHideGongChuang");
	if (DYYYHideGongChuang) {
		return nil;
	}
	return %orig;
}

- (id)awe_coCreatorFromAuthor {
	BOOL DYYYHideGongChuang = DYYYGetBool(@"DYYYHideGongChuang");
	if (DYYYHideGongChuang) {
		return nil;
	}
	return %orig;
}

- (id)awe_userModelWithCoCreator:(id)creator {
	BOOL DYYYHideGongChuang = DYYYGetBool(@"DYYYHideGongChuang");
	if (DYYYHideGongChuang) {
		return nil;
	}
	return %orig;
}


// 屏蔽相关视频推荐
- (id)relatedVideoExtra {
	BOOL DYYYHideBottomRelated = DYYYGetBool(@"DYYYHideBottomRelated");
	if (DYYYHideBottomRelated) {
		return nil;
	}
	return %orig;
}

- (id)relatedVideo {
	BOOL DYYYHideBottomRelated = DYYYGetBool(@"DYYYHideBottomRelated");
	if (DYYYHideBottomRelated) {
		return nil;
	}
	return %orig;
}

- (id)playletRelatedVideoInfoModel {
	BOOL DYYYHideBottomRelated = DYYYGetBool(@"DYYYHideBottomRelated");
	if (DYYYHideBottomRelated) {
		return nil;
	}
	return %orig;
}

// 屏蔽评论搜索锚点
- (id)commonSearchAnchor {
	BOOL DYYYHideCommentLongPressSearch = DYYYGetBool(@"DYYYHideCommentLongPressSearch");
	if (DYYYHideCommentLongPressSearch) {
		return nil;
	}
	return %orig;
}

- (void)setCommonSearchAnchor:(id)arg {
	BOOL DYYYHideCommentLongPressSearch = DYYYGetBool(@"DYYYHideCommentLongPressSearch");
	if (DYYYHideCommentLongPressSearch) {
		%orig(nil);
		return;
	}
	%orig;
}

// 屏蔽汽水音乐锚点
- (id)relatedMusicAnchor {
	BOOL DYYYHideQuqishuiting = DYYYGetBool(@"DYYYHideQuqishuiting");
	if (DYYYHideQuqishuiting) {
		return nil;
	}
	return %orig;
}

- (void)setRelatedMusicAnchor:(id)anchor {
	BOOL DYYYHideQuqishuiting = DYYYGetBool(@"DYYYHideQuqishuiting");
	if (DYYYHideQuqishuiting) {
		%orig(nil);
		return;
	}
	%orig;
}

// 屏蔽底栏热点
- (id)hotSpotRawData {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return nil;
	}
	return %orig;
}

- (void)setHotSpotRawData:(id)data {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		%orig(nil);
		return;
	}
	%orig;
}

- (id)hotSpotListModel {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return nil;
	}
	return %orig;
}

- (void)setHotSpotListModel:(id)model {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		%orig(nil);
		return;
	}
	%orig;
}

- (NSString *)templateBarsString {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return @"";
	}
	return %orig;
}

- (void)setTemplateBarsString:(NSString *)string {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		%orig(@"");
		return;
	}
	%orig;
}

// 旧版本回退：没有可用的合集显示接口时，沿用推荐页屏蔽逻辑。
- (id)mixInfo {
	BOOL DYYYHideTemplateVideo = DYYYGetBool(@"DYYYHideTemplateVideo");
	if (!dyyyVideoMixBarVisibilityHookEnabled && DYYYHideTemplateVideo && [self.referString isEqualToString:@"homepage_hot"]) {
		return nil;
	}
	return %orig;
}

// 屏蔽短剧信息（复用屏蔽合集开关，只对推荐页生效）
- (id)playletInfoModel {
	BOOL DYYYHideTemplatePlaylet = DYYYGetBool(@"DYYYHideTemplatePlaylet");
	if (DYYYHideTemplatePlaylet && [self.referString isEqualToString:@"homepage_hot"]) {
		return nil;
	}
	return %orig;
}

// 屏蔽锚点信息
- (id)anchorInfo {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		return nil;
	}
	return %orig;
}

- (void)setAnchorInfo:(id)info {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		%orig(nil);
		return;
	}
	%orig;
}

- (id)localLifeAnchorInfo {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		return nil;
	}
	return %orig;
}

- (void)setLocalLifeAnchorInfo:(id)info {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		%orig(nil);
		return;
	}
	%orig;
}

- (id)nearbyFeedDualAnchorInfo {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		return nil;
	}
	return %orig;
}

- (void)setNearbyFeedDualAnchorInfo:(id)info {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		%orig(nil);
		return;
	}
	%orig;
}

- (id)minorAnchorInfo {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		return nil;
	}
	return %orig;
}

- (void)setMinorAnchorInfo:(id)info {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		%orig(nil);
		return;
	}
	%orig;
}

// 屏蔽通用锚点（合并到锚点信息）
- (id)commonAnchor {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) { 
		return nil;
	}
	return %orig;
}

- (void)setCommonAnchor:(id)anchor {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		%orig(nil);
		return;
	}
	%orig;
}

// 屏蔽作者声明及风险提示
- (id)riskInfoModel {
	BOOL DYYYHideAntiAddictedNotice = DYYYGetBool(@"DYYYHideAntiAddictedNotice");
	if (DYYYHideAntiAddictedNotice) {
		return nil;
	}
	return %orig;
}

- (void)setRiskInfoModel:(id)model {
	BOOL DYYYHideAntiAddictedNotice = DYYYGetBool(@"DYYYHideAntiAddictedNotice");
	if (DYYYHideAntiAddictedNotice) {
		%orig(nil);
		return;
	}
	%orig;
}

%end


//以下部分为新增
// 屏蔽头像直播
%hook AWEUserModel

- (NSNumber *)roomID {
	BOOL DYYYHideAvatarLive = DYYYGetBool(@"DYYYHideAvatarLive") || DYYYGetBool(@"DYYYHideAvatarButton");
	if (DYYYHideAvatarLive) {
		return @(0);
	}
	return %orig;
}

%end


// 屏蔽头像光圈
%hook AWEUserModel

- (id)storyRing {
	BOOL DYYYHideAvatarButton = DYYYGetBool(@"DYYYHideAvatarButton");
	if (DYYYHideAvatarButton) {
		return nil;
	}
	return %orig;
}

- (void)setStoryRing:(id)ring {
	BOOL DYYYHideAvatarButton = DYYYGetBool(@"DYYYHideAvatarButton");
	if (DYYYHideAvatarButton) {
		%orig(nil);
		return;
	}
	%orig;
}

%end

%hook AWECodeGenStoryRingInfoModel

- (NSArray *)storyRingsModelArray {
	BOOL DYYYHideAvatarButton = DYYYGetBool(@"DYYYHideAvatarButton");
	if (DYYYHideAvatarButton) {
		return @[];
	}
	return %orig;
}

- (void)setStoryRingsModelArray:(NSArray *)array {
	BOOL DYYYHideAvatarButton = DYYYGetBool(@"DYYYHideAvatarButton");
	if (DYYYHideAvatarButton) {
		%orig(@[]);
		return;
	}
	%orig;
}

%end

// 屏蔽挑战贴纸
%hook AWEInteractionHashtagStickerModel

- (id)hashtagInfo {
	BOOL DYYYHideChallengeStickers = DYYYGetBool(@"DYYYHideChallengeStickers");
	if (DYYYHideChallengeStickers) {
		return nil;
	}
	return %orig;
}

- (void)setHashtagInfo:(id)info {
	BOOL DYYYHideChallengeStickers = DYYYGetBool(@"DYYYHideChallengeStickers");
	if (DYYYHideChallengeStickers) {
		%orig(nil);
		return;
	}
	%orig;
}

- (id)hashtagId {
	BOOL DYYYHideChallengeStickers = DYYYGetBool(@"DYYYHideChallengeStickers");
	if (DYYYHideChallengeStickers) {
		return nil;
	}
	return %orig;
}

- (id)hashtagName {
	BOOL DYYYHideChallengeStickers = DYYYGetBool(@"DYYYHideChallengeStickers");
	if (DYYYHideChallengeStickers) {
		return nil;
	}
	return %orig;
}

%end

// 屏蔽互动贴纸
%hook AWEInteractionEditTagStickerModel

- (id)editTagInfo {
	if (DYYYGetBool(@"DYYYHideEditTag")) {
		return nil;
	}
	return %orig;
}

- (void)setEditTagInfo:(id)info {
	if (DYYYGetBool(@"DYYYHideEditTag")) {
		%orig(nil);
		return;
	}
	%orig;
}

%end


// 隐藏下面底部热点框
%hook AWEHotSpotListModel

- (BOOL)disableDisplay {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return YES;
	}
	return %orig;
}

- (BOOL)disableDisplayInner {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return YES;
	}
	return %orig;
}

- (NSString *)hotSpotTipTitleHeader {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return @"";
	}
	return %orig;
}

- (NSString *)hotSpotTipTitle {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return @"";
	}
	return %orig;
}

- (NSString *)hotSpotTipTitleFooter {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return @"";
	}
	return %orig;
}

- (NSString *)hotInfoWord {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return @"";
	}
	return %orig;
}

- (NSString *)i18NTipTitle {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return @"";
	}
	return %orig;
}

- (NSString *)tipSchema {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return nil;
	}
	return %orig;
}

- (NSDictionary *)extraDictionary {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return @{};
	}
	return %orig;
}

- (NSDictionary *)relativityExtra {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return @{};
	}
	return %orig;
}

%end

// 屏蔽精选标签
%hook AWETemplateStaticLabelInfoModel

- (NSArray *)containers {
	if (DYYYGetBool(@"DYYYHideTemplateLabel")) {
		return @[];
	}
	return %orig;
}

- (void)setContainers:(NSArray *)containers {
	if (DYYYGetBool(@"DYYYHideTemplateLabel")) {
		%orig(@[]);
		return;
	}
	%orig;
}

%end

// 隐藏好友推荐
%hook AFDFriendRecommendTagView

- (void)layoutSubviews {
	if (DYYYGetBool(@"DYYYHideFriendRecommend")) {
		self.hidden = YES;
		return;
	}
	%orig;
}

%end

// 屏蔽汽水音乐锚点 - hook AWERelatedMusicAnchorModel
%hook AWERelatedMusicAnchorModel

- (instancetype)init {
	BOOL DYYYHideQuqishuiting = DYYYGetBool(@"DYYYHideQuqishuiting");
	if (DYYYHideQuqishuiting) {
		return nil;
	}
	return %orig;
}

- (instancetype)initWithDictionary:(id)dict error:(NSError **)error {
	BOOL DYYYHideQuqishuiting = DYYYGetBool(@"DYYYHideQuqishuiting");
	if (DYYYHideQuqishuiting) {
		return nil;
	}
	return %orig;
}

%end

// 屏蔽汽水音乐 - 清空 commentTopBarInfo
%hook AWEMusicExtraModel

- (id)commentTopBarInfo {
	BOOL DYYYHideQuqishuiting = DYYYGetBool(@"DYYYHideQuqishuiting");
	if (DYYYHideQuqishuiting) {
		return nil;
	}
	return %orig;
}

- (void)setCommentTopBarInfo:(id)info {
	BOOL DYYYHideQuqishuiting = DYYYGetBool(@"DYYYHideQuqishuiting");
	if (DYYYHideQuqishuiting) {
		%orig(nil);
		return;
	}
	%orig;
}

%end


// 拦截开屏广告 - hook TTAdSplashModel，直接返回 nil
%hook TTAdSplashModel

+ (id)alloc {
	if (DYYYGetBool(@"DYYYNoAds")) {
		return nil;  // 直接返回 nil，阻止对象创建
	}
	return %orig;
}

%end

%hook AWEOriginalAdModel
- (instancetype)init {
	BOOL noAds = DYYYGetBool(@"DYYYNoAds");
	if (noAds) {
		return nil;  // 阻止创建，直接返回 nil
	}
	return %orig;
}

- (instancetype)initWithDictionary:(id)dict error:(NSError **)error {
	BOOL noAds = DYYYGetBool(@"DYYYNoAds");
	if (noAds) {
		return nil;  // 阻止创建，直接返回 nil
	}
	return %orig;
}
%end

// 屏蔽 AWEGeneralSearchModel 中的广告卡（搜索卡片、动态卡及其作品模型统一判定）
%hook AWEGeneralSearchModel
- (instancetype)initWithDictionary:(id)dict error:(NSError **)error {
	id orig = %orig;
	
	BOOL noAds = DYYYGetBool(@"DYYYNoAds");
	if (!noAds || !orig) {
		return orig;
	}
	
	if ([DYYYUtils isAdvertisementContainerModel:orig] || [DYYYUtils isAdvertisementRawData:dict]) {
		return nil;
	}
	
	return orig;
}
%end

// 去除启动视频广告
%hook AWEAwesomeSplashFeedCellOldAccessoryView

// 在方法入口处添加控制逻辑
- (id)ddExtraView {
	if (DYYYGetBool(@"DYYYNoAds")) {
		return NULL; // 返回空视图
	}

	// 正常模式调用原始方法
	return %orig;
}

%end

// 屏蔽青少年模式弹窗
%hook AWETeenModeAlertView
- (BOOL)show {
	if (DYYYGetBool(@"DYYYHideTeenMode")) {
		return NO;
	}
	return %orig;
}
%end

// 屏蔽青少年模式弹窗
%hook AWETeenModeSimpleAlertView
- (BOOL)show {
	if (DYYYGetBool(@"DYYYHideTeenMode")) {
		return NO;
	}
	return %orig;
}
%end


%hook AWEFeedCommentConfigModel
- (void)setCommentInputConfigText:(NSString *)text {
    NSString *customText = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYCommentContent"];
    if (customText && customText.length > 0) {
        text = customText;
    }
    %orig(text);
}
%end

// 推荐、搜索及详情页共用合集底栏的显示判断，保留作品的合集数据。
%group DYYYVideoMixBarVisibilityGroup
%hook AWEPlayInteractionNewMixVideoInfoElement
- (BOOL)shouldAppearWithData:(AWEAwemeModel *)data {
    if (!DYYYGetBool(@"DYYYHideTemplateVideo")) {
        return %orig(data);
    }

    // 原生判断会同步此状态；复用页面时也必须清除，避免残留显示标记。
    AWEContextStore *context = self.context;
    if ([context isKindOfClass:%c(AWEContextStore)]) {
        [context setBool:NO forKey:@"shouldShowMixVideo"];
    }
    return NO;
}
%end
%end

%hook AWEAwemeStatusModel
- (void)setListenVideoStatus:(NSInteger)status {
    if (status == 1 && DYYYGetBool(@"DYYYEnableBackgroundListen")) {
        status = 2;
    }
    %orig(status);
}
%end

%hook MTKView

- (void)layoutSubviews {
    %orig;
    DYYYDisableExtendedRangeForLayer(self.layer);
    UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:self];
    Class playVCClass = NSClassFromString(@"AWEPlayVideoViewController");
    if (vc && playVCClass && [vc isKindOfClass:playVCClass]) {
        NSString *colorHex = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYVideoBGColor"];
        if (colorHex && colorHex.length > 0) {
            CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
            UIColor *customColor = [DYYYUtils colorFromSchemeHexString:colorHex targetWidth:screenWidth];
            if (customColor)
                self.backgroundColor = customColor;
        }
    }
}

%end

%hook AWEPlayInteractionUserAvatarView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideAvatarButton")) {
        DYYYHideAvatarVisualForSelector(self, NSSelectorFromString(@"userAvatarView"));
        DYYYApplyAvatarSurroundingSettingsForOwner(self);
    }

    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)didMoveToWindow {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)didMoveToSuperview {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)updateRightContainerElement {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)p_resetFollowAnimation {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playFollowAnimation:(id)completion {
    %orig(completion);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playUnFollowAnimation {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)changeSendMessageViewWithFlag:(BOOL)flag {
    %orig(flag);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}
%end

%hook AWEPlayInteractionUserAvatarFollowPromptController
- (void)onFollowViewClicked:(UITapGestureRecognizer *)gesture {
    if (DYYYGetBool(@"DYYYHideFollowPromptView"))
        return;
    if (!DYYYGetBool(@"DYYYFollowTips")) {
        %orig;
        return;
    }
    AWEUserModel *author = self.userAvatarContext.model.author;
    NSString *userID = author.userID;
    [DYYYBottomAlertView showFollowConfirmationForUser:author avatarView:self.userAvatarContext.avatarPicView confirmAction:^{
        if (![self.userAvatarContext.model.author.userID isEqualToString:userID]) {
            [DYYYUtils showToast:@"当前作品已切换，请重新确认"];
            return;
        }
        %orig(gesture);
    }];
}

- (void)onUnFollowViewClicked:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}

- (void)followPromptViewClicked:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}

- (void)layoutElementView {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (BOOL)shouldShowFollowAddWithModel:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return NO;
    }
    return %orig(arg1);
}

- (BOOL)shouldShowSpecialFollowWithModel:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return NO;
    }
    return %orig(arg1);
}

- (void)showFollowAddView:(BOOL)show {
    %orig(show);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_willDisplay {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_viewDidAppear {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)updateFollowStatus {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)followStatusChanged:(id)arg1 {
    %orig(arg1);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playFollowAnimation {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playFollowAnimation:(id)completion {
    %orig(completion);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playUnFollowAnimation {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)_ensureStaticFollowAnimationView {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}
%end

%hook AWEPlayInteractionUserAvatarMainBusinessController
- (void)layoutElementView {
    %orig;
    if (DYYYGetBool(@"DYYYHideAvatarButton")) {
        DYYYHideAvatarVisualForSelector(self, NSSelectorFromString(@"avatarPicView"));
        id context = DYYYAvatarObjectForSelector(self, NSSelectorFromString(@"userAvatarContext"));
        DYYYHideAvatarVisualForSelector(context, NSSelectorFromString(@"avatarPicView"));
        DYYYApplyAvatarSurroundingSettingsForOwner(self);
    }
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}
%end

%hook AWEPlayInteractionUserAvatarOptElementElement
- (void)layoutElementView {
    %orig;
    if (DYYYGetBool(@"DYYYHideAvatarButton")) {
        id context = DYYYAvatarObjectForSelector(self, NSSelectorFromString(@"userAvatarContext"));
        DYYYHideAvatarVisualForSelector(context, NSSelectorFromString(@"avatarPicView"));
        DYYYApplyAvatarSurroundingSettingsForOwner(self);
    }
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_willDisplay {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_viewDidAppear {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)setAppear:(BOOL)appear {
    %orig(appear);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}
%end

%hook AWEPlayInteractionUserAvatarStoryController
- (void)layoutElementView {
    %orig;
    DYYYApplyAvatarSurroundingSettingsForOwner(self);
}

- (void)showStory25RingView {
    %orig;
    DYYYApplyAvatarSurroundingSettingsForOwner(self);
}
%end

%hook AWEPlayInteractionUserAvatarDecorationController
- (void)layoutElementView {
    %orig;
    DYYYApplyAvatarSurroundingSettingsForOwner(self);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_willDisplay {
    %orig;
    DYYYApplyAvatarSurroundingSettingsForOwner(self);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)setDecorationStyle:(long long)style {
    %orig(style);
    DYYYApplyAvatarSurroundingSettingsForOwner(self);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}
%end

%hook AWEPlayInteractionUserAvatarSendMessageController
- (void)controllerViewDidLayout {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)controllerStartConfigAvatarView:(id)view {
    %orig(view);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(view);
}

- (void)controllerWillDisplay {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)controllerPlay {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)controllerReset {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)updateSendMessageView:(BOOL)show {
    %orig(show);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)p_updateSendMessageView:(BOOL)show {
    %orig(show);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)p_showSendMessageView:(id)view shouldShowSendMessageView:(BOOL)show animated:(BOOL)animated completion:(id)completion {
    %orig(view, show, animated, completion);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(view);
}

- (BOOL)shouldShowSendMessageView {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return NO;
    }
    return %orig;
}

- (BOOL)shouldShowSendMessageGuideAnimation {
    if (DYYYAvatarFollowOptionsEnabled()) {
        return NO;
    }
    return %orig;
}

- (void)playSendMessageGuideAnimationIfNeeded {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)onSendMessageViewClicked:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}
%end

%hook AWEPlayInteractionUserAvatarSendMsgController
- (void)layoutElementView {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_willDisplay {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_viewDidDisappear {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)play {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)reset {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)changeSendMessageViewWithFlag:(BOOL)flag {
    %orig(flag);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)showSendMessageView:(id)view show:(BOOL)show animated:(BOOL)animated completion:(id)completion {
    %orig(view, show, animated, completion);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(view);
}

- (void)showSendMessageViewWithAnimation:(BOOL)animated {
    %orig(animated);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (BOOL)shouldShowSendMessageView:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return NO;
    }
    return %orig(arg1);
}

- (BOOL)shouldShowSendMessageGuideAnimation {
    if (DYYYAvatarFollowOptionsEnabled()) {
        return NO;
    }
    return %orig;
}

- (void)updateSendMsgWithFollowShow:(BOOL)show animation:(BOOL)animated {
    %orig(show, animated);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)handleAvatarFollowStatusChange:(id)arg1 {
    %orig(arg1);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playSendMessageGuideAnimationIfNeeded {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)onSendMessageViewClicked:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}
%end

%hook AWEPlayInteractionUserAvatarEnterStoreController
- (void)layoutElementView {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_willDisplay {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_viewDidAppear {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)play {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)reset {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)showEnterStore {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)hideEnterStore {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (BOOL)shouldShowEnterStoreView {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return NO;
    }
    return %orig;
}

- (BOOL)shouldShowEnterStoreGuideAnimation {
    if (DYYYAvatarFollowOptionsEnabled()) {
        return NO;
    }
    return %orig;
}

- (void)playEnterStoreGuideAnimationIfNeeded {
    if (DYYYAvatarFollowOptionsEnabled()) {
        DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
        return;
    }
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)handleAvatarFollowStatusChange:(id)arg1 {
    %orig(arg1);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)onEnterStoreViewClicked:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}
%end

%hook AWEPlayInteractionUserAvatarAdLinkController
- (void)layoutElementView {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)reset {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)updateCommerceHotSplashLinkIconImageIfNeeded:(id)arg1 {
    %orig(arg1);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)onLinkIconContainerViewClicked:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}
%end

%hook AWEPlayInteractionViewController

- (void)performCommentAction {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)setIsCommentVCShowing:(BOOL)showing {
    %orig(showing);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)onPlayer:(id)arg0 didDoubleClick:(id)arg1 {
    BOOL isPopupEnabled = DYYYGetBool(@"DYYYEnableDoubleTapMenu");
    BOOL isDirectCommentEnabled = DYYYGetBool(@"DYYYEnableDoubleOpenComment");

    // 直接打开评论区的情况
    if (isDirectCommentEnabled) {
        [self performCommentAction];
        return;
    }

    if (isPopupEnabled) {
        AWEAwemeModel *awemeModel = nil;

        awemeModel = [self performSelector:@selector(awemeModel)];

        AWEVideoModel *videoModel = awemeModel.video;
        AWEMusicModel *musicModel = awemeModel.music;
        NSURL *audioURL = nil;
        if (musicModel && musicModel.playURL && musicModel.playURL.originURLList.count > 0) {
            audioURL = [NSURL URLWithString:musicModel.playURL.originURLList.firstObject];
        }

        // 确定内容类型（视频或图片）
        BOOL isImageContent = (awemeModel.awemeType == 68);
        // 判断是否为新版实况照片
        BOOL isNewLivePhoto = (awemeModel.video && awemeModel.animatedImageVideoInfo != nil);
        NSString *downloadTitle;

        if (isImageContent) {
            AWEImageAlbumImageModel *currentImageModel = nil;
            if (awemeModel.currentImageIndex > 0 && awemeModel.currentImageIndex <= awemeModel.albumImages.count) {
                currentImageModel = awemeModel.albumImages[awemeModel.currentImageIndex - 1];
            } else {
                currentImageModel = awemeModel.albumImages.firstObject;
            }

            if (awemeModel.albumImages.count > 1) {
                downloadTitle = (currentImageModel.clipVideo != nil || awemeModel.isLivePhoto) ? @"保存当前实况" : @"保存当前图片";
            } else {
                downloadTitle = (currentImageModel.clipVideo != nil || awemeModel.isLivePhoto) ? @"保存实况" : @"保存图片";
            }
        } else if (isNewLivePhoto) {
            downloadTitle = @"保存实况";
        } else {
            downloadTitle = @"保存视频";
        }

        AWEUserActionSheetView *actionSheet = [[NSClassFromString(@"AWEUserActionSheetView") alloc] init];
        NSMutableArray *actions = [NSMutableArray array];

        // 添加下载选项
        if (DYYYGetBool(@"DYYYDoubleTapDownload") || ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapDownload"]) {

            AWEUserSheetAction *downloadAction = [NSClassFromString(@"AWEUserSheetAction")
                actionWithTitle:downloadTitle
                        imgName:nil
                        handler:^{
                          if (isImageContent) {
                              // 图片内容
                              AWEImageAlbumImageModel *currentImageModel = nil;
                              if (awemeModel.currentImageIndex > 0 && awemeModel.currentImageIndex <= awemeModel.albumImages.count) {
                                  currentImageModel = awemeModel.albumImages[awemeModel.currentImageIndex - 1];
                              } else {
                                  currentImageModel = awemeModel.albumImages.firstObject;
                              }

                              // 查找非.image后缀的URL
                              NSURL *downloadURL = nil;
                              for (NSString *urlString in currentImageModel.urlList) {
                                  NSURL *url = [NSURL URLWithString:urlString];
                                  NSString *pathExtension = [url.path.lowercaseString pathExtension];
                                  if (![pathExtension isEqualToString:@"image"]) {
                                      downloadURL = url;
                                      break;
                                  }
                              }

                              if (currentImageModel.clipVideo != nil) {
                                  NSURL *videoURL = [currentImageModel.clipVideo.playURL getDYYYSrcURLDownload];
                                  [DYYYManager downloadLivePhoto:downloadURL
                                                        videoURL:videoURL
                                                      completion:^{
                                                      }];
                              } else if (currentImageModel && currentImageModel.urlList.count > 0) {
                                  if (downloadURL) {
                                      [DYYYManager downloadMedia:downloadURL
                                                       mediaType:MediaTypeImage
                                                           audio:nil
                                                      completion:^(BOOL success) {
                                                        if (success) {
                                                        } else {
                                                            [DYYYUtils showToast:@"图片保存已取消"];
                                                        }
                                                      }];
                                  } else {
                                      [DYYYUtils showToast:@"没有找到合适格式的图片"];
                                  }
                              }
                          } else if (isNewLivePhoto) {
                              // 新版实况照片
                              // 使用封面URL作为图片URL
                              NSURL *imageURL = nil;
                              if (videoModel.coverURL && videoModel.coverURL.originURLList.count > 0) {
                                  imageURL = [NSURL URLWithString:videoModel.coverURL.originURLList.firstObject];
                              }

                              // 视频URL从视频模型获取
                              NSURL *videoURL = nil;
                              if (videoModel && videoModel.playURL && videoModel.playURL.originURLList.count > 0) {
                                  videoURL = [NSURL URLWithString:videoModel.playURL.originURLList.firstObject];
                              } else if (videoModel && videoModel.h264URL && videoModel.h264URL.originURLList.count > 0) {
                                  videoURL = [NSURL URLWithString:videoModel.h264URL.originURLList.firstObject];
                              }

                              // 下载实况照片
                              if (imageURL && videoURL) {
                                  [DYYYManager downloadLivePhoto:imageURL
                                                        videoURL:videoURL
                                                      completion:^{
                                                      }];
                              }
                          } else {
                              if (videoModel.h264URL && videoModel.h264URL.originURLList.count > 0) {
                                  NSURL *url = [NSURL URLWithString:videoModel.h264URL.originURLList.firstObject];
                                  [DYYYManager downloadMedia:url
                                                   mediaType:MediaTypeVideo
                                                       audio:audioURL
                                                  completion:^(BOOL success){
                                                  }];
                              }
                          }
                        }];
            [actions addObject:downloadAction];

            // 如果是图集，添加下载所有图片选项
            if (isImageContent && awemeModel.albumImages.count > 1) {
                // 检查是否有实况照片
                BOOL hasLivePhoto = NO;
                for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
                    if (imageModel.clipVideo != nil) {
                        hasLivePhoto = YES;
                        break;
                    }
                }

                NSString *actionTitle = hasLivePhoto ? @"保存所有实况" : @"保存所有图片";

                AWEUserSheetAction *downloadAllAction = [NSClassFromString(@"AWEUserSheetAction")
                    actionWithTitle:actionTitle
                            imgName:nil
                            handler:^{
                              NSMutableArray *imageURLs = [NSMutableArray array];
                              NSMutableArray *livePhotos = [NSMutableArray array];

                              for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
                                  if (imageModel.urlList.count > 0) {
                                      // 查找非.image后缀的URL
                                      NSURL *downloadURL = nil;
                                      for (NSString *urlString in imageModel.urlList) {
                                          NSURL *url = [NSURL URLWithString:urlString];
                                          NSString *pathExtension = [url.path.lowercaseString pathExtension];
                                          if (![pathExtension isEqualToString:@"image"]) {
                                              downloadURL = url;
                                              break;
                                          }
                                      }

                                      if (!downloadURL && imageModel.urlList.count > 0) {
                                          downloadURL = [NSURL URLWithString:imageModel.urlList.firstObject];
                                      }

                                      // 检查是否是实况照片
                                      if (imageModel.clipVideo != nil) {
                                          NSURL *videoURL = [imageModel.clipVideo.playURL getDYYYSrcURLDownload];
                                          [livePhotos addObject:@{@"imageURL" : downloadURL.absoluteString, @"videoURL" : videoURL.absoluteString}];
                                      } else {
                                          [imageURLs addObject:downloadURL.absoluteString];
                                      }
                                  }
                              }

                              if (livePhotos.count > 0 || imageURLs.count > 0)
                                  [DYYYManager downloadImages:imageURLs livePhotos:livePhotos];

                              if (livePhotos.count == 0 && imageURLs.count == 0) {
                                  [DYYYUtils showToast:@"没有找到合适格式的图片"];
                              }
                            }];
                [actions addObject:downloadAllAction];
            }
        }

        // 添加下载音频选项
        if (DYYYGetBool(@"DYYYDoubleTapDownloadAudio") || ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapDownloadAudio"]) {

            AWEUserSheetAction *downloadAudioAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"保存音频"
                                                                                                        imgName:nil
                                                                                                        handler:^{
                                                                                                          if (musicModel && musicModel.playURL && musicModel.playURL.originURLList.count > 0) {
                                                                                                              NSURL *url = [NSURL URLWithString:musicModel.playURL.originURLList.firstObject];
                                                                                                              [DYYYManager downloadMedia:url mediaType:MediaTypeAudio audio:nil completion:nil];
                                                                                                          }
                                                                                                        }];
            [actions addObject:downloadAudioAction];
        }

        // 添加接口保存选项
        if (DYYYGetBool(@"DYYYDoubleInterfaceDownload")) {
            NSString *apiKey = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYInterfaceDownload"];
            if (apiKey.length > 0) {
                AWEUserSheetAction *apiDownloadAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"接口保存"
                                                                                                          imgName:nil
                                                                                                          handler:^{
                                                                                                            NSString *shareLink = [awemeModel valueForKey:@"shareURL"];
                                                                                                            if (shareLink.length == 0) {
                                                                                                                [DYYYUtils showToast:@"无法获取分享链接"];
                                                                                                                return;
                                                                                                            }

                                                                                                            // 使用封装的方法进行解析下载
                                                                                                            [DYYYManager parseAndDownloadVideoWithShareLink:shareLink apiKey:apiKey];
                                                                                                          }];
                [actions addObject:apiDownloadAction];
            }
        }

        // 添加制作视频功能
        if (DYYYGetBool(@"DYYYDoubleCreateVideo") || ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleCreateVideo"]) {
            if (isImageContent) {
                AWEUserSheetAction *createVideoAction = [NSClassFromString(@"AWEUserSheetAction")
                    actionWithTitle:@"制作视频"
                            imgName:nil
                            handler:^{
                              // 收集普通图片URL
                              NSMutableArray *imageURLs = [NSMutableArray array];
                              // 收集实况照片信息（图片URL+视频URL）
                              NSMutableArray *livePhotos = [NSMutableArray array];

                              // 获取背景音乐URL
                              NSString *bgmURL = nil;
                              if (musicModel && musicModel.playURL && musicModel.playURL.originURLList.count > 0) {
                                  bgmURL = musicModel.playURL.originURLList.firstObject;
                              }

                              // 处理所有图片和实况
                              for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
                                  if (imageModel.urlList.count > 0) {
                                      // 查找非.image后缀的URL
                                      NSString *bestURL = nil;
                                      for (NSString *urlString in imageModel.urlList) {
                                          NSURL *url = [NSURL URLWithString:urlString];
                                          NSString *pathExtension = [url.path.lowercaseString pathExtension];
                                          if (![pathExtension isEqualToString:@"image"]) {
                                              bestURL = urlString;
                                              break;
                                          }
                                      }

                                      if (!bestURL && imageModel.urlList.count > 0) {
                                          bestURL = imageModel.urlList.firstObject;
                                      }

                                      // 如果是实况照片，需要收集图片和视频URL
                                      if (imageModel.clipVideo != nil) {
                                          NSURL *videoURL = [imageModel.clipVideo.playURL getDYYYSrcURLDownload];
                                          if (videoURL) {
                                              [livePhotos addObject:@{@"imageURL" : bestURL, @"videoURL" : videoURL.absoluteString}];
                                          }
                                      } else {
                                          // 普通图片
                                          [imageURLs addObject:bestURL];
                                      }
                                  }
                              }

                              // 调用视频创建API
                              [DYYYManager createVideoFromMedia:imageURLs
                                  livePhotos:livePhotos
                                  bgmURL:bgmURL
                                  progress:^(NSInteger current, NSInteger total, NSString *status) {
                                  }
                                  completion:^(BOOL success, NSString *message) {
                                    if (success) {
                                    } else {
                                        [DYYYUtils showToast:[NSString stringWithFormat:@"视频制作失败: %@", message]];
                                    }
                                  }];
                            }];
                [actions addObject:createVideoAction];
            }
        }

        // 添加复制文案选项
        if (DYYYGetBool(@"DYYYDoubleTapCopyDesc") || ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapCopyDesc"]) {

            AWEUserSheetAction *copyTextAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"复制文案"
                                                                                                   imgName:nil
                                                                                                   handler:^{
                                                                                                     NSString *descText = [awemeModel valueForKey:@"descriptionString"];
                                                                                                     [[UIPasteboard generalPasteboard] setString:descText];
                                                                                                     [DYYYToast showSuccessToastWithMessage:@"文案已复制"];
                                                                                                   }];
            [actions addObject:copyTextAction];
        }

        // 添加打开评论区选项
        if (DYYYGetBool(@"DYYYDoubleTapComment") || ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapComment"]) {

            AWEUserSheetAction *openCommentAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"打开评论"
                                                                                                      imgName:nil
                                                                                                      handler:^{
                                                                                                        [self performCommentAction];
                                                                                                      }];
            [actions addObject:openCommentAction];
        }

        // 添加分享选项
        if (DYYYGetBool(@"DYYYDoubleTapshowSharePanel") || ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapshowSharePanel"]) {

            AWEUserSheetAction *showSharePanel = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"分享视频"
                                                                                                   imgName:nil
                                                                                                   handler:^{
                                                                                                     [self showSharePanel];
                                                                                                   }];
            [actions addObject:showSharePanel];
        }

        // 添加点赞视频选项
        if (DYYYGetBool(@"DYYYDoubleTapLike") || ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapLike"]) {

            AWEUserSheetAction *likeAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"点赞视频"
                                                                                               imgName:nil
                                                                                               handler:^{
                                                                                                 [self performLikeAction];
                                                                                               }];
            [actions addObject:likeAction];
        }

        // 添加长按面板
        if (DYYYGetBool(@"DYYYDoubleTapshowDislikeOnVideo") || ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapshowDislikeOnVideo"]) {

            AWEUserSheetAction *showDislikeOnVideo = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"长按面板"
                                                                                                       imgName:nil
                                                                                                       handler:^{
                                                                                                         [self showDislikeOnVideo];
                                                                                                       }];
            [actions addObject:showDislikeOnVideo];
        }

        // 显示操作表
        [actionSheet setActions:actions];
        [actionSheet show];

        return;
    }

    // 默认行为
    %orig;
}

%end

%hook AFDPrivacyHalfScreenViewController

%new
- (void)updateDarkModeAppearance {
    BOOL isDarkMode = [DYYYUtils isDarkMode];

    UIView *contentView = self.view.subviews.count > 1 ? self.view.subviews[1] : nil;
    if (contentView) {
        if (isDarkMode) {
            contentView.backgroundColor = [UIColor colorWithRed:0.13 green:0.13 blue:0.13 alpha:1.0];
        } else {
            contentView.backgroundColor = [UIColor whiteColor];
        }
    }

    // 修改标题文本颜色
    if (self.titleLabel) {
        if (isDarkMode) {
            self.titleLabel.textColor = [UIColor whiteColor];
        } else {
            self.titleLabel.textColor = [UIColor blackColor];
        }
    }

    // 修改内容文本颜色
    if (self.contentLabel) {
        if (isDarkMode) {
            self.contentLabel.textColor = [UIColor lightGrayColor];
        } else {
            self.contentLabel.textColor = [UIColor darkGrayColor];
        }
    }

    // 修改左侧按钮颜色和文字颜色
    if (self.leftCancelButton) {
        if (isDarkMode) {
            [self.leftCancelButton setBackgroundColor:[UIColor colorWithRed:0.25 green:0.25 blue:0.25 alpha:1.0]]; // 暗色模式按钮背景色
            [self.leftCancelButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];          // 暗色模式文字颜色
        } else {
            [self.leftCancelButton setBackgroundColor:[UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0]]; // 默认按钮背景色
            [self.leftCancelButton setTitleColor:[UIColor darkTextColor] forState:UIControlStateNormal];        // 默认文字颜色
        }
    }
}

- (void)viewDidLoad {
    %orig;
    [self updateDarkModeAppearance];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [self updateDarkModeAppearance];
}

- (void)configWithImageView:(UIImageView *)imageView
                  lockImage:(UIImage *)lockImage
           defaultLockState:(BOOL)defaultLockState
             titleLabelText:(NSString *)titleText
           contentLabelText:(NSString *)contentText
       leftCancelButtonText:(NSString *)leftButtonText
     rightConfirmButtonText:(NSString *)rightButtonText
       rightBtnClickedBlock:(void (^)(void))rightBtnBlock
     leftButtonClickedBlock:(void (^)(void))leftBtnBlock {

    %orig;
    [self updateDarkModeAppearance];
}

%end

%hook UITextField

- (void)willMoveToWindow:(UIWindow *)newWindow {
    %orig;

    if (newWindow) {
        BOOL isDarkMode = [DYYYUtils isDarkMode];
        self.keyboardAppearance = isDarkMode ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    }
}

- (BOOL)becomeFirstResponder {
    BOOL isDarkMode = [DYYYUtils isDarkMode];
    self.keyboardAppearance = isDarkMode ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    return %orig;
}

%end

%hook UITextView

- (void)willMoveToWindow:(UIWindow *)newWindow {
    %orig;

    if (newWindow) {
        BOOL isDarkMode = [DYYYUtils isDarkMode];
        self.keyboardAppearance = isDarkMode ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    }
}

- (BOOL)becomeFirstResponder {
    BOOL isDarkMode = [DYYYUtils isDarkMode];
    self.keyboardAppearance = isDarkMode ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    return %orig;
}

%end

// 底栏高度
%hook AWENormalModeTabBarPlusButton

- (void)setHidden:(BOOL)hidden {
    BOOL hidePlus = DYYYGetBool(@"DYYYHidePlusButton");
    %orig(hidePlus ? YES : hidden);

    if (hidePlus) {
        self.userInteractionEnabled = NO;
    }
}

- (void)didMoveToWindow {
    %orig;

    if (self.window && DYYYGetBool(@"DYYYHidePlusButton")) {
        self.userInteractionEnabled = NO;
        self.hidden = YES;
    }
}

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHidePlusButton")) {
        self.userInteractionEnabled = NO;
        self.hidden = YES;
    }
}

%end

%hook AWENormalModeTabBar

static Class barBackgroundClass = nil;
static Class generalButtonClass = nil;
static Class plusContainerButtonClass = nil;
static Class plusButtonClass = nil;
static Class plusInnerButtonClass = nil;
static Class tabBarButtonClass = nil;

+ (void)initialize {
    if (self == [%c(AWENormalModeTabBar) class]) {
        barBackgroundClass = NSClassFromString(@"_UIBarBackground");
        generalButtonClass = %c(AWENormalModeTabBarGeneralButton);
        plusContainerButtonClass = %c(AWENormalModeTabBarPlusButton);
        plusButtonClass = %c(AWENormalModeTabBarGeneralPlusButton);
        plusInnerButtonClass = %c(AWENormalModeTabBarGeneralPlusInnerButton);
        tabBarButtonClass = %c(UITabBarButton);
    }
}

%new
- (void)initializeOriginalTabBarHeight {
    if (originalTabBarHeight != kInvalidHeight) {
        if (gCurrentTabBarHeight == kInvalidHeight) {
            gCurrentTabBarHeight = originalTabBarHeight;
        }
        NSLog(@"[DYYY] initializeOriginalTabBarHeight: Skipped! originalTabBarHeight already initialized as %.1f.", originalTabBarHeight);
        return;
    }

    UIWindow *targetWindow = self.window ?: [DYYYUtils getActiveWindow];
    if (self.frame.size.height >= 30) {
        originalTabBarHeight = self.frame.size.height;
        NSLog(@"[DYYY] initializeOriginalTabBarHeight: Success! originalTabBarHeight set to %.1f (from self.frame.size.height)", originalTabBarHeight);
    } else if (targetWindow) {
        CGFloat bottomInset = targetWindow.safeAreaInsets.bottom;
        originalTabBarHeight = 49 + bottomInset;
        NSLog(@"[DYYY] initializeOriginalTabBarHeight: Success! originalTabBarHeight set to %.1f (fallback calculation: 49.0 + %.1f)", originalTabBarHeight, bottomInset);
    } else {
        NSLog(@"[DYYY] initializeOriginalTabBarHeight: Failed! No window available.");
    }
    if (originalTabBarHeight != kInvalidHeight) {
        gCurrentTabBarHeight = originalTabBarHeight;
        NSLog(@"[DYYY] initializeOriginalTabBarHeight: gCurrentTabBarHeight synced to %.1f.", gCurrentTabBarHeight);
    }
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        [self initializeOriginalTabBarHeight];
    }
}

- (void)layoutSubviews {
    %orig;

    if (originalTabBarHeight == kInvalidHeight) {
        NSLog(@"[DYYY] layoutSubviews: Fallback! originalTabBarHeight initialization triggered.");
        [self initializeOriginalTabBarHeight];
    }

    if (gCurrentTabBarHeight == kInvalidHeight) {
        gCurrentTabBarHeight = originalTabBarHeight;
        NSLog(@"[DYYY] layoutSubviews: gCurrentTabBarHeight fallback synced to %.1f.", gCurrentTabBarHeight);
    }

    BOOL hideShop = DYYYGetBool(@"DYYYHideShopButton");
    BOOL hideMsg = DYYYGetBool(@"DYYYHideMessageButton");
    BOOL hideFri = DYYYGetBool(@"DYYYHideFriendsButton");
    BOOL hideMe = DYYYGetBool(@"DYYYHideMyButton");
    BOOL hidePlus = DYYYGetBool(@"DYYYHidePlusButton");
    BOOL isPad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);

    NSMutableArray *visibleButtons = [NSMutableArray array];
    UIView *ipadContainerView = nil;

    for (UIView *subview in self.subviews) {
        if ([subview isKindOfClass:generalButtonClass] || [subview isKindOfClass:plusContainerButtonClass] || [subview isKindOfClass:plusButtonClass] ||
            [subview isKindOfClass:plusInnerButtonClass]) {
            NSString *label = subview.accessibilityLabel;
            BOOL isPlusButton = [subview isKindOfClass:plusContainerButtonClass] || [subview isKindOfClass:plusButtonClass] || [subview isKindOfClass:plusInnerButtonClass] ||
                                [label isEqualToString:@"拍摄"];
            BOOL shouldHide = (isPlusButton && hidePlus) || ([label containsString:@"商城"] && hideShop) || ([label containsString:@"消息"] && hideMsg) || ([label containsString:@"朋友"] && hideFri) ||
                              ([label isEqualToString:@"我"] && hideMe);

            subview.userInteractionEnabled = !shouldHide;
            subview.hidden = shouldHide;

            if (!shouldHide) {
                [visibleButtons addObject:subview];
            }
        } else if ([subview isKindOfClass:tabBarButtonClass]) {
            subview.userInteractionEnabled = NO;
            subview.hidden = YES;
        } else if (isPad && !ipadContainerView && [subview isMemberOfClass:UIView.class] && fabs(subview.frame.size.width - self.bounds.size.width) > 0.1) {
            ipadContainerView = subview;
        }
    }

    [visibleButtons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
      return [@(a.frame.origin.x) compare:@(b.frame.origin.x)];
    }];

    CGFloat offsetX, totalWidth;
    if (ipadContainerView) {
        offsetX = ipadContainerView.frame.origin.x;
        totalWidth = ipadContainerView.bounds.size.width;
    } else {
        offsetX = 0;
        totalWidth = self.bounds.size.width;
    }
    CGFloat buttonWidth = (visibleButtons.count > 0) ? (totalWidth / visibleButtons.count) : 0;

    // 均匀布局按钮
    for (NSInteger i = 0; i < visibleButtons.count; i++) {
        UIView *button = visibleButtons[i];
        button.frame = CGRectMake(offsetX + i * buttonWidth, button.frame.origin.y, buttonWidth, button.frame.size.height);
    }

    // 禁用首页刷新功能
    if (DYYYGetBool(@"DYYYDisableHomeRefresh")) {
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:generalButtonClass]) {
                AWENormalModeTabBarGeneralButton *button = (AWENormalModeTabBarGeneralButton *)subview;
                if ([button.accessibilityLabel isEqualToString:@"首页"]) {
                    // status == 2 表示选中状态
                    button.userInteractionEnabled = (button.status != 2);
                }
            }
        }
    }

    // 背景和分隔线处理
    BOOL hideBottomBg = DYYYGetBool(@"DYYYHideBottomBg");
    BOOL enableFullScreen = DYYYGetBool(@"DYYYEnableFullScreen");

    if (hideBottomBg || enableFullScreen) {
        if (self.skinContainerView) {
            self.skinContainerView.hidden = YES;
        }

        BOOL isHomeSelected = NO;
        BOOL isFriendsSelected = NO;

        if (enableFullScreen && !hideBottomBg) {
            for (UIView *subview in self.subviews) {
                if ([subview isKindOfClass:generalButtonClass]) {
                    AWENormalModeTabBarGeneralButton *button = (AWENormalModeTabBarGeneralButton *)subview;
                    if (button.status == 2) {
                        if ([button.accessibilityLabel isEqualToString:@"首页"])
                            isHomeSelected = YES;
                        else if ([button.accessibilityLabel containsString:@"朋友"])
                            isFriendsSelected = YES;
                    }
                }
            }
        }

        BOOL hideFriendsButton = DYYYGetBool(@"DYYYHideFriendsButton");
        BOOL shouldHideBackgrounds = hideBottomBg || (enableFullScreen && (isHomeSelected || (isFriendsSelected && !hideFriendsButton)));

        // 单次遍历处理所有背景和分割线
        for (UIView *subview in self.subviews) {
            // 跳过底栏按钮
            if ([subview isKindOfClass:generalButtonClass] || [subview isKindOfClass:plusContainerButtonClass] || [subview isKindOfClass:plusButtonClass] ||
                [subview isKindOfClass:plusInnerButtonClass]) {
                continue;
            }
            // 隐藏底栏背景
            if ([subview isKindOfClass:barBackgroundClass] || ([subview isMemberOfClass:[UIView class]] && originalTabBarHeight > 0 && fabs(subview.frame.size.height - gCurrentTabBarHeight) < 0.1)) {
                subview.hidden = shouldHideBackgrounds;
            }
            // 隐藏细分割线
            if (subview.frame.size.height > 0 && subview.frame.size.height < 1 && subview.frame.size.width > 300) {
                subview.hidden = enableFullScreen;
            }
        }
    } else {
        if (self.skinContainerView) {
            self.skinContainerView.hidden = NO;
        }

        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:barBackgroundClass] || [subview isMemberOfClass:[UIView class]]) {
                subview.hidden = NO;
            }
        }
    }
}

- (void)setHidden:(BOOL)hidden {
    %orig(hidden);

    BOOL disableHomeRefresh = DYYYGetBool(@"DYYYDisableHomeRefresh");
    BOOL enableFullScreen = DYYYGetBool(@"DYYYEnableFullScreen");
    BOOL hideBottomBg = DYYYGetBool(@"DYYYHideBottomBg");
    BOOL hideFriendsButton = DYYYGetBool(@"DYYYHideFriendsButton");

    BOOL isHomeSelected = NO;
    BOOL isFriendsSelected = NO;

    for (UIView *subview in self.subviews) {
        if ([subview isKindOfClass:generalButtonClass]) {
            AWENormalModeTabBarGeneralButton *button = (AWENormalModeTabBarGeneralButton *)subview;

            // 禁用首页刷新功能
            if (disableHomeRefresh && [button.accessibilityLabel isEqualToString:@"首页"]) {
                button.userInteractionEnabled = (button.status != 2);
            }

            // 检查当前选中的页
            if (enableFullScreen && button.status == 2) {
                if ([button.accessibilityLabel isEqualToString:@"首页"]) {
                    isHomeSelected = YES;
                } else if ([button.accessibilityLabel containsString:@"朋友"]) {
                    isFriendsSelected = YES;
                }
            }
        }
    }

    if (hideBottomBg || enableFullScreen) {
        if (self.skinContainerView) {
            self.skinContainerView.hidden = YES;
        }

        BOOL shouldHideBackgrounds = NO;
        if (hideBottomBg) {
            shouldHideBackgrounds = YES;
        } else if (enableFullScreen) {
            shouldHideBackgrounds = isHomeSelected || (isFriendsSelected && !hideFriendsButton);
        }

        // 处理所有背景和分割线
        for (UIView *subview in self.subviews) {
            CGFloat subviewHeight = subview.frame.size.height;
            // 跳过底栏按钮
            if ([subview isKindOfClass:generalButtonClass] || [subview isKindOfClass:plusContainerButtonClass] || [subview isKindOfClass:plusButtonClass] ||
                [subview isKindOfClass:plusInnerButtonClass]) {
                continue;
            }
            // 隐藏底栏背景
            if ([subview isKindOfClass:barBackgroundClass] || ([subview isMemberOfClass:[UIView class]] && originalTabBarHeight > 0 && fabs(subviewHeight - gCurrentTabBarHeight) < 0.1)) {
                subview.hidden = shouldHideBackgrounds;
            }
            // 隐藏细分割线
            if (subviewHeight > 0 && subviewHeight < 1 && subview.frame.size.width > 300) {
                subview.hidden = enableFullScreen;
            }
        }
    } else {
        if (self.skinContainerView) {
            self.skinContainerView.hidden = NO;
        }
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:barBackgroundClass] || [subview isMemberOfClass:[UIView class]]) {
                subview.hidden = NO;
            }
        }
    }
}

%end

// 精简平板底栏
%hook AWETabBarElementContainerView

- (void)setHidden:(BOOL)hidden {
    if (DYYYGetBool(@"DYYYHidePadTabBarElements")) {
        %orig(YES);
        return;
    }

    %orig(hidden);
}

%end

%hook AWENormalModeTabBarBadgeContainerView

- (void)layoutSubviews {
    %orig;
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideBottomDot"]) {
        return;
    }

    static char kDYBadgeCacheKey;
    NSArray *badges = objc_getAssociatedObject(self, &kDYBadgeCacheKey);
    if (!badges) {
        NSMutableArray *tmp = [NSMutableArray array];
        for (UIView *subview in [self subviews]) {
            if ([subview isKindOfClass:NSClassFromString(@"DUXBadge")]) {
                [tmp addObject:subview];
            }
        }
        badges = [tmp copy];
        objc_setAssociatedObject(self, &kDYBadgeCacheKey, badges, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UIView *badge in badges) {
        badge.hidden = YES;
    }
}

%end

// 禁用点击首页刷新
%hook AWENormalModeTabBarGeneralButton

- (BOOL)enableRefresh {
    if ([self.accessibilityLabel isEqualToString:@"首页"]) {
        if (DYYYGetBool(@"DYYYDisableHomeRefresh")) {
            return NO;
        }
    }
    return %orig;
}

%end

%hook AWENormalModeTabBarTextView

- (void)layoutSubviews {
    @try {
        %orig;

        if (![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{
              [self layoutSubviews];
            });
            return;
        }

        if (!self || !self.superview) {
            return;
        }

        NSString *indexTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYIndexTitle"];
        NSString *friendsTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFriendsTitle"];
        NSString *msgTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYMsgTitle"];
        NSString *selfTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYSelfTitle"];

        if (!(indexTitle.length || friendsTitle.length || msgTitle.length || selfTitle.length)) {
            return;
        }

        static char kDYTabTextLabelCacheKey;
        NSArray *labelCache = objc_getAssociatedObject(self, &kDYTabTextLabelCacheKey);
        if (!labelCache) {
            NSMutableArray *tmp = [NSMutableArray array];
            if (!tmp) {
                return;
            }

            NSArray *subviews = [self subviews];
            if (!subviews) {
                return;
            }

            for (UIView *subview in subviews) {
                if (subview && [subview isKindOfClass:[UILabel class]]) {
                    [tmp addObject:subview];
                }
            }

            labelCache = [tmp copy];
            if (labelCache) {
                objc_setAssociatedObject(self, &kDYTabTextLabelCacheKey, labelCache, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }

        if (!labelCache) {
            return;
        }

        for (UILabel *label in labelCache) {
            if (!label || ![label isKindOfClass:[UILabel class]]) {
                continue;
            }

            NSString *labelText = label.text;
            if (!labelText) {
                continue;
            }

            if ([labelText isEqualToString:@"首页"] && indexTitle.length > 0) {
                label.text = indexTitle;
                dispatch_async(dispatch_get_main_queue(), ^{
                  [self setNeedsLayout];
                });
            } else if ([labelText isEqualToString:@"朋友"] && friendsTitle.length > 0) {
                label.text = friendsTitle;
                dispatch_async(dispatch_get_main_queue(), ^{
                  [self setNeedsLayout];
                });
            } else if ([labelText isEqualToString:@"消息"] && msgTitle.length > 0) {
                label.text = msgTitle;
                dispatch_async(dispatch_get_main_queue(), ^{
                  [self setNeedsLayout];
                });
            } else if ([labelText isEqualToString:@"我"] && selfTitle.length > 0) {
                label.text = selfTitle;
                dispatch_async(dispatch_get_main_queue(), ^{
                  [self setNeedsLayout];
                });
            }
        }

    } @catch (NSException *exception) {
        return;
    }
}
%end

%hook AWENormalModeTabBarFeedView

- (void)layoutSubviews {
    @try {
        %orig;
        if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideDoubleColumnEntry"]) {
            return;
        }

        static char kDYDoubleColumnCacheKey;
        static char kDYDoubleColumnCountKey;
        NSArray *cachedViews = objc_getAssociatedObject(self, &kDYDoubleColumnCacheKey);
        NSNumber *cachedCount = objc_getAssociatedObject(self, &kDYDoubleColumnCountKey);
        if (!cachedViews || cachedCount.unsignedIntegerValue != self.subviews.count) {
            NSMutableArray *views = [NSMutableArray array];
            for (UIView *subview in self.subviews) {
                if (![subview isKindOfClass:[UILabel class]]) {
                    [views addObject:subview];
                }
            }
            cachedViews = [views copy];
            objc_setAssociatedObject(self, &kDYDoubleColumnCacheKey, cachedViews, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(self, &kDYDoubleColumnCountKey, @(self.subviews.count), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        for (UIView *v in cachedViews) {
            v.hidden = YES;
        }

        if (![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{
              [self layoutSubviews];
            });
            return;
        }

        if (!self || !self.superview) {
            return;
        }

        NSString *indexTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYIndexTitle"];

        if (!(indexTitle.length)) {
            return;
        }

        static char kDYTabFeedLabelCacheKey;
        NSArray *labelCache = objc_getAssociatedObject(self, &kDYTabFeedLabelCacheKey);
        if (!labelCache) {
            NSMutableArray *tmp = [NSMutableArray array];
            if (!tmp) {
                return;
            }

            NSArray *subviews = [self subviews];
            if (!subviews) {
                return;
            }

            for (UIView *subview in subviews) {
                if (subview && [subview isKindOfClass:[UILabel class]]) {
                    [tmp addObject:subview];
                }
            }

            labelCache = [tmp copy];
            if (labelCache) {
                objc_setAssociatedObject(self, &kDYTabFeedLabelCacheKey, labelCache, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }

        if (!labelCache) {
            return;
        }

        for (UILabel *label in labelCache) {
            if (!label || ![label isKindOfClass:[UILabel class]]) {
                continue;
            }

            NSString *labelText = label.text;
            if (!labelText) {
                continue;
            }

            if ([labelText isEqualToString:@"首页"] && indexTitle.length > 0) {
                label.text = indexTitle;
                dispatch_async(dispatch_get_main_queue(), ^{
                  [self setNeedsLayout];
                });
            }
        }

    } @catch (NSException *exception) {
        return;
    }
}
%end


%hook AWECommentInputBackgroundView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideComment")) {
        [self removeFromSuperview];
        return;
    }

    CGAffineTransform newTransform = CGAffineTransformMakeTranslation(0, originalTabBarHeight - gCurrentTabBarHeight);

    if (!CGAffineTransformEqualToTransform(self.transform, newTransform)) {
        self.transform = newTransform;
    }
}
%end

%hook AWECommentContainerViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    dyyyCommentViewVisible = YES;
    updateSpeedButtonVisibility();
    updateClearButtonVisibility();
    NSString *transparentValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYTopBarTransparent"];
    if (transparentValue && transparentValue.length > 0) {
        CGFloat alphaValue = [transparentValue floatValue];
        if (alphaValue >= 0.0 && alphaValue <= 1.0) {

            UIView *parentView = self.view.superview;
            if (parentView) {
                for (UIView *subview in parentView.subviews) {
                    if ([subview.accessibilityLabel isEqualToString:@"搜索"]) {
                        CGFloat finalAlpha = (alphaValue < 0.011) ? 0.011 : alphaValue;
                        subview.alpha = finalAlpha;
                    }
                }
            }
        }
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    dyyyCommentViewVisible = NO;
    updateSpeedButtonVisibility();
    updateClearButtonVisibility();
}

%end


%hook UIView

- (void)setHidden:(BOOL)hidden {
    BOOL shouldForceHidden = DYYYShouldForceAvatarActionViewHidden(self) || DYYYShouldForceAvatarSurroundingViewHidden(self);
    %orig(shouldForceHidden ? YES : hidden);
}

- (void)didAddSubview:(UIView *)subview {
    %orig(subview);

    if (!subview) {
        return;
    }

    BOOL hasSuppressedChrome = objc_getAssociatedObject(self, &kDYYYAvatarActionChromeViewKey) != nil;
    BOOL isAvatarFollowScope = objc_getAssociatedObject(self, &kDYYYAvatarFollowScopeViewKey) != nil;
    if ((!hasSuppressedChrome && !isAvatarFollowScope) || !DYYYAvatarFollowOptionsEnabled()) {
        return;
    }

    if (hasSuppressedChrome) {
        DYYYClearAvatarActionSubviewChrome(subview);
        DYYYHideAvatarAuxiliaryActionVisualsInView(subview);
    }

    if (isAvatarFollowScope) {
        DYYYApplyAvatarFollowSettingsInView(subview, self);
    }
}

- (void)didMoveToWindow {
    %orig;
    if (!hideButton || !hideButton.isElementsHidden) {
        DYYYRestoreClearTargetViewStateIfNeeded(self);
    }
}

- (id)initWithFrame:(CGRect)frame {
    UIView *view = %orig;
    if (hideButton && hideButton.isElementsHidden) {
        for (NSString *className in targetClassNames) {
            if ([view isKindOfClass:NSClassFromString(className)]) {
                if ([view isKindOfClass:NSClassFromString(@"AWELeftSideBarEntranceView")]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                      UIViewController *controller = [hideButton findViewController:view];
                      if ([controller isKindOfClass:NSClassFromString(@"AWEFeedContainerViewController")]) {
                          DYYYApplyClearTargetViewHiddenState(view);
                      }
                    });
                    break;
                }
                DYYYApplyClearTargetViewHiddenState(view);
                break;
            }
        }
    }
    return view;
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self setBackgroundColor:backgroundColor];
        });
        return;
    }

    if (DYYYShouldClearAvatarActionViewChrome(self)) {
        %orig([UIColor clearColor]);
        return;
    }


    %orig(backgroundColor);
}


- (void)setFrame:(CGRect)frame {
    CGRect adjusted = DYYYFullscreenAdjustFrame(self, frame);
    if (CGRectIsNull(adjusted)) { %orig; return; }
    %orig(adjusted);
}

%new
- (void)dyyy_refreshLivePreStreamLayout {
    if (![NSThread isMainThread]) {
        __weak UIView *weakView = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakView dyyy_refreshLivePreStreamLayout];
        });
        return;
    }

    [DYYYUtils applyLivePreStreamLayoutToStackView:self upwardOffset:0];
}

%new
- (void)dyyy_applyGlobalTransparency {
    if ([NSThread isMainThread]) {
        if (self.window && self.tag != DYYY_IGNORE_GLOBAL_ALPHA_TAG) {
            NSNumber *stored = objc_getAssociatedObject(self, &kDYYYGlobalTransparencyBaseAlphaKey);
            CGFloat baseAlpha = stored ? stored.floatValue : self.alpha;
            if (!stored) {
                objc_setAssociatedObject(self, &kDYYYGlobalTransparencyBaseAlphaKey, @(baseAlpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            CGFloat finalAlpha = baseAlpha;
            if (gGlobalTransparency != kInvalidAlpha) {
                CGFloat clampedAlpha = MIN(MAX(baseAlpha, 0.0), 1.0);
                finalAlpha = clampedAlpha * gGlobalTransparency;
            }
            if (fabs(self.alpha - finalAlpha) >= 0.01) {
                [UIView animateWithDuration:0.2
                                 animations:^{
                                   dyyyGlobalTransparencyMutationDepth++;
                                   self.alpha = finalAlpha;
                                   if (dyyyGlobalTransparencyMutationDepth > 0) {
                                       dyyyGlobalTransparencyMutationDepth--;
                                   }
                                 }];
            }
        }
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self dyyy_applyGlobalTransparency];
        });
    }
}

%end

%hook AWEIMSkylightListView
- (void)setFrame:(CGRect)frame {
    if (DYYYGetBool(@"DYYYHideAvatarList")) {
        CGFloat scale = [UIScreen mainScreen].scale ?: 2.0;
        CGFloat minH = MAX(1.0 / scale, 0.5);
        frame.size.height = minH;
    }
    %orig(frame);
}
%end

%hook AFDPureModePageTapController

- (void)onVideoPlayerViewDoubleClicked:(id)arg1 {
    BOOL isSwitchOn = DYYYGetBool(@"DYYYDisableDoubleTapLike");
    if (!isSwitchOn) {
        %orig;
    }
}

%end

%hook AWEPlayInteractionViewController

- (void)onVideoPlayerViewDoubleClicked:(id)arg1 {
    BOOL isSwitchOn = DYYYGetBool(@"DYYYDisableDoubleTapLike");
    if (!isSwitchOn) {
        %orig;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    isInPlayInteractionVC = YES;
    dyyyCurrentSpeedAweme = self.model;
    DYYYRestoreFloatSpeedButtonForAwemeIfNeeded(self.model);
    DYYYEnsureFloatSpeedButton(self);
    reloadClearButtonConfiguration();
}

- (void)viewDidLayoutSubviews {
    %orig;

    if (self.view.window && !self.view.hidden) {
        DYYYEnsureFloatSpeedButton(self);
        reloadClearButtonConfiguration();
    } else {
        [FloatingSpeedButton reloadConfiguration];
        updateClearButtonVisibility();
    }

}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (dyyyActiveSpeedInteractionController == self) {
        AWEPlayInteractionViewController *replacementController = DYYYResolveCurrentSpeedInteractionController(nil);
        if (replacementController && replacementController != self) {
            DYYYEnsureFloatSpeedButton(replacementController);
        } else {
            dyyyActiveSpeedInteractionController = nil;
            dyyyInteractionViewVisible = NO;
            dyyyCommentViewVisible = self.isCommentVCShowing;
            updateSpeedButtonVisibility();
            dispatch_async(dispatch_get_main_queue(), ^{
              DYYYEnsureFloatSpeedButton(nil);
            });
        }
        updateClearButtonVisibility();
    }
}

%new
- (void)speedButtonTapped:(UIButton *)sender {
    [(FloatingSpeedButton *)sender resetFadeTimer];
    NSArray *speeds = getSpeedOptions();
    if (speeds.count == 0)
        return;

    NSInteger currentIndex = getCurrentSpeedIndex();
    NSInteger newIndex = (currentIndex + 1) % speeds.count;

    setCurrentSpeedIndex(newIndex);

    float newSpeed = [speeds[newIndex] floatValue];
    updateSpeedButtonUI();
    DYYYClearLongPressSpeedState();

    [UIView animateWithDuration:0.1
        delay:0
        options:UIViewAnimationOptionCurveEaseOut
        animations:^{
          sender.transform = CGAffineTransformMakeScale(1.1, 1.1);
        }
        completion:^(BOOL finished) {
          [UIView animateWithDuration:0.1
                                delay:0
                              options:UIViewAnimationOptionCurveEaseIn
                           animations:^{
                             sender.transform = CGAffineTransformIdentity;
                           }
                           completion:nil];
        }];

    AWEPlayInteractionViewController *currentController = DYYYResolveCurrentSpeedInteractionController(self);
    if (currentController) {
        speedButton.interactionController = currentController;
    }
    if (!DYYYApplyPlaybackSpeed(currentController, newSpeed)) {
        [DYYYUtils showToast:@"无法找到视频控制器"];
    }
}

%new
- (void)buttonTouchDown:(UIButton *)sender {
    [UIView animateWithDuration:0.1
                     animations:^{
                       sender.alpha = 0.7;
                       sender.transform = CGAffineTransformMakeScale(0.95, 0.95);
                     }];
}

%new
- (void)buttonTouchUp:(UIButton *)sender {
    [UIView animateWithDuration:0.1
                     animations:^{
                       sender.alpha = 1.0;
                       sender.transform = CGAffineTransformIdentity;
                     }];
}

%end

%hook AWEAwemePlayVideoViewController

- (void)setIsAutoPlay:(BOOL)arg0 {
    %orig(arg0);
    DYYYApplyPreparedPlaybackSpeedToPlayer(self);
}

- (void)prepareForDisplay {
    %orig;
    if (!DYYYShouldHandleSpeedFeatures()) {
        return;
    }

    DYYYApplyPreparedPlaybackSpeedToPlayer(self);
    updateSpeedButtonUI();
}

%new
- (void)adjustPlaybackSpeed:(float)speed {
    [self setVideoControllerPlaybackRate:speed];
}

%end

%hook AWEDPlayerFeedPlayerViewController

- (BOOL)enableHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}


- (void)setIsAutoPlay:(BOOL)arg0 {
    %orig(arg0);
    DYYYApplyPreparedPlaybackSpeedToPlayer(self);
}

- (void)prepareForDisplay {
    %orig;
    if (!DYYYShouldHandleSpeedFeatures()) {
        return;
    }
    DYYYApplyPreparedPlaybackSpeedToPlayer(self);
    updateSpeedButtonUI();
}

%new
- (void)adjustPlaybackSpeed:(float)speed {
    [self setVideoControllerPlaybackRate:speed];
}

%end

%hook AWEDPlayerViewController_Merge

- (BOOL)enableHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}


- (void)setIsAutoPlay:(BOOL)arg0 {
    %orig(arg0);
    DYYYApplyPreparedPlaybackSpeedToPlayer(self);
}

- (void)prepareForDisplay {
    %orig;
    if (!DYYYShouldHandleSpeedFeatures()) {
        return;
    }
    DYYYApplyPreparedPlaybackSpeedToPlayer(self);
    updateSpeedButtonUI();
}

%new
- (void)adjustPlaybackSpeed:(float)speed {
    [self setVideoControllerPlaybackRate:speed];
}

%end

%hook AWEFeedTableViewCell
- (void)prepareForReuse {
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
    %orig;
}

- (void)layoutSubviews {
    %orig;
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
}
%end

%hook AWEFeedViewCell
- (void)layoutSubviews {
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
    %orig;
}

- (void)setModel:(id)model {
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
    %orig;
}
%end

%hook UIViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    isAppInTransition = YES;
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      isAppInTransition = NO;
    });
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    isAppInTransition = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      isAppInTransition = NO;
    });
}
%end

%hook AFDPureModePageContainerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    isPureViewVisible = YES;
    updateClearButtonVisibility();
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    isPureViewVisible = NO;
    updateClearButtonVisibility();
}
%end

%hook AWEFeedContainerViewController
- (void)aweme:(id)arg1 currentIndexWillChange:(NSInteger)arg2 {
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
    %orig;
}

- (void)aweme:(id)arg1 currentIndexDidChange:(NSInteger)arg2 {
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
    %orig;
    DYYYHandleCurrentSpeedAwemeChanged(arg1);
}

- (void)viewWillLayoutSubviews {
    %orig;
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
}
%end

static id dyyyWindowKeyObserverToken = nil;
static id dyyyDidBecomeActiveToken = nil;
static id dyyyWillResignActiveToken = nil;
static id dyyyKeyboardWillShowToken = nil;
static void *DYYYGlobalTransparencyContext = &DYYYGlobalTransparencyContext;

static void DYYYRemoveAppLifecycleObservers(void) {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (dyyyWindowKeyObserverToken) {
        [center removeObserver:dyyyWindowKeyObserverToken];
        dyyyWindowKeyObserverToken = nil;
    }
    if (dyyyDidBecomeActiveToken) {
        [center removeObserver:dyyyDidBecomeActiveToken];
        dyyyDidBecomeActiveToken = nil;
    }
    if (dyyyWillResignActiveToken) {
        [center removeObserver:dyyyWillResignActiveToken];
        dyyyWillResignActiveToken = nil;
    }
}

static void DYYYRemoveKeyboardObserver(void) {
    if (dyyyKeyboardWillShowToken) {
        [[NSNotificationCenter defaultCenter] removeObserver:dyyyKeyboardWillShowToken];
        dyyyKeyboardWillShowToken = nil;
    }
}

%hook AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig;
    initTargetClassNames();

    updateGlobalTransparencyCache();

    [[NSUserDefaults standardUserDefaults] addObserver:(NSObject *)self forKeyPath:kDYYYGlobalTransparencyKey options:NSKeyValueObservingOptionNew context:DYYYGlobalTransparencyContext];

    reloadClearButtonConfiguration();
    DYYYRemoveAppLifecycleObservers();

    dyyyWindowKeyObserverToken = [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeKeyNotification
                                                                                   object:nil
                                                                                    queue:[NSOperationQueue mainQueue]
                                                                               usingBlock:^(NSNotification *_Nonnull notification) {
                                                                                 reloadClearButtonConfiguration();
                                                                               }];

    dyyyDidBecomeActiveToken = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                                                 object:nil
                                                                                  queue:[NSOperationQueue mainQueue]
                                                                             usingBlock:^(NSNotification *_Nonnull notification) {
                                                                               isAppActive = YES;
                                                                               reloadClearButtonConfiguration();
                                                                             }];

    dyyyWillResignActiveToken = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
                                                                                  object:nil
                                                                                   queue:[NSOperationQueue mainQueue]
                                                                              usingBlock:^(NSNotification *_Nonnull notification) {
                                                                                isAppActive = NO;
                                                                                updateClearButtonVisibility();
                                                                              }];

    return result;
}

- (void)applicationWillTerminate:(UIApplication *)application {
    DYYYRemoveAppLifecycleObservers();
    DYYYRemoveKeyboardObserver();
    %orig;
}

- (void)dealloc {
    DYYYRemoveAppLifecycleObservers();
    DYYYRemoveKeyboardObserver();
    @try {
        [[NSUserDefaults standardUserDefaults] removeObserver:(NSObject *)self forKeyPath:kDYYYGlobalTransparencyKey context:DYYYGlobalTransparencyContext];
    } @catch (NSException *exception) {
        NSLog(@"[DYYY] KVO removeObserver failed: %@", exception);
    } 
    %orig;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    if (context == DYYYGlobalTransparencyContext) {
        dispatch_async(dispatch_get_main_queue(), ^{
          updateGlobalTransparencyCache();
          [[NSNotificationCenter defaultCenter] postNotificationName:kDYYYGlobalTransparencyDidChangeNotification object:nil];
        });
    } else {
        %orig(keyPath, object, change, context);
    }
}

%end

%hook AWELiveNewPreStreamViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [DYYYUtils refreshLivePreStreamLayoutForController:self];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [DYYYUtils refreshLivePreStreamLayoutForController:self];
}

%end

%group DYYYLivePreStreamPageAppearGroup
%hook AWELiveNewPreStreamViewController

- (void)pageDidAppear:(BOOL)animated {
    %orig;
    [DYYYUtils refreshLivePreStreamLayoutForController:self];
}

%end
%end

%hook AWEElementStackView

- (void)setTransform:(CGAffineTransform)transform {
    %orig(transform);
    // 切换底部页面时原生会重置 transform，排队恢复当前设置。
    [self dyyy_refreshLivePreStreamLayout];
}

- (void)setAlpha:(CGFloat)alpha {
    BOOL isApplyingGlobal = (dyyyGlobalTransparencyMutationDepth > 0);
    if (!isApplyingGlobal) {
        objc_setAssociatedObject(self, &kDYYYGlobalTransparencyBaseAlphaKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // 纯净模式功能
    static AWMSafeDispatchTimer *pureModeTimer = nil;
    static int attempts = 0;
    static BOOL pureModeSet = NO;
    if (DYYYGetBool(@"DYYYEnablePure")) {
        %orig(0.0);
        if (pureModeSet) {
            return;
        }
        if (!pureModeTimer) {
            pureModeTimer = [[AWMSafeDispatchTimer alloc] init];
        }
        if (!pureModeTimer.isRunning) {
            attempts = 0;
            __weak AWMSafeDispatchTimer *weakTimer = pureModeTimer;
            [pureModeTimer startWithInterval:0.5
                                      leeway:0.1
                                       queue:dispatch_get_main_queue()
                                     repeats:YES
                                     handler:^{
                                       AWMSafeDispatchTimer *strongTimer = weakTimer;
                                       UIWindow *keyWindow = [DYYYUtils getActiveWindow];
                                       if (keyWindow && keyWindow.rootViewController) {
                                           UIViewController *feedVC = [DYYYUtils findViewControllerOfClass:NSClassFromString(@"AWEFeedTableViewController")
                                                                                          inViewController:keyWindow.rootViewController];
                                           if (feedVC) {
                                               [feedVC setValue:@YES forKey:@"pureMode"];
                                               pureModeSet = YES;
                                               [strongTimer cancel];
                                               pureModeTimer = nil;
                                               attempts = 0;
                                               return;
                                           }
                                       }
                                       attempts++;
                                       if (attempts >= 10) {
                                           [strongTimer cancel];
                                           pureModeTimer = nil;
                                           attempts = 0;
                                       }
                                     }];
        }
        return;
    }

    // 清理纯净模式的残留状态
    if (pureModeTimer) {
        [pureModeTimer cancel];
        pureModeTimer = nil;
    }
    attempts = 0;
    pureModeSet = NO;

    // 倍速和清屏按钮的状态控制
    BOOL hasFloatingButtons = (speedButton && isFloatSpeedButtonEnabled) || hideButton;
    if (!isApplyingGlobal && hasFloatingButtons && !dyyyIsPerformingFloatClearOperation) {
        const CGFloat threshold = 0.01f;
        if (alpha <= threshold) {
            dyyyCommentViewVisible = YES;
        } else if (alpha >= (1.0f - threshold)) {
            dyyyCommentViewVisible = NO;
        }
        updateSpeedButtonVisibility();
        updateClearButtonVisibility();
    }

    // 值守全局透明度
    CGFloat finalAlpha = alpha;
    if (!isApplyingGlobal && self.tag != DYYY_IGNORE_GLOBAL_ALPHA_TAG && gGlobalTransparency != kInvalidAlpha) {
        CGFloat clampedAlpha = MIN(MAX(alpha, 0.0), 1.0);
        finalAlpha = clampedAlpha * gGlobalTransparency;
    }

    // 统一应用透明度
    if (fabs(self.alpha - finalAlpha) >= 0.01) {
        %orig(finalAlpha);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    dyyyCommentViewVisible = NO;
    updateSpeedButtonVisibility();
    updateClearButtonVisibility();
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    dyyyCommentViewVisible = YES;
    updateSpeedButtonVisibility();
    updateClearButtonVisibility();
}

- (void)didMoveToWindow {
    %orig;
    [self dyyy_refreshLivePreStreamLayout];
    if (self.window) {
        [self dyyy_applyGlobalTransparency];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dyyy_applyGlobalTransparency) name:kDYYYGlobalTransparencyDidChangeNotification object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kDYYYGlobalTransparencyDidChangeNotification object:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    %orig;
}

- (void)layoutSubviews {
    %orig;

    [self dyyy_refreshLivePreStreamLayout];
    if ([DYYYUtils findAncestorResponderOfClass:%c(AWELiveNewPreStreamViewController) fromView:self]) {
        return;
    }

    UIViewController *viewController = [DYYYUtils firstAvailableViewControllerFromView:self];

    if ([viewController isKindOfClass:%c(AWEPlayInteractionViewController)]) {
        NSString *label = self.accessibilityLabel ?: @"";
        BOOL hasAnchor = [DYYYUtils containsSubviewOfClass:NSClassFromString(@"AWEFeedAnchorContainerView") inContainer:self];
        BOOL hasAvatar = [DYYYUtils containsSubviewOfClass:NSClassFromString(@"AWEPlayInteractionUserAvatarView") inContainer:self];

        BOOL isRightStack = ([label isEqualToString:@"right"] || hasAvatar);
        if (!isRightStack) {
            NSArray *subviews = [self.subviews copy];
            for (NSInteger i = (NSInteger)subviews.count - 1; i >= 0; i--) {
                UIView *sub = subviews[i];
                if ([sub respondsToSelector:@selector(elementClassName)]) {
                    NSString *elementClassName = [sub performSelector:@selector(elementClassName)];
                    if ([elementClassName isEqualToString:@"AWEPlayInteractionUserAvatarOptElementElement"]) {
                        isRightStack = YES;
                        break;
                    }
                }
            }
        }

        BOOL isLeftStack = ([label isEqualToString:@"left"] || hasAnchor);
        if (!isLeftStack) {
            NSArray *subviews = [self.subviews copy];
            for (NSInteger i = (NSInteger)subviews.count - 1; i >= 0; i--) {
                UIView *sub = subviews[i];
                if ([sub respondsToSelector:@selector(elementClassName)]) {
                    NSString *elementClassName = [sub performSelector:@selector(elementClassName)];
                    if ([elementClassName isEqualToString:@"AWEPlayInteractionDescriptionElement"]) {
                        isLeftStack = YES;
                        break;
                    }
                }
            }
        }

        // 右侧元素的处理逻辑
        if (isRightStack) {
            NSString *scaleValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYElementScale"];
            self.transform = CGAffineTransformIdentity;
            if (scaleValue.length > 0) {
                CGFloat scale = [scaleValue floatValue];
                if (scale > 0 && scale != 1.0) {
                    NSArray *subviews = [self.subviews copy];
                    CGFloat ty = 0;
                    for (UIView *view in subviews) {
                        CGFloat viewHeight = view.frame.size.height;
                        ty += (viewHeight - viewHeight * scale) / 2;
                    }
                    CGFloat frameWidth = self.frame.size.width;
                    CGFloat right_tx = (frameWidth - frameWidth * scale) / 2;
                    self.transform = CGAffineTransformMake(scale, 0, 0, scale, right_tx, ty);
                } else {
                    self.transform = CGAffineTransformIdentity;
                }
            }
        }
        // 左侧元素的处理逻辑
        else if (isLeftStack) {
            NSString *scaleValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNicknameScale"];
            if (scaleValue.length > 0) {
                CGFloat scale = [scaleValue floatValue];
                self.transform = CGAffineTransformIdentity;
                if (scale > 0 && scale != 1.0) {
                    NSArray *subviews = [self.subviews copy];
                    CGFloat ty = 0;
                    for (UIView *view in subviews) {
                        CGFloat viewHeight = view.frame.size.height;
                        ty += (viewHeight - viewHeight * scale) / 2;
                    }
                    CGFloat frameWidth = self.frame.size.width;
                    CGFloat left_tx = (frameWidth - frameWidth * scale) / 2 - frameWidth * (1 - scale);
                    CGAffineTransform newTransform = CGAffineTransformMakeScale(scale, scale);
                    newTransform = CGAffineTransformTranslate(newTransform, left_tx / scale, ty / scale);
                    self.transform = newTransform;
                }
            }
        }
    }
}

- (NSArray<__kindof UIView *> *)arrangedSubviews {

    UIViewController *viewController = [DYYYUtils firstAvailableViewControllerFromView:self];
    if ([viewController isKindOfClass:%c(AWEPlayInteractionViewController)] &&
        ![DYYYUtils findAncestorResponderOfClass:%c(AWELiveNewPreStreamViewController) fromView:self]) {

        if ([self.accessibilityLabel isEqualToString:@"left"] || [DYYYUtils containsSubviewOfClass:NSClassFromString(@"AWEFeedAnchorContainerView") inContainer:self]) {
            NSString *scaleValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNicknameScale"];
            if (scaleValue.length > 0) {
                CGFloat scale = [scaleValue floatValue];
                self.transform = CGAffineTransformIdentity;
                if (scale > 0 && scale != 1.0) {
                    NSArray *subviews = [self.subviews copy];
                    CGFloat ty = 0;
                    for (UIView *view in subviews) {
                        CGFloat viewHeight = view.frame.size.height;
                        ty += (viewHeight - viewHeight * scale) / 2;
                    }
                    CGFloat frameWidth = self.frame.size.width;
                    CGFloat left_tx = (frameWidth - frameWidth * scale) / 2 - frameWidth * (1 - scale);
                    CGAffineTransform newTransform = CGAffineTransformMakeScale(scale, scale);
                    newTransform = CGAffineTransformTranslate(newTransform, left_tx / scale, ty / scale);
                    self.transform = newTransform;
                }
            }
        }
    }

    NSArray *originalSubviews = %orig;
    return originalSubviews;
}

%end

%hook IESLiveStackView

- (void)setTransform:(CGAffineTransform)transform {
    %orig(transform);
    [self dyyy_refreshLivePreStreamLayout];
}

- (void)setAlpha:(CGFloat)alpha {
    BOOL isApplyingGlobal = (dyyyGlobalTransparencyMutationDepth > 0);
    if (!isApplyingGlobal) {
        objc_setAssociatedObject(self, &kDYYYGlobalTransparencyBaseAlphaKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (!isApplyingGlobal && speedButton && isFloatSpeedButtonEnabled) {
        if (alpha == 0) {
            dyyyCommentViewVisible = YES;
        } else if (alpha == 1) {
            dyyyCommentViewVisible = NO;
        }
        updateSpeedButtonVisibility();
        updateClearButtonVisibility();
    }

    CGFloat finalAlpha = alpha;
    if (!isApplyingGlobal && self.tag != DYYY_IGNORE_GLOBAL_ALPHA_TAG && gGlobalTransparency != kInvalidAlpha) {
        CGFloat clampedAlpha = MIN(MAX(alpha, 0.0), 1.0);
        finalAlpha = clampedAlpha * gGlobalTransparency;
    }

    if (fabs(self.alpha - finalAlpha) >= 0.01) {
        %orig(finalAlpha);
    }
}

- (void)didMoveToWindow {
    %orig;
    [self dyyy_refreshLivePreStreamLayout];
    if (self.window) {
        [self dyyy_applyGlobalTransparency];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dyyy_applyGlobalTransparency) name:kDYYYGlobalTransparencyDidChangeNotification object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kDYYYGlobalTransparencyDidChangeNotification object:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    %orig;
}

- (void)layoutSubviews {
    %orig;

    [self dyyy_refreshLivePreStreamLayout];
}

%end


%hook TTPlayerView

- (void)layoutSubviews {
    %orig;
    UIView *parent = self.superview;
    if (parent) {
        parent.backgroundColor = self.backgroundColor;
    }
}

%end


// 隐藏图片滑条
%hook AWEStoryProgressContainerView


- (BOOL)isHidden {
    BOOL originalValue = %orig;
    BOOL customHide = DYYYGetBool(@"DYYYHideDotsIndicator");
    return originalValue || customHide;
}

- (void)setHidden:(BOOL)hidden {
    BOOL forceHide = DYYYGetBool(@"DYYYHideDotsIndicator");
    %orig(forceHide ? YES : hidden);
}
%end

%hook AWELandscapeFeedEntryView

- (void)setAlpha:(CGFloat)alpha {
    BOOL isApplyingGlobal = (dyyyGlobalTransparencyMutationDepth > 0);
    if (!isApplyingGlobal) {
        objc_setAssociatedObject(self, &kDYYYGlobalTransparencyBaseAlphaKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CGFloat finalAlpha = alpha;
    if (!isApplyingGlobal && self.tag != DYYY_IGNORE_GLOBAL_ALPHA_TAG && gGlobalTransparency != kInvalidAlpha) {
        CGFloat clampedAlpha = MIN(MAX(alpha, 0.0), 1.0);
        finalAlpha = clampedAlpha * gGlobalTransparency;
    }

    if (fabs(self.alpha - finalAlpha) >= 0.01) {
        %orig(finalAlpha);
    }
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        [self dyyy_applyGlobalTransparency];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dyyy_applyGlobalTransparency) name:kDYYYGlobalTransparencyDidChangeNotification object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kDYYYGlobalTransparencyDidChangeNotification object:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    %orig;
}

- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYRemoveEntry")) {
        [self removeFromSuperview];
        return;
    }
    if (DYYYGetBool(@"DYYYHideEntry")) {
        for (UIView *subview in self.subviews) {
            subview.hidden = YES;
        }
        return;
    }

    if (self.superview) {
        [self.superview bringSubviewToFront:self];
    }

    NSString *scaleValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNicknameScale"];
    CGFloat scale = scaleValue.length > 0 ? [scaleValue floatValue] : 1.0;
    if (scale > 0 && scale != 1.0) {
        self.transform = CGAffineTransformMakeScale(scale, scale);
    } else {
        self.transform = CGAffineTransformIdentity;
    }
}

%end


%hook CommentInputContainerView

- (void)layoutSubviews {
    %orig;
    UIViewController *parentVC = nil;
    if ([self respondsToSelector:@selector(viewController)]) {
        id viewController = [self performSelector:@selector(viewController)];
        if ([viewController respondsToSelector:@selector(parentViewController)]) {
            parentVC = [viewController parentViewController];
        }
    }

    if (parentVC && ([parentVC isKindOfClass:%c(AWEAwemeDetailTableViewController)] || [parentVC isKindOfClass:%c(AWEAwemeDetailCellViewController)])) {
        static char kDYCommentHideCacheKey;
        UIView *target = objc_getAssociatedObject(self, &kDYCommentHideCacheKey);
        if (!target) {
            for (UIView *subview in [self subviews]) {
                if ([subview class] == [UIView class]) {
                    target = subview;
                    objc_setAssociatedObject(self, &kDYCommentHideCacheKey, target, OBJC_ASSOCIATION_ASSIGN);
                    break;
                }
            }
        }
        if (target) {
            target.hidden = ([(UIView *)self frame].size.height == gCurrentTabBarHeight);
        }
    }
}

%end

// 聊天视频底部评论框背景透明


// 隐藏上次看到
%hook DUXPopover
- (void)layoutSubviews {
    %orig;

    if (!DYYYGetBool(@"DYYYHidePopover")) {
        return;
    }

    id rawContent = nil;
    @try {
        rawContent = [self valueForKey:@"content"];
    } @catch (__unused NSException *e) {
        return;
    }

    NSString *text = [rawContent isKindOfClass:NSString.class] ? (NSString *)rawContent : [rawContent description];

    if ([text containsString:@"上次看到"]) {
        self.hidden = YES;
        return;
    }
}
%end

%hook _TtC21AWEIncentiveSwiftImpl29IncentivePendantContainerView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHidePendantGroup")) {
        [self removeFromSuperview];
    }
}
%end

%hook UIImageView
- (void)setImage:(UIImage *)image {
    DYYYApplySDRDynamicRangeToImageView(self);
    %orig;
    DYYYApplySDRDynamicRangeToImageView(self);
}

- (void)setHighlightedImage:(UIImage *)highlightedImage {
    DYYYApplySDRDynamicRangeToImageView(self);
    %orig;
    DYYYApplySDRDynamicRangeToImageView(self);
}

- (void)setAnimationImages:(NSArray<UIImage *> *)animationImages {
    DYYYApplySDRDynamicRangeToImageView(self);
    %orig;
    DYYYApplySDRDynamicRangeToImageView(self);
}

- (void)setHighlightedAnimationImages:(NSArray<UIImage *> *)highlightedAnimationImages {
    DYYYApplySDRDynamicRangeToImageView(self);
    %orig;
    DYYYApplySDRDynamicRangeToImageView(self);
}

- (void)layoutSubviews {
    %orig;
    DYYYApplySDRDynamicRangeToImageView(self);
    if (DYYYGetBool(@"DYYYHideCommentDiscover")) {
        if (!self.accessibilityLabel) {
            UIView *parentView = self.superview;

            if (parentView && [parentView class] == [UIView class] && [parentView.accessibilityLabel isEqualToString:@"搜索"]) {
                self.hidden = YES;
            }

            else if (parentView && [NSStringFromClass([parentView class]) isEqualToString:@"AWESearchEntryHalfScreenElement"] && [parentView.accessibilityLabel isEqualToString:@"搜索"]) {
                self.hidden = YES;
            }
        }
    }
    return;
}
%end

// 移除极速版我的片面红包横幅
%hook AWELuckyCatBannerView
- (id)initWithFrame:(CGRect)frame {
    return nil;
}

- (id)init {
    return nil;
}
%end

static NSString *const kHideRecentAppsKey = @"DYYYHideSidebarRecentApps";
static NSString *const kHideRecentUsersKey = @"DYYYHideSidebarRecentUsers";

%hook AWELeftSideBarModel

- (NSArray *)moduleModels {
    NSArray *originalModels = %orig;

    BOOL shouldHideRecentApps = DYYYGetBool(kHideRecentAppsKey);
    BOOL shouldHideRecentUsers = DYYYGetBool(kHideRecentUsersKey);

    if (!shouldHideRecentApps && !shouldHideRecentUsers) {
        return originalModels;
    }

    NSMutableArray *filteredModels = [NSMutableArray arrayWithCapacity:originalModels.count];

    for (id moduleModel in originalModels) {
        if ([moduleModel respondsToSelector:@selector(moduleID)]) {
            NSString *moduleID = [moduleModel moduleID];

            if (shouldHideRecentApps && [moduleID isEqualToString:@"recently_apps_module"]) {
                continue;
            }

            if (shouldHideRecentUsers && [moduleID isEqualToString:@"recently_users_module"]) {
                continue;
            }
        }

        id filteredModule = [self filterModuleItems:moduleModel];
        if (filteredModule) {
            [filteredModels addObject:filteredModule];
        }
    }

    return [filteredModels copy];
}

%new
- (id)filterModuleItems:(id)moduleModel {
    if (![moduleModel respondsToSelector:@selector(items)] || ![moduleModel respondsToSelector:@selector(moduleID)]) {
        return moduleModel;
    }

    NSString *moduleID = [moduleModel moduleID];
    NSArray *originalItems = [moduleModel items];

    if ([moduleID isEqualToString:@"top_area"]) {
        // 只保留天气、设置、扫一扫
        NSMutableArray *filteredItems = [NSMutableArray array];

        for (id item in originalItems) {
            if ([item respondsToSelector:@selector(businessType)]) {
                NSString *businessType = [item businessType];

                // 保留需要的组件
                if ([businessType isEqualToString:@"weather_time_tip_component"] || [businessType isEqualToString:@"setting_page_component"] ||
                    [businessType isEqualToString:@"top_area_vertical_cell"]) {
                    [filteredItems addObject:item];
                }
            }
        }

        // 创建新的模块对象，保持原有属性但更新items
        if ([moduleModel respondsToSelector:@selector(copy)]) {
            id newModule = [moduleModel copy];
            if ([newModule respondsToSelector:@selector(setItems:)]) {
                [newModule setItems:[filteredItems copy]];
            }
            return newModule;
        }
    }

    return moduleModel;
}

%end

@interface UIDropShadowView : UIView
@end

// 修复 ios26 模态透明效果
// %hook UIDropShadowView

// - (void)didMoveToSuperview {
//     %orig;

//     if (@available(iOS 26.0, *)) {
//         self.backgroundColor = UIColor.clearColor;
//         self.opaque = NO;
//     }
// }

// - (void)layoutSubviews {
//     %orig;

//     if (@available(iOS 26.0, *)) {
//         self.backgroundColor = UIColor.clearColor;
//         self.opaque = NO;
//     }
// }

// - (void)setBackgroundColor:(UIColor *)color {
//     if (@available(iOS 26.0, *)) {
//         %orig(UIColor.clearColor);
//         return;
//     }
//     %orig;
// }

// %end


// 极速版红包激励挂件容器视图类组（移除逻辑）
%group IncentivePendantGroup
%hook AWEIncentiveSwiftImplDOUYINLite_IncentivePendantContainerView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHidePendantGroup")) {
        [self removeFromSuperview];
    }
}
%end
%end

%hook AWEDPlayerProgressContainerView

- (void)layoutSubviews {
    %orig;
    DYYYApplyFloatClearProgressStateToView(self);
}

%end


// 隐藏键盘 AI
static __weak UIView *cachedHideView = nil;
static void hideParentViewsSubviews(UIView *view) {
    if (!view)
        return;
    UIView *parentView = [view superview];
    if (!parentView)
        return;
    UIView *grandParentView = [parentView superview];
    if (!grandParentView)
        return;
    UIView *greatGrandParentView = [grandParentView superview];
    if (!greatGrandParentView)
        return;
    cachedHideView = greatGrandParentView;
    for (UIView *subview in greatGrandParentView.subviews) {
        subview.hidden = YES;
    }
}

// 递归查找目标视图
static void findTargetViewInView(UIView *view) {
    if (cachedHideView)
        return;
    if ([view isKindOfClass:NSClassFromString(@"AWESearchKeyboardVoiceSearchEntranceView")]) {
        hideParentViewsSubviews(view);
        return;
    }
    for (UIView *subview in view.subviews) {
        findTargetViewInView(subview);
        if (cachedHideView)
            break;
    }
}

// 液体玻璃实现移植自 DYKiller，MIT 许可见仓库 LICENSE。

#pragma mark - 底栏液体玻璃（通透）

// 移植自 DYKiller，MIT 许可见 LICENSE。

// 依赖的抖音/UIKit 私有符号集中在此，抖音改名时只改这里。
static NSString *const kDYYYTabGlassBadgeContainerClass = @"AWENormalModeTabBarBadgeContainerView";
static NSString *const kDYYYTabGlassBadgeClass = @"DUXBadge";
static NSString *const kDYYYTabGlassPlatterClass = @"_UITabBarItemPlatterView";
static NSString *const kDYYYTabGlassTabButtonClass = @"_UITabButton";
static NSString *const kDYYYTabGlassPlusClickSelector = @"plusTabBarButtonDidClick:";
static NSString *const kDYYYTabGlassTabClickSelector = @"tabBarButtonDidTouchUpInside:gestureRecognizer:";

// 抖音按钮的 type：拍摄入口。它不是页面，不参与 selectedIndex，单独做成右侧圆键。
static const long long kDYYYTabGlassPlusButtonType = 2;
// 标题字号。抖音原生底栏是 10pt——那是留给「图标在上、10pt 标签在下」的层叠布局的，
// 标题独占整个按钮后 10pt 会显得空落，故按纯文字胶囊的比例取值。
static const CGFloat kDYYYTabGlassTitleFontSize = 15.0;
// 胶囊与拍摄键之间的间距。
static const CGFloat kDYYYTabGlassPlusKeyGap = 12.0;
// 拍摄图标在圆键内的四周留白。
static const CGFloat kDYYYTabGlassPlusIconInset = 14.0;

static const CGFloat kDYYYTabGlassTitleMaxWidth = 64.0;
static const CGFloat kDYYYTabGlassTitleMinFontSize = 11.0;
// platter 还没建起来时的兜底几何（beta7 实测值），量到真实值后即被取代。
static const CGFloat kDYYYTabGlassPlatterFallbackHeight = 62.0;
static const CGFloat kDYYYTabGlassPlatterFallbackInset = 21.0;
// 胶囊里每颗 _UITabButton 的宽与首颗距胶囊左缘的距离（0.6.1-beta1 实测值），用法同上。
static const CGFloat kDYYYTabGlassTabButtonFallbackWidth = 94.0;
static const CGFloat kDYYYTabGlassTabButtonFallbackPad = 4.0;

#pragma mark - 状态

static UITabBar *gDYYYTabGlassBar = nil;
static id gDYYYTabGlassProxy = nil;
// 每个 item 对应的 tab 序号（validIndex）。与 items 同序等长。
static NSArray<NSNumber *> *gDYYYTabGlassItemKinds = nil;
// 每个 item 对应的抖音按钮，转发点击与读取角标都用它。与 items 同序等长。
static NSArray *gDYYYTabGlassItemButtons = nil;
// 每个 item 的抖音 tabID（取不到为 NSNull），按样式出图用。与 items 同序等长。
static NSArray *gDYYYTabGlassItemTabIDs = nil;
// 上次构建 items 用的签名，变了才重建，避免每次布局都换 items。
static NSString *gDYYYTabGlassSignature = nil;
// 最近一次见到的抖音底栏，供开关变化时立即生效。
static __weak AWENormalModeTabBar *gDYYYTabGlassDouyinBar = nil;
// 已挂上深浅色监听的场景，避免重复注册。
static __weak UIWindowScene *gDYYYTabGlassObservedScene = nil;

// 拍摄圆键及其内容。
static UIVisualEffectView *gDYYYTabGlassPlusKey = nil;
static UIImageView *gDYYYTabGlassPlusIcon = nil;
// 新双色图标的青红层，垫在 gPlusIcon 下面；其他样式隐藏。
static UIImageView *gDYYYTabGlassPlusAccent = nil;
// 上次出图时的拍摄样式，样式变了要重新取图与着色。
static UIButton *gDYYYTabGlassPlusHit = nil;
// 抖音的拍摄按钮；被其他插件移除时为 nil，圆键随之隐藏。
static __weak UIView *gDYYYTabGlassPlusButton = nil;
// 上次裁过的图标源图，按指针比对，变了才重裁。
static UIImage *gDYYYTabGlassPlusSourceIcon = nil;

// 每次布局由 DYYYLGGlassLayoutGlass 刷新。弱引用：UIKit 换掉 platter 时这里自动变 nil。

#pragma mark - 小工具

static id DYYYTabGlassGlassValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *DYYYTabGlassGlassButtonTitle(id button) {
    id inner = DYYYTabGlassGlassValue(button, @"innerView");
    NSString *text = DYYYTabGlassGlassValue(DYYYTabGlassGlassValue(inner, @"label"), @"text");
    if (text.length > 0) return text;

    NSString *current = DYYYTabGlassGlassValue(inner, @"currentTitleText");
    if (current.length > 0) return current;

    NSString *label = [button isKindOfClass:UIView.class] ? [(UIView *)button accessibilityLabel] : nil;
    return label.length > 0 ? label : nil;
}

static UITabBarController *DYYYTabGlassGlassControllerForView(UIView *view) {
    for (UIResponder *responder = view.nextResponder; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:UITabBarController.class]) return (UITabBarController *)responder;
    }
    return nil;
}

#pragma mark - 开关

static BOOL DYYYTabGlassGlassTabBarEnabled(void) {
    return [DYYYUtils liquidGlassAvailable] && [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableTabBarLiquidGlass"];
}

static BOOL DYYYTabGlassGlassTabBarUsesClear(void) { return YES; }

#pragma mark - 材质

static UIGlassEffect *DYYYTabGlassGlassMakeGlassEffect(UIUserInterfaceStyle style, BOOL interactive)
    API_AVAILABLE(ios(26.0)) {
    BOOL clear = DYYYTabGlassGlassTabBarUsesClear();
    UIGlassEffect *effect = [UIGlassEffect effectWithStyle:
        clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
    if (clear) effect.tintColor = [DYYYUtils liquidGlassTintForStyle:style];
    effect.interactive = interactive;
    return effect;
}

static NSString *const kDYYYTabGlassPlatterGlassKey = @"glassEffect";
static char kDYYYTabGlassPlatterOriginalGlassKey;
static BOOL gDYYYTabGlassPlatterGlassProbed = NO;
static BOOL gDYYYTabGlassPlatterGlassSupported = NO;
// glassEffect 是 copy 属性（实测回读指针 != 写入指针），所以记的是 platter 存下的那只【副本】。
// 弱引用：platter 换掉它、或 platter 本身销毁，这里都会变，正好当作「需要重装」的信号。
static __weak id gDYYYTabGlassPlatterGlassInstalled = nil;
static UIUserInterfaceStyle gDYYYTabGlassPlatterGlassStyle = UIUserInterfaceStyleUnspecified;

static void DYYYTabGlassGlassApplyPlatterGlass(UIView *platter, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    if (!platter || (gDYYYTabGlassPlatterGlassProbed && !gDYYYTabGlassPlatterGlassSupported)) return;

    id current = nil;
    @try {
        current = [platter valueForKey:kDYYYTabGlassPlatterGlassKey];
    } @catch (__unused NSException *exception) {
        gDYYYTabGlassPlatterGlassProbed = YES;      // 属性不在，永久放弃
        gDYYYTabGlassPlatterGlassSupported = NO;
        return;
    }
    gDYYYTabGlassPlatterGlassProbed = YES;
    gDYYYTabGlassPlatterGlassSupported = YES;

    BOOL patched = current && current == gDYYYTabGlassPlatterGlassInstalled;

    if (!DYYYTabGlassGlassTabBarUsesClear()) {
        if (!patched) return;                       // 没接管过，无需还原
        id original = objc_getAssociatedObject(platter, &kDYYYTabGlassPlatterOriginalGlassKey);
        @try {
            [platter setValue:(original == NSNull.null ? nil : original)
                       forKey:kDYYYTabGlassPlatterGlassKey];
        } @catch (__unused NSException *exception) {}
        gDYYYTabGlassPlatterGlassInstalled = nil;
        gDYYYTabGlassPlatterGlassStyle = UIUserInterfaceStyleUnspecified;
        [platter setNeedsLayout];
        return;
    }

    // 装的还是我们那只、档位也没变，就什么都不做。逐帧无脑重写会打断系统的呈现过渡。
    if (patched && style == gDYYYTabGlassPlatterGlassStyle) return;

    if (!objc_getAssociatedObject(platter, &kDYYYTabGlassPlatterOriginalGlassKey)) {
        objc_setAssociatedObject(platter, &kDYYYTabGlassPlatterOriginalGlassKey, current ?: NSNull.null,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // interactive 照抄现有那只。UIKit 给 platter 的原厂配置就是 interactive=YES，整块胶囊的
    // 按压/触摸/高亮动效全从它来；写死 NO 会把这些动效一并抹掉（beta23 踩过）。
    BOOL interactive = [current isKindOfClass:UIGlassEffect.class]
        ? ((UIGlassEffect *)current).interactive : YES;
    @try {
        [platter setValue:DYYYTabGlassGlassMakeGlassEffect(style, interactive) forKey:kDYYYTabGlassPlatterGlassKey];
        gDYYYTabGlassPlatterGlassInstalled = [platter valueForKey:kDYYYTabGlassPlatterGlassKey];
    } @catch (__unused NSException *exception) {
        gDYYYTabGlassPlatterGlassSupported = NO;
        return;
    }
    gDYYYTabGlassPlatterGlassStyle = style;
    [platter setNeedsLayout];
}

#pragma mark - 深浅色

static UIUserInterfaceStyle gDYYYTabGlassGlassStyle = UIUserInterfaceStyleUnspecified;

static void DYYYTabGlassGlassApplyStyle(UIUserInterfaceStyle style) API_AVAILABLE(ios(26.0)) {
    if (style == UIUserInterfaceStyleUnspecified || style == gDYYYTabGlassGlassStyle) return;
    gDYYYTabGlassGlassStyle = style;

    if (gDYYYTabGlassBar) gDYYYTabGlassBar.overrideUserInterfaceStyle = style;
    if (gDYYYTabGlassPlusKey) {
        gDYYYTabGlassPlusKey.overrideUserInterfaceStyle = style;
        gDYYYTabGlassPlusKey.effect = DYYYTabGlassGlassMakeGlassEffect(style, YES);
    }
    // platter 的玻璃在下一次布局里跟着重写；trait 变化未必伴随布局，主动踢一次。
    [gDYYYTabGlassDouyinBar setNeedsLayout];
}

// 挂在场景上监听，系统一切深浅色即刻改；否则只能等抖音下次布局，就是 beta3 那种「切一下页才变」。
static void DYYYTabGlassGlassObserveStyle(UIView *host) API_AVAILABLE(ios(26.0)) {
    UIWindowScene *scene = host.window.windowScene;
    if (!scene || scene == gDYYYTabGlassObservedScene) return;
    gDYYYTabGlassObservedScene = scene;
    [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                       withHandler:^(UIWindowScene *changed, __unused UITraitCollection *previous) {
        if (gDYYYTabGlassBar) DYYYTabGlassGlassApplyStyle(changed.traitCollection.userInterfaceStyle);
    }];
}

#pragma mark - 内容取色

static UIImage *DYYYTabGlassGlassTitleImage(NSString *title, UIColor *color);

static UIUserInterfaceStyle gDYYYTabGlassInkStyle = UIUserInterfaceStyleUnspecified;
// 上一次分类过的宿主文字色，按指针比对做缓存——这是逐帧路径，指针没变就不必再解析一次。
static UIColor *gDYYYTabGlassInkHostColor = nil;
static BOOL gDYYYTabGlassInkHostIsLight = NO;

static UIUserInterfaceStyle gDYYYTabGlassPlusIconInkStyle = UIUserInterfaceStyleUnspecified;

// 未选中的浓度。实测：50% 在亮底只有 3.94:1 不达 AA、55% 是 4.68:1 卡线，
// 60% 两侧分别 6.69 / 5.59。不用系统 secondaryLabel——它浅色档是 #3C3C43 而非纯黑，
// 压在白页上只有 3.4:1。保留 alpha、底色取纯黑白，与 DYYYLGGlassInkTextColor 同一口径。
static const CGFloat kDYYYTabGlassInkSecondaryAlpha = 0.60;

static UIColor *DYYYTabGlassGlassInkColor(BOOL selected) {
    CGFloat white = (gDYYYTabGlassInkStyle == UIUserInterfaceStyleDark) ? 1.0 : 0.0;
    return [UIColor colorWithWhite:white alpha:(selected ? 1.0 : kDYYYTabGlassInkSecondaryAlpha)];
}

static UIImage *DYYYTabGlassGlassItemImage(NSString *tabID, NSString *title, BOOL selected, UIColor *color);

// 按当前极性与底栏样式重渲染每个 item 的两张图。就地改 image / selectedImage，不重建 items——
// 极性变化和切页是同一时刻，重建 items 会打断系统正在跑的透镜位移动画。
static void DYYYTabGlassGlassApplyItemImages(void) {
    if (!gDYYYTabGlassBar) return;
    UIColor *selected = DYYYTabGlassGlassInkColor(YES);
    UIColor *normal = DYYYTabGlassGlassInkColor(NO);
    [gDYYYTabGlassBar.items enumerateObjectsUsingBlock:^(UITabBarItem *item, NSUInteger index, __unused BOOL *stop) {
        // 标题不另存一份：建 item 时就写进 accessibilityLabel 了，跟着 item 走不会失配。
        NSString *title = item.accessibilityLabel;
        if (title.length == 0) return;
        id tabID = index < gDYYYTabGlassItemTabIDs.count ? gDYYYTabGlassItemTabIDs[index] : nil;
        if (![tabID isKindOfClass:NSString.class]) tabID = nil;
        item.image = DYYYTabGlassGlassItemImage(tabID, title, NO, normal);
        item.selectedImage = DYYYTabGlassGlassItemImage(tabID, title, YES, selected);
    }];
}

static UIColor *DYYYTabGlassGlassHostTitleColor(NSArray *buttons, NSInteger selectedIndex) {
    for (id button in buttons) {
        UIView *view = [button isKindOfClass:UIView.class] ? button : nil;
        if (!view || view.isHidden || !view.superview) continue;
        if ([DYYYTabGlassGlassValue(button, @"type") longLongValue] == kDYYYTabGlassPlusButtonType) continue;
        if ([DYYYTabGlassGlassValue(button, @"validIndex") integerValue] != selectedIndex) continue;
        id inner = DYYYTabGlassGlassValue(button, @"innerView");
        return DYYYTabGlassGlassValue(DYYYTabGlassGlassValue(inner, @"label"), @"textColor");
    }
    return nil;
}

static UIUserInterfaceStyle DYYYTabGlassGlassInkStyleFor(NSArray *buttons, NSInteger selectedIndex,
                                               UIUserInterfaceStyle fallback) {
    UIColor *host = DYYYTabGlassGlassHostTitleColor(buttons, selectedIndex);
    if (!host) {
        return gDYYYTabGlassInkStyle != UIUserInterfaceStyleUnspecified ? gDYYYTabGlassInkStyle : fallback;
    }
    if (host == gDYYYTabGlassInkHostColor) return gDYYYTabGlassInkHostIsLight ? UIUserInterfaceStyleLight
                                                      : UIUserInterfaceStyleDark;

    // 宿主给的可能是动态色，按当前场景解析后才是真值。
    UIColor *resolved = [host resolvedColorWithTraitCollection:
        [UITraitCollection traitCollectionWithUserInterfaceStyle:fallback]];
    // 切页过渡里抖音会把文字整体淡出，那一帧的色不能用来判极性，保持上一次的结论。
    if (CGColorGetAlpha(resolved.CGColor) < 0.5) {
        return gDYYYTabGlassInkStyle != UIUserInterfaceStyleUnspecified ? gDYYYTabGlassInkStyle : fallback;
    }

    // 宿主用黑系文字 → 这一页底色偏亮 → 我们也用黑系。
    gDYYYTabGlassInkHostColor = host;
    gDYYYTabGlassInkHostIsLight = [DYYYUtils liquidGlassColorIsInk:resolved];
    return gDYYYTabGlassInkHostIsLight ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
}

static void DYYYTabGlassGlassApplyInk(UIUserInterfaceStyle style) {
    // gBar 的判定放在记录档位之前：没底栏可写就不能把档位记下来，否则下次同档会被跳过。
    if (style == UIUserInterfaceStyleUnspecified || !gDYYYTabGlassBar || style == gDYYYTabGlassInkStyle) return;
    gDYYYTabGlassInkStyle = style;
    DYYYTabGlassGlassApplyItemImages();
}

#pragma mark - 标题图

static UIImage *DYYYTabGlassGlassTitleImage(NSString *title, UIColor *color) {
    UIFont *font = [UIFont systemFontOfSize:kDYYYTabGlassTitleFontSize weight:UIFontWeightSemibold];
    CGFloat width = [title sizeWithAttributes:@{ NSFontAttributeName: font }].width;
    if (width > kDYYYTabGlassTitleMaxWidth) {
        CGFloat fontSize = MAX(kDYYYTabGlassTitleMinFontSize, floor(kDYYYTabGlassTitleFontSize * kDYYYTabGlassTitleMaxWidth / width));
        font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
    }
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color
    };
    CGSize size = [title sizeWithAttributes:attributes];
    size.width = ceil(size.width);
    size.height = ceil(size.height);

    UIGraphicsImageRendererFormat *format = UIGraphicsImageRendererFormat.preferredFormat;
    format.opaque = NO;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format]
        imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
            [title drawAtPoint:CGPointZero withAttributes:attributes];
        }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

// 「图标+文字」：图标在上、10pt 文字在下合成一张图，交给系统当图标居中；文字宽度同样受邻项间距限制。

// 按底栏样式出一张 item 图，颜色烤进图里（悬浮 provider 不采纳 tint）。表外 tabID 回落标题图。
static UIImage *DYYYTabGlassGlassItemImage(NSString *tabID, NSString *title, BOOL selected, UIColor *color) {
    return DYYYTabGlassGlassTitleImage(title, color);
}

#pragma mark - 拍摄图标

// 取抖音当前真实显示的拍摄图标。别的插件替换图标改的正是这个 image view，故天然跟随
//（UIButton 自己的 state image 也经 imageView 渲染，同样命中）。
static UIImage *DYYYTabGlassGlassPlusSourceIcon(UIView *button) {
    for (UIView *subview in button.subviews) {
        if (![subview isKindOfClass:UIImageView.class]) continue;
        UIImage *image = ((UIImageView *)subview).image;
        if (image) return image;
    }
    return nil;
}

// 按 alpha 裁掉四周透明留白。抖音给的图是 75×49 而字形只有约 33×30，直接缩进圆键会小到看不清；
// 裁完再排版，换了图标也自适应，不必写死内缩。
static UIImage *DYYYTabGlassGlassTrimTransparent(UIImage *image) {
    CGImageRef source = image.CGImage;
    if (!source) return image;

    size_t width = CGImageGetWidth(source);
    size_t height = CGImageGetHeight(source);
    if (width == 0 || height == 0) return image;

    uint8_t *alpha = (uint8_t *)calloc(width * height, sizeof(uint8_t));
    if (!alpha) return image;

    CGContextRef context = CGBitmapContextCreate(alpha, width, height, 8, width, NULL,
                                                 (CGBitmapInfo)kCGImageAlphaOnly);
    if (!context) {
        free(alpha);
        return image;
    }
    CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), source);
    CGContextRelease(context);

    size_t minX = width, minY = height, maxX = 0, maxY = 0;
    for (size_t y = 0; y < height; y++) {
        for (size_t x = 0; x < width; x++) {
            if (alpha[y * width + x] == 0) continue;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
        }
    }
    free(alpha);
    if (minX > maxX || minY > maxY) return image;   // 整张全透明，原样返回

    CGImageRef cropped = CGImageCreateWithImageInRect(
        source, CGRectMake(minX, minY, maxX - minX + 1, maxY - minY + 1));
    if (!cropped) return image;

    UIImage *result = [UIImage imageWithCGImage:cropped
                                          scale:image.scale
                                    orientation:image.imageOrientation];
    CGImageRelease(cropped);
    return result;
}

// 图标同样走模板图：抖音会随页面在白/黑两版图标间切换，只取 alpha 则两版形状一致，
// 着色跟内容极性走（见「内容取色」），黑视频上不会出现看不见的黑图标。
CGFloat DYYYTabGlassGlassPlusIconInset(void) { return kDYYYTabGlassPlusIconInset; }

// 拍摄圆键的图按「拍摄按钮」选项出：默认镜像抖音原图；新图标 / 新双色图标为照相机，
// 双色在机身下垫一层青红；自定义图片用用户的圆形图。
static void DYYYTabGlassGlassSyncPlusIcon(UIView *button) {
    if (gDYYYTabGlassPlusIconInkStyle != gDYYYTabGlassInkStyle) {
        gDYYYTabGlassPlusIconInkStyle = gDYYYTabGlassInkStyle;
        gDYYYTabGlassPlusIcon.tintColor = DYYYTabGlassGlassInkColor(YES);
    }
    UIImage *source = DYYYTabGlassGlassPlusSourceIcon(button);
    if (!source || source == gDYYYTabGlassPlusSourceIcon) return;
    gDYYYTabGlassPlusSourceIcon = source;
    gDYYYTabGlassPlusIcon.image = [DYYYTabGlassGlassTrimTransparent(source) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

#pragma mark - 点击转发

@implementation DYYYTabGlassGlassTabBarProxy

// 拍摄不是页面，走抖音自己的拍摄回调，传它自己的按钮。
- (void)plusKeyDidTap {
    UITabBarController *controller = DYYYTabGlassGlassControllerForView(gDYYYTabGlassPlusKey);
    SEL selector = NSSelectorFromString(kDYYYTabGlassPlusClickSelector);
    if (controller && gDYYYTabGlassPlusButton && [controller respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, gDYYYTabGlassPlusButton);
    }
}

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    UITabBarController *controller = DYYYTabGlassGlassControllerForView(tabBar);
    NSUInteger index = [tabBar.items indexOfObjectIdenticalTo:item];
    if (!controller || index == NSNotFound || index >= gDYYYTabGlassItemButtons.count) return;

    id button = gDYYYTabGlassItemButtons[index];
    // 切页必须走抖音自己的按钮点击回调。直接写 selectedIndex 会被它的 override 吞掉——
    // 实测底栏选中态变了、抖音的 selectedIndex 仍是 0、页面也没换，只是「看着切了」。
    // 连手势一并原样回传，抖音据此构造点击上下文，与真实点按走完全相同的路径。
    SEL selector = NSSelectorFromString(kDYYYTabGlassTabClickSelector);
    if ([controller respondsToSelector:selector]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(controller, selector, button,
                                                  DYYYTabGlassGlassValue(button, @"singleTapGes"));
    }
}

@end

#pragma mark - 未读角标镜像

// 读抖音按钮当前的角标。走子视图扫描而不是 badge / badgeContainerView 属性：那两个 getter
// 可能懒建对象，而这里是逐帧路径，只读不建才安全。
static NSString *DYYYTabGlassGlassBadgeValue(id button) {
    if (![button isKindOfClass:UIView.class]) return nil;

    UIView *badge = nil;
    for (UIView *container in ((UIView *)button).subviews) {
        if (![NSStringFromClass(container.class) isEqualToString:kDYYYTabGlassBadgeContainerClass]
            || container.isHidden || container.alpha < 0.01) {
            continue;
        }
        for (UIView *candidate in container.subviews) {
            // 尺寸也要判：抖音会把角标留在树里收成零尺寸，那不算「有角标」。
            if ([NSStringFromClass(candidate.class) isEqualToString:kDYYYTabGlassBadgeClass]
                && !candidate.isHidden && candidate.alpha >= 0.01
                && !CGRectIsEmpty(candidate.bounds)) {
                badge = candidate;
                break;
            }
        }
        if (badge) break;
    }
    if (!badge) return nil;

    NSString *text = DYYYTabGlassGlassValue(badge, @"badgeText");
    if (text.length > 0) return text;                      // 抖音自己给的文案，如 "99+"
    unsigned long long count = [DYYYTabGlassGlassValue(badge, @"badgeNumber") unsignedLongLongValue];
    if (count > 0) return @(count).stringValue;
    return @"";                                            // 有角标但无数字 → 纯红点
}

// badgeValue 交给系统渲染即得 iOS 26 悬浮胶囊里的原生红点，badgeColor 留 nil 用系统默认色。
static void DYYYTabGlassGlassSyncBadges(void) {
    NSUInteger count = MIN(gDYYYTabGlassItemButtons.count, gDYYYTabGlassBar.items.count);
    for (NSUInteger i = 0; i < count; i++) {
        UITabBarItem *item = gDYYYTabGlassBar.items[i];
        NSString *value = DYYYTabGlassGlassBadgeValue(gDYYYTabGlassItemButtons[i]);
        NSString *current = item.badgeValue;
        if (current != value && ![current isEqualToString:value]) item.badgeValue = value;
    }
}

#pragma mark - 内容镜像

static BOOL DYYYTabGlassGlassSyncItems(UITabBarController *controller, NSArray *buttons) {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableArray<NSNumber *> *kinds = [NSMutableArray array];
    NSMutableArray *mirrored = [NSMutableArray array];
    NSMutableArray *tabIDs = [NSMutableArray array];
    // 底栏样式进签名：换样式即重建 items、重新出图。
    NSMutableString *signature = [NSMutableString string];
    UIView *plus = nil;

    for (id button in buttons) {
        UIView *view = [button isKindOfClass:UIView.class] ? button : nil;
        // 源按钮的 opacity 会被本功能置零，不能作为存在性信号；显隐与父视图关系保留原始语义。
        if (!view || view.isHidden || !view.superview) continue;

        if ([DYYYTabGlassGlassValue(button, @"type") longLongValue] == kDYYYTabGlassPlusButtonType) {
            plus = view;
            continue;                  // 拍摄不进胶囊，见 DYYYLGGlassMakePlusKey
        }

        NSString *title = DYYYTabGlassGlassButtonTitle(button);
        if (title.length == 0) continue;

        NSInteger kind = [DYYYTabGlassGlassValue(button, @"validIndex") integerValue];
        NSString *tabID = DYYYTabGlassGlassValue(button, @"tabID");
        [titles addObject:title];
        [kinds addObject:@(kind)];
        [mirrored addObject:button];
        [tabIDs addObject:tabID ?: (id)NSNull.null];
        // tabID 取没取到也进签名：映射表晚于首轮布局就绪时，取到后要补出图标。
        [signature appendFormat:@"%@:%ld:%@|", title, (long)kind, tabID ?: @"-"];
    }

    gDYYYTabGlassPlusButton = plus;

    if (mirrored.count == 0) return NO;
    // 按钮引用每次都刷新：抖音可能重建出标题相同的新按钮，签名察觉不到，
    // 拿着旧对象转发点击就会落空。items 与它同序等长，只在签名变化时才重建。
    gDYYYTabGlassItemButtons = mirrored;

    BOOL rebuilt = ![signature isEqualToString:gDYYYTabGlassSignature];
    if (rebuilt) {
        NSMutableArray<UITabBarItem *> *items = [NSMutableArray arrayWithCapacity:titles.count];
        [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, __unused BOOL *stop) {
            // 标题走 image 槽（见 DYYYLGGlassTitleImage），title 置空，否则系统还会再排一行标签。
            // 图交给 DYYYLGGlassApplyItemImages 按极性统一渲染，选中与未选中各一张。
            UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:nil image:nil
                                                                 tag:(NSInteger)index];
            item.accessibilityLabel = title;   // 标题不再是文字，旁白与探针都靠它认人
            [items addObject:item];
        }];
        gDYYYTabGlassBar.items = items;
        gDYYYTabGlassItemKinds = kinds;
        gDYYYTabGlassItemTabIDs = tabIDs;
        gDYYYTabGlassSignature = [signature copy];
        DYYYTabGlassGlassApplyItemImages();
    }

    NSUInteger current = [gDYYYTabGlassItemKinds indexOfObject:@((NSInteger)controller.selectedIndex)];
    if (current != NSNotFound && current < gDYYYTabGlassBar.items.count) {
        UITabBarItem *item = gDYYYTabGlassBar.items[current];
        if (gDYYYTabGlassBar.selectedItem != item) gDYYYTabGlassBar.selectedItem = item;
    }

    DYYYTabGlassGlassSyncBadges();
    return rebuilt;
}

static BOOL gDYYYTabGlassPendingMirror = NO;

static void DYYYTabGlassGlassScheduleMirror(void) {
    if (gDYYYTabGlassPendingMirror || !gDYYYTabGlassBar) return;
    gDYYYTabGlassPendingMirror = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        gDYYYTabGlassPendingMirror = NO;
        AWENormalModeTabBar *bar = gDYYYTabGlassDouyinBar;
        UITabBarController *controller = bar ? DYYYTabGlassGlassControllerForView(bar) : nil;
        if (!gDYYYTabGlassBar || !controller) return;
        // 内容没变时纯空转；变了才重建 items，并要求底栏重排一次几何——胶囊宽度归 UIKit 算，
        // 圆键位置得跟着它走。签名收敛后不再标脏，不会形成布局环。
        // 取色排在同步之前：标题图要按极性渲染，极性得先定下来。
        NSArray *buttons = DYYYTabGlassGlassValue(bar, @"tabBarButtons");
        DYYYTabGlassGlassApplyInk(DYYYTabGlassGlassInkStyleFor(buttons, (NSInteger)controller.selectedIndex,
                                           gDYYYTabGlassGlassStyle));
        if (DYYYTabGlassGlassSyncItems(controller, buttons)) [bar setNeedsLayout];
    });
}

#pragma mark - 拍摄圆键

static UIVisualEffectView *DYYYTabGlassGlassMakePlusKey(id target) API_AVAILABLE(ios(26.0)) {
    UIVisualEffectView *key =
        [[UIVisualEffectView alloc] initWithEffect:DYYYTabGlassGlassMakeGlassEffect(gDYYYTabGlassGlassStyle, YES)];
    key.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];

    gDYYYTabGlassPlusAccent = [[UIImageView alloc] init];
    gDYYYTabGlassPlusAccent.contentMode = UIViewContentModeScaleAspectFit;
    gDYYYTabGlassPlusAccent.hidden = YES;
    [key.contentView addSubview:gDYYYTabGlassPlusAccent];

    gDYYYTabGlassPlusIcon = [[UIImageView alloc] init];
    gDYYYTabGlassPlusIcon.contentMode = UIViewContentModeScaleAspectFit;
    [key.contentView addSubview:gDYYYTabGlassPlusIcon];

    gDYYYTabGlassPlusHit = [UIButton buttonWithType:UIButtonTypeCustom];
    [gDYYYTabGlassPlusHit addTarget:target action:@selector(plusKeyDidTap)
       forControlEvents:UIControlEventTouchUpInside];
    [key.contentView addSubview:gDYYYTabGlassPlusHit];
    return key;
}

static UIView *DYYYTabGlassGlassFindPlatter(UIView *root) {
    for (UIView *subview in root.subviews) {
        if ([NSStringFromClass(subview.class) containsString:kDYYYTabGlassPlatterClass]) return subview;
        UIView *found = DYYYTabGlassGlassFindPlatter(subview);
        if (found) return found;
    }
    return nil;
}

#pragma mark - 几何

typedef struct {
    CGFloat buttonWidth;   // b
    CGFloat buttonPad;     // pad
    CGFloat height;        // 胶囊高，即圆键直径
    CGFloat top;           // 胶囊在 UITabBar 内的 y
    CGFloat inset;         // UITabBar 左右到胶囊的内缩
} DYYYTabGlassGlassMetrics;

static const DYYYTabGlassGlassMetrics kDYYYTabGlassGlassFallbackMetrics = {
    kDYYYTabGlassTabButtonFallbackWidth, kDYYYTabGlassTabButtonFallbackPad, kDYYYTabGlassPlatterFallbackHeight, 0.0, kDYYYTabGlassPlatterFallbackInset
};
static DYYYTabGlassGlassMetrics gDYYYTabGlassMetrics = kDYYYTabGlassGlassFallbackMetrics;
// 量这些值时抖音底栏的宽度；宽度变了全部作废，重新量。
static CGFloat gDYYYTabGlassMetricsBarWidth = 0.0;
// 最近一次布局的读数，只给探针看。
static CGFloat gDYYYTabGlassGeometryTarget = 0.0;

static void DYYYTabGlassGlassCollectTabButtons(UIView *root, NSMutableArray<UIView *> *result) {
    for (UIView *subview in root.subviews) {
        if ([NSStringFromClass(subview.class) isEqualToString:kDYYYTabGlassTabButtonClass]) [result addObject:subview];
        else DYYYTabGlassGlassCollectTabButtons(subview, result);
    }
}

static BOOL DYYYTabGlassGlassMetricChanged(CGFloat a, CGFloat b) {
    return fabs(a - b) > 0.5;
}

// 从 platter 实物量出各项；返回 YES 表示有量变了，需要按新值重算一轮。
// 胶囊里每颗按钮画两份（选中 / 未选中），frame 相同，取 minX 最小与次小的两个不同值即可。
// 内缩只在压缩态量：此时胶囊两侧各让出一个内缩；自然态胶囊比可用宽度窄，读数偏大不可信。
static BOOL DYYYTabGlassGlassMeasure(UIView *platter, NSUInteger count) {
    if (!platter || CGRectGetHeight(platter.bounds) <= 0.0) return NO;
    CGRect frame = [platter convertRect:platter.bounds toView:gDYYYTabGlassBar];
    DYYYTabGlassGlassMetrics metrics = gDYYYTabGlassMetrics;
    metrics.height = CGRectGetHeight(frame);
    metrics.top = CGRectGetMinY(frame);

    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    DYYYTabGlassGlassCollectTabButtons(platter, buttons);
    CGFloat first = CGFLOAT_MAX, second = CGFLOAT_MAX, width = 0.0;
    for (UIView *button in buttons) {
        CGRect rect = [button convertRect:button.bounds toView:platter];
        CGFloat x = CGRectGetMinX(rect);
        if (x < first - 0.5) {
            if (first < CGFLOAT_MAX) second = first;
            first = x;
            width = CGRectGetWidth(rect);
        } else if (x > first + 0.5 && x < second - 0.5) {
            second = x;
        }
    }
    if (first < CGFLOAT_MAX && width > 0.0) {
        metrics.buttonPad = first;
        metrics.buttonWidth = width;
    }
    CGFloat naturalPitch = metrics.buttonWidth - 2.0 * metrics.buttonPad;
    if (count >= 2 && second < CGFLOAT_MAX && second - first < naturalPitch - 0.5) {
        metrics.inset = (CGRectGetWidth(gDYYYTabGlassBar.bounds) - CGRectGetWidth(frame)) / 2.0;
    }

    BOOL changed = DYYYTabGlassGlassMetricChanged(metrics.buttonWidth, gDYYYTabGlassMetrics.buttonWidth) ||
                   DYYYTabGlassGlassMetricChanged(metrics.buttonPad, gDYYYTabGlassMetrics.buttonPad) ||
                   DYYYTabGlassGlassMetricChanged(metrics.height, gDYYYTabGlassMetrics.height) ||
                   DYYYTabGlassGlassMetricChanged(metrics.inset, gDYYYTabGlassMetrics.inset);
    gDYYYTabGlassMetrics = metrics;
    return changed;
}

// 胶囊宽度跟着 4+1 参考态走：参考态是 reference 个项目、右侧有拍摄圆键、整组占满底栏两侧内缩之间。
// 由参考态得出相邻间距，少几项就少几个间距——每项的大小与位置间隔都与参考态相同，不拉长。
static CGFloat DYYYTabGlassGlassCapsuleWidth(NSUInteger count, NSUInteger reference, CGFloat barWidth) {
    CGFloat single = gDYYYTabGlassMetrics.buttonWidth + 2.0 * gDYYYTabGlassMetrics.buttonPad;
    CGFloat naturalPitch = MAX(gDYYYTabGlassMetrics.buttonWidth - 2.0 * gDYYYTabGlassMetrics.buttonPad, 0.0);
    reference = MAX(reference, count);
    if (count <= 1 || reference <= 1) return single;

    CGFloat available = barWidth - gDYYYTabGlassMetrics.height - kDYYYTabGlassPlusKeyGap - 2.0 * gDYYYTabGlassMetrics.inset;
    CGFloat referenceWidth = MIN(available, single + (reference - 1) * naturalPitch);
    CGFloat pitch = MIN(MAX((referenceWidth - single) / (reference - 1), 0.0), naturalPitch);
    return single + (count - 1) * pitch;
}

static void DYYYTabGlassGlassLayoutGlass(AWENormalModeTabBar *douyinBar, NSUInteger reference) API_AVAILABLE(ios(26.0)) {
    CGSize size = douyinBar.bounds.size;
    if (DYYYTabGlassGlassMetricChanged(size.width, gDYYYTabGlassMetricsBarWidth)) {
        gDYYYTabGlassMetrics = kDYYYTabGlassGlassFallbackMetrics;
        gDYYYTabGlassMetricsBarWidth = size.width;
    }

    // 拍摄按钮被移除时圆键一并隐藏。
    BOOL available = gDYYYTabGlassPlusButton != nil;
    if (gDYYYTabGlassPlusKey.isHidden == available) gDYYYTabGlassPlusKey.hidden = !available;

    NSUInteger count = gDYYYTabGlassBar.items.count;
    UIView *platterView = nil;
    for (NSUInteger pass = 0; pass < 2; pass++) {
        gDYYYTabGlassGeometryTarget = DYYYTabGlassGlassCapsuleWidth(count, reference, size.width);
        CGFloat barWidth = gDYYYTabGlassGeometryTarget + 2.0 * gDYYYTabGlassMetrics.inset;
        CGRect frame = gDYYYTabGlassBar.frame;
        if (fabs(CGRectGetWidth(frame) - barWidth) > 0.01 || CGRectGetHeight(frame) != size.height) {
            gDYYYTabGlassBar.frame = CGRectMake(CGRectGetMinX(frame), 0.0, barWidth, size.height);
        }
        [gDYYYTabGlassBar layoutIfNeeded];
        platterView = DYYYTabGlassGlassFindPlatter(gDYYYTabGlassBar);
        if (!DYYYTabGlassGlassMeasure(platterView, count)) break;
    }
    // 找到 platter 就顺手把它的玻璃换成 Clear。放在所有提前 return 之前：
    // 拍摄按钮被移除时下面会早退，但胶囊材质照样要生效。
    DYYYTabGlassGlassApplyPlatterGlass(platterView, gDYYYTabGlassGlassStyle);

    CGRect platter = platterView ? [platterView convertRect:platterView.bounds toView:gDYYYTabGlassBar] : CGRectZero;
    BOOL measured = CGRectGetWidth(platter) > 0.0;
    CGFloat capsule = measured ? CGRectGetWidth(platter) : gDYYYTabGlassGeometryTarget;
    CGFloat capsuleX = measured ? CGRectGetMinX(platter) : gDYYYTabGlassMetrics.inset;
    CGFloat diameter = gDYYYTabGlassMetrics.height;

    CGFloat group = capsule + (available ? kDYYYTabGlassPlusKeyGap + diameter : 0.0);
    CGFloat left = (size.width - group) / 2.0;
    CGRect barFrame = gDYYYTabGlassBar.frame;
    barFrame.origin.x = left - capsuleX;
    if (!CGRectEqualToRect(gDYYYTabGlassBar.frame, barFrame)) gDYYYTabGlassBar.frame = barFrame;
    if (!available) return;

    CGRect keyFrame = CGRectMake(left + capsule + kDYYYTabGlassPlusKeyGap, gDYYYTabGlassMetrics.top, diameter, diameter);
    if (!CGRectEqualToRect(gDYYYTabGlassPlusKey.frame, keyFrame)) gDYYYTabGlassPlusKey.frame = keyFrame;

    CGRect bounds = gDYYYTabGlassPlusKey.bounds;
    CGFloat iconInset = DYYYTabGlassGlassPlusIconInset();
    CGRect iconFrame = CGRectInset(bounds, iconInset, iconInset);
    if (!CGRectEqualToRect(gDYYYTabGlassPlusIcon.frame, iconFrame)) gDYYYTabGlassPlusIcon.frame = iconFrame;
    if (!CGRectEqualToRect(gDYYYTabGlassPlusAccent.frame, iconFrame)) gDYYYTabGlassPlusAccent.frame = iconFrame;
    if (!CGRectEqualToRect(gDYYYTabGlassPlusHit.frame, bounds)) gDYYYTabGlassPlusHit.frame = bounds;

    DYYYTabGlassGlassSyncPlusIcon(gDYYYTabGlassPlusButton);
}

static void DYYYTabGlassGlassSetDouyinContentVisible(AWENormalModeTabBar *douyinBar, NSArray *buttons, BOOL visible) {
    float opacity = visible ? 1.0f : 0.0f;
    NSArray *backdrops = @[ DYYYTabGlassGlassValue(douyinBar, @"backgroundView") ?: NSNull.null,
                            DYYYTabGlassGlassValue(douyinBar, @"awe_blurView") ?: NSNull.null,
                            DYYYTabGlassGlassValue(douyinBar, @"separatorLine") ?: NSNull.null,
                            DYYYTabGlassGlassValue(douyinBar, @"skinContainerView") ?: NSNull.null ];
    for (id backdrop in backdrops) {
        if (![backdrop isKindOfClass:UIView.class]) continue;
        CALayer *layer = ((UIView *)backdrop).layer;
        if (layer.opacity != opacity) layer.opacity = opacity;
    }
    for (id button in buttons) {
        if (![button isKindOfClass:UIView.class]) continue;
        UIView *view = button;
        if (view.layer.opacity != opacity) view.layer.opacity = opacity;
        if (view.userInteractionEnabled != visible) view.userInteractionEnabled = visible;
    }
}

// 4+1 参考态里胶囊的项目数：当前在镜像的项目，加上被「移除底栏项目」隐藏的。
// 抖音或其他插件自己藏起的按钮不算，那不是参考态的一部分。
static NSUInteger DYYYTabGlassGlassReferenceCount(NSArray *buttons) {
    NSUInteger count = 0;
    for (id button in buttons) {
        UIView *view = [button isKindOfClass:UIView.class] ? button : nil;
        if (!view.superview) continue;
        if ([DYYYTabGlassGlassValue(button, @"type") longLongValue] == kDYYYTabGlassPlusButtonType) continue;
        if (!view.isHidden) count++;
    }
    return count;
}

#pragma mark - 挂载与拆除

// 整个功能只在 iOS 26 及以上成立——低版本没有 UIGlassEffect，装上去只是一条没有玻璃的
// UITabBar 盖住抖音底栏，比原生还差。故在此一处挡住，各 helper 用 API_AVAILABLE 标注。
static void DYYYTabGlassGlassUpdate(AWENormalModeTabBar *douyinBar) API_AVAILABLE(ios(26.0)) {
    // 抖音换过底栏实例时，先把旧那条的内容还原——玻璃底栏只会跟着新实例走，
    // 旧实例的按钮若停在 opacity=0，它再次出现时就是一条空底栏。
    AWENormalModeTabBar *previousBar = gDYYYTabGlassDouyinBar;
    if (previousBar && previousBar != douyinBar && gDYYYTabGlassBar) {
        DYYYTabGlassGlassSetDouyinContentVisible(
            previousBar, DYYYTabGlassGlassValue(previousBar, @"tabBarButtons"), YES);
    }
    gDYYYTabGlassDouyinBar = douyinBar;

    NSArray *buttons = DYYYTabGlassGlassValue(douyinBar, @"tabBarButtons");
    if (!DYYYTabGlassGlassTabBarEnabled()) {
        if (!gDYYYTabGlassBar) return;
        DYYYTabGlassGlassSetDouyinContentVisible(douyinBar, buttons, YES);
        [gDYYYTabGlassBar removeFromSuperview];
        [gDYYYTabGlassPlusKey removeFromSuperview];
        gDYYYTabGlassBar = nil;
        gDYYYTabGlassPlusKey = nil;
        gDYYYTabGlassPlusIcon = nil;
        gDYYYTabGlassPlusAccent = nil;
        gDYYYTabGlassPlusHit = nil;
        gDYYYTabGlassPlusButton = nil;
        gDYYYTabGlassPlusSourceIcon = nil;
        gDYYYTabGlassProxy = nil;
        gDYYYTabGlassItemKinds = nil;
        gDYYYTabGlassItemButtons = nil;
        gDYYYTabGlassItemTabIDs = nil;
        gDYYYTabGlassSignature = nil;
        // 重新开启时材质与 platter 玻璃都要能重新装上；探测结果不复位，那是设备能力，一次为准。
        gDYYYTabGlassGlassStyle = UIUserInterfaceStyleUnspecified;
        gDYYYTabGlassInkStyle = UIUserInterfaceStyleUnspecified;
        gDYYYTabGlassInkHostColor = nil;
        gDYYYTabGlassPlusIconInkStyle = UIUserInterfaceStyleUnspecified;
        gDYYYTabGlassPlatterGlassStyle = UIUserInterfaceStyleUnspecified;
        gDYYYTabGlassPlatterGlassInstalled = nil;
        // 玻璃底栏是可视化的落位基准，它一撤可视化必须跟着撤，否则会留下一层孤儿视图。
        return;
    }
    // 场景监听不撤：handler 只在 gBar 存在时才动手，重新开启开关后照旧生效。

    UITabBarController *controller = DYYYTabGlassGlassControllerForView(douyinBar);
    if (!controller) return;

    if (!gDYYYTabGlassBar) {
        gDYYYTabGlassProxy = [[DYYYTabGlassGlassTabBarProxy alloc] init];
        // 不碰 appearance：实测出厂态与装了 Regular backgroundEffect 渲染逐像素相同，
        // 悬浮 provider 不读这个旧 API。材质统一由 DYYYLGGlassApplyPlatterGlass 决定。
        gDYYYTabGlassBar = [[UITabBar alloc] initWithFrame:douyinBar.bounds];
        gDYYYTabGlassBar.delegate = gDYYYTabGlassProxy;
        gDYYYTabGlassPlusKey = DYYYTabGlassGlassMakePlusKey(gDYYYTabGlassProxy);
    }

    // 作为子视图挂在抖音底栏内：显隐/透明度/位置全部随父视图继承。
    if (gDYYYTabGlassBar.superview != douyinBar) [douyinBar addSubview:gDYYYTabGlassBar];
    if (gDYYYTabGlassPlusKey.superview != douyinBar) [douyinBar addSubview:gDYYYTabGlassPlusKey];
    // 置顶兜底——其他插件遍历底栏子视图后可能改动层级。圆键在胶囊之上。
    if (douyinBar.subviews.lastObject != gDYYYTabGlassPlusKey) {
        [douyinBar bringSubviewToFront:gDYYYTabGlassBar];
        [douyinBar bringSubviewToFront:gDYYYTabGlassPlusKey];
    }

    DYYYTabGlassGlassObserveStyle(douyinBar);
    // 监听之外再逐帧比对一次：冷启动首帧与刚挂上时都没有 trait 变化事件可等。
    DYYYTabGlassGlassApplyStyle(douyinBar.window.windowScene.traitCollection.userInterfaceStyle);
    // 取色排在最前：标题图按极性渲染，拍摄图标着色也要用这一步定下的极性。
    DYYYTabGlassGlassApplyInk(DYYYTabGlassGlassInkStyleFor(buttons, (NSInteger)controller.selectedIndex, gDYYYTabGlassGlassStyle));
    DYYYTabGlassGlassSyncItems(controller, buttons);
    DYYYTabGlassGlassLayoutGlass(douyinBar, DYYYTabGlassGlassReferenceCount(buttons));
    DYYYTabGlassGlassSetDouyinContentVisible(douyinBar, buttons, NO);
    // 放在最后：可视化的环绕轮廓要用 DYYYLGGlassLayoutGlass 刚算完的胶囊与圆键几何。
}

#pragma mark - Hook

%group DYYYTabGlassGlassTabBarHooks

%hook AWENormalModeTabBar

- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DYYYTabGlassGlassUpdate(self);
}

%end

// 角标变化不一定伴随底栏重新布局（收到推送时就不会），故在抖音写入角标的两个入口上
// 立即重跑一次同步。逐帧同步只兜稳态。
%hook AWENormalModeTabBarGeneralButton

- (id)p_showBadgeWithStyle:(unsigned long long)style count:(long long)count text:(id)text config:(id)config {
    id result = %orig;
    if (gDYYYTabGlassBar) DYYYTabGlassGlassSyncBadges();
    return result;
}

- (void)hideBadge {
    %orig;
    if (gDYYYTabGlassBar) DYYYTabGlassGlassSyncBadges();
}

%end

// 这两个子视图是其他插件改底栏内容的落点：DYYY 在 TextView 里写 label.text 改标题，
// 在 BadgeContainerView 里把 DUXBadge 隐掉。见 DYYYLGGlassScheduleMirror。
%hook AWENormalModeTabBarTextView

- (void)layoutSubviews {
    %orig;
    DYYYTabGlassGlassScheduleMirror();
}

- (void)textColorChangedWithSelectedStatus:(BOOL)selected {
    %orig;
    DYYYTabGlassGlassScheduleMirror();
}

- (void)tabbarStatusDidChanged:(long long)status animated:(BOOL)animated {
    %orig;
    DYYYTabGlassGlassScheduleMirror();
}

%end

%hook AWENormalModeTabBarBadgeContainerView

- (void)layoutSubviews {
    %orig;
    DYYYTabGlassGlassScheduleMirror();
}

%end

%end

#pragma mark - 评论区液体玻璃（通透）

// 移植自 DYKiller，MIT 许可见 LICENSE。

// 依赖的抖音类名集中在此，抖音改名时只改这里。
static NSString *const kDYYYCommentGlassInnerControllerClass =
    @"AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController";
static NSString *const kDYYYCommentGlassInputContainerClass =
    @"AWECommentInputViewSwiftImpl.CommentInputContainerView";
static NSString *const kDYYYCommentGlassFoldDisplayClass =
    @"AWECommentPanelListSwiftImpl.CommentFoldDisplayView";

// 输入栏底色槽的尺寸比对容差。
static const CGFloat kDYYYCommentGlassSlotSizeTolerance = 0.5;
// 槽位尚未写入圆角时的顶部半径下限，保证玻璃有效半径 > 0。
static const CGFloat kDYYYCommentGlassTopRadiusFloor = 8.0;
// 没有可复用的页面转场时，材质更换使用这个短动画。
static const NSTimeInterval kDYYYCommentGlassGlassAnimationDuration = 0.25;
// 满幅底色清扫的深度上限：主面板要一路走到 Cell 里（第 12 层左右）；输入栏容器最深只到表情
// 面板的 tab 条（第 6 层），收窄一点也把表情面板展开时的遍历成本关住。判据见 DYYYLGIsCoverCandidate。
static const NSUInteger kDYYYCommentGlassPanelCoverWalkDepth = 14;
static const NSUInteger kDYYYCommentGlassInputCoverWalkDepth = 8;
static const CGFloat kDYYYCommentGlassCoverMinHeight = 8.0;

#pragma mark - 状态（全部挂在被改动的视图上，多个评论面板并存也互不干扰）

static char kDYYYCommentGlassSlotOriginalColorKey;     // 槽位：抖音写的底色
static char kDYYYCommentGlassSlotGlassKey;             // 槽位：我们插的玻璃层
static char kDYYYCommentGlassCoverOriginalColorKey;    // 遮盖层：抖音写的底色
static char kDYYYCommentGlassGlassClearModeKey;         // 玻璃：当前 effect 是否按 Clear 构造
static char kDYYYCommentGlassGlassMaterializingKey;     // 玻璃：已排入 materialize，防止重复排队
static char kDYYYCommentGlassFoldMaskedHiddenKey;       // 被折叠条盖住的兄弟：抖音原本的 hidden

// 本次会话是否接管过槽位。开关一直关着的用户不必为每帧的查找与还原付出代价。
static BOOL gDYYYCommentGlassEverAttached = NO;
// 所有在场的玻璃层，供深浅色切换时统一更新。
static NSHashTable *gDYYYCommentGlassGlassCarriers = nil;
// 已清过底色的满幅遮盖层，关开关时还原。
static NSHashTable *gDYYYCommentGlassClearedCovers = nil;
// 被折叠提示条盖住、由我们代抖音藏起来的兄弟视图，关开关时还原。
static NSHashTable *gDYYYCommentGlassFoldMaskedViews = nil;
// 已挂上深浅色监听的场景，避免重复注册。
static __weak UIWindowScene *gDYYYCommentGlassObservedScene = nil;
// 拦下「不透明绘制优化」网关的次数，只给调试探针读。
// 最近接管的面板槽位与输入框槽位，只给调试探针读。
static __weak UIView *gDYYYCommentGlassLastPanelSlot = nil;
// 最近接管的输入栏容器。主面板玻璃的让位判据、小表情栏的清色判据都以它那块玻璃为准。
static __weak UIView *gDYYYCommentGlassLastInputContainer = nil;
// 在场的小表情栏。它随键盘来去，玻璃可能比它后到，同步时补清一次。
static __weak UIView *gDYYYCommentGlassEmoticonPanel = nil;
// 最近同步过的评论控制器，供小表情栏那条补救路径回调同步（见 DYYYLGCommentEmoticonHook）。
static __weak UIViewController *gDYYYCommentGlassLastController = nil;

#pragma mark - 小工具

static BOOL DYYYCommentGlassColorIsOpaque(UIColor *color) {
    return color && CGColorGetAlpha(color.CGColor) >= 0.99;
}

static BOOL DYYYCommentGlassViewIsVisible(UIView *view) {
    return view && !view.hidden && view.alpha >= 0.01;
}

// 输入栏隐藏使用透明 mask 保留点击；其后代玻璃也不再提供可见覆盖。
static BOOL DYYYCommentGlassViewChainVisible(UIView *view) {
    for (UIView *node = view; node; node = node.superview) {
        if (!DYYYCommentGlassViewIsVisible(node)) return NO;
    }
    return YES;
}

#pragma mark - 材质与外观

// 抖音的 window override 恒为浅色，真实系统外观从 UIWindowScene 取。
static UIUserInterfaceStyle gDYYYCommentGlassGlassStyle = UIUserInterfaceStyleUnspecified;

static BOOL DYYYCommentGlassColorsEqual(UIColor *lhs, UIColor *rhs) {
    return lhs == rhs || [lhs isEqual:rhs];
}

static UIUserInterfaceStyle DYYYCommentGlassGlassStyleForView(UIView *view) {
    UIUserInterfaceStyle style = view.window.windowScene.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = gDYYYCommentGlassGlassStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = view.traitCollection.userInterfaceStyle;
    return style == UIUserInterfaceStyleUnspecified ? UIUserInterfaceStyleLight : style;
}

static BOOL DYYYCommentGlassCommentGlassEnabled(void) {
    return [DYYYUtils liquidGlassAvailable] && [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableCommentBlur"];
}

static BOOL DYYYCommentGlassCommentGlassUsesClearMaterial(void) { return YES; }

static UIUserInterfaceStyle DYYYCommentGlassGlassOverrideStyle(BOOL clear, UIUserInterfaceStyle style) {
    return clear ? UIUserInterfaceStyleUnspecified : style;
}

static UIColor *DYYYCommentGlassCommentGlassTint(BOOL clear, UIUserInterfaceStyle style) {
    return clear ? [DYYYUtils liquidGlassTintForStyle:style] : nil;
}

static UIGlassEffect *DYYYCommentGlassMakeCommentGlassEffect(BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    UIGlassEffect *effect = [UIGlassEffect effectWithStyle:
        clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
    effect.tintColor = DYYYCommentGlassCommentGlassTint(clear, style);
    effect.interactive = YES;
    return effect;
}

static void DYYYCommentGlassRunGlassAnimation(UIViewController *controller, BOOL animated, void (^changes)(void)) {
    if (!changes) return;
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        [UIView performWithoutAnimation:changes];
        return;
    }

    id<UIViewControllerTransitionCoordinator> coordinator = controller.transitionCoordinator;
    if (coordinator && coordinator.isAnimated) {
        BOOL accepted = [coordinator
            animateAlongsideTransition:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
                changes();
            }
            completion:nil];
        if (accepted) return;
    }

    [UIView animateWithDuration:kDYYYCommentGlassGlassAnimationDuration
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState
                              | UIViewAnimationOptionAllowUserInteraction
                              | UIViewAnimationOptionCurveEaseInOut
                     animations:changes
                     completion:nil];
}

static void DYYYCommentGlassInstallGlassEffect(UIVisualEffectView *glass, UIGlassEffect *effect, BOOL clear)
    API_AVAILABLE(ios(26.0)) {
    glass.effect = effect;
    objc_setAssociatedObject(glass, &kDYYYCommentGlassGlassClearModeKey, @(clear), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL DYYYCommentGlassGlassNeedsAppearance(UIVisualEffectView *glass, BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    UIGlassEffect *current = [glass.effect isKindOfClass:UIGlassEffect.class]
        ? (UIGlassEffect *)glass.effect : nil;
    if (!current) return glass.effect != nil;

    NSNumber *installedClear = objc_getAssociatedObject(glass, &kDYYYCommentGlassGlassClearModeKey);
    if (!installedClear || installedClear.boolValue != clear) return YES;
    if (!current.interactive) return YES;
    return !DYYYCommentGlassColorsEqual(current.tintColor, DYYYCommentGlassCommentGlassTint(clear, style));
}

// 外观切换只改 overrideUserInterfaceStyle；只有 Regular/Clear 档位或 tint 真的变了才重建 effect。
static void DYYYCommentGlassApplyGlassStyle(UIUserInterfaceStyle style, BOOL animated) API_AVAILABLE(ios(26.0)) {
    if (style == UIUserInterfaceStyleUnspecified) return;
    gDYYYCommentGlassGlassStyle = style;

    BOOL clear = DYYYCommentGlassCommentGlassUsesClearMaterial();
    NSArray<UIVisualEffectView *> *carriers = gDYYYCommentGlassGlassCarriers.allObjects;
    UIUserInterfaceStyle override = DYYYCommentGlassGlassOverrideStyle(clear, style);

    NSMutableArray<UIVisualEffectView *> *restyle = [NSMutableArray array];
    for (UIVisualEffectView *glass in carriers) {
        if (glass.overrideUserInterfaceStyle != override) {
            glass.overrideUserInterfaceStyle = override;
        }
        if (glass.effect && DYYYCommentGlassGlassNeedsAppearance(glass, clear, style)) [restyle addObject:glass];
    }
    if (restyle.count == 0) return;

    DYYYCommentGlassRunGlassAnimation(nil, animated, ^{
        for (UIVisualEffectView *glass in restyle) {
            DYYYCommentGlassInstallGlassEffect(glass, DYYYCommentGlassMakeCommentGlassEffect(clear, style), clear);
        }
    });
}

// 挂在场景上监听，系统一切深浅色即刻改；否则只能等抖音下次布局。
static void DYYYCommentGlassObserveGlassStyle(UIView *host) API_AVAILABLE(ios(26.0)) {
    UIWindowScene *scene = host.window.windowScene;
    if (!scene || scene == gDYYYCommentGlassObservedScene) return;
    gDYYYCommentGlassObservedScene = scene;
    [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                       withHandler:^(UIWindowScene *changed, __unused UITraitCollection *previous) {
        DYYYCommentGlassApplyGlassStyle(changed.traitCollection.userInterfaceStyle, YES);
    }];
}

#pragma mark - 槽位

// 槽位候选：当前带不透明底色，或底色已被我们清掉但记忆还在。
static BOOL DYYYCommentGlassIsSlotCandidate(UIView *view) {
    return objc_getAssociatedObject(view, &kDYYYCommentGlassSlotOriginalColorKey) != nil
        || DYYYCommentGlassColorIsOpaque(view.backgroundColor);
}

// 整棵跳过 effect view：底色槽接管之后玻璃就挂在它里面，UIKit 那套内部视图里既有满幅的、
// 也有带圆角的，扫进来会被当成第二个槽位。别的插件的 effect 同理，也不该往里认。
static void DYYYCommentGlassCollectSlotCandidates(UIView *view, NSUInteger depth, NSMutableArray<UIView *> *candidates) {
    if (depth > 4) return;
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:UIVisualEffectView.class]) continue;
        if (DYYYCommentGlassIsSlotCandidate(subview)) [candidates addObject:subview];
        DYYYCommentGlassCollectSlotCandidates(subview, depth + 1, candidates);
    }
}

// 半屏与全屏复用同一个评论控制器；槽位按结构解析，认不出时不接管。
static UIView *DYYYCommentGlassPanelSlot(UIViewController *controller) {
    UIViewController *inner = [DYYYUtils findViewControllerOfClass:NSClassFromString(kDYYYCommentGlassInnerControllerClass) inViewController:controller];
    return inner.isViewLoaded ? inner.view : nil;
}

static UIView *DYYYCommentGlassInputContainer(UIViewController *controller) {
    Class containerClass = NSClassFromString(kDYYYCommentGlassInputContainerClass);
    if (!containerClass || !controller.isViewLoaded) return nil;
    for (UIView *subview in controller.view.subviews) {
        if ([subview isKindOfClass:containerClass]) return subview;
    }
    return nil;
}

// 输入栏里只剩一个要单独接管的槽位：输入框那枚圆角胶囊。
// 整个输入区的底（底色槽、艾特面板、表情面板）由容器那一块玻璃统一垫，见 DYYYLGSyncInputGlass。
static UIView *DYYYCommentGlassInputFieldSlot(UIView *container) {
    if (!container) return nil;

    NSMutableArray<UIView *> *candidates = [NSMutableArray array];
    DYYYCommentGlassCollectSlotCandidates(container, 0, candidates);

    CGSize size = container.bounds.size;
    for (UIView *candidate in candidates) {
        // 铺满容器的是底色槽、艾特面板或表情面板，都不是胶囊——它们由容器那块玻璃统一垫。
        CGSize candidateSize = candidate.bounds.size;
        if (fabs(candidateSize.width - size.width) <= kDYYYCommentGlassSlotSizeTolerance) continue;
        // 发送键之类的圆角控件也有底色，胶囊本身从来不是控件。
        if ([candidate isKindOfClass:UIControl.class]) continue;
        if (candidate.layer.cornerRadius > 0.0) return candidate;
    }
    return nil;
}

#pragma mark - 玻璃层

// 玻璃要垫在抖音内容之下。其他插件遍历子视图后可能改动层级，每轮校验一次，顺序对就不动。
static void DYYYCommentGlassEnsureBackmost(UIView *slot, UIView *glass) {
    if (slot.subviews.firstObject == glass) return;
    [slot insertSubview:glass atIndex:0];
}

typedef NS_ENUM(NSUInteger, DYYYCommentGlassGlassShape) {
    // 上圆下方：主面板；顶部半径跟槽位实时 cornerRadius。
    DYYYCommentGlassGlassShapeTopRounded = 0,
    // 跟随槽位实时 cornerRadius：输入框那枚控件。常驻态它的半径正好是半高，本来就是胶囊。
    DYYYCommentGlassGlassShapeField,
    // 输入栏容器，平角：它与主面板玻璃上下拼接，顶边给圆角会在两角露出原始视频。
    DYYYCommentGlassGlassShapeBarFlat,
    // 输入栏容器，上圆下方：艾特 / 表情面板把输入区顶出主面板之后，顶边成了露在视频上的自由边，
    // 原生那条盖条就是 8pt 圆角。
    DYYYCommentGlassGlassShapeBarRounded,
};

static BOOL DYYYCommentGlassGlassShapeIsBar(DYYYCommentGlassGlassShape shape) {
    return shape == DYYYCommentGlassGlassShapeBarFlat || shape == DYYYCommentGlassGlassShapeBarRounded;
}

static void DYYYCommentGlassSyncPanelGlassHeight(void);
static void DYYYCommentGlassClearCoverLayers(UIView *slot, NSUInteger maxDepth);

@implementation DYYYCommentGlassCommentBarGlassView

- (void)layoutSubviews {
    [super layoutSubviews];
    DYYYCommentGlassSyncPanelGlassHeight();

    // 尺寸变了 = 输入区换了形态（艾特面板 / 表情面板出现或收起）。新露出来的那一块若在玻璃
    // 出现**之前**就被抖音画过底色，取色口那道拦截赶不上，按形态变化补扫一次。
    // 只认尺寸变化：layoutSubviews 本身可能被调很多次，而形态切换一共就那么几次。
    CGSize size = self.bounds.size;
    if (CGSizeEqualToSize(size, _dkSweptSize)) return;
    _dkSweptSize = size;
    DYYYCommentGlassClearCoverLayers(self.superview, kDYYYCommentGlassInputCoverWalkDepth);
}

@end

// 先以 nil effect 建好视图；挂上视图树并完成几何后再走系统 materialize。
// 用 DYYYGlassFlexView 而不是裸 UIVisualEffectView：它多一条触摸源重定向，除此之外行为一致。
static UIVisualEffectView *DYYYCommentGlassMakeGlassShell(DYYYCommentGlassGlassShape shape) API_AVAILABLE(ios(26.0)) {
    Class shellClass = DYYYCommentGlassGlassShapeIsBar(shape) ? DYYYCommentGlassCommentBarGlassView.class : DYYYGlassFlexView.class;
    DYYYGlassFlexView *glass = [[shellClass alloc] initWithEffect:nil];
    glass.userInteractionEnabled = NO;
    glass.alpha = 1.0;
    // 输入框与输入栏都会在常驻态与回复态之间改变尺寸；交给 UIKit 按槽位 bounds 自动跟随。
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // 胶囊已有输入栏的底层，额外白底与模糊只铺一次。
    if (shape != DYYYCommentGlassGlassShapeField) {
        DYYYGlassBackdropView *background = [[DYYYGlassBackdropView alloc] initWithSettingsPrefix:@"DYYYCommentGlass"];
        background.frame = glass.contentView.bounds;
        background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        background.userInteractionEnabled = NO;
        glass.contentView.clipsToBounds = YES;
        [glass.contentView addSubview:background];
    }
    return glass;
}

// 顶部：同心圆角 + 槽位实时半径作下限，保证折射与高光所需的有效圆角。
// 胶囊：系统 capsuleConfiguration，正方形/扁矩形上都保证有效圆角 > 0。
static void DYYYCommentGlassApplyGlassShape(UIVisualEffectView *glass, UIView *slot, DYYYCommentGlassGlassShape shape)
    API_AVAILABLE(ios(26.0)) {
    // cornerConfiguration 是 nonnull，且形状会在 BarFlat / BarRounded 之间来回切，
    // 必须显式写回 0 半径，不能留着上一次的圆角。
    if (shape == DYYYCommentGlassGlassShapeBarFlat) {
        glass.cornerConfiguration =
            [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:0.0]];
        glass.contentView.cornerConfiguration = glass.cornerConfiguration;
        return;
    }
    // 输入框：跟随抖音写在槽位上的圆角，不写死 capsule。抖音恒写 18——常驻 36pt 高时它等于半高、
    // 观感就是胶囊；加图或多行涨到 124pt 时它是圆角矩形。而文字与图片缩略图是槽位的**兄弟视图**，
    // 画在玻璃上面、不受槽位裁剪，写死 capsule 会把两侧收进 62pt，把它们甩到玻璃外面。
    if (shape == DYYYCommentGlassGlassShapeField) {
        CGFloat radius = slot.layer.cornerRadius;
        glass.cornerConfiguration = radius > 0.0
            ? [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:radius]]
            : [UICornerConfiguration capsuleConfiguration];
        glass.contentView.cornerConfiguration = glass.cornerConfiguration;
        return;
    }

    CGFloat floor = slot.layer.cornerRadius;
    if (floor <= 0.0) floor = kDYYYCommentGlassTopRadiusFloor;
    UICornerRadius *top = [UICornerRadius containerConcentricRadiusWithMinimum:floor];
    glass.cornerConfiguration =
        [UICornerConfiguration configurationWithUniformTopRadius:top
                                                bottomLeftRadius:nil
                                               bottomRightRadius:nil];
    glass.contentView.cornerConfiguration = glass.cornerConfiguration;
}

// 仅在 effect 仍为 nil 时写入，让系统 materialize 动画跑一次。
static void DYYYCommentGlassMaterializeGlass(UIVisualEffectView *glass, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!glass || glass.effect || [objc_getAssociatedObject(glass, &kDYYYCommentGlassGlassMaterializingKey) boolValue]) return;
    objc_setAssociatedObject(glass, &kDYYYCommentGlassGlassMaterializingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    DYYYCommentGlassRunGlassAnimation(controller, YES, ^{
        if (!glass.superview || !DYYYCommentGlassCommentGlassEnabled()) {
            objc_setAssociatedObject(glass, &kDYYYCommentGlassGlassMaterializingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }

        UIUserInterfaceStyle style = gDYYYCommentGlassGlassStyle;
        if (style == UIUserInterfaceStyleUnspecified) style = DYYYCommentGlassGlassStyleForView(glass);
        BOOL clear = DYYYCommentGlassCommentGlassUsesClearMaterial();
        glass.overrideUserInterfaceStyle = DYYYCommentGlassGlassOverrideStyle(clear, style);
        DYYYCommentGlassInstallGlassEffect(glass, DYYYCommentGlassMakeCommentGlassEffect(clear, style), clear);
        objc_setAssociatedObject(glass, &kDYYYCommentGlassGlassMaterializingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // 让位判据要求输入栏玻璃已写入 effect，而 effect 是在几何之后才写的（转场协调器那条路
        // 还会推迟到转场里）。这里补算一次，主面板才不会一直停在满幅、与输入栏叠成一块台阶。
        DYYYCommentGlassSyncPanelGlassHeight();
    });
}

// 记下并清掉槽位的不透明底色。返回 NO 表示这个槽位不该接管——它本来就没有底色。
static BOOL DYYYCommentGlassClearSlotColor(UIView *slot) {
    if (objc_getAssociatedObject(slot, &kDYYYCommentGlassSlotOriginalColorKey)) {
        if (DYYYCommentGlassColorIsOpaque(slot.backgroundColor)) slot.backgroundColor = UIColor.clearColor;
        return YES;
    }
    UIColor *current = slot.backgroundColor;
    if (!DYYYCommentGlassColorIsOpaque(current)) return NO;
    objc_setAssociatedObject(slot, &kDYYYCommentGlassSlotOriginalColorKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    slot.backgroundColor = UIColor.clearColor;
    gDYYYCommentGlassEverAttached = YES;
    return YES;
}

static Class DYYYCommentGlassFoldDisplayClass(void) {
    static Class cls = Nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(kDYYYCommentGlassFoldDisplayClass); });
    return cls;
}

static BOOL DYYYCommentGlassIsCoverCandidate(UIView *view, UIView *slot) {
    if (!view || view == slot) return NO;
    if (view.hidden || view.alpha < 0.01) return NO;
    if ([view isKindOfClass:UILabel.class]
        || [view isKindOfClass:UIControl.class]
        || [view isKindOfClass:UIImageView.class]) {
        return NO;
    }
    if (!DYYYCommentGlassColorIsOpaque(view.backgroundColor)) return NO;
    if (fabs(CGRectGetWidth(view.bounds) - CGRectGetWidth(slot.bounds)) > 1.0) return NO;
    return CGRectGetHeight(view.bounds) >= kDYYYCommentGlassCoverMinHeight;
}

static void DYYYCommentGlassClearCoverColor(UIView *view) {
    if (objc_getAssociatedObject(view, &kDYYYCommentGlassCoverOriginalColorKey)) {
        if (DYYYCommentGlassColorIsOpaque(view.backgroundColor)) view.backgroundColor = UIColor.clearColor;
        return;
    }
    if (!DYYYCommentGlassColorIsOpaque(view.backgroundColor)) return;
    objc_setAssociatedObject(view, &kDYYYCommentGlassCoverOriginalColorKey,
                             view.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gDYYYCommentGlassClearedCovers addObject:view];
    view.backgroundColor = UIColor.clearColor;
}

static void DYYYCommentGlassWalkClearCovers(UIView *view, UIView *slot, NSUInteger depth, NSUInteger maxDepth) {
    if (depth > maxDepth) return;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UIVisualEffectView.class]) continue;
        if (DYYYCommentGlassIsCoverCandidate(sub, slot)) DYYYCommentGlassClearCoverColor(sub);
        if ([sub isKindOfClass:UILabel.class] || [sub isKindOfClass:UIImageView.class]) continue;
        DYYYCommentGlassWalkClearCovers(sub, slot, depth + 1, maxDepth);
    }
}

static void DYYYCommentGlassClearCoverLayers(UIView *slot, NSUInteger maxDepth) {
    if (!slot) return;
    DYYYCommentGlassWalkClearCovers(slot, slot, 0, maxDepth);
}

static void DYYYCommentGlassRestoreCoverColor(UIView *view) {
    UIColor *original = objc_getAssociatedObject(view, &kDYYYCommentGlassCoverOriginalColorKey);
    if (!original) return;
    objc_setAssociatedObject(view, &kDYYYCommentGlassCoverOriginalColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.backgroundColor = original;
}

static void DYYYCommentGlassRestoreAllCovers(void) {
    NSArray<UIView *> *views = gDYYYCommentGlassClearedCovers.allObjects;
    [gDYYYCommentGlassClearedCovers removeAllObjects];
    for (UIView *view in views) DYYYCommentGlassRestoreCoverColor(view);
}

// 接管一个槽位：清掉它的不透明底色，在最底层插一层玻璃壳。
// requireOpaque：输入框胶囊必须本来有底色；主面板槽位按类名认定，底色透明也要挂。
// 返回 nil 表示这个槽位不该接管——已被别的插件插了玻璃，或（输入框）没有底色。
static UIView *DYYYCommentGlassAttachGlass(UIView *slot, DYYYCommentGlassGlassShape shape, BOOL requireOpaque)
    API_AVAILABLE(ios(26.0)) {
    UIView *glass = objc_getAssociatedObject(slot, &kDYYYCommentGlassSlotGlassKey);
    // 退让只在尚未接管时判定；接管之后层级由 DYYYLGEnsureBackmost 维持，不能再据此退出。
    if (!glass && [slot.subviews.firstObject isKindOfClass:UIVisualEffectView.class]) return nil;

    BOOL cleared = DYYYCommentGlassClearSlotColor(slot);
    if (requireOpaque && !cleared) return nil;

    if (!glass) {
        glass = DYYYCommentGlassMakeGlassShell(shape);
        objc_setAssociatedObject(slot, &kDYYYCommentGlassSlotGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gDYYYCommentGlassGlassCarriers addObject:glass];
        gDYYYCommentGlassEverAttached = YES;
    }

    // 槽位作为触摸源时包含它的整棵子树，面板列表与输入控件都不必单独枚举。
    ((DYYYGlassFlexView *)glass).flexSourceView = slot;
    DYYYCommentGlassApplyGlassShape((UIVisualEffectView *)glass, slot, shape);
    return glass;
}

static void DYYYCommentGlassDetachGlass(UIView *slot) {
    UIView *glass = objc_getAssociatedObject(slot, &kDYYYCommentGlassSlotGlassKey);
    UIColor *original = objc_getAssociatedObject(slot, &kDYYYCommentGlassSlotOriginalColorKey);
    if (!glass && !original) return;

    [glass removeFromSuperview];
    if (original) slot.backgroundColor = original;

    objc_setAssociatedObject(slot, &kDYYYCommentGlassSlotOriginalColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slot, &kDYYYCommentGlassSlotGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 让位

// 输入栏那块玻璃在不在场、是不是真的在渲染。effect 是几何之后才写的，所以没写入就还不算数。
static UIVisualEffectView *DYYYCommentGlassUsableInputGlass(void) {
    UIVisualEffectView *glass = objc_getAssociatedObject(gDYYYCommentGlassLastInputContainer, &kDYYYCommentGlassSlotGlassKey);
    if (!glass || !glass.effect || !glass.window || !DYYYCommentGlassViewChainVisible(glass)) return nil;
    return glass;
}

// 输入栏那块玻璃是否**确实**盖住了槽位某条横线以下的整段。除了「在渲染」，还要与槽位同属一个
// 评论控制器、同窗口、满宽、底边到槽位底边。任一条不成立就当没盖住。
// gLastInputContainer 是「最近一个」，同源判定挡住另一个面板的残留。
static BOOL DYYYCommentGlassInputGlassCoverage(UIView *slot, CGFloat *coverTop) {
    UIVisualEffectView *glass = DYYYCommentGlassUsableInputGlass();
    if (!glass || !slot.window || glass.window != slot.window) return NO;
    if (!slot.superview || ![gDYYYCommentGlassLastInputContainer isDescendantOfView:slot.superview]) return NO;

    CGRect cover = [glass convertRect:glass.bounds toView:slot];
    CGSize size = slot.bounds.size;
    if (CGRectGetMinX(cover) > 0.5 || CGRectGetMaxX(cover) < size.width - 0.5) return NO;
    if (CGRectGetMaxY(cover) < size.height - 0.5) return NO;

    // 可以是负的：艾特 / 表情面板把输入区顶出主面板之后，容器顶边高过槽位顶边，
    // 等于整个槽位都被盖住。调用方据此把主面板玻璃整块收起来。
    *coverTop = CGRectGetMinY(cover);
    return YES;
}

static void DYYYCommentGlassSyncPanelGlassHeight(void) {
    UIView *slot = gDYYYCommentGlassLastPanelSlot;
    UIVisualEffectView *glass = objc_getAssociatedObject(slot, &kDYYYCommentGlassSlotGlassKey);
    if (!glass || !DYYYCommentGlassCommentGlassEnabled()) return;

    CGFloat coverTop = 0.0;
    BOOL covered = DYYYCommentGlassInputGlassCoverage(slot, &coverTop);
    // 输入区盖到了槽位顶边之上（艾特 / 表情面板那种形态）：整块收起来。用 hidden 而不是把高度
    // 压成 0——零尺寸的 UIGlassEffect 建不出材质层，之后再撑大也补不回来
    // （见 docs/share-panel-liquid-glass.md 的 beta4 一节）。
    BOOL entirelyCovered = covered && coverTop <= 0.5;
    if (glass.hidden != entirelyCovered) glass.hidden = entirelyCovered;
    if (entirelyCovered) return;

    CGRect target = slot.bounds;
    if (covered) target.size.height = coverTop;
    if (!CGRectEqualToRect(glass.frame, target)) glass.frame = target;
}

#pragma mark - 折叠提示条

static const NSUInteger kDYYYCommentGlassFoldWalkDepth = 3;

static BOOL DYYYCommentGlassFoldRowActive(UIView *fold) {
    if (!DYYYCommentGlassViewIsVisible(fold)) return NO;
    // 底色被我们清过之后就只剩记忆可认，两者取其一。
    return DYYYCommentGlassColorIsOpaque(fold.backgroundColor)
        || objc_getAssociatedObject(fold, &kDYYYCommentGlassCoverOriginalColorKey) != nil;
}

static void DYYYCommentGlassUnmaskFoldSibling(UIView *view) {
    NSNumber *original = objc_getAssociatedObject(view, &kDYYYCommentGlassFoldMaskedHiddenKey);
    if (!original) return;
    objc_setAssociatedObject(view, &kDYYYCommentGlassFoldMaskedHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gDYYYCommentGlassFoldMaskedViews removeObject:view];
    view.hidden = original.boolValue;
}

static void DYYYCommentGlassRestoreAllFoldMasks(void) {
    NSArray<UIView *> *views = gDYYYCommentGlassFoldMaskedViews.allObjects;
    for (UIView *view in views) DYYYCommentGlassUnmaskFoldSibling(view);
    [gDYYYCommentGlassFoldMaskedViews removeAllObjects];
}

// 收敛一条折叠提示条：亮着就清底色 + 藏被它完整罩住的可见兄弟，灭了就原样放回去。
// 「完整罩住」而不是「相交」——头像在左、点赞与不喜欢在右、昵称在上、正文比它宽，都不会命中。
static void DYYYCommentGlassSyncFoldRow(UIView *fold) {
    UIView *parent = fold.superview;
    if (!parent) return;

    if (!DYYYCommentGlassFoldRowActive(fold)) {

        for (UIView *sibling in parent.subviews) DYYYCommentGlassUnmaskFoldSibling(sibling);
        return;
    }

    DYYYCommentGlassClearCoverColor(fold);
    CGRect covered = fold.frame;
    for (UIView *sibling in parent.subviews) {
        if (sibling == fold) continue;
        if (objc_getAssociatedObject(sibling, &kDYYYCommentGlassFoldMaskedHiddenKey)) continue;
        if (sibling.hidden || !CGRectContainsRect(covered, sibling.frame)) continue;
        objc_setAssociatedObject(sibling, &kDYYYCommentGlassFoldMaskedHiddenKey, @(sibling.hidden),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gDYYYCommentGlassFoldMaskedViews addObject:sibling];
        sibling.hidden = YES;
    }
}

static void DYYYCommentGlassSyncFoldRowsIn(UIView *view, Class foldClass, NSUInteger depth) {
    if (depth > kDYYYCommentGlassFoldWalkDepth) return;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:foldClass]) {
            DYYYCommentGlassSyncFoldRow(sub);
            continue;
        }
        if ([sub isKindOfClass:UILabel.class] || [sub isKindOfClass:UIImageView.class]) continue;
        DYYYCommentGlassSyncFoldRowsIn(sub, foldClass, depth + 1);
    }
}

#pragma mark - 小表情栏

static void DYYYCommentGlassApplyEmoticonPanel(void) {
    UIView *panel = gDYYYCommentGlassEmoticonPanel;
    if (!panel || !panel.window || !DYYYCommentGlassCommentGlassEnabled()) return;

    UIVisualEffectView *glass = DYYYCommentGlassUsableInputGlass();
    if (!glass) return;

    // 两个窗口都是满屏同原点，各自的窗口坐标可以直接比。
    CGRect panelRect = [panel convertRect:panel.bounds toView:nil];
    CGRect glassRect = [glass convertRect:glass.bounds toView:nil];
    if (!CGRectContainsRect(CGRectInset(glassRect, -0.5, -0.5), panelRect)) return;

    DYYYCommentGlassClearCoverColor(panel);
}

#pragma mark - 同步

static void DYYYCommentGlassSyncInputGlass(UIView *container) API_AVAILABLE(ios(26.0)) {
    if (!DYYYCommentGlassViewIsVisible(container)) return;

    // 顶边露在主面板槽位之上时它是压在视频上的自由边，按原生那条盖条给 8pt 圆角；
    // 贴着主面板玻璃时必须平角——给了圆角会在两角露出原始视频。
    UIView *panel = gDYYYCommentGlassLastPanelSlot;
    BOOL freeTopEdge = panel.window == container.window
        && [container convertPoint:CGPointZero toView:panel].y < -0.5;
    DYYYCommentGlassGlassShape shape = freeTopEdge ? DYYYCommentGlassGlassShapeBarRounded : DYYYCommentGlassGlassShapeBarFlat;

    UIVisualEffectView *barGlass = (UIVisualEffectView *)DYYYCommentGlassAttachGlass(container, shape, NO);
    if (barGlass) {
        gDYYYCommentGlassLastInputContainer = container;
        // 触摸源取容器自己：工具栏按钮、发送键、艾特头像都在它的子树里。
        ((DYYYGlassFlexView *)barGlass).flexSourceView = container;
        if (!CGRectEqualToRect(barGlass.frame, container.bounds)) {
            barGlass.frame = container.bounds;
        }
        DYYYCommentGlassEnsureBackmost(container, barGlass);
        DYYYCommentGlassClearCoverLayers(container, kDYYYCommentGlassInputCoverWalkDepth);
    }

    UIView *field = DYYYCommentGlassInputFieldSlot(container);
    if (!field) return;

    // 输入框不用 UIGlassContainerEffect：嵌套会被合并成同一形状。
    UIVisualEffectView *glass = (UIVisualEffectView *)DYYYCommentGlassAttachGlass(field, DYYYCommentGlassGlassShapeField, YES);
    if (!glass) return;
    if (!CGRectEqualToRect(glass.frame, field.bounds)) glass.frame = field.bounds;
    DYYYCommentGlassEnsureBackmost(field, glass);
}

static void DYYYCommentGlassMaterializeSlotGlass(UIView *slot, UIViewController *controller) API_AVAILABLE(ios(26.0)) {
    if (!slot) return;
    UIVisualEffectView *glass = objc_getAssociatedObject(slot, &kDYYYCommentGlassSlotGlassKey);
    if (glass) DYYYCommentGlassMaterializeGlass(glass, controller);
}

static void DYYYCommentGlassCommentGlassSync(UIViewController *controller) API_AVAILABLE(ios(26.0)) {
    BOOL enabled = DYYYCommentGlassCommentGlassEnabled();
    if (!enabled && !gDYYYCommentGlassEverAttached) return;

    UIView *panel = DYYYCommentGlassPanelSlot(controller);
    if (!panel) return;

    UIView *inputContainer = DYYYCommentGlassInputContainer(controller);

    if (!enabled) {
        // 还原一次即收敛：槽位记忆清空后，后续布局只剩几次空查找。
        // 玻璃可能正处在「整块被盖住」的隐藏态，DYYYLGDetachGlass 直接把它摘掉，不必先复位。
        DYYYCommentGlassDetachGlass(panel);
        DYYYCommentGlassDetachGlass(inputContainer);
        DYYYCommentGlassDetachGlass(DYYYCommentGlassInputFieldSlot(inputContainer));
        DYYYCommentGlassRestoreAllCovers();
        DYYYCommentGlassRestoreAllFoldMasks();
        return;
    }

    DYYYCommentGlassObserveGlassStyle(panel);
    UIUserInterfaceStyle style = DYYYCommentGlassGlassStyleForView(panel);

    // 本函数可能落在抖音的布局或键盘动画里，隐式动画会让玻璃几何拖在内容后面。
    // materialize 在几何就位后单独执行，不受这个 CATransaction 影响。
    UIVisualEffectView *panelGlass = nil;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    panelGlass = (UIVisualEffectView *)DYYYCommentGlassAttachGlass(panel, DYYYCommentGlassGlassShapeTopRounded, NO);
    if (panelGlass) {
        gDYYYCommentGlassLastPanelSlot = panel;
        gDYYYCommentGlassLastController = controller;

        DYYYCommentGlassEnsureBackmost(panel, panelGlass);
        DYYYCommentGlassClearCoverLayers(panel, kDYYYCommentGlassPanelCoverWalkDepth);

        // 先摆输入栏，再按它实际盖住的那一段给主面板玻璃定高。
        DYYYCommentGlassSyncInputGlass(inputContainer);
        DYYYCommentGlassSyncPanelGlassHeight();
    }

    [CATransaction commit];

    // 几何就位后统一更新已存在的材质，再让新玻璃从 nil → effect materialize。
    if (panelGlass) {
        DYYYCommentGlassApplyGlassStyle(style, YES);
        DYYYCommentGlassMaterializeGlass(panelGlass, controller);
        if (DYYYCommentGlassViewIsVisible(inputContainer)) {
            DYYYCommentGlassMaterializeSlotGlass(inputContainer, controller);
            DYYYCommentGlassMaterializeSlotGlass(DYYYCommentGlassInputFieldSlot(inputContainer), controller);
        }
        DYYYCommentGlassApplyEmoticonPanel();
    }
}

#pragma mark - Hook

// DYYYLGCommentBottomBar.xm 也在这两个方法上挂了一层（底栏抑制），两处分属两个功能、各有各的开关，
// 本文件这一层还整体受 iOS 26 可用性约束。多层 %hook 会正常串联，两条同时生效。
%group DYYYCommentGlassCommentGlassHooks

%hook AWECommentContainerViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (@available(iOS 26.0, *)) DYYYCommentGlassCommentGlassSync(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DYYYCommentGlassCommentGlassSync(self);
}

%end

%hook UIView

- (void)setBackgroundColor:(UIColor *)color {
    if ((objc_getAssociatedObject(self, &kDYYYCommentGlassCoverOriginalColorKey)
         || objc_getAssociatedObject(self, &kDYYYCommentGlassSlotOriginalColorKey))
        && DYYYCommentGlassColorIsOpaque(color)) {
        %orig(UIColor.clearColor);
        return;
    }
    %orig;
}

%end

%end

// 小表情栏随键盘来去，且不在评论控制器的视图树里——遍历找不到它，只能按类名挂钩。
// 玻璃可能比它后到，所以 DYYYLGCommentGlassSync 末尾也补一次（弱引用记住这一块）。
%group DYYYCommentGlassCommentEmoticonHook

%hook AWECommentMiniEmoticonPanelView

- (void)layoutSubviews {
    %orig;
    gDYYYCommentGlassEmoticonPanel = self;
    if (@available(iOS 26.0, *)) {
        DYYYCommentGlassApplyEmoticonPanel();

        if (!DYYYCommentGlassUsableInputGlass() && gDYYYCommentGlassLastController) DYYYCommentGlassCommentGlassSync(gDYYYCommentGlassLastController);
    }
}

%end

%end

// 折叠提示条的收敛必须在布局落定之后算（判据是矩形包含），而折叠这件事本身就会把 Cell 从
// 86 压到 58、**必然触发列表重新布局**——触发条件与要修的现象是同一件事，不存在错过。
// 复用、滚动、缩放全屏半屏走的也是这一条；收敛幂等，来回切自愈。
%group DYYYCommentGlassCommentFoldHook

%hook AWEListKitMagicCollectionView

- (void)layoutSubviews {
    %orig;
    if (!DYYYCommentGlassCommentGlassEnabled()) return;
    Class foldClass = DYYYCommentGlassFoldDisplayClass();
    if (!foldClass) return;
    DYYYCommentGlassSyncFoldRowsIn(self, foldClass, 0);
}

%end

%end

%group DYYYCommentGlassCommentSearchPanelHook

%hook AWECommentSearchViewController

- (id)obtainPanelColor {
    // 判据只问「输入区玻璃此刻在不在屏」，**不问自己在不在那棵树里**：这几个取色点是懒加载
    // getter，第一次调用时 view 还没挂进输入容器，用层级判定会在冷启动首次原样返回白色，
    // 正是要修的那个洞。艾特面板只为评论输入而生，输入区玻璃亮着时它就是被我们垫着的那块。
    return DYYYCommentGlassCommentGlassEnabled() && DYYYCommentGlassUsableInputGlass() ? UIColor.clearColor : %orig;
}

%end

%end

%group DYYYCommentGlassCommentRenderOptimizeHook

%hook AWECommentABTestSettings

+ (BOOL)enableCommentRenderingOptimize:(id)context {
    if (DYYYCommentGlassCommentGlassEnabled()) {
        return NO;
    }
    return %orig;
}

%end

%end

#pragma mark - 通知栏液体玻璃（通透）

// 移植自 DYKiller，MIT 许可见 LICENSE。

static const NSTimeInterval kDYYYNotificationGlassNotiGlassAnimation = 0.25;
static const CGFloat kDYYYNotificationGlassNotiNativeCorner = 12.0;
static NSString *const kDYYYNotificationGlassNotiHintPrefix = @"私信了你";

static char kDYYYNotificationGlassSlotColorKey;
static char kDYYYNotificationGlassSlotGlassKey;
static char kDYYYNotificationGlassSlotMarkedKey;
static char kDYYYNotificationGlassGlassClearKey;
static char kDYYYNotificationGlassGlassStyleKey;
static char kDYYYNotificationGlassGlassMaterializingKey;
static char kDYYYNotificationGlassCornerRadiusKey;
static char kDYYYNotificationGlassCornerConfigKey;
static char kDYYYNotificationGlassActionConfigKey;
static char kDYYYNotificationGlassActionColorKey;
static char kDYYYNotificationGlassActionTitleKey;
static char kDYYYNotificationGlassActionAttrTitleKey;
static char kDYYYNotificationGlassActionForegroundKey;
static char kDYYYNotificationGlassActionClearKey;
static char kDYYYNotificationGlassBadgeColorKey;
static char kDYYYNotificationGlassBadgeGlassKey;
static char kDYYYNotificationGlassHintHiddenKey;

static NSHashTable *gDYYYNotificationGlassGlassCarriers;
static NSHashTable<AWEInnerNotificationContainerView *> *gDYYYNotificationGlassContainers;
static NSHashTable<AWEInnerPushCommonView *> *gDYYYNotificationGlassCommonViews;
static BOOL gDYYYNotificationGlassEverAttached = NO;
// 我们自己写 textColor 会再次触发 setTextColor: 钩子，用它挡住重入。
static BOOL gDYYYNotificationGlassInkReapplying = NO;
static __weak UIWindowScene *gDYYYNotificationGlassObservedScene = nil;
static UIUserInterfaceStyle gDYYYNotificationGlassGlassStyle = UIUserInterfaceStyleUnspecified;

#pragma mark - 开关与材质

static BOOL DYYYNotificationGlassNotiEnabled(void) {
    return [DYYYUtils liquidGlassAvailable] && [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableNotificationTransparency"];
}

static BOOL DYYYNotificationGlassNotiUsesClear(void) { return YES; }

// 未写过键时保持胶囊（100），与 beta7 观感一致。
static CGFloat DYYYNotificationGlassNotiCornerProgress(void) { return 1.0; }

static BOOL DYYYNotificationGlassNotiColorOpaque(UIColor *color) {
    return color && CGColorGetAlpha(color.CGColor) >= 0.99;
}

static UIUserInterfaceStyle DYYYNotificationGlassNotiStyleForView(UIView *view) {
    UIUserInterfaceStyle style = view.window.windowScene.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = gDYYYNotificationGlassGlassStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = view.traitCollection.userInterfaceStyle;
    return style == UIUserInterfaceStyleUnspecified ? UIUserInterfaceStyleLight : style;
}

static UIUserInterfaceStyle DYYYNotificationGlassNotiOverrideStyle(BOOL clear, UIUserInterfaceStyle style) {
    return clear ? UIUserInterfaceStyleUnspecified : style;
}

static UIColor *DYYYNotificationGlassNotiTint(BOOL clear, UIUserInterfaceStyle style) {
    return clear ? [DYYYUtils liquidGlassTintForStyle:style] : nil;
}

static UIGlassEffect *DYYYNotificationGlassNotiMakeEffect(BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    UIGlassEffect *effect = [UIGlassEffect effectWithStyle:
        clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
    effect.tintColor = DYYYNotificationGlassNotiTint(clear, style);
    effect.interactive = YES;
    return effect;
}

static void DYYYNotificationGlassNotiRunAnimation(BOOL animated, void (^changes)(void)) {
    if (!changes) return;
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        [UIView performWithoutAnimation:changes];
        return;
    }
    [UIView animateWithDuration:kDYYYNotificationGlassNotiGlassAnimation
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState
                              | UIViewAnimationOptionAllowUserInteraction
                              | UIViewAnimationOptionCurveEaseInOut
                     animations:changes
                     completion:nil];
}

static void DYYYNotificationGlassNotiInstallEffect(UIVisualEffectView *glass, BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    glass.effect = DYYYNotificationGlassNotiMakeEffect(clear, style);
    objc_setAssociatedObject(glass, &kDYYYNotificationGlassGlassClearKey, @(clear), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(glass, &kDYYYNotificationGlassGlassStyleKey, @(style), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL DYYYNotificationGlassNotiGlassNeedsUpdate(UIVisualEffectView *glass, BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    if (glass.overrideUserInterfaceStyle != DYYYNotificationGlassNotiOverrideStyle(clear, style)) return YES;
    UIGlassEffect *current = [glass.effect isKindOfClass:UIGlassEffect.class]
        ? (UIGlassEffect *)glass.effect : nil;
    if (!current) return glass.effect != nil;
    NSNumber *installedClear = objc_getAssociatedObject(glass, &kDYYYNotificationGlassGlassClearKey);
    NSNumber *installedStyle = objc_getAssociatedObject(glass, &kDYYYNotificationGlassGlassStyleKey);
    if (!installedClear || installedClear.boolValue != clear) return YES;
    if (!installedStyle || installedStyle.integerValue != style) return YES;
    if (!current.interactive) return YES;
    UIColor *want = DYYYNotificationGlassNotiTint(clear, style);
    return !((current.tintColor == want) || [current.tintColor isEqual:want]);
}

static UIView *DYYYNotificationGlassNotiSlot(AWEInnerNotificationContainerView *container);

static void DYYYNotificationGlassNotiApplyStyle(UIUserInterfaceStyle style, BOOL animated) API_AVAILABLE(ios(26.0)) {
    if (style == UIUserInterfaceStyleUnspecified) return;
    gDYYYNotificationGlassGlassStyle = style;
    // 场景 trait 回调在关开关后仍会来，这里不能再往回写。
    if (!DYYYNotificationGlassNotiEnabled()) return;
    BOOL clear = DYYYNotificationGlassNotiUsesClear();

    // 深浅切换时横幅可能正在场，文字要跟着材质一起换。
    for (AWEInnerPushCommonView *common in gDYYYNotificationGlassCommonViews.allObjects) {
        [DYYYUtils applyLiquidGlassInkText:common clear:clear style:style];
    }
    for (AWEInnerNotificationContainerView *container in gDYYYNotificationGlassContainers.allObjects) {
        [DYYYUtils applyLiquidGlassInkText:DYYYNotificationGlassNotiSlot(container) clear:clear style:style];
    }

    BOOL needs = NO;
    for (UIVisualEffectView *glass in gDYYYNotificationGlassGlassCarriers.allObjects) {
        if (DYYYNotificationGlassNotiGlassNeedsUpdate(glass, clear, style)) {
            needs = YES;
            break;
        }
    }
    if (!needs) return;

    DYYYNotificationGlassNotiRunAnimation(animated, ^{
        for (UIVisualEffectView *glass in gDYYYNotificationGlassGlassCarriers.allObjects) {
            glass.overrideUserInterfaceStyle = DYYYNotificationGlassNotiOverrideStyle(clear, style);
            if (!glass.effect || !DYYYNotificationGlassNotiGlassNeedsUpdate(glass, clear, style)) continue;
            DYYYNotificationGlassNotiInstallEffect(glass, clear, style);
        }
    });
}

static void DYYYNotificationGlassNotiObserveStyle(UIView *host) API_AVAILABLE(ios(26.0)) {
    UIWindowScene *scene = host.window.windowScene;
    if (!scene || scene == gDYYYNotificationGlassObservedScene) return;
    gDYYYNotificationGlassObservedScene = scene;
    [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                       withHandler:^(UIWindowScene *changed, __unused UITraitCollection *previous) {
        DYYYNotificationGlassNotiApplyStyle(changed.traitCollection.userInterfaceStyle, YES);
    }];
}

static UIVisualEffectView *DYYYNotificationGlassNotiMakeShell(void) API_AVAILABLE(ios(26.0)) {
    DYYYGlassFlexView *glass = [[DYYYGlassFlexView alloc] initWithEffect:nil];
    glass.userInteractionEnabled = NO;
    glass.alpha = 1.0;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    DYYYGlassBackdropView *background = [[DYYYGlassBackdropView alloc] initWithSettingsPrefix:@"DYYYNotificationGlass"];
    background.frame = glass.contentView.bounds;
    background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    background.userInteractionEnabled = NO;
    glass.contentView.clipsToBounds = YES;
    [glass.contentView addSubview:background];
    return glass;
}

static BOOL DYYYNotificationGlassNotiRectUsable(CGRect rect) {
    return CGRectGetWidth(rect) >= 8.0 && CGRectGetHeight(rect) >= 8.0;
}

static void DYYYNotificationGlassNotiEnsureBackmost(UIView *slot, UIView *glass) {
    if (slot.subviews.firstObject == glass) return;
    [slot insertSubview:glass atIndex:0];
}

// 0 尺寸写入 UIGlassEffect 不会建材质层，之后只改 frame 补不回来。
static void DYYYNotificationGlassNotiPlaceGlass(UIVisualEffectView *glass, UIView *slot) {
    if (!glass || !slot) return;
    BOOL wasEmpty = !DYYYNotificationGlassNotiRectUsable(glass.bounds);
    if (!CGRectEqualToRect(glass.frame, slot.bounds)) glass.frame = slot.bounds;
    DYYYNotificationGlassNotiEnsureBackmost(slot, glass);
    if (wasEmpty && DYYYNotificationGlassNotiRectUsable(glass.bounds) && glass.effect) {
        glass.effect = nil;
        objc_setAssociatedObject(glass, &kDYYYNotificationGlassGlassMaterializingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DYYYNotificationGlassNotiMaterialize(UIVisualEffectView *glass) API_AVAILABLE(ios(26.0)) {
    if (!glass || !DYYYNotificationGlassNotiRectUsable(glass.bounds) || glass.effect
        || [objc_getAssociatedObject(glass, &kDYYYNotificationGlassGlassMaterializingKey) boolValue]) {
        return;
    }
    objc_setAssociatedObject(glass, &kDYYYNotificationGlassGlassMaterializingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DYYYNotificationGlassNotiRunAnimation(YES, ^{
        if (!glass.superview || !DYYYNotificationGlassNotiEnabled()) {
            objc_setAssociatedObject(glass, &kDYYYNotificationGlassGlassMaterializingKey,
                                     nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
        UIUserInterfaceStyle style = gDYYYNotificationGlassGlassStyle;
        if (style == UIUserInterfaceStyleUnspecified) style = DYYYNotificationGlassNotiStyleForView(glass);
        BOOL clear = DYYYNotificationGlassNotiUsesClear();
        glass.overrideUserInterfaceStyle = DYYYNotificationGlassNotiOverrideStyle(clear, style);
        DYYYNotificationGlassNotiInstallEffect(glass, clear, style);
        objc_setAssociatedObject(glass, &kDYYYNotificationGlassGlassMaterializingKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

#pragma mark - 圆角

static void DYYYNotificationGlassNotiRememberCorners(UIView *view) {
    if (!view || objc_getAssociatedObject(view, &kDYYYNotificationGlassCornerRadiusKey)) return;
    objc_setAssociatedObject(view, &kDYYYNotificationGlassCornerRadiusKey,
                             @(view.layer.cornerRadius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([view respondsToSelector:@selector(cornerConfiguration)]) {
        objc_setAssociatedObject(view, &kDYYYNotificationGlassCornerConfigKey,
                                 view.cornerConfiguration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static UICornerConfiguration *DYYYNotificationGlassNotiCardCornerConfig(UIView *view) API_AVAILABLE(ios(26.0)) {
    DYYYNotificationGlassNotiRememberCorners(view);
    CGFloat native = kDYYYNotificationGlassNotiNativeCorner;
    NSNumber *remembered = objc_getAssociatedObject(view, &kDYYYNotificationGlassCornerRadiusKey);
    if (remembered && remembered.doubleValue > 0.0) native = remembered.doubleValue;
    CGFloat capsule = MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) * 0.5;
    if (capsule < native) capsule = native;
    CGFloat radius = native + (capsule - native) * DYYYNotificationGlassNotiCornerProgress();
    view.layer.cornerRadius = radius;
    return [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:radius]];
}

static void DYYYNotificationGlassNotiApplyCardShape(UIView *view, UIVisualEffectView *glass) API_AVAILABLE(ios(26.0)) {
    if (!view) return;
    UICornerConfiguration *config = DYYYNotificationGlassNotiCardCornerConfig(view);
    if ([view respondsToSelector:@selector(setCornerConfiguration:)]) {
        view.cornerConfiguration = config;
    }
    if (glass && [glass respondsToSelector:@selector(setCornerConfiguration:)]) {
        glass.cornerConfiguration = config;
        glass.contentView.cornerConfiguration = config;
    }
}

static void DYYYNotificationGlassNotiApplyCapsule(UIView *view) API_AVAILABLE(ios(26.0)) {
    if (!view) return;
    DYYYNotificationGlassNotiRememberCorners(view);
    if ([view respondsToSelector:@selector(setCornerConfiguration:)]) {
        view.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
    }
    CGFloat height = CGRectGetHeight(view.bounds);
    if (height >= 1.0) view.layer.cornerRadius = height * 0.5;
}

static void DYYYNotificationGlassNotiRestoreCorners(UIView *view) {
    NSNumber *radius = objc_getAssociatedObject(view, &kDYYYNotificationGlassCornerRadiusKey);
    if (!view || !radius) return;
    if ([view respondsToSelector:@selector(setCornerConfiguration:)]) {
        view.cornerConfiguration = objc_getAssociatedObject(view, &kDYYYNotificationGlassCornerConfigKey);
    }
    view.layer.cornerRadius = radius.doubleValue;
    objc_setAssociatedObject(view, &kDYYYNotificationGlassCornerRadiusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDYYYNotificationGlassCornerConfigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 查找

static AWEInnerNotificationContainerView *DYYYNotificationGlassNotiContainerOf(UIView *view) {
    while (view) {
        if ([view isKindOfClass:%c(AWEInnerNotificationContainerView)]) {
            return (AWEInnerNotificationContainerView *)view;
        }
        view = view.superview;
    }
    return nil;
}

static UIView *DYYYNotificationGlassNotiSlot(AWEInnerNotificationContainerView *container) {
    UIView *marked = objc_getAssociatedObject(container, &kDYYYNotificationGlassSlotMarkedKey);
    if (marked.superview == container) return marked;

    if ([container respondsToSelector:@selector(containerView)]) {
        UIView *candidate = container.containerView;
        if (candidate.superview == container
            && (DYYYNotificationGlassNotiColorOpaque(candidate.backgroundColor)
                || objc_getAssociatedObject(candidate, &kDYYYNotificationGlassSlotColorKey))) {
            return candidate;
        }
    }
    for (UIView *child in container.subviews) {
        if (child.hidden) continue;
        if (DYYYNotificationGlassNotiColorOpaque(child.backgroundColor)
            || objc_getAssociatedObject(child, &kDYYYNotificationGlassSlotColorKey)) {
            return child;
        }
    }
    return nil;
}

static AWEInnerPushCommonView *DYYYNotificationGlassNotiCommonIn(UIView *view, NSUInteger depth) {
    if (!view || depth > 6) return nil;
    if ([view isKindOfClass:%c(AWEInnerPushCommonView)]) return (AWEInnerPushCommonView *)view;
    for (UIView *child in view.subviews) {
        AWEInnerPushCommonView *found = DYYYNotificationGlassNotiCommonIn(child, depth + 1);
        if (found) return found;
    }
    return nil;
}

#pragma mark - 卡片

static BOOL DYYYNotificationGlassNotiClearSlot(UIView *slot) {
    UIColor *current = slot.backgroundColor;
    if (DYYYNotificationGlassNotiColorOpaque(current)) {
        if (!objc_getAssociatedObject(slot, &kDYYYNotificationGlassSlotColorKey)) {
            objc_setAssociatedObject(slot, &kDYYYNotificationGlassSlotColorKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        slot.backgroundColor = UIColor.clearColor;
        gDYYYNotificationGlassEverAttached = YES;
        return YES;
    }
    return objc_getAssociatedObject(slot, &kDYYYNotificationGlassSlotColorKey) != nil;
}

static UIVisualEffectView *DYYYNotificationGlassNotiAttachCard(AWEInnerNotificationContainerView *container,
                                            UIView *slot)
    API_AVAILABLE(ios(26.0)) {
    if (!DYYYNotificationGlassNotiClearSlot(slot)) return nil;

    UIVisualEffectView *glass = objc_getAssociatedObject(slot, &kDYYYNotificationGlassSlotGlassKey);
    if (!glass) {
        UIView *first = slot.subviews.firstObject;
        if ([first isKindOfClass:UIVisualEffectView.class]
            && first != objc_getAssociatedObject(slot, &kDYYYNotificationGlassSlotGlassKey)) {
            return nil;
        }
        glass = DYYYNotificationGlassNotiMakeShell();
        ((DYYYGlassFlexView *)glass).flexSourceView = container;
        objc_setAssociatedObject(slot, &kDYYYNotificationGlassSlotGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(container, &kDYYYNotificationGlassSlotMarkedKey, slot, OBJC_ASSOCIATION_ASSIGN);
        [gDYYYNotificationGlassGlassCarriers addObject:glass];
        gDYYYNotificationGlassEverAttached = YES;
    }

    DYYYNotificationGlassNotiApplyCardShape(container, glass);
    DYYYNotificationGlassNotiApplyCardShape(slot, glass);
    DYYYNotificationGlassNotiPlaceGlass(glass, slot);
    return glass;
}

static void DYYYNotificationGlassNotiDetachCard(AWEInnerNotificationContainerView *container) {
    UIView *slot = DYYYNotificationGlassNotiSlot(container);
    if (!slot) return;
    [DYYYUtils restoreLiquidGlassInkText:slot];
    UIView *glass = objc_getAssociatedObject(slot, &kDYYYNotificationGlassSlotGlassKey);
    [gDYYYNotificationGlassGlassCarriers removeObject:glass];
    [glass removeFromSuperview];
    UIColor *original = objc_getAssociatedObject(slot, &kDYYYNotificationGlassSlotColorKey);
    if (original) slot.backgroundColor = original;
    DYYYNotificationGlassNotiRestoreCorners(slot);
    DYYYNotificationGlassNotiRestoreCorners(container);
    objc_setAssociatedObject(slot, &kDYYYNotificationGlassSlotColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slot, &kDYYYNotificationGlassSlotGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(container, &kDYYYNotificationGlassSlotMarkedKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

#pragma mark - 回复键

static BOOL DYYYNotificationGlassNotiActionHasGlass(UIButton *button) {
    return button.configuration && objc_getAssociatedObject(button, &kDYYYNotificationGlassActionClearKey);
}

static void DYYYNotificationGlassNotiRememberAction(UIButton *button) {
    if (!button || DYYYNotificationGlassNotiActionHasGlass(button)) return;
    if (button.configuration && !objc_getAssociatedObject(button, &kDYYYNotificationGlassActionConfigKey)) {
        objc_setAssociatedObject(button, &kDYYYNotificationGlassActionConfigKey,
                                 button.configuration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (button.backgroundColor) {
        objc_setAssociatedObject(button, &kDYYYNotificationGlassActionColorKey,
                                 button.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSAttributedString *attributed = button.currentAttributedTitle;
    if (attributed.length) {
        objc_setAssociatedObject(button, &kDYYYNotificationGlassActionAttrTitleKey,
                                 attributed, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    NSString *title = button.currentTitle.length ? button.currentTitle : attributed.string;
    if (title.length) {
        objc_setAssociatedObject(button, &kDYYYNotificationGlassActionTitleKey,
                                 title, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    UIColor *foreground = nil;
    if (attributed.length) {
        foreground = [attributed attribute:NSForegroundColorAttributeName
                                   atIndex:0
                            effectiveRange:NULL];
    }
    if (!foreground) foreground = [button titleColorForState:UIControlStateNormal];
    if (foreground) {
        objc_setAssociatedObject(button, &kDYYYNotificationGlassActionForegroundKey,
                                 foreground, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static UIButtonConfiguration *DYYYNotificationGlassNotiMakeActionConfig(BOOL clear) API_AVAILABLE(ios(26.0)) {
    UIButtonConfiguration *config = nil;
    if (clear && [UIButtonConfiguration respondsToSelector:@selector(clearGlassButtonConfiguration)]) {
        config = [UIButtonConfiguration clearGlassButtonConfiguration];
    } else if ([UIButtonConfiguration respondsToSelector:@selector(glassButtonConfiguration)]) {
        config = [UIButtonConfiguration glassButtonConfiguration];
    }
    if (!config) return nil;
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    return config;
}

static void DYYYNotificationGlassNotiWriteActionTitle(UIButton *button, UIButtonConfiguration *config) {
    NSAttributedString *attributed = objc_getAssociatedObject(button, &kDYYYNotificationGlassActionAttrTitleKey);
    NSString *title = objc_getAssociatedObject(button, &kDYYYNotificationGlassActionTitleKey);
    UIColor *foreground = objc_getAssociatedObject(button, &kDYYYNotificationGlassActionForegroundKey);
    if (attributed.length) {
        config.attributedTitle = attributed;
    } else if (title.length) {
        config.title = title;
    }
    if (foreground) config.baseForegroundColor = foreground;
}

static void DYYYNotificationGlassNotiRestoreAction(UIButton *button) {
    if (!button || !objc_getAssociatedObject(button, &kDYYYNotificationGlassActionForegroundKey)) return;
    UIButtonConfiguration *original = objc_getAssociatedObject(button, &kDYYYNotificationGlassActionConfigKey);
    button.configuration = original;
    UIColor *color = objc_getAssociatedObject(button, &kDYYYNotificationGlassActionColorKey);
    if (color) button.backgroundColor = color;
    if (!original) {
        NSAttributedString *attributed = objc_getAssociatedObject(button, &kDYYYNotificationGlassActionAttrTitleKey);
        NSString *title = objc_getAssociatedObject(button, &kDYYYNotificationGlassActionTitleKey);
        UIColor *foreground = objc_getAssociatedObject(button, &kDYYYNotificationGlassActionForegroundKey);
        if (attributed) {
            [button setAttributedTitle:attributed forState:UIControlStateNormal];
        } else if (title) {
            [button setTitle:title forState:UIControlStateNormal];
        }
        if (foreground) [button setTitleColor:foreground forState:UIControlStateNormal];
    }
    objc_setAssociatedObject(button, &kDYYYNotificationGlassActionConfigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kDYYYNotificationGlassActionColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kDYYYNotificationGlassActionTitleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kDYYYNotificationGlassActionAttrTitleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kDYYYNotificationGlassActionForegroundKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kDYYYNotificationGlassActionClearKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DYYYNotificationGlassNotiApplyAction(UIButton *button) API_AVAILABLE(ios(26.0)) {
    if (!button || button.hidden || button.alpha < 0.01) {
        if (button) DYYYNotificationGlassNotiRestoreAction(button);
        return;
    }

    DYYYNotificationGlassNotiRememberAction(button);
    if (objc_getAssociatedObject(button, &kDYYYNotificationGlassActionColorKey)) {
        button.backgroundColor = UIColor.clearColor;
    }

    BOOL clear = DYYYNotificationGlassNotiUsesClear();
    NSNumber *installed = objc_getAssociatedObject(button, &kDYYYNotificationGlassActionClearKey);
    if (DYYYNotificationGlassNotiActionHasGlass(button) && installed.boolValue == clear) return;

    UIButtonConfiguration *config = DYYYNotificationGlassNotiMakeActionConfig(clear);
    if (!config) return;
    DYYYNotificationGlassNotiWriteActionTitle(button, config);
    button.configuration = config;
    objc_setAssociatedObject(button, &kDYYYNotificationGlassActionClearKey, @(clear), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gDYYYNotificationGlassEverAttached = YES;
}

#pragma mark - 角标

static void DYYYNotificationGlassNotiRestoreBadge(UIView *badge) {
    if (!badge) return;
    UIView *glass = objc_getAssociatedObject(badge, &kDYYYNotificationGlassBadgeGlassKey);
    [gDYYYNotificationGlassGlassCarriers removeObject:glass];
    [glass removeFromSuperview];
    UIColor *original = objc_getAssociatedObject(badge, &kDYYYNotificationGlassBadgeColorKey);
    if (original) badge.backgroundColor = original;
    DYYYNotificationGlassNotiRestoreCorners(badge);
    objc_setAssociatedObject(badge, &kDYYYNotificationGlassBadgeColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(badge, &kDYYYNotificationGlassBadgeGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DYYYNotificationGlassNotiApplyBadge(UIView *badge) API_AVAILABLE(ios(26.0)) {
    if (!badge || badge.hidden || badge.alpha < 0.01) {
        if (badge) DYYYNotificationGlassNotiRestoreBadge(badge);
        return;
    }

    UIColor *current = badge.backgroundColor;
    if (DYYYNotificationGlassNotiColorOpaque(current)) {
        if (!objc_getAssociatedObject(badge, &kDYYYNotificationGlassBadgeColorKey)) {
            objc_setAssociatedObject(badge, &kDYYYNotificationGlassBadgeColorKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        badge.backgroundColor = UIColor.clearColor;
    } else if (!objc_getAssociatedObject(badge, &kDYYYNotificationGlassBadgeColorKey)) {
        return;
    }

    UIVisualEffectView *glass = objc_getAssociatedObject(badge, &kDYYYNotificationGlassBadgeGlassKey);
    if (!glass) {
        glass = DYYYNotificationGlassNotiMakeShell();
        glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
        glass.contentView.cornerConfiguration = glass.cornerConfiguration;
        ((DYYYGlassFlexView *)glass).flexSourceView = badge;
        objc_setAssociatedObject(badge, &kDYYYNotificationGlassBadgeGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gDYYYNotificationGlassGlassCarriers addObject:glass];
        gDYYYNotificationGlassEverAttached = YES;
    }
    DYYYNotificationGlassNotiApplyCapsule(badge);
    DYYYNotificationGlassNotiPlaceGlass(glass, badge);
    DYYYNotificationGlassNotiMaterialize(glass);
}

#pragma mark - 「私信了你」

static BOOL DYYYNotificationGlassNotiIsHintText(NSString *text) {
    if (text.length < kDYYYNotificationGlassNotiHintPrefix.length) return NO;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![trimmed hasPrefix:kDYYYNotificationGlassNotiHintPrefix]) return NO;
    NSString *rest = [trimmed substringFromIndex:kDYYYNotificationGlassNotiHintPrefix.length];
    static NSCharacterSet *junk;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        junk = [NSCharacterSet characterSetWithCharactersInString:@":： "];
    });
    return [rest stringByTrimmingCharactersInSet:junk].length == 0;
}

static void DYYYNotificationGlassNotiWalkLabels(UIView *view, NSUInteger depth, void (^block)(UILabel *label)) {
    if (!view || depth > 8 || !block) return;
    if ([view isKindOfClass:UILabel.class]) block((UILabel *)view);
    for (UIView *child in view.subviews) DYYYNotificationGlassNotiWalkLabels(child, depth + 1, block);
}

static void DYYYNotificationGlassNotiRestoreHint(AWEInnerPushCommonView *common) {
    UIView *root = ([common respondsToSelector:@selector(middleContentTextStackView)]
                    && common.middleContentTextStackView)
        ? common.middleContentTextStackView : common;
    DYYYNotificationGlassNotiWalkLabels(root, 0, ^(UILabel *label) {
        NSNumber *hidden = objc_getAssociatedObject(label, &kDYYYNotificationGlassHintHiddenKey);
        if (!hidden) return;
        label.hidden = hidden.boolValue;
        objc_setAssociatedObject(label, &kDYYYNotificationGlassHintHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

static AWEInnerPushCommonView *DYYYNotificationGlassNotiCommonOf(UIView *view) {
    while (view) {
        if ([view isKindOfClass:%c(AWEInnerPushCommonView)]) return (AWEInnerPushCommonView *)view;
        view = view.superview;
    }
    return nil;
}

static void DYYYNotificationGlassNotiHideHintLabel(UILabel *label) {
    if (!label) return;
    if (!objc_getAssociatedObject(label, &kDYYYNotificationGlassHintHiddenKey)) {
        objc_setAssociatedObject(label, &kDYYYNotificationGlassHintHiddenKey,
                                 @(label.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!label.hidden) label.hidden = YES;
    gDYYYNotificationGlassEverAttached = YES;
}

#pragma mark - 迟到的文字色

static void DYYYNotificationGlassNotiReapplyInk(UILabel *label) {
    if (gDYYYNotificationGlassInkReapplying) return;
    if (![label.window isKindOfClass:%c(AWEInnerNotificationWindow)]
        && gDYYYNotificationGlassContainers.count == 0 && gDYYYNotificationGlassCommonViews.count == 0) {
        return;
    }
    if (!DYYYNotificationGlassNotiEnabled()) return;

    for (UIView *node = label; node; node = node.superview) {
        // 按钮标题由 UIButtonConfiguration 管，写 textColor 会被配置刷掉，两边打架。
        if ([node isKindOfClass:UIControl.class]) return;
        if (![node isKindOfClass:%c(AWEInnerNotificationContainerView)]) continue;
        gDYYYNotificationGlassInkReapplying = YES;
        [DYYYUtils applyLiquidGlassInkText:label clear:DYYYNotificationGlassNotiUsesClear() style:DYYYNotificationGlassNotiStyleForView(label)];
        gDYYYNotificationGlassInkReapplying = NO;
        return;
    }
}

static void DYYYNotificationGlassNotiApplyHint(AWEInnerPushCommonView *common) {
    UIView *root = ([common respondsToSelector:@selector(middleContentTextStackView)]
                    && common.middleContentTextStackView)
        ? common.middleContentTextStackView : common;
    DYYYNotificationGlassNotiWalkLabels(root, 0, ^(UILabel *label) {
        NSString *text = label.text.length ? label.text : label.attributedText.string;
        BOOL hint = DYYYNotificationGlassNotiIsHintText(text);
        NSNumber *marked = objc_getAssociatedObject(label, &kDYYYNotificationGlassHintHiddenKey);
        if (hint) {
            DYYYNotificationGlassNotiHideHintLabel(label);
        } else if (marked) {
            label.hidden = marked.boolValue;
            objc_setAssociatedObject(label, &kDYYYNotificationGlassHintHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    });
}

#pragma mark - 同步

static void DYYYNotificationGlassNotiRestoreCommon(AWEInnerPushCommonView *common) {
    if ([common respondsToSelector:@selector(rightActionButton)]) {
        DYYYNotificationGlassNotiRestoreAction(common.rightActionButton);
    }
    if ([common respondsToSelector:@selector(leftExtraIconBackgroundView)]) {
        DYYYNotificationGlassNotiRestoreBadge(common.leftExtraIconBackgroundView);
    }
    DYYYNotificationGlassNotiRestoreHint(common);
    [DYYYUtils restoreLiquidGlassInkText:common];
    [gDYYYNotificationGlassCommonViews removeObject:common];
}

static void DYYYNotificationGlassNotiRestoreContainer(AWEInnerNotificationContainerView *container) {
    AWEInnerPushCommonView *common = DYYYNotificationGlassNotiCommonIn(container, 0);
    if (common) DYYYNotificationGlassNotiRestoreCommon(common);
    DYYYNotificationGlassNotiDetachCard(container);
    [gDYYYNotificationGlassContainers removeObject:container];
}

static void DYYYNotificationGlassNotiSyncCommon(AWEInnerPushCommonView *common) API_AVAILABLE(ios(26.0)) {
    if (!common) return;
    BOOL enabled = DYYYNotificationGlassNotiEnabled();
    if (!enabled && !gDYYYNotificationGlassEverAttached) return;
    if (!enabled) {
        DYYYNotificationGlassNotiRestoreCommon(common);
        return;
    }

    [gDYYYNotificationGlassCommonViews addObject:common];
    DYYYNotificationGlassNotiApplyHint(common);
    [DYYYUtils applyLiquidGlassInkText:common clear:DYYYNotificationGlassNotiUsesClear() style:DYYYNotificationGlassNotiStyleForView(common)];
    if ([common respondsToSelector:@selector(rightActionButton)]) {
        DYYYNotificationGlassNotiApplyAction(common.rightActionButton);
    }
    if ([common respondsToSelector:@selector(leftExtraIconBackgroundView)]) {
        DYYYNotificationGlassNotiApplyBadge(common.leftExtraIconBackgroundView);
    }
}

static void DYYYNotificationGlassNotiSyncContainer(AWEInnerNotificationContainerView *container)
    API_AVAILABLE(ios(26.0)) {
    if (!container) return;
    BOOL enabled = DYYYNotificationGlassNotiEnabled();
    if (!enabled && !gDYYYNotificationGlassEverAttached) return;
    if (!enabled) {
        DYYYNotificationGlassNotiRestoreContainer(container);
        return;
    }

    UIView *slot = DYYYNotificationGlassNotiSlot(container);
    if (!slot) return;

    [gDYYYNotificationGlassContainers addObject:container];
    DYYYNotificationGlassNotiObserveStyle(container);
    UIUserInterfaceStyle style = DYYYNotificationGlassNotiStyleForView(container);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    UIVisualEffectView *card = DYYYNotificationGlassNotiAttachCard(container, slot);
    DYYYNotificationGlassNotiSyncCommon(DYYYNotificationGlassNotiCommonIn(container, 0));
    // 从白槽起走一遍：点赞、评论、直播这类不带 AWEInnerPushCommonView 的横幅也覆盖到。
    [DYYYUtils applyLiquidGlassInkText:slot clear:DYYYNotificationGlassNotiUsesClear() style:style];
    [CATransaction commit];

    if (card) {
        DYYYNotificationGlassNotiApplyStyle(style, YES);
        DYYYNotificationGlassNotiMaterialize(card);
    }
}

#pragma mark - Hook

%group DYYYNotificationGlassInnerNotificationGlassHooks

%hook AWEInnerNotificationContainerView

- (void)renderModel:(id)model context:(id)context {
    %orig;
    if (@available(iOS 26.0, *)) DYYYNotificationGlassNotiSyncContainer(self);
}

- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DYYYNotificationGlassNotiSyncContainer(self);
}

- (void)viewDidDisappear:(BOOL)animated reason:(long long)reason {
    %orig;
    if (self.window) return;
    DYYYNotificationGlassNotiRestoreContainer(self);
}

%end

%hook AWEInnerPushCommonView

- (void)updateViewWithRequest:(id)request notificationContent:(id)content viewModel:(id)viewModel {
    %orig;
    if (@available(iOS 26.0, *)) {
        DYYYNotificationGlassNotiSyncCommon(self);
        AWEInnerNotificationContainerView *container = DYYYNotificationGlassNotiContainerOf(self);
        if (container) DYYYNotificationGlassNotiSyncContainer(container);
    }
}

- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DYYYNotificationGlassNotiSyncCommon(self);
}

%end

// 文案在布局之后才写入；只靠 layoutSubviews 会首帧漏藏，拖一下才消失。
%hook UILabel

- (void)setText:(NSString *)text {
    %orig;
    if (DYYYNotificationGlassNotiEnabled() && DYYYNotificationGlassNotiIsHintText(text) && DYYYNotificationGlassNotiCommonOf(self)) {
        DYYYNotificationGlassNotiHideHintLabel(self);
    }
    DYYYNotificationGlassNotiReapplyInk(self);
}

- (void)setAttributedText:(NSAttributedString *)text {
    %orig;
    if (DYYYNotificationGlassNotiEnabled() && DYYYNotificationGlassNotiIsHintText(text.string) && DYYYNotificationGlassNotiCommonOf(self)) {
        DYYYNotificationGlassNotiHideHintLabel(self);
    }
    DYYYNotificationGlassNotiReapplyInk(self);
}

- (void)setTextColor:(UIColor *)color {
    %orig;
    DYYYNotificationGlassNotiReapplyInk(self);
}

- (void)setHidden:(BOOL)hidden {
    if (!hidden && DYYYNotificationGlassNotiEnabled() && objc_getAssociatedObject(self, &kDYYYNotificationGlassHintHiddenKey)) {
        NSString *text = self.text.length ? self.text : self.attributedText.string;
        if (DYYYNotificationGlassNotiIsHintText(text)) {
            %orig(YES);
            return;
        }
    }
    %orig;
}

%end

%end

// 视频全屏和评论态位置控制移植自 DYKiller，MIT 许可见 LICENSE。
#pragma mark - VideoGeometry

static const CGFloat kDYYYFullscreenFullscreenMinAspect = 1.70;
static const long long kDYYYFullscreenAwemeTypeImage = 68;
// 覆盖 @3x 像素对齐带来的亚像素漂移。
static const CGFloat kDYYYFullscreenGeometryTolerance = 0.5;
static NSMapTable<UIView *, NSValue *> *gDYYYFullscreenOriginalMergeFrames;

BOOL DYYYFullscreenVideoFullscreenOn(void) {
    return DYYYGetBool(@"DYYYEnableFullScreen");
}

BOOL DYYYFullscreenPreventCommentMovement(void) {
    return DYYYFullscreenVideoFullscreenOn() || ([DYYYUtils liquidGlassAvailable] && DYYYGetBool(@"DYYYEnableCommentBlur"));
}

#pragma mark - 类缓存

static Class DYYYFullscreenMergeClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"AWEDPlayerViewController_Merge"); });
    return cls;
}

static Class DYYYFullscreenPlayInteractionClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"AWEPlayInteractionViewController"); });
    return cls;
}

#pragma mark - 视频容器的钉位目标

// 拉满整屏只对比例达标的竖屏视频做：图文、横屏、低比例竖屏拉满会 aspect-fill 过裁。
// 它们只需保持容器自然满幅，背景延伸到底栏交给 DYYYFullscreenVideoPageChrome.xm 的 DYYYFullscreenSyncBackdrop。
static BOOL DYYYFullscreenMergeCanCoverScreen(AWEDPlayerViewController_Merge *merge) {
    if (![merge isKindOfClass:DYYYFullscreenMergeClass()]) return NO;

    AWEAwemeModel *model = merge.model;
    if (model.awemeType == kDYYYFullscreenAwemeTypeImage) return NO;
    if (merge.hasInlandscape) return NO;
    if ([merge respondsToSelector:@selector(isInLandscapeFeedStatus)]
        && [merge isInLandscapeFeedStatus]) {
        return NO;
    }

    AWEVideoModel *video = model.video;
    double width = video.width.doubleValue;
    double height = video.height.doubleValue;
    return width <= 0.0
        || height <= 0.0
        || (height / width) >= kDYYYFullscreenFullscreenMinAspect;
}

CGRect DYYYFullscreenVideoContainerTargetFrame(UIView *view) {
    if (!DYYYFullscreenVideoFullscreenOn()) return CGRectNull;

    UIWindow *window = view.window;
    if (window && window.windowLevel != UIWindowLevelNormal) return CGRectNull;

    UIView *parent = view.superview;
    CGFloat width = CGRectGetWidth(parent.bounds);
    CGFloat height = CGRectGetHeight(parent.bounds);
    if (width <= 0.0 || height <= 0.0) return CGRectNull;

    if (DYYYFullscreenMergeCanCoverScreen((AWEDPlayerViewController_Merge *)view.nextResponder)) {
        CGFloat full = [DYYYUtils fullscreenCellHeight:view];
        if (full > height) height = full;
    }
    return CGRectMake(0.0, 0.0, width, height);
}

BOOL DYYYFullscreenRectsClose(CGRect lhs, CGRect rhs) {
    return fabs(CGRectGetMinX(lhs) - CGRectGetMinX(rhs)) <= kDYYYFullscreenGeometryTolerance
        && fabs(CGRectGetMinY(lhs) - CGRectGetMinY(rhs)) <= kDYYYFullscreenGeometryTolerance
        && fabs(CGRectGetWidth(lhs) - CGRectGetWidth(rhs)) <= kDYYYFullscreenGeometryTolerance
        && fabs(CGRectGetHeight(lhs) - CGRectGetHeight(rhs)) <= kDYYYFullscreenGeometryTolerance;
}

static CGRect DYYYFullscreenAdjustFrame(UIView *view, CGRect frame) {
    UIResponder *owner = view.nextResponder;
    if (!owner) return CGRectNull;

    if ([owner isKindOfClass:DYYYFullscreenMergeClass()]) {
        CGRect target = DYYYFullscreenVideoContainerTargetFrame(view);
        if (CGRectIsNull(target) || DYYYFullscreenRectsClose(frame, target)) return CGRectNull;
        [gDYYYFullscreenOriginalMergeFrames setObject:[NSValue valueWithCGRect:frame] forKey:view];
        return target;
    }
    if ([owner isKindOfClass:DYYYFullscreenPlayInteractionClass()]) {
        return DYYYFullscreenFeedHUDAdjustFrame(view, frame);
    }
    return CGRectNull;
}

static void DYYYFullscreenRestoreMergeFrames(void) {
    NSMapTable<UIView *, NSValue *> *originalFrames = [gDYYYFullscreenOriginalMergeFrames copy];
    [gDYYYFullscreenOriginalMergeFrames removeAllObjects];
    for (UIView *view in originalFrames) {
        view.frame = [originalFrames objectForKey:view].CGRectValue;
        [view.superview setNeedsLayout];
    }
}

#pragma mark - 全局 UIView 钩子

#pragma mark - VideoFeedTable

%group DYYYFullscreenVideoFeedTableHooks

static const CGFloat kDYYYFullscreenFeedTolerance = 0.5;
// 表高至少要到容器的这个比例才认作「已排好、只差一个底栏」，排除布局早期的半成品尺寸。
static const CGFloat kDYYYFullscreenFeedMinHeightRatio = 0.5;
// 从 HUD 往上找视频表的最大层数（图文内容多两层容器，取 8 有余量）。
static const NSUInteger kDYYYFullscreenFeedAncestorLimit = 8;

// 撑高前的表高。挂在表上，既是还原依据，也是 HUD 的钉位目标。
static char kDYYYFullscreenFeedOriginalHeightKey;
// 所有撑高过的表（弱引用），供关闭开关时立即还原。多页并存时可能不止一张。
static NSHashTable<UITableView *> *gDYYYFullscreenStretchedTables = nil;

#pragma mark - 命中统计

// 这两个数一起看才有意义：写入时拦截 vs 布局后兜底。首页/朋友页实测比例约 130:6，
// 是「写入时拦截不能砍成事后纠正」的直接依据。
static NSUInteger gDYYYFullscreenHitSetFrame = 0;
static NSUInteger gDYYYFullscreenHitFallback = 0;
// 40.7.0 的旧表写入入口。与新版控制器布局补正分开统计，用于后续判断旧逻辑是否仍有贡献。
static NSUInteger gDYYYFullscreenHitTableSetFrame = 0;
// 控制器布局完成后补正已进入视图树的子表，并分别统计首页与详情入口。
static NSUInteger gDYYYFullscreenHitTableLayout = 0;
struct DYYYFullscreenFeedTableLayoutStats {
    NSUInteger runs;
    NSUInteger adjustments;
};
static DYYYFullscreenFeedTableLayoutStats gDYYYFullscreenFeedTableLayoutStats = {};
static DYYYFullscreenFeedTableLayoutStats gDYYYFullscreenDetailTableLayoutStats = {};

#pragma mark - 目标判定

Class DYYYFullscreenVideoFeedTableClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"AWEFeedDataSafeTableView"); });
    return cls;
}

UIView *DYYYFullscreenFeedTableForView(UIView *view) {
    Class tableCls = DYYYFullscreenVideoFeedTableClass();
    if (!tableCls) return nil;

    UIView *ancestor = view.superview;
    for (NSUInteger i = 0; ancestor && i < kDYYYFullscreenFeedAncestorLimit; i++, ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:tableCls]) return ancestor;
    }
    return nil;
}

NSNumber *DYYYFullscreenVideoFeedTableOriginalHeight(UIView *table) {
    return objc_getAssociatedObject(table, &kDYYYFullscreenFeedOriginalHeightKey);
}

// 该视图所在视频表撑高前的高度，也就是 HUD 的钉位目标；不在撑高作用域内返回 0。
static CGFloat DYYYFullscreenFeedOriginalHeight(UIView *view) {
    if (!DYYYFullscreenVideoFullscreenOn()) return 0.0;
    return DYYYFullscreenVideoFeedTableOriginalHeight(DYYYFullscreenFeedTableForView(view)).doubleValue;
}

#pragma mark - 撑高视频表

// 共享撑高规则同时供表写入与控制器布局入口调用。首页表自己实现 setFrame:，
// 详情表继承基类的写入入口；已达到目标高度的写入直接放行。
static CGRect DYYYFullscreenFeedTableAdjustFrameToHeight(UITableView *table, CGRect frame, CGFloat target) {
    if (!DYYYFullscreenVideoFullscreenOn()) {
        // 原高度交给关闭回调还原，不能在它执行前丢失。
        return CGRectNull;
    }

    CGFloat current = CGRectGetHeight(frame);
    // 容器不比来意的高度更高 → 这张表没被底栏压缩过（搜索页、好友聊天页就是这种），不在作用域内；
    // 高度不到容器一半 → 布局早期的半成品，记下它会把 HUD 钉到错误的位置。
    if (!isfinite(target) || !isfinite(current)
        || target <= 0.0
        || current >= target - kDYYYFullscreenFeedTolerance
        || current < target * kDYYYFullscreenFeedMinHeightRatio) {
        return CGRectNull;
    }

    if (!objc_getAssociatedObject(table, &kDYYYFullscreenFeedOriginalHeightKey)) {
        objc_setAssociatedObject(table, &kDYYYFullscreenFeedOriginalHeightKey, @(current),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gDYYYFullscreenStretchedTables addObject:table];
    }
    frame.size.height = target;
    return frame;
}

CGRect DYYYFullscreenVideoFeedTableAdjustFrame(UITableView *table, CGRect frame) {
    return DYYYFullscreenFeedTableAdjustFrameToHeight(table, frame,
        CGRectGetHeight(table.superview.bounds));
}

// 详情表在建行前可能尚未挂入父视图，此时取已加载控制器根视图的高度。
// 首次写表尺寸之前记录真实原高，供首个 Cell 的 HUD 钉位使用。
BOOL DYYYFullscreenVideoFeedTablePrepareForController(UIViewController *controller, UITableView *table) {
    if (!DYYYFullscreenVideoFullscreenOn() || !NSThread.isMainThread || !table) return NO;
    Class tableClass = DYYYFullscreenVideoFeedTableClass();
    UIView *root = controller.viewIfLoaded;
    if (!tableClass || ![table isKindOfClass:tableClass] || !root) return NO;
    UIWindow *window = table.window ?: root.window;
    if (window && window.windowLevel != UIWindowLevelNormal) return NO;
    if (table.superview && ![table isDescendantOfView:root]) return NO;
    if (!CGAffineTransformIsIdentity(table.transform)) return NO;

    CGFloat target = table.superview
        ? CGRectGetHeight(table.superview.bounds) : CGRectGetHeight(root.bounds);
    CGRect adjusted = DYYYFullscreenFeedTableAdjustFrameToHeight(table, table.frame, target);
    if (CGRectIsNull(adjusted)) return NO;
    table.frame = adjusted;
    return YES;
}

// 在写入时就改成满高：抖音把表高改回原值（如关闭评论区）的那一刻即被顶回去，
// 不必等下一次布局。事后在 layoutSubviews 里改会留下「切一下才恢复」的空窗。
%hook AWEFeedDataSafeTableView

- (void)setFrame:(CGRect)frame {
    CGRect adjusted = DYYYFullscreenVideoFeedTableAdjustFrame(self, frame);
    if (CGRectIsNull(adjusted)) {
        %orig;
        return;
    }
    gDYYYFullscreenHitTableSetFrame++;
    %orig(adjusted);
}

%end

%hook AWEFeedTableView

- (void)setFrame:(CGRect)frame {
    CGRect adjusted = DYYYFullscreenVideoFeedTableAdjustFrame(self, frame);
    if (CGRectIsNull(adjusted)) {
        %orig;
        return;
    }
    gDYYYFullscreenHitTableSetFrame++;
    %orig(adjusted);
}

%end

// 控制器完成原生布局后，子表已进入视图树，可以读取父容器高度。
// 两套控制器共用撑高规则；仅在目标未满足时修改子表 frame。
static void DYYYFullscreenSyncFeedTableLayout(UITableView *table, DYYYFullscreenFeedTableLayoutStats *stats) {
    stats->runs++;
    if (!table) return;

    CGRect adjusted = DYYYFullscreenVideoFeedTableAdjustFrame(table, table.frame);
    if (CGRectIsNull(adjusted)) return;

    table.frame = adjusted;
    gDYYYFullscreenHitTableLayout++;
    stats->adjustments++;
}

%hook AWEFeedTableViewController

- (void)viewDidLayoutSubviews {
    %orig;
    if (!DYYYFullscreenVideoFullscreenOn()) return;
    DYYYFullscreenSyncFeedTableLayout(self.tableView, &gDYYYFullscreenFeedTableLayoutStats);
}

%end

%hook AWEAwemeDetailTableViewController

- (void)viewDidLayoutSubviews {
    %orig;
    if (!DYYYFullscreenVideoFullscreenOn()) return;
    DYYYFullscreenSyncFeedTableLayout(self.tableView, &gDYYYFullscreenDetailTableLayoutStats);
}

%end

#pragma mark - HUD 钉位

CGRect DYYYFullscreenFeedHUDAdjustFrame(UIView *view, CGRect frame) {
    if (!DYYYFullscreenVideoFullscreenOn()) return CGRectNull;

    UIView *table = DYYYFullscreenFeedTableForView(view);
    if (!table) return CGRectNull;

    NSNumber *original = DYYYFullscreenVideoFeedTableOriginalHeight(table);
    if (!original) return CGRectNull;

    // 只拦「被设成撑高后的满高」这一种写入；缩小态（如评论展开）一律放行。
    CGFloat pinned = original.doubleValue;
    if (CGRectGetHeight(frame) <= pinned + kDYYYFullscreenFeedTolerance) return CGRectNull;

    gDYYYFullscreenHitSetFrame++;
    frame.size.height = pinned;
    return frame;
}

%hook AWEPlayInteractionViewController

- (void)viewDidLayoutSubviews {
    %orig;

    // 已经在 HUD 控制器内部，不必再判类型。
    UIView *view = self.viewIfLoaded;
    if (!view) return;

    CGFloat original = DYYYFullscreenFeedOriginalHeight(view);
    if (original <= 0.0) return;

    CGRect frame = view.frame;
    if (fabs(CGRectGetMinY(frame)) <= kDYYYFullscreenFeedTolerance
        && CGRectGetHeight(frame) <= original + kDYYYFullscreenFeedTolerance) {
        return;
    }

    view.frame = CGRectMake(CGRectGetMinX(frame), 0.0, CGRectGetWidth(frame), original);
    gDYYYFullscreenHitFallback++;
}

%end

#pragma mark - 还原

// 关闭开关时立刻把表高还回去，不必等抖音下一次写 frame。
static void DYYYFullscreenVideoFeedTableRestore(void) {
    for (UITableView *table in gDYYYFullscreenStretchedTables.allObjects) {
        NSNumber *original = DYYYFullscreenVideoFeedTableOriginalHeight(table);
        objc_setAssociatedObject(table, &kDYYYFullscreenFeedOriginalHeightKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGRect frame = table.frame;
        frame.size.height = original.doubleValue;
        table.frame = frame;
        [UIView performWithoutAnimation:^{
            [table beginUpdates];
            [table endUpdates];
            [table setNeedsLayout];
            [table layoutIfNeeded];
        }];
    }
    [gDYYYFullscreenStretchedTables removeAllObjects];
}

%end

#pragma mark - VideoDetailTable

static const CGFloat kDYYYFullscreenDetailHeightTolerance = 0.5;
static NSUInteger gDYYYFullscreenDKDetailPrepareRuns;
static NSUInteger gDYYYFullscreenDKDetailPrepareChanges;
struct DYYYFullscreenDetailHeightStats {
    NSUInteger runs;
    NSUInteger changes;
};
static DYYYFullscreenDetailHeightStats gDYYYFullscreenDKDetailFixedStats = {};
static DYYYFullscreenDetailHeightStats gDYYYFullscreenDKDetailIndexStats = {};
static DYYYFullscreenDetailHeightStats gDYYYFullscreenDKDetailRowStats = {};

static void DYYYFullscreenPrepareDetailTable(AWEAwemeDetailTableViewController *controller,
                                 UITableView *table) {
    if (!DYYYFullscreenVideoFullscreenOn()) return;
    gDYYYFullscreenDKDetailPrepareRuns++;
    if (DYYYFullscreenVideoFeedTablePrepareForController(controller, table)) {
        gDYYYFullscreenDKDetailPrepareChanges++;
    }
}

// 仅统一已接管表中的整页行高；原生特殊行、自动尺寸和未就绪尺寸继续使用原返回值。
static double DYYYFullscreenDetailRowHeight(UITableView *table, double nativeHeight,
                                DYYYFullscreenDetailHeightStats *stats) {
    if (!DYYYFullscreenVideoFullscreenOn() || !NSThread.isMainThread) return nativeHeight;
    stats->runs++;
    NSNumber *original = DYYYFullscreenVideoFeedTableOriginalHeight(table);
    CGFloat target = CGRectGetHeight(table.bounds);
    if (!original || !isfinite(nativeHeight) || !isfinite(target)
        || nativeHeight <= 0.0 || target <= original.doubleValue + kDYYYFullscreenDetailHeightTolerance) {
        return nativeHeight;
    }
    if (fabs(nativeHeight - original.doubleValue) > kDYYYFullscreenDetailHeightTolerance
        && fabs(nativeHeight - target) > kDYYYFullscreenDetailHeightTolerance) {
        return nativeHeight;
    }
    if (fabs(nativeHeight - target) > kDYYYFullscreenDetailHeightTolerance) stats->changes++;
    return target;
}

%group DYYYFullscreenVideoDetailTableHooks

%hook AWEAwemeDetailTableViewController

- (void)setupDetailTableView {
    %orig;
    if (DYYYFullscreenVideoFullscreenOn()) DYYYFullscreenPrepareDetailTable(self, self.tableView);
}

- (void)viewWillLayoutSubviews {
    if (DYYYFullscreenVideoFullscreenOn()) DYYYFullscreenPrepareDetailTable(self, self.tableView);
    %orig;
    if (DYYYFullscreenVideoFullscreenOn()) DYYYFullscreenPrepareDetailTable(self, self.tableView);
}

- (double)fixedCellHeight {
    if (!DYYYFullscreenVideoFullscreenOn()) return %orig;
    UITableView *table = self.tableView;
    DYYYFullscreenPrepareDetailTable(self, table);
    double nativeHeight = %orig;
    return DYYYFullscreenDetailRowHeight(table, nativeHeight, &gDYYYFullscreenDKDetailFixedStats);
}

- (double)cellHeightAtIndex:(long long)index {
    if (!DYYYFullscreenVideoFullscreenOn()) return %orig;
    UITableView *table = self.tableView;
    DYYYFullscreenPrepareDetailTable(self, table);
    double nativeHeight = %orig;
    return DYYYFullscreenDetailRowHeight(table, nativeHeight, &gDYYYFullscreenDKDetailIndexStats);
}

- (double)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!DYYYFullscreenVideoFullscreenOn()) return %orig;
    DYYYFullscreenPrepareDetailTable(self, table);
    double nativeHeight = %orig;
    return DYYYFullscreenDetailRowHeight(table, nativeHeight, &gDYYYFullscreenDKDetailRowStats);
}

- (double)contentOffsetYForCellAtIndex:(long long)index {
    if (DYYYFullscreenVideoFullscreenOn()) DYYYFullscreenPrepareDetailTable(self, self.tableView);
    return %orig;
}

- (void)adjustTableViewHeightForTargetIndex:(long long)index {
    if (DYYYFullscreenVideoFullscreenOn()) DYYYFullscreenPrepareDetailTable(self, self.tableView);
    %orig;
    if (DYYYFullscreenVideoFullscreenOn()) DYYYFullscreenPrepareDetailTable(self, self.tableView);
}

%end

%end

#pragma mark - VideoPageChrome

%group DYYYFullscreenVideoPageChromeHooks

static const CGFloat kDYYYFullscreenSignatureTolerance = 0.5;
static NSHashTable<UIView *> *gDYYYFullscreenDKManagedVisualViews;

static Class DYYYFullscreenChromeMergeClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls = NSClassFromString(@"AWEDPlayerViewController_Merge");
    });
    return cls;
}

#pragma mark - 全屏目标判定

static AWEDPlayerViewController_Merge *DYYYFullscreenMergeForView(UIView *view) {
    Class mergeCls = DYYYFullscreenChromeMergeClass();
    if (!mergeCls) return nil;

    UIResponder *responder = view.nextResponder;
    for (NSUInteger i = 0; responder && i < 40; i++) {
        if ([responder isKindOfClass:mergeCls]) {
            return (AWEDPlayerViewController_Merge *)responder;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

// 底部渐变要不要拉伸，取决于这条视频的容器有没有被钉得比自然高度更高——只有详情页那几页
// 会出现这种情况（首页/朋友页靠撑高 feed 表，渐变本来就在满高容器里）。
static BOOL DYYYFullscreenMergeIsStretchedTarget(AWEDPlayerViewController_Merge *merge) {
    if (!merge || !merge.isViewLoaded) return NO;

    UIView *view = merge.view;
    CGRect target = DYYYFullscreenVideoContainerTargetFrame(view);
    if (CGRectIsNull(target) || !view.superview) return NO;
    return CGRectGetHeight(target)
        > CGRectGetHeight(view.superview.bounds) + kDYYYFullscreenSignatureTolerance;
}

#pragma mark - 视频容器重钉

static BOOL DYYYFullscreenPinMergeToTarget(UIViewController *merge) {
    UIView *view = merge.viewIfLoaded;
    if (!view) return NO;

    CGRect target = DYYYFullscreenVideoContainerTargetFrame(view);
    if (CGRectIsNull(target) || DYYYFullscreenRectsClose(view.frame, target)) return NO;

    if (![gDYYYFullscreenOriginalMergeFrames objectForKey:view])
        [gDYYYFullscreenOriginalMergeFrames setObject:[NSValue valueWithCGRect:view.frame] forKey:view];
    view.frame = target;
    return YES;
}

%hook AWEDPlayerViewController_Merge

- (void)willDisplay {
    %orig;
    DYYYFullscreenPinMergeToTarget(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    DYYYFullscreenPinMergeToTarget(self);
}

// 全屏时保留铺满容器所需的背景；评论玻璃在评论控制器处禁止原生缩放。
- (void)videoDidShrink {
    if (!DYYYFullscreenVideoFullscreenOn()) {
        %orig;
        return;
    }

    UIView *gradient = self.gradientBackgroundView;
    if (gradient && gradient.alpha < 1.0) {
        gradient.alpha = 1.0;
    }
}

%end

#pragma mark - 背景延伸至底栏

static char kDYYYFullscreenBackdropAppliedKey;    // 挂内容控制器：是否接管过
static char kDYYYFullscreenCellBackdropKey;       // 挂承载视图：原背景色

// 内容下方那块空区由哪一层兜住，各页不同（好友页是 Cell contentView，搜索页是铺满且不透明的
// CellVC.view）。故动态求：从内容根往上，第一个高度超过它底边的祖先才是会露出来的那层。
static UIView *DYYYFullscreenBackdropCanvas(UIView *anchor) {
    UIView *contentView = [DYYYUtils fullscreenCellContentView:anchor];
    if (!contentView) return nil;

    for (UIView *ancestor = anchor.superview; ancestor; ancestor = ancestor.superview) {
        CGRect rect = [anchor convertRect:anchor.bounds toView:ancestor];
        if (CGRectGetHeight(ancestor.bounds)
            > CGRectGetMaxY(rect) + kDYYYFullscreenSignatureTolerance) {
            return ancestor;
        }
        if (ancestor == contentView) break;
    }
    return nil;
}

// 承载层会随页面/布局变化，按标记回收，不假设它是哪一个。
static void DYYYFullscreenRestoreBackdrop(UIView *anchor, UIView *except) {
    UIView *ancestor = anchor.superview;
    for (NSUInteger i = 0; ancestor && i < 12; i++, ancestor = ancestor.superview) {
        if (ancestor == except) continue;

        id baseline = objc_getAssociatedObject(ancestor, &kDYYYFullscreenCellBackdropKey);
        if (!baseline) continue;

        ancestor.backgroundColor =
            baseline == [NSNull null] ? nil : (UIColor *)baseline;
        objc_setAssociatedObject(
            ancestor,
            &kDYYYFullscreenCellBackdropKey,
            nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }
}

// 其他比例视频：把 playerBackgroundView 的色涂到 anchor 下方会露出来的祖先上。
// owner 记「接管过没有」；color 为 nil 表示本条不需要延伸。图文不走这里——它钉的是
// AWEKnowledgeGradientView 自身高度（见下方），不取样另涂。
static void DYYYFullscreenSyncBackdrop(id owner, UIView *anchor, UIColor *color) {
    BOOL applied = objc_getAssociatedObject(owner, &kDYYYFullscreenBackdropAppliedKey) != nil;
    // 绝大多数内容没有原生背景，这里直接退出，不做任何链式遍历。
    if (!anchor || (!color && !applied)) return;

    UIView *canvas = (color && DYYYFullscreenVideoFullscreenOn()) ? DYYYFullscreenBackdropCanvas(anchor) : nil;

    DYYYFullscreenRestoreBackdrop(anchor, canvas);
    if (!canvas) {
        objc_setAssociatedObject(owner, &kDYYYFullscreenBackdropAppliedKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (!objc_getAssociatedObject(canvas, &kDYYYFullscreenCellBackdropKey)) {
        objc_setAssociatedObject(canvas, &kDYYYFullscreenCellBackdropKey,
                                 canvas.backgroundColor ?: (id)[NSNull null],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (![canvas.backgroundColor isEqual:color]) {
        canvas.backgroundColor = color;
    }
    objc_setAssociatedObject(owner, &kDYYYFullscreenBackdropAppliedKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gDYYYFullscreenDKManagedVisualViews addObject:canvas];
}

// 抖音把横屏智能背景色画在 playerBackgroundView 上；该色在首帧渲染出图后才算出来，
// 因此同步点必须是抖音自己落色的时刻，而不是 setModel:/setFrame: 这类首帧之前的入口。
// 仅当背景层确实挂在视图树上并可见时才算「抖音画了背景」，避免跟随已摘除的残留层。
static UIColor *DYYYFullscreenPlayerBackdropColor(AWEPlayVideoViewController *controller) {
    UIView *backdrop = controller.playerBackgroundView;
    return (backdrop.superview && !backdrop.hidden) ? backdrop.backgroundColor : nil;
}

static Class DYYYFullscreenRichContentContainerClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls = NSClassFromString(@"RichContentContainerViewController");
    });
    return cls;
}

// 图文 cell 内仍嵌着一套 Merge/PlayVideo（alpha=0）。它与 RichContent 共用祖先链；
// 若让嵌套播放器继续 DYYYFullscreenSyncBackdrop，会用黑底或 restore 把图文渐变末色清掉，
// 表现就是「偶发」底栏与图文背景不统一（beta5 导出：同页 contentView 有时透明有时已涂色）。
static BOOL DYYYFullscreenIsUnderRichContent(UIViewController *controller) {
    Class richCls = DYYYFullscreenRichContentContainerClass();
    if (!richCls) return NO;
    for (NSUInteger i = 0; controller && i < 12; i++) {
        if ([controller isKindOfClass:richCls]) return YES;
        controller = controller.parentViewController;
    }
    return NO;
}

%hook AWEPlayVideoViewController

- (void)setPlayerBackgroundView:(UIView *)backgroundView {
    %orig;
    if (DYYYFullscreenIsUnderRichContent(self)) return;
    DYYYFullscreenSyncBackdrop(self, self.viewIfLoaded, DYYYFullscreenPlayerBackdropColor(self));
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (DYYYFullscreenIsUnderRichContent(self)) return;
    DYYYFullscreenSyncBackdrop(self, self.viewIfLoaded, DYYYFullscreenPlayerBackdropColor(self));
}

%end

#pragma mark - 图文

static char kDYYYFullscreenRichClipKey;
static char kDYYYFullscreenKnowledgeTransformKey;
static char kDYYYFullscreenRichGradientTransformKey;
static char kDYYYFullscreenVideoGradientTransformKey;
static char kDYYYFullscreenLiveChromeTransformKey;

// center/bounds/anchorPoint 不受 transform 影响，可据此还原应用 transform 前的几何。
static CGRect DYYYFullscreenIdentityFrameInSuperview(UIView *view) {
    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat height = CGRectGetHeight(view.bounds);
    CGFloat minX = view.center.x - width * view.layer.anchorPoint.x;
    CGFloat minY = view.center.y - height * view.layer.anchorPoint.y;
    return CGRectMake(minX, minY, width, height);
}

// 只接管原本没有 transform 的目标；首次修改时保存原值，恢复时不影响其他功能的状态。
static BOOL DYYYFullscreenApplyVerticalStretch(
    UIView *view,
    const void *baselineKey,
    CGFloat top,
    CGFloat targetBottom
) {
    if (!view) return NO;

    CGFloat height = CGRectGetHeight(view.bounds);
    if (height <= 0.0 || targetBottom <= top + height + kDYYYFullscreenSignatureTolerance) {
        return NO;
    }

    CGFloat scaleY = (targetBottom - top) / height;
    if (scaleY <= 1.0 + 1e-4) return NO;

    NSValue *baseline = objc_getAssociatedObject(view, baselineKey);
    if (!baseline) {
        if (!CGAffineTransformIsIdentity(view.transform)) return NO;
        baseline = [NSValue valueWithCGAffineTransform:view.transform];
        objc_setAssociatedObject(view, baselineKey, baseline,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CGAffineTransform transform = CGAffineTransformMake(
        1.0, 0.0, 0.0, scaleY, 0.0, (height / 2.0) * (scaleY - 1.0));
    if (!CGAffineTransformEqualToTransform(view.transform, transform)) {
        view.transform = transform;
    }
    return YES;
}

// 纵向平移，用于把被撑高顶下去的 chrome 抬回原位。与上面的拉伸同一套接管规则：
// 只接管原本没有 transform 的目标（抖音自己在动它就让开），首次接管时存下原值。
static BOOL DYYYFullscreenApplyVerticalLift(UIView *view, const void *baselineKey, CGFloat lift) {
    if (!view || lift <= kDYYYFullscreenSignatureTolerance) return NO;

    NSValue *baseline = objc_getAssociatedObject(view, baselineKey);
    if (!baseline) {
        if (!CGAffineTransformIsIdentity(view.transform)) return NO;
        baseline = [NSValue valueWithCGAffineTransform:view.transform];
        objc_setAssociatedObject(view, baselineKey, baseline,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CGAffineTransform transform = CGAffineTransformMakeTranslation(0.0, -lift);
    if (!CGAffineTransformEqualToTransform(view.transform, transform)) {
        view.transform = transform;
    }
    return YES;
}

static void DYYYFullscreenRestoreTransformBaseline(UIView *view, const void *baselineKey) {
    NSValue *baseline = objc_getAssociatedObject(view, baselineKey);
    if (!baseline) return;

    view.transform = baseline.CGAffineTransformValue;
    objc_setAssociatedObject(view, baselineKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 图文向 Cell 底部溢出时，只解除真实阻挡它的裁剪层；原本不裁剪的视图不接管。
static void DYYYFullscreenAllowRichOverflow(UIView *view) {
    if (!view) return;

    if (!objc_getAssociatedObject(view, &kDYYYFullscreenRichClipKey)) {
        if (!view.clipsToBounds) return;
        objc_setAssociatedObject(view, &kDYYYFullscreenRichClipKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gDYYYFullscreenDKManagedVisualViews addObject:view];
    }
    if (view.clipsToBounds) view.clipsToBounds = NO;
}

static void DYYYFullscreenRestoreRichOverflow(UIView *view) {
    if (!objc_getAssociatedObject(view, &kDYYYFullscreenRichClipKey)) return;

    view.clipsToBounds = YES;
    objc_setAssociatedObject(view, &kDYYYFullscreenRichClipKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static Class DYYYFullscreenKnowledgeGradientClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls = NSClassFromString(@"AWEKnowledgeGradientView");
    });
    return cls;
}

static void DYYYFullscreenSyncRichClips(UIView *view) {
    if (!view) return;

    CGFloat full = DYYYFullscreenVideoFullscreenOn() ? [DYYYUtils fullscreenCellHeight:view] : 0.0;
    if (full > CGRectGetHeight(view.bounds) + kDYYYFullscreenSignatureTolerance) {
        DYYYFullscreenAllowRichOverflow(view);
        return;
    }

    DYYYFullscreenRestoreRichOverflow(view);
}

static void DYYYFullscreenSyncKnowledgeGradientStretch(UIView *gradient) {
    if (!gradient) return;

    CGFloat height = CGRectGetHeight(gradient.bounds);
    CGFloat full = DYYYFullscreenVideoFullscreenOn() ? [DYYYUtils fullscreenCellHeight:gradient] : 0.0;

    if (height > 0.0 && full > height + kDYYYFullscreenSignatureTolerance
        && DYYYFullscreenApplyVerticalStretch(
            gradient,
            &kDYYYFullscreenKnowledgeTransformKey,
            0.0,
            full
        )) {
        [gDYYYFullscreenDKManagedVisualViews addObject:gradient];
        return;
    }

    DYYYFullscreenRestoreTransformBaseline(gradient, &kDYYYFullscreenKnowledgeTransformKey);
}

%hook RichContentContainerViewController

- (void)updateShrinkState:(BOOL)shrink insets:(UIEdgeInsets)insets animated:(BOOL)animated {
    // 抑制时一律不调 %orig：class-dump 把 insets 折叠成 (struct)，真实类型只能按参数名推断，
    // 不重新编组它就不依赖这个推断；放行走裸 %orig，Logos 原样透传实参。
    if (shrink && (DYYYFullscreenPreventCommentMovement())) return;
    %orig;
}

- (void)updateShrinkState:(BOOL)shrink
                   insets:(UIEdgeInsets)insets
                 animated:(BOOL)animated
        animationDuration:(double)duration {
    if (shrink && (DYYYFullscreenPreventCommentMovement())) return;
    %orig;
}

- (void)viewDidLayoutSubviews {
    %orig;
    DYYYFullscreenSyncRichClips(self.viewIfLoaded);
}

%end

%hook AWEKnowledgeGradientView

- (void)layoutSubviews {
    %orig;
    DYYYFullscreenSyncKnowledgeGradientStretch(self);
}

%end

#pragma mark - 评论态 HUD 顶部遮罩

// 评论展开时抖音会在 HUD 顶部现场插入一条「安全区高 × 满宽」的纯黑遮罩，
// 它是「视频缩小」态的产物，被强钉满屏的视频顶上去就成了黑边。
static char kDYYYFullscreenStatusBarCoverHiddenKey;

// 遮罩的高度是**窗口**安全区高，尺子也必须取窗口的：HUD 根视图在 table cell 里，它自己的安全区
// 随 cell 在滚动视图中的位置变化，滑到不覆盖窗口顶部安全区的位置就是 0，签名会整条失配。
CGFloat DYYYFullscreenHUDStatusBarCoverHeight(UIView *hudView) {
    UIWindow *window = hudView.window;
    return window ? window.safeAreaInsets.top : hudView.safeAreaInsets.top;
}

static UIView *DYYYFullscreenFindHUDStatusBarCover(UIView *hudView) {
    CGFloat safeTop = DYYYFullscreenHUDStatusBarCoverHeight(hudView);
    CGFloat width = CGRectGetWidth(hudView.bounds);
    if (safeTop <= 1.0 || width <= 0.0) return nil;

    for (UIView *view in hudView.subviews) {
        if (object_getClass(view) != [UIView class]) continue;
        if (!view.opaque || view.hidden) continue;

        CGRect frame = view.frame;
        if (fabs(CGRectGetMinX(frame)) > 1.0
            || fabs(CGRectGetMinY(frame)) > 1.0
            || fabs(CGRectGetWidth(frame) - width) > 1.0
            || fabs(CGRectGetHeight(frame) - safeTop) > 2.0) {
            continue;
        }
        if ([DYYYUtils fullscreenColorIsOpaqueBlack:view.backgroundColor]) return view;
    }
    return nil;
}

// 仅全屏铺满时移除这条遮罩；评论玻璃保留页面原有的留白与遮罩。
void DYYYFullscreenHUDStatusBarCoverSync(UIViewController *interaction) {
    UIView *hudView = interaction.viewIfLoaded;
    if (!hudView) return;

    if (DYYYFullscreenVideoFullscreenOn()) {
        UIView *cover = DYYYFullscreenFindHUDStatusBarCover(hudView);
        if (cover) {
            cover.hidden = YES;
            objc_setAssociatedObject(
                cover,
                &kDYYYFullscreenStatusBarCoverHiddenKey,
                @YES,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }
        return;
    }

    for (UIView *view in hudView.subviews) {
        if (!objc_getAssociatedObject(view, &kDYYYFullscreenStatusBarCoverHiddenKey)) continue;
        view.hidden = NO;
        objc_setAssociatedObject(
            view,
            &kDYYYFullscreenStatusBarCoverHiddenKey,
            nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }
}

// DYYYFullscreenVideoFeedTable.xm 也在同一个方法上挂了一层（HUD 高度的布局后补正），两处分属两个功能、
// 各自跟着自己的模块走，串联生效，互不依赖。
%hook AWEPlayInteractionViewController

- (void)viewDidLayoutSubviews {
    %orig;
    DYYYFullscreenHUDStatusBarCoverSync(self);
}

%end

#pragma mark - 底部压暗渐变

%hook AWEGradientView

- (void)layoutSubviews {
    %orig;

    // ① 视频：Merge 被钉得比父视图高时，容器内非贴底的压暗跟着撑满（旧逻辑，保留）。
    AWEDPlayerViewController_Merge *merge = DYYYFullscreenMergeForView(self);
    if (DYYYFullscreenMergeIsStretchedTarget(merge)) {
        UIView *container = self.superview;
        CGFloat height = CGRectGetHeight(self.bounds);
        if (container && height > 0.0) {
            CGFloat top = self.center.y - height / 2.0;
            CGFloat containerHeight = CGRectGetHeight(container.bounds);
            if (top > 1.0 && top + height < containerHeight - 1.0) {
                if (DYYYFullscreenApplyVerticalStretch(
                    self,
                    &kDYYYFullscreenVideoGradientTransformKey,
                    top,
                    containerHeight
                )) {
                    [gDYYYFullscreenDKManagedVisualViews addObject:self];
                    return;
                }
            }
        }
    }

    DYYYFullscreenRestoreTransformBaseline(self, &kDYYYFullscreenVideoGradientTransformKey);
}

%end

static Class DYYYFullscreenGradientClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls = NSClassFromString(@"AWEGradientView");
    });
    return cls;
}

// 图文贴底压暗的结构签名：全宽、贴父底、顶边不在父顶。尺寸随设备和内容布局动态变化。
static BOOL DYYYFullscreenIsRichBottomGradient(UIView *view) {
    Class gradientCls = DYYYFullscreenGradientClass();
    UIView *parent = view.superview;
    if (!gradientCls || !parent || view.hidden || view.alpha <= 0.01
        || ![view isKindOfClass:gradientCls]) {
        return NO;
    }

    CGFloat parentWidth = CGRectGetWidth(parent.bounds);
    CGFloat parentHeight = CGRectGetHeight(parent.bounds);
    if (parentWidth <= 0.0 || parentHeight <= 0.0) return NO;

    CGRect frame = DYYYFullscreenIdentityFrameInSuperview(view);
    CGFloat tolerance = MAX(kDYYYFullscreenSignatureTolerance, 1.0);
    return fabs(CGRectGetMinX(frame)) <= tolerance
        && fabs(CGRectGetWidth(frame) - parentWidth) <= tolerance
        && fabs(CGRectGetMaxY(frame) - parentHeight) <= tolerance
        && CGRectGetMinY(frame) > tolerance;
}

static void DYYYFullscreenCollectRichBottomGradients(UIView *root, NSMutableArray<UIView *> *output) {
    for (UIView *subview in root.subviews) {
        if (subview.hidden || subview.alpha <= 0.01) continue;
        if (DYYYFullscreenIsRichBottomGradient(subview)) {
            [output addObject:subview];
            continue;
        }
        DYYYFullscreenCollectRichBottomGradients(subview, output);
    }
}

static NSArray<UIView *> *DYYYFullscreenRichBottomGradients(
    AWEStoryContainerCollectionView *collection
) {
    NSMutableArray<UIView *> *gradients = [NSMutableArray array];
    for (UICollectionViewCell *cell in collection.visibleCells) {
        DYYYFullscreenCollectRichBottomGradients(cell, gradients);
    }
    return gradients;
}

static BOOL DYYYFullscreenViewIsInCollection(UIView *view, UIView *collection) {
    return view == collection || [view isDescendantOfView:collection];
}

static void DYYYFullscreenRestoreUnusedRichCollectionState(
    AWEStoryContainerCollectionView *collection,
    NSSet<UIView *> *activeGradients,
    NSSet<UIView *> *activeClipViews
) {
    for (UIView *view in gDYYYFullscreenDKManagedVisualViews.allObjects) {
        if (!DYYYFullscreenViewIsInCollection(view, collection)) continue;

        if (objc_getAssociatedObject(view, &kDYYYFullscreenRichGradientTransformKey)
            && ![activeGradients containsObject:view]) {
            DYYYFullscreenRestoreTransformBaseline(view, &kDYYYFullscreenRichGradientTransformKey);
        }
        if (objc_getAssociatedObject(view, &kDYYYFullscreenRichClipKey)
            && ![activeClipViews containsObject:view]) {
            DYYYFullscreenRestoreRichOverflow(view);
        }
    }
}

static void DYYYFullscreenSyncRichCollection(AWEStoryContainerCollectionView *collection) {
    CGFloat contentHeight = CGRectGetHeight(collection.bounds);
    CGFloat fullHeight = DYYYFullscreenVideoFullscreenOn() ? [DYYYUtils fullscreenCellHeight:collection] : 0.0;
    if (contentHeight <= 0.0
        || fullHeight <= contentHeight + kDYYYFullscreenSignatureTolerance) {
        DYYYFullscreenRestoreUnusedRichCollectionState(collection, [NSSet set], [NSSet set]);
        return;
    }

    NSMutableSet<UIView *> *activeGradients = [NSMutableSet set];
    NSMutableSet<UIView *> *activeClipViews = [NSMutableSet set];
    for (UIView *gradient in DYYYFullscreenRichBottomGradients(collection)) {
        UIView *contentView = [DYYYUtils fullscreenCellContentView:gradient];
        UIView *parent = gradient.superview;
        if (!contentView || !parent || ![gradient isDescendantOfView:collection]) continue;

        CGRect identityFrame = DYYYFullscreenIdentityFrameInSuperview(gradient);
        CGFloat top = [parent convertPoint:identityFrame.origin toView:contentView].y;
        if (!DYYYFullscreenApplyVerticalStretch(
            gradient,
            &kDYYYFullscreenRichGradientTransformKey,
            top,
            fullHeight
        )) {
            continue;
        }

        [gDYYYFullscreenDKManagedVisualViews addObject:gradient];
        [activeGradients addObject:gradient];

        for (UIView *ancestor = parent; ancestor; ancestor = ancestor.superview) {
            if (ancestor.clipsToBounds
                || objc_getAssociatedObject(ancestor, &kDYYYFullscreenRichClipKey)) {
                DYYYFullscreenAllowRichOverflow(ancestor);
                [activeClipViews addObject:ancestor];
            }
            if (ancestor == collection) break;
        }
    }

    DYYYFullscreenRestoreUnusedRichCollectionState(collection, activeGradients, activeClipViews);
}

%hook AWEStoryContainerCollectionView

- (void)layoutSubviews {
    %orig;
    DYYYFullscreenSyncRichCollection(self);
}

%end

#pragma mark - 直播预览 HUD

static CGFloat DYYYFullscreenLiveChromeLift(UIView *container) {
    NSNumber *original = DYYYFullscreenVideoFeedTableOriginalHeight(DYYYFullscreenFeedTableForView(container));
    UIView *contentView = [DYYYUtils fullscreenCellContentView:container];
    if (!original || !contentView) return 0.0;

    CGFloat full = CGRectGetHeight(contentView.bounds);
    if (CGRectGetHeight(container.bounds) < full - kDYYYFullscreenSignatureTolerance) return 0.0;
    return full - original.doubleValue;
}

// 目标底边在**容器**坐标里的位置。取 identity frame，免得自己叠上去的位移污染判定。
static CGFloat DYYYFullscreenLiveChromeBottom(UIView *view, UIView *container) {
    CGRect frame = DYYYFullscreenIdentityFrameInSuperview(view);
    return [view.superview convertPoint:CGPointMake(0.0, CGRectGetMaxY(frame))
                                 toView:container].y;
}

// 暗水印贴底但留了 8pt 边距，只在它确实落进撑出来的那一段里才抬——它与 chrome 不在同一槽位，
// 位置由 IESLive 直接排，不跟着控制层走。
static BOOL DYYYFullscreenLiveWatermarkNeedsLift(UIImageView *watermark, UIView *container, CGFloat lift) {
    if (!watermark || watermark.hidden || lift <= kDYYYFullscreenSignatureTolerance) return NO;
    return DYYYFullscreenLiveChromeBottom(watermark, container)
        > CGRectGetHeight(container.bounds) - lift + kDYYYFullscreenSignatureTolerance;
}

// 该抬就抬、不该抬就还原，两个槽位共用。幂等：值没变不写。
static void DYYYFullscreenApplyLiveLift(UIView *target, CGFloat lift, BOOL wanted) {
    if (!target) return;

    if (wanted && DYYYFullscreenApplyVerticalLift(target, &kDYYYFullscreenLiveChromeTransformKey, lift)) {
        [gDYYYFullscreenDKManagedVisualViews addObject:target];
        return;
    }
    DYYYFullscreenRestoreTransformBaseline(target, &kDYYYFullscreenLiveChromeTransformKey);
}

// 位移为 0（表本就满高，或容器还没跟着 cell 长高）时两个槽位都走还原分支，没接管过就是空转。
// 目标是两个具名属性、没有遍历可省，所以不再挂「接管过没有」的标记来提前退出。
static void DYYYFullscreenSyncLiveChrome(AWELivePreStream4LayerContainerView *container) {

    CGFloat lift = DYYYFullscreenVideoFullscreenOn() ? DYYYFullscreenLiveChromeLift(container) : 0.0;
    UIImageView *watermark = container.bottomDarkWatermark;

    DYYYFullscreenApplyLiveLift(container.controlContainer, lift, lift > kDYYYFullscreenSignatureTolerance);
    DYYYFullscreenApplyLiveLift(watermark, lift, DYYYFullscreenLiveWatermarkNeedsLift(watermark, container, lift));
}

// 抬升目标逐个给出 identity frame 与实际底边：identity 是抖音排的位置，实际底边是抬完的结果。

%hook AWELivePreStream4LayerContainerView

- (void)layoutSubviews {
    %orig;
    DYYYFullscreenSyncLiveChrome(self);
}

%end

static void DYYYFullscreenPageChromeVisualRestore(void) {
    for (UIView *view in gDYYYFullscreenDKManagedVisualViews.allObjects) {
        id color = objc_getAssociatedObject(view, &kDYYYFullscreenCellBackdropKey);
        if (color) {
            view.backgroundColor = color == NSNull.null ? nil : color;
            objc_setAssociatedObject(view, &kDYYYFullscreenCellBackdropKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        DYYYFullscreenRestoreTransformBaseline(view, &kDYYYFullscreenKnowledgeTransformKey);
        DYYYFullscreenRestoreTransformBaseline(view, &kDYYYFullscreenRichGradientTransformKey);
        DYYYFullscreenRestoreTransformBaseline(view, &kDYYYFullscreenVideoGradientTransformKey);
        DYYYFullscreenRestoreTransformBaseline(view, &kDYYYFullscreenLiveChromeTransformKey);
        DYYYFullscreenRestoreRichOverflow(view);
    }
    [gDYYYFullscreenDKManagedVisualViews removeAllObjects];
}

%end

#pragma mark - 进度条原生垫层颜色

static NSHashTable *gDYYYFullscreenProgressColorOwners;

%group DYYYFullscreenProgressFeedColorHooks
%hook AWEDProgressFeedContainer

- (void)setProgressUnderViewColor {
    %orig;
    if (!DYYYFullscreenVideoFullscreenOn()) return;
    // 40.7.0 原生取色会再次写黑底，从取色入口只清理这块具名垫层。
    UIView *underView = self.progressSliderUnderView;
    if (!underView) return;
    underView.backgroundColor = UIColor.clearColor;
    [gDYYYFullscreenProgressColorOwners addObject:self];
}

%end
%end

%group DYYYFullscreenLegacyProgressColorHooks
%hook AWEPlayInteractionProgressController

- (void)setProgressUnderViewColor {
    %orig;
    if (!DYYYFullscreenVideoFullscreenOn()) return;
    UIView *underView = self.progressSliderUnderView;
    if (!underView) return;
    underView.backgroundColor = UIColor.clearColor;
    [gDYYYFullscreenProgressColorOwners addObject:self];
}

%end
%end

#pragma mark - CommentFullBackdrop

%group DYYYFullscreenCommentFullBackdropHooks

static char kDYYYFullscreenBackdropPageKey;   // 全屏容器 → 垫回去的那一页的 view
static char kDYYYFullscreenPanelColorKey;     // 全屏容器 view → 原底色（NSNull 表示原本就是 nil）

// 最近一次补播的现场读数。

// 在屏的全屏容器。用弱引用而不是计数：交互式返回中途取消会再发一次 viewDidAppear:
// 而没有配对的 viewWillDisappear:，计数会一去不回。
static __weak UIViewController *gDYYYFullscreenFullPanel = nil;
// 底色拦截的总闸，与 kDYYYFullscreenBackdropPageKey 同生共死。用纯 BOOL 而不是读 gDYYYFullscreenFullPanel：
// 后者是 __weak，取值要走 objc_loadWeakRetained，全局钩子里付不起这个开销。
static BOOL gDYYYFullscreenBackdropAttached = NO;

BOOL DYYYFullscreenCommentFullPanelOnScreen(void) {
    return gDYYYFullscreenFullPanel != nil;
}

// 导航栈里本页下面那一页；本页不在栈里或已是栈底时返回 nil。
static UIViewController *DYYYFullscreenPageBelowPanel(UIViewController *panel) {
    NSArray<UIViewController *> *stack = panel.navigationController.viewControllers;
    NSUInteger index = [stack indexOfObject:panel];
    return (index == NSNotFound || index == 0) ? nil : stack[index - 1];
}

static void DYYYFullscreenAttachBackdrop(UIViewController *panel) {
    if (!DYYYFullscreenPreventCommentMovement() || objc_getAssociatedObject(panel, &kDYYYFullscreenBackdropPageKey)) return;

    UIView *panelView = panel.viewIfLoaded;
    UIView *wrapper = panelView.superview;   // 承载本页的 wrapper
    UIView *stage = wrapper.superview;       // 导航的转场舞台
    UIView *page = DYYYFullscreenPageBelowPanel(panel).viewIfLoaded;
    // 只接管「被导航摘下来的」那一页：还在栈里、view 还活着、但已不在任何层级。
    if (!stage || !page || page.superview) return;

    [stage insertSubview:page belowSubview:wrapper];
    objc_setAssociatedObject(panel, &kDYYYFullscreenBackdropPageKey, page,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 垫上了才清底色：清了却没垫上只会更黑。
    objc_setAssociatedObject(panelView, &kDYYYFullscreenPanelColorKey,
                             panelView.backgroundColor ?: (id)[NSNull null],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    panelView.backgroundColor = UIColor.clearColor;
    panelView.opaque = NO;
    gDYYYFullscreenBackdropAttached = YES;
}

static void DYYYFullscreenDetachBackdrop(UIViewController *panel) {
    UIView *page = objc_getAssociatedObject(panel, &kDYYYFullscreenBackdropPageKey);
    if (!page) return;
    gDYYYFullscreenBackdropAttached = NO;

    UIView *panelView = panel.viewIfLoaded;
    id baseline = objc_getAssociatedObject(panelView, &kDYYYFullscreenPanelColorKey);
    if (baseline) {
        UIColor *color = (baseline == [NSNull null]) ? nil : (UIColor *)baseline;
        panelView.backgroundColor = color;
        // opaque 由记下的底色推出来，不额外留一份状态。
        panelView.opaque = color && CGColorGetAlpha(color.CGColor) >= 0.99;
        objc_setAssociatedObject(panelView, &kDYYYFullscreenPanelColorKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [page removeFromSuperview];
    objc_setAssociatedObject(panel, &kDYYYFullscreenBackdropPageKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook UIView

- (void)setBackgroundColor:(UIColor *)color {
    if (gDYYYFullscreenBackdropAttached && color && CGColorGetAlpha(color.CGColor) >= 0.99
        && objc_getAssociatedObject(self, &kDYYYFullscreenPanelColorKey)) {
        // 记下最新的主题色：摘除时才还得回当前外观那一份，而不是进场时那一份。
        objc_setAssociatedObject(self, &kDYYYFullscreenPanelColorKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        %orig(UIColor.clearColor);
        return;
    }
    %orig;
}

%end

%hook AWECommentFullScreenContainerViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // 转场已结束，此时插入不干扰动画；交互式返回中途取消会再走一次，与下面的摘除天然对称。
    gDYYYFullscreenFullPanel = self;
    DYYYFullscreenAttachBackdrop(self);
    // 全屏态弹幕该回到抖音原生的隐藏；标记先于同步，判据才是新状态。
}

- (void)viewWillDisappear:(BOOL)animated {
    // 必须早于 %orig：pop 之后 UIKit 会把那一页放回它自己的 wrapper，得先还回原状。
    gDYYYFullscreenFullPanel = nil;
    DYYYFullscreenDetachBackdrop(self);
    %orig;
}

%end

%hook AWEPlayInteractionCommentPanelController

- (BOOL)shouldShowCommentShrinkVideo {
    if (DYYYFullscreenPreventCommentMovement()) return NO;
    return %orig;
}

- (void)resizeVideoWhenDragCommentPanel:(double)progress {
    if (DYYYFullscreenPreventCommentMovement()) return;
    %orig;
}

- (void)shrinkVideoWhenEnterPartialFullCommentPanel:(BOOL)animated {
    if (DYYYFullscreenPreventCommentMovement()) return;
    %orig;
}

- (void)shrinkVideoWhenShowCommentPanel:(BOOL)animated {
    if (DYYYFullscreenPreventCommentMovement()) return;
    %orig;
}

- (BOOL)enableShowInnerPiPWhenFullScreen {
    if (!DYYYFullscreenPreventCommentMovement()) return %orig;

    return NO;
}

%end

%hook AWEPlayVideoViewController

- (void)playerWillLoopPlaying:(id)player {
    %orig;
    if (!DYYYFullscreenPreventCommentMovement() || !DYYYFullscreenCommentFullPanelOnScreen()) return;

    AWEDPlayerViewController_Merge *merge = (AWEDPlayerViewController_Merge *)self.parentViewController;
    if (![merge isKindOfClass:%c(AWEDPlayerViewController_Merge)]) return;

    // 落到下一轮 runloop，才排在抖音自己那串同步监听之后；它自己续上了就不插手。
    __weak AWEDPlayerViewController_Merge *weakMerge = merge;
    dispatch_async(dispatch_get_main_queue(), ^{
        AWEDPlayerViewController_Merge *strongMerge = weakMerge;
        if (!strongMerge || !DYYYFullscreenCommentFullPanelOnScreen() || [strongMerge isPlaying]) return;

        if (DYYYFullscreenPreventCommentMovement()) [strongMerge play];
    });
}

%end

// 只数不拦，纯排查用：分辨「播放请求被拒」与「播起来之后又被停掉」，
// 这正是 beta16 → beta17 花了两轮才分清的那个问题。

%end

#pragma mark - Hook 初始化

%ctor {
gDYYYFullscreenStretchedTables = [NSHashTable weakObjectsHashTable];
    gDYYYFullscreenOriginalMergeFrames = [NSMapTable weakToStrongObjectsMapTable];

%init(DYYYFullscreenVideoFeedTableHooks);

Class controllerClass = NSClassFromString(@"AWEAwemeDetailTableViewController");
    SEL selectors[] = {
        @selector(setupDetailTableView), @selector(viewWillLayoutSubviews),
        @selector(fixedCellHeight), @selector(cellHeightAtIndex:),
        @selector(tableView:heightForRowAtIndexPath:),
        @selector(contentOffsetYForCellAtIndex:),
        @selector(adjustTableViewHeightForTargetIndex:)
    };
    BOOL compatible = YES;
    for (SEL selector : selectors) {
        if (!class_getInstanceMethod(controllerClass, selector)) compatible = NO;
    }
    if (compatible) { %init(DYYYFullscreenVideoDetailTableHooks); }

gDYYYFullscreenDKManagedVisualViews = [NSHashTable weakObjectsHashTable];

%init(DYYYFullscreenVideoPageChromeHooks);

    gDYYYFullscreenProgressColorOwners = [NSHashTable weakObjectsHashTable];
    Class feedProgressClass = NSClassFromString(@"AWEDProgressFeedContainer");
    if ([feedProgressClass instancesRespondToSelector:@selector(setProgressUnderViewColor)] &&
        [feedProgressClass instancesRespondToSelector:@selector(progressSliderUnderView)]) {
        %init(DYYYFullscreenProgressFeedColorHooks);
    }
    Class legacyProgressClass = NSClassFromString(@"AWEPlayInteractionProgressController");
    if ([legacyProgressClass instancesRespondToSelector:@selector(setProgressUnderViewColor)] &&
        [legacyProgressClass instancesRespondToSelector:@selector(progressSliderUnderView)]) {
        %init(DYYYFullscreenLegacyProgressColorHooks);
    }

%init(DYYYFullscreenCommentFullBackdropHooks);

    // 设置页和远程配置共用 defaults；关闭时执行上游的原高/transform 还原。
    static id fullscreenDefaultsObserver;
    __block BOOL fullscreenWasEnabled = DYYYFullscreenVideoFullscreenOn();
    __block BOOL movementWasPrevented = DYYYFullscreenPreventCommentMovement();
    fullscreenDefaultsObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
        usingBlock:^(__unused NSNotification *note) {
            // defaults 可在持有初始化锁的后台线程发通知，不能同步等待主线程。
            dispatch_async(dispatch_get_main_queue(), ^{
                BOOL enabled = DYYYFullscreenVideoFullscreenOn();
                BOOL preventMovement = DYYYFullscreenPreventCommentMovement();
                if (enabled == fullscreenWasEnabled && preventMovement == movementWasPrevented) return;
                BOOL leavingFullscreen = fullscreenWasEnabled && !enabled;
                fullscreenWasEnabled = enabled;
                movementWasPrevented = preventMovement;
                if (leavingFullscreen) {
                    DYYYFullscreenVideoFeedTableRestore();
                    DYYYFullscreenPageChromeVisualRestore();
                    // 交回原生取色，恢复当前页面/主题应有的颜色。
                    for (id owner in gDYYYFullscreenProgressColorOwners.allObjects) {
                        [owner setProgressUnderViewColor];
                    }
                    [gDYYYFullscreenProgressColorOwners removeAllObjects];
                }
                DYYYFullscreenRestoreMergeFrames();
            });
        }];

if ([DYYYUtils liquidGlassAvailable]) {
        %init(DYYYTabGlassGlassTabBarHooks);
    }

gDYYYCommentGlassGlassCarriers = [NSHashTable weakObjectsHashTable];
    gDYYYCommentGlassClearedCovers = [NSHashTable weakObjectsHashTable];
    gDYYYCommentGlassFoldMaskedViews = [NSHashTable weakObjectsHashTable];

    if ([DYYYUtils liquidGlassAvailable]) {
        %init(DYYYCommentGlassCommentGlassHooks);

        if (NSClassFromString(@"AWECommentMiniEmoticonPanelView")) {
            %init(DYYYCommentGlassCommentEmoticonHook);
        }

        if (NSClassFromString(@"AWEListKitMagicCollectionView") && DYYYCommentGlassFoldDisplayClass()) {
            %init(DYYYCommentGlassCommentFoldHook);
        }

        Class searchPanel = NSClassFromString(@"AWECommentSearchViewController");
        if ([searchPanel instancesRespondToSelector:@selector(obtainPanelColor)]) {
            %init(DYYYCommentGlassCommentSearchPanelHook);
        }

        // 类或方法任一不在就不装：内部 generator 对不存在的方法会「新增」而不是「钩住」，
        // 那样 %orig 会调进空实现。
        Class abTest = NSClassFromString(@"AWECommentABTestSettings");
        if ([abTest respondsToSelector:@selector(enableCommentRenderingOptimize:)]) {
            %init(DYYYCommentGlassCommentRenderOptimizeHook);
        }
    }

gDYYYNotificationGlassGlassCarriers = [NSHashTable weakObjectsHashTable];
    gDYYYNotificationGlassContainers = [NSHashTable weakObjectsHashTable];
    gDYYYNotificationGlassCommonViews = [NSHashTable weakObjectsHashTable];

    if ([DYYYUtils liquidGlassAvailable]) {
        %init(DYYYNotificationGlassInnerNotificationGlassHooks);
    }

    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        @"DYYYDisableFeedNowPlayingInfo" : @YES
    }];

    DYYYMigrateCombinedHDRModeIfNeeded();

    // 合集底栏接口签名一致时才接入；旧版本继续使用模型层回退。
    Class mixBarElementClass = objc_getClass("AWEPlayInteractionNewMixVideoInfoElement");
    Class contextStoreClass = objc_getClass("AWEContextStore");
    Method mixBarAppearMethod = class_getInstanceMethod(mixBarElementClass, @selector(shouldAppearWithData:));
    Method mixBarContextMethod = class_getInstanceMethod(mixBarElementClass, @selector(context));
    Method contextSetBoolMethod = class_getInstanceMethod(contextStoreClass, @selector(setBool:forKey:));
    if (mixBarAppearMethod && method_getNumberOfArguments(mixBarAppearMethod) == 3 &&
        mixBarContextMethod && method_getNumberOfArguments(mixBarContextMethod) == 2 &&
        contextSetBoolMethod && method_getNumberOfArguments(contextSetBoolMethod) == 4) {
        char appearReturnType[16] = {0}, appearArgumentType[16] = {0};
        char contextReturnType[16] = {0}, setterReturnType[16] = {0};
        char setterValueType[16] = {0}, setterKeyType[16] = {0};
        method_getReturnType(mixBarAppearMethod, appearReturnType, sizeof(appearReturnType));
        method_getArgumentType(mixBarAppearMethod, 2, appearArgumentType, sizeof(appearArgumentType));
        method_getReturnType(mixBarContextMethod, contextReturnType, sizeof(contextReturnType));
        method_getReturnType(contextSetBoolMethod, setterReturnType, sizeof(setterReturnType));
        method_getArgumentType(contextSetBoolMethod, 2, setterValueType, sizeof(setterValueType));
        method_getArgumentType(contextSetBoolMethod, 3, setterKeyType, sizeof(setterKeyType));
        if (appearReturnType[0] == @encode(BOOL)[0] && appearArgumentType[0] == @encode(id)[0] &&
            contextReturnType[0] == @encode(id)[0] && setterReturnType[0] == @encode(void)[0] &&
            setterValueType[0] == @encode(BOOL)[0] && setterKeyType[0] == @encode(id)[0]) {
            %init(DYYYVideoMixBarVisibilityGroup);
            dyyyVideoMixBarVisibilityHookEnabled = YES;
        }
    }

    // 直播预览内部页面回调与 UIKit 回调分开，确认 BOOL 参数签名后再接入。
    Class livePreviewClass = objc_getClass("AWELiveNewPreStreamViewController");
    Method livePageAppearMethod = class_getInstanceMethod(livePreviewClass, @selector(pageDidAppear:));
    char livePageReturnType[16] = {0}, livePageArgumentType[16] = {0};
    if (livePageAppearMethod && method_getNumberOfArguments(livePageAppearMethod) == 3) {
        method_getReturnType(livePageAppearMethod, livePageReturnType, sizeof(livePageReturnType));
        method_getArgumentType(livePageAppearMethod, 2, livePageArgumentType, sizeof(livePageArgumentType));
        if (livePageReturnType[0] == @encode(void)[0] && livePageArgumentType[0] == @encode(BOOL)[0]) {
            %init(DYYYLivePreStreamPageAppearGroup);
        }
    }

    Class interactionBaseLabelClass = objc_getClass("AWECommentSwiftBizUI.CommentInteractionBaseLabel");
    if (interactionBaseLabelClass) {
        %init(DYYYCommentExactTimeGroup, AWECommentSwiftBizUI_CommentInteractionBaseLabel = interactionBaseLabelClass);
    }
    
    Class imMenuComponentClass = objc_getClass("AWEIMCustomMenuComponent");
    if (imMenuComponentClass) {
        SEL legacySelector = NSSelectorFromString(@"msg_showMenuForBubbleFrameInScreen:tapLocationInScreen:menuItemList:moreEmoticon:onCell:extra:");
        SEL tapLocationSelector = NSSelectorFromString(@"msg_showMenuForBubbleFrameInScreen:tapLocationInScreen:menuItemList:menuPanelOptions:moreEmoticon:onCell:extra:");
        SEL highLowSelector = NSSelectorFromString(@"msg_showMenuForBubbleFrameInScreen:highLocationInScreen:lowLocationInScreen:tryHighLocationFirst:menuItemList:menuPanelOptions:onCell:extra:");
        if (legacySelector && class_getInstanceMethod(imMenuComponentClass, legacySelector)) {
            %init(DYYYIMMenuLegacyGroup);
        }
        if (tapLocationSelector && class_getInstanceMethod(imMenuComponentClass, tapLocationSelector)) {
            %init(DYYYIMMenuTapLocationGroup);
        }
        if (highLowSelector && class_getInstanceMethod(imMenuComponentClass, highLowSelector)) {
            %init(DYYYIMMenuHighLowGroup);
        }
    }

    // 唯一日常入口始终可用；兼容保留旧禁用配置，不再让它锁死设置中心。
    %init(DYYYSettingsGesture);
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) [[DYYYSettingsCoordinator shared] installGestureInWindow:window];
        }
    });
    if (DYYYGetBool(@"DYYYUserAgreementAccepted")) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
          Class wSwiftImpl = objc_getClass("AWECommentInputViewSwiftImpl.CommentInputContainerView");
          %init(CommentInputContainerView = wSwiftImpl);
        });
        BOOL isAutoPlayEnabled = DYYYGetBool(@"DYYYEnableAutoPlay");
        if (isAutoPlayEnabled) {
            %init(AutoPlay);
        }
        if (DYYYGetBool(@"DYYYForceDownloadEmotion") ||
            DYYYGetBool(@"DYYYForceDownloadCommentAudio") ||
            DYYYGetBool(@"DYYYForceDownloadCommentImage")) {
            %init(EnableStickerSaveMenu);
        }
        [FloatingSpeedButton reloadConfiguration];

        // 初始化红包激励挂件容器视图类组
        Class incentivePendantClass = objc_getClass("AWEIncentiveSwiftImplDOUYINLite.IncentivePendantContainerView");
        if (incentivePendantClass) {
            %init(IncentivePendantGroup, AWEIncentiveSwiftImplDOUYINLite_IncentivePendantContainerView = incentivePendantClass);
        }

        // 动态获取 Swift 类并初始化对应的组
        Class commentHeaderGeneralClass = objc_getClass("AWECommentPanelHeaderSwiftImpl.CommentHeaderGeneralView");
        if (commentHeaderGeneralClass) {
            %init(CommentHeaderGeneralGroup, AWECommentPanelHeaderSwiftImpl_CommentHeaderGeneralView = commentHeaderGeneralClass);
        }

        Class commentHeaderGoodsClass = objc_getClass("AWECommentPanelHeaderSwiftImpl.CommentHeaderGoodsView");
        if (commentHeaderGoodsClass) {
            %init(CommentHeaderGoodsGroup, AWECommentPanelHeaderSwiftImpl_CommentHeaderGoodsView = commentHeaderGoodsClass);
        }
        Class commentHeaderTemplateClass = objc_getClass("AWECommentPanelHeaderSwiftImpl.CommentHeaderTemplateAnchorView");
        if (commentHeaderTemplateClass) {
            %init(CommentHeaderTemplateGroup, AWECommentPanelHeaderSwiftImpl_CommentHeaderTemplateAnchorView = commentHeaderTemplateClass);
        }

        Class tipsVCClass = objc_getClass("AWECommentPanelListSwiftImpl.CommentBottomTipsContainerViewController");
        if (tipsVCClass) {
            %init(CommentBottomTipsVCGroup, AWECommentPanelListSwiftImpl_CommentBottomTipsContainerViewController = tipsVCClass);
        }

        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        DYYYRemoveKeyboardObserver();
        dyyyKeyboardWillShowToken = [center addObserverForName:UIKeyboardWillShowNotification
                                                        object:nil
                                                         queue:[NSOperationQueue mainQueue]
                                                    usingBlock:^(NSNotification *notification) {
                                                      if (DYYYGetBool(@"DYYYHideKeyboardAI")) {
                                                          if (cachedHideView) {
                                                              for (UIView *subview in cachedHideView.subviews) {
                                                                  subview.hidden = YES;
                                                              }
                                                          } else {
                                                              for (UIWindow *window in [UIApplication sharedApplication].windows) {
                                                                  findTargetViewInView(window);
                                                                  if (cachedHideView)
                                                                      break;
                                                              }
                                                          }
                                                      }
                                                    }];
    }
}
