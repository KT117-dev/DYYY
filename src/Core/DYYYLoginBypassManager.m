#import "DYYYLoginBypassManager.h"

#import "AwemeHeaders.h"
#import "DYYYUtils.h"
#import <objc/message.h>

static NSString *const kDYYYLoginBypassManagerEnabledKey = @"DYYYEnableLoginBypass";
static NSString *const kDYYYLoginBypassStickyCloneBundleMapKey = @"DYYYLoginBypassStickyCloneBundleMap";
static NSString *const kDYYYLoginBypassDisabledToast = @"检测账号登录，绕登录设置关闭";
static NSString *const kDYYYLoginBypassManualCloseToast = @"检测登录态失败，请手动关闭绕登录设置";

typedef NS_ENUM(NSUInteger, DYYYOfficialAccountLoginState) {
    DYYYOfficialAccountLoginStateUnknown,
    DYYYOfficialAccountLoginStateLoggedOut,
    DYYYOfficialAccountLoginStateLoggedIn,
};

static NSString *dyyyLoginBypassDefaultsDomainName = nil;
static BOOL dyyyLoginBypassInitialConfigurationPending = NO;
static BOOL dyyyLoginBypassDisableInFlight = NO;
static CFAbsoluteTime dyyyLoginBypassLastHandledAt = 0;

@implementation DYYYLoginBypassManager

#pragma mark - Official account helpers

+ (DYYYOfficialAccountLoginState)officialAccountLoginState {
    Class serviceClass = NSClassFromString(@"AWEUserService");
    if (!serviceClass || ![serviceClass respondsToSelector:@selector(sharedService)]) {
        return DYYYOfficialAccountLoginStateUnknown;
    }

    @try {
        AWEUserService *service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(sharedService));
        if (!service || ![service respondsToSelector:@selector(isLogin)]) {
            return DYYYOfficialAccountLoginStateUnknown;
        }

        return [service isLogin] ? DYYYOfficialAccountLoginStateLoggedIn : DYYYOfficialAccountLoginStateLoggedOut;
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][绕登录] 账号登录态检测异常：%@", exception.reason);
        return DYYYOfficialAccountLoginStateUnknown;
    }
}

+ (nullable NSString *)normalizedUserID:(id)value {
    NSString *userID = nil;
    if ([value isKindOfClass:NSString.class]) {
        userID = value;
    } else if ([value respondsToSelector:@selector(stringValue)]) {
        userID = [value stringValue];
    }

    userID = [userID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (userID.length == 0 ||
        [userID rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) {
        return nil;
    }

    NSCharacterSet *nonZeroDigits = [NSCharacterSet characterSetWithCharactersInString:@"123456789"];
    return [userID rangeOfCharacterFromSet:nonZeroDigits].location == NSNotFound ? nil : userID;
}

+ (nullable NSString *)userIDFromLoginPayload:(id)userIDOrAccount {
    NSString *direct = [self normalizedUserID:userIDOrAccount];
    if (direct.length > 0) {
        return direct;
    }
    if (!userIDOrAccount) {
        return nil;
    }

    @try {
        if ([userIDOrAccount respondsToSelector:@selector(userID)]) {
            return [self normalizedUserID:[userIDOrAccount userID]];
        }
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][绕登录] 解析登录载荷 UID 异常：%@", exception.reason);
    }
    return nil;
}

+ (nullable NSString *)currentOfficialUserID {
    Class serviceClass = NSClassFromString(@"AWEUserService");
    if (!serviceClass || ![serviceClass respondsToSelector:@selector(sharedService)]) {
        return nil;
    }

    @try {
        AWEUserService *service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(sharedService));
        if (!service) {
            return nil;
        }

        if ([service respondsToSelector:@selector(userID)]) {
            NSString *serviceUserID = [self normalizedUserID:[service userID]];
            if (serviceUserID.length > 0) {
                return serviceUserID;
            }
        }

        if ([service respondsToSelector:@selector(currentLoginUser)]) {
            AWEUserModel *currentUser = [service currentLoginUser];
            if ([currentUser respondsToSelector:@selector(userID)]) {
                return [self normalizedUserID:[currentUser userID]];
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][绕登录] 读取官方 UID 异常：%@", exception.reason);
    }
    return nil;
}

+ (BOOL)officialUserServiceConfirmsLoginWithUserID:(NSString *)callbackUserID {
    Class serviceClass = NSClassFromString(@"AWEUserService");
    if (!serviceClass || ![serviceClass respondsToSelector:@selector(sharedService)]) {
        return NO;
    }

    @try {
        AWEUserService *service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(sharedService));
        if (!service ||
            ![service respondsToSelector:@selector(isLogin)] ||
            ![service respondsToSelector:@selector(userID)] ||
            ![service isLogin]) {
            return NO;
        }

        NSString *serviceUserID = [self normalizedUserID:[service userID]];
        NSString *modelUserID = nil;
        if ([service respondsToSelector:@selector(currentLoginUser)]) {
            AWEUserModel *currentUser = [service currentLoginUser];
            if ([currentUser respondsToSelector:@selector(userID)]) {
                modelUserID = [self normalizedUserID:[currentUser userID]];
            }
        }

        return (serviceUserID.length > 0 && [serviceUserID isEqualToString:callbackUserID]) ||
               (modelUserID.length > 0 && [modelUserID isEqualToString:callbackUserID]);
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][绕登录] 官方账号服务状态校验异常：%@", exception.reason);
        return NO;
    }
}

