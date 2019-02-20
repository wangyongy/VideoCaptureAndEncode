//
//  CaptureManager.m
//  VideoCaptureAndEncode
//
//  Created by 王勇 on 2018/11/21.
//  Copyright © 2018年 王勇. All rights reserved.
//

#import "CaptureManager.h"

@interface CaptureManager ()<AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate>

/**  自定义串行队列  */
@property (nonatomic, strong) dispatch_queue_t videoQueue;
/**  负责输入和输出设备之间的数据传递  */
@property (strong, nonatomic) AVCaptureSession *captureSession;
/**  视频输入  */
@property (nonatomic, strong) AVCaptureDeviceInput *videoInput;
/**  视频输出  */
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
/**  声音输出  */
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioOutput;
/**  预览图层  */
@property (strong, nonatomic) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;

@property (nonatomic, copy) void(^captureBlock)(CMSampleBufferRef sampleBuffer ,AVMediaType type);

@property (strong, nonatomic) UIView *superView;

@end

@implementation CaptureManager

- (instancetype)initWithSuperView:(UIView *)superView captureBlock:(void(^)(CMSampleBufferRef sampleBuffer ,AVMediaType type))captureBlock
{
    self = [super init];
    
    if (self) {
        
        _captureBlock = captureBlock;
        
        _superView = superView;
    }
    return self;
}
/**
 *  初始化AVCapture会话
 */
- (void)initAVCaptureSession
{
    //1、添加 "视频" 与 "音频" 输入流到session
    [self setupVideo];
    
//    [self setupAudio];
    
    //2、创建视频预览层，用于实时展示摄像头状态
    [self setupCaptureVideoPreviewLayer];
    
    //设置静音状态也可播放声音
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
}
/**
 *  开启会话
 */
- (void)startSession
{
    if (![self.captureSession isRunning])
    {
        [self.captureSession startRunning];
    }
}

/**
 *  停止会话
 */
- (void)stopSession
{
    if ([self.captureSession isRunning])
    {
        [self.captureSession stopRunning];
    }
}
- (AVCaptureDeviceInput *)videoInput
{
    return _videoInput;
}
- (AVCaptureVideoPreviewLayer *)captureVideoPreviewLayer
{
    return _captureVideoPreviewLayer;
}
/**
 *  取得指定位置的摄像头
 *
 *  @param position 摄像头位置
 *
 *  @return 摄像头设备
 */
- (AVCaptureDevice *)getCameraDeviceWithPosition:(AVCaptureDevicePosition )position
{
    NSArray *cameras = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:position].devices;
    
    for (AVCaptureDevice *camera in cameras)
    {
        if ([camera position] == position)
        {
            return camera;
        }
    }
    return nil;
}
- (void)switchCamera
{

    AVCaptureDevice *currentDevice = [self.videoInput device];
    
    AVCaptureDevicePosition currentPosition = [currentDevice position];
    
    AVCaptureDevice *toChangeDevice;
    
    AVCaptureDevicePosition toChangePosition = AVCaptureDevicePositionFront;
    
    if (currentPosition == AVCaptureDevicePositionUnspecified || currentPosition == AVCaptureDevicePositionFront)
    {
        toChangePosition = AVCaptureDevicePositionBack;
    }
    
    toChangeDevice = [self getCameraDeviceWithPosition:toChangePosition];
    
    //获得要调整的设备输入对象
    AVCaptureDeviceInput *toChangeDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:toChangeDevice error:nil];
    
    //改变会话的配置前一定要先开启配置，配置完成后提交配置改变
    [self.captureSession beginConfiguration];
    //移除原有输入对象
    [self.captureSession removeInput:self.videoInput];
    //添加新的输入对象
    if ([self.captureSession canAddInput:toChangeDeviceInput])
    {
        [self.captureSession addInput:toChangeDeviceInput];
        
        AVCaptureConnection *connection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
        
        [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
        
        self.videoInput = toChangeDeviceInput;
    }
    
    //提交会话配置
    [self.captureSession commitConfiguration];
}
#pragma mark - 懒加载
- (AVCaptureSession *)captureSession
{
    if (_captureSession == nil)
    {
        _captureSession = [[AVCaptureSession alloc] init];
        
        if ([_captureSession canSetSessionPreset:AVCaptureSessionPresetHigh])
        {
            _captureSession.sessionPreset = AVCaptureSessionPresetHigh;
        }
    }
    
    return _captureSession;
}

- (dispatch_queue_t)videoQueue
{
    if (!_videoQueue)
    {
        _videoQueue = dispatch_queue_create("videoQueue", DISPATCH_QUEUE_SERIAL); // dispatch_get_main_queue();
    }
    
    return _videoQueue;
}
#pragma mark - 私有方法


/**
 *  设置视频输入
 */
- (void)setupVideo
{
    AVCaptureDevice *captureDevice = [self getCameraDeviceWithPosition:AVCaptureDevicePositionBack];
    
    if (!captureDevice)
    {
        NSLog(@"取得后置摄像头时出现问题.");
        
        return;
    }
    
    NSError *error = nil;
    
    AVCaptureDeviceInput *videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:captureDevice error:&error];
    if (error)
    {
        NSLog(@"取得设备输入videoInput对象时出错，错误原因：%@", error);
        
        return;
    }
    
    //3、将设备输出添加到会话中
    if ([self.captureSession canAddInput:videoInput])
    {
        [self.captureSession addInput:videoInput];
    }
    
    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    
    self.videoOutput.alwaysDiscardsLateVideoFrames = NO; //立即丢弃旧帧，节省内存，默认YES
    
    [self.videoOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    
    [self.videoOutput setSampleBufferDelegate:self queue:self.videoQueue];
    
    if ([self.captureSession canAddOutput:self.videoOutput])
    {
        [self.captureSession addOutput:self.videoOutput];
    }
    
    AVCaptureConnection *connection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
    
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    
    self.videoInput = videoInput;
}

/**
 *  设置音频录入
 */
- (void)setupAudio
{
    NSError *error = nil;
    AVCaptureDeviceInput *audioInput = [[AVCaptureDeviceInput alloc] initWithDevice:[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio] error:&error];
    if (error)
    {
        NSLog(@"取得设备输入audioInput对象时出错，错误原因：%@", error);
        
        return;
    }
    if ([self.captureSession canAddInput:audioInput])
    {
        [self.captureSession addInput:audioInput];
    }
    
    self.audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    
    [self.audioOutput setSampleBufferDelegate:self queue:self.videoQueue];
    
    if([self.captureSession canAddOutput:self.audioOutput])
    {
        [self.captureSession addOutput:self.audioOutput];
    }
}

/**
 *  设置预览layer
 */
- (void)setupCaptureVideoPreviewLayer
{
    _captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.captureSession];
    
    _captureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspect;           //填充模式
    
    [_captureVideoPreviewLayer setFrame:self.superView.bounds];
    
    [self.superView.layer addSublayer:_captureVideoPreviewLayer];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate AVCaptureAudioDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    
    @autoreleasepool
    {
        //视频
        if (connection == [self.videoOutput connectionWithMediaType:AVMediaTypeVideo])
        {
            @synchronized(self)
            {
                if (self.captureBlock) {
                    
                    self.captureBlock(sampleBuffer, AVMediaTypeVideo);
                }
            }
        }
        
        //音频
        if (connection == [self.audioOutput connectionWithMediaType:AVMediaTypeAudio])
        {
            @synchronized(self)
            {
                if (self.captureBlock) {
                    
                    self.captureBlock(sampleBuffer, AVMediaTypeAudio);
                }
            }
        }
    }
}
@end
