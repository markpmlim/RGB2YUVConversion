
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import ImageIO
import Accelerate.vImage

guard let url = Bundle.main.url(forResource: "Flowers_1",
                                withExtension: "png")
else {
    fatalError("Can't load the resource file")
}
let options = [kCGImageSourceShouldCache : true] as CFDictionary

guard let cgImageSource = CGImageSourceCreateWithURL(url as CFURL,
                                                     options)
else {
    fatalError("Can't create the CoreImage Source")
}

// `cgImage` has a bitmapInfo of 3 (non-premultiplied RGBA)
guard let cgImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, options)
else {
    fatalError("Can't create the CGImage object")
}

// Initialize an Image Format and vImage Buffers
// bitmapInfo: order32Little+none+floatComponents --> RGB (0x2100/8448)
// Assume each 4 bytes of Floats are stored in Little-Endian format.
var floatBitmapInfo = CGBitmapInfo(rawValue:
    CGBitmapInfo.floatComponents.rawValue |
    CGImageAlphaInfo.none.rawValue |
    CGImageByteOrderInfo.order32Little.rawValue)

var cgImageFormat = vImage_CGImageFormat(
    bitsPerComponent: 32,
    bitsPerPixel: 32 * 3,
    colorSpace: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: floatBitmapInfo,
    renderingIntent: .defaultIntent)!

// Convert the 8-bit non-premultiplied RGBA CGImage object to
// interleaved RGBFFF source buffer
guard var sourceBufferRGBFFF = try? vImage_Buffer(cgImage: cgImage,
                                                  format: cgImageFormat)
else {
    fatalError("Can't create the source buffer")
}

// Debugging:
var bufferPtr = sourceBufferRGBFFF.data.assumingMemoryBound(to: Float.self)
for j in 0 ..< 2 * cgImageFormat.componentCount {
    print(bufferPtr[j], terminator: " ")
}
print()
/* */

// Prepare 3 vImage_Buffers as the source planes.
// You are responsible for filling out the height, width, and rowBytes fields of this structure,
// and for allocating a data buffer of the appropriate size.
var sourceBuffers: [vImage_Buffer] = (0...2).map {
    (index: Int) in
    //print("Initialising input buffer \(index)");
    var buffer = vImage_Buffer()
    buffer.width = sourceBufferRGBFFF.width
    buffer.height = sourceBufferRGBFFF.height
    buffer.rowBytes = Int(buffer.width) * MemoryLayout<Float>.size
    buffer.data = malloc(buffer.rowBytes * Int(buffer.height))
    return buffer
}

// Prepare 3 vImage_Buffers as the destination planes
var destinationBuffers: [vImage_Buffer] = (0...2).map {
    (index: Int) in
    //print("Initialising output buffer \(index)");
    var buffer = vImage_Buffer()
    buffer.width = sourceBufferRGBFFF.width
    buffer.height = sourceBufferRGBFFF.height
    buffer.rowBytes = Int(buffer.width) * MemoryLayout<Float>.size
    buffer.data = malloc(buffer.rowBytes * Int(buffer.height))
    return buffer
}

// `yuvMatrix` needs to hold `src_planes` x `dest_planes` elements
// Full-range color format is used for JPEG images
let yuvMatrix: [Float] = [
    0.299, -0.169,  0.500,  // column 0
    0.587, -0.331, -0.419,  // column 1
    0.114,  0.500, -0.081   // column 2
]

// array of 3 floats
let preBias: [Float] = [0.0, 0.0, 0.0]
let postBias: [Float] = [0.0, 0.5, 0.5]

// You need to use pointers or BufferPointers inside the closure
sourceBuffers.withUnsafeBufferPointer {
    (sourceBuffersBP: UnsafeBufferPointer) in
    destinationBuffers.withUnsafeBufferPointer {
        destinationBuffersBP in

        // Prepare an array of pointers, each pointing to a source vImage_Buffer
        var sourceBufferPointers: [UnsafePointer<vImage_Buffer>?] =
            sourceBuffers.withUnsafeBufferPointer {
                (sourceBuffersBP: UnsafeBufferPointer) in
                (0...2).map { sourceBuffersBP.baseAddress! + $0 }
        }

        // Split the interleaved floating point RGB pixels into 3 distinct vImage_Buffers.
        vImageConvert_RGBFFFtoPlanarF(
            &sourceBufferRGBFFF,        // rgbSrc
            sourceBufferPointers[0]!,   // redDest
            sourceBufferPointers[1]!,   // greenDest
            sourceBufferPointers[2]!,   // blueDest
            UInt32(kvImageNoFlags))

        // Prepare an array of pointers, each pointing to a destination vImage_Buffer
        var destinationBufferPointers: [UnsafePointer<vImage_Buffer>?] =
            destinationBuffers.withUnsafeBufferPointer {
                destinationBuffersBP in
                (0...2).map { destinationBuffersBP.baseAddress! + $0 }
        }

        // With all things prepared properly, now call `vImageMatrixMultiply_PlanarF`
        // No divisor is needed for `vImageMatrixMultiply_PlanarF`
        vImageMatrixMultiply_PlanarF(
            &sourceBufferPointers,      // srcs
            &destinationBufferPointers, // dests
            3,                          // # of src_planes
            3,                          // # of dest_planes
            yuvMatrix,                  // applying matrix
            preBias,                    // pre_bias
            postBias,                   // post_bias
            UInt32(kvImageNoFlags))
    }
}

// The Yp, Cb and Cr floating point values are in 3 separate planes.
// We can merge their values in chunks of values. The order in each chunk is Cr Yp Cb.
var yCbCrBufferFFF = try! vImage_Buffer(
    width: cgImage.width,
    height: cgImage.height,
    bitsPerPixel: 32*3)
