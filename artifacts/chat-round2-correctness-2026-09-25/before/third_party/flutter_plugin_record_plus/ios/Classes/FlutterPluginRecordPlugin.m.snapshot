// FlutterPluginRecordPlugin.m
// 
// Created by joy on 2022/07/08
// Copyright (c) 2022年 Tencent. All rights reserved.
//
#import "FlutterPluginRecordPlugin.h"
#import "DPAudioRecorder.h"
#import "DPAudioPlayer.h"


@implementation FlutterPluginRecordPlugin{
    FlutterMethodChannel *_channel;
    FlutterResult  _result;
    FlutterMethodCall  *_call;
    NSData  *wavData;
    NSString *audioPath;
    BOOL _isInit;//是否执行初始化的标识
    NSString *_activeRecordSessionId;
    NSString *_activeRecordRequestId;
}

- (void)notifyRecordFailedForRequestId:(NSString *)requestId
                             sessionId:(NSString *)sessionId
                                reason:(NSString *)reason {
    NSDictionary *payload = @{
        @"result": reason ?: @"record_failed",
        @"id": requestId ?: @"",
        @"sessionId": sessionId ?: @"",
    };
    [_channel invokeMethod:@"onRecordFail" arguments:payload];
}

+ (void)registerWithRegistrar:(NSObject <FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *channel = [FlutterMethodChannel
                                     methodChannelWithName:@"flutter_plugin_record"
                                     binaryMessenger:[registrar messenger]];
    
    FlutterPluginRecordPlugin *instance =  [[FlutterPluginRecordPlugin alloc] initWithChannel:channel];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithChannel:(FlutterMethodChannel *)channel {
    self = [super init];
    if (self) {
        _channel = channel;
        _isInit = NO;
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result{
    _result  = result;
    _call = call;
    NSString *method = call.method;
    if ([@"init" isEqualToString:method]) {
        [self initRecord ];
        result(nil);
    }else if([@"initRecordMp3" isEqualToString:method]){
        [self initMp3Record];
        result(nil);
    }else if([@"startByWavPath" isEqualToString:method]){
        [self startByWavPath];
        result(nil);
    }else if([@"start" isEqualToString:method]){
        [self start ];
        result(nil);
    }else if([@"stop" isEqualToString:method]){
        [self stop ];
        result(nil);
    }else if([@"play" isEqualToString:method]){
        [self play ];
    }else if([@"pause" isEqualToString:method]){
        [self pausePlay ];
    }else if([@"playByPath" isEqualToString:method]){
        [self playByPath];
    }else if([@"stopPlay" isEqualToString:method]){
        [self stopPlay];
    }else{
        result(FlutterMethodNotImplemented);
    }
    
}



//初始化录制mp3
- (void) initMp3Record{
    [DPAudioRecorder.sharedInstance initByMp3];
    [self initRecord];
    
}

///初始化语音录制的方法 初始化录制完成的回调,开始录制的回调,录制失败的回调,录制音量大小的回调
/// 注意未初始化的话 Flutter 不能监听到上述回调事件
- (void) initRecord{
    _isInit = YES;
    
    DPAudioRecorder.sharedInstance.audioRecorderFinishRecording = ^void (NSData *data, NSTimeInterval audioTimeLength,NSString *path){
        self->audioPath =path;
        self->wavData = data;
        NSLog(@"ios  voice   onStop");
        NSDictionary *args =   [self->_call arguments];
        NSString *mId = self->_activeRecordRequestId ?: [args valueForKey:@"id"];
        NSString *sessionId = self->_activeRecordSessionId ?: @"";
        if (sessionId.length == 0) return;
        
        NSDictionary *dict3 = [NSDictionary dictionaryWithObjectsAndKeys:
                               @"success", @"result",
                               mId, @"id",
                               sessionId, @"sessionId",
                               path, @"voicePath",
                               [NSString stringWithFormat:@"%.20lf", audioTimeLength], @"audioTimeLength",
                               nil];
        [self->_channel invokeMethod:@"onStop" arguments:dict3];
        self->_activeRecordSessionId = nil;
        self->_activeRecordRequestId = nil;
        
    };
    
    DPAudioRecorder.sharedInstance.audioStartRecording =  ^void(BOOL isRecording){
        NSLog(@"ios  voice   start  audioStartRecording");
        if (self->_activeRecordSessionId.length == 0) return;
        if (!isRecording) {
            NSDictionary *failure = @{
                @"result": @"start_failed",
                @"id": self->_activeRecordRequestId ?: @"",
                @"sessionId": self->_activeRecordSessionId,
            };
            [self->_channel invokeMethod:@"onRecordFail" arguments:failure];
            self->_activeRecordSessionId = nil;
            self->_activeRecordRequestId = nil;
            return;
        }
        NSDictionary *payload = @{
            @"result": @"success",
            @"id": self->_activeRecordRequestId ?: @"",
            @"sessionId": self->_activeRecordSessionId,
        };
        [self->_channel invokeMethod:@"onStart" arguments:payload];
    };
    DPAudioRecorder.sharedInstance.audioRecordingFail = ^void(NSString *reason){
        NSLog(@"ios  voice %@", reason);
        NSDictionary *args = [self->_call arguments];
        NSString *mId = self->_activeRecordRequestId ?: [args valueForKey:@"id"];
        NSString *sessionId = self->_activeRecordSessionId ?: @"";
        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                              @"fail", @"result",
                              mId ?: @"", @"id",
                              sessionId, @"sessionId",
                              reason ?: @"", @"reason",
                              nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_channel invokeMethod:@"onRecordFail" arguments:dict];
            self->_activeRecordSessionId = nil;
            self->_activeRecordRequestId = nil;
        });
    };
    DPAudioRecorder.sharedInstance.audioSpeakPower = ^void(float power){
        NSString *powerStr = [NSString stringWithFormat:@"%f", power];
        NSString *mId = self->_activeRecordRequestId ?: @"";
        NSString *sessionId = self->_activeRecordSessionId ?: @"";
        NSDictionary *dict3 = [NSDictionary dictionaryWithObjectsAndKeys:
                               @"success",@"result",
                               mId ,@"id",
                               sessionId, @"sessionId",
                               powerStr,@"amplitude",
                               nil];
        [self->_channel invokeMethod:@"onAmplitude" arguments:dict3];
    };
    
    NSLog(@"ios  voice   init");
    NSDictionary *args =   [_call arguments];
    NSString *mId = [args valueForKey:@"id"];
    NSDictionary *dict3 = [NSDictionary dictionaryWithObjectsAndKeys:@"success",@"result",mId,@"id", nil];
    [_channel invokeMethod:@"onInit" arguments:dict3];
}



