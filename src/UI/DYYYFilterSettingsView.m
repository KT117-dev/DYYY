#import "DYYYFilterSettingsView.h"
#import "DYYYSettingsCoordinator.h"
#import "DYYYSettingsHelper.h"

@interface DYYYNativeFilterController : UIViewController
@property(nonatomic, copy) NSString *text, *propName;
@property(nonatomic, strong) UITextView *textView;
@property(nonatomic, copy) void (^confirmed)(NSString *);
@property(nonatomic, copy) void (^cancelled)(void), (^keywords)(void);
@end
@implementation DYYYNativeFilterController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.textView = [UITextView new];
    self.textView.text = self.text;
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.textView.adjustsFontForContentSizeCategory = YES;
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.textView];
    UILabel *hint = [UILabel new];
    hint.text = @"使用系统文本选择，选中要过滤的词句后点“过滤选中内容”。";
    hint.numberOfLines = 0;
    hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    hint.textColor = UIColor.secondaryLabelColor;
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:hint];
    [NSLayoutConstraint activateConstraints:@[
        [hint.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [hint.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [hint.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16], [self.textView.leadingAnchor constraintEqualToAnchor:hint.leadingAnchor],
        [self.textView.trailingAnchor constraintEqualToAnchor:hint.trailingAnchor], [self.textView.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:12],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"过滤选中内容" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    NSMutableArray *toolbar = [NSMutableArray array];
    if (self.keywords)
        [toolbar addObject:[[UIBarButtonItem alloc] initWithTitle:@"管理关键词" style:UIBarButtonItemStylePlain target:self action:@selector(openKeywords)]];
    if (self.propName.length)
        [toolbar addObject:[[UIBarButtonItem alloc] initWithTitle:@"切换拍同款过滤" style:UIBarButtonItemStylePlain target:self action:@selector(toggleProp)]];
    self.toolbarItems = toolbar;
    [self.navigationController setToolbarHidden:toolbar.count == 0 animated:NO];
}
- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:self.cancelled];
}
- (void)save {
    NSRange range = self.textView.selectedRange;
    if (!range.length || NSMaxRange(range) > self.text.length)
        return;
    NSString *selected = [self.text substringWithRange:range];
    void (^confirm)(NSString *) = self.confirmed;
    [self dismissViewControllerAnimated:YES
                             completion:^{
                               if (confirm)
                                   confirm(selected);
                             }];
}
- (void)openKeywords {
    [self dismissViewControllerAnimated:YES completion:self.keywords];
}
- (void)toggleProp {
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:@"DYYYFilterProp"] ?: @"";
    NSMutableArray *words = saved.length ? [[saved componentsSeparatedByString:@","] mutableCopy] : [NSMutableArray array];
    if ([words containsObject:self.propName])
        [words removeObject:self.propName];
    else
        [words addObject:self.propName];
    [DYYYSettingsHelper setUserDefaults:[words componentsJoinedByString:@","] forKey:@"DYYYFilterProp"];
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
}
@end
@interface DYYYFilterSettingsView ()
@property(nonatomic, copy) NSString *editorTitle, *text, *propName;
@property(nonatomic, weak) UIViewController *editor;
@end
@implementation DYYYFilterSettingsView
- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text {
    return [self initWithTitle:title text:text propName:nil];
}
- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text propName:(NSString *)propName {
    if ((self = [super initWithFrame:CGRectZero])) {
        _editorTitle = title;
        _text = text;
        _propName = propName;
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
    DYYYNativeFilterController *editor = [DYYYNativeFilterController new];
    editor.title = self.editorTitle;
    editor.text = self.text;
    editor.propName = self.propName;
    editor.confirmed = self.onConfirm;
    editor.cancelled = self.onCancel;
    editor.keywords = self.onKeywordFilterTap;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    self.editor = nav;
    [DYYYSettingsCoordinator.presenter presentViewController:nav animated:YES completion:nil];
}
- (void)dismiss {
    [self.editor dismissViewControllerAnimated:YES completion:nil];
}
@end
