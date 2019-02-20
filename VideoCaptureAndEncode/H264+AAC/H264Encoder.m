//
//  H264Encoder.m
//  VideoCaptureAndEncode
//
//  Created by 王勇 on 2018/11/21.
//  Copyright © 2018年 王勇. All rights reserved.
//

#import "H264Encoder.h"

#import <UIKit/UIKit.h>

@interface H264Encoder ()
{
    int _frameID;
    
    VTCompressionSessionRef _EncodingSession;
    
    CMFormatDescriptionRef  _format;
    
    NSFileHandle *_videoFileHandle;
    
    NSFileHandle *_audioFileHandle;
    
    dispatch_queue_t _encodeQueue;
}
@end

@implementation H264Encoder
#pragma mark - public
- (void)encodeSampleBuffer:(CMSampleBufferRef )sampleBuffer
{
    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    // 帧时间，如果不设置会导致时间轴过长。
    CMTime presentationTimeStamp = CMTimeMake(_frameID++, 1000);
    
    VTEncodeInfoFlags flags;
    
    OSStatus statusCode = VTCompressionSessionEncodeFrame(_EncodingSession,
                                                          imageBuffer,
                                                          presentationTimeStamp,
                                                          kCMTimeInvalid,
                                                          NULL, NULL, &flags);
    if (statusCode != noErr) {
        
        NSLog(@"H264: VTCompressionSessionEncodeFrame failed with %d", (int)statusCode);
        
        VTCompressionSessionInvalidate(_EncodingSession);
        
        CFRelease(_EncodingSession);
        
        _EncodingSession = NULL;
        
        return;
    }
    NSLog(@"H264: VTCompressionSessionEncodeFrame Success");
}
- (void)EndVideoToolBox
{
    VTCompressionSessionCompleteFrames(_EncodingSession, kCMTimeInvalid);
    
    VTCompressionSessionInvalidate(_EncodingSession);
    
    CFRelease(_EncodingSession);
    
    _EncodingSession = NULL;
    
    [_videoFileHandle closeFile];
    
    _videoFileHandle = NULL;
    
    [_audioFileHandle closeFile];
    
    _audioFileHandle = NULL;
}
- (NSFileHandle *)audioFileHandle
{
    return _audioFileHandle;
}
#pragma mark -

- (instancetype)init
{
    self = [super init];
    if (self) {
        
        [self initVideoToolBox];
    }
    return self;
}

- (void)initVideoToolBox
{
    
    _frameID = 0;
    
    int width = 480, height = 640;
    
    OSStatus status = VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, didCompressH264, (__bridge void *)(self),  &_EncodingSession);
    
    NSLog(@"H264: VTCompressionSessionCreate %d", (int)status);
    
    if (status != 0)
    {
        NSLog(@"H264: Unable to create a H264 session");
        return ;
    }
    
    // 设置实时编码输出（避免延迟）
    VTSessionSetProperty(_EncodingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    
    VTSessionSetProperty(_EncodingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
    
    // 设置关键帧（GOPsize)间隔
    int frameInterval = 24;
    
    CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
    
    VTSessionSetProperty(_EncodingSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
    
    // 设置期望帧率
    int fps = 24;
    CFNumberRef  fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &fps);
    
    VTSessionSetProperty(_EncodingSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
    
    
    //设置码率，均值，单位是byte
    int bitRate = 1024*1024*1024;
    
    CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRate);
    
    VTSessionSetProperty(_EncodingSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
    
    //设置码率，上限，单位是bps
    int bitRateLimit = 1024 *1024*1024;
    
    CFNumberRef bitRateLimitRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRateLimit);
    
    VTSessionSetProperty(_EncodingSession, kVTCompressionPropertyKey_DataRateLimits, bitRateLimitRef);
    
    // Tell the encoder to start encoding
    VTCompressionSessionPrepareToEncodeFrames(_EncodingSession);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [self setupFile];
    });
}
- (void)setupFile
{
    NSString *file = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"abc.h264"];
    
    [[NSFileManager defaultManager] removeItemAtPath:file error:nil];
    
    [[NSFileManager defaultManager] createFileAtPath:file contents:nil attributes:nil];
    
    _videoFileHandle = [NSFileHandle fileHandleForWritingAtPath:file];
    
    
    NSString *audioFile = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"abc.aac"];
    
    [[NSFileManager defaultManager] removeItemAtPath:audioFile error:nil];
    
    [[NSFileManager defaultManager] createFileAtPath:audioFile contents:nil attributes:nil];
    
    _audioFileHandle = [NSFileHandle fileHandleForWritingAtPath:audioFile];
}

// 编码完成回调
void didCompressH264(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer) {
    
    NSLog(@"didCompressH264 called with status %d infoFlags %d", (int)status, (int)infoFlags);
    
    if (status != 0) {
        return;
    }
    
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
    
    H264Encoder* encoder = (__bridge H264Encoder*)outputCallbackRefCon;
    
    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    
    // 判断当前帧是否为关键帧
    // 获取sps & pps数据
    if (keyframe)
    {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        
        size_t sparameterSetSize, sparameterSetCount;
        
        const uint8_t *sparameterSet;
        
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
        
        if (statusCode == noErr)
        {
            // Found sps and now check for pps
            size_t pparameterSetSize, pparameterSetCount;
            
            const uint8_t *pparameterSet;
            
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
            
            if (statusCode == noErr)
            {
                // Found pps
                NSData *sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                
                NSData *pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                
                if (encoder)
                {
                    [encoder gotSpsPps:sps pps:pps];
                }
            }
        }
    }
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    
    size_t length, totalLength;
    
    char *dataPointer;
    
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        
        size_t bufferOffset = 0;
        
        static const int AVCCHeaderLength = 4; // 返回的nalu数据前四个字节不是0001的startcode，而是大端模式的帧长度length
        
        // 循环获取nalu数据
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            
            uint32_t NALUnitLength = 0;
            // Read the NAL unit length
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            
            // 从大端转系统端
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            
            NSData* data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
            [encoder gotEncodedData:data isKeyFrame:keyframe];
            
            // Move to the next NAL unit in the block buffer
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
}
- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps
{
    NSLog(@"gotSpsPps %d %d", (int)[sps length], (int)[pps length]);
    
    const char bytes[] = "\x00\x00\x00\x01";
    
    size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
    
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    
    [_videoFileHandle writeData:ByteHeader];
    
    [_videoFileHandle writeData:sps];
    
    [_videoFileHandle writeData:ByteHeader];
    
    [_videoFileHandle writeData:pps];
    
}
- (void)gotEncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame
{
    NSLog(@"gotEncodedData %d", (int)[data length]);
    
    if (_videoFileHandle != NULL)
    {
        const char bytes[] = "\x00\x00\x00\x01";
        
        size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
        
        NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
        
        [_videoFileHandle writeData:ByteHeader];
        
        [_videoFileHandle writeData:data];
    }
}

@end