/// 开始录制的方法
- (void) start{
    NSDictionary *args = [_call arguments];
    NSString *mId = [args valueForKey:@"id"];
    NSString *sessionId = [args valueForKey:@"sessionId"] ?: @"";
    if (!_isInit) {
        NSLog(@"ios-------未初始化录制方法- initRecord--");
        [self notifyRecordFailedForRequestId:mId sessionId:sessionId reason:@"not_initialized"];
        return;
    }
    NSLog(@"ios--------start record -----function--- start----");
    if (sessionId.length == 0) {
        [self notifyRecordFailedForRequestId:mId sessionId:sessionId reason:@"invalid_session"];
        return;
    }
    if (_activeRecordSessionId != nil) {
        [self notifyRecordFailedForRequestId:mId sessionId:sessionId reason:@"record_busy"];
        return;
    }
    _activeRecordSessionId = sessionId;
    _activeRecordRequestId = mId;
    [DPAudioRecorder.sharedInstance startRecording];
}

/// 根据文件路径进行录制
- (void) startByWavPath{
    NSDictionary *args = [_call arguments];
    NSString *mId = [args valueForKey:@"id"];
    NSString *sessionId = [args valueForKey:@"sessionId"] ?: @"";
    if (!_isInit) {
        NSLog(@"ios-------未初始化录制方法- initRecord--");
        [self notifyRecordFailedForRequestId:mId sessionId:sessionId reason:@"not_initialized"];
        return;
    }
    NSString *wavPath = [args valueForKey:@"wavPath"];
    
    NSLog(@"ios--------start record -----function--- startByWavPath----%@", wavPath);
    
    if (sessionId.length == 0 || wavPath.length == 0) {
        [self notifyRecordFailedForRequestId:mId sessionId:sessionId reason:@"invalid_record_request"];
        return;
    }
    if (_activeRecordSessionId != nil) {
        [self notifyRecordFailedForRequestId:mId sessionId:sessionId reason:@"record_busy"];
        return;
    }
    _activeRecordSessionId = sessionId;
    _activeRecordRequestId = mId;
    [DPAudioRecorder.sharedInstance initByWavPath:wavPath];
    [DPAudioRecorder.sharedInstance startRecording];
    
}



