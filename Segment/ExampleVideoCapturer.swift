

import OpenTok
import AVFoundation

extension UIApplication {
    func currentDeviceOrientation(cameraPosition pos: AVCaptureDevice.Position) -> OTVideoOrientation {
        let orientation = statusBarOrientation
        // print("Orientation is \(orientation)")
        
        if pos == .front {
            switch orientation {
            case .landscapeLeft: return .up
            case .landscapeRight: return .down
            case .portrait: return .left
            case .portraitUpsideDown: return .right
            case .unknown: return .up
            }
        } else {
            switch orientation {
            case .landscapeLeft: return .down
            case .landscapeRight: return .up
            case .portrait: return .left
            case .portraitUpsideDown: return .right
            case .unknown: return .up
            }
        }
    }
}

extension AVCaptureSession.Preset {
    func dimensionForCapturePreset() -> (width: UInt32, height: UInt32) {
        switch self {
        case AVCaptureSession.Preset.cif352x288: return (352, 288)
        case AVCaptureSession.Preset.vga640x480, AVCaptureSession.Preset.high: return (640, 480)
        case AVCaptureSession.Preset.low: return (192, 144)
        case AVCaptureSession.Preset.medium: return (480, 360)
        case AVCaptureSession.Preset.hd1280x720: return (1280, 720)
        default: return (352, 288)
        }
    }
}

protocol FrameCapturerMetadataDelegate {
    func finishPreparingFrame(_ videoFrame: OTVideoFrame?)
}

class ExampleVideoCapture: NSObject, OTVideoCapture {
    var captureSession: AVCaptureSession?
    var videoInput: AVCaptureDeviceInput?
    var videoOutput: AVCaptureVideoDataOutput?
    
    var videoCaptureConsumer: OTVideoCaptureConsumer?
    
    var delegate: FrameCapturerMetadataDelegate?
    
    fileprivate var capturePreset: AVCaptureSession.Preset {
        didSet {
            (captureWidth, captureHeight) = capturePreset.dimensionForCapturePreset()
        }
    }
    
    fileprivate var captureWidth: UInt32
    fileprivate var captureHeight: UInt32
    fileprivate var capturing = false
    fileprivate let videoFrame: OTVideoFrame
    fileprivate var videoFrameOrientation: OTVideoOrientation = .left
    
    
    
    // private var Segmentati
    var segmentation: SegmentationDelegate?
    
    
    let captureQueue: DispatchQueue
    
    fileprivate func updateFrameOrientation() {
        DispatchQueue.main.async {
            guard let inputDevice = self.videoInput else {
                return;
            }
            self.videoFrameOrientation=UIApplication.shared.currentDeviceOrientation(cameraPosition: inputDevice.device.position)
        }
    }
    
    override init() {
        capturePreset = AVCaptureSession.Preset.vga640x480
        //capturePreset = AVCaptureSession.Preset.hd1280x720
        captureQueue = DispatchQueue(label: "com.tokbox.VideoCapture", attributes: [])
        (captureWidth, captureHeight) = capturePreset.dimensionForCapturePreset()
        videoFrame = OTVideoFrame(format: OTVideoFormat(nv12WithWidth: captureWidth, height: captureHeight))
        
    }
    func setDelegate(metaDataDelegate: FrameCapturerMetadataDelegate){
        self.delegate = metaDataDelegate
    }
    
    // MARK: - AVFoundation functions
    fileprivate func setupAudioVideoSession() throws {
        captureSession = AVCaptureSession()
        captureSession?.beginConfiguration()
        
        captureSession?.sessionPreset = capturePreset
        captureSession?.usesApplicationAudioSession = false
        
        // Configure Camera Input
        guard let device = camera(withPosition: .front)
            else {
                print("Failed to acquire camera device for video")
                return
        }
        
        videoInput = try AVCaptureDeviceInput(device: device)
        guard let videoInput = self.videoInput else {
            print("There was an error creating videoInput")
            return
        }
        captureSession?.addInput(videoInput)
        
        // Configure Ouput
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.alwaysDiscardsLateVideoFrames = true
        videoOutput?.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        ]
        videoOutput?.setSampleBufferDelegate(self, queue: captureQueue)
        
