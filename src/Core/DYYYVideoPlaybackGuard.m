#import "DYYYVideoPlaybackGuard.h"
#import "AwemeHeaders.h"
#import "DYYYConstants.h"
#import "DYYYUtils.h"
#import <objc/runtime.h>

static char kDYYYPlaybackGuardKey;
static char kDYYYPlaybackGuardResultKey;

@interface DYYYVideoPlaybackGuard ()
@property(nonatomic, weak) AWEAwemeFeedSafetyCheckVideoController *controller;
@property(nonatomic, weak) UIViewController<DYYYVideoSafetyFeedContainer> *container;
@property(nonatomic, weak) AWEAwemeModel *observedModel;
@property(nonatomic, weak) AWEAwemeModel *protectedModel;
@property(nonatomic, assign) NSUInteger visit;
@property(nonatomic, assign) BOOL interceptionToastScheduled;
@end

@implementation DYYYVideoPlaybackGuard

#pragma mark - 私有接口兼容性

+ (BOOL)isCompatibleWithApp {
    // 启动时校验一次返回值、参数数量和参数类型，版本接口变化时整组保持原样。
    NSDictionary *interfaces = @{
        @"AWEVideoSafetyCheckResult": @{
            @"safetyCode": @[@"q"], @"safetyMsg": @[@"@"], @"itemId": @[@"@"]
        },
        @"AWEFeedVideoSafetyCheckHandler": @{
            @"handleVideoSafetyPreCheckWithResults:referString:completion:": @[@"v", @"@", @"@", @"@?"],
            @"isIllegalAweme:resultItemIDs:referString:": @[@"B", @"@", @"@", @"@"],
            @"enableSafeCheckCache": @[@"B"], @"lruCache": @[@"@"],
            @"updateCacheIfNeededWithArray:result:": @[@"v", @"@", @"@"],
            @"updateCacheIfNeededWithArray:resultIDs:": @[@"v", @"@", @"@"]
        },
        @"AWEAwemeFeedSafetyCheckVideoController": @{
            @"container": @[@"@"], @"safetyCheckHandler": @[@"@"],
            @"handleVideoPrivacyCheckNotification:": @[@"v", @"@"]
        },
        @"AWEFeedTableViewController": @{
            @"currentAweme": @[@"@"], @"currentIndex": @[@"q"], @"isViewAppearing": @[@"B"], @"isActive": @[@"B"],
            @"setCurrentPlayIndex:": @[@"v", @"q"], @"setIsViewAppearing:": @[@"v", @"B"]
        },
        @"AWEAwemeDetailTableViewController": @{
            @"currentAweme": @[@"@"], @"currentIndex": @[@"q"], @"isViewAppearing": @[@"B"], @"isActive": @[@"B"],
            @"setCurrentIndex:": @[@"v", @"q"], @"setIsViewAppearing:": @[@"v", @"B"]
        }
    };
    for (NSString *className in interfaces) {
        Class cls = NSClassFromString(className);
        if (!cls) {
            return NO;
        }
        NSDictionary *methods = interfaces[className];
        for (NSString *selectorName in methods) {
            Method method = class_getInstanceMethod(cls, NSSelectorFromString(selectorName));
            if (!method) {
                return NO;
            }
            NSArray<NSString *> *types = methods[selectorName];
            NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
            if (signature.numberOfArguments != types.count + 1 || signature.methodReturnType[0] != [types[0] UTF8String][0]) {
                return NO;
            }
            for (NSUInteger index = 1; index < types.count; index++) {
                const char *actual = [signature getArgumentTypeAtIndex:index + 1];
                const char *expected = [types[index] UTF8String];
                if (actual[0] != expected[0] || (expected[0] == '@' && expected[1] == '?' && actual[1] != '?')) {
                    return NO;
                }
            }
        }
    }
    return YES;
}

#pragma mark - 当前观看范围

- (void)endVisit {
    self.visit++;
    self.observedModel = nil;
    self.protectedModel = nil;
    self.interceptionToastScheduled = NO;
}

- (AWEAwemeModel *)visibleModel {
    // 原生结果处理 block 在主线程执行，后台调用保持原样，避免跨线程访问 UIKit。
    if (![NSThread isMainThread]) {
        return nil;
    }
    if (!DYYYGetBool(@"DYYYKeepUnpublishedVideo")) {
        [self endVisit];
        return nil;
    }
    UIViewController<DYYYVideoSafetyFeedContainer> *container = self.container;
    if (!self.controller || self.controller.container != container || !container.isViewLoaded || !container.view.window ||
        ![container respondsToSelector:@selector(isViewAppearing)] || !container.isViewAppearing ||
        ![container respondsToSelector:@selector(isActive)] || !container.isActive ||
        ![container respondsToSelector:@selector(currentAweme)]) {
        [self endVisit];
        return nil;
    }
    AWEAwemeModel *model = container.currentAweme;
    if (![model respondsToSelector:@selector(itemID)] || ![model.itemID isKindOfClass:NSString.class] || !model.itemID.length ||
        ![model respondsToSelector:@selector(isLive)] || model.isLive ||
        ![model respondsToSelector:@selector(video)] || !model.video) {
        [self endVisit];
        return nil;
    }
    if (self.observedModel != model) {
        [self endVisit];
        self.observedModel = model;
    }
    return model;
}

