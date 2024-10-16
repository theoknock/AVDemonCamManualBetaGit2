/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 View controller for camera interface.
 
 Modified by James Alan Bush (The Life of a Demoniac)
 demonicactivity.blogspot.com
 
 */

@import AVFoundation;
@import Photos;
@import CoreFoundation;
@import AVKit;

#import "AVCamManualCameraViewController.h"
#import "AVCamManualPreviewView.h"
#import "AVCamManualAppDelegate.h"

#import <objc/runtime.h>
#import <objc/NSObjCRuntime.h>

static void * SessionRunningContext = &SessionRunningContext;
static void * FocusModeContext = &FocusModeContext;
static void * ExposureModeContext = &ExposureModeContext;
static void * TorchLevelContext = &TorchLevelContext;
static void * LensPositionContext = &LensPositionContext;
static void * ExposureDurationContext = &ExposureDurationContext;
static void * ISOContext = &ISOContext;
static void * ExposureTargetBiasContext = &ExposureTargetBiasContext;
static void * ExposureTargetOffsetContext = &ExposureTargetOffsetContext;
static void * VideoZoomFactorContext = &VideoZoomFactorContext;
static void * PresetsContext = &PresetsContext;

static void * DeviceWhiteBalanceGainsContext = &DeviceWhiteBalanceGainsContext;
static void * WhiteBalanceModeContext = &WhiteBalanceModeContext;

typedef NS_ENUM( NSInteger, AVCamManualSetupResult ) {
    AVCamManualSetupResultSuccess,
    AVCamManualSetupResultCameraNotAuthorized,
    AVCamManualSetupResultSessionConfigurationFailed
};

@interface AVCamManualCameraViewController () <AVCaptureFileOutputRecordingDelegate>

@property (nonatomic, weak) IBOutlet AVCamManualPreviewView *previewView;
@property (nonatomic, weak) IBOutlet UIImageView * cameraUnavailableImageView;
@property (nonatomic, weak) IBOutlet UIButton *resumeButton;
@property (nonatomic, weak) IBOutlet UIButton *recordButton;
@property (nonatomic, weak) IBOutlet UIButton *HUDButton;
@property (nonatomic, weak) IBOutlet UIView *manualHUD;
@property (nonatomic, weak) IBOutlet UIView *controlsView;

@property (nonatomic) NSArray *focusModes;
@property (nonatomic, weak) IBOutlet UIView *manualHUDFocusView;
@property (nonatomic, weak) IBOutlet UISegmentedControl *focusModeControl;
@property (nonatomic, weak) IBOutlet UISlider *lensPositionSlider;

@property (nonatomic) NSArray *exposureModes;
@property (nonatomic, weak) IBOutlet UIView *manualHUDExposureView;
@property (nonatomic, weak) IBOutlet UISegmentedControl *exposureModeControl;
@property (nonatomic, weak) IBOutlet UISlider *exposureDurationSlider;
@property (nonatomic, weak) IBOutlet UISlider *ISOSlider;

@property (weak, nonatomic) IBOutlet UIView *manualHUDVideoZoomFactorView;
@property (weak, nonatomic) IBOutlet UISlider *videoZoomFactorSlider;

@property (weak, nonatomic) IBOutlet UIView *manualHUDTorchLevelView;
@property (weak, nonatomic) IBOutlet UISlider *torchLevelSlider;

@property (strong, nonatomic) UILongPressGestureRecognizer *rescaleLensPositionSliderValueRangeGestureRecognizer;

@property (nonatomic) NSArray<NSNumber *> * whiteBalanceModes;
@property (weak, nonatomic) IBOutlet UIView *manualHUDWhiteBalanceView;
@property (weak, nonatomic) IBOutlet UISegmentedControl *whiteBalanceModeControl;
@property (weak, nonatomic) IBOutlet UISlider *temperatureSlider;
@property (weak, nonatomic) IBOutlet UISlider *tintSlider;
@property (weak, nonatomic) IBOutlet UIButton *grayWorldButton;
@property (weak, nonatomic) IBOutlet UIView *coverView;
//@property (weak, nonatomic) IBOutlet UILabel *fpsLabel;


// Session management
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic) AVCaptureDeviceDiscoverySession *videoDeviceDiscoverySession;
@property (nonatomic) AVCaptureDevice *videoDevice;
@property (nonatomic) AVCaptureConnection *videoCaptureConnection;
@property (nonatomic) AVCaptureDeviceRotationCoordinator * videoDeviceRotationCoordinator;

// Utilities
@property (nonatomic) AVCamManualSetupResult setupResult;
@property (nonatomic, getter=isSessionRunning) BOOL sessionRunning;
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;

@end

@implementation AVCamManualCameraViewController

//typedef typeof(UIView *)TouchControlView;
//static void (^position_control_using_touch_point)(UITouch *) = ^ (UITouch * touch) {
//    dispatch_async(dispatch_get_main_queue(), ^{
//        [touch.view setCenter:[touch preciseLocationInView:touch.view.superview]];
//    });
//};
//
//- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
//    UITouch * touch = event.allTouches.anyObject;// touches.anyObject;
//    if ([touch.view isKindOfClass:[UISlider class]]) {
//        position_control_using_touch_point(touch);
//    }
//}
//
//- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
//    printf("%s", __PRETTY_FUNCTION__);
//    UITouch * touch = touches.anyObject;
//    if ([touch.view isKindOfClass:[UISlider class]])
//        position_control_using_touch_point(touch);
//}
//
//- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
//    // To-Do: return slider to normal position
//    UITouch * touch = touches.anyObject;
//    if ([touch.view isKindOfClass:[UISlider class]])
//        position_control_using_touch_point(touch);
//
//}
//
//- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
//    UITouch * touch = touches.anyObject;
//    dispatch_async(dispatch_get_main_queue(), ^{
//        // To-Do: return slider to normal position
////        [touch.view setCenter:[touch precisePreviousLocationInView:touch.view.superview]];
//    });
//}
//}

static const double kVideoZoomFactorPowerCoefficient = 3.333f; // Higher numbers will give the slider more sensitivity at shorter durations
static const float kExposureDurationPower = 5.f; // Higher numbers will give the slider more sensitivity at shorter durations

#pragma mark View Controller Life Cycle

- (void)toggleControlViewVisibility:(NSArray *)views hide:(BOOL)shouldHide
{
    [views enumerateObjectsUsingBlock:^(UIView *  _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
        [view setHidden:shouldHide];
        [view setAlpha:(shouldHide) ? 0.0 : 1.0];
    }];
}


- (IBAction)toggleCoverView:(UIButton *)sender {
    [self.coverView setHidden:TRUE];
    [self.coverView setAlpha:0.0];
}

- (IBAction)toggleDisplay:(UIButton *)sender {
    [self.coverView setHidden:FALSE];
    [self.coverView setAlpha:1.0];
}

- (void)configureCameraForHighestFrameRate:(AVCaptureDevice *)device {
    AVCaptureDeviceFormat *bestFormat = nil;
    AVFrameRateRange *bestFrameRateRange = nil;
    for (AVCaptureDeviceFormat *format in device.formats) {
        for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
            if (range.maxFrameRate > bestFrameRateRange.maxFrameRate && CMFormatDescriptionGetMediaSubType(format.formatDescription) == kCVPixelFormatType_64ARGB /*kCVPixelFormatType_420YpCbCr8BiPlanarFullRange*/) {
                bestFormat = format;
                bestFrameRateRange = range;
            }
        }
    }
    if (bestFormat) {
        if ([device lockForConfiguration:nil]) {
            device.activeFormat = bestFormat;
            device.activeVideoMinFrameDuration = bestFrameRateRange.minFrameDuration;
            device.activeVideoMaxFrameDuration = bestFrameRateRange.minFrameDuration;
            [device unlockForConfiguration];
        }
    }
}

// Should be called on the session queue
//- (void)configureCameraForHighestFrameRate:(AVCaptureDevice *)device {
//    AVCaptureDeviceFormat *bestFormat = nil;
//    AVFrameRateRange *bestFrameRateRange = nil;
//    for ( AVCaptureDeviceFormat *format in [device formats] ) {
//        for ( AVFrameRateRange *range in format.videoSupportedFrameRateRanges ) {
//            if ( range.maxFrameRate > bestFrameRateRange.maxFrameRate ) {
//                bestFormat = format;
//                bestFrameRateRange = range;
//            }
//        }
//    }
//    if ( bestFormat ) {
//        if ( [device lockForConfiguration:NULL] == YES ) {
//            device.activeFormat = bestFormat;
//            device.activeVideoMinFrameDuration = bestFrameRateRange.minFrameDuration;
//            device.activeVideoMaxFrameDuration = bestFrameRateRange.maxFrameDuration;
//            [device unlockForConfiguration];
//        }
//    }
//}

