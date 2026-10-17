#import "DYYYCustomInputView.h"
#import "DYYYSettingsCoordinator.h"
#import "DYYYSettingsHelper.h"

@interface DYYYNativeTextEditor : UIViewController
@property(nonatomic, copy) NSString *initialText;
@property(nonatomic, copy) void (^saved)(NSString *);
@property(nonatomic, copy) void (^cancelled)(void);
@property(nonatomic, strong) UITextView *editor;
@end
@implementation DYYYNativeTextEditor
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.editor = [UITextView new];
    self.editor.text = self.initialText;
    self.editor.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.editor.adjustsFontForContentSizeCategory = YES;
    self.editor.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.editor];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    NSMutableArray *constraints = [@[
        [self.editor.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16], [self.editor.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16],
        [self.editor.topAnchor constraintEqualToAnchor:guide.topAnchor constant:12]
    ] mutableCopy];
    if (@available(iOS 15.0, *))
        [constraints addObject:[self.editor.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor]];
    else
        [constraints addObject:[self.editor.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]];
    [NSLayoutConstraint activateConstraints:constraints];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)];
}
- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:self.cancelled];
}
- (void)save {
    NSString *text = self.editor.text ?: @"";
    void (^saved)(NSString *) = self.saved;
    [self dismissViewControllerAnimated:YES
                             completion:^{
                               if (saved)
                                   saved(text);
                             }];
}
@end

@interface DYYYCustomInputView ()
@property(nonatomic, weak) UIAlertController *alert;
@end
@implementation DYYYCustomInputView
- (instancetype)initWithTitle:(NSString *)title {
    return [self initWithTitle:title defaultText:nil placeholder:nil];
}
- (instancetype)initWithTitle:(NSString *)title defaultText:(NSString *)text {
    return [self initWithTitle:title defaultText:text placeholder:nil];
}
- (instancetype)initWithTitle:(NSString *)title defaultText:(NSString *)text placeholder:(NSString *)placeholder {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.titleLabel = [UILabel new];
        self.titleLabel.text = title;
        self.defaultText = [text isKindOfClass:NSString.class] ? text : [text description];
        self.placeholderText = placeholder;
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
    if ([self.defaultText containsString:@"\n"] || [self.titleLabel.text containsString:@"评论内容"] || [self.titleLabel.text containsString:@"文案内容"]) {
        DYYYNativeTextEditor *editor = [DYYYNativeTextEditor new];
        editor.title = self.titleLabel.text;
        editor.initialText = self.defaultText;
        editor.saved = self.onConfirm;
        editor.cancelled = self.onCancel;
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:editor];
        [DYYYSettingsCoordinator.presenter presentViewController:navigation animated:YES completion:nil];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.titleLabel.text message:nil preferredStyle:UIAlertControllerStyleAlert];
    self.alert = alert;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
      field.text = self.defaultText;
      field.placeholder = self.placeholderText;
      field.clearButtonMode = UITextFieldViewModeWhileEditing;
      field.autocapitalizationType = UITextAutocapitalizationTypeNone;
      field.autocorrectionType = UITextAutocorrectionTypeNo;
      self.inputTextField = field;
    }];
    UITextField *field = alert.textFields.firstObject;
    field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    field.adjustsFontForContentSizeCategory = YES;
    if ([self.titleLabel.text containsString:@"URL"] || [self.titleLabel.text containsString:@"接口"] || [self.titleLabel.text containsString:@"地址"])
        field.keyboardType = UIKeyboardTypeURL;
    else if ([self.placeholderText containsString:@"数字"] || [self.placeholderText containsString:@"天"] || [self.titleLabel.text containsString:@"低赞"])
        field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    void (^confirm)(NSString *) = self.onConfirm;
    void (^cancel)(void) = self.onCancel;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *a) {
                                              [weakAlert dismissViewControllerAnimated:YES completion:cancel];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *a) {
                                              NSString *text = weakAlert.textFields.firstObject.text ?: @"";
                                              [weakAlert dismissViewControllerAnimated:YES
                                                                            completion:^{
                                                                              if (confirm)
                                                                                  confirm(text);
                                                                            }];
                                            }]];
    [DYYYSettingsCoordinator.presenter presentViewController:alert animated:YES completion:nil];
}
- (void)dismiss {
    [self.alert dismissViewControllerAnimated:YES completion:nil];
}
@end
