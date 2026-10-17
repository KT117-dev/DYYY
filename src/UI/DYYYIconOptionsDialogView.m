#import "DYYYIconOptionsDialogView.h"
#import "DYYYSettingsCoordinator.h"
#import "DYYYSettingsHelper.h"

@interface DYYYIconOptionsDialogView ()
@property(nonatomic, weak) UIAlertController *alert;
@end
@implementation DYYYIconOptionsDialogView
- (instancetype)initWithTitle:(NSString *)title previewImage:(UIImage *)image {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.titleLabel = [UILabel new];
        self.titleLabel.text = title;
        self.previewImageView = [[UIImageView alloc] initWithImage:image];
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
    UIViewController *presenter = DYYYSettingsCoordinator.presenter;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.titleLabel.text
                                                                   message:self.previewImageView.image ? @"已使用自定义图标" : @"当前使用默认图标"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    self.alert = alert;
    void (^select)(void) = self.onSelect;
    void (^clear)(void) = self.onClear;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"选择或更换图标"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *a) {
                                              [weakAlert dismissViewControllerAnimated:YES completion:select];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复默认图标"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *a) {
                                              [weakAlert dismissViewControllerAnimated:YES completion:clear];
                                            }]];
    UIImage *image = self.previewImageView.image;
    if (image)
        [alert addAction:[UIAlertAction actionWithTitle:@"预览当前图标"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *a) {
                                                  [weakAlert dismissViewControllerAnimated:YES
                                                                                completion:^{
                                                                                  UIViewController *preview = [UIViewController new];
                                                                                  preview.title = @"图标预览";
                                                                                  preview.view.backgroundColor = UIColor.systemBackgroundColor;
                                                                                  UIImageView *view = [[UIImageView alloc] initWithImage:image];
                                                                                  view.contentMode = UIViewContentModeScaleAspectFit;
                                                                                  view.translatesAutoresizingMaskIntoConstraints = NO;
                                                                                  [preview.view addSubview:view];
                                                                                  [NSLayoutConstraint activateConstraints:@[
                                                                                      [view.leadingAnchor constraintEqualToAnchor:preview.view.safeAreaLayoutGuide.leadingAnchor constant:24],
                                                                                      [view.trailingAnchor constraintEqualToAnchor:preview.view.safeAreaLayoutGuide.trailingAnchor constant:-24],
                                                                                      [view.topAnchor constraintEqualToAnchor:preview.view.safeAreaLayoutGuide.topAnchor constant:24],
                                                                                      [view.bottomAnchor constraintEqualToAnchor:preview.view.safeAreaLayoutGuide.bottomAnchor constant:-24]
                                                                                  ]];
                                                                                  [DYYYSettingsCoordinator.navigationController pushViewController:preview animated:YES];
                                                                                }];
                                                }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [DYYYSettingsCoordinator configurePopover:alert from:presenter];
    [presenter presentViewController:alert animated:YES completion:nil];
}
- (void)dismiss {
    [self.alert dismissViewControllerAnimated:YES completion:nil];
}
@end