//- (void)viewDidLoad
//{
//    [super viewDidLoad];
//
//    [self.recordButton setImage:[UIImage systemImageNamed:@"stop.circle"] forState:UIControlStateSelected];
//    [self.recordButton setImage:[UIImage systemImageNamed:@"record.circle"] forState:UIControlStateNormal];
//
//
//    NSArray<NSString *> *deviceTypes = @[AVCaptureDeviceTypeBuiltInWideAngleCamera];
//    self.videoDeviceDiscoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
//
//
//
//    self.sessionQueue = dispatch_queue_create( "session queue", DISPATCH_QUEUE_SERIAL );
//    self.setupResult = AVCamManualSetupResultSuccess;
//    switch ( [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] )
//    {
//        case AVAuthorizationStatusAuthorized:
//        {
//            __autoreleasing NSError *error = nil;
//            ({ [self.session = [[AVCaptureSession alloc] init] beginConfiguration];
//                {
//                    [self.session setSessionPreset:AVCaptureSessionPreset3840x2160];
//                    [self.session setAutomaticallyConfiguresCaptureDeviceForWideColor:TRUE];
//                    // set device input here (above)
//                    !(![self.session canAddInput:(self.videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:({
//                        [({
//                            [self.videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack] lockForConfiguration:&error];
//                            {
//                                @try {
//                                    !(!error) ?: ^ (NSError ** error_t) {
//                                        NSException* exception = [NSException
//                                                                  exceptionWithName:(*error_t).domain
//                                                                  reason:(*error_t).debugDescription
//                                                                  userInfo:@{@"Error Code" : @((*error_t).code)}];
//                                        @throw exception;
//                                    }(&error);
//
//                                    [self.videoDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
//                                    [self.videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
//                                    [self.videoDevice setAutomaticallyEnablesLowLightBoostWhenAvailable:self.videoDevice.isLowLightBoostSupported];
//
//                                    AVCaptureDeviceFormat *bestFormat = nil;
//                                    AVFrameRateRange *bestFrameRateRange = nil;
//                                    for (AVCaptureDeviceFormat *format in [self.videoDevice formats]) {
//                                        for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
//                                            if (range.maxFrameRate > bestFrameRateRange.maxFrameRate) {
//                                                bestFormat = format;
//                                                bestFrameRateRange = range;
//                                            }
//                                        }
//                                    }
//                                    if (bestFormat) {
//                                        self.videoDevice.activeFormat = bestFormat;
//                                        self.videoDevice.activeVideoMinFrameDuration = bestFrameRateRange.minFrameDuration;
//                                        self.videoDevice.activeVideoMaxFrameDuration = bestFrameRateRange.maxFrameDuration;
//                                    }
//                                } @catch (NSException *exception) {
//                                    NSLog(@"\n\nException configuring video device:\n\tException: %@\n\tDescription: %@\n\tError Code: %@\n",
//                                          exception.name,
//                                          exception.reason,
//                                          exception.userInfo[@"Error Code"]);
//                                }
//                            }
//                            self.videoDevice;
//                        }) unlockForConfiguration];
//                        self.videoDevice;
//                    }) error:&error])]) ?: [self.session addInput:self.videoDeviceInput];
//                    // set device output here (below)
//                } [self.session commitConfiguration];
//            });
//
//            ({ [self.videoCaptureConnection = [self.movieFileOutput = [[AVCaptureMovieFileOutput alloc] init] connectionWithMediaType:AVMediaTypeVideo] setPreferredVideoStabilizationMode:AVCaptureVideoStabilizationModeAuto];
//                if ( [self.session canAddOutput:self.movieFileOutput] ) {
//                    ({
//                        [self.session addOutput:self.movieFileOutput];
//                        self.videoCaptureConnection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
//                        self.videoCaptureConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
//                        self.videoCaptureConnection.videoRotationAngle = self.videoDeviceRotationCoordinator.videoRotationAngleForHorizonLevelPreview; // wrong -- not initialized
//
//                        dispatch_async( self.sessionQueue, ^{
//                            [self configureCameraForHighestFrameRate:self.videoDevice];
//                        });
//                    });
//                }
//            });
//
//            [self.session commitConfiguration];
//            self.previewView.session = self.session;
//
//            dispatch_async( dispatch_get_main_queue(), ^{
//                UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
//                if ( UIDeviceOrientationIsPortrait( deviceOrientation ) || UIDeviceOrientationIsLandscape( deviceOrientation ) ) {
//                    self.videoDeviceRotationCoordinator = [[AVCaptureDeviceRotationCoordinator alloc] initWithDevice:self.videoDevice previewLayer:(AVCaptureVideoPreviewLayer *)self.previewView.layer];
//                    ((AVCaptureVideoPreviewLayer *)self.previewView.layer).connection.videoRotationAngle = self.videoDeviceRotationCoordinator.videoRotationAngleForHorizonLevelPreview;
//                }
//                self.recordButton.enabled = YES;
//                self.HUDButton.enabled = YES;
//            });
//        }
//
//        case AVAuthorizationStatusNotDetermined:
//        {
//            dispatch_suspend( self.sessionQueue );
//            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^( BOOL granted ) {
//                if ( ! granted ) {
//                    self.setupResult = AVCamManualSetupResultCameraNotAuthorized;
//                }
//                dispatch_resume( self.sessionQueue );
//            }];
//            break;
//        }
//        default:
//        {
//            self.setupResult = AVCamManualSetupResultCameraNotAuthorized;
//            break;
//        }
//            break;
//    }
//}
- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Initialize session
    self.session = [[AVCaptureSession alloc] init];
    [self.session beginConfiguration];
    self.session.sessionPreset = AVCaptureSessionPreset3840x2160;
    self.session.automaticallyConfiguresCaptureDeviceForWideColor = YES;
    
    NSError *error = nil;
    
    // Add video input
    self.videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                          mediaType:AVMediaTypeVideo
                                                           position:AVCaptureDevicePositionBack];
    self.videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:self.videoDevice error:&error];
    if (!self.videoDeviceInput) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                       message:[NSString stringWithFormat:@"Error creating video device input: %@", error.localizedDescription]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];
        self.setupResult = AVCamManualSetupResultSessionConfigurationFailed;
        [self.session commitConfiguration];
        return;
    }
    if ([self.session canAddInput:self.videoDeviceInput]) {
        [self.session addInput:self.videoDeviceInput];
    } else {
        NSLog(@"Could not add video device input to the session");
        self.setupResult = AVCamManualSetupResultSessionConfigurationFailed;
        [self.session commitConfiguration];
        return;
    }
    
    // Add audio input
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
    if (!audioDeviceInput) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                       message:[NSString stringWithFormat:@"Error creating audio device input: %@", error.localizedDescription]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];
    } else if ([self.session canAddInput:audioDeviceInput]) {
        [self.session addInput:audioDeviceInput];
        
        // Configure default camera focus and exposure properties (set to manual vs. auto)
        __autoreleasing NSError *error;
        @try {
            if ([self.videoDevice lockForConfiguration:&error]) {
                [self.videoDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
                [self.videoDevice setSmoothAutoFocusEnabled:self.videoDevice.isSmoothAutoFocusSupported];
                [self.videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
                //                if ([self->_videoDevice isTorchActive])
                [self->_videoDevice setTorchMode:0];
                //                else
                //                    [_videoDevice setTorchModeOnWithLevel:AVCaptureMaxAvailableTorchLevel error:nil];
            } else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:@"Could not add video device input to the session" preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
                [alert addAction:okAction];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }
        } @catch (NSException *exception) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:@"Could not lock video device for configuration" preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
            [alert addAction:okAction];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        } @finally {
            __autoreleasing NSError *automaticallyEnablesLowLightBoostWhenAvailableError;
            [self.videoDevice lockForConfiguration:&automaticallyEnablesLowLightBoostWhenAvailableError];
            @try {
                [self.videoDevice setAutomaticallyEnablesLowLightBoostWhenAvailable:TRUE];
            } @catch (NSException *exception) {
                NSLog(@"Error enabling automatic low light boost: %@", automaticallyEnablesLowLightBoostWhenAvailableError.description);
            } @finally {
                [self.videoDevice unlockForConfiguration];
            }
        }
        
        [self configureCameraForHighestFrameRate:self.videoDevice];
        
        dispatch_async( dispatch_get_main_queue(), ^{
            UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
            if ( UIDeviceOrientationIsPortrait( deviceOrientation ) || UIDeviceOrientationIsLandscape( deviceOrientation ) ) {
                self.videoDeviceRotationCoordinator = [[AVCaptureDeviceRotationCoordinator alloc] initWithDevice:self.videoDevice previewLayer:(AVCaptureVideoPreviewLayer *)self.previewView.layer];
                ((AVCaptureVideoPreviewLayer *)self.previewView.layer).connection.videoRotationAngle = self.videoDeviceRotationCoordinator.videoRotationAngleForHorizonLevelPreview;
            }
        } );
        
    } else {
        NSLog(@"Could not add audio device input to the session");
    }
    
    // Add movie file output
    self.movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
    if ([self.session canAddOutput:self.movieFileOutput]) {
        [self.session addOutput:self.movieFileOutput];
        self.videoCaptureConnection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
        self.videoCaptureConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeCinematicExtendedEnhanced;
        
        // Insert your code here
        if ([self.movieFileOutput.availableVideoCodecTypes containsObject:AVVideoCodecTypeHEVC]) {
            [self.movieFileOutput setOutputSettings:@{ AVVideoCodecKey : AVVideoCodecTypeHEVC } forConnection:self.videoCaptureConnection];
        }
    } else {
        NSLog(@"Could not add movie file output to the session");
        self.setupResult = AVCamManualSetupResultSessionConfigurationFailed;
        [self.session commitConfiguration];
        return;
    }
    
    [self.session commitConfiguration];
    
    // Set the preview view's session
    self.previewView.session = self.session;
    
    // Start the session on the session queue
    self.sessionQueue = dispatch_queue_create( "session queue", DISPATCH_QUEUE_SERIAL );
    dispatch_async(self.sessionQueue, ^{
        [self.session startRunning];
        self.sessionRunning = self.session.isRunning;
        if (self.sessionRunning) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.recordButton.enabled = YES;
                self.HUDButton.enabled = YES;
                [self configureManualHUD];
            });
        }
        
    });
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    switch ( self.setupResult )
    {
        case AVCamManualSetupResultSuccess:
        {
            [self addObservers];
            dispatch_async( self.sessionQueue, ^{
                
                [self.session startRunning];
                self.sessionRunning = self.session.isRunning;
            });
            
            break;
        }
        case AVCamManualSetupResultCameraNotAuthorized:
        {
            dispatch_async( dispatch_get_main_queue(), ^{
                NSString *message = NSLocalizedString( @"AVCamManual doesn't have permission to use the camera, please change privacy settings", @"Alert message when the user has denied access to the camera" );
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCamManual" message:message preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"OK", @"Alert OK button" ) style:UIAlertActionStyleCancel handler:nil];
                [alertController addAction:cancelAction];
                
                UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"Settings", @"Alert button to open Settings" ) style:UIAlertActionStyleDefault handler:^( UIAlertAction *action ) {
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
                }];
                [alertController addAction:settingsAction];
                [self presentViewController:alertController animated:YES completion:nil];
            } );
            break;
        }
        case AVCamManualSetupResultSessionConfigurationFailed:
        {
            dispatch_async( dispatch_get_main_queue(), ^{
                NSString *message = NSLocalizedString( @"Unable to capture media", @"Alert message when something goes wrong during capture session configuration" );
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVDemonCamManual" message:message preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"OK", @"Alert OK button" ) style:UIAlertActionStyleCancel handler:nil];
                [alertController addAction:cancelAction];
                [self presentViewController:alertController animated:YES completion:nil];
            } );
            break;
        }
    }
}