- (AWEAwemeModel *)keptModel {
    if (!self.protectedModel) {
        return nil;
    }
    AWEAwemeModel *model = [self visibleModel];
    return model && model == self.protectedModel ? model : nil;
}

- (void)showInterceptionToastIfNeeded {
    if (self.interceptionToastScheduled) {
        return;
    }
    // 网络结果和隐私通知共用一次提示，不随重复检查连续弹出。
    self.interceptionToastScheduled = YES;
    NSUInteger visit = self.visit;
    __weak DYYYVideoPlaybackGuard *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        DYYYVideoPlaybackGuard *guard = weakSelf;
        // 提示入队后可能已滑走或关闭开关，显示前再次核对观看范围。
        if (!guard || guard.visit != visit || ![guard keptModel]) {
            return;
        }
        [DYYYUtils showToast:DYYY_UNPUBLISHED_VIDEO_INTERCEPTED_MESSAGE];
    });
}

+ (DYYYVideoPlaybackGuard *)guardForObject:(id)object {
    return object && [NSThread isMainThread] ? objc_getAssociatedObject(object, &kDYYYPlaybackGuardKey) : nil;
}

+ (void)bindHandler:(AWEFeedVideoSafetyCheckHandler *)handler toController:(AWEAwemeFeedSafetyCheckVideoController *)controller {
    if (![NSThread isMainThread] || !DYYYGetBool(@"DYYYKeepUnpublishedVideo") || !handler ||
        ![controller respondsToSelector:@selector(container)]) {
        return;
    }
    id container = controller.container;
    if (![container isKindOfClass:UIViewController.class]) {
        return;
    }
    DYYYVideoPlaybackGuard *guard = [self guardForObject:controller];
    if (!guard) {
        guard = [DYYYVideoPlaybackGuard new];
        guard.controller = controller;
        objc_setAssociatedObject(controller, &kDYYYPlaybackGuardKey, guard, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (guard.container != container) {
        if ([self guardForObject:guard.container] == guard) {
            objc_setAssociatedObject(guard.container, &kDYYYPlaybackGuardKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [guard endVisit];
        guard.container = container;
        objc_setAssociatedObject(container, &kDYYYPlaybackGuardKey, guard, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(handler, &kDYYYPlaybackGuardKey, guard, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)container:(UIViewController *)container willChangeIndex:(NSInteger)index {
    DYYYVideoPlaybackGuard *guard = [self guardForObject:container];
    if (!guard || ![NSThread isMainThread]) {
        return;
    }
    id<DYYYVideoSafetyFeedContainer> feed = (id)container;
    if (![feed respondsToSelector:@selector(currentIndex)] || feed.currentIndex != index) {
        [guard endVisit];
    }
}

+ (void)containerWillDisappear:(UIViewController *)container {
    if ([NSThread isMainThread]) {
        [[self guardForObject:container] endVisit];
    }
}

#pragma mark - 检查结果

+ (BOOL)isUnpublishedMessage:(NSString *)message {
    if (![message isKindOfClass:NSString.class] || !message.length || message.length > 512) {
        return NO;
    }
    // 混合提示不能证明只是未公开，保留原生处理，避免吞掉删除等其他原因。
    static NSString * const otherReasons[] = {@"删除", @"不存在", @"违规", @"封禁", @"审核", @"下架", @"失效"};
    for (NSUInteger index = 0; index < sizeof(otherReasons) / sizeof(otherReasons[0]); index++) {
        if ([message rangeOfString:otherReasons[index]].location != NSNotFound) {
            return NO;
        }
    }
    static NSString * const privateReasons[] = {@"未公开", @"不公开", @"私密", @"仅自己可见", @"仅作者可见"};
    for (NSUInteger index = 0; index < sizeof(privateReasons) / sizeof(privateReasons[0]); index++) {
        if ([message rangeOfString:privateReasons[index]].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

+ (void)prepareResults:(NSArray *)results forHandler:(AWEFeedVideoSafetyCheckHandler *)handler {
    DYYYVideoPlaybackGuard *guard = [self guardForObject:handler];
    AWEAwemeModel *current = [guard visibleModel];
    Class resultClass = NSClassFromString(@"AWEVideoSafetyCheckResult");
    if (!current || !resultClass || ![results isKindOfClass:NSArray.class]) {
        return;
    }
    // 一个批次里只要当前作品还有其他失败原因，就不应用临时保留。
    BOOL hasOtherFailure = NO;
    NSMutableArray *privateResults = nil;
    for (AWEVideoSafetyCheckResult *result in results) {
        if (![result isKindOfClass:resultClass]) {
            continue;
        }
        objc_setAssociatedObject(result, &kDYYYPlaybackGuardResultKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (![result.itemId isKindOfClass:NSString.class] || ![result.itemId isEqualToString:current.itemID] || result.safetyCode == 0) {
            continue;
        }
        if (![self isUnpublishedMessage:result.safetyMsg]) {
            hasOtherFailure = YES;
            continue;
        }
        if (!privateResults) {
            privateResults = [NSMutableArray array];
        }
        [privateResults addObject:result];
    }
    if (hasOtherFailure) {
        guard.protectedModel = nil;
        return;
    }
    if (privateResults.count) {
        // 回调入队和实际处理之间可能已滑走；getter 按观看批次再次核对。
        NSDictionary *ticket = @{@"guard": guard, @"visit": @(guard.visit)};
        for (AWEVideoSafetyCheckResult *result in privateResults) {
            objc_setAssociatedObject(result, &kDYYYPlaybackGuardResultKey, ticket, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

+ (NSInteger)safetyCodeForResult:(AWEVideoSafetyCheckResult *)result originalCode:(NSInteger)code {
    if (!code || ![NSThread isMainThread]) {
        return code;
    }
    NSDictionary *ticket = objc_getAssociatedObject(result, &kDYYYPlaybackGuardResultKey);
    if (!ticket) {
        return code;
    }
    DYYYVideoPlaybackGuard *guard = ticket[@"guard"];
    AWEAwemeModel *current = [guard visibleModel];
    if (!current || guard.visit != [ticket[@"visit"] unsignedIntegerValue] ||
        ![result.itemId isKindOfClass:NSString.class] || ![result.itemId isEqualToString:current.itemID]) {
        return code;
    }
    if (![self isUnpublishedMessage:result.safetyMsg]) {
        guard.protectedModel = nil;
        return code;
    }
    if (guard.protectedModel != current) {
        NSLog(@"[DYYY] 保留当前未公开作品的本次观看，检查码：%ld，提示：%@", (long)code, result.safetyMsg);
    }
    guard.protectedModel = current;
    [guard showInterceptionToastIfNeeded];
    // 只改变这次检查的读取结果，不调用 setSafetyCode:/setIsPrivate:/setIsNeedDrawBack:。
    return 0;
}

+ (BOOL)shouldKeepModel:(AWEAwemeModel *)model forHandler:(AWEFeedVideoSafetyCheckHandler *)handler {
    DYYYVideoPlaybackGuard *guard = [self guardForObject:handler];
    return model && model == guard.protectedModel && [guard keptModel] == model;
}

#pragma mark - 隐私通知与检查缓存

+ (BOOL)shouldKeepPrivacyNotification:(NSNotification *)notification forController:(AWEAwemeFeedSafetyCheckVideoController *)controller {
    if (![NSThread isMainThread] || !DYYYGetBool(@"DYYYKeepUnpublishedVideo") ||
        ![notification.name isEqualToString:@"AWEAwemeFeedVideoPrivacyCheckNotification"]) {
        return NO;
    }
    [self bindHandler:controller.safetyCheckHandler toController:controller];
    DYYYVideoPlaybackGuard *guard = [self guardForObject:controller];
    AWEAwemeModel *model = [guard visibleModel];
    id itemID = notification.userInfo[@"AWEAwemeFeedVideoPrivacyCheckValidItemID"];
    if (!model || ![itemID isKindOfClass:NSString.class] || ![itemID isEqualToString:model.itemID]) {
        return NO;
    }
    guard.protectedModel = model;
    [guard showInterceptionToastIfNeeded];
    return YES;
}

+ (NSArray *)filterCacheRequests:(NSArray *)requests forHandler:(AWEFeedVideoSafetyCheckHandler *)handler {
    AWEAwemeModel *model = [[self guardForObject:handler] keptModel];
    if (!model || ![requests isKindOfClass:NSArray.class]) {
        return requests;
    }
    if ([handler enableSafeCheckCache]) {
        id<DYYYVideoSafetyCheckCache> cache = handler.lruCache;
        if ([cache respondsToSelector:@selector(removeObjectForKey:)]) {
            // 同时清理此前的通过缓存，滑走后仍由原生重新判断该作品。
            [cache removeObjectForKey:model.itemID];
        }
    }
    NSMutableArray *filtered = nil;
    NSUInteger index = 0;
    for (id request in requests) {
        // 原生缓存方法使用请求字典里的 item_id；未知结构不做修改。
        if ([request isKindOfClass:NSDictionary.class] && [request[@"item_id"] isEqual:model.itemID]) {
            if (!filtered) {
                filtered = [[requests subarrayWithRange:NSMakeRange(0, index)] mutableCopy];
            }
        } else if (filtered) {
            [filtered addObject:request];
        }
        index++;
    }
    return filtered ?: requests;
}

@end
