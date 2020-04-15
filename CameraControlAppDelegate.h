#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

// #import <QTKit/QTKit.h>
#import "UVCCameraControl.h"

@interface CameraControlAppDelegate : NSObject {
	AVCaptureSession * captureSession;
	AVCaptureDevice * defaultDevice;
	AVCaptureDeviceInput * videoInput;
    NSArray<AVCaptureDevice *> * allDevices;

	UVCCameraControl * cameraControl;
	
	IBOutlet NSView * captureView;
	
	IBOutlet NSButton * autoExposureCheckBox;
	IBOutlet NSButton * autoWhiteBalanceCheckBox;
	IBOutlet NSSlider * exposureSlider;
	IBOutlet NSSlider * whiteBalanceSlider;
	IBOutlet NSSlider * gainSlider;
    IBOutlet NSPopUpButton *cameraPopupButton;
}

- (IBAction)sliderMoved:(id)sender;
- (IBAction)checkBoxChanged:(id)sender;

- (void)cameraMenuSelected:(id)sender;

@end
