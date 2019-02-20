//
//  VideoRecordViewController.m
//  VideoCaptureAndEncode
//
//  Created by 王勇 on 2018/11/20.
//  Copyright © 2018年 王勇. All rights reserved.
//  使用AVFoundation录制音视频并保存到系统相册

#import "VideoRecordViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "CaptureManager.h"
#define kScreenWidth [UIScreen mainScreen].bounds.size.width
#define kScreenHeight [UIScreen mainScreen].bounds.size.height
@interface VideoRecordViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, UIGestureRecognizerDelegate>

/**  写入音视频  */
@property (nonatomic, strong) AVAssetWriter *assetWriter;
/**  写入视频输出  */
@property (nonatomic, strong) AVAssetWriterInput *assetWriterVideoInput;
/**  写入音频输出  */
@property (nonatomic, strong) AVAssetWriterInput *assetWriterAudioInput;
/**  是否可以写入  */
@property (nonatomic, assign) BOOL canWrite;
/**  视频文件地址  */
@property (strong, nonatomic) NSURL *videoURL;
/**  视频预览View  */
@property (strong, nonatomic) UIView *videoPreviewContainerView;
/**  播放器  */
@property (strong, nonatomic) AVPlayer *player;

@property (nonatomic, strong) CaptureManager * captureManager;

@property(nonatomic,assign) BOOL isStart;

@end

@implementation VideoRecordViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"切换摄像头" style:UIBarButtonItemStyleDone target:self action:@selector(switchButtonAction:)];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"开始录制" style:UIBarButtonItemStyleDone target:self action:@selector(captureButtonAction:)];
    
    __weak typeof(self) weakSelf = self;
    
    self.captureManager = [[CaptureManager alloc] initWithSuperView:self.view captureBlock:^(CMSampleBufferRef  _Nonnull sampleBuffer, AVMediaType  _Nonnull type) {
        
        [weakSelf appendSampleBuffer:sampleBuffer ofMediaType:type];
    }];
    // Do any additional setup after loading the view, typically from a nib.
}
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    
    if (authStatus == AVAuthorizationStatusRestricted || authStatus == AVAuthorizationStatusDenied)
    {
        [self requestAuthorizationForVideo];
    }
    
    //判断用户是否允许访问麦克风权限
    authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    
    if (authStatus == AVAuthorizationStatusRestricted || authStatus == AVAuthorizationStatusDenied)
    {
        [self requestAuthorizationForVideo];
    }
    
    [self requestAuthorizationForPhotoLibrary];
    
    [self.captureManager initAVCaptureSession];
}
- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];

    [self.captureManager stopSession];
}
#pragma mark - 视频录制
/**
 *  开始录制视频
 */
- (void)startVideoRecorder
{
    __weak typeof(self) weakSelf = self;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        NSURL *url = [NSURL fileURLWithPath:[weakSelf createVideoFilePath]];
        
        weakSelf.videoURL = url;
        
        [weakSelf setUpWriter];
    });
}

/**
 *  结束录制视频
 */
- (void)stopVideoRecorder
{
    __weak __typeof(self)weakSelf = self;
    
    if(_assetWriter && _assetWriter.status == AVAssetWriterStatusWriting)
    {
        [_assetWriter finishWritingWithCompletionHandler:^{
            
            weakSelf.canWrite = NO;
            
            weakSelf.assetWriter = nil;
            
            weakSelf.assetWriterAudioInput = nil;
            
            weakSelf.assetWriterVideoInput = nil;
        }];
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        [weakSelf previewVideoAfterShoot];
        
    });
}
/**
 *  预览录制的视频
 */
