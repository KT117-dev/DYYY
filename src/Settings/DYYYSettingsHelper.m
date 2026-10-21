#import "DYYYSettingsHelper.h"
#import <UIKit/UIKit.h>
#import <math.h>
#import <objc/runtime.h>
#import "DYYYFloatClearButton.h"
#import "DYYYFloatSpeedButton.h"
#import "DYYYSettingViewController.h"
#import "DYYYSettingsCoordinator.h"
#import "DYYYSettingsRegistry.h"
#import "DYYYUtils.h"

#import "DYYYAboutDialogView.h"
#import "DYYYBottomAlertView.h"
#import "DYYYCustomInputView.h"
#import "DYYYIconOptionsDialogView.h"

@implementation DYYYSettingsHelper

#pragma mark - 原生备份与恢复
+ (NSArray<NSString *> *)backupIconNames {
    return @[ @"like_before.png", @"like_after.png", @"comment.png", @"unfavorite.png", @"favorite.png", @"share.png", @"tab_plus.png", @"qingping.gif" ];
}
+ (NSDictionary *)validatedBackup:(id)decoded {
    if (![decoded isKindOfClass:NSDictionary.class] || ![NSPropertyListSerialization propertyList:decoded isValidForFormat:NSPropertyListBinaryFormat_v1_0])
        return nil;
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    NSMutableDictionary *icons = [NSMutableDictionary dictionary];
    for (id key in decoded) {
        if (![key isKindOfClass:NSString.class] || ![key hasPrefix:@"DYYY"])
            return nil;
        if ([key isEqual:@"DYYYIconsBase64"]) {
            id images = decoded[key];
            if (![images isKindOfClass:NSDictionary.class])
                return nil;
            for (id name in images) {
                id encoded = images[name];
                NSData *data = [encoded isKindOfClass:NSString.class] ? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
                if (![self.backupIconNames containsObject:name] || !data.length)
                    return nil;
                icons[name] = data;
            }
        } else if (DYYYGlassBackdropView.defaultSettings[key]) {
            id stored = decoded[key];
            if (![stored isKindOfClass:NSString.class] && ![stored isKindOfClass:NSNumber.class])
                return nil;
            NSScanner *scanner = [NSScanner scannerWithString:[stored description]];
            double value;
            if (![scanner scanDouble:&value] || !scanner.isAtEnd || !isfinite(value) || value < 0 || value > 1)
                return nil;
            values[key] = [NSString stringWithFormat:@"%.2f", value];
        } else
            values[key] = decoded[key];
    }
    return @{@"values" : values, @"icons" : icons};
}
+ (UIAlertController *)showProgress:(NSString *)title progress:(NSProgress *)progress {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:@"正在处理，请稍候…" preferredStyle:UIAlertControllerStyleAlert];
    alert.view.tintColor = UIColor.labelColor;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *action) {
                                              [progress cancel];
                                            }]];
    [DYYYSettingsCoordinator.presenter presentViewController:alert animated:YES completion:nil];
    return alert;
}
+ (void)exportSettingsBackup {
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
    UIAlertController *busy = [self showProgress:@"准备备份" progress:progress];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSMutableDictionary *settings = [NSMutableDictionary dictionary];
      NSDictionary *defaults = NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
      for (NSString *key in defaults)
          if ([key hasPrefix:@"DYYY"])
              settings[key] = defaults[key];
      NSString *folder = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"DYYY"];
      NSMutableDictionary *icons = [NSMutableDictionary dictionary];
      for (NSString *name in self.backupIconNames) {
          if (progress.cancelled)
              break;
          NSData *data = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:name]];
          if (data)
              icons[name] = [data base64EncodedStringWithOptions:0];
      }
      if (icons.count)
          settings[@"DYYYIconsBase64"] = icons;
      NSError *error;
      NSData *json = [NSJSONSerialization dataWithJSONObject:DYYYJSONSafeObject(settings) options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
      NSDateFormatter *formatter = [NSDateFormatter new];
      formatter.dateFormat = @"yyyyMMdd_HHmmss";
      NSString *filename = [NSString stringWithFormat:@"DYYY_Backup_%@.json", [formatter stringFromDate:NSDate.date]];
      NSString *path = [DYYYUtils cachePathForFilename:filename];
      BOOL saved = !progress.cancelled && json && [json writeToFile:path options:NSDataWritingAtomic error:&error];
      dispatch_async(dispatch_get_main_queue(), ^{
        [busy dismissViewControllerAnimated:YES
                                 completion:^{
                                   if (!saved || progress.cancelled) {
                                       if (saved)
                                           [NSFileManager.defaultManager removeItemAtPath:path error:nil];
                                       if (!progress.cancelled)
                                           [DYYYUtils showToast:error.localizedDescription ?: @"备份失败"];
                                       return;
                                   }
                                   UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithURLs:@[ [NSURL fileURLWithPath:path] ]
                                                                                                                          inMode:UIDocumentPickerModeExportToService];
                                   DYYYBackupPickerDelegate *delegate = [DYYYBackupPickerDelegate new];
                                   delegate.tempFilePath = path;
                                   delegate.completionBlock = ^(__unused NSURL *url) {
                                     [DYYYUtils showToast:@"备份已导出"];
                                   };
                                   picker.delegate = delegate;
                                   objc_setAssociatedObject(picker, @selector(exportSettingsBackup), delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                                   [DYYYSettingsCoordinator.presenter presentViewController:picker animated:YES completion:nil];
                                 }];
      });
    });
}
+ (void)importSettingsBackup {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[ @"public.json", @"public.text" ] inMode:UIDocumentPickerModeImport];
    DYYYBackupPickerDelegate *delegate = [DYYYBackupPickerDelegate new];
    delegate.completionBlock = ^(NSURL *url) {
      [self inspectBackupURL:url];
    };
    picker.delegate = delegate;
    objc_setAssociatedObject(picker, @selector(importSettingsBackup), delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [DYYYSettingsCoordinator.presenter presentViewController:picker animated:YES completion:nil];
}
+ (void)inspectBackupURL:(NSURL *)url {
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
    UIAlertController *busy = [self showProgress:@"读取备份" progress:progress];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      BOOL access = [url startAccessingSecurityScopedResource];
      NSError *error;
      NSData *json = [NSData dataWithContentsOfURL:url options:0 error:&error];
      if (access)
          [url stopAccessingSecurityScopedResource];
      id decoded = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:&error] : nil;
      NSDictionary *backup = [self validatedBackup:decoded];
      BOOL valid = backup != nil;
      NSDictionary *values = backup[@"values"], *icons = backup[@"icons"];
      dispatch_async(dispatch_get_main_queue(), ^{
        [busy dismissViewControllerAnimated:YES
                                 completion:^{
                                   if (progress.cancelled)
                                       return;
                                   if (!valid) {
                                       [DYYYUtils showToast:error.localizedDescription ?: @"备份包含无效配置或图标，未恢复"];
                                       return;
                                   }
                                   UIAlertController *confirm =
                                       [UIAlertController alertControllerWithTitle:@"恢复备份"
                                                                           message:[NSString stringWithFormat:@"将覆盖 %lu 项配置和 %lu 个图标。其他配置保留。完成后需重启应用。",
                                                                                                              (unsigned long)values.count, (unsigned long)icons.count]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
                                   confirm.view.tintColor = UIColor.labelColor;
                                   [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                                   [confirm addAction:[UIAlertAction actionWithTitle:@"恢复"
                                                                               style:UIAlertActionStyleDestructive
                                                                             handler:^(__unused UIAlertAction *action) {
                                                                               [self applyBackupValues:values icons:icons];
                                                                             }]];
                                   [DYYYSettingsCoordinator.presenter presentViewController:confirm animated:YES completion:nil];
                                 }];
      });
    });
}
+ (void)applyBackupValues:(NSDictionary *)values icons:(NSDictionary *)icons {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSString *folder = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"DYYY"];
      NSError *error;
      BOOL success = !icons.count || [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error];
      for (NSString *name in icons) {
          if (!success)
              break;
          success = [icons[name] writeToFile:[folder stringByAppendingPathComponent:name] options:NSDataWritingAtomic error:&error];
      }
      if (success)
          for (NSString *key in values) [NSUserDefaults.standardUserDefaults setObject:values[key] forKey:key];
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!success) {
            [DYYYUtils showToast:error.localizedDescription ?: @"图标恢复失败，配置未覆盖；部分图标可能已更新"];
            return;
        }
        [FloatingSpeedButton reloadConfiguration];
        reloadClearButtonConfiguration();
        [NSNotificationCenter.defaultCenter postNotificationName:@"DYYYGlobalTransparencyDidChangeNotification" object:nil];
        [NSNotificationCenter.defaultCenter postNotificationName:DYYYSettingsDidChangeNotification object:nil];
        [DYYYUtils showToast:@"设置与图标已恢复，请重启应用"];
      });
    });
}

