#import <UIKit/UIKit.h>

@class DYYYSettingsSection;

@interface DYYYSettingDescriptor : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *subTitle;
@property(nonatomic, copy) NSString *detail;
@property(nonatomic, copy) NSString *svgIconImageName;
@property(nonatomic, copy) NSString *iconImageName;
@property(nonatomic) NSInteger cellType, type, colorStyle;
@property(nonatomic) BOOL isEnable, isSwitchOn;
@property(nonatomic, copy) void (^cellTappedBlock)(void);
@property(nonatomic, copy) UIMenu *(^menuProvider)(void);
@property(nonatomic, copy) void (^switchChangedBlock)(void);
@property(nonatomic, copy) NSString *category;
@property(nonatomic, copy) NSString *tab;
@property(nonatomic, strong) NSMutableArray<NSString *> *aliases;
@property(nonatomic, copy) NSArray<DYYYSettingsSection *> *children;
@property(nonatomic, copy) NSString *controlType;
@property(nonatomic, copy) NSString *assetFilename;
@property(nonatomic) BOOL requiresRestart;
- (void)refreshCell;
@end

@interface DYYYSettingsSection : NSObject
@property(nonatomic, copy) NSString *sectionHeaderTitle, *sectionFooterTitle;
@property(nonatomic) CGFloat sectionHeaderHeight;
@property(nonatomic) NSInteger type;
@property(nonatomic) BOOL useNewFooterLayout;
@property(nonatomic, copy) NSArray<DYYYSettingDescriptor *> *itemArray;
@end

@interface DYYYSettingsRegistry : NSObject
@property(nonatomic, readonly) NSArray<DYYYSettingDescriptor *> *allItems;
@property(nonatomic, readonly) NSArray<DYYYSettingsSection *> *sections;
+ (instancetype)current;
+ (BOOL)isBuilding;
+ (void)registerSections:(NSArray *)sections category:(NSString *)category;
- (void)build;
- (void)invalidate;
- (void)refreshDependencies;
- (void)setValue:(id)value forItem:(DYYYSettingDescriptor *)item;
- (NSArray<DYYYSettingsSection *> *)sectionsForTab:(NSString *)tab;
- (DYYYSettingDescriptor *)itemForIdentifier:(NSString *)identifier;
@end

FOUNDATION_EXPORT NSNotificationName const DYYYSettingsDidChangeNotification;
