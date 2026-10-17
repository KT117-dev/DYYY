#import <MobileCoreServices/MobileCoreServices.h>
#import <UIKit/UIKit.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "AwemeHeaders.h"
#import "DYYYManager.h"

#import "DYYYABTestHook.h"

#import "DYYYAboutDialogView.h"
#import "DYYYBottomAlertView.h"
#import "DYYYCustomInputView.h"
#import "DYYYIconOptionsDialogView.h"
#import "DYYYKeywordListView.h"
#import "DYYYOptionsSelectionView.h"

#import "DYYYConstants.h"
#import "DYYYFloatClearButton.h"
#import "DYYYFloatSpeedButton.h"
#import "DYYYSettingsHelper.h"
#import "DYYYUtils.h"

#import "DYYYSettingViewController.h"
#import "DYYYSettingsCoordinator.h"
#import "DYYYSettingsRegistry.h"

static NSString *const kDYYYFeedNowPlayingSettingTitle = @"屏蔽灵动岛抖音播放信息";
static NSString *const kDYYYFeedNowPlayingSVGIconName = @"ic_liveactivityplayslash_outlined_20";
static NSString *DYYYCurrentSpeedSettingsDisplayString(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:@"DYYYSpeedSettings"];
    return [value isKindOfClass:NSString.class] && [value length] ? value : DYYYDefaultSpeedSettingsString();
}

NSNotificationName const DYYYSettingsDidChangeNotification = @"DYYYSettingsDidChange";
static DYYYSettingsRegistry *DYYYActiveRegistry;

@implementation DYYYSettingDescriptor
- (instancetype)init {
    if ((self = [super init])) {
        _isEnable = YES;
        _aliases = [NSMutableArray array];
    }
    return self;
}
- (BOOL)isSwitchOn {
    return [NSUserDefaults.standardUserDefaults boolForKey:self.identifier];
}
- (void)refreshCell {
    [NSNotificationCenter.defaultCenter postNotificationName:DYYYSettingsDidChangeNotification object:self];
}
@end
@implementation DYYYSettingsSection
@end

@interface DYYYSettingsRegistry ()
@property(nonatomic, strong) NSMutableArray *mutableSections;
@property(nonatomic, strong) NSMutableDictionary<NSString *, DYYYSettingDescriptor *> *items;
@property(nonatomic, strong) id remoteToken;
@property(nonatomic) BOOL building;
@end

@implementation DYYYSettingsRegistry
+ (instancetype)current {
    if (!DYYYActiveRegistry)
        DYYYActiveRegistry = [self new];
    return DYYYActiveRegistry;
}
+ (BOOL)isBuilding {
    return [self current].building;
}
- (NSArray *)sections {
    return self.mutableSections ?: @[];
}
- (NSArray *)allItems {
    return [self.items.allValues sortedArrayUsingComparator:^NSComparisonResult(DYYYSettingDescriptor *a, DYYYSettingDescriptor *b) {
      return [a.identifier compare:b.identifier];
    }];
}
- (DYYYSettingDescriptor *)itemForIdentifier:(NSString *)identifier {
    return self.items[identifier];
}
+ (void)registerSections:(NSArray *)sections category:(NSString *)category {
    DYYYSettingsRegistry *registry = [self current];
    for (DYYYSettingsSection *section in sections) {
        NSMutableArray *unique = [NSMutableArray array];
        for (DYYYSettingDescriptor *item in section.itemArray) {
            if (!item.identifier.length)
                continue;
            DYYYSettingDescriptor *existing = registry.items[item.identifier];
            if (existing) {
                if (![existing.aliases containsObject:item.title])
                    [existing.aliases addObject:item.title ?: @""];
                item.cellTappedBlock = nil;
                item.switchChangedBlock = nil;
                continue;
            }
            item.category = section.sectionHeaderTitle ?: category;
            if (category.length)
                [item.aliases addObject:category];
            NSString *legacyCategory = @{
                @"基本设置" : @"DYYYBasicSettings",
                @"界面设置" : @"DYYYUISettings",
                @"隐藏设置" : @"DYYYHideSettings",
                @"顶栏移除" : @"DYYYRemoveSettings",
                @"增强设置" : @"DYYYEnhanceSettings",
                @"悬浮按钮" : @"DYYYFloatButtonSettings"
            }[category];
            if (legacyCategory)
                [item.aliases addObject:legacyCategory];
            item.tab = [registry tabForItem:item];
            item.controlType = (item.cellType == 6 || item.cellType == 37) ? @"switch" : @"text";
            NSString *key = item.identifier;
            if ([@[
                    @"DYYYBackupSettings", @"DYYYRestoreSettings", @"DYYYCleanSettings", @"DYYYCleanCache", @"DYYYAbout", @"DYYYLicense", @"SaveCurrentABTestData", @"SaveABTestConfigFile",
                    @"LoadABTestConfigFile", @"DeleteABTestConfigFile", @"DYYYCheckUpdate"
                ] containsObject:key])
                item.controlType = @"action";
            if ([@[ @"DYYYDefaultSpeed", @"DYYYLongPressSpeed", @"DYYYHDRMode", @"DYYYLiveQuality", @"DYYYABTestModeString", @"DYYYScheduleStyle" ] containsObject:key])
                item.controlType = @"choice";
            if ([@[ @"DYYYFilterKeywords", @"DYYYFilterUsers", @"DYYYFilterProp" ] containsObject:key])
                item.controlType = @"keywords";
            if ([key hasPrefix:@"DYYYIcon"] || [key isEqual:@"DYYYClearButtonIcon"])
                item.controlType = @"icon";
            if ([@[
                    @"DYYYElementScale", @"DYYYNicknameScale", @"DYYYNicknameVerticalOffset", @"DYYYDescriptionVerticalOffset", @"DYYYIPLabelVerticalOffset", @"DYYYTimelineVerticalPosition",
                    @"DYYYTabBarHeight"
                ] containsObject:key])
                item.controlType = @"number";
            if ([@[ @"DYYYFilterLowLikes", @"DYYYFilterTimeLimit" ] containsObject:key])
                item.controlType = @"number";
            if (![item.controlType isEqual:@"switch"] && [key containsString:@"Color"])
                item.controlType = @"color";
            if ([key hasSuffix:@"Transparent"] || [key hasSuffix:@"Transparency"])
                item.controlType = @"slider";
            if ([@[ @"DYYYSpeedButtonSize", @"DYYYEnableFloatClearButtonSize" ] containsObject:key])
                item.controlType = @"size";
            item.requiresRestart = [@[
                @"DYYYEnableAutoPlay", @"DYYYABTestBlockEnabled", @"DYYYABTestModeString", @"DYYYRestoreSettings", @"DYYYCleanSettings", @"DYYYForceDownloadEmotion", @"DYYYForceDownloadCommentAudio",
                @"DYYYForceDownloadCommentImage", @"DYYYHideKeyboardAI"
            ] containsObject:key];
            if (item.requiresRestart)
                item.subTitle = [(item.subTitle ?: @"") stringByAppendingString:@"\n部分行为在重启应用后生效。"];
            if ([key isEqualToString:@"DYYYEntrance"] || [key isEqualToString:@"DYYYDisableSettingsGesture"]) {
                item.controlType = @"compatibility";
                item.subTitle = @"双指长按是唯一常规入口；旧配置保留，但不再影响入口。";
            }
            registry.items[key] = item;
            [unique addObject:item];
        }
        section.itemArray = unique;
        if (unique.count)
            [registry.mutableSections addObject:section];
    }
}
- (NSString *)tabForItem:(DYYYSettingDescriptor *)item {
    NSString *key = item.identifier, *category = item.category ?: @"";
    if ([category containsString:@"清屏"] || [category containsString:@"快捷倍速"] || [category containsString:@"ABTest"] || [category containsString:@"面板设置"] ||
        [category containsString:@"媒体"] || [category containsString:@"交互"] || [@[ @"备份", @"清理", @"关于" ] containsObject:category])
        return @"工具";
    if ([key hasPrefix:@"DYYYHide"] || [key hasPrefix:@"DYYYSkip"] || [key hasPrefix:@"DYYYFilter"] || [key hasPrefix:@"DYYYNo"] || [category containsString:@"隐藏"] ||
        [category containsString:@"过滤"] || [category containsString:@"顶栏"])
        return @"净化";
    if ([category containsString:@"透明"] || [category containsString:@"缩放"] || [category containsString:@"自定义"] || [category containsString:@"位置"] || [category containsString:@"外观"] ||
        [key containsString:@"Color"] || [key containsString:@"Glass"] || [key containsString:@"Blur"] || [key containsString:@"Transparency"] || [key containsString:@"Transparent"])
        return @"外观";
    if ([category containsString:@"播放"] || [key containsString:@"Speed"] || [key containsString:@"HDR"] || [key containsString:@"Quality"] || [key containsString:@"Progress"] ||
        [key containsString:@"Schedule"] || [key containsString:@"FullScreen"])
        return @"播放";
    return @"工具";
}
- (NSArray *)sectionsForTab:(NSString *)tab {
    NSMutableArray *result = [NSMutableArray array];
    for (DYYYSettingsSection *source in self.sections) {
        NSMutableArray *items = [NSMutableArray array];
        for (DYYYSettingDescriptor *item in source.itemArray)
            if ([item.tab isEqual:tab])
                [items addObject:item];
        if (!items.count)
            continue;
        DYYYSettingsSection *section = [DYYYSettingsSection new];
        section.sectionHeaderTitle = source.sectionHeaderTitle;
        section.sectionFooterTitle = source.sectionFooterTitle;
        section.itemArray = items;
        [result addObject:section];
    }
    return result;
}
- (void)build {
    if (self.items)
        return;
    self.items = [NSMutableDictionary dictionary];
    self.mutableSections = [NSMutableArray array];
    self.building = YES;
    [self buildLegacyCatalog];
    [self addSupplementalItems];
    self.building = NO;
    [self refreshDependencies];
}
- (void)refreshDependencies {
    NSDictionary *rules = [DYYYSettingsHelper settingsDependencyConfig];
    NSMutableSet *controlled = [NSMutableSet set];
    for (NSString *kind in @[ @"dependencies", @"mutualExclusions" ]) {
        for (NSArray *targets in [rules[kind] allValues]) [controlled addObjectsFromArray:targets];
    }
    [controlled addObjectsFromArray:[rules[@"conditionalDependencies"] allKeys]];
    for (NSDictionary *rule in [rules[@"valueDependencies"] allValues]) [controlled addObjectsFromArray:rule[@"dependents"] ?: @[]];
    for (DYYYSettingDescriptor *item in self.allItems) {
        if ([item.category isEqual:@"设置双击菜单项目"])
            item.isEnable = [NSUserDefaults.standardUserDefaults boolForKey:@"DYYYEnableDoubleTapMenu"];
        if ([controlled containsObject:item.identifier])
            [DYYYSettingsHelper applyDependencyRulesForItem:item];
        if ([item.category isEqual:@"设置双击菜单项目"] && ![NSUserDefaults.standardUserDefaults boolForKey:@"DYYYEnableDoubleTapMenu"])
            item.isEnable = NO;
    }
}
- (void)setValue:(id)value forItem:(DYYYSettingDescriptor *)item {
    [DYYYSettingsHelper setUserDefaults:value forKey:item.identifier];
    [DYYYSettingsHelper handleConflictsAndDependenciesForSetting:item.identifier isEnabled:[value isKindOfClass:NSNumber.class] ? [value boolValue] : [value length] > 0];
    [self refreshDependencies];
    [item refreshCell];
}
- (void)resetItem:(DYYYSettingDescriptor *)item {
    [DYYYSettingsHelper setUserDefaults:nil forKey:item.identifier];
    [self refreshDependencies];
    [item refreshCell];
    [FloatingSpeedButton reloadConfiguration];
    reloadClearButtonConfiguration();
}
- (void)invalidate {
    if (self.remoteToken)
        [NSNotificationCenter.defaultCenter removeObserver:self.remoteToken];
    self.remoteToken = nil;
    // 旧业务回调捕获模型；页面关闭时统一断开这些会话内引用。
    for (DYYYSettingDescriptor *item in self.allItems) {
        item.cellTappedBlock = nil;
        item.switchChangedBlock = nil;
    }
    if (DYYYActiveRegistry == self)
        DYYYActiveRegistry = nil;
}
- (void)addSupplementalItems {
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[DYYYSettingsHelper createSettingItem:@{@"identifier" : @"DYYYHideEditTags", @"title" : @"隐藏图文标签", @"cellType" : @6} cellTapHandlers:[NSMutableDictionary dictionary]]];
    [items addObject:[DYYYSettingsHelper createSettingItem:@{@"identifier" : @"DYYYHideTemplateGroup", @"title" : @"隐藏底部话题", @"cellType" : @6} cellTapHandlers:[NSMutableDictionary dictionary]]];
    [DYYYSettingsRegistry registerSections:@[ [DYYYSettingsHelper createSectionWithTitle:@"兼容设置" items:items] ] category:@"工具"];
}

