# Quick Camera

<img src="Icons/QuickCamera.iconset/icon_256x256.png" alt="Icon" style="zoom:50%;" />

## Note on Fork

This fork is intended to modify/augment original Simon’s code to provide minimal latency on both video and audio when streaming capture devices:

1. Uses `AVSampleBufferDisplayLayer` and `AVAudioEngine` to display video and play audio with minimal latency.
2. Removes (temporarily?) ability to select devices.
3. Replaces original icon with more modern one.
4. Targets macOS 10.15 or higher.

## Original Description

Quick Camera is a MacOS utility that displays the output from any of your web cameras on your desktop. Quick Camera can be used for video conferences and presentations where you need to show an external device to your audience via the USB camera. 

Quick Camera supports mirroring (normal and reversed, both vertical and horizontal), can be rotated, resized to any size, and the window can be placed in the foreground.

You can find the app on the Mac App Store: https://itunes.apple.com/us/app/qcamera/id598853070?mt=12

License
-------
Copyright 2013-2023 Simon Guest

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.

You may obtain a copy of the License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the License for the specific language governing permissions and limitations under the License.
