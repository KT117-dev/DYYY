#import "DYYYBottomAlertView.h"
#import "DYYYSettingsCoordinator.h"
#import "DYYYSettingsRegistry.h"
#import "DYYYUtils.h"
#import <math.h>

@interface DYYYGlassBackdropView ()
@property(nonatomic, strong) UIVisualEffectView *blurView;
@property(nonatomic, strong) UIViewPropertyAnimator *blurAnimator;
@property(nonatomic, strong) UIView *whiteView;
@property(nonatomic, copy) NSString *settingsPrefix;
@property(nonatomic, strong) id changeToken;
@property(nonatomic) CGFloat blurIntensity;
@end

@implementation DYYYGlassBackdropView
+ (NSDictionary<NSString *, NSString *> *)defaultSettings {
    static NSDictionary *defaults;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaults = @{
            @"DYYYSettingsWhiteOpacity": @"0.1", @"DYYYSettingsBlurIntensity": @"0.1",
            @"DYYYCommentGlassWhiteOpacity": @"0.05", @"DYYYCommentGlassBlurIntensity": @"0.08",
            @"DYYYNotificationGlassWhiteOpacity": @"0.05", @"DYYYNotificationGlassBlurIntensity": @"0.08",
            @"DYYYFollowConfirmationWhiteOpacity": @"0.2", @"DYYYFollowConfirmationBlurIntensity": @"0.1",
            @"DYYYCollectConfirmationWhiteOpacity": @"0.2", @"DYYYCollectConfirmationBlurIntensity": @"0.1"
        };
    });
    return defaults;
}
- (instancetype)initWithSettingsPrefix:(NSString *)prefix {
    if ((self = [self initWithWhiteOpacity:0 blurIntensity:0])) {
        self.settingsPrefix = prefix;
        [self reloadSettings];
        __weak typeof(self) weakSelf = self;
        self.changeToken = [NSNotificationCenter.defaultCenter addObserverForName:DYYYSettingsDidChangeNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf reloadSettings];
            });
        }];
    }
    return self;
}
- (void)reloadSettings {
    NSString *whiteKey = [self.settingsPrefix stringByAppendingString:@"WhiteOpacity"];
    NSString *blurKey = [self.settingsPrefix stringByAppendingString:@"BlurIntensity"];
    NSDictionary *defaults = self.class.defaultSettings;
    CGFloat white = round([[NSUserDefaults.standardUserDefaults objectForKey:whiteKey] ?: defaults[whiteKey] doubleValue] * 100) / 100;
    CGFloat blur = round([[NSUserDefaults.standardUserDefaults objectForKey:blurKey] ?: defaults[blurKey] doubleValue] * 100) / 100;
    self.whiteView.backgroundColor = [UIColor colorWithWhite:1 alpha:white];
    if (self.blurIntensity != blur) {
        self.blurIntensity = blur;
        [self updateBlurEffect];
    }
}
- (instancetype)initWithWhiteOpacity:(CGFloat)whiteOpacity blurIntensity:(CGFloat)blurIntensity {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.opaque = NO;
        self.blurIntensity = blurIntensity;
        self.blurView = [[UIVisualEffectView alloc] initWithEffect:nil];
        self.blurView.frame = self.bounds;
        self.blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.blurView.userInteractionEnabled = NO;
        self.blurView.clipsToBounds = YES;
        self.blurView.hidden = blurIntensity <= 0;
        [self addSubview:self.blurView];
        UIView *white = [[UIView alloc] initWithFrame:self.bounds];
        self.whiteView = white;
        white.opaque = NO;
        white.backgroundColor = [UIColor colorWithWhite:1 alpha:whiteOpacity];
        white.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        white.userInteractionEnabled = NO;
        white.clipsToBounds = YES;
        [self addSubview:white];
    }
    return self;
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self.blurAnimator stopAnimation:YES];
    self.blurAnimator = nil;
    self.blurView.effect = nil;
    [self updateBlurEffect];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateBlurEffect];
}
- (void)setCornerConfiguration:(UICornerConfiguration *)configuration API_AVAILABLE(ios(26.0)) {
    [super setCornerConfiguration:configuration];
    self.blurView.cornerConfiguration = configuration;
    self.whiteView.cornerConfiguration = configuration;
}
- (void)updateBlurEffect {
    // 入窗可能早于首次布局；零尺寸或强度为零时不创建效果，后续布局再补齐。
    if (!self.window || CGRectIsEmpty(self.bounds) || self.blurIntensity <= 0) {
        [self.blurAnimator stopAnimation:YES];
        self.blurAnimator = nil;
        self.blurView.effect = nil;
        self.blurView.hidden = YES;
        return;
    }
    self.blurView.hidden = NO;
    if (!self.blurAnimator) {
        UIVisualEffectView *blur = self.blurView;
        self.blurAnimator = [[UIViewPropertyAnimator alloc] initWithDuration:1 curve:UIViewAnimationCurveLinear animations:^{
            blur.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
        }];
        self.blurAnimator.pausesOnCompletion = YES;
    }
    if (self.blurAnimator.fractionComplete != self.blurIntensity) self.blurAnimator.fractionComplete = self.blurIntensity;
}
- (void)dealloc {
    if (self.changeToken)
        [NSNotificationCenter.defaultCenter removeObserver:self.changeToken];
    [self.blurAnimator stopAnimation:YES];
}
@end