- (void)viewDidDisappear:(BOOL)animated
{
    [self removeObservers];
    dispatch_async( self.sessionQueue, ^{
        if ( self.setupResult == AVCamManualSetupResultSuccess ) {
            [self.session stopRunning];
            
        }
    } );
    
    [super viewDidDisappear:animated];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
    
    if ( UIDeviceOrientationIsPortrait( deviceOrientation ) || UIDeviceOrientationIsLandscape( deviceOrientation ) ) {
        ((AVCaptureVideoPreviewLayer *)self.previewView.layer).connection.videoRotationAngle = self.videoDeviceRotationCoordinator.videoRotationAngleForHorizonLevelPreview;
    }
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

#pragma mark HUD

- (IBAction)longPress:(UILongPressGestureRecognizer *)sender {
    printf("longPress == %f\n", ((UISlider *)(sender.delegate)).value);
}

- (void)configureManualHUD
{
    self.focusModes = @[@(AVCaptureFocusModeContinuousAutoFocus), @(AVCaptureFocusModeLocked)];
    NSLog(@"self.videoDevice.focusMode == %ld", (long)self.videoDevice.focusMode);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.focusModeControl setSelectedSegmentIndex:0];
        [self.lensPositionSlider setEnabled:FALSE];
        
        self.lensPositionSlider.minimumValue = 0.0;
        self.lensPositionSlider.maximumValue = 1.0;
        self.lensPositionSlider.value = self.videoDevice.lensPosition;
        [self.lensPositionSlider setMinimumTrackTintColor:[UIColor systemYellowColor]];
        [self.lensPositionSlider setMaximumTrackTintColor:[UIColor systemBlueColor]];
        [self.lensPositionSlider setThumbTintColor:[UIColor whiteColor]];
        rescale_lens_position = set_lens_position_scale(0.f, 1.f, 0.f, 1.f);
        
        self.rescaleLensPositionSliderValueRangeGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self.rescaleLensPositionSliderValueRangeGestureRecognizer action:@selector(rescaleLensPositionSliderRange:)];
        [self.rescaleLensPositionSliderValueRangeGestureRecognizer setAllowableMovement:20];
        [self.rescaleLensPositionSliderValueRangeGestureRecognizer setMinimumPressDuration:(NSTimeInterval)0.5];
        [self.rescaleLensPositionSliderValueRangeGestureRecognizer setNumberOfTapsRequired:1];
        [self.rescaleLensPositionSliderValueRangeGestureRecognizer setNumberOfTouchesRequired:1];
        [self.rescaleLensPositionSliderValueRangeGestureRecognizer setDelaysTouchesBegan:FALSE];
        [self.rescaleLensPositionSliderValueRangeGestureRecognizer setDelaysTouchesEnded:FALSE];
        [self.rescaleLensPositionSliderValueRangeGestureRecognizer setCancelsTouchesInView:TRUE];
        [self.rescaleLensPositionSliderValueRangeGestureRecognizer setRequiresExclusiveTouchType:FALSE];
        [self.lensPositionSlider addGestureRecognizer:self.rescaleLensPositionSliderValueRangeGestureRecognizer];
        
        self.exposureModes = @[@(AVCaptureExposureModeContinuousAutoExposure), @(AVCaptureExposureModeCustom)];
        self.exposureModeControl.enabled = ( self.videoDevice != nil );
        [self.exposureModeControl setSelectedSegmentIndex:0];
        for ( NSNumber *mode in self.exposureModes ) {
            [self.exposureModeControl setEnabled:[self.videoDevice isExposureModeSupported:mode.intValue] forSegmentAtIndex:[self.exposureModes indexOfObject:mode]];
        }
        //        [self changeExposureMode:self.exposureModeControl.];
        
        self.exposureDurationSlider.minimumValue = 0.f;
        self.exposureDurationSlider.maximumValue = 1.f;
        double exposureDurationSeconds = CMTimeGetSeconds( self.videoDevice.exposureDuration );
        double minExposureDurationSeconds = CMTimeGetSeconds(CMTimeMakeWithSeconds((1.f / 1000.f), 1000.f*1000.f*1000.f));
        double maxExposureDurationSeconds = CMTimeGetSeconds(CMTimeMakeWithSeconds((1.f / 3.f), 1000.f*1000.f*1000.f));
        self.exposureDurationSlider.value = property_control_value(exposureDurationSeconds, minExposureDurationSeconds, maxExposureDurationSeconds, kExposureDurationPower, 0.f);
        
        self.exposureDurationSlider.enabled = ( self.videoDevice && self.videoDevice.exposureMode == AVCaptureExposureModeCustom);
        
        
        self.ISOSlider.minimumValue = 0.f; //;
        self.ISOSlider.maximumValue = 1.f; //self.videoDevice.activeFormat.maxISO;
        self.ISOSlider.value = property_control_value(self.videoDevice.ISO, self.videoDevice.activeFormat.minISO, self.videoDevice.activeFormat.maxISO, 1.f, 0.f);
        self.ISOSlider.enabled = ( self.videoDevice.exposureMode == AVCaptureExposureModeCustom );
        
        self.videoZoomFactorSlider.minimumValue = 0.0;
        self.videoZoomFactorSlider.maximumValue = 1.0;
        self.videoZoomFactorSlider.value = property_control_value(self.videoDevice.videoZoomFactor, self.videoDevice.minAvailableVideoZoomFactor, self.videoDevice.activeFormat.videoMaxZoomFactor, kVideoZoomFactorPowerCoefficient, 0.f);
        self.videoZoomFactorSlider.enabled = YES;
        
        
        
        // To-Do: Restore these for "color-contrasting" overwhite/overblack subject areas (where luminosity contrasting fails)
        
        // Manual white balance controls
        self.whiteBalanceModes = @[@(AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance), @(AVCaptureWhiteBalanceModeLocked)];
        self.whiteBalanceModeControl.enabled = (self.videoDevice != nil);
        self.whiteBalanceModeControl.selectedSegmentIndex = [self.whiteBalanceModes indexOfObject:@(self.videoDevice.whiteBalanceMode)];
        for ( NSNumber *mode in self.whiteBalanceModes ) {
            [self.whiteBalanceModeControl setEnabled:[self.videoDevice isWhiteBalanceModeSupported:mode.intValue] forSegmentAtIndex:[self.whiteBalanceModes indexOfObject:mode]];
        }
        AVCaptureWhiteBalanceGains whiteBalanceGains = self.videoDevice.deviceWhiteBalanceGains;
        AVCaptureWhiteBalanceTemperatureAndTintValues whiteBalanceTemperatureAndTint = [self.videoDevice temperatureAndTintValuesForDeviceWhiteBalanceGains:whiteBalanceGains];
        
        //            temp (yellow/blue) and tint (magenta/green)
        [self.temperatureSlider setMaximumValueImage:[UIImage systemImageNamed:@"b.circle" withConfiguration:[UIImageSymbolConfiguration configurationWithHierarchicalColor:[UIColor systemBlueColor]]]];
        [self.temperatureSlider setMinimumValueImage:[UIImage systemImageNamed:@"y.circle" withConfiguration:[UIImageSymbolConfiguration configurationWithHierarchicalColor:[UIColor systemYellowColor]]]];
        self.temperatureSlider.minimumValue = 0.f;
        self.temperatureSlider.maximumValue = 1.f;
        self.temperatureSlider.value = property_control_value(whiteBalanceTemperatureAndTint.temperature, 3000.f, 8000.f, 1.f, 0.f);
        self.temperatureSlider.enabled = ( self.videoDevice && self.videoDevice.whiteBalanceMode == AVCaptureWhiteBalanceModeLocked );
        
        [self.tintSlider setMinimumValueImage:[UIImage systemImageNamed:@"m.circle" withConfiguration:[UIImageSymbolConfiguration configurationWithHierarchicalColor:[UIColor colorWithRed:0.8470588235f green:0.06274509804f blue:0.4941176471f alpha:1.f]]]];
        [self.tintSlider setMaximumValueImage:[UIImage systemImageNamed:@"g.circle" withConfiguration:[UIImageSymbolConfiguration configurationWithHierarchicalColor:[UIColor systemGreenColor]]]];
        
        self.tintSlider.minimumValue = 0.f;
        self.tintSlider.maximumValue = 1.f;
        self.tintSlider.value = property_control_value(whiteBalanceTemperatureAndTint.tint, -150.f, 150.f, 1.f, 0.f);
        self.tintSlider.enabled = ( self.videoDevice && self.videoDevice.whiteBalanceMode == AVCaptureWhiteBalanceModeLocked );
    });
}
//        __autoreleasing NSError *error;
//        if ([self->_videoDevice lockForConfiguration:&error]) {

//            if (self.videoDevice.focusMode == AVCaptureFocusModeLocked) {
//                [self.focusModeControl setSelectedSegmentIndex:1];
//            } else if (self.videoDevice.focusMode == AVCaptureFocusModeContinuousAutoFocus) {
//                [self.focusModeControl setSelectedSegmentIndex:0];
//            }
//



//        } else {
//            NSLog(@"AVCaptureDevice lockForConfiguration returned error\t%@", error);
//        }
//        [self->_videoDevice unlockForConfiguration];
//    });
//    }

//- (IBAction)toggleTorch:(id)sender
//{
//    NSLog(@"%s", __PRETTY_FUNCTION__);
//    dispatch_async(dispatch_get_main_queue(), ^{
//        __autoreleasing NSError *error;
//        if ([_videoDevice lockForConfiguration:&error]) {
//            if ([_videoDevice isTorchActive])
//                [_videoDevice setTorchMode:0];
//            else
//                [_videoDevice setTorchModeOnWithLevel:AVCaptureMaxAvailableTorchLevel error:nil];
//        } else {
//            NSLog(@"AVCaptureDevice lockForConfiguration returned error\t%@", error);
//        }
//        [_videoDevice unlockForConfiguration];
//    });
//}

- (IBAction)toggleHUD:(UIButton *)sender
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [sender setSelected:self.manualHUD.hidden = !self.manualHUD.hidden];
        [sender setHighlighted:!self.manualHUD.hidden];
    });
}

- (IBAction)changeManualHUDSelection:(UISegmentedControl *)sender {
    for (UIView * view in self.controlsView.subviews) {
        BOOL shouldHide = (view.tag == sender.selectedSegmentIndex) ? !view.hidden : TRUE;
        view.hidden = shouldHide;
        [view setAlpha:!shouldHide];
    };
    
    //    switch (sender.selectedSegmentIndex) {
    //        case 0:
    //            self.manualHUDTorchLevelView.hidden = !self.manualHUDTorchLevelView.hidden;
    //            break;
    //        case 1:
    //            self.manualHUDTorchLevelView.hidden = !self.manualHUDTorchLevelView.hidden;
    //            break;
    //        case 2:
    //            self.manualHUDFocusView.hidden = !self.manualHUDFocusView.hidden;
    //            break;
    //        case 3:
    //            self.manualHUDExposureView.hidden = !self.manualHUDExposureView.hidden;
    //            break;
    //        case 4:
    //            self.manualHUDVideoZoomFactorView.hidden = !self.manualHUDVideoZoomFactorView.hidden;
    //            break;
    //        case 5:
    //            self.manualHUDWhiteBalanceView.hidden = !self.manualHUDWhiteBalanceView.hidden;
    //            break;
    //
    //        default:
    //            self.manualHUD.hidden = !self.manualHUD.hidden;
    //    }
}

#pragma mark Session Management

