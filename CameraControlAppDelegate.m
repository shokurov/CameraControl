#import "CameraControlAppDelegate.h"


@implementation CameraControlAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // List all video devices
    [self reloadCameraDevices];
    [self initUSBListeners];
}

- (void)initUSBListeners {
    io_iterator_t newDevicesIterator;
    io_iterator_t lostDevicesIterator;
    
    newDevicesIterator = 0;
    lostDevicesIterator = 0;
    NSLog(@" ");
    
    NSMutableDictionary *matchingDict = (__bridge NSMutableDictionary *)IOServiceMatching(kIOUSBDeviceClassName);
    
    if (matchingDict == nil){
        NSLog(@"Could not create matching dictionary");
        return;
    }
    
    //  Add notification ports to runloop
    IONotificationPortRef notificationPort = IONotificationPortCreate(kIOMasterPortDefault);
    CFRunLoopSourceRef notificationRunLoopSource = IONotificationPortGetRunLoopSource(notificationPort);
    CFRunLoopAddSource([[NSRunLoop currentRunLoop] getCFRunLoop], notificationRunLoopSource, kCFRunLoopDefaultMode);
    
    kern_return_t err;
    err = IOServiceAddMatchingNotification(notificationPort,
                                           kIOMatchedNotification,
                                           (__bridge CFDictionaryRef)matchingDict,
                                           usbDeviceAppeared,
                                           (__bridge void *)self,
                                           &newDevicesIterator);
    if (err)
    {
        NSLog(@"error adding publish notification");
    }
    io_object_t thisObject;
    while ( (thisObject = IOIteratorNext(newDevicesIterator))) IOObjectRelease(thisObject);
    
    
    NSMutableDictionary *matchingDictRemoved = (__bridge NSMutableDictionary *)IOServiceMatching(kIOUSBDeviceClassName);
    
    if (matchingDictRemoved == nil){
        NSLog(@"Could not create matching dictionary");
        return;
    }
    
    err = IOServiceAddMatchingNotification(notificationPort,
                                           kIOTerminatedNotification,
                                           (__bridge CFDictionaryRef)matchingDictRemoved,
                                           usbDeviceDisappeared,
                                           (__bridge void *)self,
                                           &lostDevicesIterator);
    if (err)
    {
        NSLog(@"error adding removed notification");
    }
    while ( (thisObject = IOIteratorNext(lostDevicesIterator))) IOObjectRelease(thisObject);
}

#pragma mark -
#pragma mark C Callback functions
#pragma mark -

void usbDeviceAppeared(void *refCon, io_iterator_t iterator){
    NSLog(@"Matching USB device appeared");
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:false block:^(NSTimer * _Nonnull timer) {
        [(CameraControlAppDelegate *)refCon reloadCameraDevices];
    }];
    io_object_t thisObject;
    while ( (thisObject = IOIteratorNext(iterator))) IOObjectRelease(thisObject);
}

void usbDeviceDisappeared(void *refCon, io_iterator_t iterator){
    NSLog(@"Matching USB device disappeared");
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:false block:^(NSTimer * _Nonnull timer) {
        [(CameraControlAppDelegate *)refCon reloadCameraDevices];
    }];
    io_object_t thisObject;
    while ( (thisObject = IOIteratorNext(iterator))) IOObjectRelease(thisObject);
}

#pragma mark -
#pragma mark UI init and re-selection of a camera

- (void)reloadCameraDevices {
    AVCaptureDeviceDiscoverySession * discoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:(@[AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeExternalUnknown]) mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
    
    allDevices = [discoverySession devices];
    if( allDevices.count == 0 ) {
        NSLog( @"No video input device" );
        exit( 1 );
    }
    defaultDevice = allDevices.firstObject;
    [cameraPopupButton removeAllItems];
    [allDevices enumerateObjectsUsingBlock:^(AVCaptureDevice * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSMenuItem * newItem = [[NSMenuItem alloc] initWithTitle:(obj.localizedName) action:@selector(cameraMenuSelected:) keyEquivalent:@""];
        newItem.representedObject = obj;
        [cameraPopupButton.menu addItem:newItem];
        if (obj == defaultDevice) {
            [cameraPopupButton setTitle:(newItem.title)];
            [cameraPopupButton selectItem:newItem];
        }
    }];
    
    [self initWithDevice:defaultDevice];
}