+ (BOOL)officialUserServiceConfirmsLoginWeakly {
    return [self officialAccountLoginState] == DYYYOfficialAccountLoginStateLoggedIn;
}

#pragma mark - Defaults / initial configuration

+ (BOOL)hasPersistentLoginBypassSetting {
    if (dyyyLoginBypassDefaultsDomainName.length == 0) {
        return YES;
    }

    @try {
        NSDictionary *persistentDomain =
            [NSUserDefaults.standardUserDefaults persistentDomainForName:dyyyLoginBypassDefaultsDomainName];
        return persistentDomain[kDYYYLoginBypassManagerEnabledKey] != nil;
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][绕登录] 读取首次配置状态异常：%@", exception.reason);
        return YES;
    }
}

+ (void)persistLoginBypassEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kDYYYLoginBypassManagerEnabledKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    dyyyLoginBypassInitialConfigurationPending = NO;
}

+ (BOOL)finalizeInitialConfigurationIfPossible {
    if (!dyyyLoginBypassInitialConfigurationPending || [self hasPersistentLoginBypassSetting]) {
        dyyyLoginBypassInitialConfigurationPending = NO;
        return YES;
    }

    DYYYOfficialAccountLoginState loginState = [self officialAccountLoginState];
    if (loginState == DYYYOfficialAccountLoginStateUnknown) {
        return NO;
    }

    BOOL shouldEnable = loginState == DYYYOfficialAccountLoginStateLoggedOut;
    [self persistLoginBypassEnabled:shouldEnable];
    NSLog(@"[DYYY][绕登录] 首次配置已完成，当前账号%@登录，绕登录已%@",
          shouldEnable ? @"未" : @"已",
          shouldEnable ? @"开启" : @"关闭");
    return YES;
}

+ (void)attemptInitialConfigurationWithRetryIndex:(NSUInteger)retryIndex {
    if ([self finalizeInitialConfigurationIfPossible]) {
        return;
    }

    static NSArray<NSNumber *> *retryDelays = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      retryDelays = @[ @0.2, @0.8, @2.0 ];
    });
    if (retryIndex >= retryDelays.count) {
        NSLog(@"[DYYY][绕登录] 首次配置登录态仍未知，保持运行时默认开启");
        return;
    }

    NSTimeInterval delay = retryDelays[retryIndex].doubleValue;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self attemptInitialConfigurationWithRetryIndex:retryIndex + 1];
    });
}

