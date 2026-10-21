#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 安装绕登录的 GF/Dtrait 前置链与 TTNetwork 内部 URL 改写。
/// 由主 `%ctor` 调用；设置关闭时 replacement 透传原 IMP。
FOUNDATION_EXPORT void DYYYLoginRepairInstallHooks(void);

NS_ASSUME_NONNULL_END
