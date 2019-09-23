//
//  HairSegmentController.swift
//  Segment
//
//  Created by ben on 2019/7/17.
//  Copyright © 2019 ben. All rights reserved.
//

import UIKit
import Vision

class HairSegmentController: UIViewController {

    @IBOutlet weak var imageView: UIImageView!
    var imagePicker = UIImagePickerController()
    let capturer = CustomCameraCapturer()
    var startTime = CFAbsoluteTime()
    var endTime = CFAbsoluteTime()
    fileprivate var maskOutput: UIImage?
    fileprivate var original: UIImage?
    fileprivate var bg: UIImage = UIImage(named: "bgimg")!
    var discard = 0
    
    
    
    
    lazy var request = hairSegmentRequest(model: frontcam_test3_lesstrained().model)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.contentMode = .scaleAspectFit
        capturer.segmentation = self
        capturer.initCapture()
    }
    
    @IBAction func selectImage() {
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            self.imagePicker.delegate = self
            self.imagePicker.sourceType = .photoLibrary
            self.imagePicker.allowsEditing = false
            self.present(self.imagePicker, animated: true)
        } else {
            print("Photo library is not available")
        }
    }
    
    
    
    
    @IBAction func switchCamera(_ sender: Any) {
        if capturer != nil{
            capturer.switchCameraTapped()
        }
        
        
        
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */
   
    // MARK: - fuctions relative to CoreML
    
    /**
     Create a hair segmentation request.
     
     - Parameters:
     model: MLModel: deep learning model.
     
     - Returns: VNCoreMLRequest
     */
    func hairSegmentRequest(model: MLModel)->VNCoreMLRequest {
        do {
            let model = try VNCoreMLModel(for: model)
            
            let request = VNCoreMLRequest(model: model, completionHandler: {
                [weak self] request, error in
                self?.updateSegmentedImage(for: request, error: error)
            })
            // MARK: - scale input with vision
            request.imageCropAndScaleOption = .scaleFill
            return request
        } catch {
            fatalError("Fail to load ML model: \(error)")
        }
    }
    
    /**
     A hook to process the result returned by request.
     
     - Parameters:
     for: VNRequest:
     error: Error?:
     */
    func updateSegmentedImage(for request:VNRequest, error: Error?) {
        guard let result = request.results else {
            return
        }
        
        let segmentResult = result as! [VNPixelBufferObservation]
        
        
        if segmentResult.isEmpty {
            print("Request return empty observation")
        } else {
            let buffer = segmentResult.last?.pixelBuffer
            guard let segmentedMaskImage = buffer?.toUIImage() else { return }
            guard let input = original else {
                print("Image not available")
                return
            }
         //self.maskOutput = segmentedMaskImage.resize(to: input.size)
          //  let y = self.postProcessing()
            DispatchQueue.main.async {
                guard let input = self.imageView.image else {
                    print("Image not available")
                    return
                    
                }
                self.endTime = CFAbsoluteTimeGetCurrent()
                print("End time is \(self.endTime)")
                print("Time \((self.endTime - self.startTime)*1000)")
                self.maskOutput = segmentedMaskImage.resize(to: input.size)
                self.bg = self.bg.resize(to: input.size)!
                self.imageView.image = self.postProcessing()
            }
        }
    }
    
    
    /**
     Wrap the CVPixelBuffer and perform the request.

     - Parameters:
     buffer cvPixelBuffer: CVPixelBuffer: input image.
     */
    func segmentSeq(buffer cvPixelBuffer: CVPixelBuffer) {
        let handler = VNSequenceRequestHandler()
        do {
           // startTime = CFAbsoluteTime()
            try handler.perform([self.request],
                                on: cvPixelBuffer,
                                orientation: .up)
            endTime = CFAbsoluteTime()
            print("Time \((self.endTime - self.startTime)*1000)")
        } catch {
            print("Fail to perform segment: \(error.localizedDescription)")
        }
    }

    @IBAction func hairSegment(_ sender: Any) {
        guard let buffer = imageView.image?.pixelBuffer() else {
            return
        }
        segmentSeq(buffer: buffer)
        
    }
}

// MARK: - UIImagePickerControllerDelegate

extension HairSegmentController: UIImagePickerControllerDelegate,
                                 UINavigationControllerDelegate {
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.dismiss(animated: true)
    }
    
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        /*if let pickedImage = info[UIImagePickerControllerOriginalImage]  as? UIImage {
            self.imageView.image = pickedImage
            self.imageView.backgroundColor = .clear
        }
        self.dismiss(animated: true)*/
    }
}