+ (void)configureInitialStateIfNeeded {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      @try {
          dyyyLoginBypassDefaultsDomainName = NSBundle.mainBundle.bundleIdentifier.copy;
      } @catch (NSException *exception) {
          NSLog(@"[DYYY][绕登录] 获取首次配置持久化域异常：%@", exception.reason);
          return;
      }
      if (dyyyLoginBypassDefaultsDomainName.length == 0) {
          return;
      }
      if ([self hasPersistentLoginBypassSetting]) {
          return;
      }

      // 同步探测：已登录场景尽早写 NO，避免 registerDefaults=YES 造成短暂误开。
      DYYYOfficialAccountLoginState loginState = [self officialAccountLoginState];
      if (loginState == DYYYOfficialAccountLoginStateLoggedIn) {
          [self persistLoginBypassEnabled:NO];
          NSLog(@"[DYYY][绕登录] 首次同步配置：已登录，绕登录已关闭");
          return;
      }
      if (loginState == DYYYOfficialAccountLoginStateLoggedOut) {
          [self persistLoginBypassEnabled:YES];
          NSLog(@"[DYYY][绕登录] 首次同步配置：未登录，绕登录已开启");
          return;
      }

      dyyyLoginBypassInitialConfigurationPending = YES;
      dispatch_async(dispatch_get_main_queue(), ^{
        [self attemptInitialConfigurationWithRetryIndex:0];
      });
    });

    dispatch_async(dispatch_get_main_queue(), ^{
      [self attemptReconcileWithRetryIndex:0];
    });
}

#pragma mark - Bundle identity / request rewrite

+ (NSArray<NSString *> *)officialFamilyBundleIdentifiers {
    static NSArray<NSString *> *bundleIdentifiers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      bundleIdentifiers = @[
          @"com.ss.iphone.ugc.Aweme",
          @"com.ss.iphone.ugc.Aweme.beta",
          @"com.ss.iphone.ugc.Aweme.internal",
          @"com.ss.iphone.ugc.Aweme.lite",
          @"com.ss.iphone.ugc.aweme.lite"
      ];
    });
    return bundleIdentifiers;
}

+ (BOOL)isNumericAwemeCloneBundleIdentifier:(NSString *)bundleIdentifier {
    static NSString *const kOfficialAwemeBundleIdentifier = @"com.ss.iphone.ugc.Aweme";
    if (bundleIdentifier.length != kOfficialAwemeBundleIdentifier.length + 4) {
        return NO;
    }
    if (![bundleIdentifier hasPrefix:kOfficialAwemeBundleIdentifier]) {
        return NO;
    }
    NSString *suffix = [bundleIdentifier substringFromIndex:kOfficialAwemeBundleIdentifier.length];
    NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
    return [suffix rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

+ (BOOL)isTargetBundleIdentifier:(id)value {
    if (![value isKindOfClass:NSString.class]) {
        return NO;
    }
    NSString *bundleIdentifier = value;
    for (NSString *officialIdentifier in [self officialFamilyBundleIdentifiers]) {
        if ([bundleIdentifier isEqualToString:officialIdentifier]) {
            return YES;
        }
    }
    return [self isNumericAwemeCloneBundleIdentifier:bundleIdentifier];
}

+ (NSString *)canonicalSpoofBaseForBundleIdentifier:(NSString *)bundleIdentifier {
    if ([self isNumericAwemeCloneBundleIdentifier:bundleIdentifier]) {
        return @"com.ss.iphone.ugc.Aweme";
    }
    return bundleIdentifier;
}

+ (NSArray<NSString *> *)emojiSuffixes {
    static NSArray<NSString *> *suffixes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      suffixes = @[
          @"\U0001F60A", @"\U0001F60E", @"\U0001F914", @"\U0001F609", @"\U0001F60B", @"\U0001F60D", @"\U0001F970",
          @"\U0001F618", @"\U0001F617", @"\U0001F619", @"\U0001F61A", @"\U0001F642", @"\U0001F917", @"\U0001F929",
          @"\U0001F928", @"\U0001F9D0", @"\U0001F913", @"\U0001F607", @"\U0001F973", @"\U0001F60C", @"\U0001F60F",
          @"\U0001F612", @"\U0001F643"
      ];
    });
    return suffixes;
}

+ (NSMutableDictionary<NSString *, NSString *> *)stickyCloneBundleMap {
    static NSMutableDictionary<NSString *, NSString *> *map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:kDYYYLoginBypassStickyCloneBundleMapKey];
      map = stored.count > 0 ? stored.mutableCopy : [NSMutableDictionary dictionary];
    });
    return map;
}

+ (void)persistStickyCloneBundleMap {
    NSDictionary<NSString *, NSString *> *snapshot = nil;
    NSMutableDictionary<NSString *, NSString *> *map = [self stickyCloneBundleMap];
    @synchronized(map) {
        snapshot = [map copy];
    }
    if (snapshot.count == 0) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kDYYYLoginBypassStickyCloneBundleMapKey];
    } else {
        [NSUserDefaults.standardUserDefaults setObject:snapshot forKey:kDYYYLoginBypassStickyCloneBundleMapKey];
    }
}

