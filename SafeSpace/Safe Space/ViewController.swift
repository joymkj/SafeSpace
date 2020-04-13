import UIKit
import Photos
import Fritz

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

  var previewView: UIImageView!

  lazy var poseModel = FritzVisionHumanPoseModelFast()

  lazy var poseSmoother = PoseSmoother<OneEuroPointFilter, HumanSkeleton>()

  private lazy var captureSession: AVCaptureSession = {
    let session = AVCaptureSession()

    guard
      let backCamera = AVCaptureDevice.default(
          .builtInWideAngleCamera,
        for: .video,
        position: .back),
      let input = try? AVCaptureDeviceInput(device: backCamera)
      else { return session }
    session.addInput(input)

    session.sessionPreset = .photo
    return session
  }()

  override func viewDidLoad() {
    super.viewDidLoad()

    previewView = UIImageView(frame: view.bounds)
    previewView.contentMode = .scaleAspectFill
    view.addSubview(previewView)

    let videoOutput = AVCaptureVideoDataOutput()
    videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA as UInt32]
    videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "MyQueue"))
    self.captureSession.addOutput(videoOutput)
    self.captureSession.startRunning()
  }

  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()

    previewView.frame = view.bounds
  }

  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
  }

  func displayInputImage(_ image: FritzVisionImage) {
    guard let rotated = image.rotate() else { return }

    let image = UIImage(pixelBuffer: rotated)
    DispatchQueue.main.async {
      self.previewView.image = image
    }
  }
  
    func distfunc(from: CGPoint, to: CGPoint) -> CGFloat {
        return (from.x - to.x) * (from.x - to.x) + (from.y - to.y) * (from.y - to.y)
    }
    
    func drawLineOnImage(size: CGSize, image: UIImage, from: CGPoint, to: CGPoint, strcolor: CGColor) -> UIImage {
        UIGraphicsBeginImageContext(size)
        image.draw(at: CGPoint.zero)
        guard let context = UIGraphicsGetCurrentContext() else { return UIImage() }
        context.setLineWidth(2.0)
        context.setStrokeColor(strcolor)
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()

        guard let resultImage = UIGraphicsGetImageFromCurrentImageContext() else { return UIImage() }
        UIGraphicsEndImageContext()
        return resultImage
    }

  var minPoseThreshold: Double { return 0.3 }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

    let image = FritzVisionImage(sampleBuffer: sampleBuffer, connection: connection)
    let options = FritzVisionPoseModelOptions()
    options.minPoseThreshold = minPoseThreshold

    guard let result = try? poseModel.predict(image, options: options) else {
      displayInputImage(image)
      return
    }

    let poses = result.poses()
    let nose: [HumanSkeleton] = [.nose]
    let hip: [HumanSkeleton] = [.leftHip]


    

//    pose = poseSmoother.smoothe(pose)

    guard var poseResult = image.draw(poses: poses) else {
      displayInputImage(image)
      return
    }
    
    var p1 = CGPoint(x: 0,y: 0), p2 = CGPoint(x: 0,y: 0), p3 = CGPoint(x: 0,y: 0), p4 = CGPoint(x: 0,y: 0)
    var dist: CGFloat = 0.0
    var linecolor = UIColor.blue.cgColor
    var closepeople = 0
    
    if poses.count>1 {
        
        for keypoint in poses[0].keypoints {
            if nose.contains(keypoint.part) {
                p3 = keypoint.position
            }
            if hip.contains(keypoint.part) {
                p4 = keypoint.position
            }
            dist = distfunc(from: p3,to: p4)
        }
        
        
        for i in 0...poses.count-2 {
            for j in i+1...poses.count-1{
                for keypoint in poses[i].keypoints {
                    if nose.contains(keypoint.part) {
                        print("Person \(i) : \(keypoint.position)")
                        p1 = keypoint.position
                    }
                }
                for keypoint in poses[j].keypoints {
                    if nose.contains(keypoint.part) {
                        print("Person2 \(j) : \(keypoint.position)")
                        p2 = keypoint.position
                    }
                }
                
                if p1 != CGPoint(x: 0,y: 0) && p2 != CGPoint(x: 0,y: 0){
                    print(dist , distfunc(from: p1,to: p2))
                    if distfunc(from: p1,to: p2)>10*dist{
                        linecolor = UIColor.green.cgColor
                    }
                    else {
                        linecolor = UIColor.blue.cgColor
                        closepeople = closepeople+1
                    }
                    poseResult = drawLineOnImage(size: poseResult.size, image: poseResult, from: p1*poseResult.size, to: p2*poseResult.size, strcolor: linecolor)
                }
            }
        }
    }
    
    func textToImage(drawText text: NSString, inImage image: UIImage, line_no: CGFloat) -> UIImage {
        UIGraphicsBeginImageContext(image.size)
        image.draw(in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))

        let font=UIFont(name: "Helvetica-Bold", size: 32)!
        let text_style=NSMutableParagraphStyle()
        text_style.alignment=NSTextAlignment.center
        let attributes=[NSAttributedString.Key.font:font, NSAttributedString.Key.paragraphStyle:text_style, NSAttributedString.Key.foregroundColor:UIColor.white,
            NSAttributedString.Key.backgroundColor: UIColor.black,
            ] as [NSAttributedString.Key : Any]

        let text_h=font.lineHeight
        let text_y=(image.size.height-text_h)/1.5 + line_no*text_h
        let text_rect=CGRect(x: 0, y: text_y, width: image.size.width, height: text_h)
        text.draw(in: text_rect.integral, withAttributes: attributes)
        let result=UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result!
    }
    
    poseResult = textToImage(drawText: "  Total Occupancy: "+String(poses.count)+" " as NSString, inImage: poseResult, line_no: 0)
    poseResult = textToImage(drawText: " Close proximities: "+String(closepeople)+" " as NSString, inImage: poseResult, line_no: 1)

    

    DispatchQueue.main.async {
      self.previewView.image = poseResult
    }
  }
}



