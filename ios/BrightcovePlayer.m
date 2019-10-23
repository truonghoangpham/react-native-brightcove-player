#import "BrightcovePlayer.h"
#import "BrightcovePlayerOfflineVideoManager.h"

@interface BrightcovePlayer () <BCOVPlaybackControllerDelegate, BCOVPUIPlayerViewDelegate>

@end

@implementation BrightcovePlayer

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    // Set the AVAudioSession category to allow audio playback in the background
    // or when the mute button is on. Refer to the AVAudioSession Class Reference:
    // https://developer.apple.com/documentation/avfoundation/avaudiosession
    
    NSError *categoryError = nil;
    // see https://developer.apple.com/documentation/avfoundation/avaudiosessioncategoryplayback
    // and https://developer.apple.com/documentation/avfoundation/avaudiosessionmodemovieplayback
    BOOL success = [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeMoviePlayback options:AVAudioSessionCategoryOptionDuckOthers error:&categoryError];
    if (!success)
    {
        NSLog(@"AppDelegate Debug - Error setting AVAudioSession category.  Because of this, there may be no sound. `%@`", categoryError);
    }
    
    // More Info @ https://developers.google.com/cast/docs/ios_sender/integrate#initialize_the_cast_context
    GCKDiscoveryCriteria *discoveryCriteria = [[GCKDiscoveryCriteria alloc] initWithApplicationID: kGCKDefaultMediaReceiverApplicationID];//@"4F8B3483"
    GCKCastOptions *options = [[GCKCastOptions alloc] initWithDiscoveryCriteria:discoveryCriteria];
    [GCKCastContext setSharedInstanceWithOptions:options];
    
    // More Info @ https://developers.google.com/cast/docs/ios_sender/integrate#add_expanded_controller
    [GCKCastContext sharedInstance].useDefaultExpandedMediaControls = YES;
    
    // More Info @ https://developers.google.com/cast/docs/ios_sender/integrate#add_mini_controllers
    UIStoryboard *appStoryboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UINavigationController *navigationController = [appStoryboard instantiateViewControllerWithIdentifier:@"NavController"];
    GCKUICastContainerViewController *castContainerVC = [[GCKCastContext sharedInstance] createCastContainerControllerForViewController:navigationController];
    castContainerVC.miniMediaControlsItemEnabled = YES;

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = castContainerVC;
    [self.window makeKeyAndVisible];
    
    return YES;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setup];
    }
    return self;
}

- (void)setup {
    
    [BCOVGoogleCastManager sharedManager].delegate = self;

    _playbackController = [BCOVPlayerSDKManager.sharedManager createPlaybackController];
    _playbackController.delegate = self;
    _playbackController.autoPlay = NO;
    _playbackController.autoAdvance = YES;
    [_playbackController setAllowsExternalPlayback:YES];

    [self.playbackController addSessionConsumer:BCOVGoogleCastManager.sharedManager];

    _playerView = [[BCOVPUIPlayerView alloc] initWithPlaybackController:self.playbackController options:nil controlsView:[BCOVPUIBasicControlView basicControlViewWithVODLayout]];
    _playerView.delegate = self;
    _playerView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _playerView.backgroundColor = UIColor.blackColor;

    // Hide the controls until it defines which controls to use based on the READY state
    _playerView.controlsView.hidden = true;

    _targetVolume = 1.0;
    _autoPlay = NO;

    [[NSNotificationCenter defaultCenter] addObserver:self
    selector:@selector(castDeviceDidChange:)
        name:kGCKCastStateDidChangeNotification
      object:[GCKCastContext sharedInstance]];

    [self addSubview:_playerView];
}

- (void)setupService {
    if ((!_playbackService || _playbackServiceDirty) && _accountId && _policyKey) {
        _playbackServiceDirty = NO;
        _playbackService = [[BCOVPlaybackService alloc] initWithAccountId:_accountId policyKey:_policyKey];
    }
}

