"""RTSP client for capturing frames from DVR cameras."""
import cv2
import numpy as np
from typing import Optional, Tuple
from pathlib import Path
import os


class RTSPClient:
    """Client for connecting to RTSP streams and capturing frames."""

    def __init__(self, rtsp_url: str):
        """Initialize RTSP client.

        Args:
            rtsp_url: Full RTSP URL (e.g., rtsp://user:pass@host:port/live)
        """
        self.rtsp_url = rtsp_url
        self.cap: Optional[cv2.VideoCapture] = None
        self.is_connected = False

    def connect(self, timeout: int = 10) -> bool:
        """Connect to RTSP stream.

        Args:
            timeout: Connection timeout in seconds

        Returns:
            True if connection successful, False otherwise
        """
        # Try TCP first (more reliable), then UDP if TCP fails
        protocols = ['tcp', 'udp']

        for protocol in protocols:
            try:
                print(f"Trying RTSP with {protocol.upper()} protocol...")

                # Set FFmpeg environment variables
                os.environ["OPENCV_FFMPEG_CAPTURE_OPTIONS"] = f"rtsp_transport;{protocol}|rtsp_flags;prefer_tcp"

                # Use FFMPEG backend explicitly for better HEVC support
                self.cap = cv2.VideoCapture(self.rtsp_url, cv2.CAP_FFMPEG)

                # Quality and performance settings
                self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)  # Reduce buffer for faster connection

                # Set timeout (in milliseconds)
                self.cap.set(cv2.CAP_PROP_OPEN_TIMEOUT_MSEC, timeout * 1000)
                self.cap.set(cv2.CAP_PROP_READ_TIMEOUT_MSEC, timeout * 1000)

                if self.cap.isOpened():
                    print(f"  Stream opened with {protocol.upper()}, testing frame read...")
                    # Test read a frame
                    ret, frame = self.cap.read()
                    if ret and frame is not None:
                        print(f"✅ Connected successfully via {protocol.upper()}")
                        self.is_connected = True
                        return True
                    else:
                        print(f"  Failed to read frame with {protocol.upper()}")
                        self.cap.release()
                        self.cap = None
                else:
                    print(f"  Failed to open stream with {protocol.upper()}")

            except Exception as e:
                print(f"RTSP connection error with {protocol.upper()}: {e}")
                if self.cap is not None:
                    self.cap.release()
                    self.cap = None

        print("❌ All connection attempts failed")
        return False

    def capture_frame(self) -> Optional[np.ndarray]:
        """Capture a single frame from the stream.

        Returns:
            Frame as numpy array (BGR format) or None if failed
        """
        if not self.is_connected or self.cap is None:
            print("Not connected to RTSP stream")
            return None

        try:
            ret, frame = self.cap.read()
            if ret:
                return frame
            else:
                print("Failed to read frame")
                return None

        except Exception as e:
            print(f"Frame capture error: {e}")
            return None

    def save_snapshot(self, output_path: Path, quality: int = 95) -> bool:
        """Capture and save a snapshot.

        Args:
            output_path: Path to save the snapshot
            quality: JPEG quality (0-100, default: 95 for high quality)

        Returns:
            True if successful, False otherwise
        """
        frame = self.capture_frame()
        if frame is not None:
            try:
                # Save with high quality
                if str(output_path).lower().endswith('.jpg') or str(output_path).lower().endswith('.jpeg'):
                    cv2.imwrite(str(output_path), frame, [cv2.IMWRITE_JPEG_QUALITY, quality])
                elif str(output_path).lower().endswith('.png'):
                    cv2.imwrite(str(output_path), frame, [cv2.IMWRITE_PNG_COMPRESSION, 1])
                else:
                    cv2.imwrite(str(output_path), frame)
                return True
            except Exception as e:
                print(f"Failed to save snapshot: {e}")
                return False
        return False

    def get_stream_info(self) -> Optional[dict]:
        """Get stream information (resolution, FPS, etc.).

        Returns:
            Dictionary with stream properties or None if not connected
        """
        if not self.is_connected or self.cap is None:
            return None

        return {
            "width": int(self.cap.get(cv2.CAP_PROP_FRAME_WIDTH)),
            "height": int(self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT)),
            "fps": self.cap.get(cv2.CAP_PROP_FPS),
            "codec": int(self.cap.get(cv2.CAP_PROP_FOURCC)),
        }

    def disconnect(self):
        """Disconnect from RTSP stream and release resources."""
        if self.cap is not None:
            self.cap.release()
            self.cap = None
        self.is_connected = False

    def __enter__(self):
        """Context manager entry."""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.disconnect()