// 获取用户默认设置
+ (BOOL)getUserDefaults:(NSString *)key {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

// 设置用户默认设置
+ (void)setUserDefaults:(id)object forKey:(NSString *)key {
    if (!key.length)
        return;
    if ([@[ @"DYYYRemoteConfigURL", @"DYYYInterfaceDownload" ] containsObject:key] && [object isKindOfClass:NSString.class] && [object length]) {
        NSURLComponents *url = [NSURLComponents componentsWithString:object];
        if (![@[ @"http", @"https" ] containsObject:url.scheme.lowercaseString] || !url.host.length) {
            dispatch_async(dispatch_get_main_queue(), ^{
              [DYYYUtils showToast:@"请输入有效的 HTTP 或 HTTPS 地址"];
            });
            return;
        }
    }
    if (object)
        [NSUserDefaults.standardUserDefaults setObject:object forKey:key];
    else
        [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
    dispatch_async(dispatch_get_main_queue(), ^{
      [FloatingSpeedButton reloadConfiguration];
      reloadClearButtonConfiguration();
      if ([key isEqual:@"DYYYGlobalTransparency"])
          [NSNotificationCenter.defaultCenter postNotificationName:@"DYYYGlobalTransparencyDidChangeNotification" object:nil];
      [NSNotificationCenter.defaultCenter postNotificationName:DYYYSettingsDidChangeNotification object:key];
    });
}

// 显示自定义关于弹窗
+ (void)showAboutDialog:(NSString *)title message:(NSString *)message onConfirm:(void (^)(void))onConfirm {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self showAboutDialog:title message:message onConfirm:onConfirm];
        });
        return;
    }
    DYYYAboutDialogView *aboutDialog = [[DYYYAboutDialogView alloc] initWithTitle:title message:message];
    aboutDialog.onConfirm = onConfirm;
    [aboutDialog show];
}