- (void)loadMovie {
    if (_videoToken) {
        BCOVVideo *video = [[BrightcovePlayerOfflineVideoManager sharedManager] videoObjectFromOfflineVideoToken:_videoToken];
        if (video) {
            [self.playbackController setVideos: @[ video ]];
        }
        return;
    }

    if (!_playbackService) return;

    if (_videoId) {
        [_playbackService findVideoWithVideoID:_videoId parameters:nil completion:^(BCOVVideo *video, NSDictionary *jsonResponse, NSError *error) {
            if (video) {
                _mediaInfo = jsonResponse;
                [self.playbackController setVideos: @[ video ]];
            } else {
                [self emitError:error];
            }
        }];
    } else if (_referenceId) {
        [_playbackService findVideoWithReferenceID:_referenceId parameters:nil completion:^(BCOVVideo *video, NSDictionary *jsonResponse, NSError *error) {
            if (video) {
                _mediaInfo = jsonResponse;
                [self.playbackController setVideos: @[ video ]];
            } else {
                [self emitError:error];
            }
        }];
    }
}

- (id<BCOVPlaybackController>)createPlaybackController {
    BCOVBasicSessionProviderOptions *options = [BCOVBasicSessionProviderOptions alloc];
    BCOVBasicSessionProvider *provider = [[BCOVPlayerSDKManager sharedManager] createBasicSessionProviderWithOptions:options];
    return [BCOVPlayerSDKManager.sharedManager createPlaybackControllerWithSessionProvider:provider viewStrategy:nil];
}

- (void)setReferenceId:(NSString *)referenceId {
    _referenceId = referenceId;
    _videoId = NULL;
    [self setupService];
    [self loadMovie];
}

- (void)setVideoId:(NSString *)videoId {
    _videoId = videoId;
    _referenceId = NULL;
    [self setupService];
    [self loadMovie];
}

- (void)setVideoToken:(NSString *)videoToken {
    _videoToken = videoToken;
    [self loadMovie];
}

- (void)setAccountId:(NSString *)accountId {
    _accountId = accountId;
    _playbackServiceDirty = YES;
    _playbackController.analytics.account = accountId;
    [self setupService];
    [self loadMovie];
}

- (void)setPlayerId:(NSString *)playerId {
    _playbackController.analytics.destination = [NSString stringWithFormat: @"bcsdk://%@", playerId];
    [self setupService];
    [self loadMovie];
}


- (void)setPlayerType:(NSString *)type {
    _playerType = type;
}

- (void)setPolicyKey:(NSString *)policyKey {
    _policyKey = policyKey;
    _playbackServiceDirty = YES;
    [self setupService];
    [self loadMovie];
}

- (void)setAutoPlay:(BOOL)autoPlay {
    _autoPlay = autoPlay;
}

- (void)setPlay:(BOOL)play {
    if (_playing && play) return;
    if (play) {
        [_playbackController play];
    } else {
        [_playbackController pause];
        _playing = FALSE;
    }
}

- (void)setFullscreen:(BOOL)fullscreen {
    if (fullscreen) {
        [_playerView performScreenTransitionWithScreenMode:BCOVPUIScreenModeFull];
    } else {
        [_playerView performScreenTransitionWithScreenMode:BCOVPUIScreenModeNormal];
    }
}

- (void)setVolume:(NSNumber*)volume {
    _targetVolume = volume.doubleValue;
    [self refreshVolume];
}

- (void)setBitRate:(NSNumber*)bitRate {
    _targetBitRate = bitRate.doubleValue;
    [self refreshBitRate];
}

- (void)setPlaybackRate:(NSNumber*)playbackRate {
    _targetPlaybackRate = playbackRate.doubleValue;
    if (_playing) {
        [self refreshPlaybackRate];
    }
}

- (void)refreshVolume {
    if (!_playbackSession) return;
    _playbackSession.player.volume = _targetVolume;
}

- (void)refreshBitRate {
    if (!_playbackSession) return;
    AVPlayerItem *item = _playbackSession.player.currentItem;
    if (!item) return;
    item.preferredPeakBitRate = _targetBitRate;
}

- (void)refreshPlaybackRate {
    if (!_playbackSession || !_targetPlaybackRate) return;
    _playbackSession.player.rate = _targetPlaybackRate;
}

- (void)setDisableDefaultControl:(BOOL)disable {
    _disableDefaultControl = disable;
    _playerView.controlsView.hidden = disable;
}