//- (void)configureSession
//{
//    if ( self.setupResult != AVCamManualSetupResultSuccess ) {
//        return;
//    }
//
//    __autoreleasing NSError *error = nil;
//
//    [self.session beginConfiguration];
//
//    self.session.sessionPreset = AVCaptureSessionPreset3840x2160;
//    [self.session setAutomaticallyConfiguresCaptureDeviceForWideColor:TRUE];
//
//    // Add video input
//    self.videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
//    self.videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:self.videoDevice error:&error];
//
//    if (![self.session canAddInput:self.videoDeviceInput]) {
//        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
//                                                                       message:@"Could not add video device input to the session"
//                                                                preferredStyle:UIAlertControllerStyleAlert];
//        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
//        [alert addAction:okAction];
//        [self presentViewController:alert animated:YES completion:nil];
//
//        self.setupResult = AVCamManualSetupResultSessionConfigurationFailed;
//        [self.session commitConfiguration];
//        return;
//    }
//
//    if ( [self.session canAddInput:self.videoDeviceInput] ) {
//        [self.session addInput:self.videoDeviceInput];
//
//        // Configure default camera focus and exposure properties (set to manual vs. auto)
//        __autoreleasing NSError *error;
//        [self.videoDevice lockForConfiguration:&error];
//        @try {
//            [self.videoDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
//            [self.videoDevice setSmoothAutoFocusEnabled:self.videoDevice.isSmoothAutoFocusSupported];
//            [self.videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
//        } @catch (NSException *exception) {
//            NSLog(@"Error setting focus mode: %@", error.description);
//        } @finally {
//            [self.videoDevice unlockForConfiguration];
//        }
//
//        //  Enable low-light boost
//        __autoreleasing NSError *automaticallyEnablesLowLightBoostWhenAvailableError;
//        [self.videoDevice lockForConfiguration:&automaticallyEnablesLowLightBoostWhenAvailableError];
//        @try {
//            [self.videoDevice setAutomaticallyEnablesLowLightBoostWhenAvailable:TRUE];
//        } @catch (NSException *exception) {
//            NSLog(@"Error enabling automatic low light boost: %@", automaticallyEnablesLowLightBoostWhenAvailableError.description);
//        } @finally {
//            [self.videoDevice unlockForConfiguration];
//        }
//
//        [self configureCameraForHighestFrameRate:self.videoDevice];
//
//        dispatch_async( dispatch_get_main_queue(), ^{
//            UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
//            if ( UIDeviceOrientationIsPortrait( deviceOrientation ) || UIDeviceOrientationIsLandscape( deviceOrientation ) ) {
//                self.videoDeviceRotationCoordinator = [[AVCaptureDeviceRotationCoordinator alloc] initWithDevice:self.videoDevice previewLayer:(AVCaptureVideoPreviewLayer *)self.previewView.layer];
//                ((AVCaptureVideoPreviewLayer *)self.previewView.layer).connection.videoRotationAngle = self.videoDeviceRotationCoordinator.videoRotationAngleForHorizonLevelPreview;
//            }
//        } );
//
//
//
//
//    }
//    else {
//        NSLog( @"Could not add video device input to the session" );
//        self.setupResult = AVCamManualSetupResultSessionConfigurationFailed;
//        [self.session commitConfiguration];
//        return;
//    }
//
//    // Add audio input
//    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
//    AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
//    if ( ! audioDeviceInput ) {
//        NSLog( @"Could not create audio device input: %@", error );
//    }
//    if ( [self.session canAddInput:audioDeviceInput] ) {
//        [self.session addInput:audioDeviceInput];
//    }
//    else {
//        NSLog( @"Could not add audio device input to the session" );
//    }
//
//
//    // We will not create an AVCaptureMovieFileOutput when configuring the session because the AVCaptureMovieFileOutput does not support movie recording with AVCaptureSessionPresetPhoto
//    self.backgroundRecordingID = UIBackgroundTaskInvalid;
//
//    [self.session commitConfiguration];
//
//    dispatch_async( dispatch_get_main_queue(), ^{
//        [self configureManualHUD];
//    } );
//}

- (IBAction)resumeInterruptedSession:(id)sender
{
    dispatch_async( self.sessionQueue, ^{
        [self.session startRunning];
        self.sessionRunning = self.session.isRunning;
        if ( ! self.session.isRunning ) {
            dispatch_async( dispatch_get_main_queue(), ^{
                NSString *message = NSLocalizedString( @"Unable to resume", @"Alert message when unable to resume the session running" );
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCamManual" message:message preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"OK", @"Alert OK button" ) style:UIAlertActionStyleCancel handler:nil];
                [alertController addAction:cancelAction];
                [self presentViewController:alertController animated:YES completion:nil];
            } );
        }
        else {
            dispatch_async( dispatch_get_main_queue(), ^{
                self.resumeButton.hidden = YES;
            } );
        }
    } );
}

#pragma mark Device Configuration

//- (void)changeCameraWithDevice:(AVCaptureDevice *)newVideoDevice
//{
//    // Check if device changed
//    if ( newVideoDevice == self.videoDevice ) {
//        return;
//    }
//
//    self.manualHUD.userInteractionEnabled = NO;
//    //	self.cameraButton.enabled = NO;
//    self.recordButton.enabled = NO;
//    //	self.photoButton.enabled = NO;
//    //	self.captureModeControl.enabled = NO;
//    //    self.HUDButton.enabled = NO;
//
//    dispatch_async( self.sessionQueue, ^{
//        AVCaptureDeviceInput *newVideoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:newVideoDevice error:nil];
//
//        [self.session beginConfiguration];
//
//        // Remove the existing device input first, since using the front and back camera simultaneously is not supported
//        [self.session removeInput:self.videoDeviceInput];
//        if ( [self.session canAddInput:newVideoDeviceInput] ) {
//            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.videoDevice];
//
//            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:newVideoDevice];
//
//            [self.session addInput:newVideoDeviceInput];
//            self.videoDeviceInput = newVideoDeviceInput;
//            self.videoDevice = newVideoDevice;
//        }
//        else {
//            [self.session addInput:self.videoDeviceInput];
//        }
//
//        AVCaptureConnection *connection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
////        if ( connection.isVideoStabilizationSupported ) {
//            connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeCinematicExtended;
//        printf("connection.activeVideoStabilizationMode == %ld", (long)connection.activeVideoStabilizationMode);
////        }
//
//        [self.session commitConfiguration];
//
//        dispatch_async( dispatch_get_main_queue(), ^{
//            [self configureManualHUD];
//
//            //			self.cameraButton.enabled = YES;
//            self.recordButton.enabled = YES;
//            //			self.photoButton.enabled = YES;
//            //			self.captureModeControl.enabled = YES;
//            self.HUDButton.enabled = YES;
//            self.manualHUD.userInteractionEnabled = YES;
//        } );
//    } );
//}

//- (void)lockFocusModeConfiguration {
//    NSLog(@"lockFocusModeConfiguration");
//    NSLog(@"self.videoDevice.focusMode == %ld", (long)self.videoDevice.focusMode);
//    dispatch_async(self.sessionQueue, ^{
//        NSError *error = nil;
//        if ([self.videoDevice lockForConfiguration:&error]) {
//            dispatch_async(dispatch_get_main_queue(), ^{
//                [self.lensPositionSlider setEnabled:self.videoDevice.focusMode == AVCaptureFocusModeLocked];
//            });
//        } else {
//            dispatch_async(dispatch_get_main_queue(), ^{
//                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
//                                                                               message:[NSString stringWithFormat:@"Could not lock device for configuration: %@", error.localizedDescription]
//                                                                        preferredStyle:UIAlertControllerStyleAlert];
//                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
//                [alert addAction:okAction];
//                [self presentViewController:alert animated:YES completion:nil];
//            });
//        }
//    });
//}

- (IBAction)lockFocusModeConfiguration:(UISegmentedControl *)sender {
    NSLog(@"lockFocusModeConfiguration");

    dispatch_async(self.sessionQueue, ^{
        __autoreleasing NSError *error = nil;
        if ([self.videoDevice lockForConfiguration:&error]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.lensPositionSlider setEnabled:(self.videoDevice.focusMode == AVCaptureFocusModeLocked)];
            });
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                           message:[NSString stringWithFormat:@"Could not lock device for configuration: %@", error.localizedDescription]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
            [alert addAction:okAction];
            [self presentViewController:alert animated:YES completion:nil];
        }
    });
}