/// 停止录制的方法
- (void) stop{
    if (!_isInit) {
        NSLog(@"ios-------未初始化录制方法- initRecord--");
        return;
    }
    NSLog(@"ios--------stop record -----function--- stop----");
    NSString *sessionId = [[_call arguments] valueForKey:@"sessionId"] ?: @"";
    if ([_activeRecordSessionId isEqualToString:sessionId]) {
        [DPAudioRecorder.sharedInstance stopRecording];
    }
}



///  播放录制完成的音频
- (void) play{
    
    NSLog(@"ios------play voice by warData----function---play--");
    [DPAudioPlayer.sharedInstance startPlayWithData:self->wavData];
    DPAudioPlayer.sharedInstance.playComplete = ^void(){
        NSLog(@"ios-----播放完成----by play");
        NSDictionary *args =   [self->_call arguments];
        NSString *mId = [args valueForKey:@"id"];
        NSDictionary *dict3 = [NSDictionary dictionaryWithObjectsAndKeys:self->audioPath,@"playPath",@"complete",@"playState",mId,@"id", nil];
        [self->_channel invokeMethod:@"onPlayState" arguments:dict3];
    };
    
    
    NSDictionary *args =   [_call arguments];
    NSString *mId = [args valueForKey:@"id"];
    NSDictionary *dict3 = [NSDictionary dictionaryWithObjectsAndKeys:@"success",@"result",mId,@"id", nil];
    [_channel invokeMethod:@"onPlay" arguments:dict3];
}
- (void)stopPlay{
    [DPAudioPlayer.sharedInstance stopPlaying];
    
}
- (void) pausePlay{
    
    NSLog(@"ios------pausePlay----function---pausePlay--");
    bool isPlaying =  [DPAudioPlayer.sharedInstance pausePlaying];
    
    NSDictionary *args =   [_call arguments];
    NSString *mId = [args valueForKey:@"id"];
    NSString *isPlayingStr = nil;
    if (isPlaying) {
        isPlayingStr = @"true";
    }else{
        isPlayingStr = @"false";
    }
    NSDictionary *dict3 = [NSDictionary dictionaryWithObjectsAndKeys:
                           @"success",@"result",
                           isPlayingStr,@"isPlaying",
                           mId,@"id",
                           nil];
    [_channel invokeMethod:@"pausePlay" arguments:dict3];
}

/// 根据指定路径播放音频
- (void) playByPath{
    NSLog(@"ios------play voice by path-----function---playByPath---");
    NSDictionary *args =   [_call arguments];
    NSString *filePath = [args valueForKey:@"path"];
    
    NSString *typeStr = [args valueForKey:@"type"];
    NSData *data;
    if ([typeStr isEqualToString:@"url"]) {
        data =[[NSData alloc]initWithContentsOfURL:[NSURL URLWithString:filePath]];
    }else if([typeStr isEqualToString:@"file"]){
        data= [NSData dataWithContentsOfFile:filePath];
        
    }
    
    [DPAudioPlayer.sharedInstance startPlayWithData:data];
    DPAudioPlayer.sharedInstance.playComplete = ^void(){
        NSLog(@"ios-----播放完成----by playbyPath---");
        NSDictionary *args =   [self->_call arguments];
        NSString *mId = [args valueForKey:@"id"];
        NSDictionary *dict3 = [NSDictionary dictionaryWithObjectsAndKeys:filePath,@"playPath",@"complete",@"playState",mId,@"id", nil];
        [self->_channel invokeMethod:@"onPlayState" arguments:dict3];
    };
    
    NSString *mId = [args valueForKey:@"id"];
    NSDictionary *dict3 = [NSDictionary dictionaryWithObjectsAndKeys:@"success",@"result",mId,@"id", nil];
    [_channel invokeMethod:@"onPlay" arguments:dict3];
}


@end