- (void)seekTo:(NSNumber *)time {
    [_playbackController seekToTime:CMTimeMakeWithSeconds([time floatValue], NSEC_PER_SEC) completionHandler:^(BOOL finished) {
    }];
}

#pragma mark - BCOVGoogleCastManagerDelegate

- (void)switchedToRemotePlayback
{
//    self.videoContainer.hidden = YES;
}

- (void)switchedToLocalPlayback:(NSTimeInterval)lastKnownStreamPosition withError:(NSError *)error
{
    if (lastKnownStreamPosition > 0)
    {
        [self.playbackController play];
    }
//    self.videoContainer.hidden = NO;
    
    if (error)
    {
        NSLog(@"Switched to local playback with error: %@", error.localizedDescription);
    }
}

- (void)currentCastedVideoDidComplete
{
//    self.videoContainer.hidden = YES;
}

- (void)suitableSourceNotFound
{
    NSLog(@"Suitable source for video not found!");
}

#pragma mark - BCOVPlaybackControllerDelegate
- (void)playbackController:(id<BCOVPlaybackController>)controller playbackSession:(id<BCOVPlaybackSession>)session didReceiveLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent {

    [self createAirplayIconOverlay];

    if (lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventReady) {

        if ([[_playerType uppercaseString] isEqualToString:@"LIVE"]) {
            _playerView.controlsView.layout = [BCOVPUIControlLayout basicLiveControlLayout];
        } else if ([[_playerType uppercaseString] isEqualToString:@"DVR"]) {
            _playerView.controlsView.layout = [BCOVPUIControlLayout basicLiveDVRControlLayout];
        } else {
            _playerView.controlsView.layout = [BCOVPUIControlLayout basicVODControlLayout];
        }
        // Once the controls are set to the layout, define the controls to the state sent to the player
        _playerView.controlsView.hidden = _disableDefaultControl;

        UITapGestureRecognizer *seekToTimeTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSeekToTimeTap:)];
        [_playerView.controlsView.progressSlider addGestureRecognizer:seekToTimeTap];

        _playbackSession = session;
        [self refreshVolume];
        [self refreshBitRate];

        if (self.onReady) {
            self.onReady(@{});
        }

        if (self.onMetadataLoaded) {
            NSDictionary *mediainfo = @{ @"title" : _mediaInfo[@"name"]};
            self.onMetadataLoaded(@{
                @"mediainfo": mediainfo
            });
        }
        if (_autoPlay && _playing) {
            [_playbackController play];
        }
    } else if (lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventPlay) {
        _playing = true;
        [self refreshPlaybackRate];
        if (self.onPlay) {
            self.onPlay(@{});
        }
    } else if (lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventPause) {
        if (_playing) {
            _playing = false;
            if (self.onPause) {
                self.onPause(@{});
            }

            // Hide controls view after pause a video
            [self refreshControlsView];
        }
    } else if (lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventEnd) {
        if (self.onEnd) {
            self.onEnd(@{});
        }
    }

     /**
      * The playback buffer is empty. This will occur when the video initially loads,
      * after a seek occurs, and when playback stops because of a slow or disabled
      * network. When the buffer is full enough to start playback again,
      * kBCOVPlaybackSessionLifecycleEventPlaybackLikelyToKeepUp will be sent.
      */
     if (lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventPlaybackBufferEmpty) {
        if (self.onBufferingStarted) {
            self.onBufferingStarted(@{});
        }
     }
     /**
      * After becoming empty, this event is sent when the playback buffer has filled
      * enough that it should be able to keep up with playback. This event will come after
      * kBCOVPlaybackSessionLifecycleEventPlaybackBufferEmpty.
      */
     if (lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventPlaybackLikelyToKeepUp) {
        if (self.onBufferingCompleted) {
            self.onBufferingCompleted(@{});
        }
     }
     /**
      * Playback of the video has stalled. When the video recovers,
      * kBCOVPlaybackSessionLifecycleEventPlaybackRecovered will be sent.
      */
     if (lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventPlaybackStalled) {
        if (self.onNetworkConnectivityChange) {
            self.onNetworkConnectivityChange(@{@"status": @"stalled"});
        }
     }
     /**
      * Playback has recovered after being stalled.
      */
     if (lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventPlaybackRecovered) {
        if (self.onNetworkConnectivityChange) {
            self.onNetworkConnectivityChange(@{@"status": @"recovered"});
        }
     }
     /**
      * A generic error has occurred.
      */
    if (lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventError) {
        NSError *error = lifecycleEvent.properties[@"error"];
        NSLog(@"Lifecycle Event Fail error: %@", error);
        [self emitError:error];
     /**
      * The video failed to load.
      */
    } else if (lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventFail) {
        NSError *error = lifecycleEvent.properties[@"error"];
        NSLog(@"Lifecycle Event Fail error: %@", error);
        [self emitError:error];
     /**
      * The video failed during playback and was unable to recover, possibly due to a
      * network error.
      */
    } else if (lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventFailedToPlayToEndTime) {
        NSError *error = lifecycleEvent.properties[@"error"];
        NSLog(@"Lifecycle Event Fail error: %@", error);
        [self emitError:error];
    }

}