- (void)initWithDevice:(AVCaptureDevice *)defaultDevice {
    videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:defaultDevice error:nil];
    if (!videoInput) {
        NSLog(@"Can't get input for selected device");
        return;
    }
    
    captureSession = [[AVCaptureSession alloc] init];
    [captureSession addInput:videoInput];
    
    AVCaptureVideoPreviewLayer * previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:captureSession];
    [previewLayer setBackgroundColor:[[NSColor blackColor] CGColor]];
    CALayer *rootLayer = [captureView layer];
    [rootLayer setMasksToBounds:YES];
    [previewLayer setFrame:[rootLayer bounds]];
    [rootLayer addSublayer:previewLayer];
    [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
    
    // Setting a lower resolution for the CaptureOutput here, since otherwise AVCaptureView
    // pulls full-res frames from the camera, which is slow. This is just for cosmetics.
    if ([captureSession canSetSessionPreset:AVCaptureSessionPreset640x480]) {
        captureSession.sessionPreset = AVCaptureSessionPreset640x480;
    }
    
    [captureSession startRunning];
    
    // Ok, this might be all kinds of wrong, but it was the only way I found to map a
    // QTCaptureDevice to a IOKit USB Device. The uniqueID method seems to always(?) return
    // the locationID as a HEX string in the first few chars, but the format of this string
    // is not documented anywhere and (knowing Apple) might change sooner or later.
    //
    // In most cases you'd be probably better of using the UVCCameraControls
    // - (id)initWithVendorID:(long) productID:(long)
    // method instead. I.e. for the Logitech QuickCam9000:
    // cameraControl = [[UVCCameraControl alloc] initWithVendorID:0x046d productID:0x0990];
    //
    // You can use USB Prober (should be in /Developer/Applications/Utilities/USB Prober.app)
    // to find the values of your camera.
    
    UInt32 locationID = 0;
    sscanf( [[defaultDevice uniqueID] UTF8String], "0x%8x", &locationID );
    cameraControl = [[UVCCameraControl alloc] initWithLocationID:locationID];
    
    [autoExposureCheckBox setState:([cameraControl getAutoExposure] ? NSControlStateValueOn : NSControlStateValueOff)];
    [autoWhiteBalanceCheckBox setState:([cameraControl getAutoWhiteBalance] ? NSControlStateValueOn : NSControlStateValueOff)];
    [exposureSlider setFloatValue:([cameraControl getExposure])];
    [whiteBalanceSlider setFloatValue:([cameraControl getWhiteBalance])];
}

#pragma mark -
#pragma mark UI actions

- (void)cameraMenuSelected:(id)sender {
    NSMenuItem * item = sender;
    [cameraPopupButton selectItem:item];
    [cameraPopupButton setTitle:item.title];
    [self initWithDevice:(item.representedObject)];
}

- (IBAction)sliderMoved:(id)sender {
	
	// Exposure Time
	if( [sender isEqualTo:exposureSlider] ) {		
		[cameraControl setExposure:exposureSlider.floatValue];
	}
	
	// White Balance Temperature
	else if( [sender isEqualTo:whiteBalanceSlider] ) {
		[cameraControl setWhiteBalance:whiteBalanceSlider.floatValue];
	}
	
	// Gain Value
	else if( [sender isEqualTo:gainSlider] ) {
		[cameraControl setBrightness:gainSlider.floatValue];
	}
}


- (IBAction)checkBoxChanged:(id)sender {
	
	// Auto Exposure
	if( [sender isEqualTo:autoExposureCheckBox] ) {
        if( autoExposureCheckBox.state == NSControlStateValueOn ) {
			[cameraControl setAutoExposure:YES];
			[exposureSlider setEnabled:NO];
		} 
		else {
			[cameraControl setAutoExposure:NO];
			[exposureSlider setEnabled:YES];
			[cameraControl setExposure:exposureSlider.floatValue];
		}
	}
	
	// Auto White Balance
	else if( [sender isEqualTo:autoWhiteBalanceCheckBox] ) {
        if( autoWhiteBalanceCheckBox.state == NSControlStateValueOn ) {
			[cameraControl setAutoWhiteBalance:YES];
			[whiteBalanceSlider setEnabled:NO];
		} 
		else {
			[cameraControl setAutoWhiteBalance:NO];
			[whiteBalanceSlider setEnabled:YES];
			[cameraControl setWhiteBalance:whiteBalanceSlider.floatValue];
		}
	}
}


- (void)dealloc {
	[captureSession release];
	[videoInput release];
	[defaultDevice release];
    [allDevices release];
	
	[cameraControl release];
	[super dealloc];
}

@end