+ (void)rememberStickyReplacement:(NSString *)replacement forBundleIdentifier:(NSString *)bundleIdentifier {
    if (![self isNumericAwemeCloneBundleIdentifier:bundleIdentifier] || replacement.length == 0) {
        return;
    }

    NSMutableDictionary<NSString *, NSString *> *map = [self stickyCloneBundleMap];
    @synchronized(map) {
        if ([map[bundleIdentifier] isEqualToString:replacement]) {
            return;
        }
        map[bundleIdentifier] = replacement;
    }
    [self persistStickyCloneBundleMap];
}

+ (nullable NSString *)stickyReplacementForBundleIdentifier:(NSString *)bundleIdentifier {
    if (![self isNumericAwemeCloneBundleIdentifier:bundleIdentifier]) {
        return nil;
    }
    NSMutableDictionary<NSString *, NSString *> *map = [self stickyCloneBundleMap];
    @synchronized(map) {
        NSString *value = map[bundleIdentifier];
        return value.length > 0 ? value : nil;
    }
}

+ (BOOL)shouldRewriteBundleIdentity {
    if ([self isLoginBypassEnabled]) {
        return YES;
    }
    NSMutableDictionary<NSString *, NSString *> *map = [self stickyCloneBundleMap];
    @synchronized(map) {
        return map.count > 0;
    }
}

+ (NSMutableDictionary<NSString *, NSString *> *)replacementCache {
    static NSMutableDictionary<NSString *, NSString *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      cache = [NSMutableDictionary dictionary];
    });
    return cache;
}

+ (NSString *)replacementBundleIdentifier:(NSString *)bundleIdentifier {
    if (![bundleIdentifier isKindOfClass:NSString.class] || ![self isTargetBundleIdentifier:bundleIdentifier]) {
        return bundleIdentifier;
    }

    NSString *stickyReplacement = [self stickyReplacementForBundleIdentifier:bundleIdentifier];
    if (stickyReplacement.length > 0) {
        return stickyReplacement;
    }
    if (![self isLoginBypassEnabled]) {
        return bundleIdentifier;
    }

    NSMutableDictionary<NSString *, NSString *> *cache = [self replacementCache];
    @synchronized(cache) {
        NSString *cachedValue = cache[bundleIdentifier];
        if (cachedValue.length > 0) {
            [self rememberStickyReplacement:cachedValue forBundleIdentifier:bundleIdentifier];
            return cachedValue;
        }

        NSArray<NSString *> *suffixes = [self emojiSuffixes];
        if (suffixes.count == 0) {
            return bundleIdentifier;
        }

        NSString *canonicalBase = [self canonicalSpoofBaseForBundleIdentifier:bundleIdentifier];
        NSString *suffix = suffixes[arc4random_uniform((uint32_t)suffixes.count)];
        NSString *replacement = [canonicalBase stringByAppendingString:suffix];
        if (replacement.length > 0 && cache.count <= 99) {
            cache[bundleIdentifier] = replacement;
        }
        [self rememberStickyReplacement:replacement forBundleIdentifier:bundleIdentifier];
        return replacement.length > 0 ? replacement : bundleIdentifier;
    }
}

+ (NSString *)headerValueByReplacingBundleIdentifier:(NSString *)value field:(NSString *)field {
    if (![value isKindOfClass:NSString.class] || ![field isKindOfClass:NSString.class]) {
        return value;
    }

    NSString *lowercaseField = field.lowercaseString;
    BOOL isBundleHeaderField = [lowercaseField isEqualToString:@"x-bundle-id"] || [lowercaseField isEqualToString:@"bundle-identifier"] ||
                               [lowercaseField isEqualToString:@"app-bundle-id"] || [lowercaseField isEqualToString:@"x-app-bundle-id"];
    if (!isBundleHeaderField || ![self isTargetBundleIdentifier:value]) {
        return value;
    }
    return [self replacementBundleIdentifier:value];
}