extension HairSegmentController: SegmentationDelegate{
    func segment(image: UIImage) {
        

        /*DispatchQueue.main.async {
            
            self.imageView.image = image
            
            
        }*/
        
        
       /* if discard <= 3 {
            discard = discard + 1
            print("Discarding")
            return
        }
        print("Processing")
        discard = 0*/
        
        
        /*DispatchQueue.main.async {
            
            self.imageView.image = image
            
        }*/
        self.original = image
        guard let buffer = image.pixelBuffer() else {
            return
        }
        startTime = CFAbsoluteTimeGetCurrent()
        
        segmentSeq(buffer: buffer)
    }
    
    //MARK: Action
    
    
    
    
    
    
    
}
extension HairSegmentController{
    
    func postProcessing() -> UIImage{
        
        if (original == nil){
            return bg
        }
        if (maskOutput == nil){
            return bg
        }
        
        let fg = self.overLay(original: self.original!, mask: maskOutput!)
        let finalImg = self.merge(bg: self.bg, fg: fg);
        return finalImg
    }
    func merge(bg: UIImage, fg: UIImage) -> UIImage {
        
        return UIImage.imageByMergingImages(topImage: fg, bottomImage: bg)
        
    }
    
}
extension HairSegmentController{
    
    func overLay(original: UIImage, mask: UIImage) -> UIImage{
        /*var size = CGSize(width: original.size.width, height: original.size.height)
         UIGraphicsBeginImageContext(size)
         
         let areaSize = CGRect(x: 0, y: 0, width: size.width, height: size.height)
         original.draw(in: areaSize)
         
         mask.draw(in: areaSize, blendMode: .normal, alpha: 0.8)
         
         var newImage:UIImage = UIGraphicsGetImageFromCurrentImageContext()!
         UIGraphicsEndImageContext()
         
         let ms = UIImage(cgImage: CGImage.masking(mask.cgImage))
         
         return ms*/
        
        return maskImage(image: original, mask: invert(originalImage:mask))
        
        
    }
    
    func invert(originalImage: UIImage) -> UIImage{
        
        let image = CIImage(cgImage: originalImage.cgImage!)
        if let filter = CIFilter(name: "CIColorInvert") {
            filter.setDefaults()
            filter.setValue(image, forKey: kCIInputImageKey)
            
            let context = CIContext(options: nil)
            let imageRef = context.createCGImage(filter.outputImage!, from: image.extent)
            print("Inverted done")
            return UIImage(cgImage: imageRef!)
        }
        
        return originalImage
        
    }
    
    
    
    func maskImage(image:UIImage, mask:(UIImage))->UIImage{
        
        let str = CFAbsoluteTimeGetCurrent()
        
        // Inverter
        // let maskm = invert(originalImage: mask)
        
        
        
        
        let imageReference = image.cgImage
        let maskReference = mask.cgImage
        
        let imageMask = CGImage(maskWidth: maskReference!.width,
                                height: maskReference!.height,
                                bitsPerComponent: maskReference!.bitsPerComponent,
                                bitsPerPixel: maskReference!.bitsPerPixel,
                                bytesPerRow: maskReference!.bytesPerRow,
                                provider: maskReference!.dataProvider!, decode: nil, shouldInterpolate: true)
        
        // let maskedReference = CGImageCreateWithMask(imageReference!, imageMask!)
        
        let maskedReference = imageReference?.masking(imageMask!)
        
        let maskedImage = UIImage(cgImage:maskedReference!)
        let end = CFAbsoluteTimeGetCurrent()
        // print("Masking Time \((end-str)*100))")
        return maskedImage
    }
    
    
    
}
extension UIImage {
    
    func resize(size: CGSize!) -> UIImage? {
        let rect = CGRect(x: 0.0, y: 0.0, width: size.width, height: size.height)
        UIGraphicsBeginImageContext(rect.size)
        self.draw(in:rect)
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return img
    }
    
    static func imageByMergingImages(topImage: UIImage, bottomImage: UIImage, scaleForTop: CGFloat = 1.0) -> UIImage {
        let size = bottomImage.size
        let container = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        UIGraphicsBeginImageContextWithOptions(size, false, 2.0)
        UIGraphicsGetCurrentContext()!.interpolationQuality = .high
        bottomImage.draw(in: container)
        
        let topWidth = size.width / scaleForTop
        let topHeight = size.height / scaleForTop
        let topX = (size.width / 2.0) - (topWidth / 2.0)
        let topY = (size.height / 2.0) - (topHeight / 2.0)
        
        topImage.draw(in: CGRect(x: topX, y: topY, width: topWidth, height: topHeight), blendMode: .normal, alpha: 1.0)
        let output = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return output
    }
    
}

extension HairSegmentController{
 
    
    
}