// 显示文本输入弹窗（完整版本）
+ (void)showTextInputAlert:(NSString *)title defaultText:(NSString *)defaultText placeholder:(NSString *)placeholder onConfirm:(void (^)(NSString *text))onConfirm onCancel:(void (^)(void))onCancel {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self showTextInputAlert:title defaultText:defaultText placeholder:placeholder onConfirm:onConfirm onCancel:onCancel];
        });
        return;
    }
    DYYYCustomInputView *inputView = [[DYYYCustomInputView alloc] initWithTitle:title defaultText:defaultText placeholder:placeholder];
    inputView.onConfirm = ^(NSString *text) {
      if (text.length && ([title containsString:@"URL"] || [title containsString:@"地址"] || [title containsString:@"接口"])) {
          NSURLComponents *url = [NSURLComponents componentsWithString:text];
          if (![@[ @"http", @"https" ] containsObject:url.scheme.lowercaseString] || !url.host.length) {
              [DYYYUtils showToast:@"请输入有效的 HTTP 或 HTTPS 地址"];
              return;
          }
      }
      if (onConfirm)
          onConfirm(text);
    };
    inputView.onCancel = onCancel;
    [inputView show];
}

// 显示文本输入弹窗（无placeholder版本）
+ (void)showTextInputAlert:(NSString *)title defaultText:(NSString *)defaultText onConfirm:(void (^)(NSString *text))onConfirm onCancel:(void (^)(void))onCancel {
    [self showTextInputAlert:title defaultText:defaultText placeholder:nil onConfirm:onConfirm onCancel:onCancel];
}

// 显示文本输入弹窗（简化版本）
+ (void)showTextInputAlert:(NSString *)title onConfirm:(void (^)(NSString *text))onConfirm onCancel:(void (^)(void))onCancel {
    [self showTextInputAlert:title defaultText:nil placeholder:nil onConfirm:onConfirm onCancel:onCancel];
}