// print(yCbCrBufferFFF)

// All source buffers must have the same dimensions (width and height)
// but their `rowBytes` may be different.
_ = withUnsafePointer(to: destinationBuffers[2]) {
    (cr: UnsafePointer<vImage_Buffer>) in
    withUnsafePointer(to: destinationBuffers[0]) {
        (y: UnsafePointer<vImage_Buffer>) in
        withUnsafePointer(to: destinationBuffers[1]) {
            (cb: UnsafePointer<vImage_Buffer>) in
            withUnsafePointer(to: yCbCrBufferFFF) {
                (yCbCr: UnsafePointer<vImage_Buffer>) in

                var srcPlanarBuffers = [Optional(cr), Optional(y), Optional(cb)]
                var destChannels = [
                    yCbCr.pointee.data,
                    yCbCr.pointee.data.advanced(by: MemoryLayout<Float>.stride),
                    yCbCr.pointee.data.advanced(by: MemoryLayout<Float>.stride*2)
                ]

                let channelCount = 3

                _ = vImageConvert_PlanarToChunkyF(
                    &srcPlanarBuffers,
                    &destChannels,
                    UInt32(channelCount),
                    MemoryLayout<Float>.stride * channelCount,
                    vImagePixelCount(cgImage.width),
                    vImagePixelCount(cgImage.height),
                    yCbCr.pointee.rowBytes,
                    vImage_Flags(kvImageNoFlags))
            }
        }
    }
}

/*
 // Now, `yCbCrBufferFFF` has interleaved CrYpCb (float) pixels.
 // Convert float destinationBuffer to 8-bit
 bufferPtr = yCbCrBufferFFF.data.assumingMemoryBound(to: Float.self)
 for j in 0 ..< 2 * cgImageFormat.componentCount {
 print(bufferPtr[j], terminator: " ")
 }
 print()
 */

// Convert floats in `yCbCrBufferFFF` to 8-bit format
var destinationBuffer888 = vImage_Buffer()
error = vImageBuffer_Init(
    &destinationBuffer888,
    yCbCrBufferFFF.height,
    yCbCrBufferFFF.width,
    8 * 3,
    vImage_Flags(kvImagePrintDiagnosticsToConsole))

let maxFloat: [Float] = [1.0, 1.0, 1.0]
let minFloat: [Float] = [0.0, 0.0, 0.0]
error = vImageConvert_RGBFFFtoRGB888_dithered(
    &yCbCrBufferFFF,                    //  src
    &destinationBuffer888,              // dest
    maxFloat,
    minFloat,
    Int32(kvImageConvert_DitherNone),   // dithering type
    vImage_Flags(0))

/*
 // `destinationBuffer8` is now populated with interleaved 8-bit CrYpCr chunks.
 var bytePtr = destinationBuffer888.data.assumingMemoryBound(to: UInt8.self)
 for i in 0 ..< 2 * cgImageFormat.componentCount {
 print(String(format: "0x%02X", bytePtr[i]), terminator: " ")
 }
 print()
 */

//// Convert the interleaved 8-bit CrYpCr chunks to interleaved ARGB pixels
func configureInfo() -> vImage_YpCbCrToARGB
{
    var info = vImage_YpCbCrToARGB()    // filled with zeroes

    // full range 8-bit, clamped to full range
    var pixelRange = vImage_YpCbCrPixelRange(
        Yp_bias: 0,
        CbCr_bias: 128,
        YpRangeMax: 255,
        CbCrRangeMax: 255,
        YpMax: 255,
        YpMin: 1,
        CbCrMax: 255,
        CbCrMin: 0)

    // The contents of `info` object is initialised by the call below. It
    // will be used by the function vImageConvert_444CrYpCb8ToARGB8888
    _ = vImageConvert_YpCbCrToARGB_GenerateConversion(
        kvImage_YpCbCrToARGBMatrix_ITU_R_601_4,
        &pixelRange,
        &info,
        kvImage444CrYpCb8,      // vImageYpCbCrType (OSType:v308)
        kvImageARGB8888,        // vImageARGBType
        vImage_Flags(kvImageDoNotTile))

    return info
}

var infoYpCbCrToARGB = configureInfo()
var rgbaDestinationBuffer = try! vImage_Buffer(
    width: cgImage.width,
    height: cgImage.height,
    bitsPerPixel: 32)
// print(rgbaDestinationBuffer)

// Note: the order in each chunk is Cr Yp Cb
// Each {Cr Yp Cb} will be decoded as R G B A
var error = vImageConvert_444CrYpCb8ToARGB8888(
    &destinationBuffer888,  //  src
    &rgbaDestinationBuffer, // dest
    &infoYpCbCrToARGB,
    [1,2,3,0],              // XRGB -> RGBX
    255,
    vImage_Flags(kvImagePrintDiagnosticsToConsole))

// `rgbaDestinationBuffer` is populated with 8-bit interleaved RGBA pixels
let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
cgImageFormat = vImage_CGImageFormat(
    bitsPerComponent: 8,
    bitsPerPixel: 8 * 4,
    colorSpace: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: bitmapInfo,
    renderingIntent: .defaultIntent)!

let cgImage2 = try rgbaDestinationBuffer.createCGImage(format: cgImageFormat)
// prints 5 (noneSkipLast - RGBX)
//print(cgImage2.bitmapInfo.rawValue)
// Cleanup
// Free the memory allocated to the various vImage_Buffer objects.
sourceBufferRGBFFF.free()
for i in 0...2 {
    sourceBuffers[i].free()
    destinationBuffers[i].free()
}

yCbCrBufferFFF.free()
destinationBuffer888.free()
rgbaDestinationBuffer.free()