@implementation DYYYGlassBackgroundView
- (instancetype)initWithCornerRadius:(CGFloat)radius settingsPrefix:(NSString *)prefix {
    if ((self = [super initWithEffect:nil])) {
        self.layer.cornerRadius = radius;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;
        if (@available(iOS 26.0, *))
            self.cornerConfiguration = [UICornerConfiguration configurationWithRadius:[UICornerRadius fixedRadius:radius]];
        DYYYGlassBackdropView *background = prefix ? [[DYYYGlassBackdropView alloc] initWithSettingsPrefix:prefix] : [[DYYYGlassBackdropView alloc] initWithWhiteOpacity:0.2 blurIntensity:0.1];
        background.frame = self.contentView.bounds;
        background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        background.userInteractionEnabled = NO;
        [self.contentView addSubview:background];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (@available(iOS 26.0, *)) {
        // 零尺寸创建材质可能只有透明外壳，先让布局确定实际大小。
        if (!self.effect && !CGRectIsEmpty(self.bounds)) {
            UIGlassEffect *effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleClear];
            effect.interactive = YES;
            self.effect = effect;
        }
    }
}
@end

@interface DYYYBottomAlertView ()
@property(nonatomic, copy) DYYYAlertActionHandler cancelAction;
@property(nonatomic, copy) DYYYAlertActionHandler closeAction;
@property(nonatomic, copy) DYYYAlertActionHandler confirmAction;
@property(nonatomic, strong) UIVisualEffectView *glass;
@property(nonatomic, weak) UIWindowScene *profileAppearanceScene;
@property(nonatomic, strong) id<UITraitChangeRegistration> profileAppearanceRegistration API_AVAILABLE(ios(17.0));
@end

@implementation DYYYBottomAlertView
+ (void)applyGlassButtonStyle:(UIButton *)button {
    button.tintColor = UIColor.labelColor;
    if (@available(iOS 26.0, *)) {
        UIButtonConfiguration *configuration = [UIButtonConfiguration clearGlassButtonConfiguration];
        configuration.title = button.currentTitle;
        configuration.image = button.currentImage;
        configuration.baseForegroundColor = UIColor.labelColor;
        button.configuration = configuration;
    }
}

+ (instancetype)showAlertWithTitle:(NSString *)title
                                 message:(NSString *)message
                        cancelButtonText:(NSString *)cancelText
                       confirmButtonText:(NSString *)confirmText
                            cancelAction:(DYYYAlertActionHandler)cancel
                             closeAction:(DYYYAlertActionHandler)close
                           confirmAction:(DYYYAlertActionHandler)confirm {
    return [self showTextConfirmationWithTitle:title message:message settingsPrefix:nil cancelButtonText:cancelText confirmButtonText:confirmText cancelAction:cancel closeAction:close confirmAction:confirm];
}

+ (instancetype)showCollectConfirmationWithAction:(DYYYAlertActionHandler)confirm {
    return [self showTextConfirmationWithTitle:@"收藏确认" message:@"是否确认/取消收藏？" settingsPrefix:@"DYYYCollectConfirmation" cancelButtonText:nil confirmButtonText:nil cancelAction:nil closeAction:nil confirmAction:confirm];
}