+ (NSDictionary *)settingsDependencyConfig {
    static NSDictionary *config = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
      config = @{
          // ===== 依赖关系配置 =====
          @"dependencies" : @{
              // 普通依赖：当源设置开启时，目标设置项可用
              @"DYYYEnableDanmuColor" : @[ @"DYYYDanmuColor" ],
              @"DYYYEnableArea" : @[ @"DYYYGeonamesUsername", @"DYYYLabelColor", @"DYYYEnableRandomGradient" ],
              @"DYYYShowScheduleDisplay" : @[ @"DYYYScheduleStyle", @"DYYYProgressLabelColor", @"DYYYTimelineVerticalPosition" ],
              @"DYYYEnableFloatSpeedButton" : @[ @"DYYYAutoRestoreSpeed", @"DYYYSpeedButtonShowX", @"DYYYSpeedButtonSize", @"DYYYSpeedSettings" ],
              @"DYYYEnableFloatClearButton" : @[
                  @"DYYYClearButtonIcon", @"DYYYEnableFloatClearButtonSize", @"DYYYRemoveTimeProgress", @"DYYYHideTimeProgress", @"DYYYHideDanmaku", @"DYYYHideSlider", @"DYYYHideTabBar",
                  @"DYYYHideSpeed", @"DYYYHideClearButtonOnTap", @"DYYYHideChapter", @"DYYYHidePauseVideoIcon", @"DYYYHideStatusBarOnClear"
              ],
              @"DYYYEnableModernPanel" : @[ @"DYYYLongPressPanelBlur", @"DYYYLongPressPanelDark" ],
              @"DYYYEnableDoubleTapMenu" : @[ @"DYYYDoubleTapMenuSettings" ],
              @"DYYYEnableCommentBlur": @[ @"DYYYCommentGlassWhiteOpacity", @"DYYYCommentGlassBlurIntensity" ],
              @"DYYYEnableNotificationTransparency": @[ @"DYYYNotificationGlassWhiteOpacity", @"DYYYNotificationGlassBlurIntensity" ],
              @"DYYYFollowTips": @[ @"DYYYFollowConfirmationWhiteOpacity", @"DYYYFollowConfirmationBlurIntensity" ],
              @"DYYYCollectTips": @[ @"DYYYCollectConfirmationWhiteOpacity", @"DYYYCollectConfirmationBlurIntensity" ],
          },

          // ===== 条件依赖配置 =====
          // 一些设置项依赖于多个其他设置项的复杂条件
          @"conditionalDependencies" : @{},

          // ===== 冲突配置 =====
          // 当源设置项开启时，会自动关闭目标设置项
          @"conflicts" : @{
              @"DYYYEnableDoubleOpenComment" : @[ @"DYYYEnableDoubleTapMenu" ],
              @"DYYYEnableDoubleTapMenu" : @[ @"DYYYEnableDoubleOpenComment" ],
              @"DYYYRemoveTimeProgress" : @[ @"DYYYHideTimeProgress" ],
              @"DYYYHideTimeProgress" : @[ @"DYYYRemoveTimeProgress" ],
              @"DYYYHideLOTAnimationView" : @[ @"DYYYHideFollowPromptView" ],
              @"DYYYHideFollowPromptView" : @[ @"DYYYHideLOTAnimationView" ],
              @"DYYYSkipLive" : @[ @"DYYYSkipAllLive" ],
              @"DYYYSkipAllLive" : @[ @"DYYYSkipLive" ],
              @"DYYYHideEntry" : @[ @"DYYYRemoveEntry" ],
              @"DYYYRemoveEntry" : @[ @"DYYYHideEntry" ],
          },

          // ===== 互斥激活配置 =====
          // 当源设置项关闭时，目标设置项才能激活
          @"mutualExclusions" : @{@"DYYYDanmuRainbowRotating" : @[ @"DYYYDanmuColor" ], @"DYYYEnableRandomGradient" : @[ @"DYYYLabelColor" ], @"DYYYSkipPhoto" : @[ @"DYYYSkipPhotoText" ]},

          // ===== 值依赖配置 =====
          // 基于字符串值的依赖关系
          @"valueDependencies" :
              @{@"DYYYInterfaceDownload" : @{@"valueType" : @"string", @"condition" : @"isNotEmpty", @"dependents" : @[ @"DYYYShowAllVideoQuality", @"DYYYDoubleInterfaceDownload" ]}},

          // ===== 同步配置 =====
          // 当源设置项打开时目标设置项也同步打开，当源设置项关闭时目标设置项也同步关闭
          @"synchronizations" : @{
              @"DYYYLongPressPanelBlur" : @[ @"DYYYLongPressPanelDark" ],
              @"DYYYLongPressPanelDark" : @[ @"DYYYLongPressPanelBlur" ],
          },
      };
    });

    return config;
}

static NSDictionary<NSString *, NSArray<NSString *> *> *DYYYDependencyTargetSourcesLookup(void) {
    static NSDictionary<NSString *, NSArray<NSString *> *> *lookup = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      NSDictionary *dependencies = [DYYYSettingsHelper settingsDependencyConfig][@"dependencies"];
      NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *reverseMap = [NSMutableDictionary dictionary];
      [dependencies enumerateKeysAndObjectsUsingBlock:^(NSString *sourceKey, NSArray *dependentItems, BOOL *stop) {
        if (![dependentItems isKindOfClass:[NSArray class]]) {
            return;
        }
        for (NSString *identifier in dependentItems) {
            if (identifier.length == 0) {
                continue;
            }
            NSMutableArray<NSString *> *sources = reverseMap[identifier];
            if (!sources) {
                sources = [NSMutableArray array];
                reverseMap[identifier] = sources;
            }
            [sources addObject:sourceKey];
        }
      }];
      lookup = [reverseMap copy];
    });
    return lookup;
}

static NSDictionary<NSString *, NSArray<NSString *> *> *DYYYMutualExclusionTargetsLookup(void) {
    static NSDictionary<NSString *, NSArray<NSString *> *> *lookup = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      NSDictionary *mutualExclusions = [DYYYSettingsHelper settingsDependencyConfig][@"mutualExclusions"];
      NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *reverseMap = [NSMutableDictionary dictionary];
      [mutualExclusions enumerateKeysAndObjectsUsingBlock:^(NSString *sourceKey, NSArray *targetIdentifiers, BOOL *stop) {
        if (![targetIdentifiers isKindOfClass:[NSArray class]]) {
            return;
        }
        for (NSString *identifier in targetIdentifiers) {
            if (identifier.length == 0) {
                continue;
            }
            NSMutableArray<NSString *> *sources = reverseMap[identifier];
            if (!sources) {
                sources = [NSMutableArray array];
                reverseMap[identifier] = sources;
            }
            [sources addObject:sourceKey];
        }
      }];
      lookup = [reverseMap copy];
    });
    return lookup;
}

