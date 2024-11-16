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
    
    private var allDepthCaptureDevices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInLiDARDepthCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInTrueDepthCamera], mediaType: .video, position: .unspecified).devices
    }
    
    private var availableCaptureDevices: [AVCaptureDevice] {
        allDepthCaptureDevices
            .filter( { $0.isConnected } )
            .filter( { !$0.isSuspended } )
    }
    
    private var captureDevice: AVCaptureDevice?

    private var addToPhotoStream: ((AVCapturePhoto) -> Void)?
    
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
    
    lazy var photoStream: AsyncStream<AVCapturePhoto> = {
        AsyncStream { continuation in
            addToPhotoStream = { photo in
                continuation.yield(photo)
            }
        }
    }()
        
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
    
//    private func deviceInputFor(device: AVCaptureDevice?) -> AVCaptureDeviceInput? {
//        guard let validDevice = device else { return nil }
//        do {
//            return try AVCaptureDeviceInput(device: validDevice)
//        } catch let error {
//            print("Error getting capture device input: \(error.localizedDescription)")
//            return nil
//        }
//    }
    
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
            
            photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }
}

extension Camera: AVCapturePhotoCaptureDelegate {
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        if let error = error {
            print("Error capturing photo: \(error.localizedDescription)")
            return
        }
        
        addToPhotoStream?(photo)
        
        // Get image data file (jpeg, heic)
        guard let imageData = photo.fileDataRepresentation() else {
            print("failed to retrieve image file data")
            return
        }
        // Get image depth data
        guard let depthData = photo.depthData?.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32) else {
            print("failed to get and convert depth data")
            return
        }
        // Get depth data to check if empty
        let depthDataMap = depthData.depthDataMap
        // Test if map is empty
        if CVPixelBufferGetWidth(depthDataMap) == 0 || CVPixelBufferGetHeight(depthDataMap) == 0 {
            print("0x0 empty depth data capture conditions failed to capture depth")
            return
        }
        // Convert depth data to point cloud list of points
        guard let pointCloud = convertDepthData(depthData: depthData) else {
            print("failed to convert depth data")
            return
        }
        // Prepare data for POST request
        let jsonDic: [String: Any] = [
            "image": imageData.base64EncodedString(),
            "depth-accuracy": depthData.depthDataAccuracy.rawValue,
            "depth-quality": depthData.depthDataQuality.rawValue,
            "point-cloud": pointCloud
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonDic) else {
            print("failed to serialize json data")
            return
        }
        // Send capture data
        Task {
            print("Sending Capture...")
            await sendCapture(data: jsonData)
            print("Capture Sent!")
        }
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

// MARK: sending capture
//https://www.hackingwithswift.com/books/ios-swiftui/sending-and-receiving-orders-over-the-internet
func sendCapture(data: Data) async {
    guard let url = URL(string: "http://192.168.1.30:8080/capture") else { // Internal network server address (Change to desired request destination)
        print("URL failed")
        return
    }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpMethod = "POST"
    
    do {
        let (data, urlRes) = try await URLSession.shared.upload(for: request, from: data)
        print(String(data: data, encoding: .utf8) ?? "Couldn't convert data to string")
        print(urlRes.url?.absoluteString ?? "couldn't find urlRes url string")
    } catch {
        print("Capture send request failed")
    }
}

