#import "DYYYSettingViewController.h"
#import <objc/runtime.h>
#import "DYYYConstants.h"
#import "DYYYSettingsCoordinator.h"
#import "DYYYSettingsHelper.h"
#import "DYYYSettingsRegistry.h"
#import "DYYYUtils.h"
#import "DYYYBottomAlertView.h"

@interface DYYYSettingsTableView : UITableView
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, UIView *> *groupBackgrounds;
@end
@implementation DYYYSettingsTableView
- (instancetype)initWithFrame:(CGRect)frame style:(UITableViewStyle)style {
    if ((self = [super initWithFrame:frame style:style])) {
        _groupBackgrounds = [NSMutableDictionary dictionary];
        UIView *mask = [UIView new];
        mask.backgroundColor = UIColor.blackColor;
        mask.layer.cornerRadius = DYYYSettingsCornerRadius;
        mask.layer.cornerCurve = kCACornerCurveContinuous;
        if (@available(iOS 26.0, *))
            mask.cornerConfiguration = [UICornerConfiguration configurationWithRadius:[UICornerRadius fixedRadius:DYYYSettingsCornerRadius]];
        self.maskView = mask;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect clipFrame = self.bounds;
    NSMutableSet<NSNumber *> *sections = [NSMutableSet set];
    for (NSIndexPath *path in self.indexPathsForVisibleRows) {
        NSNumber *section = @(path.section);
        if ([sections containsObject:section])
            continue;
        [sections addObject:section];
        UIView *background = self.groupBackgrounds[section];
        if (!background) {
            background = [UIView new];
            background.layer.cornerRadius = DYYYSettingsCornerRadius;
            background.layer.cornerCurve = kCACornerCurveContinuous;
            background.clipsToBounds = YES;
            background.userInteractionEnabled = NO;
            background.accessibilityElementsHidden = YES;
            UIVisualEffect *effect;
            if (@available(iOS 26.0, *))
                effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
            else
                effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
            UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
            if (@available(iOS 26.0, *))
                glass.cornerConfiguration = [UICornerConfiguration configurationWithRadius:[UICornerRadius fixedRadius:DYYYSettingsCornerRadius]];
            else {
                glass.layer.cornerRadius = DYYYSettingsCornerRadius;
                glass.layer.cornerCurve = kCACornerCurveContinuous;
            }
            glass.frame = background.bounds;
            glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [background addSubview:glass];
            // 只裁去玻璃材质向容器外投出的阴影，保留内部折射。
            [self insertSubview:background atIndex:0];
            self.groupBackgrounds[section] = background;
        }
        CGRect first = [self rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:path.section]];
        CGRect last = [self rectForRowAtIndexPath:[NSIndexPath indexPathForRow:[self numberOfRowsInSection:path.section] - 1 inSection:path.section]];
        UITableViewCell *cell = [self cellForRowAtIndexPath:path];
        CGRect row = [self convertRect:cell.bounds fromView:cell];
        background.frame = CGRectMake(CGRectGetMinX(row), CGRectGetMinY(first), CGRectGetWidth(row), CGRectGetMaxY(last) - CGRectGetMinY(first));
        clipFrame = CGRectMake(CGRectGetMinX(row), CGRectGetMinY(self.bounds), CGRectGetWidth(row), CGRectGetHeight(self.bounds));
    }
    self.maskView.frame = clipFrame;
    for (NSNumber *section in self.groupBackgrounds.allKeys) {
        if (![sections containsObject:section]) {
            [self.groupBackgrounds[section] removeFromSuperview];
            [self.groupBackgrounds removeObjectForKey:section];
        }
    }
}
@end

