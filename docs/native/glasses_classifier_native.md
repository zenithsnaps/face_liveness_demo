# Glasses (sunglasses) classifier — native integration (Android + iOS)

The exported `glasses_sunglasses.tflite` is a single artifact that runs on
Flutter, native Android, and native iOS. The **preprocessing contract must be
identical on every platform** or scores drift:

```
crop face box (expanded ~0.6) → resize to 256×256 (bilinear)
→ NCHW float buffer (1,3,256,256), RGB channel-planar, values 0..255
→ run → output[0] = P(sunglasses)   → block if >= 0.5
```

`/255`, ImageNet normalization and `sigmoid` are baked into the model — do
**not** re-apply them in native code.

> NCHW = channel-planar: fill all 256×256 R values, then all G, then all B
> (not interleaved RGBRGB). This matches the Flutter `_buildInput`.

---

## Android (Kotlin) — `org.tensorflow:tensorflow-lite`

`app/build.gradle`:
```gradle
dependencies {
    implementation "org.tensorflow:tensorflow-lite:2.16.1"
    // optional NNAPI/GPU delegate:
    // implementation "org.tensorflow:tensorflow-lite-gpu:2.16.1"
}
android { aaptOptions { noCompress "tflite" } }   // keep model uncompressed
```

```kotlin
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder

class SunglassesClassifier(context: Context) {
    private val size = 256
    private val interpreter: Interpreter

    init {
        val fd = context.assets.openFd("flutter_assets/assets/models/glasses_sunglasses.tflite")
        fd.createInputStream().channel.use { ch ->
            val buf = ch.map(java.nio.channels.FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength)
            interpreter = Interpreter(buf, Interpreter.Options().apply { numThreads = 2 })
        }
    }

    /** [face] is the detected box; pass null to use the whole bitmap. */
    fun probaSunglasses(frame: Bitmap, face: Rect? = null): Float {
        val crop = expandClamp(face, frame.width, frame.height)
            ?: Rect(0, 0, frame.width, frame.height)
        val cropped = Bitmap.createBitmap(frame, crop.left, crop.top, crop.width(), crop.height())
        val resized = Bitmap.createScaledBitmap(cropped, size, size, /*filter=*/true)

        // NCHW: 3 planes of size*size floats, RGB, values 0..255
        val input = ByteBuffer.allocateDirect(1 * 3 * size * size * 4).order(ByteOrder.nativeOrder())
        val px = IntArray(size * size)
        resized.getPixels(px, 0, size, 0, 0, size, size)
        for (c in 0 until 3) {                       // R, then G, then B
            val shift = when (c) { 0 -> 16; 1 -> 8; else -> 0 }
            for (p in px) input.putFloat(((p shr shift) and 0xFF).toFloat())
        }
        input.rewind()

        val output = Array(1) { FloatArray(1) }
        interpreter.run(input, output)
        return output[0][0]
    }

    fun isWearingSunglasses(frame: Bitmap, face: Rect? = null) = probaSunglasses(frame, face) >= 0.5f

    private fun expandClamp(r: Rect?, w: Int, h: Int): Rect? {
        if (r == null) return null
        val dx = (r.width() * 0.6f).toInt(); val dy = (r.height() * 0.6f).toInt()
        return Rect(
            (r.left - dx).coerceAtLeast(0), (r.top - dy).coerceAtLeast(0),
            (r.right + dx).coerceAtMost(w), (r.bottom + dy).coerceAtMost(h),
        )
    }

    fun close() = interpreter.close()
}
```

> Asset path note: when bundled via Flutter the model lives under
> `flutter_assets/assets/models/…`. In a pure-native app, drop the `.tflite`
> in `src/main/assets/` and open `"glasses_sunglasses.tflite"` directly.

---

## iOS (Swift) — `TensorFlowLiteSwift`

`Podfile`:
```ruby
pod 'TensorFlowLiteSwift', '~> 2.16.0'
```

```swift
import TensorFlowLite
import CoreGraphics
import UIKit

final class SunglassesClassifier {
    private let size = 256
    private let interpreter: Interpreter

    init() throws {
        // Flutter bundles assets under the app bundle; adjust subdir as needed.
        guard let path = Bundle.main.path(
            forResource: "glasses_sunglasses", ofType: "tflite",
            inDirectory: "flutter_assets/assets/models") else { throw Err.modelMissing }
        var opts = Interpreter.Options(); opts.threadCount = 2
        interpreter = try Interpreter(modelPath: path, options: opts)
        try interpreter.allocateTensors()
    }

    enum Err: Error { case modelMissing, badImage }

    /// `face` in pixel coords of `image`; pass nil to use the whole image.
    func probaSunglasses(_ image: UIImage, face: CGRect? = nil) throws -> Float {
        guard let cg = image.cgImage else { throw Err.badImage }
        let full = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let crop = (face.map { expandClamp($0, full) }) ?? full
        guard let cropped = cg.cropping(to: crop) else { throw Err.badImage }

        // draw into a 256×256 RGBA8888 context (bilinear via interpolation)
        let bytesPerRow = size * 4
        var rgba = [UInt8](repeating: 0, count: size * size * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Err.badImage }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: size, height: size))

        // NCHW: R plane, then G, then B; values 0..255 as Float32
        var input = [Float32](repeating: 0, count: 3 * size * size)
        let plane = size * size
        for i in 0..<plane {
            let o = i * 4
            input[i]             = Float32(rgba[o])       // R
            input[plane + i]     = Float32(rgba[o + 1])   // G
            input[2 * plane + i] = Float32(rgba[o + 2])   // B
        }
        try input.withUnsafeBufferPointer {
            try interpreter.copy(Data(buffer: $0), toInputAt: 0)
        }
        try interpreter.invoke()
        let out = try interpreter.output(at: 0)
        return out.data.withUnsafeBytes { $0.load(as: Float32.self) }
    }

    func isWearingSunglasses(_ image: UIImage, face: CGRect? = nil) -> Bool {
        (try? probaSunglasses(image, face: face)).map { $0 >= 0.5 } ?? false
    }

    private func expandClamp(_ r: CGRect, _ bounds: CGRect) -> CGRect {
        r.insetBy(dx: -r.width * 0.6, dy: -r.height * 0.6).intersection(bounds)
    }
}
```

---

## Parity checklist (all three platforms)

1. **RGB order**, not BGR. (Android `getPixels` is ARGB → shift 16/8/0 = R/G/B.)
2. **NCHW channel-planar** buffer, not interleaved.
3. Pixel values **0..255 float**, no `/255`, no normalization, no sigmoid.
4. Resize to exactly **256×256** with bilinear/high interpolation.
5. Crop = face box **expanded by 0.6**, clamped to image (or whole frame).
6. Block when output **≥ 0.5**.

Sanity-check a port by running it on `tools/glasses_export/` sample frames and
confirming proba ≈ {0.99, 0.96, 0.91, 0.97, 0.06}.