static NSDictionary<NSString *, NSArray<NSDictionary *> *> *DYYYValueDependencyTargetsLookup(void) {
    static NSDictionary<NSString *, NSArray<NSDictionary *> *> *lookup = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      NSDictionary *valueDependencies = [DYYYSettingsHelper settingsDependencyConfig][@"valueDependencies"];
      NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *targetMap = [NSMutableDictionary dictionary];
      [valueDependencies enumerateKeysAndObjectsUsingBlock:^(NSString *sourceKey, NSDictionary *config, BOOL *stop) {
        NSArray *dependents = config[@"dependents"];
        if (dependents.count == 0)
            return;

        for (NSString *identifier in dependents) {
            if (identifier.length == 0) {
                continue;
            }
            NSMutableArray<NSDictionary *> *entries = targetMap[identifier];
            if (!entries) {
                entries = [NSMutableArray array];
                targetMap[identifier] = entries;
            }
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"sourceKey"] = sourceKey;
            if (config[@"valueType"])
                entry[@"valueType"] = config[@"valueType"];
            if (config[@"condition"])
                entry[@"condition"] = config[@"condition"];
            [entries addObject:[entry copy]];
        }
      }];
      lookup = [targetMap copy];
    });
    return lookup;
}

static NSDictionary<NSString *, NSArray<NSString *> *> *DYYYConditionalSourceTargetsLookup(void) {
    static NSDictionary<NSString *, NSArray<NSString *> *> *lookup = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      NSDictionary *conditionalDependencies = [DYYYSettingsHelper settingsDependencyConfig][@"conditionalDependencies"];
      NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *sourceToTargets = [NSMutableDictionary dictionary];
      [conditionalDependencies enumerateKeysAndObjectsUsingBlock:^(NSString *targetIdentifier, NSDictionary *conditionConfig, BOOL *stop) {
        NSArray *settingsList = conditionConfig[@"settings"];
        if (settingsList.count == 0)
            return;
        for (NSString *sourceIdentifier in settingsList) {
            if (sourceIdentifier.length == 0) {
                continue;
            }
            NSMutableArray<NSString *> *targets = sourceToTargets[sourceIdentifier];
            if (!targets) {
                targets = [NSMutableArray array];
                sourceToTargets[sourceIdentifier] = targets;
            }
            [targets addObject:targetIdentifier];
        }
      }];
      lookup = [sourceToTargets copy];
    });
    return lookup;
}

static BOOL settingActive(NSString *identifier) {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:identifier];
    if ([val isKindOfClass:[NSNumber class]]) {
        return [val boolValue];
    } else if ([val isKindOfClass:[NSString class]]) {
        return ((NSString *)val).length > 0;
    }
    return NO;
}

+ (void)applyDependencyRulesForItem:(DYYYSettingDescriptor *)item {
    NSString *itemIdentifier = item.identifier;
    if (itemIdentifier.length == 0) {
        item.isEnable = YES;
        return;
    }
    NSDictionary *conditionalDependencies = [self settingsDependencyConfig][@"conditionalDependencies"];

    BOOL enableState = YES;

    NSArray<NSString *> *directSources = DYYYDependencyTargetSourcesLookup()[itemIdentifier];
    if (directSources.count > 0) {
        NSString *primarySource = directSources.firstObject;
        enableState = settingActive(primarySource);
    }

    NSDictionary *conditionConfig = conditionalDependencies[itemIdentifier];
    if (conditionConfig) {
        NSString *conditionType = conditionConfig[@"condition"];
        NSArray *settingList = conditionConfig[@"settings"];

        if ([conditionType isEqualToString:@"OR"]) {
            BOOL shouldEnable = NO;
            for (NSString *settingKey in settingList) {
                if (settingActive(settingKey)) {
                    shouldEnable = YES;
                    break;
                }
            }
            enableState = shouldEnable;
        } else if ([conditionType isEqualToString:@"AND"]) {
            BOOL shouldEnable = YES;
            for (NSString *settingKey in settingList) {
                if (!settingActive(settingKey)) {
                    shouldEnable = NO;
                    break;
                }
            }
            enableState = shouldEnable;
        }
    }

    NSArray<NSDictionary *> *valueRules = DYYYValueDependencyTargetsLookup()[itemIdentifier];
    NSDictionary *valueRule = valueRules.firstObject;
    if (valueRule) {
        NSString *valueType = valueRule[@"valueType"];
        NSString *condition = valueRule[@"condition"];
        NSString *sourceKey = valueRule[@"sourceKey"];

        if ([valueType isEqualToString:@"string"] && [condition isEqualToString:@"isNotEmpty"]) {
            NSString *sourceValue = [[NSUserDefaults standardUserDefaults] objectForKey:sourceKey];
            enableState = (sourceValue != nil && sourceValue.length > 0);
        }
    }

    NSArray<NSString *> *exclusiveSources = DYYYMutualExclusionTargetsLookup()[itemIdentifier];
    for (NSString *sourceKey in exclusiveSources) {
        if (settingActive(sourceKey)) {
            enableState = NO;
            break;
        }
    }

    item.isEnable = enableState;
}

