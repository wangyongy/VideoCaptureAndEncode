//
//  VideoCaptureAndEncodeViewController.m
//  VideoCaptureAndEncode
//
//  Created by 王勇 on 2018/11/20.
//  Copyright © 2018年 王勇. All rights reserved.
//  使用videoToolBox和AudioToolBox分别录制音视频，并编码(硬编码)成H264和AAC格式，再将H264解码(硬解码)并渲染到屏幕上，同时解码(硬解码)AAC并播放

#import "VideoCaptureEncodeViewController.h"

#import "CaptureManager.h"

#import "H264Player.h"
#import "AACEncoder.h"
#import "AACPlayer.h"
#import "H264Encoder.h"

#import "LYOpenGLView.h"
#import <VideoToolbox/VideoToolbox.h>

#define WS(weakSelf)            __weak __typeof(&*self)weakSelf = self; // 弱引用

#define ST(strongSelf)          __strong __typeof(&*self)strongSelf = weakSelf; //使用这个要先声明weakSelf

@interface VideoCaptureEncodeViewController ()

@property (nonatomic, strong) CaptureManager * captureManager;

@property (nonatomic , strong) LYOpenGLView *openGLView;

@property (nonatomic , strong) AACEncoder *audioEncoder;

@property (nonatomic , strong) AACPlayer *audioPlayer;

@property (nonatomic, strong) H264Encoder *videoEncoder;

@property (nonatomic , strong) H264Player *videoPlayer;

@property(nonatomic,assign) BOOL isStart;

@end

@implementation VideoCaptureEncodeViewController
{
    dispatch_queue_t _encodeQueue;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    self.audioEncoder = [[AACEncoder alloc] init];
    
    self.videoEncoder = [[H264Encoder alloc] init];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"切换摄像头" style:UIBarButtonItemStyleDone target:self action:@selector(switchButtonAction:)];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"开始录制" style:UIBarButtonItemStyleDone target:self action:@selector(captureButtonAction:)];

    _encodeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    WS(weakSelf)
    
    self.captureManager = [[CaptureManager alloc] initWithSuperView:self.view captureBlock:^(CMSampleBufferRef  _Nonnull sampleBuffer, AVMediaType  _Nonnull type) {
        
        ST(strongSelf)
        
        if (type == AVMediaTypeVideo) {
            
            dispatch_sync(strongSelf->_encodeQueue, ^{
                
                [weakSelf.videoEncoder encodeSampleBuffer:sampleBuffer];
            });
        }
        else {
            
            dispatch_sync(strongSelf->_encodeQueue, ^{
                
                [weakSelf.audioEncoder encodeSampleBuffer:sampleBuffer];
            });
        }
    }];
    
   
}
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [_captureManager initAVCaptureSession];
}
#pragma mark - action
- (void)switchButtonAction:(id)sender
{
    self.navigationItem.leftBarButtonItem.enabled = NO;
    
    [self.captureManager switchCamera];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        self.navigationItem.leftBarButtonItem.enabled = YES;
    });
}
- (void)captureButtonAction:(id)sender
{
    if (!_isStart) {
        
        [self.captureManager startSession];

    }else {
        
        [self.captureManager stopSession];
        
        [self.captureManager.captureVideoPreviewLayer removeFromSuperlayer];
        
        [self startDecode];
    }
    
     self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_isStart ? @"开始录制" : @"结束录制" style:UIBarButtonItemStyleDone target:self action:@selector(captureButtonAction:)];
    
    _isStart = !_isStart;
}
- (void)startDecode
{
    _audioPlayer = [[AACPlayer alloc] init];
    
    [_audioPlayer play];
    
    _videoPlayer = [[H264Player alloc] init];
    
    [_videoPlayer startDecodeWithView:self.view];
}

@end
