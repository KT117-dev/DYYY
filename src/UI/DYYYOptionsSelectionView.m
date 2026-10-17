#import "DYYYOptionsSelectionView.h"
#import "DYYYSettingsCoordinator.h"
#import "DYYYSettingsHelper.h"

@interface DYYYNativeOptionsController : UITableViewController
@property(nonatomic, copy) NSArray<NSString *> *options;
@property(nonatomic, copy) NSString *key;
@property(nonatomic, copy) void (^changed)(NSString *);
@end
@implementation DYYYNativeOptionsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
}
- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return self.options.count;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = self.options[path.row];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.numberOfLines = 0;
    NSString *selected = [NSUserDefaults.standardUserDefaults objectForKey:self.key] ?: self.options.firstObject;
    cell.accessoryType = [selected isEqual:self.options[path.row]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    NSString *value = self.options[path.row];
    [DYYYSettingsHelper setUserDefaults:value forKey:self.key];
    if (self.changed)
        self.changed(value);
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end
@implementation DYYYOptionsSelectionView
+ (NSString *)showWithPreferenceKey:(NSString *)key optionsArray:(NSArray *)options headerText:(NSString *)title onPresentingVC:(UIViewController *)presenter {
    return [self showWithPreferenceKey:key optionsArray:options headerText:title onPresentingVC:presenter selectionChanged:nil];
}
+ (NSString *)showWithPreferenceKey:(NSString *)key
                       optionsArray:(NSArray *)options
                         headerText:(NSString *)title
                     onPresentingVC:(UIViewController *)presenter
                   selectionChanged:(void (^)(NSString *))callback {
    DYYYNativeOptionsController *list = [[DYYYNativeOptionsController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    list.options = options;
    list.title = title;
    list.key = key;
    list.changed = callback;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:list];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    [(presenter ?: DYYYSettingsCoordinator.presenter) presentViewController:navigation animated:YES completion:nil];
    return [NSUserDefaults.standardUserDefaults objectForKey:key] ?: options.firstObject;
}
@end
