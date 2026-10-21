#import "DYYYAboutDialogView.h"
#import "DYYYSettingsCoordinator.h"
#import "DYYYSettingsHelper.h"

@interface DYYYNativeAboutController : UIViewController
@property(nonatomic, copy) NSString *message;
@property(nonatomic, copy) void (^confirmed)(void);
@end
@implementation DYYYNativeAboutController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBar.tintColor = UIColor.labelColor;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UITextView *text = [UITextView new];
    text.text = self.message;
    text.editable = NO;
    text.selectable = YES;
    text.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    text.adjustsFontForContentSizeCategory = YES;
    text.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:text];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [text.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16], [text.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16],
        [text.topAnchor constraintEqualToAnchor:guide.topAnchor constant:12], [text.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]
    ]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
}
- (void)done {
    [self dismissViewControllerAnimated:YES completion:self.confirmed];
}
@end

@interface DYYYAboutDialogView ()
@property(nonatomic, weak) UIViewController *alert;
@end
@implementation DYYYAboutDialogView
- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.titleLabel = [UILabel new];
        self.titleLabel.text = title;
        self.messageTextView = [UITextView new];
        self.messageTextView.text = message;
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
    if (self.messageTextView.text.length > 400) {
        DYYYNativeAboutController *about = [DYYYNativeAboutController new];
        about.title = self.titleLabel.text;
        about.message = self.messageTextView.text;
        about.confirmed = self.onConfirm;
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:about];
        self.alert = navigation;
        [DYYYSettingsCoordinator.presenter presentViewController:navigation animated:YES completion:nil];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.titleLabel.text message:self.messageTextView.text preferredStyle:UIAlertControllerStyleAlert];
    self.alert = alert;
    alert.view.tintColor = UIColor.labelColor;
    void (^confirm)(void) = self.onConfirm;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"好"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *a) {
                                              [weakAlert dismissViewControllerAnimated:YES completion:confirm];
                                            }]];
    [DYYYSettingsCoordinator.presenter presentViewController:alert animated:YES completion:nil];
}
- (void)dismiss {
    [self.alert dismissViewControllerAnimated:YES completion:nil];
}
- (void)confirmTapped {
    [self.alert dismissViewControllerAnimated:YES completion:self.onConfirm];
}
@end
