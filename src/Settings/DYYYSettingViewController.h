//
//  DYYY
//
//  Copyright (c) 2024 huami. All rights reserved.
//  Channel: @huamidev
//  Created on: 2024/10/04
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class DYYYSettingsSection;
@interface DYYYSettingViewController : UITableViewController
- (instancetype)initWithSections:(NSArray<DYYYSettingsSection *> *)sections title:(NSString *)title;
- (instancetype)initWithTab:(NSString *)tab;

@end

NS_ASSUME_NONNULL_END
