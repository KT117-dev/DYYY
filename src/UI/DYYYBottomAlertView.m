#import "DYYYBottomAlertView.h"
#import "DYYYSettingsCoordinator.h"
#import "DYYYSettingsHelper.h"

@implementation DYYYBottomAlertView
+ (UIViewController *)showAlertWithTitle:(NSString *)title
                                 message:(NSString *)message
                               avatarURL:(NSString *)avatarURL
                        cancelButtonText:(NSString *)cancelText
                       confirmButtonText:(NSString *)confirmText
                            cancelAction:(DYYYAlertActionHandler)cancel
                             closeAction:(DYYYAlertActionHandler)close
                           confirmAction:(DYYYAlertActionHandler)confirm {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:cancelText ?: @"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *a) {
                                              [weakAlert dismissViewControllerAnimated:YES completion:cancel ?: close];
                                            }]];
    BOOL destructive = [title containsString:@"删除"] || [title containsString:@"清除"] || [title containsString:@"清理"];
    [alert addAction:[UIAlertAction actionWithTitle:confirmText ?: @"确定"
                                              style:destructive ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *a) {
                                              [weakAlert dismissViewControllerAnimated:YES completion:confirm];
                                            }]];
    if (close && cancelText.length && ![cancelText isEqual:@"取消"])
        [alert addAction:[UIAlertAction actionWithTitle:@"暂不操作"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *a) {
                                                  [weakAlert dismissViewControllerAnimated:YES completion:close];
                                                }]];
    [DYYYSettingsCoordinator.presenter presentViewController:alert animated:YES completion:nil];
    return alert;
}
- (void)dismiss {
    [DYYYSettingsCoordinator.presenter dismissViewControllerAnimated:YES completion:nil];
}
@end
