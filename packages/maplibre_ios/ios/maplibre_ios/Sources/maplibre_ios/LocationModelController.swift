import GLTFSceneKit
import SceneKit
import UIKit

final class LocationModelController {
    private let containerView: UIView
    private let sceneView: SCNView
    private var modelNode: SCNNode?
    private let modelSize: CGFloat = 96

    init(parent: UIView, modelURL: URL, scale: Float) {
        containerView = UIView(
            frame: CGRect(x: 0, y: 0, width: modelSize, height: modelSize)
        )
        containerView.isUserInteractionEnabled = false
        sceneView = SCNView(frame: containerView.bounds)
        sceneView.backgroundColor = .clear
        sceneView.autoenablesDefaultLighting = true
        sceneView.allowsCameraControl = false
        sceneView.isUserInteractionEnabled = false
        containerView.addSubview(sceneView)
        parent.addSubview(containerView)

        do {
            let source = try GLTFSceneSource(url: modelURL)
            let scene = try source.scene()
            sceneView.scene = scene
            modelNode = scene.rootNode.childNodes.first ?? scene.rootNode
            modelNode?.scale = SCNVector3(scale, scale, scale)

            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(0, 0, 2.5)
            scene.rootNode.addChildNode(cameraNode)
            sceneView.pointOfView = cameraNode
        } catch {
            containerView.isHidden = true
        }
    }

    func update(
        screenX: CGFloat,
        screenY: CGFloat,
        bearing: CGFloat,
        visible: Bool
    ) {
        containerView.isHidden = !visible
        guard visible else { return }
        containerView.center = CGPoint(
            x: screenX,
            y: screenY - modelSize / 2
        )
        modelNode?.eulerAngles.y = Float(bearing) * .pi / 180
    }

    func dispose() {
        containerView.removeFromSuperview()
    }
}