// MARK: depth map conversion and lens distortion correction
//Convert CVPixelBuffer depth data to 2D float32 array and undistorts the points
func convertDepthData(depthData: AVDepthData) -> [[Float32]]? {
    
    let depthMap = depthData.depthDataMap
    
    let depthWidth = CVPixelBufferGetWidth(depthMap)
    let depthHeight = CVPixelBufferGetHeight(depthMap)
    let depthSize = CGSize(width: depthWidth, height: depthHeight)
    //768 X 576 (for photo), 768 X 432 (for the iFrame1280x720 format)
    
    //Compare the height and width with the camera intrisix reference dimensions object
    
    var convertedtDepthMap: [[Float32]] = []
    
    CVPixelBufferLockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
    let depthPointer = unsafeBitCast(CVPixelBufferGetBaseAddress(depthMap), to: UnsafeMutablePointer<Float32>.self)
    
    guard let intrinsicMatrix = depthData.cameraCalibrationData?.intrinsicMatrix else {
        // Has to break I guess its in the stack overflow guys method so idk but i guess this fails sometimes
        //So put up error message and manage failure from this method at UI level
        print("intrinsicMatrix failed")
        return nil
    }

    // Prepare for lens distortion correction
    guard let lut = depthData.cameraCalibrationData?.lensDistortionLookupTable else {
        //Camera calibration is optional so have to  handle potential nils????
        print("lensDistortionLookupTable failed")
        return nil
    }
    
    guard let correctedCenter = depthData.cameraCalibrationData?.lensDistortionCenter else {
        //Camera calibration is optional so have to  handle potential nils????
        print("lensDistortionCenter failed")
        return nil
    }
    
    for row in 0 ..< depthHeight {
        for col in 0 ..< depthWidth {
            let currentDepth = depthPointer[row * depthWidth + col]
            if currentDepth.isNaN || currentDepth.isZero {
                print("invalid depth \(currentDepth)")
                continue
            }
            
            let currentPoint = CGPoint(x: col, y: row)
            let correctedPoint: CGPoint = lensDistortionPoint(for: currentPoint, lookupTable: lut, distortionOpticalCenter: correctedCenter, imageSize: depthSize)
            
            let trueX: Float32 = (Float((correctedPoint.x)) - intrinsicMatrix[2][0]) * currentDepth / intrinsicMatrix[0][0]
            if trueX.isInfinite || trueX.isNaN {
                print("\(trueX): (\(correctedPoint.x) - \(intrinsicMatrix[2][0])) * \(currentDepth) / \(intrinsicMatrix[0][0])")
                continue
            }

            let trueY: Float32 = (Float(correctedPoint.y) - intrinsicMatrix[2][1]) * currentDepth / intrinsicMatrix[1][1]
            if trueY.isInfinite || trueY.isNaN {
                print("\(trueY): (\(correctedPoint.y) - \(intrinsicMatrix[2][1])) * \(currentDepth) / \(intrinsicMatrix[1][1])")
                continue
            }
            
            let point = [trueX, trueY, currentDepth]
            
            convertedtDepthMap.append(point)
        }
    }
    
    return convertedtDepthMap
}

// From AVCameraCalibrationData.h
func lensDistortionPoint(for point: CGPoint, lookupTable: Data, distortionOpticalCenter opticalCenter: CGPoint, imageSize: CGSize) -> CGPoint {
    // The lookup table holds the relative radial magnification for n linearly spaced radii.
    // The first position corresponds to radius = 0
    // The last position corresponds to the largest radius found in the image.

    // Determine the maximum radius.
    let delta_ocx_max = Float(max(opticalCenter.x, imageSize.width  - opticalCenter.x))
    let delta_ocy_max = Float(max(opticalCenter.y, imageSize.height - opticalCenter.y))
    let r_max = sqrt(delta_ocx_max * delta_ocx_max + delta_ocy_max * delta_ocy_max)

    // Determine the vector from the optical center to the given point.
    let v_point_x = Float(point.x - opticalCenter.x)
    let v_point_y = Float(point.y - opticalCenter.y)

    // Determine the radius of the given point.
    let r_point = sqrt(v_point_x * v_point_x + v_point_y * v_point_y)

    // Look up the relative radial magnification to apply in the provided lookup table
    let magnification: Float = lookupTable.withUnsafeBytes { (lookupTableValues: UnsafePointer<Float>) in
        let lookupTableCount = lookupTable.count / MemoryLayout<Float>.size

        if r_point < r_max {
            // Linear interpolation
            let val   = r_point * Float(lookupTableCount - 1) / r_max
            let idx   = Int(val)
            let frac  = val - Float(idx)

            let mag_1 = lookupTableValues[idx]
            let mag_2 = lookupTableValues[idx + 1]

            return (1.0 - frac) * mag_1 + frac * mag_2
        } else {
            return lookupTableValues[lookupTableCount - 1]
        }
    }

    // Apply radial magnification
    let new_v_point_x = v_point_x + magnification * v_point_x
    let new_v_point_y = v_point_y + magnification * v_point_y

    // Construct output
    return CGPoint(x: opticalCenter.x + CGFloat(new_v_point_x), y: opticalCenter.y + CGFloat(new_v_point_y))
}