        guard let videoOutput = self.videoOutput else {
            print("There was an error creating videoOutput")
            return
        }
        captureSession?.addOutput(videoOutput)
        setFrameRate()
        captureSession?.commitConfiguration()
        
        captureSession?.startRunning()
    }
    
    fileprivate func frameRateRange(forFrameRate fps: Int) -> AVFrameRateRange? {
        return videoInput?.device.activeFormat.videoSupportedFrameRateRanges.filter({ range in
            return range.minFrameRate <= Double(fps) && Double(fps) <= range.maxFrameRate
        }).first
    }
    
    fileprivate func setFrameRate(fps: Int = 20) {
        guard let _ = frameRateRange(forFrameRate: fps)
            else {
                print("Unsupported frameRate \(fps)")
                return
        }
        
        let desiredMinFps = CMTime(value: 1, timescale: CMTimeScale(fps))
        let desiredMaxFps = CMTime(value: 1, timescale: CMTimeScale(fps))
        
        do {
            try videoInput?.device.lockForConfiguration()
            videoInput?.device.activeVideoMinFrameDuration = desiredMinFps
            videoInput?.device.activeVideoMaxFrameDuration = desiredMaxFps
        } catch {
            print("Error setting framerate")
        }
        
    }
    
    fileprivate func camera(withPosition pos: AVCaptureDevice.Position) -> AVCaptureDevice? {
        return AVCaptureDevice.devices(for: AVMediaType.video).filter({ $0.position == pos }).first
    }
    
    fileprivate func updateCaptureFormat(width w: UInt32, height h: UInt32) {
        captureWidth = w
        captureHeight = h
        videoFrame.format = OTVideoFormat.init(nv12WithWidth: w, height: h)
    }
    
    // MARK: - OTVideoCapture protocol
    func initCapture() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIDeviceOrientationDidChange,
                                               object: nil,
                                               queue: .main,
                                               using: { (_) in self.updateFrameOrientation() })
        captureQueue.async {
            do {
                try self.setupAudioVideoSession()
            } catch let error as NSError {
                print("Error configuring AV Session: \(error)")
            }
        }
    }
    
    func start() -> Int32 {
        self.updateFrameOrientation()
        self.capturing = true
        return 0
    }
    
    func stop() -> Int32 {
        capturing = false
        return 0
    }
    
    func releaseCapture() {
        let _ = stop()
        videoOutput?.setSampleBufferDelegate(nil, queue: captureQueue)
        captureQueue.sync {
            self.captureSession?.stopRunning()
        }
        captureSession = nil
        videoOutput = nil
        videoInput = nil
        
        NotificationCenter.default.removeObserver(self,
                                                  name: NSNotification.Name.UIDeviceOrientationDidChange,
                                                  object: nil)
    }
    
    func isCaptureStarted() -> Bool {
        return capturing && (captureSession != nil)
    }
    
    func captureSettings(_ videoFormat: OTVideoFormat) -> Int32 {
        videoFormat.pixelFormat = .NV12
        videoFormat.imageWidth = captureWidth
        videoFormat.imageHeight = captureHeight
        return 0
    }
    
    fileprivate func frontFacingCamera() -> AVCaptureDevice? {
        return camera(withPosition: .front)
    }
    
    fileprivate func backFacingCamera() -> AVCaptureDevice? {
        return camera(withPosition: .back)
    }
    
    fileprivate var hasMultipleCameras : Bool {
        return AVCaptureDevice.devices(for: AVMediaType.video).count > 1
    }
    
    func setCameraPosition(_ position: AVCaptureDevice.Position) -> Bool {
        guard let preset = captureSession?.sessionPreset else {
            print("No preset")
            return false
        }
        
        let newVideoInput: AVCaptureDeviceInput? = {
            
            do {
                if position == AVCaptureDevice.Position.back {
                    
                    guard let backFacingCamera = backFacingCamera() else {
                        print("New Video Input found back r nill")
                        return nil
                        
                    }
                    print("New Video Input found back")
                    return try AVCaptureDeviceInput.init(device: backFacingCamera)
                } else if position == AVCaptureDevice.Position.front {
                    print("New Video Input front")
                    guard let frontFacingCamera = frontFacingCamera() else { return nil }
                    return try AVCaptureDeviceInput.init(device: frontFacingCamera)
                } else {
                    return nil
                }
            } catch {
                return nil
            }
        }()
        
        guard let newInput = newVideoInput else {
            return false
        }
        
        var success = true
        
        captureQueue.sync {
            print("InsideCapture session")
            captureSession?.beginConfiguration()
            guard let videoInput = self.videoInput else { return }
            captureSession?.removeInput(videoInput)
            
            if captureSession?.canAddInput(newInput) ?? false {
                captureSession?.addInput(newInput)
                self.videoInput = newInput
            } else {
                success = false
                captureSession?.addInput(videoInput)
            }
            
            captureSession?.commitConfiguration()
            
        }
        print("Outside the condition queue \(success)")
        if success {
            capturePreset = preset
        }
        
        return success
    }
    
    func toggleCameraPosition() -> Bool {
        guard hasMultipleCameras else {
            print("Has Multiple camera")
            return false
        }
        
        /* if  videoInput?.device.position == .front {
         print("Toggle from front")
         return setCameraPosition(.back)
         } else {
         print("Toggle from back")
         return setCameraPosition(.front)
         }*/
        
        switchCameraTapped()
        return true
        
        
        
    }
    func switchCameraTapped() {
        //Change camera source
        if let session = self.captureSession {
            //Indicate that some changes will be made to the session
            session.beginConfiguration()
            
            //Remove existing input
            guard let currentCameraInput: AVCaptureInput = session.inputs.first else {
                return
            }
            
            session.removeInput(currentCameraInput)
            
            //Get new input
            var newCamera: AVCaptureDevice! = nil
            if let input = currentCameraInput as? AVCaptureDeviceInput {
                if (input.device.position == .back) {
                    newCamera = cameraWithPosition(position: .front)
                } else {
                    newCamera = cameraWithPosition(position: .back)
                }
            }
            
            //Add input to session
            var err: NSError?
            var newVideoInput: AVCaptureDeviceInput!
            do {
                newVideoInput = try AVCaptureDeviceInput(device: newCamera)
            } catch let err1 as NSError {
                err = err1
                newVideoInput = nil
            }
            
            if newVideoInput == nil || err != nil {
                print("Error creating capture device input: \(err?.localizedDescription)")
            } else {
                session.addInput(newVideoInput)
            }
            
            //Commit all the configuration changes at once
            session.commitConfiguration()
        }
    }
    // Find a camera with the specified AVCaptureDevicePosition, returning nil if one is not found
    func cameraWithPosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .unspecified)
        for device in discoverySession.devices {
            if device.position == position {
                return device
            }
        }
        
        return nil
    }
    
    
}










