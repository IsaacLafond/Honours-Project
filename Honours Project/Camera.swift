//
//  Camera.swift
//  Honours Project
//
//  Created by Isaac Lafond on 2024-11-13.
//

/*
See the License.txt file for this sample’s licensing information.
*/

import AVFoundation
import CoreImage
import UIKit
import os.log

class Camera: NSObject {
    private let captureSession = AVCaptureSession()
    private var isCaptureSessionConfigured = false
    private var deviceInput: AVCaptureDeviceInput?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var sessionQueue: DispatchQueue!
    
    public var capturedImage: AVCapturePhoto?
    
    private var allDepthCaptureDevices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInLiDARDepthCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInTrueDepthCamera], mediaType: .video, position: .unspecified).devices
    }
    
    private var availableCaptureDevices: [AVCaptureDevice] {
        allDepthCaptureDevices
            .filter( { $0.isConnected } )
            .filter( { !$0.isSuspended } )
    }
    
    private var captureDevice: AVCaptureDevice?

//    private var addToPhotoStream: ((AVCapturePhoto) -> Void)?
    
    private var addToPreviewStream: ((CIImage) -> Void)?
    
    var isPreviewPaused = false
    
    lazy var previewStream: AsyncStream<CIImage> = {
        AsyncStream { continuation in
            addToPreviewStream = { ciImage in
                if !self.isPreviewPaused {
                    continuation.yield(ciImage)
                }
            }
        }
    }()
    
//    lazy var photoStream: AsyncStream<AVCapturePhoto> = {
//        AsyncStream { continuation in
//            addToPhotoStream = { photo in
//                continuation.yield(photo)
//            }
//        }
//    }()
        
    override init() {
        super.init()
        initialize()
    }
    
    private func initialize() {
        sessionQueue = DispatchQueue(label: "session queue")
        
        captureDevice = availableCaptureDevices.first ?? AVCaptureDevice.default(for: .video)
    }
    
    private func configureCaptureSession(completionHandler: (_ success: Bool) -> Void) {
        // Define success marker
        var success = false
        // MARK: start session config
        self.captureSession.beginConfiguration()
        // commit config on success = true
        defer {
            self.captureSession.commitConfiguration()
            completionHandler(success)
        }
        // attempt to create device input
        guard
            let captureDevice = captureDevice,
            let deviceInput = try? AVCaptureDeviceInput(device: captureDevice)
        else {
            print("Failed to obtain video input.")
            return
        }
        // Initialize photo output for image capture
        let photoOutput = AVCapturePhotoOutput()
        // Define resolution preset
        captureSession.sessionPreset = AVCaptureSession.Preset.photo
        // Initialize video output for preview stream
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "VideoDataOutputQueue"))
        // Test if can add components to capture session (device input, photo output, video output)
        guard captureSession.canAddInput(deviceInput) else {
            print("Unable to add device input to capture session.")
            return
        }
        guard captureSession.canAddOutput(photoOutput) else {
            print("Unable to add photo output to capture session.")
            return
        }
        guard captureSession.canAddOutput(videoOutput) else {
            print("Unable to add video output to capture session.")
            return
        }
        // Add all outputs to the session
        captureSession.addInput(deviceInput)
        captureSession.addOutput(photoOutput)
        captureSession.addOutput(videoOutput)
        
        self.deviceInput = deviceInput
        self.photoOutput = photoOutput
        self.videoOutput = videoOutput
        // Test if depth is supported and enable it
        if photoOutput.isDepthDataDeliverySupported {
            photoOutput.isDepthDataDeliveryEnabled = true
        } else {
            print("Depth capture not supported")
            return
        }
        // Flag that session configuration was successful in camera object
        isCaptureSessionConfigured = true
        // Flag config success to commit configs (defer flag)
        success = true
    }
    
    private func checkAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("Camera access authorized.")
            return true
        case .notDetermined:
            print("Camera access not determined.")
            sessionQueue.suspend()
            let status = await AVCaptureDevice.requestAccess(for: .video)
            sessionQueue.resume()
            return status
        case .denied:
            print("Camera access denied.")
            return false
        case .restricted:
            print("Camera library access restricted.")
            return false
        @unknown default:
            return false
        }
    }
    
    func start() async {
        let authorized = await checkAuthorization()
        guard authorized else {
            print("Camera access was not authorized.")
            return
        }
        
        if isCaptureSessionConfigured {
            if !captureSession.isRunning {
                sessionQueue.async { [self] in
                    self.captureSession.startRunning()
                }
            }
            return
        }
        
        sessionQueue.async { [self] in
            self.configureCaptureSession { success in
                guard success else { return }
                self.captureSession.startRunning()
            }
        }
    }
    
    func stop() {
        guard isCaptureSessionConfigured else { return }
        
        if captureSession.isRunning {
            sessionQueue.async {
                self.captureSession.stopRunning()
            }
        }
    }

    private var deviceOrientation: UIDeviceOrientation {
        var orientation = UIDevice.current.orientation
        if orientation == UIDeviceOrientation.unknown {
            orientation = UIScreen.main.orientation
        }
        return orientation
    }
    
    private func videoOrientationFor(_ deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation? {
        switch deviceOrientation {
        case .portrait: return AVCaptureVideoOrientation.portrait
        case .portraitUpsideDown: return AVCaptureVideoOrientation.portraitUpsideDown
        case .landscapeLeft: return AVCaptureVideoOrientation.landscapeRight
        case .landscapeRight: return AVCaptureVideoOrientation.landscapeLeft
        default: return nil
        }
    }
    
    func takePhoto() {
        guard let photoOutput = self.photoOutput else { return }
        
        sessionQueue.async {
        
            var photoSettings = AVCapturePhotoSettings()

            if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            }
            
            let isFlashAvailable = self.deviceInput?.device.isFlashAvailable ?? false
            photoSettings.flashMode = isFlashAvailable ? .auto : .off
            photoSettings.isDepthDataDeliveryEnabled = true
            photoSettings.isDepthDataFiltered = true
            if let previewPhotoPixelFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPhotoPixelFormatType]
            }
