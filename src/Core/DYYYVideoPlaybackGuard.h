#import <Foundation/Foundation.h>

@class AWEAwemeModel;
@class AWEAwemeFeedSafetyCheckVideoController;
@class AWEFeedVideoSafetyCheckHandler;
@class AWEVideoSafetyCheckResult;
@class UIViewController;

// 保留当前作品的这次观看；状态随作品切换释放，不改写作品的永久隐私状态。
@interface DYYYVideoPlaybackGuard : NSObject
+ (BOOL)isCompatibleWithApp;
+ (void)bindHandler:(AWEFeedVideoSafetyCheckHandler *)handler toController:(AWEAwemeFeedSafetyCheckVideoController *)controller;
+ (void)prepareResults:(NSArray *)results forHandler:(AWEFeedVideoSafetyCheckHandler *)handler;
+ (NSInteger)safetyCodeForResult:(AWEVideoSafetyCheckResult *)result originalCode:(NSInteger)code;
+ (BOOL)shouldKeepModel:(AWEAwemeModel *)model forHandler:(AWEFeedVideoSafetyCheckHandler *)handler;
+ (BOOL)shouldKeepPrivacyNotification:(NSNotification *)notification forController:(AWEAwemeFeedSafetyCheckVideoController *)controller;
+ (NSArray *)filterCacheRequests:(NSArray *)requests forHandler:(AWEFeedVideoSafetyCheckHandler *)handler;
+ (void)container:(UIViewController *)container willChangeIndex:(NSInteger)index;
+ (void)containerWillDisappear:(UIViewController *)container;
@end