- (IBAction)changeFocusMode:(UISegmentedControl *)sender
{
    NSInteger position = self.lensPositionSlider.value;
    BOOL selected = [self.focusModeControl selectedSegmentIndex] == 0;
    dispatch_async(self.sessionQueue, ^{
        NSLog(@"changeFocusMode");
        NSLog(@"self.videoDevice.focusMode == %ld", (long)self.videoDevice.focusMode);
        
        AVCaptureFocusMode mode = (AVCaptureFocusMode)self.videoDevice.focusMode;
        if (mode == AVCaptureFocusModeLocked) {
            [self.videoDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
//            dispatch_async(dispatch_get_main_queue(), ^{
//                [sender setSelectedSegmentIndex:0];
//            });
        } else if (mode == AVCaptureFocusModeContinuousAutoFocus) {
            [self.videoDevice setFocusModeLockedWithLensPosition:position completionHandler:nil];
//            dispatch_async(dispatch_get_main_queue(), ^{
//                [sender setSelectedSegmentIndex:1];
//            });
        }
        NSLog(@"NEW self.videoDevice.focusMode == %ld", (long)self.videoDevice.focusMode);
        //        }
        //        else {
        //            NSLog( @"Focus mode %@ is not supported. Focus mode is %@.", [self stringFromFocusMode:mode], [self stringFromFocusMode:self.videoDevice.focusMode] );
        //            self.focusModeControl.selectedSegmentIndex = [self.focusModes indexOfObject:@(self.videoDevice.focusMode)];
        //        }
    });
}

- (IBAction)unlockFocusModeConfiguration:(UISegmentedControl *)sender {
        NSLog(@"unlockFocusModeConfiguration");
    
        dispatch_async(self.sessionQueue, ^{
            [self.videoDevice unlockForConfiguration];
        });
}


//- (void)unlockFocusModeConfiguration {
//    NSLog(@"unlockFocusModeConfiguration");
//    
//    dispatch_async(self.sessionQueue, ^{
//        [self.videoDevice unlockForConfiguration];
//    });
//}


#pragma mark Lens Position Configuration

- (IBAction)lockLensPositionConfiguration:(UISlider *)sender {
    dispatch_async(self.sessionQueue, ^{
        __autoreleasing NSError *error = nil;
        if ([self.videoDevice lockForConfiguration:&error]) {
            // Empty block—no action taken when the lock is successful.
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                           message:[NSString stringWithFormat:@"Could not lock device for configuration: %@", error.localizedDescription]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
            [alert addAction:okAction];
            [self presentViewController:alert animated:YES completion:nil];
        }
    });
}

- (IBAction)changeLensPosition:(UISlider *)sender {
    float value = sender.value;
    dispatch_async( self.sessionQueue, ^{
        [self.videoDevice setFocusModeLockedWithLensPosition:value completionHandler:nil];
    });
}

- (IBAction)unlockLensPositionConfiguration:(UISlider *)sender {
    dispatch_async(self.sessionQueue, ^{
        [self.videoDevice unlockForConfiguration];
    });
}

- (IBAction)rescaleLensPositionSliderRange:(UILongPressGestureRecognizer *)sender {
    printf("\nrescaled_value %f to %f\n", (self.lensPositionSlider.value), property_control_value(self.lensPositionSlider.value, 0.f, 1.f, 1.f, 0.f));
    rescale_lens_position = set_lens_position_scale(0.f, 1.f, self.lensPositionSlider.value - 0.10, self.lensPositionSlider.value + 0.10);
}

- (IBAction)magnifyLensPositionSlider:(UISlider *)sender forEvent:(UIEvent *)event {
    printf("%s\n", __PRETTY_FUNCTION__);
    // set new colors
    //    [sender setMinimumTrackTintColor:[UIColor systemOrangeColor]];
    //    [sender setMaximumTrackTintColor:[UIColor systemIndigoColor]];
    //    [sender setThumbTintColor:[UIColor systemGrayColor]];
    [sender setBackgroundColor:[UIColor colorWithWhite:1.f alpha:0.15f]];
    
    rescale_lens_position = set_lens_position_scale(0.f, 1.f, (sender.value - 0.10), (sender.value + 0.15));
}

- (IBAction)restoreLensSlider:(UISlider *)sender forEvent:(UIEvent *)event {
    [self restoreLensSlider_:sender forEvent:event];
}

- (IBAction)restoreLensSlider_:(UISlider *)sender forEvent:(UIEvent *)event {
    printf("%s\n", __PRETTY_FUNCTION__);
    // restore original colors
    //    [sender setMinimumTrackTintColor:[UIColor systemYellowColor]];
    //    [sender setMaximumTrackTintColor:[UIColor systemBlueColor]];
    //    [sender setThumbTintColor:[UIColor whiteColor]];
    [sender setBackgroundColor:[UIColor colorWithWhite:1.f alpha:0.f]];
    
    rescale_lens_position = set_lens_position_scale(0.f, 1.f, 0.f, 1.f);
}

- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange
{
    dispatch_async( self.sessionQueue, ^{
        AVCaptureDevice *device = self.videoDevice;
        NSError *error = nil;
        if ( [device lockForConfiguration:&error] ) {
            if ( focusMode != AVCaptureFocusModeLocked && device.isFocusPointOfInterestSupported && [device isFocusModeSupported:focusMode] ) {
                device.focusPointOfInterest = point;
                device.focusMode = focusMode;
            }
            
            if ( exposureMode != AVCaptureExposureModeCustom && device.isExposurePointOfInterestSupported && [device isExposureModeSupported:exposureMode] ) {
                device.exposurePointOfInterest = point;
                device.exposureMode = exposureMode;
            }
            
            device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange;
            [device unlockForConfiguration];
        }
        else {
            if (![self.videoDevice lockForConfiguration:&error]) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:[NSString stringWithFormat:@"Could not lock device for configuration: %@", error.localizedDescription]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
                [alert addAction:okAction];
                [self presentViewController:alert animated:YES completion:nil];
            }
        }
    } );
}



- (IBAction)changeExposureMode:(id)sender
{
    UISegmentedControl *control = sender;
    AVCaptureExposureMode mode = (AVCaptureExposureMode)[self.exposureModes[control.selectedSegmentIndex] intValue];
    self.exposureDurationSlider.enabled = ( mode == AVCaptureExposureModeCustom );
    self.ISOSlider.enabled = ( mode == AVCaptureExposureModeCustom );
    NSError *error = nil;
    
    if ( [self.videoDevice lockForConfiguration:&error] ) {
        if ( [self.videoDevice isExposureModeSupported:mode] ) {
            self.videoDevice.exposureMode = mode;
        }
        else {
            NSLog( @"Exposure mode %@ is not supported. Exposure mode is %@.", [self stringFromExposureMode:mode], [self stringFromExposureMode:self.videoDevice.exposureMode] );
            self.exposureModeControl.selectedSegmentIndex = [self.exposureModes indexOfObject:@(self.videoDevice.exposureMode)];
        }
        [self.videoDevice unlockForConfiguration];
    }
    else {
        if (![self.videoDevice lockForConfiguration:&error]) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                           message:[NSString stringWithFormat:@"Could not lock device for configuration: %@", error.localizedDescription]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
            [alert addAction:okAction];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

#pragma mark Exposure Duration Configuration

- (IBAction)lockExposureDurationConfiguration:(UISlider *)sender {
    dispatch_async(self.sessionQueue, ^{
        __autoreleasing NSError *error = nil;
        if ([self.videoDevice lockForConfiguration:&error]) {
            
        } else {
            if (![self.videoDevice lockForConfiguration:&error]) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:[NSString stringWithFormat:@"Could not lock device for configuration: %@", error.localizedDescription]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
                [alert addAction:okAction];
                [self presentViewController:alert animated:YES completion:nil];
            }
        }
    });
}

- (IBAction)changeExposureDuration:(UISlider *)sender {
    double minExposureDurationSeconds = CMTimeGetSeconds(CMTimeMakeWithSeconds((1.f / 1000.f), 1000*1000*1000));
    double maxExposureDurationSeconds = CMTimeGetSeconds(CMTimeMakeWithSeconds((1.f / 3.f), 1000*1000*1000));
    double exposureDurationSeconds = control_property_value(sender.value, minExposureDurationSeconds, maxExposureDurationSeconds, kExposureDurationPower, 0.f);
    
    dispatch_async(self.sessionQueue, ^{
        [self.videoDevice setExposureModeCustomWithDuration:CMTimeMakeWithSeconds( exposureDurationSeconds, 1000*1000*1000 )  ISO:AVCaptureISOCurrent completionHandler:nil];
    });
}

- (IBAction)unlockExposureDurationConfiguration:(UISlider *)sender {
    dispatch_async(self.sessionQueue, ^{
        [self.videoDevice unlockForConfiguration];
    });
}



#pragma mark Torch Level Configuration

- (IBAction)lockTorchLevelConfiguration:(UISlider *)sender {
    dispatch_async(self.sessionQueue, ^{
        __autoreleasing NSError *error = nil;
        if ([self.videoDevice lockForConfiguration:&error]) {
            
        } else {
            if (![self.videoDevice lockForConfiguration:&error]) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:[NSString stringWithFormat:@"Could not lock device for configuration: %@", error.localizedDescription]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
                [alert addAction:okAction];
                [self presentViewController:alert animated:YES completion:nil];
            }
        }
    });
}

- (IBAction)changeTorchLevel:(UISlider *)sender {
    
    ^ (NSError ** error){
        NSError * outError = *error;
        ((((([[NSProcessInfo processInfo] thermalState] != NSProcessInfoThermalStateCritical || [[NSProcessInfo processInfo] thermalState] != NSProcessInfoThermalStateSerious)) && !outError)
          && ^ unsigned long {
            if (sender.value != 0)
                [self->_videoDevice setTorchModeOnWithLevel:sender.value error:nil];
            else
                [self->_videoDevice setTorchMode:AVCaptureTorchModeOff];
            return 1UL;
        }())
         || ^ unsigned long {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Warning"
                                                                           message:[NSString stringWithFormat:@"Unable to adjust torch level; thermal state: %lu", (unsigned long)[[NSProcessInfo processInfo] thermalState]]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
            [alert addAction:okAction];
            [self presentViewController:alert animated:YES completion:nil];
            @throw [NSException exceptionWithName:outError.domain reason:outError.localizedFailureReason userInfo:@{@"Error Code" : @(outError.code)}]; return 1UL; }());
    }(({ __autoreleasing NSError * error = nil; &error; }));
    
    
    
//    __autoreleasing NSError *error;
//    if ([[NSProcessInfo processInfo] thermalState] != NSProcessInfoThermalStateCritical || [[NSProcessInfo processInfo] thermalState] != NSProcessInfoThermalStateSerious) {
//        if (sender.value != 0)
//            [self->_videoDevice setTorchModeOnWithLevel:sender.value error:&error];
//        else
//            [self->_videoDevice setTorchMode:AVCaptureTorchModeOff];
//    } else {
//        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Warning"
//                                                                       message:[NSString stringWithFormat:@"Unable to adjust torch level; thermal state: %lu", (unsigned long)[[NSProcessInfo processInfo] thermalState]]
//                                                                preferredStyle:UIAlertControllerStyleAlert];
//        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
//        [alert addAction:okAction];
//        [self presentViewController:alert animated:YES completion:nil];
//    }
}

- (IBAction)unlockTorchLevelConfiguration:(UISlider *)sender {
    dispatch_async(self.sessionQueue, ^{
        [self.videoDevice unlockForConfiguration];
    });
}

- (IBAction)lockISOConfiguration:(UISlider *)sender {
    dispatch_async(self.sessionQueue, ^{
        __autoreleasing NSError *error = nil;
        if ([self.videoDevice lockForConfiguration:&error]) {
            
        } else {
            if (![self.videoDevice lockForConfiguration:&error]) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:[NSString stringWithFormat:@"Could not lock device for ISO configuration: %@", error.localizedDescription]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
                [alert addAction:okAction];
                [self presentViewController:alert animated:YES completion:nil];
            }
        }
    });
}

- (IBAction)changeISO:(UISlider *)sender
{
    NSError *error = nil;
    @try {
        [self.videoDevice setExposureModeCustomWithDuration:AVCaptureExposureDurationCurrent ISO:control_property_value(sender.value, self.videoDevice.activeFormat.minISO, self.videoDevice.activeFormat.maxISO, 1.f, 0.f) completionHandler:nil];
    } @catch (NSException *exception) {
        [self.videoDevice setExposureModeCustomWithDuration:AVCaptureExposureDurationCurrent ISO:AVCaptureISOCurrent completionHandler:^(CMTime syncTime) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:[NSString stringWithFormat:@"Could not lock device for configuration: %@", error.localizedDescription]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
                [alert addAction:okAction];
                [(AVCamManualCameraViewController *)(alert.parentViewController) presentViewController:alert animated:YES completion:nil];
            });
        }];
    }
    
}

- (IBAction)unlockISOConfiguration:(UISlider *)sender {
    dispatch_async(self.sessionQueue, ^{
        [self.videoDevice unlockForConfiguration];
    });
}


- (IBAction)lockVideoZoomFactorConfiguration:(UISlider *)sender {
    dispatch_async(self.sessionQueue, ^{
        __autoreleasing NSError *error = nil;
        if ([self.videoDevice lockForConfiguration:&error]) {
            
        } else {
            if (![self.videoDevice lockForConfiguration:&error]) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:[NSString stringWithFormat:@"Could not lock device for configuration: %@", error.localizedDescription]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
                [alert addAction:okAction];
                [self presentViewController:alert animated:YES completion:nil];
            }
        }
    });
}


