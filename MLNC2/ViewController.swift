//
//  ViewController.swift
//  MLNC2
//
//  Created by Youssef Donadeo on 12/03/2019.
//  Copyright © 2019 YoussefDonadeo. All rights reserved.
//
import CoreML
import UIKit
import Vision
import AVKit
import AVFoundation

class ViewController: UIViewController,UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    @IBOutlet weak var imageSet: UIImageView!
    
    var position : AVCaptureDevice.Position = .back
    var Model : VNCoreMLModel!
    var captureSession : AVCaptureSession!
    var previewLayer : AVCaptureVideoPreviewLayer!
    
    //    pick an image from library
    @IBAction func pickImage(_ sender: Any) {
        flipCamera()
        configureCamera(CaptureDevice: getDevice(Position: position)!)
        
    }
    
    @IBAction func imagePicker(_ sender: Any) {
        let imagePick = UIImagePickerController()
        imagePick.delegate = self
        imagePick.allowsEditing = false
        imagePick.sourceType = .photoLibrary
        present(imagePick, animated: true, completion: nil)
    }
    
    @IBOutlet weak var descriptionLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        /* Get the capture Device( Camera )
         and configure the Camera ( Frame layout, Session, input buffer, ecc.. )
         */
        guard let captureDevice = getDevice(Position: position) else { return }
        
        configureCamera(CaptureDevice: captureDevice)
        
        /* Initialise Core ML model
         We create a model container to be used with VNCoreMLRequest based on our HandSigns Core ML model.
         */
        Model = try? VNCoreMLModel(for: YCTSL().model)
    }
    
    
    /* Set picker controller and set image frame
     after the selection of image
     */
    @objc func imagePickerController(_ picker: UIImagePickerController,didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
        let pickedImage = info[.originalImage]  as! UIImage
        imageSet.image = pickedImage
        imageSet.contentMode = .scaleAspectFit
        
        //resize image
        UIGraphicsBeginImageContextWithOptions (CGSize(width: 277,height: 277), true, 2.0)
        pickedImage.draw(in: CGRect(x: 0, y: 0, width: 277,
                                    height: 277))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()!
        
        UIGraphicsEndImageContext()
        
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer : CVPixelBuffer?
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(newImage.size.width), Int(newImage.size.height),
                                         kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
        guard (status == kCVReturnSuccess) else {return}
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pixelData, width:
            Int(newImage.size.width), height: Int(newImage.size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        context?.translateBy(x: 0, y: newImage.size.height)
        context?.scaleBy(x: 1.0, y: -1.0)
        UIGraphicsPushContext(context!)
        newImage.draw(in: CGRect(x: 0, y: 0, width: newImage.size.width, height: newImage.size.height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        visionHendler(PixelBuffer: pixelBuffer!)
        
    }
    
    func imagePickerControllerDidCancel(_ picker:
        UIImagePickerController) {
        self.dismiss(animated: true, completion: nil)
    }
    
    
    
    
}

/* Extention of View Controller that handle
 the capure device
 */
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    enum ModelType: String {
        case Youssef = "Youssef"
        case Carmine = "Carmine"
        case Tavoli = "Tavoli"
        case Ludos = "Ludos"
        case sedie = "sedie"
    }
    
    
    
    
    
    func configureCamera(CaptureDevice: AVCaptureDevice ) {
        
        //Start capture session
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo
        captureSession.startRunning()
        
        // Add input for capture
        //guard let captureDevice = AVCaptureDevice.default(for: .video) else { return }
        guard let captureInput = try? AVCaptureDeviceInput(device: CaptureDevice) else { return }
        captureSession.addInput(captureInput)
        
        // Add preview layer to our view to display the open camera screen
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        view.layer.addSublayer(previewLayer)
        previewLayer.frame = view.frame
        
        // Add output of capture
        /* Here we set the sample buffer delegate to our viewcontroller whose callback
         will be on a queue named - videoQueue */
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(dataOutput)
    }
    
    
    /* This delegate is fired periodically every time a new video frame is written.
     It is called on the dispatch queue specified while setting up the capture session.
     */
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        /* Initialise CVPixelBuffer from sample buffer
         CVPixelBuffer is the input type we will feed our coremlmodel .
         */
        guard let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        visionHendler(PixelBuffer: pixelBuffer)
    }
    
    
    /* This function hendle the call to coreML model and
     use the pixelBuffer for identification
     */
    func visionHendler(PixelBuffer : CVPixelBuffer) {
        
        /* Create a Core ML Vision request
         The completion block will execute when the request finishes execution and fetches a response.
         */
        let request =  VNCoreMLRequest(model: self.Model!) { (finishedRequest, err) in
            
            /* Dealing with the result of the Core ML Vision request
             The request's result is an array of VNClassificationObservation object which holds
             identifier - The prediction tag we had defined in our Custom Vision model - Youssef, Carmine, Tavoli, sedie
             confidence - The confidence on the prediction made by the model on a scale of 0 to 1
             */
            guard let results = finishedRequest.results as? [VNClassificationObservation] else { return }
            
            /* Results array holds predictions iwth decreasing level of confidence.
             Thus we choose the first one with highest confidence. */
            guard let firstResult = results.first else { return }
            
            var predictionString = ""
            
            /* Depending on the identifier we set the UILabel text with it's confidence.
             We update UI on the main queue. */
            DispatchQueue.main.async {
                switch firstResult.identifier {
                case ModelType.Youssef.rawValue :
                    predictionString = "Youssef👊🏽"
                case ModelType.Carmine.rawValue :
                    predictionString = "Carmine✌🏽"
                case ModelType.Tavoli.rawValue :
                    predictionString = "Tavoli🖐🏽"
                case ModelType.sedie.rawValue :
                    predictionString = "sedie❎"
                case ModelType.Ludos.rawValue :
                    predictionString = "Ludos🌈"
                default:
                    break
                }
                
                self.descriptionLabel.text = predictionString + "(\(firstResult.confidence))"
            }
        }
        
        /* Perform the above request using Vision Image Request Handler
         We input our CVPixelbuffer to this handler along with the request declared above.
         */
        try? VNImageRequestHandler(cvPixelBuffer: PixelBuffer, options: [:]).perform([request])
    }
    
    /* Search the Capture Device(Camera)
     and return the selected device position
     */
    
    func getDevice(Position: AVCaptureDevice.Position) -> AVCaptureDevice? {

        let devices: NSArray = AVCaptureDevice.devices() as NSArray;
        for de in devices {
            let deviceConverted = de as! AVCaptureDevice
            if(deviceConverted.position == position){
                return deviceConverted
            }
        }
        return nil
    }
    
    /* Change the position of
     Capture Device
     */
    func flipCamera() {
        if (self.position == .back) {
            self.position = .front
        }else{
            self.position = .back
        }
    }
    
    /* Stop Camera session
     and remove Camera layer
     */
    func stopSession() {
        if captureSession.isRunning {
            DispatchQueue.global().async {
                self.previewLayer.removeFromSuperlayer()
                self.captureSession.stopRunning()
            }
        }
    }
}

extension ViewController : UITabBarControllerDelegate {
    
    
}

