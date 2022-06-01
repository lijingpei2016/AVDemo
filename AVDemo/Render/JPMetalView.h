//
//  JPMetalView.h
//  AVDemo
//
//  Created by LJP on 2022/6/1.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 渲染画面填充模式。
typedef NS_ENUM(NSInteger, JPMetalViewContentMode) {
    // 自动填充满，可能会变形。
    JPMetalViewContentModeStretch = 0,
    // 按比例适配，可能会有黑边。
    JPMetalViewContentModeFit = 1,
    // 根据比例裁剪后填充满。
    JPMetalViewContentModeFill = 2
};

@interface JPMetalView : UIView
@property (nonatomic, assign) JPMetalViewContentMode fillMode; // 画面填充模式。
- (void)renderPixelBuffer:(CVPixelBufferRef)pixelBuffer; // 渲染。
@end

NS_ASSUME_NONNULL_END
