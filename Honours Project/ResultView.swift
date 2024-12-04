//
//  ResultView.swift
//  Honours Project
//
//  Created by Isaac Lafond on 2024-11-25.
//

import SwiftUI
import AVFoundation

struct ResultView: View {
    let capture: AVCapturePhoto?
    @State var result: String = ""
    
    var body: some View {
        ZStack {
            Color.black
            
            if let capture = capture {
//                ScrollView {
                    VStack {
                        Text("Time: \(capture.timestamp.seconds)\n")
                        Text("Setting: \(capture.resolvedSettings.debugDescription)\n")
                            .foregroundStyle(.white)
                        Text("Buffer: \(capture.pixelBuffer.debugDescription)\n")
                            .foregroundStyle(.white)
                        Text("File rep: \(capture.fileDataRepresentation()?.description ?? "nil")")
                        Text("Camera calibration: \(capture.cameraCalibrationData.debugDescription)\n")
                            .foregroundStyle(.white)
//                        Text
                        Text("Depth data: \(capture.depthData.debugDescription)\n")
                        Text(result)
                    }.task {
//                        await sendCapture(data: { // Inline building of the data object to be sent using closure
//                            // Prepare data for POST request
//                            let jsonDic: [String: Any] = [
//                                "test": "test"
//                            ]
//                            guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonDic) else {
//                                print("failed to serialize json data")
//                                return Data()
//                            }
//                            return jsonData
//                        }())
                        //Get image data
                        guard let imageData = capture.fileDataRepresentation() else {
                            result = "could not get image data"
                            return
                        }
                        //Get image depth data
                        guard let depthData = capture.depthData?.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32) else {
                            result = "failed to get and convert depth data"
                            return
                        }
                        let depthMap = depthData.depthDataMap
                        guard let calibrationData = depthData.cameraCalibrationData else {
                            result = "nil calibration data"
                            return
                        }
                        await sendCapture(data: wrapEstimateImageData(image: imageData.base64EncodedString() ,depthData: depthData, depthMap: depthMap, calibration: calibrationData))
                    }
//                }
            } else {
                Text("nil capture")
                    .foregroundStyle(.white)
            }
        }
    }
    
    // MARK: sending capture
    //https://www.hackingwithswift.com/books/ios-swiftui/sending-and-receiving-orders-over-the-internet
    func sendCapture(data: Data) async {
        guard let url = URL(string: "http://192.168.1.30:8080/capture") else { // Internal network server address (Change to desired request destination)
            print("URL failed")
            result = "URL failed"
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        
        do {
            let (data, urlRes) = try await URLSession.shared.upload(for: request, from: data)
            result = String(data: data, encoding: .utf8) ?? "Couldn't convert data to string"
        } catch {
            result = "Capture send request failed"
        }
    }
}

// MARK: depth map conversion and lens distortion correction
//Convert CVPixelBuffer depth data to 2D float32 array and undistorts the points
func convertAndRectDepthData(depthData: AVDepthData) -> [[Float32]]? {
    
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
    CVPixelBufferLockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
    return convertedtDepthMap
}

// Passing a filtered depth data map doesn't require the finite/nan checks
func convertDepthData(depthMap: CVPixelBuffer) -> [[Float32]] {
    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)
    var convertedDepthMap: [[Float32]] = Array(
        repeating: Array(repeating: 0, count: width),
        count: height
    )
    CVPixelBufferLockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 2))
    let floatBuffer = unsafeBitCast(
        CVPixelBufferGetBaseAddress(depthMap),
        to: UnsafeMutablePointer<Float32>.self
    )
    for row in 0 ..< height-1 {
        for col in 0 ..< width-1 {
            let currentDepth = floatBuffer[row * width + col]
//            if currentDepth.isFinite {
                convertedDepthMap[row][col] = currentDepth
//            } else if currentDepth.isNaN {
//                print("NaN")
//            } else if currentDepth.isInfinite {
//                print("inf")
//            } else if currentDepth.isZero {
//                print("0")
//            } else {
//                print("some other form unknown")
//            }
        }
    }
    CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 2))
    return convertedDepthMap
}

func convertLensDistortionLookupTable(lookupTable: Data) -> [Float] {
    let tableLength = lookupTable.count / MemoryLayout<Float>.size
    var floatArray: [Float] = Array(repeating: 0, count: tableLength)
    _ = floatArray.withUnsafeMutableBytes{lookupTable.copyBytes(to: $0)}
    return floatArray
}

func wrapEstimateImageData(
    image: String,
    depthData: AVDepthData,
    depthMap: CVPixelBuffer,
    calibration: AVCameraCalibrationData) -> Data {
    let jsonDict: [String : Any] = [
        "image" : image,
        "calibration_data" : [
            "intrinsic_matrix" : (0 ..< 3).map{ x in
                (0 ..< 3).map{ y in calibration.intrinsicMatrix[x][y]}
            },
            "pixel_size" : calibration.pixelSize,
            "intrinsic_matrix_reference_dimensions" : [
                calibration.intrinsicMatrixReferenceDimensions.width,
                calibration.intrinsicMatrixReferenceDimensions.height
            ],
            "lens_distortion_center" : [
                calibration.lensDistortionCenter.x,
                calibration.lensDistortionCenter.y
            ],
            "lens_distortion_lookup_table" : convertLensDistortionLookupTable(
                lookupTable: calibration.lensDistortionLookupTable!
            ),
            "inverse_lens_distortion_lookup_table" : convertLensDistortionLookupTable(
                lookupTable: calibration.inverseLensDistortionLookupTable!
            )
        ],
        "depth_data" : convertDepthData(depthMap: depthMap),
        "point_cloud" : convertAndRectDepthData(depthData: depthData) ?? "nil"
    ]
    let jsonStringData = try! JSONSerialization.data(
        withJSONObject: jsonDict,
        options: .prettyPrinted
    )
    return jsonStringData
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




#Preview {
    ResultView(capture: nil)
}