- (IBAction)changeVideoZoomFactor:(UISlider *)sender {
    dispatch_async(self.sessionQueue, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            ^ (NSError * error){
                ((((![self.videoDevice isRampingVideoZoom] && (sender.value != self.videoDevice.videoZoomFactor)) && !error)
                  && ^ unsigned long { [self.videoDevice setVideoZoomFactor:control_property_value(sender.value, self.videoDevice.minAvailableVideoZoomFactor, self.videoDevice.activeFormat.videoMaxZoomFactor, kVideoZoomFactorPowerCoefficient, 0.f)]; return 1UL; }())
                 || ^ unsigned long { @throw [NSException exceptionWithName:error.domain reason:error.localizedFailureReason userInfo:@{@"Error Code" : @(error.code)}]; return 1UL; }());
            }(({ NSError *error = nil; error; }));
        });
    });
}

- (IBAction)unlockVideoZoomFactorConfiguration:(UISlider *)sender {
    dispatch_async(self.sessionQueue, ^{
        [self.videoDevice unlockForConfiguration];
    });
}

- (IBAction)lockWhiteBalanceModeConfiguration:(UISegmentedControl *)sender {
    dispatch_async(self.sessionQueue, ^{
        __autoreleasing NSError *error = nil;
        if ([self.videoDevice lockForConfiguration:&error]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.temperatureSlider setEnabled:self.whiteBalanceModeControl.selectedSegmentIndex == 1];
                [self.tintSlider setEnabled:self.whiteBalanceModeControl.selectedSegmentIndex == 1];
            });
            } else {
            if (![self.videoDevice lockForConfiguration:&error]) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:[NSString stringWithFormat:@"Could not lock device for configuration: %@", error.localizedDescription]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
                [alert addAction:okAction];
                [self presentViewController:alert animated:YES completion:nil];
            }
        }
    });
}

- (IBAction)changeWhiteBalanceMode:(UISegmentedControl *)sender {
    AVCaptureWhiteBalanceMode mode = (AVCaptureWhiteBalanceMode)(self.whiteBalanceModes[sender.selectedSegmentIndex]).integerValue;
   
    if ( [self.videoDevice isWhiteBalanceModeSupported:mode] ) {
        self.videoDevice.whiteBalanceMode = mode;
    }
    else {
        NSLog( @"White balance mode %@ is not supported. White balance mode is %@.", [self stringFromWhiteBalanceMode:mode], [self stringFromWhiteBalanceMode:self.videoDevice.whiteBalanceMode] );
        self.whiteBalanceModeControl.selectedSegmentIndex = [self.whiteBalanceModes indexOfObject:@(self.videoDevice.whiteBalanceMode)];
    }
}


//- (IBAction)changeWhiteBalanceMode:(id)sender
//{
//    UISegmentedControl *control = sender;
//    AVCaptureWhiteBalanceMode mode = (AVCaptureWhiteBalanceMode)[self.whiteBalanceModes[control.selectedSegmentIndex] intValue];
//    NSError *error = nil;
//    
////    if ( [self.videoDevice lockForConfiguration:&error] ) {
//        if ( [self.videoDevice isWhiteBalanceModeSupported:mode] ) {
//            self.videoDevice.whiteBalanceMode = mode;
//        }
//        else {
//            NSLog( @"White balance mode %@ is not supported. White balance mode is %@.", [self stringFromWhiteBalanceMode:mode], [self stringFromWhiteBalanceMode:self.videoDevice.whiteBalanceMode] );
//            self.whiteBalanceModeControl.selectedSegmentIndex = [self.whiteBalanceModes indexOfObject:@(self.videoDevice.whiteBalanceMode)];
//        }
////        [self.videoDevice unlockForConfiguration];
//    }
//    else {
//        if (![self.videoDevice lockForConfiguration:&error]) {
//            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
//                                                                           message:[NSString stringWithFormat:@"Could not lock device for configuration: %@", error.localizedDescription]
//                                                                    preferredStyle:UIAlertControllerStyleAlert];
//            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
//            [alert addAction:okAction];
//            [self presentViewController:alert animated:YES completion:nil];
//        }
//    }
//}

- (IBAction)unlockWhiteBalanceModeConfiguration:(UISegmentedControl *)sender {
    dispatch_async(self.sessionQueue, ^{
        [self.videoDevice unlockForConfiguration];
    });
}


- (IBAction)lockWhiteBalanceGainsConfiguration:(UISlider *)sender {
    dispatch_async(self.sessionQueue, ^{
        __autoreleasing NSError *error = nil;
        if ([self.videoDevice lockForConfiguration:&error]) {
//            [self.temperatureSlider setEnabled:self.whiteBalanceModeControl.selectedSegmentIndex == 1];
//            [self.tintSlider setEnabled:self.whiteBalanceModeControl.selectedSegmentIndex == 0];
        } else {
            if (![self.videoDevice lockForConfiguration:&error]) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:[NSString stringWithFormat:@"Could not lock device for configuration: %@", error.localizedDescription]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
                [alert addAction:okAction];
                [self presentViewController:alert animated:YES completion:nil];
            }
        }
    });
}

- (void)setWhiteBalanceGains:(AVCaptureWhiteBalanceGains)gains
{
    //    NSError *error = nil;
    //
    //    if ( [self.videoDevice lockForConfiguration:&error] ) {
    AVCaptureWhiteBalanceGains normalizedGains = [self normalizedGains:gains]; // Conversion can yield out-of-bound values, cap to limits
    [self.videoDevice setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:normalizedGains completionHandler:nil];
    //        [self.videoDevice unlockForConfiguration];
    //    }
    //    else {
    //        if (![self.videoDevice lockForConfiguration:&error]) {
    //            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
    //                                                                           message:[NSString stringWithFormat:@"Could not lock device for configuration: %@", error.localizedDescription]
    //                                                                    preferredStyle:UIAlertControllerStyleAlert];
    //            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    //            [alert addAction:okAction];
    //            [self presentViewController:alert animated:YES completion:nil];
    //        }
    //    }
}

- (IBAction)changeTemperature:(id)sender
{
    AVCaptureWhiteBalanceTemperatureAndTintValues temperatureAndTint = {
        .temperature = control_property_value(self.temperatureSlider.value, 3000.f, 8000.f, 1.f, 0.f),
        .tint = control_property_value(self.tintSlider.value, -150.f, 150.f, 1.f, 0.f)
    };
    
    [self setWhiteBalanceGains:[self.videoDevice deviceWhiteBalanceGainsForTemperatureAndTintValues:temperatureAndTint]];
}

- (IBAction)changeTint:(id)sender
{
    AVCaptureWhiteBalanceTemperatureAndTintValues temperatureAndTint = {
        .temperature = control_property_value(self.temperatureSlider.value, 3000.f, 8000.f, 1.f, 0.f),
        .tint = control_property_value(self.tintSlider.value, -150.f, 150.f, 1.f, 0.f)
    };
    
    [self setWhiteBalanceGains:[self.videoDevice deviceWhiteBalanceGainsForTemperatureAndTintValues:temperatureAndTint]];
}

- (IBAction)lockWithGrayWorld:(id)sender
{
    [self lockWhiteBalanceGainsConfiguration:sender];
    
    [self setWhiteBalanceGains:self.videoDevice.grayWorldDeviceWhiteBalanceGains];
    
    AVCaptureWhiteBalanceTemperatureAndTintValues whiteBalanceTemperatureAndTint = [self.videoDevice temperatureAndTintValuesForDeviceWhiteBalanceGains:self.videoDevice.deviceWhiteBalanceGains];
    self.tintSlider.value = property_control_value(whiteBalanceTemperatureAndTint.tint, -150.f, 150.f, 1.f, 0.f);
    self.temperatureSlider.value = property_control_value(whiteBalanceTemperatureAndTint.temperature, 3000.f, 8000.f, 1.f, 0.f);
    
    [self unlockWhiteBalanceGainsConfiguration:sender];
}

- (IBAction)unlockWhiteBalanceGainsConfiguration:(UISlider *)sender {
    dispatch_async(self.sessionQueue, ^{
        [self.videoDevice unlockForConfiguration];
    });
}

- (AVCaptureWhiteBalanceGains)normalizedGains:(AVCaptureWhiteBalanceGains)gains
{
    AVCaptureWhiteBalanceGains g = gains;
    
    g.redGain = MAX( 1.0, g.redGain );
    g.greenGain = MAX( 1.0, g.greenGain );
    g.blueGain = MAX( 1.0, g.blueGain );
    
    g.redGain = MIN( self.videoDevice.maxWhiteBalanceGain, g.redGain );
    g.greenGain = MIN( self.videoDevice.maxWhiteBalanceGain, g.greenGain );
    g.blueGain = MIN( self.videoDevice.maxWhiteBalanceGain, g.blueGain );
    
    return g;
}

#pragma mark Recording Movies

//- (IBAction)toggleMovieRecording:(UIButton *)sender
//{
//    //    AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.previewView.layer;
//    //    AVCaptureDeviceRotationCoordinator * rotation_coord = [[AVCaptureDeviceRotationCoordinator alloc] initWithDevice:_videoDevice previewLayer:previewLayer];
//    //    previewLayer.connection.videoRotationAngle = rotation_coord.videoRotationAngleForHorizonLevelPreview;
//    if ( ! self.movieFileOutput.isRecording ) {
//        dispatch_async(dispatch_get_main_queue(), ^{
//            [sender setAlpha:.15];
//        });
//
//        dispatch_async( self.sessionQueue, ^{
//            if ( [UIDevice currentDevice].isMultitaskingSupported ) {
//                self.backgroundRecordingID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil];
//            }
//            //            AVCaptureConnection *movieConnection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
//            //            AVCaptureDeviceRotationCoordinator * rotation_coord = [[AVCaptureDeviceRotationCoordinator alloc] initWithDevice:self->_videoDevice previewLayer:previewLayer];
//            //            previewLayer.connection.videoRotationAngle = rotation_coord.videoRotationAngleForHorizonLevelPreview;
//            //            self.videoCaptureConnection.videoRotationAngle = rotation_coord.videoRotationAngleForHorizonLevelPreview;
//            //            movieConnection.videoOrientation = previewLayerVideoOrientation;
//
//            NSString *outputFileName = [NSProcessInfo processInfo].globallyUniqueString;
//            NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[outputFileName stringByAppendingPathExtension:@"mov"]];
//            [self.movieFileOutput startRecordingToOutputFileURL:[NSURL fileURLWithPath:outputFilePath] recordingDelegate:self];
//
//            dispatch_sync(dispatch_get_main_queue(), ^{
//                UIApplication.sharedApplication.idleTimerDisabled = TRUE;
//                //                NSString * fps = (NSString *)CFBridgingRelease(CMTimeCopyDescription(NULL, self->_videoDevice.activeVideoMaxFrameDuration));
//                //                self->_fpsLabel.text = [NSString stringWithFormat:@"%@", fps];
//            });
//        });
//    }
//    else {
//        dispatch_async(dispatch_get_main_queue(), ^{
//            [sender setAlpha:1.0];
//            [(UIButton *)sender setImage:[UIImage systemImageNamed:@"bolt.slash"] forState:UIControlStateSelected];
//
//        });
//        dispatch_async( self.sessionQueue, ^{
//            [self.movieFileOutput stopRecording];
//            dispatch_sync(dispatch_get_main_queue(), ^{
//                UIApplication.sharedApplication.idleTimerDisabled = FALSE;
//                //                NSString * fps = (NSString *)CFBridgingRelease(CMTimeCopyDescription(NULL, self->_videoDevice.activeVideoMaxFrameDuration));
//                //                self->_fpsLabel.text = [NSString stringWithFormat:@"%@", fps];
//            });
//        });
//    }
//}