- (void)previewVideoAfterShoot
{
    if (self.videoURL == nil || self.videoPreviewContainerView != nil)
    {
        return;
    }
    
    AVURLAsset *asset = [AVURLAsset assetWithURL:self.videoURL];

    // 初始化AVPlayer
    self.videoPreviewContainerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kScreenWidth, kScreenHeight)];

    self.videoPreviewContainerView.backgroundColor = [UIColor blackColor];
    
    AVPlayerItem * playerItem = [AVPlayerItem playerItemWithAsset:asset];
    
    self.player = [[AVPlayer alloc] initWithPlayerItem:playerItem];
    
    AVPlayerLayer *playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    
    playerLayer.frame = CGRectMake(0, 0, kScreenWidth, kScreenHeight);
    
    playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    
    [self.videoPreviewContainerView.layer addSublayer:playerLayer];
    
    // 其余UI布局设置
    [self.view addSubview:self.videoPreviewContainerView];
    [self.view bringSubviewToFront:self.videoPreviewContainerView];
    
    // 重复播放预览视频
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playVideoFinished:) name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
    
    // 开始播放
    [self.player play];
}
/**
 *  设置写入视频属性
 */
- (void)setUpWriter
{
    if (self.videoURL == nil)
    {
        return;
    }
    
    self.assetWriter = [AVAssetWriter assetWriterWithURL:self.videoURL fileType:AVFileTypeMPEG4 error:nil];
    //写入视频大小
    NSInteger numPixels = kScreenWidth * kScreenHeight;
    
    //每像素比特
    CGFloat bitsPerPixel = 12.0;
    NSInteger bitsPerSecond = numPixels * bitsPerPixel;
    
    // 码率和帧率设置
    NSDictionary *compressionProperties = @{ AVVideoAverageBitRateKey : @(bitsPerSecond),
                                             AVVideoExpectedSourceFrameRateKey : @(15),
                                             AVVideoMaxKeyFrameIntervalKey : @(15),
                                             AVVideoProfileLevelKey : AVVideoProfileLevelH264BaselineAutoLevel };
    CGFloat width = kScreenWidth;
    CGFloat height = kScreenHeight;
    
    //视频属性
    if (@available(iOS 11.0, *)) {
        NSDictionary *videoCompressionSettings = @{ AVVideoCodecKey : AVVideoCodecTypeH264,
                                                    AVVideoWidthKey : @(width * 2),
                                                    AVVideoHeightKey : @(height * 2),
                                                    AVVideoScalingModeKey : AVVideoScalingModeResizeAspectFill,
                                                    AVVideoCompressionPropertiesKey : compressionProperties };
        
        _assetWriterVideoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoCompressionSettings];
    } else {
        // Fallback on earlier versions
    }
    //expectsMediaDataInRealTime 必须设为yes，需要从capture session 实时获取数据
    _assetWriterVideoInput.expectsMediaDataInRealTime = YES;

    // 音频设置
    NSDictionary *audioCompressionSettings = @{ AVEncoderBitRatePerChannelKey : @(28000),
                                                AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                                AVNumberOfChannelsKey : @(1),
                                                AVSampleRateKey : @(22050) };
    
    _assetWriterAudioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioCompressionSettings];
    
    _assetWriterAudioInput.expectsMediaDataInRealTime = YES;
    
    if ([_assetWriter canAddInput:_assetWriterVideoInput])
    {
        [_assetWriter addInput:_assetWriterVideoInput];
    }
    else
    {
        NSLog(@"AssetWriter videoInput append Failed");
    }
    
    if ([_assetWriter canAddInput:_assetWriterAudioInput])
    {
        [_assetWriter addInput:_assetWriterAudioInput];
    }
    else
    {
        NSLog(@"AssetWriter audioInput Append Failed");
    }
    
    _canWrite = NO;
}

- (NSString *)createVideoFilePath
{
    // 创建视频文件的存储路径
    NSString *filePath = [self createVideoFolderPath];
    if (filePath == nil)
    {
        return nil;
    }
    
    NSString *videoType = @".mp4";
    NSString *videoDestDateString = [self createFileNamePrefix];
    NSString *videoFileName = [videoDestDateString stringByAppendingString:videoType];
    
    NSUInteger idx = 1;
    /*We only allow 10000 same file name*/
    NSString *finalPath = [NSString stringWithFormat:@"%@/%@", filePath, videoFileName];
    
    while (idx % 10000 && [[NSFileManager defaultManager] fileExistsAtPath:finalPath])
    {
        finalPath = [NSString stringWithFormat:@"%@/%@_(%lu)%@", filePath, videoDestDateString, (unsigned long)idx++, videoType];
    }
    
    return finalPath;
}