- (void)buildLegacyCatalog {
    // 创建主分类列表
    DYYYSettingsSection *mainSection = [[DYYYSettingsSection.class alloc] init];
    mainSection.sectionHeaderTitle = @"功能";
    mainSection.sectionHeaderHeight = 40;
    mainSection.type = 0;
    NSMutableArray<DYYYSettingDescriptor *> *mainItems = [NSMutableArray array];

    // 创建基本设置分类项
    DYYYSettingDescriptor *basicSettingItem = [[DYYYSettingDescriptor.class alloc] init];
    basicSettingItem.identifier = @"DYYYBasicSettings";
    basicSettingItem.title = @"基本设置";
    basicSettingItem.type = 0;
    basicSettingItem.svgIconImageName = @"ic_gearsimplify_outlined_20";
    basicSettingItem.cellType = 26;
    basicSettingItem.colorStyle = 0;
    basicSettingItem.isEnable = YES;
    basicSettingItem.cellTappedBlock = ^{
      // 创建基本设置二级界面的设置项
      NSMutableDictionary *cellTapHandlers = [NSMutableDictionary dictionary];

      // 【外观设置】分类
      NSMutableArray<DYYYSettingDescriptor *> *appearanceItems = [NSMutableArray array];
      NSArray *appearanceSettings = @[
          @{@"identifier" : @"DYYYEnableDanmuColor", @"title" : @"启用弹幕改色", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_dansquare_outlined_20"}, @{
              @"identifier" : @"DYYYDanmuColor",
              @"title" : @"自定弹幕颜色",
              @"subTitle" : @"填入 random 使用随机颜色弹幕",
              @"detail" : @"十六进制",
              @"cellType" : @20,
              @"imageName" : @"ic_dansquarenut_outlined_20"
          },
          @{
              @"identifier" : @"DYYYDanmuRainbowRotating",
              @"title" : @"旋转彩虹弹幕",
              @"subTitle" : @"启用后将覆盖上面的自定义弹幕颜色",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_dansquarenut_outlined_20"
          }
      ];

      for (NSDictionary *dict in appearanceSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict cellTapHandlers:cellTapHandlers];
          [appearanceItems addObject:item];
      }

      // 【视频播放设置】分类
      NSMutableArray<DYYYSettingDescriptor *> *videoItems = [NSMutableArray array];
      NSArray *videoSettings = @[
          @{
              @"identifier" : @"DYYYVideoBGColor",
              @"title" : @"视频背景颜色",
              @"subTitle" : @"可以自定义部分横屏视频的背景颜色",
              @"detail" : @"",
              @"cellType" : @20,
              @"imageName" : @"ic_tv_outlined_20"
          },
          @{
              @"identifier" : @"DYYYShowScheduleDisplay",
              @"title" : @"显示进度时长",
              @"subTitle" : @"强制显示所有视频的进度条和时长",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_playertime_outlined_20"
          },
          @{@"identifier" : @"DYYYScheduleStyle", @"title" : @"进度时长样式", @"detail" : @"", @"cellType" : @26, @"imageName" : @"ic_playertime_outlined_20"},
          @{@"identifier" : @"DYYYProgressLabelColor", @"title" : @"进度标签颜色", @"detail" : @"十六进制", @"cellType" : @26, @"imageName" : @"ic_playertime_outlined_20"},
          @{@"identifier" : @"DYYYTimelineVerticalPosition", @"title" : @"进度纵轴位置", @"detail" : @"-12.5", @"cellType" : @26, @"imageName" : @"ic_playertime_outlined_20"},
          @{@"identifier" : @"DYYYHideVideoProgress", @"title" : @"隐藏视频进度", @"subTitle" : @"隐藏视频进度条", @"detail" : @"", @"cellType" : @37, @"imageName" : @"ic_playertime_outlined_20"}, @{
              @"identifier" : @"DYYYEnableAutoPlay",
              @"title" : @"启用自动播放",
              @"subTitle" : @"暂时仅支持推荐、搜索和个人主页的自动连播",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_play_outlined_12"
          },
          @{
              @"identifier" : @"DYYYKeepUnpublishedVideo",
              @"title" : @"阻止未公开视频自动跳过",
              @"subTitle" : @"保留当前作品的这次观看，手动滑走后结束保留",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_play_outlined_12"
          },
          @{
              @"identifier" : @"DYYYEnableBackgroundListen",
              @"title" : @"启用后台播放",
              @"subTitle" : @"使受到后台播放限制的视频可以在后台继续播放",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_play_outlined_12"
          },
          @{
              @"identifier" : @"DYYYDisableCastVPNCheck",
              @"title" : @"忽略投屏 VPN 检测",
              @"subTitle" : @"开启后在连接 VPN 时也可以正常投屏",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_tv_outlined_20"
          },
          @{@"identifier" : @"DYYYDefaultSpeed", @"title" : @"设置默认倍速", @"detail" : @"", @"cellType" : @26, @"imageName" : @"ic_speed_outlined_20"},
          @{@"identifier" : @"DYYYLongPressSpeed", @"title" : @"设置长按倍速", @"detail" : @"", @"cellType" : @26, @"imageName" : @"ic_speed_outlined_20"}, @{
              @"identifier" : @"DYYYEnableLongPressSpeedGesture",
              @"title" : @"上下控制倍速",
              @"subTitle" : @"长按时可通过上下滑动调整倍速",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_speed_outlined_20"
          },
          @{@"identifier" : @"DYYYEnableArea", @"title" : @"时间属地显示", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_location_outlined_20"}, @{
              @"identifier" : @"DYYYGeonamesUsername",
              @"title" : @"国外解析账号",
              @"subTitle" : @"使用 Geonames.org 账号解析国外 IP 属地",
              @"detail" : @"",
              @"cellType" : @20,
              @"imageName" : @"ic_ip_outlined_12"
          },
          @{@"identifier" : @"DYYYLabelStyle", @"title" : @"文案标签样式", @"detail" : @"", @"cellType" : @26, @"imageName" : @"ic_tag_outlined_20"},
          @{@"identifier" : @"DYYYLabelColor", @"title" : @"属地标签颜色", @"detail" : @"十六进制", @"cellType" : @26, @"imageName" : @"ic_location_outlined_20"}, @{
              @"identifier" : @"DYYYEnableRandomGradient",
              @"title" : @"属地随机渐变",
              @"subTitle" : @"启用后将覆盖上面的属地标签颜色",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_location_outlined_20"
          }
      ];

      for (NSDictionary *dict in videoSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict cellTapHandlers:cellTapHandlers];

          if ([item.identifier isEqualToString:@"DYYYDefaultSpeed"]) {
              NSString *savedSpeed = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDefaultSpeed"];
              item.detail = savedSpeed ?: @"1.0x";

              item.cellTappedBlock = ^{
                NSArray *speedOptions = @[ @"0.75x", @"1.0x", @"1.25x", @"1.5x", @"2.0x", @"2.5x", @"3.0x" ];

                [DYYYOptionsSelectionView showWithPreferenceKey:@"DYYYDefaultSpeed"
                                                   optionsArray:speedOptions
                                                     headerText:@"选择默认倍速"
                                                 onPresentingVC:[DYYYSettingsCoordinator presenter]
                                               selectionChanged:^(NSString *selectedValue) {
                                                 item.detail = selectedValue;
                                                 [item refreshCell];
                                               }];
              };
          }

          else if ([item.identifier isEqualToString:@"DYYYLongPressSpeed"]) {
              NSString *savedSpeed = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYLongPressSpeed"];
              item.detail = savedSpeed ?: @"2.0x";

              item.cellTappedBlock = ^{
                NSArray *speedOptions = @[ @"0.75x", @"1.0x", @"1.25x", @"1.5x", @"2.0x", @"2.5x", @"3.0x" ];

                [DYYYOptionsSelectionView showWithPreferenceKey:@"DYYYLongPressSpeed"
                                                   optionsArray:speedOptions
                                                     headerText:@"选择右侧长按倍速"
                                                 onPresentingVC:[DYYYSettingsCoordinator presenter]
                                               selectionChanged:^(NSString *selectedValue) {
                                                 item.detail = selectedValue;
                                                 [item refreshCell];
                                               }];
              };
          }

          else if ([item.identifier isEqualToString:@"DYYYScheduleStyle"]) {
              NSString *savedStyle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYScheduleStyle"];
              item.detail = savedStyle ?: @"默认";
              item.cellTappedBlock = ^{
                NSArray *styleOptions = @[ @"进度条两侧上下", @"进度条左侧剩余", @"进度条左侧完整", @"进度条右侧剩余", @"进度条右侧完整" ];

                [DYYYOptionsSelectionView showWithPreferenceKey:@"DYYYScheduleStyle"
                                                   optionsArray:styleOptions
                                                     headerText:@"选择进度时长样式"
                                                 onPresentingVC:[DYYYSettingsCoordinator presenter]
                                               selectionChanged:^(NSString *selectedValue) {
                                                 item.detail = selectedValue;
                                                 [item refreshCell];
                                               }];
              };
          }

          else if ([item.identifier isEqualToString:@"DYYYLabelStyle"]) {
              NSString *savedStyle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYLabelStyle"];
              item.detail = savedStyle ?: @"默认";
              item.cellTappedBlock = ^{
                NSArray *styleOptions = @[ @"文案标签显示", @"文案标签隐藏", @"文案标签禁止跳转搜索" ];

                [DYYYOptionsSelectionView showWithPreferenceKey:@"DYYYLabelStyle"
                                                   optionsArray:styleOptions
                                                     headerText:@"选择文案标签样式"
                                                 onPresentingVC:[DYYYSettingsCoordinator presenter]
                                               selectionChanged:^(NSString *selectedValue) {
                                                 item.detail = selectedValue;
                                                 [item refreshCell];
                                               }];
              };
          }

          [videoItems addObject:item];
      }
      // 【杂项设置】分类
      NSMutableArray<DYYYSettingDescriptor *> *miscellaneousItems = [NSMutableArray array];
      NSArray *miscellaneousSettings = @[
          @{@"identifier" : @"DYYYLiveQuality", @"title" : @"默认直播画质", @"detail" : @"自动", @"cellType" : @26, @"imageName" : @"ic_video_outlined_20"}, @{
              @"identifier" : @"DYYYEnableLiveRealCount",
              @"title" : @"直播真实人数",
              @"subTitle" : @"直播显示具体的在线人数",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_video_outlined_20"
          },
          @{
              @"identifier" : @"DYYYShowLiveDuration",
              @"title" : @"显示开播时长",
              @"subTitle" : @"在直播间左上角显示主播已开播时间",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_clock_outlined_20"
          },

          @{
              @"identifier" : @"DYYYCommentExactTime",
              @"title" : @"评论具体时间",
              @"subTitle" : @"开启后评论区将显示具体的发布时间而非相对时间",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_clock_outlined_20"
          },
          @{
              @"identifier" : @"DYYYDisableProfileVisitRecordUpload",
              @"title" : @"禁用访客记录上传",
              @"subTitle" : @"访问用户主页时不上传该访问记录",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{
              @"identifier" : @"DYYYDisableFeedNowPlayingInfo",
              @"title" : kDYYYFeedNowPlayingSettingTitle,
              @"subTitle" : @"开启后禁止信息流视频播放信息显示在灵动岛",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : kDYYYFeedNowPlayingSVGIconName
          },
          @{@"identifier" : @"DYYYEnableVideoHighestQuality", @"title" : @"提高视频画质", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_squaretriangletwo_outlined_20"},
          @{@"identifier" : @"DYYYHideStatusbar", @"title" : @"隐藏系统顶栏", @"subTitle" : @"隐藏系统状态栏", @"detail" : @"", @"cellType" : @37, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYEnablePure", @"title" : @"启用首页净化", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_rectangleportraittriangle_outlined_20"},
          @{@"identifier" : @"DYYYEnableFullScreen", @"title" : @"启用视频全屏", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_fullscreen_outlined_16"}
      ];

      for (NSDictionary *dict in miscellaneousSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict cellTapHandlers:cellTapHandlers];

          if ([item.identifier isEqualToString:@"DYYYLiveQuality"]) {
              NSString *savedQuality = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYLiveQuality"] ?: @"自动";
              item.detail = savedQuality;
              item.cellTappedBlock = ^{
                NSArray *qualities = @[ @"蓝光帧彩", @"蓝光", @"超清", @"高清", @"标清", @"自动" ];

                [DYYYOptionsSelectionView showWithPreferenceKey:@"DYYYLiveQuality"
                                                   optionsArray:qualities
                                                     headerText:@"选择默认直播画质\n无对应画质时会切换到比选择画质低一级的画质"
                                                 onPresentingVC:[DYYYSettingsCoordinator presenter]
                                               selectionChanged:^(NSString *selectedValue) {
                                                 item.detail = selectedValue;
                                                 [item refreshCell];
                                               }];
              };
          }

          [miscellaneousItems addObject:item];
      }
      // 【过滤与屏蔽】分类
      NSMutableArray<DYYYSettingDescriptor *> *filterItems = [NSMutableArray array];
      NSArray *filterSettings = @[
          @{@"identifier" : @"DYYYSkipLive", @"title" : @"推荐过滤直播", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_video_outlined_20"}, @{
              @"identifier" : @"DYYYSkipAllLive",
              @"title" : @"全部过滤直播",
              @"subTitle" : @"开启后屏蔽直播页面之外的所有直播",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_video_outlined_20"
          },
          @{
              @"identifier" : @"DYYYSkipHotSpot",
              @"title" : @"推荐过滤热点",
              @"subTitle" : @"开启后会过滤推荐中的商品、团购、热点等",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_squaretriangletwo_outlined_20"
          },
          @{@"identifier" : @"DYYYSkipPhoto", @"title" : @"推荐过滤图文", @"subTitle" : @"开启后会过滤全部图文类型", @"detail" : @"", @"cellType" : @37, @"imageName" : @"ic_video_outlined_20"}, @{
              @"identifier" : @"DYYYSkipPhotoText",
              @"title" : @"推荐过滤文字",
              @"subTitle" : @"开启后会过滤带有文字标签的图文",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_video_outlined_20"
          },
          @{@"identifier" : @"DYYYSkipMusic", @"title" : @"推荐过滤音乐", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_video_outlined_20"},
          @{@"identifier" : @"DYYYSkipAIInteraction", @"title" : @"推荐过滤AI互动", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_video_outlined_20"},
          @{@"identifier" : @"DYYYFilterLowLikes", @"title" : @"推荐过滤低赞", @"detail" : @"0", @"cellType" : @26, @"imageName" : @"ic_thumbsdown_outlined_20"},
          @{@"identifier" : @"DYYYFilterUsers", @"title" : @"推荐过滤用户", @"detail" : @"", @"cellType" : @26, @"imageName" : @"ic_userban_outlined_20"},
          @{@"identifier" : @"DYYYFilterKeywords", @"title" : @"推荐过滤文案", @"detail" : @"", @"cellType" : @26, @"imageName" : @"ic_tag_outlined_20"},
          @{@"identifier" : @"DYYYFilterProp", @"title" : @"推荐过滤拍同款", @"detail" : @"", @"cellType" : @26, @"imageName" : @"ic_tag_outlined_20"}, @{
              @"identifier" : @"DYYYFilterTimeLimit",
              @"subTitle" : @"开启后只会推荐最近 N 天内发布的视频\n谨慎开启，最低建议为 10 天",
              @"title" : @"推荐视频时限",
              @"detail" : @"",
              @"cellType" : @20,
              @"imageName" : @"ic_playertime_outlined_20"
          },
          @{
              @"identifier" : @"DYYYHDRMode",
              @"title" : @"全局HDR设置",
              @"subTitle" : @"开启并选择后全局屏蔽HDR效果/过滤HDR作品。",
              @"detail" : @"关闭",
              @"cellType" : @26,
              @"imageName" : @"ic_sun_outlined"
          },
          @{@"identifier" : @"DYYYNoAds", @"title" : @"启用屏蔽广告", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_ad_outlined_20"},
          @{@"identifier" : @"DYYYHideTeenMode", @"title" : @"移除青少年弹窗", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_personcircleclean_outlined_20"},
          @{@"identifier" : @"DYYYNoUpdates", @"title" : @"屏蔽抖音检测更新", @"subTitle" : @"屏蔽抖音应用的版本更新", @"detail" : @"", @"cellType" : @37, @"imageName" : @"ic_circletop_outlined"},
          @{@"identifier" : @"DYYYDisableLivePCDN", @"title" : @"屏蔽直播PCDN功能", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_video_outlined_20"}
      ];

      for (NSDictionary *dict in filterSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict cellTapHandlers:cellTapHandlers];

          if ([item.identifier isEqualToString:@"DYYYFilterLowLikes"]) {
              NSString *savedValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterLowLikes"];
              item.detail = savedValue ?: @"0";
              item.cellTappedBlock = ^{
                [DYYYSettingsHelper showTextInputAlert:@"设置过滤赞数阈值"
                                           defaultText:item.detail
                                           placeholder:@"填0关闭功能"
                                             onConfirm:^(NSString *text) {
                                               NSScanner *scanner = [NSScanner scannerWithString:text];
                                               NSInteger value;
                                               BOOL isValidNumber = [scanner scanInteger:&value] && [scanner isAtEnd];

                                               if (isValidNumber) {
                                                   if (value < 0)
                                                       value = 0;
                                                   NSString *valueString = [NSString stringWithFormat:@"%ld", (long)value];
                                                   [DYYYSettingsHelper setUserDefaults:valueString forKey:@"DYYYFilterLowLikes"];

                                                   item.detail = valueString;
                                                   [item refreshCell];
                                               } else {
                                                   DYYYAboutDialogView *errorDialog = [[DYYYAboutDialogView alloc] initWithTitle:@"输入错误" message:@"\n\n请输入有效的数字\n\n"];
                                                   [errorDialog show];
                                               }
                                             }
                                              onCancel:nil];
              };
          } else if ([item.identifier isEqualToString:@"DYYYFilterUsers"]) {
              NSString *savedValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterUsers"];
              item.detail = savedValue ?: @"";
              item.cellTappedBlock = ^{
                // 将保存的逗号分隔字符串转换为数组
                NSString *savedKeywords = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterUsers"] ?: @"";
                NSArray *keywordArray = [savedKeywords length] > 0 ? [savedKeywords componentsSeparatedByString:@","] : @[];
                DYYYKeywordListView *keywordListView = [[DYYYKeywordListView alloc] initWithTitle:@"过滤用户列表" keywords:keywordArray];
                keywordListView.onConfirm = ^(NSArray *keywords) {
                  NSString *keywordString = [keywords componentsJoinedByString:@","];
                  [DYYYSettingsHelper setUserDefaults:keywordString forKey:@"DYYYFilterUsers"];
                  item.detail = keywordString;
                  [item refreshCell];
                };

                [keywordListView show];
              };
          } else if ([item.identifier isEqualToString:@"DYYYFilterKeywords"]) {
              NSString *savedValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterKeywords"];
              item.detail = savedValue ?: @"";
              item.cellTappedBlock = ^{
                NSString *savedKeywords = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterKeywords"] ?: @"";
                NSArray *keywordArray = [savedKeywords length] > 0 ? [savedKeywords componentsSeparatedByString:@","] : @[];
                DYYYKeywordListView *keywordListView = [[DYYYKeywordListView alloc] initWithTitle:@"设置过滤关键词" keywords:keywordArray];
                keywordListView.onConfirm = ^(NSArray *keywords) {
                  NSString *keywordString = [keywords componentsJoinedByString:@","];

                  [DYYYSettingsHelper setUserDefaults:keywordString forKey:@"DYYYFilterKeywords"];
                  item.detail = keywordString;
                  [item refreshCell];
                };
                [keywordListView show];
              };
          } else if ([item.identifier isEqualToString:@"DYYYFilterTimeLimit"]) {
              NSString *savedValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterTimeLimit"];
              item.detail = savedValue ?: @"";
              item.cellTappedBlock = ^{
                [DYYYSettingsHelper showTextInputAlert:@"过滤视频的发布时间"
                                           defaultText:item.detail
                                           placeholder:@"单位为天"
                                             onConfirm:^(NSString *text) {
                                               NSString *trimmedText = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                                               [DYYYSettingsHelper setUserDefaults:trimmedText forKey:@"DYYYFilterTimeLimit"];
                                               item.detail = trimmedText ?: @"";
                                               [item refreshCell];
                                             }
                                              onCancel:nil];
              };
          } else if ([item.identifier isEqualToString:@"DYYYFilterProp"]) {
              NSString *savedValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterProp"];
              item.detail = savedValue ?: @"";
              item.cellTappedBlock = ^{
                NSString *savedKeywords = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterProp"] ?: @"";
                NSArray *keywordArray = [savedKeywords length] > 0 ? [savedKeywords componentsSeparatedByString:@","] : @[];
                DYYYKeywordListView *keywordListView = [[DYYYKeywordListView alloc] initWithTitle:@"设置过滤词（支持部分匹配）" keywords:keywordArray];
                keywordListView.onConfirm = ^(NSArray *keywords) {
                  NSString *keywordString = [keywords componentsJoinedByString:@","];

                  [DYYYSettingsHelper setUserDefaults:keywordString forKey:@"DYYYFilterProp"];
                  item.detail = keywordString;
                  [item refreshCell];
                };
                [keywordListView show];
              };
          } else if ([item.identifier isEqualToString:@"DYYYHDRMode"]) {
              NSString *savedMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"DYYYHDRMode"] ?: @"关闭";
              item.detail = savedMode;
              item.cellTappedBlock = ^{
                NSArray *options = @[ @"关闭", @"全局屏蔽HDR效果", @"全局过滤HDR作品" ];
                [DYYYOptionsSelectionView showWithPreferenceKey:@"DYYYHDRMode"
                                                   optionsArray:options
                                                     headerText:@"选择 HDR 处理模式"
                                                 onPresentingVC:[DYYYSettingsCoordinator presenter]
                                               selectionChanged:^(NSString *selectedValue) {
                                                 item.detail = selectedValue;
                                                 [item refreshCell];
                                               }];
              };
          }
          [filterItems addObject:item];
      }

      // 【二次确认】分类
      NSMutableArray<DYYYSettingDescriptor *> *securityItems = [NSMutableArray array];
      NSArray *securitySettings = @[
          @{@"identifier" : @"DYYYFollowTips", @"title" : @"关注二次确认", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_userplus_outlined_20"},
          @{@"identifier" : @"DYYYCollectTips", @"title" : @"收藏二次确认", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_star_outlined_20"}
      ];

      for (NSDictionary *dict in securitySettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict];
          [securityItems addObject:item];
      }

      // 创建并组织所有section
      NSMutableArray *sections = [NSMutableArray array];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"外观设置" items:appearanceItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"视频播放" items:videoItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"杂项设置" items:miscellaneousItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"过滤与屏蔽" footerTitle:@"请不要同时开启过多过滤推荐项目，这会增大视频流加载延迟。" items:filterItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"二次确认" items:securityItems]];

      [DYYYSettingsRegistry registerSections:sections category:@"基本设置"];
      if ([DYYYSettingsRegistry isBuilding]) {
          return;
      }

      // 创建并推入二级设置页面
      DYYYSettingViewController *subVC = [DYYYSettingsHelper createSubSettingsViewController:@"基本设置" sections:sections];
      [[DYYYSettingsCoordinator navigationController] pushViewController:(UIViewController *)subVC animated:YES];
    };
    [mainItems addObject:basicSettingItem];

    // 创建界面设置分类项
    DYYYSettingDescriptor *uiSettingItem = [[DYYYSettingDescriptor.class alloc] init];
    uiSettingItem.identifier = @"DYYYUISettings";
    uiSettingItem.title = @"界面设置";
    uiSettingItem.type = 0;
    uiSettingItem.svgIconImageName = @"ic_ipadiphone_outlined";
    uiSettingItem.cellType = 26;
    uiSettingItem.colorStyle = 0;
    uiSettingItem.isEnable = YES;
    uiSettingItem.cellTappedBlock = ^{
      // 创建界面设置二级界面的设置项
      NSMutableDictionary *cellTapHandlers = [NSMutableDictionary dictionary];

      // 【透明度设置】分类
      NSMutableArray<DYYYSettingDescriptor *> *transparencyItems = [NSMutableArray array];
      NSArray *transparencySettings = @[
          @{@"identifier" : @"DYYYTopBarTransparent", @"title" : @"设置顶栏透明", @"detail" : @"0-1小数", @"cellType" : @26, @"imageName" : @"ic_module_outlined_20"},
          @{@"identifier" : @"DYYYGlobalTransparency", @"title" : @"设置全局透明", @"detail" : @"0-1小数", @"cellType" : @26, @"imageName" : @"ic_eye_outlined_20"},
          @{@"identifier" : @"DYYYAvatarViewTransparency", @"title" : @"首页头像透明", @"detail" : @"0-1小数", @"cellType" : @26, @"imageName" : @"ic_user_outlined_20"},
          @{@"identifier" : @"DYYYEnableTabBarLiquidGlass", @"title" : @"启用底栏液体玻璃", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_module_outlined_20"},
          @{@"identifier" : @"DYYYEnableCommentBlur", @"title" : @"评论区液体玻璃", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_comment_outlined_20"},
          @{@"identifier" : @"DYYYEnableNotificationTransparency", @"title" : @"通知栏液体玻璃", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_comment_outlined_20"},
      ];

      for (NSDictionary *dict in transparencySettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict cellTapHandlers:cellTapHandlers];
          [transparencyItems addObject:item];
      }

      // 【缩放与大小】分类
      NSMutableArray<DYYYSettingDescriptor *> *scaleItems = [NSMutableArray array];
      NSArray *scaleSettings = @[
          @{@"identifier" : @"DYYYElementScale", @"title" : @"右侧栏缩放度", @"detail" : @"不填默认", @"cellType" : @26, @"imageName" : @"ic_zoomin_outlined_20"},
          @{@"identifier" : @"DYYYNicknameScale", @"title" : @"昵称文案缩放", @"detail" : @"不填默认", @"cellType" : @26, @"imageName" : @"ic_zoomin_outlined_20"},
          @{@"identifier" : @"DYYYNicknameVerticalOffset", @"title" : @"昵称下移距离", @"detail" : @"不填默认", @"cellType" : @26, @"imageName" : @"ic_pensketch_outlined_20"},
          @{@"identifier" : @"DYYYDescriptionVerticalOffset", @"title" : @"文案下移距离", @"detail" : @"不填默认", @"cellType" : @26, @"imageName" : @"ic_pensketch_outlined_20"},
          @{@"identifier" : @"DYYYIPLabelVerticalOffset", @"title" : @"属地上移距离", @"detail" : @"默认为 3", @"cellType" : @26, @"imageName" : @"ic_pensketch_outlined_20"},
          @{@"identifier" : @"DYYYTabBarHeight", @"title" : @"修改底栏高度", @"detail" : @"默认为空", @"cellType" : @26, @"imageName" : @"ic_pensketch_outlined_20"},
      ];

      for (NSDictionary *dict in scaleSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict cellTapHandlers:cellTapHandlers];
          [scaleItems addObject:item];
      }

      // 【标题自定义】分类
      NSMutableArray<DYYYSettingDescriptor *> *titleItems = [NSMutableArray array];
      NSArray *titleSettings = @[
          @{@"identifier" : @"DYYYModifyTopTabText", @"title" : @"设置顶栏标题", @"detail" : @"标题=修改#标题=修改", @"cellType" : @26, @"imageName" : @"ic_tag_outlined_20"},
          @{@"identifier" : @"DYYYIndexTitle", @"title" : @"设置首页标题", @"detail" : @"不填默认", @"cellType" : @26, @"imageName" : @"ic_squaretriangle_outlined_20"},
          @{@"identifier" : @"DYYYFriendsTitle", @"title" : @"设置朋友标题", @"detail" : @"不填默认", @"cellType" : @26, @"imageName" : @"ic_usertwo_outlined_20"},
          @{@"identifier" : @"DYYYMsgTitle", @"title" : @"设置消息标题", @"detail" : @"不填默认", @"cellType" : @26, @"imageName" : @"ic_msg_outlined_20"},
          @{@"identifier" : @"DYYYSelfTitle", @"title" : @"设置我的标题", @"detail" : @"不填默认", @"cellType" : @26, @"imageName" : @"ic_user_outlined_20"},
          @{@"identifier" : @"DYYYCommentContent", @"title" : @"设置评论填充", @"detail" : @"善语结善缘，恶言伤人心", @"cellType" : @26, @"imageName" : @"ic_comment_outlined_20"},
      ];

      for (NSDictionary *dict in titleSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict cellTapHandlers:cellTapHandlers];
          if ([item.identifier isEqualToString:@"DYYYModifyTopTabText"]) {
              NSString *savedValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYModifyTopTabText"];
              item.detail = savedValue ?: @"";
              item.cellTappedBlock = ^{
                NSString *savedPairs = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYModifyTopTabText"] ?: @"";
                NSArray *pairArray = savedPairs.length > 0 ? [savedPairs componentsSeparatedByString:@"#"] : @[];
                DYYYKeywordListView *keywordListView = [[DYYYKeywordListView alloc] initWithTitle:@"设置顶栏标题" keywords:pairArray];
                keywordListView.addItemTitle = @"添加标题修改";
                keywordListView.editItemTitle = @"编辑标题修改";
                keywordListView.inputPlaceholder = @"原标题=新标题";
                keywordListView.onConfirm = ^(NSArray *keywords) {
                  NSString *keywordString = [keywords componentsJoinedByString:@"#"];
                  [DYYYSettingsHelper setUserDefaults:keywordString forKey:@"DYYYModifyTopTabText"];
                  item.detail = keywordString;
                  [item refreshCell];
                };
                [keywordListView show];
              };
          }
          [titleItems addObject:item];
      }

      // 【图标自定义】分类
      NSMutableArray<DYYYSettingDescriptor *> *iconItems = [NSMutableArray array];

      [iconItems addObject:[DYYYSettingsHelper createIconCustomizationItemWithIdentifier:@"DYYYIconLikeBefore" title:@"未点赞图标" svgIcon:@"ic_heart_outlined_20" saveFile:@"like_before.png"]];
      [iconItems addObject:[DYYYSettingsHelper createIconCustomizationItemWithIdentifier:@"DYYYIconLikeAfter" title:@"已点赞图标" svgIcon:@"ic_heart_filled_20" saveFile:@"like_after.png"]];
      [iconItems addObject:[DYYYSettingsHelper createIconCustomizationItemWithIdentifier:@"DYYYIconComment" title:@"评论的图标" svgIcon:@"ic_comment_outlined_20" saveFile:@"comment.png"]];
      [iconItems addObject:[DYYYSettingsHelper createIconCustomizationItemWithIdentifier:@"DYYYIconUnfavorite" title:@"未收藏图标" svgIcon:@"ic_star_outlined_20" saveFile:@"unfavorite.png"]];
      [iconItems addObject:[DYYYSettingsHelper createIconCustomizationItemWithIdentifier:@"DYYYIconFavorite" title:@"已收藏图标" svgIcon:@"ic_star_filled_20" saveFile:@"favorite.png"]];
      [iconItems addObject:[DYYYSettingsHelper createIconCustomizationItemWithIdentifier:@"DYYYIconShare" title:@"分享的图标" svgIcon:@"ic_share_outlined" saveFile:@"share.png"]];
      [iconItems addObject:[DYYYSettingsHelper createIconCustomizationItemWithIdentifier:@"DYYYIconPlus" title:@"拍摄的图标" svgIcon:@"ic_camera_outlined" saveFile:@"tab_plus.png"]];

      NSMutableArray *sections = [NSMutableArray array];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"透明度设置" items:transparencyItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"缩放与大小" items:scaleItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"标题自定义" items:titleItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"图标自定义" items:iconItems]];
      // 创建并组织所有section
      [DYYYSettingsRegistry registerSections:sections category:@"界面设置"];
      if ([DYYYSettingsRegistry isBuilding]) {
          return;
      }

      // 创建并推入二级设置页面
      DYYYSettingViewController *subVC = [DYYYSettingsHelper createSubSettingsViewController:@"界面设置" sections:sections];
      [[DYYYSettingsCoordinator navigationController] pushViewController:(UIViewController *)subVC animated:YES];
    };

    [mainItems addObject:uiSettingItem];

    // 创建隐藏设置分类项
    DYYYSettingDescriptor *hideSettingItem = [[DYYYSettingDescriptor.class alloc] init];
    hideSettingItem.identifier = @"DYYYHideSettings";
    hideSettingItem.title = @"隐藏设置";
    hideSettingItem.type = 0;
    hideSettingItem.svgIconImageName = @"ic_eyeslash_outlined_20";
    hideSettingItem.cellType = 26;
    hideSettingItem.colorStyle = 0;
    hideSettingItem.isEnable = YES;
    hideSettingItem.cellTappedBlock = ^{
      // 创建隐藏设置二级界面的设置项

      // 【主界面元素】分类
      NSMutableArray<DYYYSettingDescriptor *> *mainUiItems = [NSMutableArray array];
      NSArray *mainUiSettings = @[
          @{
              @"identifier" : @"DYYYHideBottomBg",
              @"title" : @"隐藏底栏背景",
              @"subTitle" : @"完全透明化底栏，可能需要配合首页全屏使用",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{@"identifier" : @"DYYYHideBottomDot", @"title" : @"隐藏底栏红点", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"}, @{
              @"identifier" : @"DYYYHideDoubleColumnEntry",
              @"title" : @"隐藏双列箭头",
              @"subTitle" : @"隐藏底栏首页旁的双列箭头",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{@"identifier" : @"DYYYHideShopButton", @"title" : @"隐藏底栏商城", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideMessageButton", @"title" : @"隐藏底栏消息", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideFriendsButton", @"title" : @"隐藏底栏朋友", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHidePlusButton", @"title" : @"隐藏底栏加号", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideMyButton", @"title" : @"隐藏底栏我的", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideComment", @"title" : @"隐藏底栏评论", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideHotSearch", @"title" : @"隐藏底栏热榜", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHidePadTabBarElements", @"title" : @"精简平板底栏", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideTopBarBadge", @"title" : @"隐藏顶栏红点", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"}
      ];

      for (NSDictionary *dict in mainUiSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict];
          [mainUiItems addObject:item];
      }

      // 【视频播放界面】分类
      NSMutableArray<DYYYSettingDescriptor *> *videoUiItems = [NSMutableArray array];
      NSArray *videoUiSettings = @[
          @{@"identifier" : @"DYYYHideEntry", @"title" : @"隐藏全屏观看", @"subTitle" : @"原始位置可点击", @"detail" : @"", @"cellType" : @37, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYRemoveEntry", @"title" : @"移除全屏观看", @"subTitle" : @"完全移除不可点击", @"detail" : @"", @"cellType" : @37, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideLOTAnimationView", @"title" : @"隐藏头像加号", @"subTitle" : @"原始位置可点击", @"detail" : @"", @"cellType" : @37, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideFollowPromptView", @"title" : @"移除头像加号", @"subTitle" : @"完全移除不可点击", @"detail" : @"", @"cellType" : @37, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideLikeLabel", @"title" : @"隐藏点赞数值", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideCommentLabel", @"title" : @"隐藏评论数值", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideCollectLabel", @"title" : @"隐藏收藏数值", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideShareLabel", @"title" : @"隐藏分享数值", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideLikeButton", @"title" : @"隐藏点赞按钮", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideCommentButton", @"title" : @"隐藏评论按钮", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideCollectButton", @"title" : @"隐藏收藏按钮", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideShareButton", @"title" : @"隐藏分享按钮", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideAvatarButton", @"title" : @"隐藏头像及周边", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideAvatarLive", @"title" : @"隐藏头像直播提示", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideMusicButton", @"title" : @"隐藏音乐按钮", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"}, @{
              @"identifier" : @"DYYYHideGradient",
              @"title" : @"隐藏遮罩效果",
              @"subTitle" : @"移除视频文案或图片滑条可能出现的黑色背景遮罩效果，但可能对部分视频的文案可读性产生一定影响。",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{@"identifier" : @"DYYYHideBack", @"title" : @"隐藏返回按钮", @"subTitle" : @"主页视频左上角的返回按钮", @"detail" : @"", @"cellType" : @37, @"imageName" : @"ic_eyeslash_outlined_16"}
      ];

      for (NSDictionary *dict in videoUiSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict];
          [videoUiItems addObject:item];
      }

      // 【侧边栏】分类
      NSMutableArray<DYYYSettingDescriptor *> *sidebarItems = [NSMutableArray array];
      NSArray *sidebarSettings = @[
          @{@"identifier" : @"DYYYHideSidebarRecentApps", @"title" : @"隐藏常用小程序", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideSidebarRecentUsers", @"title" : @"隐藏常访问的人", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideSidebarDot", @"title" : @"隐藏侧栏红点", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideLeftSideBar", @"title" : @"隐藏左侧边栏", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"}
      ];

      for (NSDictionary *dict in sidebarSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict];
          [sidebarItems addObject:item];
      }

      // 【消息页与我的页】分类
      NSMutableArray<DYYYSettingDescriptor *> *messageAndMineItems = [NSMutableArray array];
      NSArray *messageAndMineSettings = @[
          @{@"identifier" : @"DYYYHidePushBanner", @"title" : @"隐藏通知权限提示", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideMessageTabRedPacket", @"title" : @"隐藏消息顶栏红包", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideAvatarList", @"title" : @"隐藏消息头像列表", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideAvatarBubble", @"title" : @"隐藏消息头像气泡", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideButton", @"title" : @"隐藏我的添加朋友", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideFamiliar", @"title" : @"隐藏朋友日常按钮", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideGroupShop", @"title" : @"隐藏群聊商店按钮", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideGroupLiveIndicator", @"title" : @"隐藏群头像直播中", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideGroupInputActionBar", @"title" : @"隐藏聊天页工具栏", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideReply", @"title" : @"隐藏底部私信回复", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHidePostView", @"title" : @"隐藏我的页发作品", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"}
      ];
      for (NSDictionary *dict in messageAndMineSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict];
          [messageAndMineItems addObject:item];
      }

      // 【提示与位置信息】分类
      NSMutableArray<DYYYSettingDescriptor *> *infoItems = [NSMutableArray array];
      NSArray *infoSettings = @[
          @{@"identifier" : @"DYYYHideLiveView", @"title" : @"隐藏关注顶端", @"subTitle" : @"隐藏关注页顶端的直播列表", @"detail" : @"", @"cellType" : @37, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{
              @"identifier" : @"DYYYHideConcernCapsuleView",
              @"title" : @"隐藏关注直播",
              @"subTitle" : @"隐藏关注页顶端的 N 个直播",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{
              @"identifier" : @"DYYYHideMenuView",
              @"title" : @"隐藏同城顶端",
              @"subTitle" : @"隐藏同城页顶端的团购等菜单",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{@"identifier" : @"DYYYHideNearbyCapsuleView", @"title" : @"隐藏吃喝玩乐", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideDiscover", @"title" : @"隐藏右上搜索", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideCommentDiscover", @"title" : @"隐藏评论搜索", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideInteractionSearch", @"title" : @"隐藏相关搜索", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{
              @"identifier" : @"DYYYHideSearchBubble",
              @"title" : @"隐藏弹出热搜",
              @"subTitle" : @"从右上搜索位置处弹出的热搜白框",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{@"identifier" : @"DYYYHideSearchSame", @"title" : @"隐藏搜索同款", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideSearchEntrance", @"title" : @"隐藏顶部搜索框", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideSearchEntranceIndicator", @"title" : @"隐藏搜索框背景", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideDanmuButton", @"title" : @"隐藏弹幕按钮", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideCancelMute", @"title" : @"隐藏静音按钮", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideQuqishuiting", @"title" : @"隐藏去汽水听", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideGongChuang", @"title" : @"屏蔽共创信息", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideHotspot", @"title" : @"隐藏热点提示", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideRecommendTips", @"title" : @"隐藏推荐提示", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideBottomRelated", @"title" : @"隐藏底部相关", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideShareContentView", @"title" : @"隐藏分享提示", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideAntiAddictedNotice", @"title" : @"隐藏作者声明及风险提示", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideFeedAnchorContainer", @"title" : @"隐藏视频锚点", @"detail" : @"", @"cellType" : @37, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideLocation", @"title" : @"隐藏视频定位", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideChallengeStickers", @"title" : @"隐藏挑战贴纸", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideEditTag", @"title" : @"隐藏互动贴纸", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideTemplateLabel", @"title" : @"隐藏精选标签", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideFriendRecommend", @"title" : @"隐藏好友推荐", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideTemplateTags", @"title" : @"隐藏校园提示", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideHisShop", @"title" : @"隐藏作者店铺", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideTopBarLine", @"title" : @"隐藏顶栏横线", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideTemplateVideo", @"title" : @"隐藏视频合集", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideTemplatePlaylet", @"title" : @"隐藏短剧合集", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideLiveGIF", @"title" : @"隐藏动图标签", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideItemTag", @"title" : @"隐藏笔记标签", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{
              @"identifier" : @"DYYYHideBottomInteraction",
              @"title" : @"隐藏底部互动",
              @"subTitle" : @"隐藏底部出现的分享等互动",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{@"identifier" : @"DYYYHideCameraLocation", @"title" : @"隐藏相机定位", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideCommentViews", @"title" : @"隐藏评论视图", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideCommentTips", @"title" : @"隐藏评论提示", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{
              @"identifier" : @"DYYYHideLiveCapsuleView",
              @"title" : @"隐藏直播提示",
              @"subTitle" : @"隐藏所有的直播中提示",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{@"identifier" : @"DYYYHideStoryProgressSlide", @"title" : @"隐藏视频滑条", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideDotsIndicator", @"title" : @"隐藏图片滑条", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{
              @"identifier" : @"DYYYHideChapterProgress",
              @"title" : @"隐藏章节进度",
              @"subTitle" : @"隐藏可能出现在视频上方或者下方的章节进度条",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{@"identifier" : @"DYYYHidePopover", @"title" : @"隐藏上次看到", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHidePrivateMessages", @"title" : @"隐藏分享私信", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideRightLabel", @"title" : @"隐藏昵称右侧", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{
              @"identifier" : @"DYYYHidePendantGroup",
              @"title" : @"隐藏红包悬浮",
              @"subTitle" : @"隐藏抖音极速版和抖音部分视频的红包悬浮按钮，可能失效，不修复。",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{
              @"identifier" : @"DYYYHideScancode",
              @"title" : @"隐藏输入扫码",
              @"subTitle" : @"隐藏点击搜索后输入框右部的扫码按钮",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{
              @"identifier" : @"DYYYHidePauseVideoRelatedWord",
              @"title" : @"隐藏暂停相关",
              @"subTitle" : @"隐藏暂停视频后出现的相关词条",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{
              @"identifier" : @"DYYYHideKeyboardAI",
              @"title" : @"隐藏键盘 AI",
              @"subTitle" : @"隐藏搜索下方的 AI 和语音搜索按钮",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          }
      ];

      for (NSDictionary *dict in infoSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict];
          [infoItems addObject:item];
      }

      // 【直播界面净化】分类
      NSMutableArray<DYYYSettingDescriptor *> *livestreamItems = [NSMutableArray array];
      NSArray *livestreamSettings = @[
          @{@"identifier" : @"DYYYHideLivePlayground", @"title" : @"隐藏直播广场", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideEnterLive", @"title" : @"隐藏进入直播", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideLiveRoomClose", @"title" : @"隐藏关闭按钮", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideLiveRoomFullscreen", @"title" : @"隐藏横屏按钮", @"subTitle" : @"原始位置可点击", @"detail" : @"", @"cellType" : @37, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideGiftPavilion", @"title" : @"隐藏礼物展馆", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideLiveRoomClear", @"title" : @"隐藏退出清屏", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideLiveRoomMirroring", @"title" : @"隐藏投屏按钮", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideLiveDiscovery", @"title" : @"隐藏直播发现", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"}, @{
              @"identifier" : @"DYYYHideLiveDetail",
              @"title" : @"隐藏直播热榜",
              @"subTitle" : @"隐藏用户下方的小时榜、人气榜、热度等信息",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{
              @"identifier" : @"DYYYHideTouchView",
              @"title" : @"隐藏红包悬浮",
              @"subTitle" : @"隐藏用户下方的红包、积分等悬浮按钮",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{@"identifier" : @"DYYYHideKTVSongIndicator", @"title" : @"隐藏直播点歌", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"}, @{
              @"identifier" : @"DYYYHideLiveGoodsMsg",
              @"title" : @"隐藏商品推广",
              @"subTitle" : @"隐藏直播间右下角的商品和右上角的推广",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{@"identifier" : @"DYYYHideLiveLikeAnimation", @"title" : @"隐藏点赞动画", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"}, @{
              @"identifier" : @"DYYYHideLivePopup",
              @"title" : @"隐藏进场特效",
              @"subTitle" : @"隐藏会员用户进入直播间时出现在弹幕顶部的动画特效",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{
              @"identifier" : @"DYYYHideLiveDanmaku",
              @"title" : @"隐藏滚动弹幕",
              @"subTitle" : @"隐藏直播间管理员发送的特殊横向滚动弹幕",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{
              @"identifier" : @"DYYYHideLiveHotMessage",
              @"title" : @"隐藏大家在说",
              @"subTitle" : @"隐藏出现在弹幕顶部的大家说热搜词",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{
              @"identifier" : @"DYYYHideStickerView",
              @"title" : @"隐藏文字贴纸",
              @"subTitle" : @"隐藏主播设置的预约直播和文字贴纸",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{
              @"identifier" : @"DYYYHideGroupComponent",
              @"title" : @"隐藏礼物挑战",
              @"subTitle" : @"隐藏主播设置的发送礼物做挑战列表",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{@"identifier" : @"DYYYHideCellularAlert", @"title" : @"隐藏流量提醒", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"}

      ];
      for (NSDictionary *dict in livestreamSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict];
          [livestreamItems addObject:item];
      }

      // 【长按面板】分类
      NSMutableArray<DYYYSettingDescriptor *> *modernpanels = [NSMutableArray array];
      NSArray *modernpanelSettings = @[
          @{
              @"identifier" : @"DYYYSimplifyLongPressPanel",
              @"title" : @"精简长按面板",
              @"subTitle" : @"开启后将隐藏所有原始面板选项，只保留 DYYY 自定义功能",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_eyeslash_outlined_16"
          },
          @{
              @"identifier" : @"DYYYHidePanelItems",
              @"title" : @"隐藏面板项目",
              @"subTitle" : @"输入要隐藏的按钮名称，多个用逗号分隔\n支持精确匹配和部分匹配，不区分大小写\n例如：举报,倍速,投屏,弹幕",
              @"detail" : @"逗号分隔按钮名",
              @"cellType" : @20,
              @"imageName" : @"ic_eyeslash_outlined_16"
          }
      ];

      for (NSDictionary *dict in modernpanelSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict];

          // 特殊处理隐藏面板项目选项（文本输入）
          if ([item.identifier isEqualToString:@"DYYYHidePanelItems"]) {
              NSString *savedItems = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYHidePanelItems"];
              item.detail = savedItems.length > 0 ? savedItems : @"逗号分隔按钮名";

              item.cellTappedBlock = ^{
                if (!item.isEnable)
                    return;
                NSString *defaultText = [item.detail isEqualToString:@"逗号分隔按钮名"] ? @"" : item.detail;
                [DYYYSettingsHelper showTextInputAlert:@"隐藏面板项目"
                                           defaultText:defaultText
                                           placeholder:@"例如：举报,倍速,投屏,弹幕"
                                             onConfirm:^(NSString *text) {
                                               NSString *trimmedText = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                                               [DYYYSettingsHelper setUserDefaults:trimmedText forKey:@"DYYYHidePanelItems"];
                                               item.detail = trimmedText.length > 0 ? trimmedText : @"逗号分隔按钮名";
                                               [item refreshCell];
                                             }
                                              onCancel:nil];
              };
          }

          [modernpanels addObject:item];
      }

      // 【长按评论分类】
      NSMutableArray<DYYYSettingDescriptor *> *commentpanel = [NSMutableArray array];
      NSArray *commentpanelSettings = @[
          @{@"identifier" : @"DYYYHideCommentShareToFriends", @"title" : @"隐藏评论分享", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideCommentLongPressCopy", @"title" : @"隐藏评论复制", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideCommentLongPressSaveImage", @"title" : @"隐藏评论保存", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideCommentLongPressReport", @"title" : @"隐藏评论举报", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideCommentLongPressSearch", @"title" : @"隐藏评论搜索", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideCommentLongPressDaily", @"title" : @"隐藏评论转发日常", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideCommentLongPressVideoReply", @"title" : @"隐藏评论视频回复", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"},
          @{@"identifier" : @"DYYYHideCommentLongPressPictureSearch", @"title" : @"隐藏评论识别图片", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"}
      ];
      for (NSDictionary *dict in commentpanelSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict];
          [commentpanel addObject:item];
      }
      // 创建并组织所有section
      NSMutableArray *sections = [NSMutableArray array];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"主界面元素" items:mainUiItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"视频播放界面" items:videoUiItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"侧边栏元素" items:sidebarItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"消息页与我的页" items:messageAndMineItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"提示与位置信息" items:infoItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"直播间界面" items:livestreamItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"隐藏面板功能" footerTitle:@"隐藏视频长按面板中的功能" items:modernpanels]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"隐藏长按评论功能" footerTitle:@"隐藏评论长按面板中的功能" items:commentpanel]];
      [DYYYSettingsRegistry registerSections:sections category:@"隐藏设置"];
      if ([DYYYSettingsRegistry isBuilding]) {
          return;
      }

      // 创建并推入二级设置页面
      DYYYSettingViewController *subVC = [DYYYSettingsHelper createSubSettingsViewController:@"隐藏设置" sections:sections];
      [[DYYYSettingsCoordinator navigationController] pushViewController:(UIViewController *)subVC animated:YES];
    };
    [mainItems addObject:hideSettingItem];

    // 创建顶栏移除分类项
    DYYYSettingDescriptor *removeSettingItem = [[DYYYSettingDescriptor.class alloc] init];
    removeSettingItem.identifier = @"DYYYRemoveSettings";
    removeSettingItem.title = @"顶栏移除";
    removeSettingItem.type = 0;
    removeSettingItem.svgIconImageName = @"ic_doublearrowup_outlined_20";
    removeSettingItem.cellType = 26;
    removeSettingItem.colorStyle = 0;
    removeSettingItem.isEnable = YES;
    removeSettingItem.cellTappedBlock = ^{
      // 创建顶栏移除二级界面的设置项
      NSMutableArray<DYYYSettingDescriptor *> *removeSettingsItems = [NSMutableArray array];
      NSArray *removeSettings = @[
          @{@"identifier" : @"DYYYHideHotContainer", @"title" : @"移除推荐", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xmark_outlined_20"},
          @{@"identifier" : @"DYYYHideFriend", @"title" : @"移除朋友", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xmark_outlined_20"},
          @{@"identifier" : @"DYYYHideFollow", @"title" : @"移除关注", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xmark_outlined_20"},
          @{@"identifier" : @"DYYYHideMediumVideo", @"title" : @"移除精选", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xmark_outlined_20"},
          @{@"identifier" : @"DYYYHideMall", @"title" : @"移除商城", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xmark_outlined_20"},
          @{@"identifier" : @"DYYYHideNearby", @"title" : @"移除同城", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xmark_outlined_20"},
          @{@"identifier" : @"DYYYHideGroupon", @"title" : @"移除团购", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xmark_outlined_20"},
          @{@"identifier" : @"DYYYHideTabLive", @"title" : @"移除直播", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xmark_outlined_20"},
          @{@"identifier" : @"DYYYHidePadHot", @"title" : @"移除热点", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xmark_outlined_20"},
          @{@"identifier" : @"DYYYHideHangout", @"title" : @"移除经验", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xmark_outlined_20"},
          @{@"identifier" : @"DYYYHidePlaylet", @"title" : @"移除短剧", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xmark_outlined_20"},
          @{@"identifier" : @"DYYYHideCinema", @"title" : @"移除看剧", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xmark_outlined_20"},
          @{@"identifier" : @"DYYYHideKidsV2", @"title" : @"移除少儿", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xmark_outlined_20"},
          @{@"identifier" : @"DYYYHideGame", @"title" : @"移除游戏", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xmark_outlined_20"},
          @{@"identifier" : @"DYYYHideMediumVideo", @"title" : @"移除长视频", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xmark_outlined_20"}
      ];

      for (NSDictionary *dict in removeSettings) {
          DYYYSettingDescriptor *item = [[DYYYSettingDescriptor.class alloc] init];
          item.identifier = dict[@"identifier"];
          item.title = dict[@"title"];
          NSString *savedDetail = [[NSUserDefaults standardUserDefaults] objectForKey:item.identifier];
          item.detail = savedDetail ?: dict[@"detail"];
          item.type = 1000;
          item.svgIconImageName = dict[@"imageName"];
          item.cellType = [dict[@"cellType"] integerValue];
          item.colorStyle = 0;
          item.isEnable = YES;
          item.isSwitchOn = [DYYYSettingsHelper getUserDefaults:item.identifier];
          __weak DYYYSettingDescriptor *weakItem = item;
          item.switchChangedBlock = ^{
            __strong DYYYSettingDescriptor *strongItem = weakItem;
            if (strongItem) {
                BOOL isSwitchOn = !strongItem.isSwitchOn;
                strongItem.isSwitchOn = isSwitchOn;
                [DYYYSettingsHelper setUserDefaults:@(isSwitchOn) forKey:strongItem.identifier];
            }
          };
          [removeSettingsItems addObject:item];
      }

      NSMutableArray *sections = [NSMutableArray array];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"顶栏选项" items:removeSettingsItems]];

      [DYYYSettingsRegistry registerSections:sections category:@"顶栏移除"];
      if ([DYYYSettingsRegistry isBuilding]) {
          return;
      }

      DYYYSettingViewController *subVC = [DYYYSettingsHelper createSubSettingsViewController:@"顶栏移除" sections:sections];
      [[DYYYSettingsCoordinator navigationController] pushViewController:(UIViewController *)subVC animated:YES];
    };
    [mainItems addObject:removeSettingItem];

    // 创建增强设置分类项
    DYYYSettingDescriptor *enhanceSettingItem = [[DYYYSettingDescriptor.class alloc] init];
    enhanceSettingItem.identifier = @"DYYYEnhanceSettings";
    enhanceSettingItem.title = @"增强设置";
    enhanceSettingItem.type = 0;
    enhanceSettingItem.svgIconImageName = @"ic_squaresplit_outlined_20";
    enhanceSettingItem.cellType = 26;
    enhanceSettingItem.colorStyle = 0;
    enhanceSettingItem.isEnable = YES;
    enhanceSettingItem.cellTappedBlock = ^{
      // 创建增强设置二级界面的设置项
      NSMutableDictionary *cellTapHandlers = [NSMutableDictionary dictionary];

      // 【长按面板设置】分类
      NSMutableArray<DYYYSettingDescriptor *> *longPressItems = [NSMutableArray array];
      NSArray *longPressSettings = @[
          @{@"identifier" : @"DYYYLongPressSaveVideo", @"title" : @"长按保存当前视频", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_boxarrowdown_outlined"},
          @{@"identifier" : @"DYYYLongPressSaveCover", @"title" : @"长按保存视频封面", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_boxarrowdown_outlined"},
          @{@"identifier" : @"DYYYLongPressSaveAudio", @"title" : @"长按保存视频音乐", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_boxarrowdown_outlined"},
          @{@"identifier" : @"DYYYLongPressSaveCurrentImage", @"title" : @"长按保存当前图片", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_boxarrowdown_outlined"},
          @{@"identifier" : @"DYYYLongPressSaveAllImages", @"title" : @"长按保存所有图片", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_boxarrowdown_outlined"},
          @{@"identifier" : @"DYYYLongPressCreateVideo", @"title" : @"长按面板制作视频", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_videosearch_outlined_20"},
          @{@"identifier" : @"DYYYLongPressCopyText", @"title" : @"长按复制视频文案", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_rectangleonrectangleup_outlined_20"},
          @{@"identifier" : @"DYYYLongPressCopyLink", @"title" : @"长按复制分享链接", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_rectangleonrectangleup_outlined_20"},
          @{@"identifier" : @"DYYYLongPressApiDownload", @"title" : @"长按接口解析下载", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_cloudarrowdown_outlined_20"},
          @{@"identifier" : @"DYYYLongPressFilterUser", @"title" : @"长按面板过滤用户", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_userban_outlined_20"},
          @{@"identifier" : @"DYYYLongPressFilterTitle", @"title" : @"长按面板过滤文案", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_funnel_outlined_20"},
          @{@"identifier" : @"DYYYLongPressTimerClose", @"title" : @"长按定时关闭抖音", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_c_alarm_outlined"}
      ];

      for (NSDictionary *dict in longPressSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict];
          [longPressItems addObject:item];
      }

      // 【媒体保存】分类
      NSMutableArray<DYYYSettingDescriptor *> *downloadItems = [NSMutableArray array];
      NSArray *downloadSettings = @[
          @{
              @"identifier" : @"DYYYInterfaceDownload",
              @"title" : @"接口解析保存媒体",
              @"subTitle" : @"填入自定义的解析接口，标准格式请查阅\nGithub 仓库内的 README 文件",
              @"detail" : @"",
              @"cellType" : @20,
              @"imageName" : @"ic_cloudarrowdown_outlined_20"
          },
          @{@"identifier" : @"DYYYShowAllVideoQuality", @"title" : @"接口显示清晰选项", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_hamburgernut_outlined_20"},
          @{@"identifier" : @"DYYYEnableSheetBlur", @"title" : @"保存面板玻璃效果", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_list_outlined"},
          @{@"identifier" : @"DYYYSheetBlurTransparent", @"title" : @"面板毛玻璃透明度", @"detail" : @"0-1小数", @"cellType" : @26, @"imageName" : @"ic_eye_outlined_20"},
          @{@"identifier" : @"DYYYCommentLivePhotoNotWaterMark", @"title" : @"移除评论实况水印", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_livephoto_outlined_20"},
          @{@"identifier" : @"DYYYCommentNotWaterMark", @"title" : @"移除评论图片水印", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_removeimage_outlined_20"}, @{
              @"identifier" : @"DYYYForceDownloadCommentImage",
              @"title" : @"保存评论区图片",
              @"subTitle" : @"长按评论可保存所有实况和图片",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_image_outlined"
          },
          @{
              @"identifier" : @"DYYYForceDownloadCommentAudio",
              @"title" : @"保存评论区语音",
              @"subTitle" : @"长按语音评论可下载并分享",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_playbackquaver_outlined"
          },
          @{
              @"identifier" : @"DYYYForceDownloadEmotion",
              @"title" : @"保存评论区表情包",
              @"subTitle" : @"长按评论或者长按表情包",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_emoji_outlined"
          },
          @{@"identifier" : @"DYYYForceDownloadPreviewEmotion", @"title" : @"保存预览页表情包", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_emoji_outlined"},
          @{@"identifier" : @"DYYYForceDownloadIMEmotion", @"title" : @"保存聊天页表情包", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_emoji_outlined"},
          @{@"identifier" : @"DYYYHapticFeedbackEnabled", @"title" : @"下载完成震动反馈", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_gearsimplify_outlined_20"}
      ];

      for (NSDictionary *dict in downloadSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict cellTapHandlers:cellTapHandlers];

          // 特殊处理接口解析保存媒体选项
          if ([item.identifier isEqualToString:@"DYYYInterfaceDownload"]) {
              // 获取已保存的接口URL
              NSString *savedURL = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYInterfaceDownload"];
              item.detail = savedURL.length > 0 ? savedURL : @"不填关闭";

              item.cellTappedBlock = ^{
                NSString *defaultText = [item.detail isEqualToString:@"不填关闭"] ? @"" : item.detail;
                [DYYYSettingsHelper showTextInputAlert:@"设置媒体解析接口"
                                           defaultText:defaultText
                                           placeholder:@"解析接口以url=结尾"
                                             onConfirm:^(NSString *text) {
                                               // 保存用户输入的接口URL
                                               NSString *trimmedText = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                                               [DYYYSettingsHelper setUserDefaults:trimmedText forKey:@"DYYYInterfaceDownload"];

                                               item.detail = trimmedText.length > 0 ? trimmedText : @"不填关闭";

                                               [item refreshCell];
                                             }
                                              onCancel:nil];
              };
          }
          [downloadItems addObject:item];
      }

      // 【ABTest】分类
      NSMutableArray<DYYYSettingDescriptor *> *hotUpdateItems = [NSMutableArray array];
      NSArray *hotUpdateSettings = @[
          @{@"identifier" : @"DYYYABTestBlockEnabled", @"title" : @"禁止下发配置", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_fire_outlined_20"},
          @{@"identifier" : @"DYYYABTestModeString", @"title" : @"配置应用方式", @"detail" : @"", @"cellType" : @26, @"imageName" : @"ic_enterpriseservice_outlined"},
          @{@"identifier" : @"DYYYRemoteConfigURL", @"title" : @"远程配置地址", @"detail" : @"", @"cellType" : @26, @"imageName" : @"ic_cloudarrowdown_outlined_20"},
          @{@"identifier" : @"DYYYCheckUpdate", @"title" : @"检查配置更新", @"detail" : @"", @"cellType" : @26, @"imageName" : @"ic_cloudarrowdown_outlined_20"},
          @{@"identifier" : @"SaveCurrentABTestData", @"title" : @"导出当前配置", @"detail" : @"", @"cellType" : @26, @"imageName" : @"ic_memorycard_outlined_20"},
          @{@"identifier" : @"SaveABTestConfigFile", @"title" : @"导出本地配置", @"detail" : @"", @"cellType" : @26, @"imageName" : @"ic_memorycard_outlined_20"},
          @{@"identifier" : @"LoadABTestConfigFile", @"title" : @"导入本地配置", @"detail" : @"", @"cellType" : @26, @"imageName" : @"ic_phonearrowup_outlined_20"},
          @{@"identifier" : @"DeleteABTestConfigFile", @"title" : @"删除本地配置", @"detail" : @"", @"cellType" : @26, @"imageName" : @"ic_trash_outlined_20"}
      ];

      // --- 声明一个__block变量来持有SaveABTestConfigFileitem ---
      __block DYYYSettingDescriptor *saveABTestConfigFileItemRef = nil;
      __block DYYYSettingDescriptor *remoteURLItemRef = nil;
      __block DYYYSettingDescriptor *checkUpdateItemRef = nil;
      __block DYYYSettingDescriptor *loadConfigItemRef = nil;
      __block DYYYSettingDescriptor *deleteConfigItemRef = nil;
      // --- 定义一个用于刷新SaveABTestConfigFileitem的局部block ---
      void (^refreshSaveABTestConfigFileItem)(void) = ^{
        if (!saveABTestConfigFileItemRef)
            return;

        // 在后台队列执行文件状态检查和大小获取
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
          __weak DYYYSettingDescriptor *weakSaveItem = saveABTestConfigFileItemRef;
          __strong DYYYSettingDescriptor *strongSaveItem = weakSaveItem;
          if (!strongSaveItem) {
              return;
          }

          NSFileManager *fileManager = [NSFileManager defaultManager];
          NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
          NSString *documentsDirectory = [paths firstObject];
          NSString *dyyyFolderPath = [documentsDirectory stringByAppendingPathComponent:@"DYYY"];
          NSString *jsonFilePath = [dyyyFolderPath stringByAppendingPathComponent:@"abtest_data_fixed.json"];

          NSString *loadingStatus = [DYYYABTestHook isLocalConfigLoaded] ? @"已加载：" : @"未加载：";

          NSString *detailText = nil;
          BOOL isItemEnable = NO;

          if (![fileManager fileExistsAtPath:jsonFilePath]) {
              detailText = [NSString stringWithFormat:@"%@ (文件不存在)", loadingStatus];
              isItemEnable = NO;
          } else {
              unsigned long long jsonFileSize = 0;
              NSError *attributesError = nil;
              NSDictionary *attributes = [fileManager attributesOfItemAtPath:jsonFilePath error:&attributesError];
              if (!attributesError && attributes) {
                  jsonFileSize = [attributes fileSize];
                  detailText = [NSString stringWithFormat:@"%@ %@", loadingStatus, [DYYYUtils formattedSize:jsonFileSize]];
                  isItemEnable = YES;
              } else {
                  detailText = [NSString stringWithFormat:@"%@ (读取失败: %@)", loadingStatus, attributesError.localizedDescription ?: @"未知错误"];
                  isItemEnable = NO;
              }
          }

          // 回到主线程更新 UI
          dispatch_async(dispatch_get_main_queue(), ^{
            // 在主线程更新 UI 前检查 item 是否仍然存在
            __strong DYYYSettingDescriptor *strongSaveItemAgain = weakSaveItem;
            if (strongSaveItemAgain) {
                strongSaveItemAgain.detail = detailText;
                strongSaveItemAgain.isEnable = isItemEnable;
                [strongSaveItemAgain refreshCell];
            }
          });
        });
      };

      void (^refreshConfigConflictState)(void) = ^{
        BOOL remoteMode = [DYYYABTestHook isRemoteMode];
        BOOL localLoaded = [DYYYABTestHook isLocalConfigLoaded];
        if (remoteMode) {
            if (loadConfigItemRef) {
                loadConfigItemRef.isEnable = NO;
                [loadConfigItemRef refreshCell];
            }
            if (deleteConfigItemRef) {
                deleteConfigItemRef.isEnable = NO;
                [deleteConfigItemRef refreshCell];
            }
            if (remoteURLItemRef) {
                remoteURLItemRef.isEnable = YES;
                [remoteURLItemRef refreshCell];
            }
            if (checkUpdateItemRef) {
                checkUpdateItemRef.isEnable = YES;
                [checkUpdateItemRef refreshCell];
            }
        } else if (localLoaded) {
            if (remoteURLItemRef) {
                remoteURLItemRef.isEnable = NO;
                [remoteURLItemRef refreshCell];
            }
            if (checkUpdateItemRef) {
                checkUpdateItemRef.isEnable = NO;
                [checkUpdateItemRef refreshCell];
            }
            if (loadConfigItemRef) {
                loadConfigItemRef.isEnable = YES;
                [loadConfigItemRef refreshCell];
            }
            if (deleteConfigItemRef) {
                deleteConfigItemRef.isEnable = YES;
                [deleteConfigItemRef refreshCell];
            }
        } else {
            if (remoteURLItemRef) {
                remoteURLItemRef.isEnable = YES;
                [remoteURLItemRef refreshCell];
            }
            if (checkUpdateItemRef) {
                checkUpdateItemRef.isEnable = YES;
                [checkUpdateItemRef refreshCell];
            }
            if (loadConfigItemRef) {
                loadConfigItemRef.isEnable = YES;
                [loadConfigItemRef refreshCell];
            }
            if (deleteConfigItemRef) {
                deleteConfigItemRef.isEnable = YES;
                [deleteConfigItemRef refreshCell];
            }
        }
      };

      self.remoteToken = [[NSNotificationCenter defaultCenter] addObserverForName:DYYY_REMOTE_CONFIG_CHANGED_NOTIFICATION
                                                                           object:nil
                                                                            queue:nil
                                                                       usingBlock:^(NSNotification *_Nonnull note) {
                                                                         dispatch_async(dispatch_get_main_queue(), refreshConfigConflictState);
                                                                       }];

      for (NSDictionary *dict in hotUpdateSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict];

          if ([item.identifier isEqualToString:@"DYYYABTestBlockEnabled"]) {
              item.switchChangedBlock = ^{
                BOOL newValue = !item.isSwitchOn;

                if (newValue) {
                    [DYYYBottomAlertView showAlertWithTitle:@"禁止 ABTest 下发配置"
                        message:@"这将暂停接收测试新功能的推送。确定要继续吗？"
                        avatarURL:nil
                        cancelButtonText:@"取消"
                        confirmButtonText:@"确定"
                        cancelAction:^{
                          item.isSwitchOn = !newValue;
                          [item refreshCell];
                        }
                        closeAction:nil
                        confirmAction:^{
                          item.isSwitchOn = newValue;
                          [DYYYSettingsHelper setUserDefaults:@(newValue) forKey:@"DYYYABTestBlockEnabled"];

                          [DYYYABTestHook setABTestBlockEnabled:newValue];
                        }];
                } else {
                    item.isSwitchOn = newValue;
                    [DYYYSettingsHelper setUserDefaults:@(newValue) forKey:@"DYYYABTestBlockEnabled"];
                    [DYYYUtils showToast:@"已允许 ABTest 下发配置，重启后生效。"];
                }
              };
          } else if ([item.identifier isEqualToString:@"DYYYABTestModeString"]) {
              BOOL isPatchMode = [DYYYABTestHook isPatchMode];
              if ([DYYYABTestHook isRemoteMode]) {
                  item.detail = isPatchMode ? @"远程模式(覆写)" : @"远程模式(替换)";
              } else {
                  item.detail = isPatchMode ? @"覆写模式" : @"替换模式";
              }

              item.cellTappedBlock = ^{
                if (!item.isEnable)
                    return;
                NSString *currentMode = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYABTestModeString"] ?: @"替换模式：忽略原配置，使用新数据";

                NSArray *modeOptions = @[ @"覆写模式：保留原设置，覆盖同名项", @"替换模式：忽略原配置，使用新数据", DYYY_REMOTE_MODE_STRING ];

                [DYYYOptionsSelectionView showWithPreferenceKey:@"DYYYABTestModeString"
                                                   optionsArray:modeOptions
                                                     headerText:@"选择本地配置的应用方式"
                                                 onPresentingVC:[DYYYSettingsCoordinator presenter]
                                               selectionChanged:^(NSString *selectedValue) {
                                                 BOOL isPatchMode = [DYYYABTestHook isPatchMode];
                                                 if ([DYYYABTestHook isRemoteMode]) {
                                                     item.detail = isPatchMode ? @"远程模式(覆写)" : @"远程模式(替换)";
                                                 } else {
                                                     item.detail = isPatchMode ? @"覆写模式" : @"替换模式";
                                                 }

                                                 BOOL wasRemote = [[NSUserDefaults standardUserDefaults] boolForKey:DYYY_REMOTE_CONFIG_FLAG_KEY];

                                                 if ([selectedValue isEqualToString:DYYY_REMOTE_MODE_STRING]) {
                                                     [DYYYSettingsHelper setUserDefaults:@(YES) forKey:DYYY_REMOTE_CONFIG_FLAG_KEY];
                                                     refreshConfigConflictState();
                                                 } else {
                                                     if (wasRemote) {
                                                         [DYYYSettingsHelper setUserDefaults:@(NO) forKey:DYYY_REMOTE_CONFIG_FLAG_KEY];
                                                         dispatch_async(dispatch_get_main_queue(), refreshConfigConflictState);
                                                     }
                                                 }

                                                 if (![selectedValue isEqualToString:currentMode]) {
                                                     [DYYYABTestHook applyFixedABTestData];
                                                 }
                                                 [item refreshCell];
                                               }];
              };
          } else if ([item.identifier isEqualToString:@"DYYYRemoteConfigURL"]) {
              remoteURLItemRef = item;
              NSString *savedURL = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYRemoteConfigURL"];
              item.detail = savedURL.length > 0 ? savedURL : DYYY_DEFAULT_ABTEST_URL;
              item.cellTappedBlock = ^{
                if (!item.isEnable)
                    return;
                NSString *defaultText = item.detail;
                [DYYYSettingsHelper showTextInputAlert:@"设置远程配置地址"
                                           defaultText:defaultText
                                           placeholder:@"JSON URL"
                                             onConfirm:^(NSString *text) {
                                               NSString *trimmedText = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                                               [DYYYSettingsHelper setUserDefaults:trimmedText forKey:@"DYYYRemoteConfigURL"];
                                               item.detail = trimmedText.length > 0 ? trimmedText : DYYY_DEFAULT_ABTEST_URL;
                                               [item refreshCell];
                                             }
                                              onCancel:nil];
              };
          } else if ([item.identifier isEqualToString:@"DYYYCheckUpdate"]) {
              checkUpdateItemRef = item;
              item.cellTappedBlock = ^{
                if (!item.isEnable)
                    return;
                [DYYYUtils showToast:@"正在检查更新..."];
                [DYYYABTestHook checkForRemoteConfigUpdate:YES];
              };
          } else if ([item.identifier isEqualToString:@"SaveCurrentABTestData"]) {
              item.detail = @"(获取中...)";
              item.isEnable = NO;

              // 在后台队列获取数据并更新 UI
              dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                __weak DYYYSettingDescriptor *weakItem = item;
                __strong DYYYSettingDescriptor *strongItem = weakItem;
                if (!strongItem) {
                    return;
                }

                NSDictionary *currentData = [DYYYABTestHook getCurrentABTestData];

                NSString *detailText = nil;
                BOOL isItemEnable = NO;
                NSData *jsonDataForSize = nil;

                if (!currentData) {
                    detailText = @"(获取失败)";
                    isItemEnable = NO;
                } else {
                    NSError *serializationError = nil;
                    jsonDataForSize = [NSJSONSerialization dataWithJSONObject:currentData options:NSJSONWritingPrettyPrinted error:&serializationError];
                    if (!serializationError && jsonDataForSize) {
                        detailText = [DYYYUtils formattedSize:jsonDataForSize.length];
                        isItemEnable = YES;
                    } else {
                        detailText = [NSString stringWithFormat:@"(序列化失败: %@)", serializationError.localizedDescription ?: @"未知错误"];
                        isItemEnable = NO;
                    }
                }

                // 回到主线程更新 UI
                dispatch_async(dispatch_get_main_queue(), ^{
                  __strong DYYYSettingDescriptor *strongItemAgain = weakItem;
                  if (strongItemAgain) {
                      strongItemAgain.detail = detailText;
                      strongItemAgain.isEnable = isItemEnable;
                      [strongItemAgain refreshCell];
                  }
                });
              });

              item.cellTappedBlock = ^{
                NSDictionary *currentData = [DYYYABTestHook getCurrentABTestData];

                if (!currentData) {
                    [DYYYUtils showToast:@"ABTest 配置获取失败"];
                    return;
                }

                NSError *error;
                NSData *sortedJsonData = [NSJSONSerialization dataWithJSONObject:currentData options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];

                if (error) {
                    [DYYYUtils showToast:@"ABTest 配置序列化失败"];
                    return;
                }

                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                [formatter setDateFormat:@"yyyyMMdd_HHmmss"];
                NSString *timestamp = [formatter stringFromDate:[NSDate date]];
                NSString *tempFile = [NSString stringWithFormat:@"ABTest_Config_%@.json", timestamp];
                NSString *tempFilePath = [DYYYUtils cachePathForFilename:tempFile];

                BOOL success = [sortedJsonData writeToFile:tempFilePath atomically:YES];

                if (!success) {
                    [DYYYUtils showToast:@"临时文件创建失败"];
                    return;
                }

                NSURL *tempFileURL = [NSURL fileURLWithPath:tempFilePath];
                UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithURLs:@[ tempFileURL ] inMode:UIDocumentPickerModeExportToService];

                DYYYBackupPickerDelegate *pickerDelegate = [[DYYYBackupPickerDelegate alloc] init];
                pickerDelegate.tempFilePath = tempFilePath;
                pickerDelegate.completionBlock = ^(NSURL *url) {
                  [DYYYUtils showToast:@"ABTest 配置已保存"];
                };

                static char kABTestPickerDelegateKey;
                documentPicker.delegate = pickerDelegate;
                objc_setAssociatedObject(documentPicker, &kABTestPickerDelegateKey, pickerDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                UIViewController *topVC = [DYYYSettingsCoordinator presenter];
                [topVC presentViewController:documentPicker animated:YES completion:nil];
              };
          } else if ([item.identifier isEqualToString:@"SaveABTestConfigFile"]) {
              item.detail = @"(获取中...)";

              saveABTestConfigFileItemRef = item;
              refreshSaveABTestConfigFileItem();

              item.cellTappedBlock = ^{
                if (!item.isEnable)
                    return;
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                NSString *documentsDirectory = [paths firstObject];

                NSString *dyyyFolderPath = [documentsDirectory stringByAppendingPathComponent:@"DYYY"];
                NSString *jsonFilePath = [dyyyFolderPath stringByAppendingPathComponent:@"abtest_data_fixed.json"];

                NSData *jsonData = [NSData dataWithContentsOfFile:jsonFilePath];
                if (!jsonData) {
                    [DYYYUtils showToast:@"本地配置获取失败"];
                    return;
                }

                NSError *error;
                NSDictionary *originalData = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
                if (error || ![originalData isKindOfClass:[NSDictionary class]]) {
                    [DYYYUtils showToast:@"本地配置序列化失败"];
                    return;
                }

                NSData *sortedJsonData = [NSJSONSerialization dataWithJSONObject:originalData options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
                if (error || !sortedJsonData) {
                    [DYYYUtils showToast:@"排序数据序列化失败"];
                    return;
                }

                // 创建临时文件
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                [formatter setDateFormat:@"yyyyMMdd_HHmmss"];
                NSString *timestamp = [formatter stringFromDate:[NSDate date]];
                NSString *tempFile = [NSString stringWithFormat:@"abtest_data_fixed_%@.json", timestamp];
                NSString *tempFilePath = [DYYYUtils cachePathForFilename:tempFile];

                if (![sortedJsonData writeToFile:tempFilePath atomically:YES]) {
                    [DYYYUtils showToast:@"临时文件创建失败"];
                    return;
                }

                UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithURLs:@[ [NSURL fileURLWithPath:tempFilePath] ]
                                                                                                               inMode:UIDocumentPickerModeExportToService];

                DYYYBackupPickerDelegate *pickerDelegate = [[DYYYBackupPickerDelegate alloc] init];
                pickerDelegate.tempFilePath = tempFilePath;
                pickerDelegate.completionBlock = ^(NSURL *url) {
                  [DYYYUtils showToast:@"本地配置已保存"];
                };

                static char kABTestConfigPickerDelegateKey;
                documentPicker.delegate = pickerDelegate;
                objc_setAssociatedObject(documentPicker, &kABTestConfigPickerDelegateKey, pickerDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                UIViewController *topVC = [DYYYSettingsCoordinator presenter];
                [topVC presentViewController:documentPicker animated:YES completion:nil];
              };
          } else if ([item.identifier isEqualToString:@"LoadABTestConfigFile"]) {
              loadConfigItemRef = item;
              item.cellTappedBlock = ^{
                if (!item.isEnable)
                    return;
                BOOL isPatchMode = [DYYYABTestHook isPatchMode];

                NSString *confirmTitle, *confirmMessage;
                if (isPatchMode) {
                    confirmTitle = @"覆写模式";
                    confirmMessage = @"\n导入后将保留原设置并覆盖同名项，\n\n点击确定后继续操作。\n";
                } else {
                    confirmTitle = @"替换模式";
                    confirmMessage = @"\n导入后将忽略原设置并使用新数据，\n\n点击确定后继续操作。\n";
                }
                DYYYAboutDialogView *confirmDialog = [[DYYYAboutDialogView alloc] initWithTitle:confirmTitle message:confirmMessage];
                confirmDialog.onConfirm = ^{
                  UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[ @"public.json" ] inMode:UIDocumentPickerModeImport];

                  DYYYBackupPickerDelegate *pickerDelegate = [[DYYYBackupPickerDelegate alloc] init];
                  pickerDelegate.completionBlock = ^(NSURL *url) {
                    // Delegate 回调通常在主线程，但文件操作和 Hook 调用应在后台
                    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                      __weak DYYYSettingDescriptor *weakSaveItem = saveABTestConfigFileItemRef;

                      NSURL *sourceURL = url;  // 用户选择的源文件 URL

                      NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                      NSString *documentsDirectory = [paths firstObject];
                      NSString *dyyyFolderPath = [documentsDirectory stringByAppendingPathComponent:@"DYYY"];
                      NSURL *destinationURL = [NSURL fileURLWithPath:[dyyyFolderPath stringByAppendingPathComponent:@"abtest_data_fixed.json"]];

                      NSFileManager *fileManager = [NSFileManager defaultManager];
                      NSError *error = nil;
                      BOOL success = NO;
                      NSString *message = nil;

                      if (![fileManager fileExistsAtPath:dyyyFolderPath]) {
                          [fileManager createDirectoryAtPath:dyyyFolderPath withIntermediateDirectories:YES attributes:nil error:&error];
                          if (error) {
                              message = [NSString stringWithFormat:@"创建目录失败: %@", error.localizedDescription];
                          }
                      }

                      if (!message) {
                          // 在同一个目录下创建一个临时文件 URL 以确保原子性
                          NSString *tempFileName = [NSUUID UUID].UUIDString;
                          NSURL *temporaryURL = [NSURL fileURLWithPath:[dyyyFolderPath stringByAppendingPathComponent:tempFileName]];

                          if ([fileManager copyItemAtURL:sourceURL toURL:temporaryURL error:&error]) {
                              if ([fileManager replaceItemAtURL:destinationURL withItemAtURL:temporaryURL backupItemName:nil options:0 resultingItemURL:nil error:&error]) {
                                  [DYYYABTestHook cleanLocalABTestData];
                                  [DYYYABTestHook loadLocalABTestConfig];
                                  [DYYYABTestHook applyFixedABTestData];
                                  [DYYYSettingsHelper setUserDefaults:@(NO) forKey:DYYY_REMOTE_CONFIG_FLAG_KEY];
                                  [[NSNotificationCenter defaultCenter] postNotificationName:DYYY_REMOTE_CONFIG_CHANGED_NOTIFICATION object:nil];
                                  success = YES;
                                  message = @"配置已导入，部分设置需重启应用后生效";
                              } else {
                                  [fileManager removeItemAtURL:temporaryURL error:nil];
                                  message = [NSString stringWithFormat:@"导入失败 (替换文件失败): %@", error.localizedDescription];
                              }
                          } else {
                              message = [NSString stringWithFormat:@"导入失败 (复制到临时文件失败): %@", error.localizedDescription];
                          }
                      }
                      // 回到主线程显示 Toast 和更新 UI
                      dispatch_async(dispatch_get_main_queue(), ^{
                        __strong DYYYSettingDescriptor *strongSaveItemAgain = weakSaveItem;

                        // 无论成功与否，都显示 Toast 告知用户结果
                        NSString *message = success ? @"配置已导入，部分设置需重启应用后生效" : [NSString stringWithFormat:@"导入失败: %@", error.localizedDescription];
                        [DYYYUtils showToast:message];

                        // 仅在导入成功且 item 仍然存在时更新 UI
                        if (success && strongSaveItemAgain) {
                            refreshSaveABTestConfigFileItem();
                            refreshConfigConflictState();
                        }
                      });
                    });
                  };

                  static char kPickerDelegateKey;
                  documentPicker.delegate = pickerDelegate;
                  objc_setAssociatedObject(documentPicker, &kPickerDelegateKey, pickerDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                  UIViewController *topVC = [DYYYSettingsCoordinator presenter];
                  [topVC presentViewController:documentPicker animated:YES completion:nil];
                };
                [confirmDialog show];
              };
          } else if ([item.identifier isEqualToString:@"DeleteABTestConfigFile"]) {
              deleteConfigItemRef = item;
              item.cellTappedBlock = ^{
                if (!item.isEnable)
                    return;
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                NSString *documentsDirectory = [paths firstObject];
                NSString *dyyyFolderPath = [documentsDirectory stringByAppendingPathComponent:@"DYYY"];
                NSString *configPath = [dyyyFolderPath stringByAppendingPathComponent:@"abtest_data_fixed.json"];

                if ([[NSFileManager defaultManager] fileExistsAtPath:configPath]) {
                    NSError *error = nil;
                    BOOL success = [[NSFileManager defaultManager] removeItemAtPath:configPath error:&error];

                    NSString *message = success ? @"本地配置已删除成功" : [NSString stringWithFormat:@"删除失败: %@", error.localizedDescription];
                    [DYYYUtils showToast:message];

                    if (success) {
                        [DYYYABTestHook cleanLocalABTestData];
                        [DYYYSettingsHelper setUserDefaults:@(NO) forKey:DYYY_REMOTE_CONFIG_FLAG_KEY];
                        [[NSNotificationCenter defaultCenter] postNotificationName:DYYY_REMOTE_CONFIG_CHANGED_NOTIFICATION object:nil];
                        // 删除成功后修改 SaveABTestConfigFile item 的状态
                        saveABTestConfigFileItemRef.detail = @"(文件已删除)";
                        saveABTestConfigFileItemRef.isEnable = NO;
                        [saveABTestConfigFileItemRef refreshCell];
                        refreshConfigConflictState();
                    }
                } else {
                    [DYYYUtils showToast:@"本地配置不存在"];
                }
              };
          }

          [hotUpdateItems addObject:item];
      }
      refreshConfigConflictState();

      // 【交互增强】分类
      NSMutableArray<DYYYSettingDescriptor *> *interactionItems = [NSMutableArray array];
      NSArray *interactionSettings = @[
          @{
              @"identifier" : @"DYYYDisableSettingsGesture",
              @"title" : @"禁用双指长按入口",
              @"subTitle" : @"开启后将禁用双指长按弹出的设置入口，开启或者关闭此选项都需要重启抖音以生效",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_gearsimplify_outlined_20"
          },
          @{
              @"identifier" : @"DYYYEntrance",
              @"title" : @"左侧边栏快捷入口",
              @"subTitle" : @"将侧边栏替换为 DYYY 快捷入口",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_circlearrowin_outlined_20"
          },
          @{
              @"identifier" : @"DYYYDisableSidebarGesture",
              @"title" : @"禁止侧滑进入边栏",
              @"subTitle" : @"禁止在首页最左边的页面时右滑进入侧边栏",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_circlearrowin_outlined_20"
          },
          @{
              @"identifier" : @"DYYYVideoGesture",
              @"title" : @"横屏视频交互增强",
              @"subTitle" : @"启用横屏视频的手势功能",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_phonearrowdown_outlined_20"
          },
          @{
              @"identifier" : @"DYYYDisableAutoEnterLive",
              @"title" : @"禁用自动进入直播",
              @"subTitle" : @"禁止顶栏直播下自动进入直播间",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_video_outlined_20"
          },
          @{
              @"identifier" : @"DYYYDisableAutoHideLive",
              @"title" : @"禁止直播标签收缩",
              @"subTitle" : @"禁止直播类型选择标签自动收缩成直播发现标签",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_video_outlined_20"
          },
          @{@"identifier" : @"DYYYEnableSaveAvatar", @"title" : @"启用保存他人头像", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_personcircleclean_outlined_20"},
          @{@"identifier" : @"DYYYCommentCopyText", @"title" : @"复制评论移除昵称", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_at_outlined_20"},
          @{
              @"identifier" : @"DYYYBioCopyText",
              @"title" : @"长按简介复制简介",
              @"subTitle" : @"长按个人主页的简介复制",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_rectangleonrectangleup_outlined_20"
          },
          @{
              @"identifier" : @"DYYYLongPressCopyTextEnabled",
              @"title" : @"长按文案复制文案",
              @"subTitle" : @"长按视频左下角的文案复制",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_rectangleonrectangleup_outlined_20"
          },
          @{
              @"identifier" : @"DYYYMusicCopyText",
              @"title" : @"评论音乐点击复制",
              @"subTitle" : @"含有音乐的视频打开评论区时，移除顶部歌曲去汽水听，点击复制歌曲名",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_quaver_outlined_20"
          },
          @{@"identifier" : @"DYYYAutoSelectOriginalPhoto", @"title" : @"启用自动勾选原图", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_image_outlined_20"},
          @{
              @"identifier" : @"DYYYEnableModernPanel",
              @"title" : @"启用新版长按面板",
              @"subTitle" : @"启用抖音灰度测试的新版长按面板",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_squaresplit_outlined_20"
          },
          @{@"identifier" : @"DYYYLongPressPanelBlur", @"title" : @"长按面板玻璃效果", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_squaresplit_outlined_20"},
          @{@"identifier" : @"DYYYLongPressPanelDark", @"title" : @"长按面板深色模式", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_sun_outlined"},
          @{
              @"identifier" : @"DYYYDefaultEnterWorks",
              @"title" : @"资料默认进入作品",
              @"subTitle" : @"禁止个人资料页自动进入橱窗等页面",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_playsquarestack_outlined_20"
          },
          @{@"identifier" : @"DYYYDisableHomeRefresh", @"title" : @"禁用点击首页刷新", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_arrowcircle_outlined_20"},
          @{
              @"identifier" : @"DYYYDisableDoubleTapLike",
              @"title" : @"禁用双击视频点赞",
              @"subTitle" : @"同时会禁用官方纯净模式的双击点赞",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_thumbsup_outlined_20"
          },
          @{
              @"identifier" : @"DYYYEnableDoubleOpenComment",
              @"title" : @"启用双击打开评论",
              @"subTitle" : @"与“双击打开菜单”互斥",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_comment_outlined_20"
          },
          @{
              @"identifier" : @"DYYYCommentShowDanmaku",
              @"title" : @"查看评论显示弹幕",
              @"subTitle" : @"打开评论区时保持弹幕可见",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_dansquare_outlined_20"
          },
          @{
              @"identifier" : @"DYYYEnableDoubleTapMenu",
              @"title" : @"启用双击打开菜单",
              @"subTitle" : @"与“双击打开评论”互斥，下方自定义",
              @"detail" : @"",
              @"cellType" : @37,
              @"imageName" : @"ic_xiaoxihuazhonghua_outlined_20"
          },
          @{
              @"identifier" : @"DYYYDoubleTapMenuSettings",
              @"title" : @"设置双击菜单项目",
              @"subTitle" : @"自定义双击打开菜单需要显示的项目",
              @"detail" : @"",
              @"cellType" : @20,
              @"imageName" : @"ic_squaresplit_outlined_20"
          }
      ];

      for (NSDictionary *dict in interactionSettings) {
          DYYYSettingDescriptor *item = [DYYYSettingsHelper createSettingItem:dict];
          if ([item.identifier isEqualToString:@"DYYYDoubleTapMenuSettings"]) {
              __weak DYYYSettingDescriptor *weakItem = item;
              item.cellTappedBlock = ^{
                __strong DYYYSettingDescriptor *strongItem = weakItem;
                if (!strongItem || (!strongItem.isEnable && ![DYYYSettingsRegistry isBuilding]))
                    return;
                NSMutableArray<DYYYSettingDescriptor *> *doubleTapItems = [NSMutableArray array];
                NSArray *doubleTapFunctions = @[
                    @{@"identifier" : @"DYYYDoubleTapDownload", @"title" : @"保存视频/图片", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_boxarrowdown_outlined"},
                    @{@"identifier" : @"DYYYDoubleTapDownloadAudio", @"title" : @"保存音频", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_boxarrowdown_outlined"},
                    @{@"identifier" : @"DYYYDoubleInterfaceDownload", @"title" : @"接口保存", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_cloudarrowdown_outlined_20"},
                    @{@"identifier" : @"DYYYDoubleCreateVideo", @"title" : @"制作视频", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_videosearch_outlined_20"},
                    @{@"identifier" : @"DYYYDoubleTapCopyDesc", @"title" : @"复制文案", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_rectangleonrectangleup_outlined_20"},
                    @{@"identifier" : @"DYYYDoubleTapComment", @"title" : @"打开评论", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_comment_outlined_20"},
                    @{@"identifier" : @"DYYYDoubleTapLike", @"title" : @"点赞视频", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_heart_outlined_20"},
                    @{@"identifier" : @"DYYYDoubleTapshowDislikeOnVideo", @"title" : @"长按面板", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xiaoxihuazhonghua_outlined_20"},
                    @{@"identifier" : @"DYYYDoubleTapshowSharePanel", @"title" : @"分享视频", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_share_outlined"},
                ];

                for (NSDictionary *dict in doubleTapFunctions) {
                    DYYYSettingDescriptor *functionItem = [DYYYSettingsHelper createSettingItem:dict];
                    [doubleTapItems addObject:functionItem];
                }
                NSMutableArray *sections = [NSMutableArray array];
                [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"设置双击菜单项目" items:doubleTapItems]];
                DYYYSettingViewController *subVC = [DYYYSettingsHelper createSubSettingsViewController:@"设置双击菜单项目" sections:sections];
                [[DYYYSettingsCoordinator navigationController] pushViewController:(UIViewController *)subVC animated:YES];
              };
          }

          if ([item.identifier isEqualToString:@"DYYYLongPressPanelDark"]) {
              BOOL isDarkPanelEnabled = [DYYYSettingsHelper getUserDefaults:item.identifier];
              item.svgIconImageName = isDarkPanelEnabled ? @"ic_moon_outlined" : @"ic_sun_outlined";

              void (^originalSwitchChangedBlock)(void) = item.switchChangedBlock;

              __weak DYYYSettingDescriptor *weakItem = item;
              item.switchChangedBlock = ^{
                __strong DYYYSettingDescriptor *strongItem = weakItem;
                if (!strongItem)
                    return;

                if (originalSwitchChangedBlock) {
                    originalSwitchChangedBlock();
                }

                if (strongItem.isSwitchOn) {
                    strongItem.svgIconImageName = @"ic_moon_outlined";
                } else {
                    strongItem.svgIconImageName = @"ic_sun_outlined";
                }
                [strongItem refreshCell];
              };
          }

          [interactionItems addObject:item];
      }

      // 创建并组织所有section
      NSMutableArray *sections = [NSMutableArray array];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"长按面板设置" items:longPressItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"媒体保存" items:downloadItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"交互增强" items:interactionItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"ABTest"
                                                         footerTitle:@"允许用户导出或导入抖音的 ABTest 配置。远程配置由 Nathalie 维护，在应用启动时自动更新远程配置。"
                                                               items:hotUpdateItems]];
      [DYYYSettingsRegistry registerSections:sections category:@"增强设置"];
      if ([DYYYSettingsRegistry isBuilding]) {
          return;
      }

      // 创建并推入二级设置页面
      DYYYSettingViewController *subVC = [DYYYSettingsHelper createSubSettingsViewController:@"增强设置" sections:sections];
      [[DYYYSettingsCoordinator navigationController] pushViewController:(UIViewController *)subVC animated:YES];
    };

    [mainItems addObject:enhanceSettingItem];

    // 创建悬浮按钮设置分类项
    DYYYSettingDescriptor *floatButtonSettingItem = [[DYYYSettingDescriptor.class alloc] init];
    floatButtonSettingItem.identifier = @"DYYYFloatButtonSettings";
    floatButtonSettingItem.title = @"悬浮按钮";
    floatButtonSettingItem.type = 0;
    floatButtonSettingItem.svgIconImageName = @"ic_gongchuang_outlined_20";
    floatButtonSettingItem.cellType = 26;
    floatButtonSettingItem.colorStyle = 0;
    floatButtonSettingItem.isEnable = YES;
    floatButtonSettingItem.cellTappedBlock = ^{
      // 创建悬浮按钮设置二级界面的设置项

      // 快捷倍速section
      NSMutableArray<DYYYSettingDescriptor *> *speedButtonItems = [NSMutableArray array];

      // 倍速按钮
      DYYYSettingDescriptor *enableSpeedButton = [DYYYSettingsHelper
          createSettingItem:@{@"identifier" : @"DYYYEnableFloatSpeedButton", @"title" : @"启用快捷倍速按钮", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_xspeed_outlined"}];
      [speedButtonItems addObject:enableSpeedButton];

      // 添加倍速设置项
      DYYYSettingDescriptor *speedSettingsItem = [[DYYYSettingDescriptor.class alloc] init];
      speedSettingsItem.identifier = @"DYYYSpeedSettings";
      speedSettingsItem.title = @"快捷倍速数值设置";
      speedSettingsItem.subTitle = @"需同时命中包含设置默认倍速和设置长按倍速的数值，否则默认恢复成0.75,1.0,1.25,1.5,2.0,2.5,3.0";
      speedSettingsItem.type = 0;
      speedSettingsItem.svgIconImageName = @"ic_speed_outlined_20";
      speedSettingsItem.cellType = 20;
      speedSettingsItem.colorStyle = 0;
      speedSettingsItem.isEnable = YES;

      // 获取已保存的倍速数值设置
      NSString *savedSpeedSettings = DYYYCurrentSpeedSettingsDisplayString();
      speedSettingsItem.detail = [NSString stringWithFormat:@"%@", savedSpeedSettings];
      speedSettingsItem.cellTappedBlock = ^{
        [DYYYSettingsHelper showTextInputAlert:@"设置快捷倍速数值"
                                   defaultText:speedSettingsItem.detail
                                   placeholder:@"使用半角逗号(,)分隔倍速值"
                                     onConfirm:^(NSString *text) {
                                       // 保存用户输入的倍速值
                                       NSString *trimmedText = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                                       [DYYYSettingsHelper setUserDefaults:trimmedText forKey:@"DYYYSpeedSettings"];
                                       speedSettingsItem.detail = DYYYCurrentSpeedSettingsDisplayString();
                                       [speedSettingsItem refreshCell];
                                       [FloatingSpeedButton reloadConfiguration];
                                     }
                                      onCancel:nil];
      };

      // 添加自动恢复倍速设置项
      DYYYSettingDescriptor *autoRestoreSpeedItem = [[DYYYSettingDescriptor.class alloc] init];
      autoRestoreSpeedItem.identifier = @"DYYYAutoRestoreSpeed";
      autoRestoreSpeedItem.title = @"自动恢复默认倍速";
      autoRestoreSpeedItem.detail = @"";
      autoRestoreSpeedItem.type = 1000;
      autoRestoreSpeedItem.svgIconImageName = @"ic_switch_outlined";
      autoRestoreSpeedItem.cellType = 6;
      autoRestoreSpeedItem.colorStyle = 0;
      autoRestoreSpeedItem.isEnable = YES;
      autoRestoreSpeedItem.isSwitchOn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYAutoRestoreSpeed"];
      autoRestoreSpeedItem.switchChangedBlock = ^{
        BOOL newValue = !autoRestoreSpeedItem.isSwitchOn;
        autoRestoreSpeedItem.isSwitchOn = newValue;
        [DYYYSettingsHelper setUserDefaults:@(newValue) forKey:@"DYYYAutoRestoreSpeed"];
      };
      [speedButtonItems addObject:autoRestoreSpeedItem];

      DYYYSettingDescriptor *showXItem = [[DYYYSettingDescriptor.class alloc] init];
      showXItem.identifier = @"DYYYSpeedButtonShowX";
      showXItem.title = @"倍速按钮显示后缀";
      showXItem.detail = @"";
      showXItem.type = 1000;
      showXItem.svgIconImageName = @"ic_pensketch_outlined_20";
      showXItem.cellType = 6;
      showXItem.colorStyle = 0;
      showXItem.isEnable = YES;
      showXItem.isSwitchOn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYSpeedButtonShowX"];
      showXItem.switchChangedBlock = ^{
        BOOL newValue = !showXItem.isSwitchOn;
        showXItem.isSwitchOn = newValue;
        [DYYYSettingsHelper setUserDefaults:@(newValue) forKey:@"DYYYSpeedButtonShowX"];
        [FloatingSpeedButton reloadConfiguration];
      };
      [speedButtonItems addObject:showXItem];
      // 添加按钮大小配置项
      DYYYSettingDescriptor *buttonSizeItem = [[DYYYSettingDescriptor.class alloc] init];
      buttonSizeItem.identifier = @"DYYYSpeedButtonSize";
      buttonSizeItem.title = @"快捷倍速按钮大小";
      // 获取当前的按钮大小，如果没有设置则默认为32
      CGFloat currentButtonSize = [[NSUserDefaults standardUserDefaults] floatForKey:@"DYYYSpeedButtonSize"] ?: 32;
      buttonSizeItem.detail = [NSString stringWithFormat:@"%.0f", currentButtonSize];
      buttonSizeItem.type = 0;
      buttonSizeItem.svgIconImageName = @"ic_zoomin_outlined_20";
      buttonSizeItem.cellType = 26;
      buttonSizeItem.colorStyle = 0;
      buttonSizeItem.isEnable = YES;
      buttonSizeItem.cellTappedBlock = ^{
        NSString *currentValue = buttonSizeItem.detail ?: @"32";
        [DYYYSettingsHelper showTextInputAlert:@"设置按钮大小"
                                   defaultText:currentValue
                                   placeholder:@"请输入20-60之间的数值"
                                     onConfirm:^(NSString *text) {
                                       NSInteger size = [text integerValue];
                                       if (size >= 20 && size <= 60) {
                                           [[NSUserDefaults standardUserDefaults] setFloat:size forKey:@"DYYYSpeedButtonSize"];
                                           buttonSizeItem.detail = [NSString stringWithFormat:@"%.0f", (CGFloat)size];
                                           [buttonSizeItem refreshCell];
                                           [FloatingSpeedButton reloadConfiguration];
                                       } else {
                                           [DYYYUtils showToast:@"请输入20-60之间的有效数值"];
                                       }
                                     }
                                      onCancel:nil];
      };

      [speedButtonItems addObject:buttonSizeItem];

      [speedButtonItems addObject:speedSettingsItem];

      NSMutableArray<DYYYSettingDescriptor *> *speedDependentItems = [NSMutableArray array];
      for (DYYYSettingDescriptor *item in speedButtonItems) {
          if (item != enableSpeedButton) {
              [speedDependentItems addObject:item];
          }
      }
      void (^refreshSpeedDependentItems)(void) = ^{
        for (DYYYSettingDescriptor *item in speedDependentItems) {
            [DYYYSettingsHelper applyDependencyRulesForItem:item];
            [item refreshCell];
        }
      };

      refreshSpeedDependentItems();

      void (^originalSpeedSwitchChangedBlock)(void) = enableSpeedButton.switchChangedBlock;
      enableSpeedButton.switchChangedBlock = ^{
        if (originalSpeedSwitchChangedBlock) {
            originalSpeedSwitchChangedBlock();
        }
        speedSettingsItem.detail = DYYYCurrentSpeedSettingsDisplayString();
        [speedSettingsItem refreshCell];
        [FloatingSpeedButton reloadConfiguration];
        refreshSpeedDependentItems();
      };

      // 一键清屏section
      NSMutableArray<DYYYSettingDescriptor *> *clearButtonItems = [NSMutableArray array];

      // 清屏按钮
      DYYYSettingDescriptor *enableClearButton = [DYYYSettingsHelper
          createSettingItem:@{@"identifier" : @"DYYYEnableFloatClearButton", @"title" : @"一键清屏按钮", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"}];
      [clearButtonItems addObject:enableClearButton];

      // 添加清屏按钮大小配置项
      DYYYSettingDescriptor *clearButtonSizeItem = [[DYYYSettingDescriptor.class alloc] init];
      clearButtonSizeItem.identifier = @"DYYYEnableFloatClearButtonSize";
      clearButtonSizeItem.title = @"清屏按钮大小";
      // 获取当前的按钮大小，如果没有设置则默认为40
      CGFloat currentClearButtonSize = [[NSUserDefaults standardUserDefaults] floatForKey:@"DYYYEnableFloatClearButtonSize"] ?: 40;
      clearButtonSizeItem.detail = [NSString stringWithFormat:@"%.0f", currentClearButtonSize];
      clearButtonSizeItem.type = 0;
      clearButtonSizeItem.svgIconImageName = @"ic_zoomin_outlined_20";
      clearButtonSizeItem.cellType = 26;
      clearButtonSizeItem.colorStyle = 0;
      clearButtonSizeItem.isEnable = YES;
      clearButtonSizeItem.cellTappedBlock = ^{
        NSString *currentValue = clearButtonSizeItem.detail ?: @"40";
        [DYYYSettingsHelper showTextInputAlert:@"设置清屏按钮大小"
                                   defaultText:currentValue
                                   placeholder:@"请输入20-60之间的数值"
                                     onConfirm:^(NSString *text) {
                                       NSInteger size = [text integerValue];
                                       // 确保输入值在有效范围内
                                       if (size >= 20 && size <= 60) {
                                           [[NSUserDefaults standardUserDefaults] setFloat:size forKey:@"DYYYEnableFloatClearButtonSize"];
                                           clearButtonSizeItem.detail = [NSString stringWithFormat:@"%.0f", (CGFloat)size];
                                           [clearButtonSizeItem refreshCell];
                                           reloadClearButtonConfiguration();
                                       } else {
                                           [DYYYUtils showToast:@"请输入20-60之间的有效数值"];
                                       }
                                     }
                                      onCancel:nil];
      };
      [clearButtonItems addObject:clearButtonSizeItem];

      // 添加清屏按钮自定义图标选项
      DYYYSettingDescriptor *clearButtonIcon = [DYYYSettingsHelper createIconCustomizationItemWithIdentifier:@"DYYYClearButtonIcon"
                                                                                                       title:@"清屏按钮图标"
                                                                                                     svgIcon:@"ic_roaming_outlined"
                                                                                                    saveFile:@"qingping.gif"];

      [clearButtonItems addObject:clearButtonIcon];
      // 清屏隐藏弹幕
      DYYYSettingDescriptor *hideDanmakuButton =
          [DYYYSettingsHelper createSettingItem:@{@"identifier" : @"DYYYHideDanmaku", @"title" : @"清屏隐藏弹幕", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"}];
      [clearButtonItems addObject:hideDanmakuButton];

      DYYYSettingDescriptor *enableqingButton = [DYYYSettingsHelper createSettingItem:@{
          @"identifier" : @"DYYYRemoveTimeProgress",
          @"title" : @"清屏移除进度",
          @"subTitle" : @"清屏状态下完全移除时间进度条",
          @"detail" : @"",
          @"cellType" : @37,
          @"imageName" : @"ic_eyeslash_outlined_16"
      }];
      [clearButtonItems addObject:enableqingButton];
      // 清屏隐藏时间进度
      DYYYSettingDescriptor *enableqingButton1 = [DYYYSettingsHelper createSettingItem:@{
          @"identifier" : @"DYYYHideTimeProgress",
          @"title" : @"清屏隐藏进度",
          @"subTitle" : @"原始位置可拖动时间进度条",
          @"detail" : @"",
          @"cellType" : @37,
          @"imageName" : @"ic_eyeslash_outlined_16"
      }];
      [clearButtonItems addObject:enableqingButton1];
      DYYYSettingDescriptor *hideSliderButton = [DYYYSettingsHelper createSettingItem:@{
          @"identifier" : @"DYYYHideSlider",
          @"title" : @"清屏隐藏滑条",
          @"subTitle" : @"清屏状态下隐藏多图片下方的滑条",
          @"detail" : @"",
          @"cellType" : @37,
          @"imageName" : @"ic_eyeslash_outlined_16"
      }];
      [clearButtonItems addObject:hideSliderButton];
      DYYYSettingDescriptor *hideChapterButton = [DYYYSettingsHelper createSettingItem:@{
          @"identifier" : @"DYYYHideChapter",
          @"title" : @"清屏隐藏章节",
          @"subTitle" : @"清屏状态下隐藏部分视频出现的章节进度显示",
          @"detail" : @"",
          @"cellType" : @37,
          @"imageName" : @"ic_eyeslash_outlined_16"
      }];
      [clearButtonItems addObject:hideChapterButton];
      DYYYSettingDescriptor *hideTabButton =
          [DYYYSettingsHelper createSettingItem:@{@"identifier" : @"DYYYHideTabBar", @"title" : @"清屏隐藏底栏", @"detail" : @"", @"cellType" : @6, @"imageName" : @"ic_eyeslash_outlined_16"}];
      [clearButtonItems addObject:hideTabButton];
      DYYYSettingDescriptor *hideSpeedButton = [DYYYSettingsHelper createSettingItem:@{
          @"identifier" : @"DYYYHideSpeed",
          @"title" : @"清屏隐藏倍速按钮",
          @"subTitle" : @"清屏状态下隐藏DYYY的倍速按钮",
          @"detail" : @"",
          @"cellType" : @37,
          @"imageName" : @"ic_eyeslash_outlined_16"
      }];
      [clearButtonItems addObject:hideSpeedButton];
      // 清屏后隐藏清屏按钮自身（仍可点击恢复）
      DYYYSettingDescriptor *hideClearButtonOnTap = [DYYYSettingsHelper createSettingItem:@{
          @"identifier" : @"DYYYHideClearButtonOnTap",
          @"title" : @"清屏隐藏清屏按钮",
          @"subTitle" : @"清屏后隐藏清屏按钮自身，原位置仍可点击恢复",
          @"detail" : @"",
          @"cellType" : @37,
          @"imageName" : @"ic_eyeslash_outlined_16"
      }];
      [clearButtonItems addObject:hideClearButtonOnTap];
      DYYYSettingDescriptor *hidePauseVideoIcon = [DYYYSettingsHelper createSettingItem:@{
          @"identifier" : @"DYYYHidePauseVideoIcon",
          @"title" : @"清屏隐藏暂停图标",
          @"subTitle" : @"清屏状态下隐藏视频中央的播放/暂停图标",
          @"detail" : @"",
          @"cellType" : @37,
          @"imageName" : @"ic_eyeslash_outlined_16"
      }];
      [clearButtonItems addObject:hidePauseVideoIcon];
      DYYYSettingDescriptor *hideStatusBarOnClear = [DYYYSettingsHelper createSettingItem:@{
          @"identifier" : @"DYYYHideStatusBarOnClear",
          @"title" : @"清屏隐藏状态栏",
          @"subTitle" : @"清屏状态下隐藏系统顶部状态栏",
          @"detail" : @"",
          @"cellType" : @37,
          @"imageName" : @"ic_eyeslash_outlined_16"
      }];
      [clearButtonItems addObject:hideStatusBarOnClear];
      NSMutableArray<DYYYSettingDescriptor *> *clearDependentItems = [NSMutableArray array];
      for (DYYYSettingDescriptor *item in clearButtonItems) {
          if (item != enableClearButton) {
              [clearDependentItems addObject:item];
          }
      }
      void (^refreshClearDependentItems)(void) = ^{
        for (DYYYSettingDescriptor *item in clearDependentItems) {
            [DYYYSettingsHelper applyDependencyRulesForItem:item];
            [item refreshCell];
        }
      };

      refreshClearDependentItems();

      for (DYYYSettingDescriptor *item in clearButtonItems) {
          void (^originalClearSwitchChangedBlock)(void) = item.switchChangedBlock;
          if (!originalClearSwitchChangedBlock) {
              continue;
          }
          item.switchChangedBlock = ^{
            originalClearSwitchChangedBlock();
            reloadClearButtonConfiguration();
            if (item == enableClearButton) {
                refreshClearDependentItems();
            }
          };
      }

      // 创建并组织所有section
      NSMutableArray *sections = [NSMutableArray array];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"快捷倍速" items:speedButtonItems]];
      [sections addObject:[DYYYSettingsHelper createSectionWithTitle:@"一键清屏" items:clearButtonItems]];

      [DYYYSettingsRegistry registerSections:sections category:@"悬浮按钮"];
      if ([DYYYSettingsRegistry isBuilding]) {
          return;
      }

      // 创建并推入二级设置页面
      DYYYSettingViewController *subVC = [DYYYSettingsHelper createSubSettingsViewController:@"悬浮按钮" sections:sections];
      [[DYYYSettingsCoordinator navigationController] pushViewController:(UIViewController *)subVC animated:YES];
    };
    [mainItems addObject:floatButtonSettingItem];

    // 创建备份设置分类
    DYYYSettingsSection *backupSection = [[DYYYSettingsSection.class alloc] init];
    backupSection.sectionHeaderTitle = @"备份";
    backupSection.sectionHeaderHeight = 40;
    backupSection.type = 0;
    NSMutableArray<DYYYSettingDescriptor *> *backupItems = [NSMutableArray array];

    DYYYSettingDescriptor *backupItem = [[DYYYSettingDescriptor.class alloc] init];
    backupItem.identifier = @"DYYYBackupSettings";
    backupItem.title = @"备份设置";
    backupItem.detail = @"";
    backupItem.type = 0;
    backupItem.svgIconImageName = @"ic_memorycard_outlined_20";
    backupItem.cellType = 26;
    backupItem.colorStyle = 0;
    backupItem.isEnable = YES;
    backupItem.cellTappedBlock = ^{
      [DYYYSettingsHelper exportSettingsBackup];
    };
    [backupItems addObject:backupItem];

    // 添加恢复设置
    DYYYSettingDescriptor *restoreItem = [[DYYYSettingDescriptor.class alloc] init];
    restoreItem.identifier = @"DYYYRestoreSettings";
    restoreItem.title = @"恢复设置";
    restoreItem.detail = @"";
    restoreItem.type = 0;
    restoreItem.svgIconImageName = @"ic_phonearrowup_outlined_20";
    restoreItem.cellType = 26;
    restoreItem.colorStyle = 0;
    restoreItem.isEnable = YES;
    restoreItem.cellTappedBlock = ^{
      [DYYYSettingsHelper importSettingsBackup];
    };
    [backupItems addObject:restoreItem];
    backupSection.itemArray = backupItems;

    // 创建清理section
    DYYYSettingsSection *cleanupSection = [[DYYYSettingsSection.class alloc] init];
    cleanupSection.sectionHeaderTitle = @"清理";
    cleanupSection.sectionHeaderHeight = 40;
    cleanupSection.type = 0;
    NSMutableArray<DYYYSettingDescriptor *> *cleanupItems = [NSMutableArray array];
    DYYYSettingDescriptor *cleanSettingsItem = [[DYYYSettingDescriptor.class alloc] init];
    cleanSettingsItem.identifier = @"DYYYCleanSettings";
    cleanSettingsItem.title = @"清除设置";
    cleanSettingsItem.detail = @"";
    cleanSettingsItem.type = 0;
    cleanSettingsItem.svgIconImageName = @"ic_trash_outlined_20";
    cleanSettingsItem.cellType = 26;
    cleanSettingsItem.colorStyle = 0;
    cleanSettingsItem.isEnable = YES;
    cleanSettingsItem.cellTappedBlock = ^{
      [DYYYBottomAlertView showAlertWithTitle:@"清除设置"
          message:@"请选择要清除的设置类型"
          avatarURL:nil
          cancelButtonText:@"清除抖音设置"
          confirmButtonText:@"清除插件设置"
          cancelAction:^{
            // 清除抖音设置的确认对话框
            [DYYYBottomAlertView showAlertWithTitle:@"清除抖音设置"
                                            message:@"确定要清除抖音所有设置吗？\n这将无法恢复，应用会自动退出！"
                                          avatarURL:nil
                                   cancelButtonText:@"取消"
                                  confirmButtonText:@"确定"
                                       cancelAction:nil
                                        closeAction:nil
                                      confirmAction:^{
                                        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
                                        if (paths.count > 0) {
                                            NSString *preferencesPath = [paths.firstObject stringByAppendingPathComponent:@"Preferences"];
                                            NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
                                            NSString *plistPath = [preferencesPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", bundleIdentifier]];

                                            NSError *error = nil;
                                            [[NSFileManager defaultManager] removeItemAtPath:plistPath error:&error];

                                            if (!error) {
                                                [DYYYUtils showToast:@"抖音设置已清除，应用即将退出"];

                                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                                  exit(0);
                                                });
                                            } else {
                                                [DYYYUtils showToast:[NSString stringWithFormat:@"清除失败: %@", error.localizedDescription]];
                                            }
                                        }
                                      }];
          }
          closeAction:^{
          }
          confirmAction:^{
            // 清除插件设置的确认对话框
            [DYYYBottomAlertView showAlertWithTitle:@"清除插件设置"
                                            message:@"确定要清除所有插件设置吗？\n这将无法恢复！"
                                          avatarURL:nil
                                   cancelButtonText:@"取消"
                                  confirmButtonText:@"确定"
                                       cancelAction:nil
                                        closeAction:nil
                                      confirmAction:^{
                                        // 获取所有以DYYY开头的NSUserDefaults键值并清除
                                        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                                        NSDictionary *allDefaults = [defaults dictionaryRepresentation];

                                        for (NSString *key in allDefaults.allKeys) {
                                            if ([key hasPrefix:@"DYYY"]) {
                                                [defaults removeObjectForKey:key];
                                            }
                                        }
                                        [DYYYUtils showToast:@"插件设置已清除，请重启应用"];
                                      }];
          }];
    };
    [cleanupItems addObject:cleanSettingsItem];

    NSArray<NSString *> *customDirs = @[ @"Application Support/gurd_cache", @"Caches", @"BDByteCast", @"kitelog" ];
    NSMutableSet<NSString *> *uniquePaths = [NSMutableSet set];
    [uniquePaths addObject:NSTemporaryDirectory()];
    [uniquePaths addObject:NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject];
    NSString *libraryDir = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    for (NSString *sub in customDirs) {
        NSString *fullPath = [libraryDir stringByAppendingPathComponent:sub];
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
            [uniquePaths addObject:fullPath];
        }
    }
    NSArray<NSString *> *allPaths = [uniquePaths allObjects];

    DYYYSettingDescriptor *cleanCacheItem = [[DYYYSettingDescriptor.class alloc] init];
    __weak DYYYSettingDescriptor *weakCleanCacheItem = cleanCacheItem;
    cleanCacheItem.identifier = @"DYYYCleanCache";
    cleanCacheItem.title = @"清理缓存";
    cleanCacheItem.type = 0;
    cleanCacheItem.svgIconImageName = @"ic_broom_outlined";
    cleanCacheItem.cellType = 26;
    cleanCacheItem.colorStyle = 0;
    cleanCacheItem.isEnable = NO;
    cleanCacheItem.detail = @"计算中...";
    __block unsigned long long initialSize = 0;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      for (NSString *basePath in allPaths) {
          initialSize += [DYYYUtils directorySizeAtPath:basePath];
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        __strong DYYYSettingDescriptor *strongCleanCacheItem = weakCleanCacheItem;
        if (strongCleanCacheItem) {
            strongCleanCacheItem.detail = [DYYYUtils formattedSize:initialSize];
            strongCleanCacheItem.isEnable = YES;
            [strongCleanCacheItem refreshCell];
        }
      });
    });
    cleanCacheItem.cellTappedBlock = ^{
      __strong DYYYSettingDescriptor *strongCleanCacheItem = weakCleanCacheItem;
      if (!strongCleanCacheItem || !strongCleanCacheItem.isEnable) {
          return;
      }
      // Disable the button to prevent multiple triggers
      strongCleanCacheItem.isEnable = NO;
      strongCleanCacheItem.detail = @"清理中...";
      [strongCleanCacheItem refreshCell];

      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        unsigned long long beforeSize = 0;
        for (NSString *basePath in allPaths) beforeSize += [DYYYUtils directorySizeAtPath:basePath];
        for (NSString *basePath in allPaths) {
            [DYYYUtils removeAllContentsAtPath:basePath];
        }

        // 修复搜索界面的猜你想搜和猜你想看
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *activeMetadataFilePath = [libraryDir stringByAppendingPathComponent:@"Application Support/gurd_cache/.active_metadata"];
        if ([fileManager fileExistsAtPath:activeMetadataFilePath]) {
            [fileManager removeItemAtPath:activeMetadataFilePath error:nil];
        }

        unsigned long long afterSize = 0;
        for (NSString *basePath in allPaths) {
            afterSize += [DYYYUtils directorySizeAtPath:basePath];
        }

        unsigned long long clearedSize = (beforeSize > afterSize) ? (beforeSize - afterSize) : 0;

        dispatch_async(dispatch_get_main_queue(), ^{
          NSString *result = !beforeSize   ? @"缓存已为空"
                             : clearedSize ? [NSString stringWithFormat:@"已清理 %@，剩余 %@", [DYYYUtils formattedSize:clearedSize], [DYYYUtils formattedSize:afterSize]]
                                           : @"未清除缓存，文件可能正在使用或无法写入";
          [DYYYUtils showToast:result];

          strongCleanCacheItem.detail = [DYYYUtils formattedSize:afterSize];
          // Re-enable the button after cleaning is done
          strongCleanCacheItem.isEnable = YES;
          [strongCleanCacheItem refreshCell];
        });
      });
    };
    [cleanupItems addObject:cleanCacheItem];

    cleanupSection.itemArray = cleanupItems;

    // 创建关于分类
    DYYYSettingsSection *aboutSection = [[DYYYSettingsSection.class alloc] init];
    aboutSection.sectionHeaderTitle = @"关于";
    aboutSection.sectionHeaderHeight = 40;
    aboutSection.type = 0;
    NSMutableArray<DYYYSettingDescriptor *> *aboutItems = [NSMutableArray array];

    // 添加关于
    DYYYSettingDescriptor *aboutItem = [[DYYYSettingDescriptor.class alloc] init];
    aboutItem.identifier = @"DYYYAbout";
    aboutItem.title = @"关于插件";
    aboutItem.detail = DYYY_VERSION;
    aboutItem.type = 0;
    aboutItem.iconImageName = @"awe-settings-icon-about";
    aboutItem.cellType = 26;
    aboutItem.colorStyle = 0;
    aboutItem.isEnable = YES;
    aboutItem.cellTappedBlock = ^{
      [DYYYSettingsHelper showAboutDialog:@"关于DYYY"
                                  message:@"版本: " DYYY_VERSION @"\n\n"
                                          @"感谢使用DYYY\n\n"
                                          @"感谢huami开源\n\n"
                                          @"@维他入我心 基于DYYY二次开发\n\n"
                                          @"感谢huami group中群友的支持赞助\n\n"
                                          @"Telegram @huamidev\n\n"
                                          @"Telegram @vita_app\n\n"
                                          @"开源地址 huami1314/DYYY\n\n"
                                          @"仓库地址 Wtrwx/DYYY\n\n"
                                onConfirm:nil];
    };
    [aboutItems addObject:aboutItem];

    DYYYSettingDescriptor *licenseItem = [[DYYYSettingDescriptor.class alloc] init];
    licenseItem.identifier = @"DYYYLicense";
    licenseItem.title = @"开源协议";
    licenseItem.detail = @"MIT License";
    licenseItem.type = 0;
    licenseItem.iconImageName = @"awe-settings-icon-opensource-notice";
    licenseItem.cellType = 26;
    licenseItem.colorStyle = 0;
    licenseItem.isEnable = YES;
    licenseItem.cellTappedBlock = ^{
      [DYYYSettingsHelper showAboutDialog:@"MIT License"
                                  message:@"Copyright (c) 2024 huami.\n\n"
                                          @"Permission is hereby granted, free of charge, to any person obtaining a copy "
                                          @"of this software and associated documentation files (the \"Software\"), to deal "
                                          @"in the Software without restriction, including without limitation the rights "
                                          @"to use, copy, modify, merge, publish, distribute, sublicense, and/or sell "
                                          @"copies of the Software, and to permit persons to whom the Software is "
                                          @"furnished to do so, subject to the following conditions:\n\n"
                                          @"The above copyright notice and this permission notice shall be included in all "
                                          @"copies or substantial portions of the Software.\n\n"
                                          @"THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR "
                                          @"IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, "
                                          @"FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE "
                                          @"AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER "
                                          @"LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, "
                                          @"OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE "
                                          @"SOFTWARE."
                                onConfirm:nil];
    };
    [aboutItems addObject:licenseItem];
    mainSection.itemArray = mainItems;
    aboutSection.itemArray = aboutItems;

    for (DYYYSettingDescriptor *category in mainItems) {
        category.cellTappedBlock();
    }
    [DYYYSettingsRegistry registerSections:@[ backupSection, cleanupSection, aboutSection ] category:@"工具"];
    DYYYSettingDescriptor *doubleTap = [self itemForIdentifier:@"DYYYDoubleTapMenuSettings"];
    if (doubleTap.cellTappedBlock)
        doubleTap.cellTappedBlock();
    for (DYYYSettingsSection *section in self.mutableSections) {
        if ([section.sectionHeaderTitle isEqual:@"设置双击菜单项目"])
            doubleTap.children = @[ section ];
    }
}
@end