- (IBAction)toggleMovieRecording:(UIButton *)sender {
    if (!self.session.isRunning) {
        NSLog(@"Session is not running. Cannot start recording.");
        return;
    }
    
    if (!self.movieFileOutput.isRecording) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [sender setAlpha:0.5];
        });
        
        dispatch_async(self.sessionQueue, ^{
            if ([UIDevice currentDevice].isMultitaskingSupported) {
                self.backgroundRecordingID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil];
            }
            
            NSString *outputFileName = [NSProcessInfo processInfo].globallyUniqueString;
            NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[outputFileName stringByAppendingPathExtension:@"mov"]];
            [self.movieFileOutput startRecordingToOutputFileURL:[NSURL fileURLWithPath:outputFilePath] recordingDelegate:self];
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [sender setAlpha:1.0];
        });
        
        dispatch_async(self.sessionQueue, ^{
            [self.movieFileOutput stopRecording];
        });
    }
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
    // Enable the Record button to let the user stop the recording
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
    // Note that currentBackgroundRecordingID is used to end the background task associated with this recording.
    // This allows a new recording to be started, associated with a new UIBackgroundTaskIdentifier, once the movie file output's isRecording property
    // is back to NO — which happens sometime after this method returns.
    // Note: Since we use a unique file path for each recording, a new recording will not overwrite a recording currently being saved.
    UIBackgroundTaskIdentifier currentBackgroundRecordingID = self.backgroundRecordingID;
    self.backgroundRecordingID = UIBackgroundTaskInvalid;
    
    dispatch_block_t cleanup = ^{
        if ( [[NSFileManager defaultManager] fileExistsAtPath:outputFileURL.path] ) {
            [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
        }
        
        if ( currentBackgroundRecordingID != UIBackgroundTaskInvalid ) {
            [[UIApplication sharedApplication] endBackgroundTask:currentBackgroundRecordingID];
        }
    };
    
    BOOL success = YES;
    
    if ( error ) {
        NSLog( @"Error occurred while capturing movie: %@", error );
        success = [error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] boolValue];
    }
    if ( success ) {
        // Check authorization status
        [PHPhotoLibrary requestAuthorization:^( PHAuthorizationStatus status ) {
            if ( status == PHAuthorizationStatusAuthorized ) {
                // Save the movie file to the photo library and cleanup
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    // In iOS 9 and later, it's possible to move the file into the photo library without duplicating the file data.
                    // This avoids using double the disk space during save, which can make a difference on devices with limited free disk space.
                    PHAssetResourceCreationOptions *options = [[PHAssetResourceCreationOptions alloc] init];
                    options.shouldMoveFile = YES;
                    PHAssetCreationRequest *changeRequest = [PHAssetCreationRequest creationRequestForAsset];
                    [changeRequest addResourceWithType:PHAssetResourceTypeVideo fileURL:outputFileURL options:options];
                } completionHandler:^( BOOL success, NSError *error ) {
                    if ( ! success ) {
                        NSLog( @"Could not save movie to photo library: %@", error );
                    }
                    cleanup();
                }];
            }
            else {
                cleanup();
            }
        }];
    }
    else {
        cleanup();
    }
    
    // Enable the Camera and Record buttons to let the user switch camera and start another recording
    dispatch_async( dispatch_get_main_queue(), ^{
        // Only enable the ability to change camera if the device has more than one camera
        //		self.cameraButton.enabled = ( self.videoDeviceDiscoverySession.devices.count > 1 );
        self.recordButton.alpha = 1.0;
        // TO-DO: Change button image to record.circle.fill
        //		[self.recordButton setTitle:NSLocalizedString( @"Record", @"Recording button record title" ) forState:UIControlStateNormal];
        //		self.captureModeControl.enabled = YES;
    });
}

#pragma mark KVO and Notifications

- (void)addObservers
{
    [self addObserver:self forKeyPath:@"session.running" options:NSKeyValueObservingOptionNew context:SessionRunningContext];
    [self addObserver:self forKeyPath:@"videoDevice.focusMode" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:FocusModeContext];
    [self addObserver:self forKeyPath:@"videoDevice.lensPosition" options:NSKeyValueObservingOptionNew context:LensPositionContext];
    [self addObserver:self forKeyPath:@"videoDevice.exposureMode" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:ExposureModeContext];
    [self addObserver:self forKeyPath:@"videoDevice.exposureDuration" options:NSKeyValueObservingOptionNew context:ExposureDurationContext];
    [self addObserver:self forKeyPath:@"videoDevice.ISO" options:NSKeyValueObservingOptionNew context:ISOContext];
    [self addObserver:self forKeyPath:@"videoDevice.videoZoomFactor" options:NSKeyValueObservingOptionNew context:VideoZoomFactorContext];
    [self addObserver:self forKeyPath:@"videoDevice.whiteBalanceMode" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:WhiteBalanceModeContext];
    [self addObserver:self forKeyPath:@"videoDevice.deviceWhiteBalanceGains" options:NSKeyValueObservingOptionNew context:DeviceWhiteBalanceGainsContext];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.videoDevice];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(captureDeviceWasConnected:) name:AVCaptureDeviceWasConnectedNotification object:self.videoDevice];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:self.session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:self.session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:self.session];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(thermalStateChanged:) name:NSProcessInfoThermalStateDidChangeNotification object:nil];
}

- (void)thermalStateChanged:(NSNotification *)notification {
    NSProcessInfoThermalState thermalState = [NSProcessInfo processInfo].thermalState;
    if (thermalState >= NSProcessInfoThermalStateSerious) {
        // Reduce video quality or frame rate
    }
}