+ (NSDictionary *)headersByReplacingBundleIdentifiers:(NSDictionary *)headers {
    if (![self shouldRewriteBundleIdentity] || ![headers isKindOfClass:NSDictionary.class]) {
        return headers;
    }

    NSMutableDictionary *mutableHeaders = [headers mutableCopy];
    NSArray<NSString *> *headerKeys = @[ @"X-Bundle-ID", @"X-App-Bundle-ID", @"Bundle-Identifier", @"App-Bundle-ID" ];
    for (NSString *headerKey in headerKeys) {
        id value = mutableHeaders[headerKey];
        if ([self isTargetBundleIdentifier:value]) {
            mutableHeaders[headerKey] = [self replacementBundleIdentifier:value];
        }

        NSString *lowercaseKey = headerKey.lowercaseString;
        id lowercaseValue = mutableHeaders[lowercaseKey];
        if ([self isTargetBundleIdentifier:lowercaseValue]) {
            mutableHeaders[lowercaseKey] = [self replacementBundleIdentifier:lowercaseValue];
        }
    }
    return mutableHeaders;
}

+ (NSString *)stringByReplacingTargetBundleIdentifiers:(NSString *)value {
    if (![self shouldRewriteBundleIdentity] || ![value isKindOfClass:NSString.class] || value.length == 0) {
        return value;
    }

    NSString *updatedString = value;
    NSArray<NSString *> *officialIdentifiers = [self officialFamilyBundleIdentifiers];
    NSMutableArray<NSString *> *candidates = officialIdentifiers.mutableCopy ?: [NSMutableArray array];
    static NSRegularExpression *cloneRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      cloneRegex = [NSRegularExpression regularExpressionWithPattern:@"com\\.ss\\.iphone\\.ugc\\.Aweme\\d{4}"
                                                             options:0
                                                               error:nil];
    });
    NSArray<NSTextCheckingResult *> *cloneMatches =
        [cloneRegex matchesInString:value options:0 range:NSMakeRange(0, value.length)];
    for (NSTextCheckingResult *match in cloneMatches) {
        NSString *cloneIdentifier = [value substringWithRange:match.range];
        if (cloneIdentifier.length > 0 && ![candidates containsObject:cloneIdentifier]) {
            [candidates addObject:cloneIdentifier];
        }
    }

    // 先替换更长的 clone / lite / beta，避免 `Aweme` 前缀把 `Aweme3760` 截断替换坏。
    [candidates sortUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
      if (left.length == right.length) {
          return [right compare:left];
      }
      return left.length < right.length ? NSOrderedDescending : NSOrderedAscending;
    }];

    for (NSString *candidate in candidates) {
        if (![updatedString containsString:candidate]) {
            continue;
        }
        updatedString = [updatedString stringByReplacingOccurrencesOfString:candidate
                                                                 withString:[self replacementBundleIdentifier:candidate]];
    }
    return updatedString;
}

+ (NSURL *)URLByReplacingTargetBundleIdentifiers:(NSURL *)url {
    if (![self shouldRewriteBundleIdentity] || ![url isKindOfClass:NSURL.class]) {
        return url;
    }

    NSString *absoluteString = url.absoluteString;
    if (absoluteString.length == 0) {
        return url;
    }

    NSString *updatedString = [self stringByReplacingTargetBundleIdentifiers:absoluteString];
    if ([updatedString isEqualToString:absoluteString]) {
        return url;
    }
    return [NSURL URLWithString:updatedString] ?: url;
}

+ (BOOL)isLoginBypassEnabled {
    if (dyyyLoginBypassInitialConfigurationPending) {
        // pending 期间每次门控复查官方态：已登录立即落盘关闭，避免伪装误开。
        if ([self finalizeInitialConfigurationIfPossible]) {
            return [NSUserDefaults.standardUserDefaults boolForKey:kDYYYLoginBypassManagerEnabledKey];
        }
        // 登录态仍未知：允许开启，保证未登录首次注入可绕过风险提示。
        return YES;
    }

    id storedValue = [NSUserDefaults.standardUserDefaults objectForKey:kDYYYLoginBypassManagerEnabledKey];
    return storedValue == nil ? YES : [storedValue boolValue];
}

#pragma mark - Toast / disable pipeline

+ (void)showToastOnMainQueue:(NSString *)text {
    if (text.length == 0) {
        return;
    }
    dispatch_block_t showBlock = ^{
      [DYYYUtils showToast:text];
    };
    if ([NSThread isMainThread]) {
        showBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), showBlock);
    }
}

