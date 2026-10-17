#import "DYYYSettingViewController.h"
#import <objc/runtime.h>
#import "DYYYConstants.h"
#import "DYYYSettingsCoordinator.h"
#import "DYYYSettingsHelper.h"
#import "DYYYSettingsRegistry.h"
#import "DYYYUtils.h"

@interface DYYYNativeValueEditor : UIViewController
@property(nonatomic, copy) NSString *initialText;
@property(nonatomic, copy) void (^saved)(NSString *);
@property(nonatomic, strong) UITextField *field;
@property(nonatomic) BOOL scale;
@property(nonatomic) BOOL integerThreshold;
@end
@implementation DYYYNativeValueEditor
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.field = [UITextField new];
    self.field.text = self.initialText;
    self.field.borderStyle = UITextBorderStyleRoundedRect;
    self.field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    self.field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.field.adjustsFontForContentSizeCategory = YES;
    self.field.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.field.placeholder = self.integerThreshold ? @"非负整数，0 表示关闭" : @"精确数值；留空使用原默认值";
    if (self.integerThreshold)
        self.field.keyboardType = UIKeyboardTypeNumberPad;
    UIStepper *stepper = [UIStepper new];
    stepper.minimumValue = -1;
    stepper.maximumValue = 1;
    stepper.value = 0;
    [stepper addTarget:self action:@selector(step:) forControlEvents:UIControlEventValueChanged];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ self.field, stepper ]];
    row.spacing = 16;
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [row.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [row.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20], [self.field.heightAnchor constraintGreaterThanOrEqualToConstant:44]
    ]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)];
}
- (void)step:(UIStepper *)stepper {
    double value = self.field.text.doubleValue + stepper.value * (self.scale ? 0.1 : 1);
    stepper.value = 0;
    if (isfinite(value))
        self.field.text = [NSString stringWithFormat:@"%.15g", value];
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
}
- (void)save {
    NSString *text = [self.field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    double value;
    NSScanner *scanner = [NSScanner scannerWithString:text];
    if (self.integerThreshold && text.length) {
        long long integer;
        if (![scanner scanLongLong:&integer] || !scanner.isAtEnd || integer < 0) {
            [DYYYUtils showToast:@"请输入非负整数，0 表示关闭"];
            return;
        }
        if (self.saved)
            self.saved([NSString stringWithFormat:@"%lld", integer]);
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    if (text.length && (![scanner scanDouble:&value] || !scanner.isAtEnd || !isfinite(value))) {
        [DYYYUtils showToast:@"请输入有限数值，可使用负数或小数"];
        return;
    }
    if (self.saved)
        self.saved(text);
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface DYYYSettingViewController () <UISearchResultsUpdating, UIColorPickerViewControllerDelegate>
@property(nonatomic, copy) NSArray<DYYYSettingsSection *> *sourceSections;
@property(nonatomic, copy) NSArray<DYYYSettingsSection *> *visibleSections;
@property(nonatomic, copy) NSString *tab;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, strong) id changeToken;
@property(nonatomic, strong) DYYYSettingDescriptor *colorItem;
@property(nonatomic) BOOL refreshPending;
@end

@implementation DYYYSettingViewController
- (instancetype)initWithTab:(NSString *)tab {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _tab = tab;
        self.title = tab;
    }
    return self;
}
- (instancetype)initWithSections:(NSArray *)sections title:(NSString *)title {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _sourceSections = sections;
        self.title = title;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 66;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:DYYYSettingsCoordinator.class action:@selector(closeSettings)];
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"搜索名称、旧标题、分类或配置键";
    self.navigationItem.searchController = self.search;
    self.definesPresentationContext = YES;
    [self prepareSections];
    __weak typeof(self) weakSelf = self;
    self.changeToken = [NSNotificationCenter.defaultCenter addObserverForName:DYYYSettingsDidChangeNotification
                                                                       object:nil
                                                                        queue:nil
                                                                   usingBlock:^(__unused NSNotification *note) {
                                                                     dispatch_async(dispatch_get_main_queue(), ^{
                                                                       [weakSelf refreshVisibleRows];
                                                                     });
                                                                   }];
}
- (void)dealloc {
    if (self.changeToken)
        [NSNotificationCenter.defaultCenter removeObserver:self.changeToken];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if ([self.tab isEqual:@"总览"] && !self.search.isActive) {
        [self prepareSections];
        [self.tableView reloadData];  // 返回总览时同步最近修改；依赖变化不走此路径。
    }
    [self refreshVisibleRows];
}
- (DYYYSettingsSection *)section:(NSString *)title items:(NSArray *)items {
    DYYYSettingsSection *section = [DYYYSettingsSection new];
    section.sectionHeaderTitle = title;
    section.itemArray = items;
    return section;
}
- (void)prepareSections {
    DYYYSettingsRegistry *registry = DYYYSettingsRegistry.current;
    if (self.sourceSections) {
        self.visibleSections = self.sourceSections;
        return;
    }
    NSMutableArray *sections = [NSMutableArray array];
    if ([self.tab isEqual:@"总览"]) {
        DYYYSettingsSection *summary = [self section:@"DYYY · " DYYY_VERSION items:@[]];
        summary.sectionFooterTitle = @"双指长按打开设置。所有选项直接读写现有配置，关闭后继续浏览。";
        [sections addObject:summary];
        NSMutableArray *common = [NSMutableArray array];
        for (NSString *key in @[ @"DYYYEnableFullScreen", @"DYYYDefaultSpeed", @"DYYYEnableCommentBlur", @"DYYYEnableTabBarLiquidGlass" ]) {
            DYYYSettingDescriptor *item = [registry itemForIdentifier:key];
            if (item)
                [common addObject:item];
        }
        [sections addObject:[self section:@"常用设置" items:common]];
        NSMutableArray *recent = [NSMutableArray array];
        for (NSString *key in [NSUserDefaults.standardUserDefaults arrayForKey:@"DYYYRecentSettings"]) {
            DYYYSettingDescriptor *item = [registry itemForIdentifier:key];
            if (item)
                [recent addObject:item];
        }
        if (recent.count)
            [sections addObject:[self section:@"最近修改" items:recent]];
        NSMutableArray *enabled = [NSMutableArray array];
        for (DYYYSettingDescriptor *item in registry.allItems) {
            if ([item.tab isEqual:@"净化"] && [item.controlType isEqual:@"switch"] && item.isSwitchOn)
                [enabled addObject:item];
        }
        if (enabled.count) {
            DYYYSettingsSection *active = [self section:[NSString stringWithFormat:@"已启用的净化 · %lu 项", (unsigned long)enabled.count]
                                                  items:[enabled subarrayWithRange:NSMakeRange(0, MIN(5, enabled.count))]];
            active.sectionFooterTitle = @"这里显示前五项；完整列表可从净化分类或搜索进入。";
            [sections addObject:active];
        }
    }
    NSArray *tabs = [self.tab isEqual:@"总览"] ? @[ @"播放", @"外观", @"净化", @"工具" ] : @[ self.tab ];
    for (NSString *tab in tabs) {
        NSMutableArray *links = [NSMutableArray array];
        for (DYYYSettingsSection *section in [registry sectionsForTab:tab]) {
            DYYYSettingDescriptor *link = [DYYYSettingDescriptor new];
            link.identifier = [@"navigation:" stringByAppendingString:section.sectionHeaderTitle];
            link.title = section.sectionHeaderTitle;
            link.detail = [NSString stringWithFormat:@"%lu 项", (unsigned long)section.itemArray.count];
            link.controlType = @"navigation";
            link.children = @[ section ];
            [links addObject:link];
        }
        if (links.count)
            [sections addObject:[self section:tab items:links]];
    }
    self.visibleSections = sections;
}
- (void)refreshVisibleRows {
    if (!self.isViewLoaded || self.refreshPending)
        return;
    self.refreshPending = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      typeof(self) self = weakSelf;
      if (!self)
          return;
      self.refreshPending = NO;
      [DYYYSettingsRegistry.current refreshDependencies];
      if (self.tableView.isTracking || self.tableView.isDragging)
          return;
      NSArray *paths = self.tableView.indexPathsForVisibleRows;
      if (paths.count)
          [self.tableView reloadRowsAtIndexPaths:paths withRowAnimation:UIAccessibilityIsReduceMotionEnabled() ? UITableViewRowAnimationNone : UITableViewRowAnimationFade];
    });
}
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *query = [controller.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!query.length)
        [self prepareSections];
    else {
        NSMutableArray *found = [NSMutableArray array];
        for (DYYYSettingDescriptor *item in DYYYSettingsRegistry.current.allItems) {
            NSString *text = [NSString stringWithFormat:@"%@ %@ %@ %@ %@", item.title, item.subTitle ?: @"", item.identifier, item.category, [item.aliases componentsJoinedByString:@" "]];
            if ([text rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound)
                [found addObject:item];
        }
        self.visibleSections = @[ [self section:found.count ? @"搜索结果" : @"没有匹配的设置" items:found] ];
    }
    [self.tableView reloadData];  // 搜索改变数据集；开关和依赖更新仅刷新可见行。
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.visibleSections.count;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visibleSections[section].itemArray.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.visibleSections[section].sectionHeaderTitle;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.visibleSections[section].sectionFooterTitle;
}
- (DYYYSettingDescriptor *)itemAt:(NSIndexPath *)path {
    return self.visibleSections[path.section].itemArray[path.row];
}
- (NSString *)valueForItem:(DYYYSettingDescriptor *)item {
    if ([item.controlType isEqual:@"navigation"])
        return item.detail;
    if (item.assetFilename.length) {
        NSString *folder = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"DYYY"];
        return [NSFileManager.defaultManager fileExistsAtPath:[folder stringByAppendingPathComponent:item.assetFilename]] ? @"已设置自定义图标" : @"默认图标";
    }
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:item.identifier];
    if (stored && ![item.controlType isEqual:@"switch"])
        return [stored description];
    return [item.detail isKindOfClass:NSString.class] && item.detail.length ? item.detail : @"默认";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    DYYYSettingDescriptor *item = [self itemAt:path];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.accessibilityIdentifier = item.identifier;
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.text = item.title;
    content.secondaryText = self.search.searchBar.text.length ? [NSString stringWithFormat:@"%@ · %@", item.tab, item.category] : item.subTitle;
    content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    content.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.secondaryTextProperties.numberOfLines = 0;
    NSString *symbol = [item.controlType isEqual:@"switch"]       ? @"switch.2"
                       : [item.controlType isEqual:@"color"]      ? @"paintpalette"
                       : [item.controlType isEqual:@"slider"]     ? @"slider.horizontal.3"
                       : [item.controlType isEqual:@"navigation"] ? @"folder"
                                                                  : @"gearshape";
    content.image = [UIImage systemImageNamed:symbol];
    content.imageProperties.tintColor = UIColor.systemBlueColor;
    cell.contentConfiguration = content;
    if (item.assetFilename.length) {
        NSString *folder = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"DYYY"];
        NSString *file = [folder stringByAppendingPathComponent:item.assetFilename];
        __weak UITableViewCell *weakCell = cell;
        NSString *identifier = item.identifier;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
          UIImage *image = [UIImage imageWithContentsOfFile:file];
          void (^apply)(UIImage *) = ^(UIImage *preview) {
            if (!preview)
                return;
            dispatch_async(dispatch_get_main_queue(), ^{
              UITableViewCell *target = weakCell;
              if (![target.accessibilityIdentifier isEqual:identifier])
                  return;
              UIListContentConfiguration *configuration = [(UIListContentConfiguration *)target.contentConfiguration copy];
              configuration.image = [preview imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
              configuration.imageProperties.maximumSize = CGSizeMake(32, 32);
              target.contentConfiguration = configuration;
            });
          };
          if (@available(iOS 15.0, *))
              [image prepareThumbnailOfSize:CGSizeMake(32, 32) completionHandler:apply];
          else
              apply(image);
        });
    }
    cell.contentView.alpha = item.isEnable ? 1 : 0.45;
    if ([item.controlType isEqual:@"switch"]) {
        UISwitch *control = [UISwitch new];
        control.on = item.isSwitchOn;
        control.enabled = item.isEnable;
        control.accessibilityIdentifier = item.identifier;
        control.accessibilityLabel = item.title;
        [control addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = control;
    } else if ([item.controlType isEqual:@"slider"] || [item.controlType isEqual:@"size"]) {
        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 4;
        UILabel *value = [UILabel new];
        value.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        value.textAlignment = NSTextAlignmentRight;
        BOOL size = [item.controlType isEqual:@"size"];
        UISlider *slider = [UISlider new];
        slider.minimumValue = size ? 20 : 0;
        slider.maximumValue = size ? 60 : 1;
        id stored = [NSUserDefaults.standardUserDefaults objectForKey:item.identifier];
        slider.value = stored ? [stored floatValue] : size ? ([item.identifier isEqual:@"DYYYSpeedButtonSize"] ? 32 : 40) : ([item.identifier isEqual:@"DYYYSheetBlurTransparent"] ? 0.9 : 1);
        slider.enabled = item.isEnable;
        slider.accessibilityIdentifier = item.identifier;
        slider.accessibilityLabel = item.title;
        objc_setAssociatedObject(slider, @selector(sliderChanged:), value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self sliderChanged:slider];
        [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [slider addTarget:self action:@selector(sliderEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
        [reset setImage:[UIImage systemImageNamed:@"arrow.counterclockwise"] forState:UIControlStateNormal];
        reset.accessibilityLabel = [@"恢复默认值：" stringByAppendingString:item.title];
        [reset addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
                 [DYYYSettingsRegistry.current resetItem:item];
               }]
            forControlEvents:UIControlEventTouchUpInside];
        UIStackView *valueRow = [[UIStackView alloc] initWithArrangedSubviews:@[ value, reset ]];
        valueRow.spacing = 8;
        [stack addArrangedSubview:valueRow];
        [stack addArrangedSubview:slider];
        stack.frame = CGRectMake(0, 0, 136, 52);
        cell.accessoryView = stack;
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if ([item.controlType isEqual:@"color"]) {
            UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 26, 26)];
            swatch.layer.cornerRadius = 13;
            swatch.backgroundColor = [DYYYUtils colorFromSchemeHexString:[self valueForItem:item] targetWidth:26] ?: UIColor.secondaryLabelColor;
            swatch.layer.borderColor = UIColor.separatorColor.CGColor;
            swatch.layer.borderWidth = 0.5;
            cell.accessoryView = swatch;
        } else {
            content.secondaryText = [@[ content.secondaryText ?: @"", [self valueForItem:item] ] componentsJoinedByString:@"\n"];
            cell.contentConfiguration = content;
        }
    }
    return cell;
}
- (void)toggle:(UISwitch *)sender {
    DYYYSettingDescriptor *item = [DYYYSettingsRegistry.current itemForIdentifier:sender.accessibilityIdentifier];
    if (!item.isEnable)
        return;
    if (item.switchChangedBlock)
        item.switchChangedBlock();
    else
        [DYYYSettingsRegistry.current setValue:@(sender.on) forItem:item];
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    [self refreshVisibleRows];
}
- (void)sliderChanged:(UISlider *)slider {
    UILabel *value = objc_getAssociatedObject(slider, @selector(sliderChanged:));
    if ([slider.accessibilityIdentifier isEqual:@"DYYYSheetBlurTransparent"] && slider.value <= 0) {
        value.text = @"默认 90%";
        return;
    }
    value.text = slider.maximumValue > 1 ? [NSString stringWithFormat:@"%.0f pt", slider.value] : [NSString stringWithFormat:@"%.0f%%", slider.value * 100];
}
- (void)sliderEnded:(UISlider *)slider {
    DYYYSettingDescriptor *item = [DYYYSettingsRegistry.current itemForIdentifier:slider.accessibilityIdentifier];
    [DYYYSettingsRegistry.current setValue:[NSString stringWithFormat:@"%.6g", slider.value] forItem:item];
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    DYYYSettingDescriptor *item = [self itemAt:path];
    if (!item.isEnable)
        return;
    if ([item.controlType isEqual:@"compatibility"]) {
        [DYYYSettingsHelper showAboutDialog:item.title message:item.subTitle onConfirm:nil];
        return;
    }
    if (item.children.count) {
        [self.navigationController pushViewController:[[DYYYSettingViewController alloc] initWithSections:item.children title:item.title] animated:YES];
        return;
    }
    if (self.search.isActive && self.search.searchBar.text.length) {
        self.search.searchBar.text = @"";
        self.search.active = NO;
        [self.navigationController pushViewController:[[DYYYSettingViewController alloc] initWithSections:@[ [self section:item.category items:@[ item ]] ] title:item.title] animated:YES];
        return;
    }
    if ([item.controlType isEqual:@"switch"])
        return;
    if ([item.controlType isEqual:@"number"]) {
        DYYYNativeValueEditor *editor = [DYYYNativeValueEditor new];
        editor.title = item.title;
        editor.initialText = [[NSUserDefaults.standardUserDefaults objectForKey:item.identifier] description] ?: @"";
        editor.scale = [item.identifier containsString:@"Scale"];
        editor.integerThreshold = [@[ @"DYYYFilterLowLikes", @"DYYYFilterTimeLimit" ] containsObject:item.identifier];
        editor.saved = ^(NSString *text) {
          [DYYYSettingsRegistry.current setValue:text forItem:item];
        };
        [self.navigationController pushViewController:editor animated:YES];
        return;
    }
    if ([item.controlType isEqual:@"color"]) {
        self.colorItem = item;
        UIColorPickerViewController *picker = [UIColorPickerViewController new];
        picker.delegate = self;
        picker.supportsAlpha = NO;
        UIColor *initial = [DYYYUtils colorFromSchemeHexString:[self valueForItem:item] targetWidth:26];
        CGFloat r, g, b, a;
        picker.selectedColor = [initial getRed:&r green:&g blue:&b alpha:&a] ? initial : UIColor.systemBlueColor;
        [self presentViewController:picker animated:YES completion:nil];
        return;
    }
    void (^action)(void) = item.cellTappedBlock;
    if (!action) {
        [self editExactValue:item];
        return;
    }
    if ([@[ @"DYYYCleanCache", @"DYYYRestoreSettings", @"DeleteABTestConfigFile", @"LoadABTestConfigFile" ] containsObject:item.identifier]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:item.title message:@"此操作会修改已有数据。请确认已保存需要保留的内容。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"继续"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction *a) {
                                                  action();
                                                }]];
        [self presentViewController:alert animated:YES completion:nil];
    } else
        action();
}
- (void)editExactValue:(DYYYSettingDescriptor *)item {
    [DYYYSettingsHelper showTextInputAlert:item.title
                               defaultText:[NSUserDefaults.standardUserDefaults objectForKey:item.identifier]
                               placeholder:item.subTitle
                                 onConfirm:^(NSString *text) {
                                   [DYYYSettingsRegistry.current setValue:text forItem:item];
                                 }
                                  onCancel:nil];
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)controller {
    CGFloat r, g, b, a;
    if (![controller.selectedColor getRed:&r green:&g blue:&b alpha:&a])
        return;
    NSString *hex = [NSString stringWithFormat:@"#%02X%02X%02X", (int)round(r * 255), (int)round(g * 255), (int)round(b * 255)];
    [DYYYSettingsRegistry.current setValue:hex forItem:self.colorItem];
    self.colorItem = nil;
}
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)path point:(CGPoint)point {
    DYYYSettingDescriptor *item = [self itemAt:path];
    if ([item.controlType isEqual:@"navigation"] || [item.controlType isEqual:@"compatibility"] || [item.controlType isEqual:@"action"])
        return nil;
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray *suggested) {
                                                      UIAction *reset = [UIAction actionWithTitle:@"恢复默认值"
                                                                                            image:[UIImage systemImageNamed:@"arrow.counterclockwise"]
                                                                                       identifier:nil
                                                                                          handler:^(__unused UIAction *a) {
                                                                                            [DYYYSettingsRegistry.current resetItem:item];
                                                                                          }];
                                                      UIAction *exact = [UIAction actionWithTitle:@"精确输入（支持原有特殊值）"
                                                                                            image:[UIImage systemImageNamed:@"keyboard"]
                                                                                       identifier:nil
                                                                                          handler:^(__unused UIAction *a) {
                                                                                            [weakSelf editExactValue:item];
                                                                                          }];
                                                      return [UIMenu menuWithChildren:[item.controlType isEqual:@"switch"] ? @[ reset ] : @[ exact, reset ]];
                                                    }];
}
@end