+ (instancetype)showTextConfirmationWithTitle:(NSString *)title message:(NSString *)message settingsPrefix:(NSString *)prefix
                        cancelButtonText:(NSString *)cancelText confirmButtonText:(NSString *)confirmText
                            cancelAction:(DYYYAlertActionHandler)cancel closeAction:(DYYYAlertActionHandler)close confirmAction:(DYYYAlertActionHandler)confirm {
    UILabel *titleLabel = [UILabel new];
    titleLabel.text = title;
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.numberOfLines = 0;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.accessibilityTraits |= UIAccessibilityTraitHeader;
    UILabel *messageLabel = [UILabel new];
    messageLabel.text = message;
    messageLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    messageLabel.adjustsFontForContentSizeCategory = YES;
    messageLabel.numberOfLines = 0;
    messageLabel.textAlignment = NSTextAlignmentCenter;
    messageLabel.hidden = !message.length;
    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, messageLabel]];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 12;
    return [self showContent:content settingsPrefix:prefix cancelButtonText:cancelText confirmButtonText:confirmText cancelAction:cancel closeAction:close confirmAction:confirm];
}

+ (UIImage *)avatarImageInView:(UIView *)view {
    if ([view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image)
        return ((UIImageView *)view).image;
    if ([view isKindOfClass:UIButton.class] && ((UIButton *)view).currentImage)
        return ((UIButton *)view).currentImage;
    for (UIView *child in view.subviews) {
        UIImage *image = [self avatarImageInView:child];
        if (image)
            return image;
    }
    return nil;
}

+ (instancetype)showFollowConfirmationForUser:(AWEUserModel *)user avatarView:(UIView *)avatarView confirmAction:(DYYYAlertActionHandler)confirm {
    UIImage *image = [self avatarImageInView:avatarView];
    if (!image) {
        [DYYYUtils showToast:@"当前头像尚未加载，请稍后重试"];
        return nil;
    }
    UIImageView *avatar = [[UIImageView alloc] initWithImage:image];
    avatar.contentMode = UIViewContentModeScaleAspectFill;
    avatar.layer.cornerRadius = 32;
    avatar.clipsToBounds = YES;
    [NSLayoutConstraint activateConstraints:@[[avatar.widthAnchor constraintEqualToConstant:64], [avatar.heightAnchor constraintEqualToConstant:64]]];
    UILabel *name = [UILabel new];
    name.text = user.nickname;
    name.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    name.adjustsFontForContentSizeCategory = YES;
    name.numberOfLines = 0;
    name.accessibilityTraits |= UIAccessibilityTraitHeader;
    UILabel *account = [UILabel new];
    account.text = [@"抖音号：" stringByAppendingString:[user uniqueIDForShow] ?: @""];
    account.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    account.adjustsFontForContentSizeCategory = YES;
    account.textColor = UIColor.secondaryLabelColor;
    UIStackView *identity = [[UIStackView alloc] initWithArrangedSubviews:@[name, account]];
    identity.axis = UILayoutConstraintAxisVertical;
    identity.spacing = 4;
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[avatar, identity]];
    header.alignment = UIStackViewAlignmentCenter;
    header.spacing = 12;

    NSString *text = user.signature ?: @"";
    UIWindow *window = DYYYSettingsCoordinator.presenter.view.window;
    UITraitCollection *appearance = window.windowScene.traitCollection ?: window.traitCollection;
    UILabel *signature = [UILabel new];
    signature.text = text;
    signature.font = [[UIFontMetrics defaultMetrics] scaledFontForFont:[UIFont systemFontOfSize:16]];
    signature.adjustsFontForContentSizeCategory = YES;
    signature.textColor = UIColor.labelColor;
    signature.numberOfLines = 0;
    signature.hidden = !text.length;
    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[header, signature]];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 12;
    DYYYBottomAlertView *alert = [self showContent:content settingsPrefix:@"DYYYFollowConfirmation" cancelButtonText:@"取消" confirmButtonText:@"关注" cancelAction:nil closeAction:nil confirmAction:confirm];
    alert.overrideUserInterfaceStyle = appearance.userInterfaceStyle;
    alert.profileAppearanceScene = window.windowScene;
    if (@available(iOS 17.0, *)) {
        __weak DYYYBottomAlertView *weakAlert = alert;
        alert.profileAppearanceRegistration = [window.windowScene registerForTraitChanges:@[UITraitUserInterfaceStyle.class] withHandler:^(UIWindowScene *scene, UITraitCollection *previous) {
            weakAlert.overrideUserInterfaceStyle = scene.traitCollection.userInterfaceStyle;
        }];
    }
    return alert;
}