- (NSString *)createVideoFolderPath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *homePath = NSHomeDirectory();
    
    NSString *tmpFilePath;
    
    if (homePath.length > 0)
    {
        NSString *documentPath = [homePath stringByAppendingString:@"/Documents"];
        if ([fileManager fileExistsAtPath:documentPath isDirectory:NULL] == YES)
        {
            BOOL success = NO;
            
            NSArray *paths = [fileManager contentsOfDirectoryAtPath:documentPath error:nil];
            
            //offline file folder
            tmpFilePath = [documentPath stringByAppendingString:[NSString stringWithFormat:@"/%@", @"video"]];
            
            if ([paths containsObject:@"video"] == NO)
            {
                success = [fileManager createDirectoryAtPath:tmpFilePath withIntermediateDirectories:YES attributes:nil error:nil];
                if (!success)
                {
                    tmpFilePath = nil;
                }
            }
            return tmpFilePath;
        }
    }
    
    return false;
}

/**
 *  创建文件名
 */
- (NSString *)createFileNamePrefix
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss zzz"];
    
    NSString *destDateString = [dateFormatter stringFromDate:[NSDate date]];
    destDateString = [destDateString stringByReplacingOccurrencesOfString:@" " withString:@"-"];
    destDateString = [destDateString stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    destDateString = [destDateString stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    
    return destDateString;
}
- (void)stopPlayer
{
    if (self.videoPreviewContainerView)
    {
        [self.player pause];
        
        self.player = nil;
        
        [self.videoPreviewContainerView removeFromSuperview];
        
        self.videoPreviewContainerView = nil;
        
        [[NSFileManager defaultManager] removeItemAtURL:self.videoURL error:nil];
        
        self.videoURL = nil;
    }
}
- (void)saveVideo
{
    [self cropWithVideoUrlStr:self.videoURL completion:^(NSURL *videoUrl, Float64 videoDuration, BOOL isSuccess) {
        
        if (isSuccess)
        {
            NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
            
            NSString * assetCollectionName = [infoDictionary objectForKey:@"CFBundleDisplayName"];
            
            if (assetCollectionName == nil)
            {
                assetCollectionName = @"视频相册";
            }
            
            __block NSString *blockAssetCollectionName = assetCollectionName;
            
            __block NSURL *blockVideoUrl = videoUrl;
            
            PHPhotoLibrary *library = [PHPhotoLibrary sharedPhotoLibrary];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                NSError *error = nil;
                __block NSString *assetId = nil;
                __block NSString *assetCollectionId = nil;
                
                // 保存视频到【Camera Roll】(相机胶卷)
                [library performChangesAndWait:^{
                    
                    assetId = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:blockVideoUrl].placeholderForCreatedAsset.localIdentifier;
                    
                } error:&error];
                
                NSLog(@"error1: %@", error);
                
                // 获取曾经创建过的自定义视频相册名字
                PHAssetCollection *createdAssetCollection = nil;
                PHFetchResult <PHAssetCollection*> *assetCollections = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:nil];
                for (PHAssetCollection *assetCollection in assetCollections)
                {
                    if ([assetCollection.localizedTitle isEqualToString:blockAssetCollectionName])
                    {
                        createdAssetCollection = assetCollection;
                        break;
                    }
                }
                
                //如果这个自定义框架没有创建过
                if (createdAssetCollection == nil)
                {
                    //创建新的[自定义的 Album](相簿\相册)
                    [library performChangesAndWait:^{
                        
                        assetCollectionId = [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:blockAssetCollectionName].placeholderForCreatedAssetCollection.localIdentifier;
                        
                    } error:&error];
                    
                    NSLog(@"error2: %@", error);
                    
                    //抓取刚创建完的视频相册对象
                    createdAssetCollection = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[assetCollectionId] options:nil].firstObject;
                    
                }
                
                // 将【Camera Roll】(相机胶卷)的视频 添加到【自定义Album】(相簿\相册)中
                [library performChangesAndWait:^{
                    PHAssetCollectionChangeRequest *request = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:createdAssetCollection];
                    
                    [request addAssets:[PHAsset fetchAssetsWithLocalIdentifiers:@[assetId] options:nil]];
                    
                } error:&error];
                
                NSLog(@"error3: %@", error);
                
            });
        }
        else
        {
            NSLog(@"保存视频失败!");
            
            [[NSFileManager defaultManager] removeItemAtURL:self.videoURL error:nil];
            
            self.videoURL = nil;
            
            [[NSFileManager defaultManager] removeItemAtURL:videoUrl error:nil];
        }
    }];
}
#pragma mark - 预览视频通知