+ (void)handleConflictsAndDependenciesForSetting:(NSString *)identifier isEnabled:(BOOL)isEnabled {
    NSDictionary *conflicts = [self settingsDependencyConfig][@"conflicts"];
    NSDictionary *synchronizations = [self settingsDependencyConfig][@"synchronizations"];

    if (isEnabled) {
        NSArray *conflictingItems = conflicts[identifier];
        if (conflictingItems) {
            for (NSString *conflictItem in conflictingItems) {
                [self updateConflictingItemUIState:conflictItem withValue:NO];
                [self updateDependentItemsForSetting:conflictItem value:@(NO)];
            }
        }
    }

    // Handle synchronizations rules
    NSArray *synchronizedItems = synchronizations[identifier];
    if (synchronizedItems) {
        for (NSString *syncItem in synchronizedItems) {
            [self updateConflictingItemUIState:syncItem withValue:isEnabled];
            [self updateDependentItemsForSetting:syncItem value:@(isEnabled)];
        }
    }

    [self updateDependentItemsForSetting:identifier value:@(isEnabled)];
}
+ (void)updateConflictingItemUIState:(NSString *)identifier withValue:(BOOL)value {
    [self setUserDefaults:@(value) forKey:identifier];
}
+ (void)updateDependentItemsForSetting:(NSString *)identifier value:(id)value {
    [[DYYYSettingsRegistry current] refreshDependencies];
}

+ (DYYYSettingDescriptor *)createSettingItem:(NSDictionary *)dict {
    return [self createSettingItem:dict cellTapHandlers:nil];
}

+ (DYYYSettingDescriptor *)createSettingItem:(NSDictionary *)dict cellTapHandlers:(NSMutableDictionary *)cellTapHandlers {
    DYYYSettingDescriptor *item = [[DYYYSettingDescriptor.class alloc] init];
    item.identifier = dict[@"identifier"];
    item.title = dict[@"title"];
    item.subTitle = dict[@"subTitle"];

    NSString *savedDetail = [[NSUserDefaults standardUserDefaults] objectForKey:item.identifier];
    NSString *placeholder = dict[@"detail"];
    item.detail = savedDetail ?: @"";

    item.svgIconImageName = dict[@"imageName"];
    item.cellType = [dict[@"cellType"] integerValue];
    item.colorStyle = 0;
    item.isEnable = YES;
    item.isSwitchOn = [self getUserDefaults:item.identifier];

    [self applyDependencyRulesForItem:item];
    if ((item.cellType == 20 || item.cellType == 26) && cellTapHandlers != nil) {
        cellTapHandlers[item.identifier] = ^{
          if (!item.isEnable)
              return;

          [self showTextInputAlert:item.title
                       defaultText:item.detail
                       placeholder:placeholder
                         onConfirm:^(NSString *text) {
                           [self setUserDefaults:text forKey:item.identifier];
                           item.detail = text;

                           if ([item.identifier isEqualToString:@"DYYYInterfaceDownload"]) {
                               [self updateDependentItemsForSetting:@"DYYYInterfaceDownload" value:text];
                           }

                           [self handleConflictsAndDependenciesForSetting:item.identifier isEnabled:(text.length > 0)];

                           [item refreshCell];
                         }
                          onCancel:nil];
        };
        item.cellTappedBlock = cellTapHandlers[item.identifier];
    } else if (item.cellType == 6 || item.cellType == 37) {
        __weak DYYYSettingDescriptor *weakItem = item;
        item.switchChangedBlock = ^{
          __strong DYYYSettingDescriptor *strongItem = weakItem;
          if (strongItem) {
              if (!strongItem.isEnable)
                  return;
              BOOL isSwitchOn = !strongItem.isSwitchOn;
              strongItem.isSwitchOn = isSwitchOn;
              [self setUserDefaults:@(isSwitchOn) forKey:strongItem.identifier];
              [self handleConflictsAndDependenciesForSetting:strongItem.identifier isEnabled:isSwitchOn];
          }
        };
    }

    return item;
}

#pragma mark

static void showIconOptionsDialog(NSString *title, UIImage *previewImage, UIView *sourceView, void (^onClear)(void), void (^onSelect)(void)) {
    DYYYIconOptionsDialogView *optionsDialog = [[DYYYIconOptionsDialogView alloc] initWithTitle:title previewImage:previewImage];
    optionsDialog.onClear = onClear;
    optionsDialog.onSelect = onSelect;
    [optionsDialog showFromView:sourceView];
}

