import Foundation
import UIKit

protocol SegmentationDelegate {
    
    func segment(image: UIImage);
}

protocol NexFrameDelegate {
    func updateFrame(image: UIImage)
    func pick()
}