+ (void)markDisablePipelineFinished {
    dyyyLoginBypassDisableInFlight = NO;
    dyyyLoginBypassLastHandledAt = CFAbsoluteTimeGetCurrent();
}

+ (BOOL)shouldStartDisablePipeline {
    if (![self isLoginBypassEnabled]) {
        return NO;
    }

    // 双通道几乎同时回调时只启动一轮；失败后允许再次登录重试。
    if (dyyyLoginBypassDisableInFlight || (CFAbsoluteTimeGetCurrent() - dyyyLoginBypassLastHandledAt) < 2.0) {
        return NO;
    }

    dyyyLoginBypassDisableInFlight = YES;
    return YES;
}

+ (BOOL)disableIfOfficialLoginIsConfirmedWithUserID:(nullable NSString *)userID allowWeakMatch:(BOOL)allowWeakMatch {
    if (![self isLoginBypassEnabled]) {
        [self markDisablePipelineFinished];
        return YES;
    }

    NSString *resolvedUserID = userID.length > 0 ? userID : [self currentOfficialUserID];
    BOOL confirmed = NO;
    if (resolvedUserID.length > 0) {
        confirmed = [self officialUserServiceConfirmsLoginWithUserID:resolvedUserID];
    }
    if (!confirmed && allowWeakMatch) {
        confirmed = [self officialUserServiceConfirmsLoginWeakly];
        if (confirmed && resolvedUserID.length == 0) {
            resolvedUserID = [self currentOfficialUserID];
        }
    }
    if (!confirmed) {
        return NO;
    }

    [self persistLoginBypassEnabled:NO];
    NSLog(@"[DYYY][绕登录] 已通过官方账号服务确认登录(uid=%@)，自动关闭绕登录开关", resolvedUserID ?: @"unknown");
    [self showToastOnMainQueue:kDYYYLoginBypassDisabledToast];
    [self markDisablePipelineFinished];
    return YES;
}

+ (void)attemptDisableWithUserID:(nullable NSString *)userID retryIndex:(NSUInteger)retryIndex {
    static NSArray<NSNumber *> *retryDelays = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      retryDelays = @[ @0.2, @0.8, @2.0 ];
    });

    BOOL isLastAttempt = retryIndex >= retryDelays.count;
    if ([self disableIfOfficialLoginIsConfirmedWithUserID:userID allowWeakMatch:isLastAttempt]) {
        return;
    }

    if (isLastAttempt) {
        NSLog(@"[DYYY][绕登录] 登录态校验失败，请手动关闭绕登录开关");
        [self showToastOnMainQueue:kDYYYLoginBypassManualCloseToast];
        [self markDisablePipelineFinished];
        return;
    }

    NSTimeInterval delay = retryDelays[retryIndex].doubleValue;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self attemptDisableWithUserID:userID retryIndex:retryIndex + 1];
    });
}

+ (void)attemptReconcileWithRetryIndex:(NSUInteger)retryIndex {
    static NSArray<NSNumber *> *retryDelays = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      retryDelays = @[ @0.2, @0.8, @2.0 ];
    });

    DYYYOfficialAccountLoginState loginState = [self officialAccountLoginState];
    if (loginState == DYYYOfficialAccountLoginStateLoggedIn) {
        if ([self isLoginBypassEnabled]) {
            [self persistLoginBypassEnabled:NO];
            NSLog(@"[DYYY][绕登录] 启动对账：官方账号已登录，绕登录已关闭");
            [self showToastOnMainQueue:kDYYYLoginBypassDisabledToast];
        }
        return;
    }
    if (loginState == DYYYOfficialAccountLoginStateLoggedOut || retryIndex >= retryDelays.count) {
        return;
    }

    NSTimeInterval delay = retryDelays[retryIndex].doubleValue;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self attemptReconcileWithRetryIndex:retryIndex + 1];
    });
}

+ (void)handleOfficialLoginCompletionWithUserID:(nullable id)userIDOrAccount {
    NSString *normalizedUserID = [self userIDFromLoginPayload:userIDOrAccount];
    if (normalizedUserID.length == 0) {
        normalizedUserID = [self currentOfficialUserID];
    }

    if (![self shouldStartDisablePipeline]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      [self attemptDisableWithUserID:normalizedUserID retryIndex:0];
    });
}

@end
