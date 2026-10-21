#import "DYYYToast.h"
#import "DYYYSettingsCoordinator.h"

// 提示覆盖层的白色背景强度：0 完全透明，1 不透明。
static const CGFloat DYYYToastWhiteOpacity = 0.18;

@interface DYYYToast ()
@property(nonatomic, strong) UIProgressView *nativeProgress;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIButton *cancelButton;
@end
@implementation DYYYToast
+ (void)showMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
      DYYYToast *toast = [[self alloc] initWithFrame:CGRectZero];
      [toast show];
      [toast showMessage:message];
    });
}
- (void)showMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
      self.statusLabel.text = message;
      self.nativeProgress.hidden = YES;
      self.cancelButton.hidden = YES;
      UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
      if ([message containsString:@"失败"] || [message containsString:@"错误"])
          [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeError];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self dismiss];
      });
    });
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        UIVisualEffect *effect;
        if (@available(iOS 26.0, *))
            effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleClear];
        else
            effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
        UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
        self.containerView = glass;
        self.containerView.layer.cornerRadius = 18;
        self.containerView.layer.cornerCurve = kCACornerCurveContinuous;
        self.containerView.clipsToBounds = YES;
        if (@available(iOS 26.0, *))
            glass.cornerConfiguration = [UICornerConfiguration configurationWithRadius:[UICornerRadius fixedRadius:18]];
        self.containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.containerView];
        UIView *white = [[UIView alloc] initWithFrame:glass.bounds];
        white.backgroundColor = [UIColor colorWithWhite:1 alpha:DYYYToastWhiteOpacity];
        white.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        white.userInteractionEnabled = NO;
        [glass.contentView addSubview:white];
        self.statusLabel = [UILabel new];
        self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        self.statusLabel.adjustsFontForContentSizeCategory = YES;
        self.statusLabel.numberOfLines = 0;
        self.statusLabel.textAlignment = NSTextAlignmentCenter;
        self.statusLabel.textColor = UIColor.labelColor;
        self.statusLabel.text = @"准备保存…";
        self.nativeProgress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ self.statusLabel, self.nativeProgress ]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 4;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [glass.contentView addSubview:stack];
        self.cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.cancelButton.frame = glass.contentView.bounds;
        self.cancelButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.cancelButton.accessibilityLabel = @"取消保存";
        [self.cancelButton addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
        [glass.contentView addSubview:self.cancelButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.containerView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor], [self.containerView.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:12],
            [self.containerView.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor constant:-32],
            [stack.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:16], [stack.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-16],
            [stack.topAnchor constraintEqualToAnchor:self.containerView.topAnchor constant:8], [stack.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor constant:-8],
            [self.containerView.heightAnchor constraintGreaterThanOrEqualToConstant:44]
        ]];
    }
    return self;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
- (void)cancel {
    self.isCancelled = YES;
    if (self.cancelBlock)
        self.cancelBlock();
    [self dismissWithCompletion:^{
        [DYYYToast showMessage:@"已取消下载"];
    }];
}
- (BOOL)isCancellable {
    return !self.cancelButton.hidden && !self.isCancelled;
}
- (void)setProgress:(float)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
      float value = MIN(MAX(progress, 0), 1);
      self.statusLabel.text = [NSString stringWithFormat:@"保存中 %.0f%%", value * 100];
      self.nativeProgress.accessibilityValue = [NSString stringWithFormat:@"%.0f%%", value * 100];
      [self.nativeProgress setProgress:value animated:!UIAccessibilityIsReduceMotionEnabled()];
    });
}
- (void)beginSaving {
    self.cancelButton.hidden = YES;
    self.statusLabel.text = @"正在保存到相册…";
    [self.nativeProgress setProgress:1 animated:!UIAccessibilityIsReduceMotionEnabled()];
}
- (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
      UIWindow *window = DYYYSettingsCoordinator.presenter.view.window;
      if (!window)
          return;
      self.frame = window.bounds;
      self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      [window addSubview:self];
      [self layoutIfNeeded];
      CGFloat offset = UIAccessibilityIsReduceMotionEnabled() ? 0 : -CGRectGetHeight(self.containerView.bounds) - 12;
      self.containerView.transform = CGAffineTransformMakeTranslation(0, offset);
      self.alpha = 0;
      [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
          self.containerView.transform = CGAffineTransformIdentity;
          self.alpha = 1;
      } completion:nil];
    });
}
- (void)dismiss {
    if (self.allowSuccessAnimation && !self.isCancelled) {
        self.allowSuccessAnimation = NO;
        [self showSuccessAnimation:nil];
        return;
    }
    [self dismissWithCompletion:nil];
}
- (void)dismissWithCompletion:(void (^)(void))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
      self.userInteractionEnabled = NO;
      CGFloat offset = UIAccessibilityIsReduceMotionEnabled() ? 0 : -CGRectGetHeight(self.containerView.bounds) - 12;
      [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn animations:^{
          self.containerView.transform = CGAffineTransformMakeTranslation(0, offset);
          self.alpha = 0;
      } completion:^(__unused BOOL finished) {
          [self removeFromSuperview];
          if (completion)
              completion();
      }];
    });
}
- (void)showSuccessAnimation:(void (^)(void))completion {
    [self showSuccessToastWithMessage:@"保存完成" completion:completion];
}
+ (void)showSuccessToastWithMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
      DYYYToast *toast = [[self alloc] initWithFrame:CGRectZero];
      [toast show];
      [toast showSuccessToastWithMessage:message completion:nil];
    });
}
- (void)showSuccessToastWithMessage:(NSString *)message completion:(void (^)(void))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
      self.statusLabel.text = message;
      self.nativeProgress.hidden = YES;
      self.cancelButton.hidden = YES;
      UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
      [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self dismissWithCompletion:completion];
      });
    });
}
@end