+ (instancetype)showContent:(UIView *)content settingsPrefix:(NSString *)prefix
                        cancelButtonText:(NSString *)cancelText
                       confirmButtonText:(NSString *)confirmText
                            cancelAction:(DYYYAlertActionHandler)cancel
                             closeAction:(DYYYAlertActionHandler)close
                           confirmAction:(DYYYAlertActionHandler)confirm {
    NSAssert(NSThread.isMainThread, @"确认覆盖层必须在主线程显示");
    UIWindow *window = DYYYSettingsCoordinator.presenter.view.window;
    DYYYBottomAlertView *alert = [[self alloc] initWithFrame:window.bounds];
    alert.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    alert.accessibilityViewIsModal = YES;
    alert.cancelAction = cancel ?: close;
    alert.closeAction = close;
    alert.confirmAction = confirm;
    UIButton *backdrop = [UIButton buttonWithType:UIButtonTypeCustom];
    backdrop.frame = alert.bounds;
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    backdrop.accessibilityLabel = @"关闭确认窗口";
    [backdrop addTarget:alert action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [alert addSubview:backdrop];

    UIVisualEffectView *glass = [[DYYYGlassBackgroundView alloc] initWithCornerRadius:26 settingsPrefix:prefix];
    alert.glass = glass;
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    [alert addSubview:glass];

    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancelButton setTitle:cancelText ?: @"取消" forState:UIControlStateNormal];
    [cancelButton addTarget:alert action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    UIButton *confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [confirmButton setTitle:confirmText ?: @"确定" forState:UIControlStateNormal];
    [self applyGlassButtonStyle:cancelButton];
    [self applyGlassButtonStyle:confirmButton];
    [confirmButton addTarget:alert action:@selector(confirmTapped) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[cancelButton, confirmButton]];
    buttons.distribution = UIStackViewDistributionFillEqually;
    buttons.spacing = 12;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[content, buttons]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    if (close && cancelText.length && ![cancelText isEqual:@"取消"]) {
        UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [closeButton setTitle:@"暂不操作" forState:UIControlStateNormal];
        [self applyGlassButtonStyle:closeButton];
        [closeButton addTarget:alert action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:closeButton];
    }
    [glass.contentView addSubview:stack];
    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:alert action:@selector(dismiss)];
    swipe.direction = UISwipeGestureRecognizerDirectionDown;
    [glass addGestureRecognizer:swipe];
    NSLayoutConstraint *width = [glass.widthAnchor constraintEqualToAnchor:alert.widthAnchor constant:-48];
    width.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [glass.centerXAnchor constraintEqualToAnchor:alert.safeAreaLayoutGuide.centerXAnchor],
        [glass.centerYAnchor constraintEqualToAnchor:alert.safeAreaLayoutGuide.centerYAnchor],
        width,
        [glass.widthAnchor constraintLessThanOrEqualToConstant:360],
        [stack.leadingAnchor constraintEqualToAnchor:glass.contentView.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:glass.contentView.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:glass.contentView.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:glass.contentView.bottomAnchor constant:-20],
        [buttons.heightAnchor constraintGreaterThanOrEqualToConstant:44]
    ]];
    // 窗口内覆盖，不 present 控制器，避免打断宿主播放。
    alert.alpha = 0;
    [window addSubview:alert];
    [alert layoutIfNeeded];
    glass.transform = UIAccessibilityIsReduceMotionEnabled() ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.94, 0.94);
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        alert.alpha = 1;
        glass.transform = CGAffineTransformIdentity;
    } completion:nil];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, content);
    return alert;
}
- (void)cancelTapped {
    [self finishWithAction:self.cancelAction];
}
- (void)confirmTapped {
    [self finishWithAction:self.confirmAction];
}
- (void)dismiss {
    [self finishWithAction:self.closeAction];
}
- (void)finishWithAction:(DYYYAlertActionHandler)action {
    self.userInteractionEnabled = NO;
    self.cancelAction = nil;
    self.closeAction = nil;
    self.confirmAction = nil;
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn animations:^{
        self.alpha = 0;
        self.glass.transform = UIAccessibilityIsReduceMotionEnabled() ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.94, 0.94);
    } completion:^(__unused BOOL finished) {
        [self removeFromSuperview];
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
        if (action)
            action();
    }];
}
- (void)dealloc {
    if (@available(iOS 17.0, *)) {
        if (_profileAppearanceRegistration)
            [_profileAppearanceScene unregisterForTraitChanges:_profileAppearanceRegistration];
    }
}
@end