- (void)playbackController:(id<BCOVPlaybackController>)controller playbackSession:(id<BCOVPlaybackSession>)session didChangeDuration:(NSTimeInterval)duration {
    _segmentDuration = duration;
    if (self.onChangeDuration) {
        self.onChangeDuration(@{
                                @"duration": @(duration)
                                });
    }
}

-(void)playbackController:(id<BCOVPlaybackController>)controller playbackSession:(id<BCOVPlaybackSession>)session didProgressTo:(NSTimeInterval)progress {
    NSTimeInterval duration = CMTimeGetSeconds(session.player.currentItem.duration);
    if (self.onProgress && progress > 0 && progress != INFINITY) {
        self.onProgress(@{
                          @"currentTime": @(progress),
                          @"duration": @(!isnan(duration) ? duration : -1)
                          });
    }
    float bufferProgress = _playerView.controlsView.progressSlider.bufferProgress;
    if (_lastBufferProgress != bufferProgress) {
        _lastBufferProgress = bufferProgress;
        self.onUpdateBufferProgress(@{
                                      @"bufferProgress": @(bufferProgress),
                                      @"duration": @(!isnan(duration) ? duration : -1)
                                      });
    }
}

-(void)playerView:(BCOVPUIPlayerView *)playerView willTransitionToScreenMode:(BCOVPUIScreenMode)screenMode {
    if (screenMode == BCOVPUIScreenModeNormal) {
        if (self.onBeforeExitFullscreen) {
            self.onBeforeExitFullscreen(@{});
        }
    } else if (screenMode == BCOVPUIScreenModeFull) {
        if (self.onBeforeEnterFullscreen) {
            self.onBeforeEnterFullscreen(@{});
        }
    }
}

-(void)playerView:(BCOVPUIPlayerView *)playerView didTransitionToScreenMode:(BCOVPUIScreenMode)screenMode {
    if (screenMode == BCOVPUIScreenModeNormal) {
        if (self.onExitFullscreen) {
            self.onExitFullscreen(@{});
        }
    } else if (screenMode == BCOVPUIScreenModeFull) {
        if (self.onEnterFullscreen) {
            self.onEnterFullscreen(@{});
        }
    }
}

- (void)handleSeekToTimeTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        CGPoint location = [recognizer locationInView:[recognizer.view superview]];

        double touchLocation = location.x / _playerView.controlsView.progressSlider.bounds.size.width;
        double percentage = [self calculateSeekTime:touchLocation];
        CMTime newTime = CMTimeMake(percentage * _segmentDuration, 1);

        [_playbackController seekToTime:CMTimeMakeWithSeconds(CMTimeGetSeconds(newTime), NSEC_PER_SEC) completionHandler:^(BOOL finished) {
        }];
    }
}

- (void)routePickerViewDidEndPresentingRoutes:(AVRoutePickerView *)routePickerView {
    [self createAirplayIconOverlay];
}