@interface DYYYNumberControl : UIControl
@property(nonatomic) double value;
@property(nonatomic) double stepValue;
@property(nonatomic) double minimumValue;
@property(nonatomic, strong) UIButton *valueButton;
@property(nonatomic, strong) UIButton *minusButton;
@property(nonatomic, strong) UIButton *plusButton;
@end
@implementation DYYYNumberControl
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 124, 44)])) {
        _valueButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _valueButton.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
        _valueButton.titleLabel.adjustsFontSizeToFitWidth = YES;
        _valueButton.titleLabel.minimumScaleFactor = 0.7;
        [_valueButton setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
        [_valueButton setTitleColor:UIColor.tertiaryLabelColor forState:UIControlStateDisabled];
        [_valueButton addTarget:self action:@selector(edit) forControlEvents:UIControlEventTouchUpInside];
        _minusButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _plusButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_minusButton setImage:[UIImage systemImageNamed:@"minus"] forState:UIControlStateNormal];
        [_plusButton setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
        _minusButton.tag = -1;
        _plusButton.tag = 1;
        [_minusButton addTarget:self action:@selector(change:) forControlEvents:UIControlEventTouchUpInside];
        [_plusButton addTarget:self action:@selector(change:) forControlEvents:UIControlEventTouchUpInside];
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ _minusButton, _valueButton, _plusButton ]];
        stack.frame = self.bounds;
        stack.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:stack];
        [_minusButton.widthAnchor constraintEqualToConstant:44].active = YES;
        [_plusButton.widthAnchor constraintEqualToConstant:44].active = YES;
    }
    return self;
}
- (void)setValue:(double)value {
    _value = value;
    [self.valueButton setTitle:[NSString stringWithFormat:@"%.15g", value] forState:UIControlStateNormal];
    self.valueButton.accessibilityValue = self.valueButton.currentTitle;
    self.minusButton.enabled = self.enabled && value > self.minimumValue;
    self.plusButton.enabled = self.enabled;
}
- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.valueButton.enabled = enabled;
    self.value = self.value;
}
- (void)change:(UIButton *)button {
    double value = MAX(self.minimumValue, self.value + button.tag * self.stepValue);
    if (!self.enabled || !isfinite(value) || value == self.value)
        return;
    self.value = value;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (void)edit {
    if (self.enabled)
        [self sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
}
@end

@interface DYYYSliderSettingCell : UITableViewCell
@property(nonatomic, strong) UIListContentView *heading;
@property(nonatomic, strong) UISlider *slider;
@property(nonatomic, strong) UILabel *value;
@end
@implementation DYYYSliderSettingCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        _heading = [[UIListContentView alloc] initWithConfiguration:[UIListContentConfiguration subtitleCellConfiguration]];
        _slider = [UISlider new];
        _value = [UILabel new];
        _value.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        _value.adjustsFontForContentSizeCategory = YES;
        _value.textColor = UIColor.secondaryLabelColor;
        [_value setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *controls = [[UIStackView alloc] initWithArrangedSubviews:@[ _slider, _value ]];
        controls.spacing = 12;
        controls.alignment = UIStackViewAlignmentCenter;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ _heading, controls ]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = -6;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
            [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [controls.heightAnchor constraintGreaterThanOrEqualToConstant:44]
        ]];
    }
    return self;
}
@end

@interface DYYYSettingViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UIColorPickerViewControllerDelegate>
@property(nonatomic, strong, readwrite) UITableView *tableView;
@property(nonatomic, copy) NSArray<DYYYSettingsSection *> *sourceSections;
@property(nonatomic, copy) NSArray<DYYYSettingsSection *> *visibleSections;
@property(nonatomic, copy) NSString *tab;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, strong) id changeToken;
@property(nonatomic, strong) DYYYSettingDescriptor *colorItem;
@property(nonatomic) BOOL colorChanged;
@property(nonatomic) BOOL refreshPending;
@end