-(void)removePlayerItemNotification
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/**
 *  播放完成通知
 *
 *  @param notification 通知对象
 */
-(void)playVideoFinished:(NSNotification *)notification
{
    [self.player seekToTime:CMTimeMake(0, 1)];
    [self.player play];
    [self saveVideo];
}
#pragma mark - 截取视频方法

- (void)cropWithVideoUrlStr:(NSURL *)videoUrl completion:(void (^)(NSURL *outputURL, Float64 videoDuration, BOOL isSuccess))completionHandle
{
    AVURLAsset *asset =[[AVURLAsset alloc] initWithURL:videoUrl options:nil];
    
    //获取视频总时长
    Float64 endTime = CMTimeGetSeconds(asset.duration);
    
    if (endTime > 10)
    {
        endTime = 10.0f;
    }
    
    Float64 startTime = 0;
    
    NSString *outputFilePath = [self createVideoFilePath];
    
    NSURL *outputFileUrl = [NSURL fileURLWithPath:outputFilePath];
    
    NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    
    if ([compatiblePresets containsObject:AVAssetExportPresetMediumQuality])
    {
        
        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc]
                                               initWithAsset:asset presetName:AVAssetExportPresetPassthrough];
        
        NSURL *outputURL = outputFileUrl;
        
        exportSession.outputURL = outputURL;
        exportSession.outputFileType = AVFileTypeMPEG4;
        exportSession.shouldOptimizeForNetworkUse = YES;
        
        CMTime start = CMTimeMakeWithSeconds(startTime, asset.duration.timescale);
        CMTime duration = CMTimeMakeWithSeconds(endTime - startTime,asset.duration.timescale);
        CMTimeRange range = CMTimeRangeMake(start, duration);
        exportSession.timeRange = range;
        
        [exportSession exportAsynchronouslyWithCompletionHandler:^{
            switch ([exportSession status]) {
                case AVAssetExportSessionStatusFailed:
                {
                    NSLog(@"合成失败：%@", [[exportSession error] description]);
                    completionHandle(outputURL, endTime, NO);
                }
                    break;
                case AVAssetExportSessionStatusCancelled:
                {
                    completionHandle(outputURL, endTime, NO);
                }
                    break;
                case AVAssetExportSessionStatusCompleted:
                {
                    completionHandle(outputURL, endTime, YES);
                }
                    break;
                default:
                {
                    completionHandle(outputURL, endTime, NO);
                } break;
            }
        }];
    }
}
#pragma mark - 判断是否有权限

/**
 *  请求权限
 */