- (void)createAirplayIconOverlay {
    if ([self isAudioSessionUsingAirplayOutputRoute]) {
        if (![_route isDescendantOfView:_playerView.controlsContainerView]) {
            _route = [[AVRoutePickerView alloc] init];
            _route.backgroundColor = [UIColor clearColor];
            _route.tintColor = [UIColor clearColor];
            _route.activeTintColor = [UIColor colorWithWhite:1.0 alpha:1.0];
            [_route setTranslatesAutoresizingMaskIntoConstraints:NO];

            [_playerView.controlsContainerView addSubview:_route];
            [_playerView.controlsContainerView sendSubviewToBack:_route];

            NSLayoutConstraint *centreHorizontallyConstraint = [NSLayoutConstraint
                                                                constraintWithItem:_route
                                                                attribute:NSLayoutAttributeCenterX
                                                                relatedBy:NSLayoutRelationEqual
                                                                toItem:_playerView
                                                                attribute:NSLayoutAttributeCenterX
                                                                multiplier:1.0
                                                                constant:0];

            NSLayoutConstraint *centreVerticallyConstraint = [NSLayoutConstraint
                                                              constraintWithItem:_route
                                                              attribute:NSLayoutAttributeCenterY
                                                              relatedBy:NSLayoutRelationEqual
                                                              toItem:_playerView
                                                              attribute:NSLayoutAttributeCenterY
                                                              multiplier:1.0
                                                              constant:0];

            NSLayoutConstraint *widthConstraint = [NSLayoutConstraint constraintWithItem:_route
                                                                               attribute:NSLayoutAttributeWidth
                                                                               relatedBy:NSLayoutRelationEqual
                                                                                  toItem:nil
                                                                               attribute:NSLayoutAttributeNotAnAttribute
                                                                              multiplier:1.0
                                                                                constant:200];

            NSLayoutConstraint *heightConstraint = [NSLayoutConstraint constraintWithItem:_route
                                                                                attribute:NSLayoutAttributeHeight
                                                                                relatedBy:NSLayoutRelationEqual
                                                                                   toItem:nil
                                                                                attribute:NSLayoutAttributeNotAnAttribute
                                                                               multiplier:1.0
                                                                                 constant:200];

            [_playerView addConstraints:@[centreHorizontallyConstraint, centreVerticallyConstraint, widthConstraint, heightConstraint]];

            [self layoutIfNeeded];
        }
    } else {
        [_route removeFromSuperview];
    }
}

- (BOOL)isAudioSessionUsingAirplayOutputRoute {
    /**
     * I found no other way to check if there is a connection to an airplay device
     * airPlayVideoActive is NO as long as the video hasn't started
     * and this method is true as soon as the device is connected to an airplay device
     */
    AVAudioSession* audioSession = [AVAudioSession sharedInstance];
    AVAudioSessionRouteDescription* currentRoute = audioSession.currentRoute;
    for (AVAudioSessionPortDescription* outputPort in currentRoute.outputs){
        if ([outputPort.portType isEqualToString:AVAudioSessionPortAirPlay])
            return YES;
    }
    return NO;
}

- (double)calculateSeekTime:(double)percentage {
    if (percentage > 1.0) {
        percentage = 1.0;
    } else if (percentage < 0.0) {
        percentage = 0.0;
    }

    return percentage;
}

-(void)dispose {
    [self.playbackController setVideos:@[]];
}

- (void)emitError:(NSError *)error {

    if (!self.onError) {
        return;
    }

    NSString *code = [NSString stringWithFormat:@"%ld", (long)[error code]];

    self.onError(@{@"error_code": code, @"message": [error localizedDescription]});
}

- (void)refreshControlsView {
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        _playerView.controlsFadingViewVisible = !_playerView.controlsFadingViewVisible;
    });
}

#pragma mark - Misc
- (void)castDeviceDidChange:(NSNotification *)notification
{
    switch ([GCKCastContext sharedInstance].castState) {
        case GCKCastStateNoDevicesAvailable:
            NSLog(@"Cast Status: No Devices Available");
            break;
        case GCKCastStateNotConnected:
            NSLog(@"Cast Status: Not Connected");
            break;
        case GCKCastStateConnecting:
            NSLog(@"Cast Status: Connecting");
            break;
        case GCKCastStateConnected:
            NSLog(@"Cast Status: Connected");
            break;
    }
}
@end