extension ExampleVideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ captureOutput: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //print("Dropping frame")
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        if !capturing || videoCaptureConsumer == nil {
            return
        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            else {
                print("Error acquiring sample buffer")
                return
        }
        // Convert to UIImage
        // let imageBufferi: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        // let ciimage : CIImage = CIImage(cvPixelBuffer: imageBuffer)
        // let image : UIImage = self.convert(cmage: ciimage)
        let imageCg = CGImage.create(pixelBuffer: imageBuffer)
        let image : UIImage = UIImage(cgImage: imageCg!)
        /*guard
         let imagei = image.rotate() else{
         fatalError("Roation fail")
         }
         */
        
        let imagei = imageRotatedByDegrees(oldImage: image, deg: 90)
        if (segmentation != nil){
            segmentation?.segment(image: imagei)
        }
        
        
        guard let videoInput = videoInput
            else {
                print("Capturer does not have a valid input")
                return
        }
        
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
        
        videoFrame.timestamp = time
        let height = UInt32(CVPixelBufferGetHeight(imageBuffer))
        let width = UInt32(CVPixelBufferGetWidth(imageBuffer))
        
        if width != captureWidth || height != captureHeight {
            updateCaptureFormat(width: width, height: height)
        }
        
        
        
        
        
        
        
        videoFrame.format?.imageWidth = width
        videoFrame.format?.imageHeight = height
        let minFrameDuration = videoInput.device.activeVideoMinFrameDuration
        
        videoFrame.format?.estimatedFramesPerSecond = Double(minFrameDuration.timescale) / Double(minFrameDuration.value)
        videoFrame.format?.estimatedCaptureDelay = 100
        videoFrame.orientation = self.videoFrameOrientation
        
        videoFrame.clearPlanes()
        
        if !CVPixelBufferIsPlanar(imageBuffer) {
            videoFrame.planes?.addPointer(CVPixelBufferGetBaseAddress(imageBuffer))
        } else {
            for idx in 0..<CVPixelBufferGetPlaneCount(imageBuffer) {
                videoFrame.planes?.addPointer(CVPixelBufferGetBaseAddressOfPlane(imageBuffer, idx))
            }
        }
        
        if let delegate = delegate {
            delegate.finishPreparingFrame(videoFrame)
        }
        
        videoCaptureConsumer!.consumeFrame(videoFrame)
        
        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)));
    }
    
    
    func convert(cmage:CIImage) -> UIImage
    {
        //  print("Converting")
        let context:CIContext = CIContext.init(options: nil)
        let cgImage:CGImage = context.createCGImage(cmage, from: cmage.extent)!
        let image:UIImage = UIImage.init(cgImage: cgImage)
        //let imagei = image.rotate(radians: 90)
        return image;
    }
    
    func imageRotatedByDegrees(oldImage: UIImage, deg degrees: CGFloat) -> UIImage {
        //Calculate the size of the rotated view's containing box for our drawing space
        let rotatedViewBox: UIView = UIView(frame: CGRect(x: 0, y: 0, width: oldImage.size.width, height: oldImage.size.height))
        let t: CGAffineTransform = CGAffineTransform(rotationAngle: degrees * CGFloat(M_PI / 180))
        rotatedViewBox.transform = t
        let rotatedSize: CGSize = rotatedViewBox.frame.size
        //Create the bitmap context
        UIGraphicsBeginImageContext(rotatedSize)
        let bitmap: CGContext = UIGraphicsGetCurrentContext()!
        //Move the origin to the middle of the image so we will rotate and scale around the center.
        bitmap.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        
        //Rotate the image context
        bitmap.rotate(by: degrees * CGFloat(Double.pi / 180))
        
        //Now, draw the rotated/scaled image into the context
        bitmap.scaleBy(x: 1.0, y: -1.0)
        bitmap.draw(oldImage.cgImage!, in: CGRect(x: -oldImage.size.width / 2, y: -oldImage.size.height / 2, width: oldImage.size.width, height: oldImage.size.height))
        let newImage: UIImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return newImage
    }
    
    
    
}
extension ExampleVideoCapture: FrameCapturerMetadataDelegate{
    func finishPreparingFrame(_ videoFrame: OTVideoFrame?) {
        
        guard let videoFrame = videoFrame else {
            return
        }
        setMetaDataWithCameraPosition(videoFrame)
        
        
    }
    
    func setMetaDataWithCameraPosition(_ videoFrame: OTVideoFrame?){
        
        guard let videoFrame = videoFrame else {
            return
        }
        var camerPosition: UInt8 = 0
        if  videoInput?.device.position == .front {
            camerPosition = 0
            
        } else {
            camerPosition = 1
        }
        
        var metaData = Data()
        metaData.append(camerPosition)
        var error: OTError?
        videoFrame.setMetadata(metaData, error: &error)
        if let error = error {
            print(error)
        }
    }
    
    
    
    
}