- (void)requestAuthorizationForVideo
{
    __weak typeof(self) weakSelf = self;
    
    // 请求相机权限
    AVAuthorizationStatus videoAuthStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (videoAuthStatus != AVAuthorizationStatusAuthorized)
    {
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
        
        NSString *appName = [infoDictionary objectForKey:@"CFBundleDisplayName"];
        if (appName == nil)
        {
            appName = @"APP";
        }
        NSString *message = [NSString stringWithFormat:@"允许%@访问你的相机？", appName];
        
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"警告" message:message preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [weakSelf dismissViewControllerAnimated:YES completion:nil];
        }];
        
        UIAlertAction *setAction = [UIAlertAction actionWithTitle:@"设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
            if ([[UIApplication sharedApplication] canOpenURL:url])
            {
                [[UIApplication sharedApplication] openURL:url];
                [weakSelf dismissViewControllerAnimated:YES completion:nil];
            }
        }];
        
        [alertController addAction:okAction];
        [alertController addAction:setAction];
        
        [weakSelf presentViewController:alertController animated:YES completion:nil];
    }
    
    // 请求麦克风权限
    AVAuthorizationStatus audioAuthStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (audioAuthStatus != AVAuthorizationStatusAuthorized)
    {
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
        
        NSString *appName = [infoDictionary objectForKey:@"CFBundleDisplayName"];
        if (appName == nil)
        {
            appName = @"APP";
        }
        NSString *message = [NSString stringWithFormat:@"允许%@访问你的麦克风？", appName];
        
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"警告" message:message preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [weakSelf dismissViewControllerAnimated:YES completion:nil];
        }];
        
        UIAlertAction *setAction = [UIAlertAction actionWithTitle:@"设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
            if ([[UIApplication sharedApplication] canOpenURL:url])
            {
                [[UIApplication sharedApplication] openURL:url];
                [weakSelf dismissViewControllerAnimated:YES completion:nil];
            }
        }];
        
        [alertController addAction:okAction];
        [alertController addAction:setAction];
        
        [self presentViewController:alertController animated:YES completion:nil];
    }
    
    
}
- (void)requestAuthorizationForPhotoLibrary
{
    __weak typeof(self) weakSelf = self;
    PHAuthorizationStatus authStatus = [PHPhotoLibrary authorizationStatus];
    if (authStatus != PHAuthorizationStatusAuthorized) // 未授权
    {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            if (status != PHAuthorizationStatusAuthorized)  //已授权
            {
                NSLog(@"用户拒绝访问相册！");
                NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
                
                NSString *appName = [infoDictionary objectForKey:@"CFBundleDisplayName"];
                if (appName == nil)
                {
                    appName = @"APP";
                }
                NSString *message = [NSString stringWithFormat:@"允许%@访问你的相册？", appName];
                
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"警告" message:message preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    [weakSelf dismissViewControllerAnimated:YES completion:nil];
                }];
                
                UIAlertAction *setAction = [UIAlertAction actionWithTitle:@"设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
                    if ([[UIApplication sharedApplication] canOpenURL:url])
                    {
                        [[UIApplication sharedApplication] openURL:url];
                        [weakSelf dismissViewControllerAnimated:YES completion:nil];
                    }
                }];
                
                [alertController addAction:okAction];
                [alertController addAction:setAction];
                
                [self presentViewController:alertController animated:YES completion:nil];
            }
            else
            {
                NSLog(@"用户允许访问相册！");
            }
        }];
    }
    else
    {
        // nothing
    }
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
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_isStart ? @"开始录制" : @"结束录制" style:UIBarButtonItemStyleDone target:self action:@selector(captureButtonAction:)];
    
    if (!_isStart){
        
        [self stopPlayer];

        [self.captureManager startSession];
        
        self.captureManager.captureVideoPreviewLayer.frame = CGRectMake(0, 0, kScreenWidth, kScreenHeight);
        
        [self startVideoRecorder];
    }
    
    else{

        [self.captureManager stopSession];
        
        self.captureManager.captureVideoPreviewLayer.frame = CGRectZero;
        
        [self stopVideoRecorder];
        
        self.navigationItem.leftBarButtonItem.enabled = self.navigationItem.rightBarButtonItem.enabled = NO;
    }
    
    _isStart = !_isStart;
}
#pragma mark -
/**
 *  开始写入数据
 */
- (void)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer ofMediaType:(NSString *)mediaType
{
    if (sampleBuffer == NULL)
    {
        NSLog(@"empty sampleBuffer");
        return;
    }
    
    @autoreleasepool
    {
        if (!self.canWrite && mediaType == AVMediaTypeVideo && self.assetWriter && self.assetWriter.status != AVAssetWriterStatusWriting)
        {
            
            [self.assetWriter startWriting];
            [self.assetWriter startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
            self.canWrite = YES;
        }
        
        //写入视频数据
        if (mediaType == AVMediaTypeVideo && self.assetWriterVideoInput.readyForMoreMediaData)
        {
            if (![self.assetWriterVideoInput appendSampleBuffer:sampleBuffer])
            {
                @synchronized (self)
                {
                    [self stopVideoRecorder];
                }
            }
        }
        
        //写入音频数据
        if (mediaType == AVMediaTypeAudio && self.assetWriterAudioInput.readyForMoreMediaData)
        {
            if (![self.assetWriterAudioInput appendSampleBuffer:sampleBuffer])
            {
                @synchronized (self)
                {
                    [self stopVideoRecorder];
                }
            }
        }
    }
}

@end
