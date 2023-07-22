//
//  AppDelegate.swift
//  Quick Camera
//
//  Created by Simon Guest on 1/22/2017.
//  Created by Adam Strzelecki on 7/25/2023.
//  Copyright © 2013-2021 Simon Guest. All rights reserved.
//  Copyright © 2023 Adam Strzelecki. All rights reserved.
//

import Cocoa
import AVKit
import AVFoundation

@NSApplicationMain
class QCAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var selectSourceMenu: NSMenuItem!
    @IBOutlet weak var playerView: NSView!

    var isMirrored: Bool = false
    var isUpsideDown: Bool = false

    // 0 = normal, 1 = 90' top to right, 2 = 180' top to bottom, 3 = 270' top to left
    var position = 0

    var isBorderless: Bool = false
    var isAspectRatioFixed: Bool = true
    var defaultBorderStyle: NSWindow.StyleMask = NSWindow.StyleMask.closable
    let defaultVideoDeviceName: Int = 0
    var selectedVideoDeviceName: Int = 0

    var captureSession: AVCaptureSession!
    var videoDeviceInput: AVCaptureDeviceInput!
    var audioDeviceInput: AVCaptureDeviceInput!
    var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer!
    var videoConnection: AVCaptureConnection!
    var videoOutQueue: DispatchQueue!

    let audioEngine = AVAudioEngine()
    let audioPlayer = AVAudioPlayerNode()

    func errorMessage(message: String){
        let popup = NSAlert()
        popup.messageText = message
        popup.runModal()
    }

    func startCapture() {
        do {
            if captureSession != nil {
                captureSession.stopRunning()
            }
            captureSession = AVCaptureSession()
            captureSession.sessionPreset = .high
            guard let videoDevice = AVCaptureDevice.default(for: .video) else {
                window.title = "No video device"
                return
            }
            for format in videoDevice.formats {
                let maxDuration = 1.0 / 59.0
                if format.formatDescription.frameDuration.seconds < maxDuration {
                    try videoDevice.lockForConfiguration()
                    let frameDuration = CMTimeMake(value: 1, timescale: 60)
                    videoDevice.activeVideoMinFrameDuration = frameDuration
                    videoDevice.activeVideoMaxFrameDuration = frameDuration
                    videoDevice.unlockForConfiguration()
                    break
                }
            }
            let formatDescription = videoDevice.activeFormat.formatDescription
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
                let audioDataOutput = AVCaptureAudioDataOutput()
                audioDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.nanoant.QuickCamera.audio"))
                let audioOutputFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
                audioDataOutput.audioSettings = audioOutputFormat.settings
                audioEngine.attach(audioPlayer)
                audioEngine.connect(audioPlayer, to: audioEngine.mainMixerNode, format: audioOutputFormat)
                try audioEngine.start()
                captureSession.addInput(audioDeviceInput)
                captureSession.addOutput(audioDataOutput)
                NSLog("Starting capture with video '%@' and audio '%@' devices", videoDevice.localizedName, audioDevice.localizedName)
                window.title = String(format: "%@:%@ %dx%d", videoDevice.localizedName, audioDevice.localizedName, formatDescription.dimensions.width, formatDescription.dimensions.height)
            } else {
                NSLog("Starting capture with video '%@' device only", videoDevice.localizedName)
                window.title = String(format: "%@ (only) %dx%d", videoDevice.localizedName, formatDescription.dimensions.width, formatDescription.dimensions.height)
            }
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            captureSession.addInput(videoDeviceInput)
            let videoDataOutput = AVCaptureVideoDataOutput()
            //videoDataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_32BGRA as UInt32)]
            videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.nanoant.QuickCamera.video"))
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            captureSession.addOutput(videoDataOutput)
            videoConnection = videoDataOutput.connection(with: .video)

            sampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
            sampleBufferDisplayLayer.magnificationFilter = CALayerContentsFilter.nearest
            sampleBufferDisplayLayer.minificationFilter = CALayerContentsFilter.nearest
            sampleBufferDisplayLayer.rasterizationScale = 1
            sampleBufferDisplayLayer.shouldRasterize = false
            playerView.layer = sampleBufferDisplayLayer
            playerView.layer?.backgroundColor = CGColor.black

            captureSession.startRunning()
            let height = videoDeviceInput.device.activeFormat.formatDescription.dimensions.height
            let width = videoDeviceInput.device.activeFormat.formatDescription.dimensions.width
            window.setContentSize(NSMakeSize(CGFloat(width) / 2, CGFloat(height) / 2))

            fixAspectRatio()
        } catch {
            NSLog("Error while opening device")
            errorMessage(message: "Unfortunately, there was an error when trying to access the camera. Try again or select a different one.")
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output is AVCaptureVideoDataOutput {
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true)! as NSArray
            let dict = attachments[0] as! NSMutableDictionary
            dict.setValue(kCFBooleanTrue as AnyObject, forKey: kCMSampleAttachmentKey_DisplayImmediately as NSString as String)
            sampleBufferDisplayLayer.enqueue(sampleBuffer)
        }
        if output is AVCaptureAudioDataOutput {
            if let pcmBuffer = createPCMBuffer(from: sampleBuffer) {
                audioPlayer.scheduleBuffer(pcmBuffer, completionHandler: nil)
                if !audioPlayer.isPlaying {
                    audioPlayer.play()
                }
            }
        }
    }

    private func createPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        let descr = CMSampleBufferGetFormatDescription(sampleBuffer)
        let format = AVAudioFormat(cmAudioFormatDescription: descr!)
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        let frameCapacity = AVAudioFrameCount(UInt(numSamples))
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)
        pcmBuffer?.frameLength = AVAudioFrameCount(UInt(numSamples))
        if let mutableAudioBufferList = pcmBuffer?.mutableAudioBufferList {
            CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(numSamples), into: mutableAudioBufferList)
        }
        return pcmBuffer
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        sampleBufferDisplayLayer.shouldRasterize = true
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        sampleBufferDisplayLayer.shouldRasterize = false
    }

    @IBAction func mirrorHorizontally(_ sender: NSMenuItem) {
        NSLog("Mirror image menu item selected")
        isMirrored = !isMirrored
        videoConnection.isVideoMirrored = isMirrored
    }

    func setRotation(_ position: Int) {
        switch position {
        case 0:
            videoConnection.videoOrientation = isUpsideDown ? AVCaptureVideoOrientation.portraitUpsideDown : AVCaptureVideoOrientation.portrait
            break
        case 1:
            videoConnection.videoOrientation = isUpsideDown ? AVCaptureVideoOrientation.landscapeRight : AVCaptureVideoOrientation.landscapeLeft
            break
        case 2:
            videoConnection.videoOrientation = isUpsideDown ? AVCaptureVideoOrientation.portrait : AVCaptureVideoOrientation.portraitUpsideDown
            break
        case 3:
            videoConnection.videoOrientation = isUpsideDown ? AVCaptureVideoOrientation.landscapeLeft : AVCaptureVideoOrientation.landscapeRight
            break
        default: break
        }
    }

    @IBAction func mirrorVertically(_ sender: NSMenuItem) {
        NSLog("Mirror image vertically menu item selected")
        isUpsideDown = !isUpsideDown
        setRotation(position)
        isMirrored = !isMirrored
        videoConnection.isVideoMirrored = isMirrored
    }

    @IBAction func rotateLeft(_ sender: NSMenuItem) {
        NSLog("Rotate Left menu item selected with position %d", position)
        position = position - 1
        if position == -1 {
            position = 3
        }
        setRotation(position)
    }

    @IBAction func rotateRight(_ sender: NSMenuItem) {
        NSLog("Rotate Right menu item selected with position %d", position)
        position = position + 1
        if position == 4 {
            position = 0
        }
        setRotation(position)
    }

    private func addBorder(){
        window.styleMask = defaultBorderStyle
        window.level = convertToNSWindowLevel(Int(CGWindowLevelForKey(.normalWindow)))
        window.isMovableByWindowBackground = false
    }

    private func removeBorder() {
        defaultBorderStyle = window.styleMask
        window.styleMask = [NSWindow.StyleMask.borderless, NSWindow.StyleMask.resizable]
        window.level = convertToNSWindowLevel(Int(CGWindowLevelForKey(.maximumWindow)))
        window.isMovableByWindowBackground = true
    }

    @IBAction func borderless(_ sender: NSMenuItem) {
        NSLog("Borderless menu item selected")
        if window.styleMask.contains(.fullScreen) {
            NSLog("Ignoring borderless command as window is full screen")
            return
        }
        isBorderless = !isBorderless
        sender.state = convertToNSControlStateValue((isBorderless ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
        if isBorderless {
            removeBorder()
        } else {
            addBorder()
        }
        fixAspectRatio()
    }

    @IBAction func enterFullScreen(_ sender: NSMenuItem) {
        NSLog("Enter full screen menu item selected")
        playerView.window?.toggleFullScreen(self)
    }

    @IBAction func toggleFixAspectRatio(_ sender: NSMenuItem) {
        isAspectRatioFixed = !isAspectRatioFixed
        sender.state = convertToNSControlStateValue((isAspectRatioFixed ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
        fixAspectRatio()
    }

    func fixAspectRatio() {
        if isAspectRatioFixed, #available(OSX 10.15, *) {
            let height = videoDeviceInput.device.activeFormat.formatDescription.dimensions.height
            let width = videoDeviceInput.device.activeFormat.formatDescription.dimensions.width
            let size = NSMakeSize(CGFloat(width), CGFloat(height))
            window.contentAspectRatio = size

            let ratio = CGFloat(Float(width) / Float(height))

            var currentSize = window.contentLayoutRect.size
            currentSize.height = currentSize.width / ratio
            window.setContentSize(currentSize)
        } else {
            window.contentResizeIncrements = NSMakeSize(1.0, 1.0)
        }
    }


    @IBAction func saveImage(_ sender: NSMenuItem) {
        if window.styleMask.contains(.fullScreen) {
            NSLog("Save is not supported as window is full screen")
            return
        }

        if captureSession != nil {
            if #available(OSX 10.12, *) {
                // turn borderless on, capture image, return border to previous state
                let borderlessState = isBorderless
                if borderlessState == false {
                    NSLog("Removing border")
                    removeBorder()
                }

                /* Pause the RunLoop for 0.1 sec to let the window repaint after removing the border - I'm not a fan of this approach
                 but can't find another way to listen to an event for the window being updated. PRs welcome :) */
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))

                let cgImage = CGWindowListCreateImage(CGRect.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution])

                if borderlessState == false {
                    addBorder()
                }

                DispatchQueue.main.async {
                    let now = Date()
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    let date = dateFormatter.string(from: now)
                    dateFormatter.dateFormat = "h.mm.ss a"
                    let time = dateFormatter.string(from: now)

                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = String(format: "Quick Camera Image %@ at %@.png", date, time)
                    panel.beginSheetModal(for: self.window) { (result) in
                        if result == NSApplication.ModalResponse.OK {
                            NSLog(panel.url!.absoluteString)
                            let destination = CGImageDestinationCreateWithURL(panel.url! as CFURL, kUTTypePNG, 1, nil)
                            if destination == nil {
                                NSLog("Could not write file - destination returned from CGImageDestinationCreateWithURL was nil")
                                self.errorMessage(message: "Unfortunately, the image could not be saved to this location.")
                            } else {
                                CGImageDestinationAddImage(destination!, cgImage!, nil)
                                CGImageDestinationFinalize(destination!)
                            }
                        }
                    }
                }
            } else {
                let popup = NSAlert()
                popup.messageText = "Unfortunately, saving images is only supported in Mac OSX 10.12 (Sierra) and higher."
                popup.runModal()
            }
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window.delegate = self
        startCapture()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToNSControlStateValue(_ input: Int) -> NSControl.StateValue {
    NSControl.StateValue(rawValue: input)
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToNSWindowLevel(_ input: Int) -> NSWindow.Level {
    NSWindow.Level(rawValue: input)
}