//            photoSettings.photoQualityPrioritization = .balanced
            
            if let photoOutputVideoConnection = photoOutput.connection(with: .video) {
                if photoOutputVideoConnection.isVideoOrientationSupported,
                    let videoOrientation = self.videoOrientationFor(self.deviceOrientation) {
                    photoOutputVideoConnection.videoOrientation = videoOrientation
                }
            }
//            photoOutput.cap
            photoOutput.capturePhoto(with: photoSettings, delegate: self)
            
            
//            print(self.photoStream)
//            let photo = photoStream
//            // Get image data file (jpeg, heic)
//            guard let imageData = photo.fileDataRepresentation() else {
//                print("failed to retrieve image file data")
//                return
//            }
//            // Get image depth data
//            guard let depthData = photo.depthData?.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32) else {
//                print("failed to get and convert depth data")
//                return
//            }
//            // Get depth data to check if empty
//            let depthDataMap = depthData.depthDataMap
//            // Test if map is empty
//            if CVPixelBufferGetWidth(depthDataMap) == 0 || CVPixelBufferGetHeight(depthDataMap) == 0 {
//                print("0x0 empty depth data capture conditions failed to capture depth")
//                return
//            }
//            // Convert depth data to point cloud list of points
//            guard let pointCloud = convertDepthData(depthData: depthData) else {
//                print("failed to convert depth data")
//                return
//            }
//            // Prepare data for POST request
//            let jsonDic: [String: Any] = [
//                "image": imageData.base64EncodedString(),
//                "depth-accuracy": depthData.depthDataAccuracy.rawValue,
//                "depth-quality": depthData.depthDataQuality.rawValue,
//                "point-cloud": pointCloud
//            ]
//            guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonDic) else {
//                print("failed to serialize json data")
//                return
//            }
//            // Send capture data
//            Task {
//                print("Sending Capture...")
//                await sendCapture(data: jsonData)
//                print("Capture Sent!")
//            }
        }
    }
}

extension Camera: AVCapturePhotoCaptureDelegate {
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        if let error = error {
            print("Error capturing photo: \(error.localizedDescription) \(error)")
            return
        }
        
//        addToPhotoStream?(photo)
        self.capturedImage = photo
    }
}

extension Camera: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        
        if connection.isVideoOrientationSupported,
           let videoOrientation = videoOrientationFor(deviceOrientation) {
            connection.videoOrientation = videoOrientation
        }

        addToPreviewStream?(CIImage(cvPixelBuffer: pixelBuffer))
    }
}

fileprivate extension UIScreen {

    var orientation: UIDeviceOrientation {
        let point = coordinateSpace.convert(CGPoint.zero, to: fixedCoordinateSpace)
        if point == CGPoint.zero {
            return .portrait
        } else if point.x != 0 && point.y != 0 {
            return .portraitUpsideDown
        } else if point.x == 0 && point.y != 0 {
            return .landscapeRight //.landscapeLeft
        } else if point.x != 0 && point.y == 0 {
            return .landscapeLeft //.landscapeRight
        } else {
            return .unknown
        }
    }
}