@implementation DYYYSettingViewController
- (instancetype)initWithTab:(NSString *)tab {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _tab = tab;
        self.title = tab;
    }
    return self;
}
- (instancetype)initWithSections:(NSArray *)sections title:(NSString *)title {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _sourceSections = sections;
        self.title = title;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.tableView = [[DYYYSettingsTableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.clipsToBounds = YES;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:10],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-10],
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20]
    ]];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 66;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 16, 0, 16);
    self.tableView.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0, 4, 0, 4);
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 6, 0);
    if (@available(iOS 26.0, *)) {
        self.tableView.topEdgeEffect.hidden = YES;
        self.tableView.bottomEdgeEffect.hidden = YES;
    }
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:DYYYSettingsCoordinator.class action:@selector(closeSettings)];
    if ([self.tab isEqualToString:@"搜索"]) {
        self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
        self.search.searchResultsUpdater = self;
        self.search.obscuresBackgroundDuringPresentation = NO;
        self.search.hidesNavigationBarDuringPresentation = NO;
        self.search.searchBar.placeholder = @"搜索插件设置";
        self.navigationItem.searchController = self.search;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
        self.definesPresentationContext = YES;
    }
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
    self.visibleSections = [registry sectionsForTab:self.tab];
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
      NSMutableArray *changed = [NSMutableArray array];
      for (NSIndexPath *path in self.tableView.indexPathsForVisibleRows) {
          UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:path];
          NSArray *previous = objc_getAssociatedObject(cell, @selector(displayStateForItem:));
          if (![previous isEqual:[self displayStateForItem:[self itemAt:path]]])
              [changed addObject:path];
      }
      if (!changed.count)
          return;
      [UIView performWithoutAnimation:^{
          if (@available(iOS 15.0, *))
              [self.tableView reconfigureRowsAtIndexPaths:changed];
          else
              [self.tableView reloadRowsAtIndexPaths:changed withRowAnimation:UITableViewRowAnimationNone];
          [self.tableView layoutIfNeeded];
      }];
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
    NSString *title = self.visibleSections[section].sectionHeaderTitle;
    return [title isEqualToString:self.title] ? nil : title;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForHeaderInSection:section];
    if (!text.length)
        return nil;
    UIView *header = [UIView new];
    UILabel *title = [UILabel new];
    title.text = text;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.adjustsFontForContentSizeCategory = YES;
    title.textColor = UIColor.labelColor;
    title.accessibilityTraits |= UIAccessibilityTraitHeader;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:title];
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:header.trailingAnchor constant:-16]
    ]];
    return header;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.visibleSections[section].sectionFooterTitle;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [self tableView:tableView titleForHeaderInSection:section].length ? [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline].lineHeight + 16 : CGFLOAT_MIN;
}
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return self.visibleSections[section].sectionFooterTitle.length ? UITableViewAutomaticDimension : CGFLOAT_MIN;
}
- (DYYYSettingDescriptor *)itemAt:(NSIndexPath *)path {
    return self.visibleSections[path.section].itemArray[path.row];
}
- (NSString *)valueForItem:(DYYYSettingDescriptor *)item {
    if (item.assetFilename.length) {
        NSString *folder = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"DYYY"];
        return [NSFileManager.defaultManager fileExistsAtPath:[folder stringByAppendingPathComponent:item.assetFilename]] ? @"已设置自定义图标" : @"默认图标";
    }
    if ([item.controlType isEqual:@"action"])
        return item.detail ?: @"";
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:item.identifier];
    if (stored && ![item.controlType isEqual:@"switch"])
        return [stored description];
    return [item.detail isKindOfClass:NSString.class] && item.detail.length ? item.detail : @"默认";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    DYYYSettingDescriptor *item = [self itemAt:path];
    BOOL hasSlider = [item.controlType isEqual:@"slider"] || [item.controlType isEqual:@"size"];
    Class cellClass = hasSlider ? DYYYSliderSettingCell.class : UITableViewCell.class;
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:path] ?: [[cellClass alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.userInteractionEnabled = YES;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessibilityTraits &= ~UIAccessibilityTraitNotEnabled;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
    cell.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(10, 16, 10, 16);
    cell.accessibilityIdentifier = item.identifier;
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(10, 16, 10, 16);
    content.text = item.title;
    content.secondaryText = self.search.searchBar.text.length ? [NSString stringWithFormat:@"%@ · %@", item.tab, item.category] : item.subTitle;
    content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    content.textProperties.numberOfLines = 0;
    content.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.secondaryTextProperties.numberOfLines = 0;
    NSString *symbol = [item.controlType isEqual:@"switch"]       ? @"switch.2"
                       : [item.controlType isEqual:@"color"]      ? @"paintpalette"
                       : [item.controlType isEqual:@"slider"]     ? @"slider.horizontal.3"
                                                                  : @"gearshape";
    content.image = [UIImage systemImageNamed:symbol];
    content.imageProperties.tintColor = UIColor.systemBlueColor;
    if (hasSlider) {
        content.directionalLayoutMargins = NSDirectionalEdgeInsetsZero;
        ((DYYYSliderSettingCell *)cell).heading.configuration = content;
    } else {
        cell.contentConfiguration = content;
    }
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
    if ([item.controlType isEqual:@"switch"]) {
        UISwitch *control = [cell.accessoryView isKindOfClass:UISwitch.class] ? (UISwitch *)cell.accessoryView : [UISwitch new];
        control.on = item.isSwitchOn;
        control.enabled = item.isEnable;
        control.accessibilityIdentifier = item.identifier;
        control.accessibilityLabel = item.title;
        [control addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = control;
    } else if ([item.controlType isEqual:@"number"]) {
        DYYYNumberControl *stepper = [cell.accessoryView isKindOfClass:DYYYNumberControl.class] ? (DYYYNumberControl *)cell.accessoryView : [DYYYNumberControl new];
        BOOL threshold = [@[ @"DYYYFilterLowLikes", @"DYYYFilterTimeLimit" ] containsObject:item.identifier];
        stepper.minimumValue = threshold ? 0 : -DBL_MAX;
        stepper.stepValue = threshold ? 1 : 0.1;
        NSString *stored = [[NSUserDefaults.standardUserDefaults objectForKey:item.identifier] description];
        double value = [item.identifier containsString:@"Scale"] ? 1 : [item.identifier isEqual:@"DYYYTimelineVerticalPosition"] ? -12.5 : [item.identifier isEqual:@"DYYYIPLabelVerticalOffset"] ? 3 : 0;
        double parsed;
        NSScanner *scanner = [NSScanner scannerWithString:stored ?: @""];
        if ([scanner scanDouble:&parsed] && scanner.isAtEnd && isfinite(parsed) && (!threshold || (parsed >= 0 && floor(parsed) == parsed)))
            value = parsed;
        stepper.value = value;
        stepper.enabled = item.isEnable;
        stepper.accessibilityIdentifier = item.identifier;
        stepper.accessibilityLabel = item.title;
        stepper.minusButton.accessibilityLabel = [item.title stringByAppendingString:@"，减小"];
        stepper.plusButton.accessibilityLabel = [item.title stringByAppendingString:@"，增加"];
        stepper.valueButton.accessibilityLabel = [item.title stringByAppendingString:@"，手动输入"];
        [stepper addTarget:self action:@selector(numberStepped:) forControlEvents:UIControlEventValueChanged];
        [stepper addTarget:self action:@selector(editNumber:) forControlEvents:UIControlEventPrimaryActionTriggered];
        cell.accessoryView = stepper;
        cell.contentConfiguration = content;
    } else if (hasSlider) {
        DYYYSliderSettingCell *sliderCell = (DYYYSliderSettingCell *)cell;
        UILabel *value = sliderCell.value;
        BOOL size = [item.controlType isEqual:@"size"];
        UISlider *slider = sliderCell.slider;
        slider.minimumValue = size ? 20 : 0;
        slider.maximumValue = size ? 60 : 1;
        id stored = [NSUserDefaults.standardUserDefaults objectForKey:item.identifier];
        NSString *glassDefault = DYYYGlassBackdropView.defaultSettings[item.identifier];
        slider.value = stored ? [stored floatValue] : glassDefault ? glassDefault.floatValue : size ? ([item.identifier isEqual:@"DYYYSpeedButtonSize"] ? 32 : 40) : ([item.identifier isEqual:@"DYYYSheetBlurTransparent"] ? 0.9 : 1);
        slider.enabled = item.isEnable;
        slider.accessibilityIdentifier = item.identifier;
        slider.accessibilityLabel = item.title;
        objc_setAssociatedObject(slider, @selector(sliderChanged:), value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self sliderChanged:slider];
        [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [slider addTarget:self action:@selector(sliderEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    } else if (!item.menuProvider) {
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if ([item.controlType isEqual:@"color"]) {
            UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 26, 26)];
            swatch.layer.cornerRadius = 13;
            swatch.backgroundColor = [DYYYUtils colorFromSchemeHexString:[self valueForItem:item] targetWidth:26] ?: UIColor.secondaryLabelColor;
            swatch.layer.borderColor = UIColor.separatorColor.CGColor;
            swatch.layer.borderWidth = 0.5;
            cell.accessoryView = swatch;
        } else if ([item.controlType isEqual:@"action"] && item.detail.length) {
            content.secondaryText = content.secondaryText.length ? [NSString stringWithFormat:@"%@\n%@", content.secondaryText, item.detail] : item.detail;
            cell.contentConfiguration = content;
        } else if (!item.children.count && ![item.controlType isEqual:@"action"]) {
            content.secondaryText = [@[ content.secondaryText ?: @"", [self valueForItem:item] ] componentsJoinedByString:@"\n"];
            cell.contentConfiguration = content;
        }
    }
    if (!item.isEnable) {
        UIListContentConfiguration *disabled = [content copy];
        disabled.textProperties.color = UIColor.secondaryLabelColor;
        disabled.secondaryTextProperties.color = UIColor.tertiaryLabelColor;
        disabled.imageProperties.tintColor = UIColor.tertiaryLabelColor;
        if (hasSlider)
            ((DYYYSliderSettingCell *)cell).heading.configuration = disabled;
        else
            cell.contentConfiguration = disabled;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.userInteractionEnabled = NO;
        cell.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
    }
    objc_setAssociatedObject(cell, @selector(displayStateForItem:), [self displayStateForItem:item], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (item.menuProvider) {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UIButton *button = [cell.accessoryView isKindOfClass:UIButton.class] ? (UIButton *)cell.accessoryView : [UIButton buttonWithType:UIButtonTypeSystem];
        if (@available(iOS 15.0, *)) {
            UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
            configuration.contentInsets = NSDirectionalEdgeInsetsMake(0, 4, 0, 0);
            configuration.titleLineBreakMode = NSLineBreakByTruncatingTail;
            configuration.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
                NSMutableDictionary *result = attributes.mutableCopy;
                result[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
                return result;
            };
            if (@available(iOS 16.0, *))
                configuration.indicator = UIButtonConfigurationIndicatorPopup;
            button.configuration = configuration;
            button.changesSelectionAsPrimaryAction = YES;
        }
        button.showsMenuAsPrimaryAction = YES;
        button.enabled = item.isEnable;
        button.accessibilityIdentifier = item.identifier;
        button.accessibilityLabel = item.title;
        button.accessibilityValue = [self valueForItem:item];
        button.accessibilityHint = item.subTitle;
        button.menu = item.menuProvider();
        [button setTitle:[item.identifier isEqual:@"DYYYABTestModeString"] ? item.detail : [self valueForItem:item] forState:UIControlStateNormal];
        [button sizeToFit];
        button.frame = CGRectMake(0, 0, MIN(CGRectGetWidth(button.bounds), CGRectGetWidth(tableView.bounds) * 0.42), 44);
        cell.accessoryView = button;
        cell.isAccessibilityElement = NO;
    }
    return cell;
}
- (NSArray *)displayStateForItem:(DYYYSettingDescriptor *)item {
    NSString *iconVersion = @"";
    if (item.assetFilename.length) {
        NSString *folder = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"DYYY"];
        iconVersion = [[[NSFileManager.defaultManager attributesOfItemAtPath:[folder stringByAppendingPathComponent:item.assetFilename] error:nil] fileModificationDate] description] ?: @"";
    }
    return @[ @(item.isEnable), @(item.isSwitchOn), [self valueForItem:item] ?: @"", iconVersion ];
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
    if (DYYYGlassBackdropView.defaultSettings[slider.accessibilityIdentifier])
        slider.value = roundf(slider.value * 100) / 100;
    if ([slider.accessibilityIdentifier isEqual:@"DYYYSheetBlurTransparent"] && slider.value <= 0) {
        value.text = @"默认 90%";
        return;
    }
    value.text = slider.maximumValue > 1 ? [NSString stringWithFormat:@"%.0f pt", slider.value] : [NSString stringWithFormat:@"%.0f%%", slider.value * 100];
    slider.accessibilityValue = value.text;
}
- (void)numberStepped:(DYYYNumberControl *)stepper {
    DYYYSettingDescriptor *item = [DYYYSettingsRegistry.current itemForIdentifier:stepper.accessibilityIdentifier];
    if (!item.isEnable || !isfinite(stepper.value))
        return;
    BOOL threshold = [@[ @"DYYYFilterLowLikes", @"DYYYFilterTimeLimit" ] containsObject:item.identifier];
    [DYYYSettingsRegistry.current setValue:[NSString stringWithFormat:threshold ? @"%.0f" : @"%.15g", stepper.value] forItem:item];
    [self refreshVisibleRows];
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
}
- (void)editNumber:(DYYYNumberControl *)control {
    DYYYSettingDescriptor *item = [DYYYSettingsRegistry.current itemForIdentifier:control.accessibilityIdentifier];
    if (item.isEnable)
        [self editExactValue:item];
}
- (void)sliderEnded:(UISlider *)slider {
    DYYYSettingDescriptor *item = [DYYYSettingsRegistry.current itemForIdentifier:slider.accessibilityIdentifier];
    BOOL glass = DYYYGlassBackdropView.defaultSettings[item.identifier] != nil;
    NSString *value = [NSString stringWithFormat:glass ? @"%.2f" : @"%.6g", slider.value];
    slider.value = value.floatValue;
    [self sliderChanged:slider];
    [DYYYSettingsRegistry.current setValue:value forItem:item];
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    DYYYSettingDescriptor *item = [self itemAt:path];
    if (!item.isEnable || item.menuProvider)
        return;
    if (item.children.count) {
        [[DYYYSettingsCoordinator navigationController] pushViewController:[[DYYYSettingViewController alloc] initWithSections:item.children title:item.title] animated:YES];
        return;
    }
    if ([item.controlType isEqual:@"switch"])
        return;
    if ([item.controlType isEqual:@"number"]) {
        [self editExactValue:item];
        return;
    }
    if ([item.controlType isEqual:@"color"]) {
        self.colorItem = item;
        self.colorChanged = NO;
        UIColorPickerViewController *picker = [UIColorPickerViewController new];
        picker.supportsAlpha = NO;
        UIColor *initial = [DYYYUtils colorFromSchemeHexString:[self valueForItem:item] targetWidth:26];
        CGFloat r, g, b, a;
        picker.selectedColor = [initial getRed:&r green:&g blue:&b alpha:&a] ? initial : UIColor.systemBlueColor;
        picker.delegate = self;
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
        alert.view.tintColor = UIColor.labelColor;
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
    BOOL number = [item.controlType isEqual:@"number"];
    BOOL glass = DYYYGlassBackdropView.defaultSettings[item.identifier] != nil;
    BOOL threshold = [@[ @"DYYYFilterLowLikes", @"DYYYFilterTimeLimit" ] containsObject:item.identifier];
    [DYYYSettingsHelper showTextInputAlert:item.title
                               defaultText:[NSUserDefaults.standardUserDefaults objectForKey:item.identifier]
                               placeholder:glass ? @"输入 0～1，例如 0.12 为 12%；留空恢复默认" : number ? (threshold ? @"非负整数，0 表示关闭；留空恢复默认" : @"可输入负数或小数；留空恢复默认") : item.subTitle
                                 onConfirm:^(NSString *text) {
                                   if (!item.isEnable)
                                       return;
                                   if (glass) {
                                       text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                                       if (text.length) {
                                           NSScanner *scanner = [NSScanner scannerWithString:text];
                                           double value;
                                           if (![scanner scanDouble:&value] || !scanner.isAtEnd || !isfinite(value) || value < 0 || value > 1) {
                                               [DYYYUtils showToast:@"请输入 0～1 之间的数值"];
                                               return;
                                           }
                                           text = [NSString stringWithFormat:@"%.2f", value];
                                       }
                                       [DYYYSettingsRegistry.current setValue:text.length ? text : nil forItem:item];
                                       return;
                                   }
                                   if (number) {
                                       text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                                       if (text.length) {
                                           NSScanner *scanner = [NSScanner scannerWithString:text];
                                           if (threshold) {
                                               long long value;
                                               if (![scanner scanLongLong:&value] || !scanner.isAtEnd || value < 0) {
                                                   [DYYYUtils showToast:@"请输入非负整数，0 表示关闭"];
                                                   return;
                                               }
                                               text = [NSString stringWithFormat:@"%lld", value];
                                           } else {
                                               double value;
                                               if (![scanner scanDouble:&value] || !scanner.isAtEnd || !isfinite(value)) {
                                                   [DYYYUtils showToast:@"请输入有限数值，可使用负数或小数"];
                                                   return;
                                               }
                                           }
                                       }
                                   }
                                   [DYYYSettingsRegistry.current setValue:text forItem:item];
                                 }
                                  onCancel:nil];
}
- (void)colorPickerViewController:(UIColorPickerViewController *)controller didSelectColor:(UIColor *)color continuously:(BOOL)continuously {
    self.colorChanged = YES;
}
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)controller {
    self.colorChanged = YES;
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)controller {
    DYYYSettingDescriptor *item = self.colorItem;
    self.colorItem = nil;
    BOOL changed = self.colorChanged;
    self.colorChanged = NO;
    if (!changed || !item.isEnable)
        return;
    CGFloat r, g, b, a;
    if (![controller.selectedColor getRed:&r green:&g blue:&b alpha:&a])
        return;
    NSString *hex = [NSString stringWithFormat:@"#%02X%02X%02X", (int)round(r * 255), (int)round(g * 255), (int)round(b * 255)];
    [DYYYSettingsRegistry.current setValue:hex forItem:item];
}
@end
