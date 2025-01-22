### Convert RGB to YpCbCr using vImageMatrixMultiply_PlanarF

Step 1: The interleaved 8-bit RGBA CGImage object is converted to vImage_Buffer object whose rectangular region pointed to by its data `property` is populated with 32-bit RGB pixels.


Step 2: Split the interleaved floating point RGB pixels of the vImage_Buffer into 3 distinct vImage_Buffers by calling the function `vImageConvert_RGBFFFtoPlanarF`

Step 3: Call the function `vImageMatrixMultiply_PlanarF` to convert the RGB pixels into YpCbCr pixels. The YpCbCr pixels are stored in 3 separate destination vImage_Buffers.

Step 4: Use the function call `vImageConvert_PlanarToChunkyF` to convert the destination  vImage_Buffers into a single vImage_Buffer, *yCbCrBufferFFF*. The YpCbCr pixels in this latter vImage_Buffer are in the order CrYpCb and are still in floating point numbers.

Step 5: Finally, call the function `vImageConvert_RGBFFFtoRGB888_dithered` to convert the floating point values to an interleaved 8-bit format. The pixels in the rectangular region of `destinationBuffer888` are  in {Cr Yp Cb} chunks. Each chunk can be decoded into RGB format if required.

We can convert the YpCbCr pixels in `destinationBuffer888` back RGBA using the function call `vImageConvert_444CrYpCb8ToARGB8888`.

Development Platform:

    XCode 11.6 or later

System Requirements:

    macOS 10.15.x or later
    iOS 13.x or later



Weblinks:

https://stackoverflow.com/questions/39928524/how-to-use-vimagematrixmultiply-in-swift-3

https://web.archive.org/web/20180423091842/http://www.equasys.de/colorconversion.html


