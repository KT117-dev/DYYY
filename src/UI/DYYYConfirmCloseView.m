#import "DYYYConfirmCloseView.h"
#import <objc/runtime.h>
#import "DYYYSettingsCoordinator.h"

@interface DYYYConfirmCloseView ()
@property(nonatomic, weak) UIAlertController *alert;
@end
@implementation DYYYConfirmCloseView
- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.titleLabel = [UILabel new];
        self.titleLabel.text = title;
        self.messageLabel = [UILabel new];
        self.messageLabel.text = message;
        self.countdown = 5;
    }
    return self;
}
- (void)show {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self show];
        });
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.titleLabel.text message:self.messageLabel.text preferredStyle:UIAlertControllerStyleAlert];
    self.alert = alert;
    alert.view.tintColor = UIColor.labelColor;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *a) {
                                              [self dismiss];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭应用"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *a) {
                                              [self confirmTapped];
                                            }]];
    [DYYYSettingsCoordinator.presenter presentViewController:alert animated:YES completion:nil];
    __weak typeof(self) weakSelf = self;
    self.countdownTimer = [NSTimer scheduledTimerWithTimeInterval:1
                                                          repeats:YES
                                                            block:^(__unused NSTimer *timer) {
                                                              [weakSelf updateCountdown];
                                                            }];
}
- (void)updateCountdown {
    self.countdown--;
    self.alert.message = [NSString stringWithFormat:@"%@\n%ld 秒后关闭", self.messageLabel.text, (long)self.countdown];
    if (self.countdown <= 0)
        [self confirmTapped];
}
- (void)confirmTapped {
    [self.countdownTimer invalidate];
    self.countdownTimer = nil;
    [self.alert dismissViewControllerAnimated:YES
                                   completion:^{
                                     exit(0);
                                   }];
}
- (void)dismiss {
    [self.countdownTimer invalidate];
    self.countdownTimer = nil;
    [self.alert dismissViewControllerAnimated:YES completion:nil];
}
- (void)dealloc {
    [self.countdownTimer invalidate];
}
@end
