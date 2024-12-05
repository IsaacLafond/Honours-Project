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
    @State var pixel: CGPoint? = nil
    @State var show_alert: Bool = false
    @State var status: Status = .awaiting_input
    enum Status {
        case awaiting_input
        case complete
        case pending
        case failed
    }
    
    var body: some View {
        ZStack {
            Color.black
            
            if let capture = capture {
                VStack {
                    switch status {
                    case .awaiting_input:
                        VStack {
                            if let image = UIImage(data: capture.fileDataRepresentation()!) {
                                PointsView(image: Image(uiImage: image), pixel: $pixel)
                            } else {
                                Text("Image capture failed try again")
                            }
                            Button { // action on click
                                if let pixel = pixel {
                                    Task {
                                        //Get image data
                                        guard let imageData = capture.fileDataRepresentation() else {
                                            status = .failed
                                            result = "could not get image data"
                                            return
                                        }
                                        //Get image depth data
                                        guard let depthData = capture.depthData?.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32) else {
                                            status = .failed
                                            result = "failed to get and convert depth data"
                                            return
                                        }
                                        let depthMap = depthData.depthDataMap
                                        guard let calibrationData = depthData.cameraCalibrationData else {
                                            status = .failed
                                            result = "nil calibration data"
                                            return
                                        }
                                        status = .pending
                                        await sendCapture(data: wrapEstimateImageData(image: imageData.base64EncodedString(), depthData: depthData, depthMap: depthMap, calibration: calibrationData, platePoint: pixel))
                                    }
                                } else {
                                    show_alert = true
                                }
                            } label: {
                                Text("Submit")
                            }
                        }
                        .alert("Select a pixel on the plate.", isPresented: $show_alert) {
                            Button("OK", role: .cancel) {}
                        }
                        case .complete:
                            // show image
                            Image(uiImage: UIImage(data: capture.fileDataRepresentation()!) ?? UIImage(systemName: "exclamationmark.triangle")!)
                                .resizable()
                                .scaledToFit()
                                .padding()
                        case .pending:
                            // Show loading
                            VStack {
                                ProgressView()
                                    .padding()
                                Text("Fetching Results...")
                            }
                        case .failed:
                            // Show warning text below will explain error
                            Image(systemName: "exclamationmark.triangle")
                                .padding()
                        }
                        Text(result)
                    }
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
            status = .failed
            result = "URL failed"
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        
        do {
            let (data, _) = try await URLSession.shared.upload(for: request, from: data)
            if let string_data = String(data: data, encoding: .utf8) {
                status = .complete
                result = string_data
            } else {
                status = .failed
                result = "Couldn't convert data to string"
            }
        } catch {
            status = .failed
            result = "Capture send request failed"
        }
    }
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
    calibration: AVCameraCalibrationData,
    platePoint: CGPoint) -> Data {
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
        "depth_quality" : depthData.depthDataQuality.rawValue,
        "depth_accuracy" : depthData.depthDataAccuracy.rawValue,
        "plate_point" : [
            Int(platePoint.x),
            Int(platePoint.y)
        ]
    ]
    let jsonStringData = try! JSONSerialization.data(
        withJSONObject: jsonDict,
        options: .prettyPrinted
    )
    return jsonStringData
}



#Preview {
    ResultView(capture: nil)
}
