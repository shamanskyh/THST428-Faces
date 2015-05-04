//
//  ViewController.swift
//  ProjectionFaces
//
//  Created by Harry Shamansky on 4/19/15.
//  Copyright (c) 2015 Harry Shamansky. All rights reserved.
//

import UIKit
import AVFoundation
import CoreVideo
import CoreGraphics

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    var captureSession = AVCaptureSession()
    var captureDevice: AVCaptureDevice?
    var captureInput: AVCaptureDeviceInput?
    var captureOutput: AVCaptureVideoDataOutput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    var faceDetector: CIDetector?
    
    var emojiImage: UIImage?
    
    var features: [CIFeature]?
    var videoBox: CGRect?
    var faceViews: [UIView] = []
    
    var timer: NSTimer?
    let refreshRate = 0.05
    
    
    @IBOutlet weak var previewView: UIView!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = AVCaptureSessionPresetHigh
        
        captureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        
        captureOutput?.videoSettings
        
        var err1: NSError?
        captureInput = AVCaptureDeviceInput(device: captureDevice!, error: &err1)
        
        captureSession.addInput(captureInput)
        
        captureOutput = AVCaptureVideoDataOutput()
        captureOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey : kCVPixelFormatType_32BGRA]
        captureOutput?.connectionWithMediaType(AVMediaTypeVideo)?.enabled = true
        let videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL)
        captureOutput?.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        captureOutput?.alwaysDiscardsLateVideoFrames = true
        
        
        
        captureSession.addOutput(captureOutput)
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        let rotation = CGAffineTransformMakeRotation(CGFloat(-M_PI_2))
        previewLayer?.setAffineTransform(rotation)
        
        // flip the view so it's like a mirror
        let flip1 = CGAffineTransformMakeTranslation(previewLayer!.frame.width, 0)
        let flip2 = CGAffineTransformMakeScale(-1, 1)
        let concat = CGAffineTransformConcat(flip1, flip2)
        self.view.layer.setAffineTransform(concat)
        
        previewView.layer.addSublayer(previewLayer)
        previewLayer?.frame = self.view.layer.frame
        
        captureSession.startRunning()
        
        faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy : CIDetectorAccuracyLow, CIDetectorTracking : true])
        
        emojiImage = UIImage(named: "emoji")
        
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        
        // set up a timer that updates the faces
        timer = NSTimer.scheduledTimerWithTimeInterval(refreshRate, target: self, selector: Selector("timerFired:"), userInfo: nil, repeats: true)

    }
    
    func timerFired(sender: AnyObject!) {
        if let vBox = videoBox, fs = features {
            dispatch_async(dispatch_get_main_queue()) {
                self.drawFeatures(fs, forVideoBox: vBox)
            }
        }
        
    }
    
    
    
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let dict = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, CMAttachmentMode(kCMAttachmentMode_ShouldPropagate)).takeRetainedValue() as [NSObject : AnyObject]
        let image = CIImage(CVPixelBuffer: imageBuffer, options: dict)
        
        features = faceDetector?.featuresInImage(image) as! [CIFeature]?
        
        let fDesc = CMSampleBufferGetFormatDescription(sampleBuffer) as CMVideoFormatDescription
        videoBox = CMVideoFormatDescriptionGetCleanAperture(fDesc, 0)
        
    }
    
    // code adapted from http://www.icapps.com/face-detection-with-core-image-on-live-video/
    func drawFeatures(features: [CIFeature]?, forVideoBox videoBox: CGRect) {
        
        // if no face detected, clear the views and quit
        if features?.count == 0 {
            for view in self.view.subviews {
                if view !== self.previewView {
                    view.removeFromSuperview()
                }
            }
            self.faceViews = []
            return
        }
        
        var newFaces: [UIView] = []
        
        // loop through features
        if let feats = features {
            for feature in feats {
                if let faceFeature = feature as? CIFaceFeature {
                    var faceRect = faceFeature.bounds
                    let faceAngle = faceFeature.faceAngle
                    
                    
                    // scale coordinates so they fit in the preview box, which may be scaled
                    let widthScaleBy = self.previewView.frame.width / videoBox.size.width
                    let heightScaleBy = self.previewView.frame.height / videoBox.size.height
                    faceRect.size.width *= widthScaleBy
                    faceRect.size.height *= heightScaleBy
                    faceRect.origin.x *= widthScaleBy
                    faceRect.origin.y = (self.view.frame.height) - (faceRect.origin.y * heightScaleBy) - faceRect.size.height
                    
                    // make the face rect slightly larger
                    faceRect.origin.x -= (((faceRect.size.width * 1.5) - faceRect.size.width) / 2)
                    faceRect.origin.y -= (((faceRect.size.height * 1.5) - faceRect.size.height) / 2)
                    faceRect.size.width *= 1.5
                    faceRect.size.height *= 1.5
                    
                    
                    let emojiLabel = UILabel()
                    emojiLabel.tag = Int(faceFeature.trackingID)
                    emojiLabel.numberOfLines = 1
                    emojiLabel.adjustsFontSizeToFitWidth = true
                    emojiLabel.font = UIFont.systemFontOfSize(1000)
                    emojiLabel.baselineAdjustment = UIBaselineAdjustment.AlignCenters
                    emojiLabel.frame = faceRect
                    emojiLabel.transform = CGAffineTransformMakeRotation((CGFloat(M_PI) / CGFloat(180)) * CGFloat(faceAngle))
                    
                    newFaces.append(emojiLabel)
                }
            }
        }
        
        drawFaces(newFaces)
    }
    
    func drawFaces(faces: [UIView]) {
        
        // 1: update existing faces
        var tempFaces: [(Int, UIView)] = []
        for faceView in faceViews {
            
            var found = false
            for newFaceView in faces {
                if newFaceView.tag == faceView.tag {
                    // face existed previously -- grab the old view and animate its movement onscreen
                    UIView.beginAnimations(nil, context: nil)
                    UIView.setAnimationDuration(refreshRate)
                    faceView.frame = newFaceView.frame
                    faceView.transform = newFaceView.transform
                    UIView.commitAnimations()
                    found = true
                    break
                }
            }
            
            // get rid of the old face if it doesn't exist in the new faces
            if !found {
                let mutableFaceArray = NSMutableArray(array: faceViews)
                mutableFaceArray.removeObject(faceView)
                faceViews = NSArray(array: mutableFaceArray) as! [UIView]
                
                for view in self.view.subviews {
                    if let v = view as? UIView {
                        if v === faceView {
                            UIView.beginAnimations(nil, context: nil)
                            UIView.setAnimationDuration(1.0)
                            faceView.alpha = 0
                            UIView.commitAnimations()
                            delay(refreshRate, {
                                v.removeFromSuperview()
                            })
                        }
                    }
                }
            }
        }
        
        // 2: add new faces
        for faceView in faces {
            var found = false
            for oldFaceView in faceViews {
                if oldFaceView.tag == faceView.tag {
                    found = true
                    break
                }
            }
            if !found {
                (faceView as! UILabel).text = getRandomEmoji()
                faceView.alpha = 0
                faceViews.append(faceView)
                self.view.addSubview(faceView)
                UIView.beginAnimations(nil, context: nil)
                UIView.setAnimationDuration(1.0)
                faceView.alpha = 1
                UIView.commitAnimations()
                
            }
        }
        
    }
    
    func getRandomEmoji() -> String {
        let emojiString = "😀😁😂😃😄😅😆😇😈👿😉😊☺️😋😌😍😎😏😐😑😒😓😔😕😖😗😘😙😚😛😜😝😞😠😡😢😣😤😥😦😧😨😩😪😫😬😭😮😯😰😱😲😳😴😵😶😷"
        
        let lower: UInt32 = 0
        let upper: UInt32 = UInt32(count(emojiString))
        let randomNumber = arc4random_uniform(upper - lower) + lower
        
        return emojiString.substringWithRange(Range<String.Index>(start: advance(emojiString.startIndex, Int(randomNumber)), end: advance(emojiString.startIndex, Int(randomNumber + 1))))
    }
    
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    
}


func delay(delay:Double, closure:()->()) {
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            Int64(delay * Double(NSEC_PER_SEC))
        ),
        dispatch_get_main_queue(), closure)
}


