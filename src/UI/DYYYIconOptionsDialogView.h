#import <UIKit/UIKit.h>

// 自定义图标选项弹窗
@interface DYYYIconOptionsDialogView : UIView
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIImageView *previewImageView;
@property(nonatomic, copy) void (^onClear)(void);
@property(nonatomic, copy) void (^onSelect)(void);

- (instancetype)initWithTitle:(NSString *)title previewImage:(UIImage *)image;
- (void)showFromView:(UIView *)sourceView;
- (void)dismiss;
@end
