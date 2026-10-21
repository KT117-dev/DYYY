#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYYYLoginBypassManager : NSObject

/// 首次注入时按官方登录态写入默认开关；未登录默认开，已登录默认关。
+ (void)configureInitialStateIfNeeded;

/// 运行时门控：含首次配置 pending 时对已登录态的即时抑制，避免短暂误开。
+ (BOOL)isLoginBypassEnabled;

/// 官方包名、Lite/beta/internal，以及 `Aweme` + 四位数字的多开副本。
+ (BOOL)isTargetBundleIdentifier:(nullable id)value;

/// 多开副本映射到官方 `com.ss.iphone.ugc.Aweme` 后再追加伪装后缀。
/// 绕登录关闭后仍沿用登录时记下的多开映射，避免作品接口身份跳变。
+ (NSString *)replacementBundleIdentifier:(NSString *)bundleIdentifier;

+ (nullable NSString *)headerValueByReplacingBundleIdentifier:(nullable NSString *)value field:(nullable NSString *)field;
+ (nullable NSDictionary *)headersByReplacingBundleIdentifiers:(nullable NSDictionary *)headers;
+ (nullable NSString *)stringByReplacingTargetBundleIdentifiers:(nullable NSString *)value;
+ (nullable NSURL *)URLByReplacingTargetBundleIdentifiers:(nullable NSURL *)url;

/// 官方登录完成双通道入口（AWEUserServiceListener / TTAccountMulticast）。
+ (void)handleOfficialLoginCompletionWithUserID:(nullable id)userIDOrAccount;

@end

NS_ASSUME_NONNULL_END