+ (DYYYSettingDescriptor *)createIconCustomizationItemWithIdentifier:(NSString *)identifier title:(NSString *)title svgIcon:(NSString *)svgIconName saveFile:(NSString *)saveFilename {
    DYYYSettingDescriptor *item = [[DYYYSettingDescriptor.class alloc] init];
    item.assetFilename = saveFilename;
    item.identifier = identifier;
    item.title = title;

    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dyyyFolderPath = [documentsPath stringByAppendingPathComponent:@"DYYY"];
    NSString *imagePath = [dyyyFolderPath stringByAppendingPathComponent:saveFilename];

    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:imagePath];
    item.detail = fileExists ? @"已设置" : @"默认";

    item.type = 0;
    item.svgIconImageName = svgIconName;
    item.cellType = 26;
    item.colorStyle = 0;
    item.isEnable = YES;

    __weak DYYYSettingDescriptor *weakItem = item;
    item.cellTappedBlock = ^{
      if (![[NSFileManager defaultManager] fileExistsAtPath:dyyyFolderPath]) {
          [[NSFileManager defaultManager] createDirectoryAtPath:dyyyFolderPath withIntermediateDirectories:YES attributes:nil error:nil];
      }

      UIViewController *topVC = [DYYYSettingsCoordinator presenter];
      UIView *sourceView = nil;
      UIViewController *list = DYYYSettingsCoordinator.navigationController.topViewController;
      if ([list isKindOfClass:DYYYSettingViewController.class]) {
          for (UITableViewCell *cell in ((DYYYSettingViewController *)list).tableView.visibleCells) {
              if ([cell.accessibilityIdentifier isEqual:identifier]) {
                  sourceView = cell;
                  break;
              }
          }
      }

      UIImage *previewImage = nil;
      if ([[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
          previewImage = [UIImage imageWithContentsOfFile:imagePath];
      }

      showIconOptionsDialog(
          title, previewImage, sourceView,
          ^{
            if ([[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
                NSError *error = nil;
                [[NSFileManager defaultManager] removeItemAtPath:imagePath error:&error];
                if (!error) {
                    weakItem.detail = @"默认";
                    [weakItem refreshCell];
                    if ([saveFilename isEqual:@"qingping.gif"])
                        [hideButton loadIcons];
                }
            }
          },
          ^{
            PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
            configuration.filter = PHPickerFilter.imagesFilter;
            configuration.selectionLimit = 1;
            PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];

            DYYYImagePickerDelegate *pickerDelegate = [[DYYYImagePickerDelegate alloc] init];
            pickerDelegate.completionBlock = ^(NSDictionary *info) {
              NSURL *originalImageURL = info[UIImagePickerControllerImageURL];
              if (!originalImageURL) {
                  originalImageURL = info[UIImagePickerControllerReferenceURL];
              }
              if (!originalImageURL) {
                  dispatch_async(dispatch_get_main_queue(), ^{
                    [DYYYUtils showToast:@"无法获取选中的图片"];
                  });
                  return;
              }

              dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
                NSString *dyyyFolderPath = [documentsPath stringByAppendingPathComponent:@"DYYY"];
                NSString *imagePath = [dyyyFolderPath stringByAppendingPathComponent:saveFilename];
                NSData *imageData = [NSData dataWithContentsOfURL:originalImageURL];

                if (!imageData) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                      [DYYYUtils showToast:@"读取图片数据失败"];
                    });
                    return;
                }

                NSFileManager *fileManager = [NSFileManager defaultManager];
                if (![fileManager fileExistsAtPath:dyyyFolderPath]) {
                    [fileManager createDirectoryAtPath:dyyyFolderPath withIntermediateDirectories:YES attributes:nil error:nil];
                }

                const char *bytes = (const char *)imageData.bytes;
                BOOL isGIF = (imageData.length >= 6 && (memcmp(bytes, "GIF87a", 6) == 0 || memcmp(bytes, "GIF89a", 6) == 0));
                if (!isGIF) {
                    UIImage *selectedImage = [UIImage imageWithData:imageData];
                    imageData = UIImagePNGRepresentation(selectedImage);
                }

                BOOL writeSuccess = [imageData writeToFile:imagePath atomically:YES];
                dispatch_async(dispatch_get_main_queue(), ^{
                  if (writeSuccess) {
                      weakItem.detail = @"已设置";
                      [weakItem refreshCell];
                      [FloatingSpeedButton reloadConfiguration];
                      reloadClearButtonConfiguration();
                      if ([saveFilename isEqual:@"qingping.gif"])
                          [hideButton loadIcons];
                  } else {
                      [DYYYUtils showToast:@"保存图标失败"];
                  }
                });
              });
            };

            static char kDYYYPickerDelegateKey;
            picker.delegate = pickerDelegate;
            objc_setAssociatedObject(picker, &kDYYYPickerDelegateKey, pickerDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [topVC presentViewController:picker animated:YES completion:nil];
          });
    };

    return item;
}

