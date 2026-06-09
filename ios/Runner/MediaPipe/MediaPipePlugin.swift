import Flutter
import Foundation

/// Single MethodChannel handler bridging Flutter to MediaPipe Tasks Vision
/// (HandLandmarker + ObjectDetector + FaceDetector + FaceLandmarker). Mirrors `MediaPipePlugin.kt` on Android.
///
/// Method names (must match `MediaPipeChannel` on the Dart side):
///   - "initialize"
///   - "detectHands"
///   - "detectObjects"
///   - "detectFaces"
///   - "detectFaceLandmarks"
///   - "dispose"
enum MediaPipePlugin {
    private static let channelName = "app.mymo/mediapipe"
    private static var handBridge: HandAnalyzerBridge?
    private static var objectBridge: ObjectAnalyzerBridge?
    private static var faceBridge: FaceDetectorBridge?
    private static var faceLandmarkerBridge: FaceLandmarkerBridge?
    private static var glassesBridge: GlassesClassifierBridge?
    private static let workQueue = DispatchQueue(label: "app.mymo.mediapipe", qos: .userInitiated)

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            workQueue.async {
                handle(call: call, result: result)
            }
        }
    }

    private static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            switch call.method {
            case "initialize":
                if handBridge == nil { handBridge = try HandAnalyzerBridge() }
                if objectBridge == nil { objectBridge = try ObjectAnalyzerBridge() }
                if faceBridge == nil { faceBridge = try FaceDetectorBridge() }
                if faceLandmarkerBridge == nil { faceLandmarkerBridge = try FaceLandmarkerBridge() }
                // Fail-soft: a missing/incompatible glasses model must not abort
                // initialize and take the core hand/face/object tasks down with it.
                // When absent, the sunglasses check skips itself (caller treats the
                // classify error as Err → fail-open).
                if glassesBridge == nil { glassesBridge = try? GlassesClassifierBridge() }
                DispatchQueue.main.async { result(nil) }
            case "detectHands":
                guard let frame = FrameArgs.fromAny(call.arguments) else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "BAD_ARGS", message: "expected Map", details: nil))
                    }
                    return
                }
                if handBridge == nil { handBridge = try HandAnalyzerBridge() }
                let hands = try handBridge!.detect(frame: frame)
                DispatchQueue.main.async { result(hands) }
            case "detectObjects":
                guard let frame = FrameArgs.fromAny(call.arguments) else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "BAD_ARGS", message: "expected Map", details: nil))
                    }
                    return
                }
                if objectBridge == nil { objectBridge = try ObjectAnalyzerBridge() }
                let objs = try objectBridge!.detect(frame: frame)
                DispatchQueue.main.async { result(objs) }
            case "detectFaces":
                guard let frame = FrameArgs.fromAny(call.arguments) else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "BAD_ARGS", message: "expected Map", details: nil))
                    }
                    return
                }
                if faceBridge == nil { faceBridge = try FaceDetectorBridge() }
                let faces = try faceBridge!.detect(frame: frame)
                DispatchQueue.main.async { result(faces) }
            case "detectFaceLandmarks":
                guard let frame = FrameArgs.fromAny(call.arguments) else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "BAD_ARGS", message: "expected Map", details: nil))
                    }
                    return
                }
                if faceLandmarkerBridge == nil { faceLandmarkerBridge = try FaceLandmarkerBridge() }
                let landmarkResult = try faceLandmarkerBridge!.detect(frame: frame)
                DispatchQueue.main.async { result(landmarkResult) }
            case "classifyGlasses":
                guard let map = call.arguments as? [String: Any],
                      let frame = FrameArgs.fromAny(call.arguments) else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "BAD_ARGS", message: "expected Map", details: nil))
                    }
                    return
                }
                if glassesBridge == nil { glassesBridge = try GlassesClassifierBridge() }
                // Optional normalized [0,1] ROI: {left, top, width, height}.
                var roi: CGRect?
                if let r = map["roi"] as? [String: Any],
                   let l = (r["left"] as? NSNumber)?.doubleValue,
                   let t = (r["top"] as? NSNumber)?.doubleValue,
                   let w = (r["width"] as? NSNumber)?.doubleValue,
                   let h = (r["height"] as? NSNumber)?.doubleValue {
                    roi = CGRect(x: l, y: t, width: w, height: h)
                }
                let proba = try glassesBridge!.classify(frame: frame, roi: roi)
                DispatchQueue.main.async { result(proba) }
            case "encodeFrameToJpeg":
                guard let map = call.arguments as? [String: Any],
                      let frame = FrameArgs.fromAny(call.arguments),
                      let outPath = map["outPath"] as? String else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "BAD_ARGS", message: "expected Map with outPath", details: nil))
                    }
                    return
                }
                let quality = (map["quality"] as? Int) ?? 90
                let path = JpegEncoderBridge.encode(frame: frame, quality: quality, outPath: outPath)
                DispatchQueue.main.async { result(path) }
            case "decodeUprightRgba":
                guard let frame = FrameArgs.fromAny(call.arguments) else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "BAD_ARGS", message: "expected Map", details: nil))
                    }
                    return
                }
                let decoded = UprightRgbaBridge.decode(frame: frame)
                DispatchQueue.main.async { result(decoded) }
            case "dispose":
                handBridge = nil
                objectBridge = nil
                faceBridge = nil
                faceLandmarkerBridge = nil
                glassesBridge = nil
                DispatchQueue.main.async { result(nil) }
            default:
                DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
            }
        } catch {
            DispatchQueue.main.async {
                result(FlutterError(code: "MEDIAPIPE_ERROR", message: "\(error)", details: nil))
            }
        }
    }
}

/// Frame shape as sent by the Flutter side (see `MediaPipeChannel._encodeFrame`).
struct FrameArgs {
    let bytes: Data
    let width: Int
    let height: Int
    let rotation: Int
    let format: String

    static func fromAny(_ any: Any?) -> FrameArgs? {
        guard let map = any as? [String: Any] else { return nil }
        let rawBytes: Data?
        if let flutter = map["bytes"] as? FlutterStandardTypedData {
            rawBytes = flutter.data
        } else if let data = map["bytes"] as? Data {
            rawBytes = data
        } else {
            rawBytes = nil
        }
        guard
            let bytes = rawBytes,
            let width = map["width"] as? Int,
            let height = map["height"] as? Int,
            let rotation = map["rotation"] as? Int,
            let format = map["format"] as? String
        else {
            return nil
        }
        return FrameArgs(bytes: bytes, width: width, height: height, rotation: rotation, format: format)
    }
}
