#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AWEUserModel;

@interface DYYYGlassBackdropView : UIView
+ (NSDictionary<NSString *, NSString *> *)defaultSettings;
- (instancetype)initWithSettingsPrefix:(NSString *)prefix;
- (instancetype)initWithWhiteOpacity:(CGFloat)whiteOpacity blurIntensity:(CGFloat)blurIntensity;
@end

@interface DYYYGlassBackgroundView : UIVisualEffectView
- (instancetype)initWithCornerRadius:(CGFloat)radius settingsPrefix:(nullable NSString *)prefix;
@end

// 定义警告框操作回调类型
typedef void (^DYYYAlertActionHandler)(void);

@interface DYYYBottomAlertView : UIView
+ (void)applyGlassButtonStyle:(UIButton *)button;

+ (nullable instancetype)showFollowConfirmationForUser:(AWEUserModel *)user
                                          avatarView:(UIView *)avatarView
                                       confirmAction:(DYYYAlertActionHandler)confirmAction;
+ (instancetype)showCollectConfirmationWithAction:(DYYYAlertActionHandler)confirmAction;

/**
 * 在当前窗口显示确认覆盖层，支持自定义按钮文本
 * @param title 标题文本
 * @param message 消息文本
 * @param cancelButtonText 取消按钮文本 (为空时使用默认文本)
 * @param confirmButtonText 确认按钮文本 (为空时使用默认文本)
 * @param cancelAction 点击取消按钮回调
 * @param closeAction 点击关闭按钮、下滑或点击外部区域关闭弹窗回调 (为空时仅关闭)
 * @param confirmAction 点击确认按钮回调
 * @return 返回覆盖视图，可用于关闭弹窗
 */
+ (instancetype)showAlertWithTitle:(nullable NSString *)title
                                 message:(nullable NSString *)message
                        cancelButtonText:(nullable NSString *)cancelButtonText
                       confirmButtonText:(nullable NSString *)confirmButtonText
                            cancelAction:(nullable DYYYAlertActionHandler)cancelAction
                             closeAction:(nullable DYYYAlertActionHandler)closeAction
                           confirmAction:(nullable DYYYAlertActionHandler)confirmAction;

/**
 * 关闭警告框
 */
- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