+ (DYYYSettingsSection *)createSectionWithTitle:(NSString *)title items:(NSArray *)items {
    return [self createSectionWithTitle:title footerTitle:nil items:items];
}

+ (DYYYSettingsSection *)createSectionWithTitle:(NSString *)title footerTitle:(NSString *)footerTitle items:(NSArray *)items {
    DYYYSettingsSection *section = [[DYYYSettingsSection.class alloc] init];
    section.sectionHeaderTitle = title;
    section.sectionHeaderHeight = 40;
    section.sectionFooterTitle = footerTitle;
    section.useNewFooterLayout = YES;
    section.type = 0;
    section.itemArray = items;
    return section;
}

+ (DYYYSettingViewController *)createSubSettingsViewController:(NSString *)title sections:(NSArray *)sectionsArray {
    if ([DYYYSettingsRegistry isBuilding]) {
        [DYYYSettingsRegistry registerSections:sectionsArray category:title];
        return nil;
    }
    return [[DYYYSettingViewController alloc] initWithSections:sectionsArray title:title];
}

+ (UIViewController *)findViewController:(UIResponder *)responder {
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
        responder = [responder nextResponder];
    }
    return nil;
}

+ (void)openSettingsWithViewController:(UIViewController *)vc { /* 旧入口保留 ABI，不再导航。 */
}
+ (void)openSettingsFromView:(UIView *)view {
}
+ (void)addTapGestureToView:(UIView *)view target:(id)target {
}

+ (void)showUserAgreementAlert {
    [self showTextInputAlert:@"用户协议"
        defaultText:@""
        placeholder:@"我已阅读并同意继续使用"
        onConfirm:^(NSString *text) {
          if ([text isEqualToString:@"我已阅读并同意继续使用"]) {
              [self setUserDefaults:@"YES" forKey:@"DYYYUserAgreementAccepted"];
              [DYYYUtils showToast:@"协议已确认；首次启用后请重启应用以加载全部功能"];
          } else {
              [DYYYUtils showToast:@"请正确输入内容"];
              [self showUserAgreementAlert];
          }
        }
        onCancel:^{
          [DYYYUtils showToast:@"请立即卸载本插件"];
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            exit(0);
          });
        }];
}

@end

#pragma mark - 图片选择代理

@implementation DYYYImagePickerDelegate
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    void (^completion)(NSDictionary *) = self.completionBlock;
    [picker dismissViewControllerAnimated:YES
                               completion:^{
                                 NSItemProvider *provider = results.firstObject.itemProvider;
                                 if (!provider || !completion)
                                     return;
                                 NSString *type = [provider hasItemConformingToTypeIdentifier:@"com.compuserve.gif"] ? @"com.compuserve.gif" : @"public.image";
                                 [provider loadFileRepresentationForTypeIdentifier:type
                                                                 completionHandler:^(NSURL *url, NSError *error) {
                                                                   NSString *filename = [NSUUID.UUID.UUIDString stringByAppendingPathExtension:url.pathExtension.length ? url.pathExtension : @"image"];
                                                                   NSURL *copy = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:filename]];
                                                                   NSError *copyError;
                                                                   if (!url || ![NSFileManager.defaultManager copyItemAtURL:url toURL:copy error:&copyError]) {
                                                                       dispatch_async(dispatch_get_main_queue(), ^{
                                                                         [DYYYUtils showToast:@"无法读取所选图标"];
                                                                       });
                                                                       return;
                                                                   }
                                                                   dispatch_async(dispatch_get_main_queue(), ^{
                                                                     completion(@{UIImagePickerControllerImageURL : copy});
                                                                   });
                                                                 }];
                               }];
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    if (self.completionBlock) {
        self.completionBlock(info);
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}
@end

#pragma mark - 备份文件选择代理

@implementation DYYYBackupPickerDelegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    void (^completion)(NSURL *) = self.completionBlock;
    NSURL *url = urls.firstObject;
    [controller dismissViewControllerAnimated:YES
                                   completion:^{
                                     if (url && completion)
                                         completion(url);
                                     [self cleanupTempFile];
                                   }];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self cleanupTempFile];
}

- (void)cleanupTempFile {
    if (self.tempFilePath && [[NSFileManager defaultManager] fileExistsAtPath:self.tempFilePath]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:self.tempFilePath error:&error];
        if (error) {
            NSLog(@"[DYYY] \u6e05\u7406\u4e34\u65f6\u6587\u4ef6\u5931\u8d25: %@", error.localizedDescription);
        }
    }
}
@end
