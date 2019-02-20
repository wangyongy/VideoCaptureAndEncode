//
//  CaptureManager.h
//  VideoCaptureAndEncode
//
//  Created by 王勇 on 2018/11/21.
//  Copyright © 2018年 王勇. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN

@interface CaptureManager : NSObject

/**
 初始化

 @param superView 视频呈现视图
 @param captureBlock 视频采集输出回调
 @return 实例
 */
- (instancetype)initWithSuperView:(UIView *)superView captureBlock:(void(^)(CMSampleBufferRef sampleBuffer ,AVMediaType type))captureBlock;

/**  初始化AVCapture会话  */
- (void)initAVCaptureSession;

/**  开启会话  */
- (void)startSession;

/**  停止会话  */
- (void)stopSession;

/**
 *  取得指定位置的摄像头
 *
 *  @param position 摄像头位置
 *
 *  @return 摄像头设备
 */
- (AVCaptureDevice *)getCameraDeviceWithPosition:(AVCaptureDevicePosition )position;

/**  视频输入  */
- (AVCaptureDeviceInput *)videoInput;

/**  预览图层  */
- (AVCaptureVideoPreviewLayer *)captureVideoPreviewLayer;

/**  切换前后摄像头  */
- (void)switchCamera;
@end

NS_ASSUME_NONNULL_END
