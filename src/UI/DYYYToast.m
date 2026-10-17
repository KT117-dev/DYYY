#import "DYYYToast.h"
#import "DYYYUtils.h"

@interface DYYYToast ()
@property(nonatomic, strong) UIProgressView *nativeProgress;
@property(nonatomic, strong) UILabel *statusLabel;
@end
@implementation DYYYToast
+ (void)showMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
      DYYYToast *toast = [[self alloc] initWithFrame:CGRectZero];
      toast.statusLabel.text = message;
      toast.statusLabel.numberOfLines = 0;
      toast.nativeProgress.hidden = YES;
      [toast show];
      UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
      if ([message containsString:@"失败"] || [message containsString:@"错误"])
          [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeError];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [toast removeFromSuperview];
      });
    });
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.containerView = [UIView new];
        self.containerView.backgroundColor = UIColor.secondarySystemBackgroundColor;
        self.containerView.layer.cornerRadius = 18;
        self.containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.containerView];
        self.statusLabel = [UILabel new];
        self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        self.statusLabel.textColor = UIColor.labelColor;
        self.statusLabel.text = @"准备保存…";
        self.nativeProgress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
        [cancel setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
        [cancel addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ self.statusLabel, cancel ]];
        row.spacing = 12;
        row.alignment = UIStackViewAlignmentCenter;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ row, self.nativeProgress ]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 8;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.containerView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [self.containerView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor], [self.containerView.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:12],
            [self.containerView.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor constant:-32],
            [stack.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:16], [stack.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-16],
            [stack.topAnchor constraintEqualToAnchor:self.containerView.topAnchor constant:12], [stack.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor constant:-12],
            [cancel.widthAnchor constraintEqualToConstant:44], [cancel.heightAnchor constraintEqualToConstant:44]
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
    [self dismiss];
}
- (void)setProgress:(float)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
      float value = MIN(MAX(progress, 0), 1);
      self.statusLabel.text = [NSString stringWithFormat:@"保存中 %.0f%%", value * 100];
      [self.nativeProgress setProgress:value animated:!UIAccessibilityIsReduceMotionEnabled()];
    });
}
- (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
      UIWindow *window = [DYYYUtils getActiveWindow];
      if (!window)
          return;
      self.frame = window.bounds;
      self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      [window addSubview:self];
    });
}
- (void)dismiss {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self removeFromSuperview];
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
      [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self removeFromSuperview];
        if (completion)
            completion();
      });
    });
}
@end
