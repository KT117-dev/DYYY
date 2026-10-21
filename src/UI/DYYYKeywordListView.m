#import "DYYYKeywordListView.h"
#import "DYYYSettingsCoordinator.h"
#import "DYYYSettingsHelper.h"

@interface DYYYNativeKeywordController : UITableViewController
@property(nonatomic, strong) NSMutableArray<NSString *> *keywords;
@property(nonatomic, copy) void (^confirm)(NSArray *);
@property(nonatomic, copy) void (^cancelled)(void);
@property(nonatomic, copy) NSString *addTitle, *editTitle, *placeholder;
@end
@implementation DYYYNativeKeywordController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBar.tintColor = UIColor.labelColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(save)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add)]
    ];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 50;
    [self updateEmpty];
}
- (void)updateEmpty {
    UILabel *empty = [UILabel new];
    empty.text = @"暂无关键词，点 + 添加";
    empty.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    empty.textColor = UIColor.secondaryLabelColor;
    empty.textAlignment = NSTextAlignmentCenter;
    self.tableView.backgroundView = self.keywords.count ? nil : empty;
}
- (void)cancel {
    void (^cancel)(void) = self.cancelled;
    [self dismissViewControllerAnimated:YES completion:cancel];
}
- (void)save {
    NSArray *keywords = [self.keywords copy];
    void (^confirm)(NSArray *) = self.confirm;
    [self dismissViewControllerAnimated:YES
                             completion:^{
                               if (confirm)
                                   confirm(keywords);
                             }];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return self.keywords.count;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = self.keywords[path.row];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    return cell;
}
- (void)edit:(NSInteger)index {
    [DYYYSettingsCoordinator prepareForTextInput];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:index < 0 ? self.addTitle : self.editTitle message:nil preferredStyle:UIAlertControllerStyleAlert];
    alert.view.tintColor = UIColor.labelColor;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
      field.text = index < 0 ? @"" : self.keywords[index];
      field.placeholder = self.placeholder;
      field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
                                              NSString *value = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                                              if (!value.length)
                                                  return;
                                              if (index < 0) {
                                                  [self.keywords addObject:value];
                                                  [self.tableView insertRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:self.keywords.count - 1 inSection:0] ]
                                                                        withRowAnimation:UITableViewRowAnimationAutomatic];
                                              } else {
                                                  self.keywords[index] = value;
                                                  [self.tableView reloadRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:index inSection:0] ] withRowAnimation:UITableViewRowAnimationAutomatic];
                                              }
                                              [self updateEmpty];
                                              [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)add {
    [self edit:-1];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    [self edit:path.row];
}
- (void)tableView:(UITableView *)table commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style == UITableViewCellEditingStyleDelete) {
        [self.keywords removeObjectAtIndex:path.row];
        [table deleteRowsAtIndexPaths:@[ path ] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self updateEmpty];
    }
}
@end
@interface DYYYKeywordListView ()
@property(nonatomic, copy) NSString *editorTitle;
@property(nonatomic, copy) NSArray *initialKeywords;
@property(nonatomic, weak) UIViewController *editor;
@end
@implementation DYYYKeywordListView
- (instancetype)initWithTitle:(NSString *)title keywords:(NSArray *)keywords {
    if ((self = [super initWithFrame:CGRectZero])) {
        _editorTitle = title;
        _initialKeywords = [keywords copy] ?: @[];
        self.addItemTitle = @"添加关键词";
        self.editItemTitle = @"编辑关键词";
        self.inputPlaceholder = @"输入完整关键词";
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
    DYYYNativeKeywordController *editor = [[DYYYNativeKeywordController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    editor.title = self.editorTitle;
    editor.keywords = self.initialKeywords.mutableCopy;
    editor.confirm = self.onConfirm;
    editor.cancelled = self.onCancel;
    editor.addTitle = self.addItemTitle;
    editor.editTitle = self.editItemTitle;
    editor.placeholder = self.inputPlaceholder;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    self.editor = nav;
    [DYYYSettingsCoordinator.presenter presentViewController:nav animated:YES completion:nil];
}
- (void)dismiss {
    [self.editor dismissViewControllerAnimated:YES completion:nil];
}
@end