- (void)removeObservers
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [self removeObserver:self forKeyPath:@"session.running" context:SessionRunningContext];
    [self removeObserver:self forKeyPath:@"videoDevice.focusMode" context:FocusModeContext];
    [self removeObserver:self forKeyPath:@"videoDevice.lensPosition" context:LensPositionContext];
    [self removeObserver:self forKeyPath:@"videoDevice.exposureMode" context:ExposureModeContext];
    [self removeObserver:self forKeyPath:@"videoDevice.exposureDuration" context:ExposureDurationContext];
    [self removeObserver:self forKeyPath:@"videoDevice.ISO" context:ISOContext];
    [self removeObserver:self forKeyPath:@"videoDevice.exposureTargetBias" context:ExposureTargetBiasContext];
    [self removeObserver:self forKeyPath:@"videoDevice.exposureTargetOffset" context:ExposureTargetOffsetContext];
    [self removeObserver:self forKeyPath:@"videoDevice.videoZoomFactor" context:VideoZoomFactorContext];
    [self removeObserver:self forKeyPath:@"videoDevice.whiteBalanceMode" context:WhiteBalanceModeContext];
    [self removeObserver:self forKeyPath:@"videoDevice.deviceWhiteBalanceGains" context:DeviceWhiteBalanceGainsContext];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.videoDevice];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    id oldValue = change[NSKeyValueChangeOldKey];
    id newValue = change[NSKeyValueChangeNewKey];
    
    if ( context == FocusModeContext ) {
        if ( newValue && newValue != [NSNull null] ) {
            AVCaptureFocusMode newMode = [newValue intValue];
            dispatch_async( dispatch_get_main_queue(), ^{
                if (self.videoDevice.focusMode == AVCaptureFocusModeLocked) {
                    [self.focusModeControl setSelectedSegmentIndex:1];
                } else if (self.videoDevice.focusMode == AVCaptureFocusModeContinuousAutoFocus) {
                    [self.focusModeControl setSelectedSegmentIndex:0];
                }
                self.lensPositionSlider.enabled = ( newMode == AVCaptureFocusModeLocked );
                self.lensPositionSlider.selected = ( newMode == AVCaptureFocusModeLocked );
                
                if ( oldValue && oldValue != [NSNull null] ) {
                    AVCaptureFocusMode oldMode = [oldValue intValue];
                    NSLog( @"focus mode: %@ -> %@", [self stringFromFocusMode:oldMode], [self stringFromFocusMode:newMode] );
                }
                else {
                    NSLog( @"focus mode: %@", [self stringFromFocusMode:newMode] );
                }
            } );
        }
    }
    else if ( context == LensPositionContext ) {
        if ( newValue && newValue != [NSNull null] ) {
            AVCaptureFocusMode focusMode = self.videoDevice.focusMode;
            float newLensPosition = [newValue floatValue];
            dispatch_async( dispatch_get_main_queue(), ^{
                if ( focusMode != AVCaptureFocusModeLocked ) {
                    self.lensPositionSlider.value = newLensPosition;
                }
                
            } );
        }
    }
    else if ( context == ExposureModeContext ) {
        if ( newValue && newValue != [NSNull null] ) {
            AVCaptureExposureMode newMode = [newValue intValue];
            if ( oldValue && oldValue != [NSNull null] ) {
                AVCaptureExposureMode oldMode = [oldValue intValue];
                
                if ( oldMode != newMode && oldMode == AVCaptureExposureModeCustom ) {
                    //                    if ( [self.videoDevice lockForConfiguration:NULL] == YES ) {
                    //                        self.videoDevice.activeVideoMinFrameDuration = kCMTimeInvalid;
                    //                        self.videoDevice.activeVideoMaxFrameDuration = kCMTimeInvalid;
                    //                        [self.videoDevice unlockForConfiguration];
                    //                    }
                }
            }
            
            dispatch_async( dispatch_get_main_queue(), ^{
                self.exposureModeControl.selectedSegmentIndex = [self.exposureModes indexOfObject:@(newMode)];
                self.exposureDurationSlider.enabled = ( newMode == AVCaptureExposureModeCustom );
                self.ISOSlider.enabled = ( newMode == AVCaptureExposureModeCustom );
                self.exposureDurationSlider.selected = ( newMode == AVCaptureExposureModeCustom );
                self.ISOSlider.selected = ( newMode == AVCaptureExposureModeCustom );
                
                if ( oldValue && oldValue != [NSNull null] ) {
                    AVCaptureExposureMode oldMode = [oldValue intValue];
                    NSLog( @"exposure mode: %@ -> %@", [self stringFromExposureMode:oldMode], [self stringFromExposureMode:newMode] );
                }
                else {
                    NSLog( @"exposure mode: %@", [self stringFromExposureMode:newMode] );
                }
            } );
        }
    }
    else if ( context == ExposureDurationContext ) {
        if ( newValue && newValue != [NSNull null] ) {
            //            double newDurationSeconds = CMTimeGetSeconds( [newValue CMTimeValue] );
            AVCaptureExposureMode exposureMode = self.videoDevice.exposureMode;
            
            double exposureDurationSeconds = CMTimeGetSeconds( self.videoDevice.exposureDuration );
            double minExposureDurationSeconds = CMTimeGetSeconds(CMTimeMakeWithSeconds((1.f / 1000.f), 1000*1000*1000));
            double maxExposureDurationSeconds = CMTimeGetSeconds(CMTimeMakeWithSeconds((1.f / 3.f), 1000*1000*1000));
            
            
            dispatch_async( dispatch_get_main_queue(), ^{
                if ( exposureMode != AVCaptureExposureModeCustom ) {
                    self.exposureDurationSlider.value = property_control_value(exposureDurationSeconds, minExposureDurationSeconds, maxExposureDurationSeconds, kExposureDurationPower, 0.f);
                }
            } );
        }
    }
    else if ( context == ISOContext ) {
        if ( newValue && newValue != [NSNull null] ) {
            float newISO = [newValue floatValue];
            AVCaptureExposureMode exposureMode = self.videoDevice.exposureMode;
            
            dispatch_async( dispatch_get_main_queue(), ^{
                if ( exposureMode != AVCaptureExposureModeCustom ) {
                    self.ISOSlider.value = property_control_value(newISO, self.videoDevice.activeFormat.minISO, self.videoDevice.activeFormat.maxISO, 1.f, 0.f);
                }
            } );
        }
    }
    else if ( context == VideoZoomFactorContext) {
        if ( newValue && newValue != [NSNull null] ) {
            double newZoomFactor = [newValue doubleValue];
            dispatch_async( dispatch_get_main_queue(), ^{
                [self.videoZoomFactorSlider setValue:property_control_value(newZoomFactor, self.videoDevice.minAvailableVideoZoomFactor, self.videoDevice.activeFormat.videoMaxZoomFactor, kVideoZoomFactorPowerCoefficient, -1.f)];
            });
        }
    }
    else if ( context == WhiteBalanceModeContext ) {
        if ( newValue && newValue != [NSNull null] ) {
            AVCaptureWhiteBalanceMode newMode = [newValue intValue];
            dispatch_async( dispatch_get_main_queue(), ^{
                self.whiteBalanceModeControl.selectedSegmentIndex = [self.whiteBalanceModes indexOfObject:@(newMode)];
                self.temperatureSlider.enabled = ( newMode == AVCaptureWhiteBalanceModeLocked );
                self.tintSlider.enabled = ( newMode == AVCaptureWhiteBalanceModeLocked );
                
                if ( oldValue && oldValue != [NSNull null] ) {
                    AVCaptureWhiteBalanceMode oldMode = [oldValue intValue];
                    NSLog( @"white balance mode: %@ -> %@", [self stringFromWhiteBalanceMode:oldMode], [self stringFromWhiteBalanceMode:newMode] );
                }
            } );
        }
    }
    else if ( context == DeviceWhiteBalanceGainsContext ) {
        if ( newValue && newValue != [NSNull null] ) {
            AVCaptureWhiteBalanceGains newGains;
            [newValue getValue:&newGains];
            AVCaptureWhiteBalanceTemperatureAndTintValues newTemperatureAndTint = [self.videoDevice temperatureAndTintValuesForDeviceWhiteBalanceGains:newGains];
            AVCaptureWhiteBalanceMode whiteBalanceMode = self.videoDevice.whiteBalanceMode;
            dispatch_async( dispatch_get_main_queue(), ^{
                if ( whiteBalanceMode != AVCaptureExposureModeLocked ) {
                    self.temperatureSlider.value = property_control_value(newTemperatureAndTint.temperature, 3000.f, 8000.f, 1.f, 0.f);
                    self.tintSlider.value = property_control_value(newTemperatureAndTint.tint, -150.f, 150.f, 1.f, 0.f);
                }
            });
        }
    }
    else if ( context == SessionRunningContext ) {
        BOOL isRunning = NO;
        if ( newValue && newValue != [NSNull null] ) {
            isRunning = [newValue boolValue];
        }
        dispatch_async( dispatch_get_main_queue(), ^{
            //			self.cameraButton.enabled = isRunning && ( self.videoDeviceDiscoverySession.devices.count > 1 );
            self.recordButton.enabled = isRunning;
        } );
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)subjectAreaDidChange:(NSNotification *)notification
{
    CGPoint devicePoint = CGPointMake( 0.5, 0.5 );
    [self focusWithMode:self.videoDevice.focusMode exposeWithMode:self.videoDevice.exposureMode atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}

- (void)captureDeviceWasConnected:(NSNotification *)notification
{
    
}

- (void)sessionRuntimeError:(NSNotification *)notification
{
    NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
    NSLog( @"Capture session runtime error: %@", error );
    
    if ( error.code == AVErrorMediaServicesWereReset ) {
        dispatch_async( self.sessionQueue, ^{
            // If we aren't trying to resume the session, try to restart it, since it must have been stopped due to an error (see -[resumeInterruptedSession:])
            if ( self.isSessionRunning ) {
                [self.session startRunning];
                self.sessionRunning = self.session.isRunning;
            }
            else {
                dispatch_async( dispatch_get_main_queue(), ^{
                    self.resumeButton.hidden = NO;
                } );
            }
        } );
    }
    else {
        self.resumeButton.hidden = NO;
    }
}

- (void)sessionWasInterrupted:(NSNotification *)notification
{
    AVCaptureSessionInterruptionReason reason = [notification.userInfo[AVCaptureSessionInterruptionReasonKey] integerValue];
    NSString *message;
    
    switch (reason) {
        case AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableInBackground:
            message = @"The session was interrupted because the app was sent to the background while using the camera.";
            break;
            
        case AVCaptureSessionInterruptionReasonAudioDeviceInUseByAnotherClient:
            message = @"The session was interrupted because the audio device is being used by another client (e.g., a phone call or alarm).";
            break;
            
        case AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient:
            message = @"The session was interrupted because the video device is being used by another application or session.";
            break;
            
        case AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableWithMultipleForegroundApps:
            message = @"The session was interrupted because the camera is not available when your app is running alongside another app (e.g., Slide Over, Split View, or Picture in Picture on iPad).";
            break;
            
        case AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableDueToSystemPressure:
            message = @"The session was interrupted due to system pressure, such as thermal overload. Please reduce system load or cool the device.";
            break;
            
        default:
            message = @"The session was interrupted for an unknown reason.";
            break;
    }
    
    NSLog(@"Capture session was interrupted with reason: %ld", (long)reason);
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Session Interrupted"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
    [self asdf:reason];
}

- (void)asdf:(AVCaptureSessionInterruptionReason)interruptionReason
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ( interruptionReason == AVCaptureSessionInterruptionReasonAudioDeviceInUseByAnotherClient ||
            interruptionReason == AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient ) {
            // Simply fade-in a button to enable the user to try to resume the session running
            self.resumeButton.hidden = NO;
            self.resumeButton.alpha = 0.0;
            [UIView animateWithDuration:0.25 animations:^{
                self.resumeButton.alpha = 1.0;
            }];
        }
        else if ( interruptionReason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableWithMultipleForegroundApps ) {
            // Simply fade-in a label to inform the user that the camera is unavailable
            self.cameraUnavailableImageView.hidden = NO;
            self.cameraUnavailableImageView.alpha = 0.0;
            [UIView animateWithDuration:0.25 animations:^{
                self.cameraUnavailableImageView.alpha = 1.0;
            }];
        }
    });
}

- (void)sessionInterruptionEnded:(NSNotification *)notification
{
    NSLog( @"Capture session interruption ended" );
    
    if ( ! self.resumeButton.hidden ) {
        [UIView animateWithDuration:0.25 animations:^{
            self.resumeButton.alpha = 0.0;
        } completion:^( BOOL finished ) {
            self.resumeButton.hidden = YES;
        }];
    }
    if ( ! self.cameraUnavailableImageView.hidden ) {
        [UIView animateWithDuration:0.25 animations:^{
            self.cameraUnavailableImageView.alpha = 0.0;
        } completion:^( BOOL finished ) {
            self.cameraUnavailableImageView.hidden = YES;
        }];
    }
}

- (NSString *)stringFromFocusMode:(AVCaptureFocusMode)focusMode
{
    NSString *string = @"INVALID FOCUS MODE";
    
    if ( focusMode == AVCaptureFocusModeLocked ) {
        string = @"Locked";
    }
    else if ( focusMode == AVCaptureFocusModeAutoFocus ) {
        string = @"Auto";
    }
    else if ( focusMode == AVCaptureFocusModeContinuousAutoFocus ) {
        string = @"ContinuousAuto";
    }
    
    return string;
}

- (NSString *)stringFromExposureMode:(AVCaptureExposureMode)exposureMode
{
    NSString *string = @"INVALID EXPOSURE MODE";
    
    if ( exposureMode == AVCaptureExposureModeLocked ) {
        string = @"Locked";
    }
    else if ( exposureMode == AVCaptureExposureModeAutoExpose ) {
        string = @"Auto";
    }
    else if ( exposureMode == AVCaptureExposureModeContinuousAutoExposure ) {
        string = @"ContinuousAuto";
    }
    else if ( exposureMode == AVCaptureExposureModeCustom ) {
        string = @"Custom";
    }
    
    return string;
}

- (NSString *)stringFromWhiteBalanceMode:(AVCaptureWhiteBalanceMode)whiteBalanceMode
{
    NSString *string = @"INVALID WHITE BALANCE MODE";
    
    if ( whiteBalanceMode == AVCaptureWhiteBalanceModeLocked ) {
        string = @"Locked";
    }
    else if ( whiteBalanceMode == AVCaptureWhiteBalanceModeAutoWhiteBalance ) {
        string = @"Auto";
    }
    else if ( whiteBalanceMode == AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance ) {
        string = @"ContinuousAuto";
    }
    
    return string;
}

@end
